import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// `.redirect` is the only install source that makes its own request, and the
/// app's periodic check used to make it on EVERY round — for an answer nobody
/// had asked for, aimed at a vendor's *download* endpoint, which is the kind
/// that rate-limits (issues #669/#670). Issue #671: the app now hands the
/// redirect's entry url straight through and lets `Downloader` follow it at the
/// moment the user presses Update; `duo verify` still follows it every time,
/// because proving where it lands is that sweep's job
/// (`RecipeSanity.crossChannelArtifact` judges exactly that url).
///
/// So the property has two halves that pull in opposite directions — either one
/// alone is satisfied by a constant. These pin both: the app path must NOT reach
/// the endpoint and must report the ENTRY url, and the verify path must reach it
/// and report the LANDING url.
///
/// Mutations, each run once against the final tree (2026-09-16; every one
/// compiles, so none went red on a build error):
///  - drop the `guard resolvesInstallRedirects else` line from `resolveInstall`'s
///    `.redirect` case → `theAppPathDoesNotReachTheDownloadEndpoint` and
///    `aSecondEndpointOnTheSameChannelAlsoDefersIt` red on BOTH the hit count and
///    the url, `theDeferredPlanIsStillInstallable` red on the url;
///  - flip the `resolvesInstallRedirects` init default to `false` →
///    `theVerifyPathStillResolvesTheLandingURL` red on all three of its
///    assertions (it stops asking, and reports `/download`);
///  - `SourceStack.make` stops passing `resolvesInstallRedirects: false` → only
///    `theShippingStackAsksForTheDeferral` red. That it is the ONLY one red is
///    the finding: the stubbed cases build their own source, so nothing else in
///    this suite can see what the shipping stack asks for;
///  - return the bare `url` instead of `Self.preferHTTPS(url)` in that guard →
///    only `theEntryURLIsStillSchemeUpgraded` red.
///
/// ⚠️ `aSecondEndpointOnTheSameChannelAlsoDefersIt` has NO mutation of its own
/// under this design, and is kept deliberately rather than by oversight. An
/// earlier draft hung the flag on `probeOutcome`, where the two call sites inside
/// `probeDiagnostic(for:)` could disagree — dropping it from one of them left the
/// other case green, which is how that case was earned. One instance property
/// cannot disagree with itself, so today it only guards the multi-endpoint branch
/// against the flag ever moving back to the call site.
@Suite struct InstallRedirectDeferralTests {

    // MARK: - a stub that tells the two urls apart, and counts who asked

    /// Path-aware (the shared `RecipeVerificationTests.StubServer` answers every
    /// path with one body, which cannot express "the redirect landed elsewhere")
    /// and counting, because "did the app make this request at all" is half of
    /// what is pinned here and no assertion on the *result* can see it.
    final class RedirectStub: @unchecked Sendable {

        /// Separate from the stub so the connection handler can be installed
        /// before `self` exists.
        private final class Counters: @unchecked Sendable {
            private let lock = NSLock()
            private var download = 0
            private var artifact = 0
            func bumpDownload() { lock.lock(); download += 1; lock.unlock() }
            func bumpArtifact() { lock.lock(); artifact += 1; lock.unlock() }
            var downloadHits: Int { lock.lock(); defer { lock.unlock() }; return download }
            var artifactHits: Int { lock.lock(); defer { lock.unlock() }; return artifact }
        }

        static let feedBody = #"{"version":"1.2.3"}"#
        static let entryPath = "/download"
        static let landingPath = "/artifact/Subject-1.2.3.dmg"

        private let listener: NWListener
        private let counters = Counters()
        let port: UInt16

        /// How many times the redirect ENTRY was fetched. The app path leaves this
        /// at zero; that zero is the point of the change.
        var downloadHits: Int { counters.downloadHits }
        /// How many times the redirect's TARGET was fetched — non-zero only when
        /// something followed the 302.
        var artifactHits: Int { counters.artifactHits }

        init() throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = DispatchQueue(label: "InstallRedirectDeferralStub")
            let counters = self.counters

            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                // The whole request line, not "whatever the first segment held":
                // this stub branches on the PATH, so a request line split across
                // TCP segments would answer the feed body to a `/download` HEAD
                // and fail a test for a reason that is not the code under test.
                // (The shared `RecipeVerificationTests.StubServer` reads once
                // because it answers every path identically; that indifference is
                // exactly what this stub gives up.)
                Self.readRequestLine(conn) { method, path in

                    var status = 200
                    var location: String?
                    var body = ""
                    if path.hasPrefix(Self.entryPath) {
                        counters.bumpDownload()
                        status = 302
                        location = Self.landingPath
                    } else if path.hasPrefix(Self.landingPath) {
                        counters.bumpArtifact()
                    } else {
                        // Anything else is a version feed. More than one path
                        // answers so the multi-endpoint branch can be reached.
                        body = Self.feedBody
                    }

                    let payload = Data(body.utf8)
                    var header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Found")\r\n"
                    if let location { header += "Location: \(location)\r\n" }
                    header += "Content-Type: application/json\r\n"
                    header += "Content-Length: \(payload.count)\r\n"
                    header += "Connection: close\r\n\r\n"
                    // A HEAD carries the headers and none of the body — and every
                    // request the install path makes is a HEAD, so getting this
                    // wrong would hang the very case under test.
                    let out = Data(header.utf8) + (method == "HEAD" ? Data() : payload)
                    conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
                }
            }
            listener.start(queue: queue)

            var resolved: UInt16?
            for _ in 0..<500 {
                if let p = listener.port?.rawValue, p != 0 { resolved = p; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            guard let bound = resolved else { throw URLError(.cannotConnectToHost) }
            self.port = bound
        }

        /// Accumulate until the request line is complete (CRLF), then hand back
        /// its method and path.
        ///
        /// Every exit that is not "found the CRLF" has to be terminal, because
        /// re-arming is the only other option and `receive` can complete WITHOUT
        /// consuming anything: on a connection error it calls back immediately
        /// with `data == nil` and `isComplete == false`, so the buffer does not
        /// grow and neither the CRLF nor the size bound can ever be reached.
        /// Dropping that error (`{ data, _, done, _ in`) therefore spins forever
        /// rather than ending the read — and every connection here shares one
        /// serial queue, so it would burn a core for the rest of the run and look
        /// like the hang `scripts/run-with-hang-report.sh` exists to catch.
        private static func readRequestLine(
            _ conn: NWConnection, _ body: @escaping (String, String) -> Void
        ) {
            func step(_ sofar: Data) {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, done, error in
                    let buffer = sofar + (data ?? Data())
                    let text = String(decoding: buffer, as: UTF8.self)
                    guard let end = text.range(of: "\r\n") else {
                        if error != nil || done || buffer.count > 64 * 1024 {
                            return body("GET", "/")
                        }
                        return step(buffer)
                    }
                    let fields = text[text.startIndex..<end.lowerBound].split(separator: " ")
                    body(
                        fields.first.map(String.init) ?? "GET",
                        fields.count > 1 ? String(fields[1]) : "/")
                }
            }
            step(Data())
        }

        func feed(_ name: String = "feed") -> URL {
            URL(string: "http://127.0.0.1:\(port)/\(name)")!
        }
        var entryURL: URL { URL(string: "http://127.0.0.1:\(port)\(Self.entryPath)")! }
        func stop() { listener.cancel() }
    }

    // MARK: - fixtures

    private static func recipe(url: URL, entry: URL) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.subject", url: url, mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9.]+)""#,
            install: VendorInstallSpec(urlSource: .redirect(entry), kind: .dmg))
    }

    private static func app() -> InstalledApp {
        InstalledApp(
            name: "Subject", bundleID: "com.example.subject",
            shortVersion: "1.0.0", buildVersion: "1",
            // Fabricated on purpose: a real path would put `resolvingSymlinksInPath`
            // and this machine's /Applications into the equation. CLAUDE.md,
            // "测试不能问宿主「你装了什么、在跑什么」".
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Subject.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    // MARK: - the app path: no request, and the entry url

    @Test func theAppPathDoesNotReachTheDownloadEndpoint() async throws {
        let stub = try RedirectStub()
        defer { stub.stop() }
        let source = VendorProbeSource(
            recipes: [Self.recipe(url: stub.feed(), entry: stub.entryURL)],
            resolvesInstallRedirects: false)

        let outcome = try #require(await source.probeDiagnostic(for: Self.app()))

        #expect(stub.downloadHits == 0, "the periodic check must not touch the download endpoint")
        #expect(stub.artifactHits == 0, "and so must not land on the artifact either")
        // The discriminator: had the redirect been followed this would be the
        // landing path. Compared on `path` rather than the whole url, because
        // `preferHTTPS` rewrites the scheme — asserted separately below.
        #expect(try #require(outcome.remote).downloadURL?.path == RedirectStub.entryPath)
    }

    /// Deferring must not cost the row its Update button — the whole premise is
    /// that `kind` is known from the recipe without asking anyone. A version-only
    /// assertion here would pass with the install spec dropped entirely, so the
    /// kind, the routing verdict and the absence of a warning are all asserted.
    @Test func theDeferredPlanIsStillInstallable() async throws {
        let stub = try RedirectStub()
        defer { stub.stop() }
        let source = VendorProbeSource(
            recipes: [Self.recipe(url: stub.feed(), entry: stub.entryURL)],
            resolvesInstallRedirects: false)

        let outcome = try #require(await source.probeDiagnostic(for: Self.app()))
        let remote = try #require(outcome.remote)

        #expect(remote.shortVersion == "1.2.3")
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.requiresManualInstaller == false)
        #expect(remote.downloadURL?.path == RedirectStub.entryPath)
        // A deferred redirect is not a broken install spec: `installURLUnresolved`
        // here would file a working recipe as dead.
        #expect(outcome.warnings.isEmpty)
    }

    /// `probeDiagnostic(for:)` has TWO call sites into `probeOutcome` — one for a
    /// channel with a single endpoint, one for a channel with several — and a fix
    /// applied to only one of them compiles and passes the other test.
    @Test func aSecondEndpointOnTheSameChannelAlsoDefersIt() async throws {
        let stub = try RedirectStub()
        defer { stub.stop() }
        let source = VendorProbeSource(
            recipes: [
                Self.recipe(url: stub.feed("feed-a"), entry: stub.entryURL),
                Self.recipe(url: stub.feed("feed-b"), entry: stub.entryURL),
            ],
            resolvesInstallRedirects: false)

        let outcome = try #require(await source.probeDiagnostic(for: Self.app()))

        #expect(stub.downloadHits == 0, "the multi-endpoint branch defers it too")
        #expect(try #require(outcome.remote).downloadURL?.path == RedirectStub.entryPath)
    }

    /// The entry url gets the same `preferHTTPS` treatment the resolved one got,
    /// so deferring never downgrades a link. A no-op for the registry as it stands
    /// — all 27 `.redirect` entries are already https, measured 2026-09-16 — which
    /// is exactly why it needs a test rather than a reader.
    @Test func theEntryURLIsStillSchemeUpgraded() async throws {
        let stub = try RedirectStub()
        defer { stub.stop() }
        let source = VendorProbeSource(
            recipes: [Self.recipe(url: stub.feed(), entry: stub.entryURL)],
            resolvesInstallRedirects: false)

        let remote = try #require(await source.probeDiagnostic(for: Self.app())?.remote)

        #expect(stub.entryURL.scheme == "http", "the fixture must start insecure or this is vacuous")
        #expect(remote.downloadURL?.scheme == "https")
    }

    // MARK: - the construction site that decides it for the product

    /// The knob lives on the source, so what the SHIPPING stack asks for is a
    /// separate fact from what `resolveInstall` does with the answer — and it is
    /// the fact a user feels. `SourceStack.make` is the only production caller
    /// that must opt out (`duo verify` builds its own and keeps the default), so
    /// a regression there is a silent return to a request per app per round.
    ///
    /// This reads the flag rather than driving a probe: `SourceStack.make` wires
    /// the real registry to the real network, so the behavioural half is pinned
    /// by the stubbed cases above and this one pins the wiring.
    @Test func theShippingStackAsksForTheDeferral() throws {
        let stack = SourceStack.make(githubToken: nil)
        let probe = try #require(
            stack.compactMap { $0 as? VendorProbeSource }.first,
            "the vendor probe left the stack — this test no longer covers anything")
        #expect(probe.resolvesInstallRedirects == false)
    }

    // MARK: - the verify path: still follows, still lands

    /// The other half. `duo verify` reaches `probeOutcome` through
    /// `probeDiagnostic(_:checkingInstallURL:)` on a source it built itself, which
    /// leaves `resolvesInstallRedirects` at its default — and that default has to stay true,
    /// or the sweep stops being able to resolve 27 specs across 17 families and
    /// `RecipeSanity.crossChannelArtifact` starts judging an entry url as if it
    /// were the artifact: the #669 bug, re-introduced from the other end.
    @Test func theVerifyPathStillResolvesTheLandingURL() async throws {
        let stub = try RedirectStub()
        defer { stub.stop() }
        let recipe = Self.recipe(url: stub.feed(), entry: stub.entryURL)

        let outcome = await VendorProbeSource().probeDiagnostic(recipe)

        #expect(stub.downloadHits == 1, "the sweep still asks")
        #expect(stub.artifactHits == 1, "and still follows through to the artifact")
        let remote = try #require(outcome.remote)
        #expect(remote.downloadURL?.path == RedirectStub.landingPath)
        #expect(remote.vendorInstallerKind == .dmg)
    }
}
