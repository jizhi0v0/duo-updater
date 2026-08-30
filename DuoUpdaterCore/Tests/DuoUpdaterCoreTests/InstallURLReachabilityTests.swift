import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// The gap #159 closes: `resolveInstall` proves an installer URL is well-FORMED,
/// not that the vendor still serves it. For every `URLSource` but `.redirect`
/// those are different claims, and nothing anywhere noticed the difference — a
/// vendor that renames an artifact leaves the pattern matching and the version
/// reading, so the recipe grades ✓ while one-click is dead. The install-time
/// signature gates cannot cover this either: a 404 delivers no bytes for them to
/// judge, so they never run.
struct InstallURLReachabilityTests {

    // MARK: - a stub that answers per method and per path

    /// Unlike `RecipeVerificationTests.StubServer`, this one has to distinguish a
    /// HEAD from a GET, because the whole design question is what to conclude
    /// when those two disagree.
    final class MethodAwareServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "InstallURLReachabilityStub")
        let port: UInt16
        /// Guarded by `queue`; read after `stop()`.
        private var seen: [String] = []

        /// - Parameters:
        ///   - headStatus: what `/install` answers a HEAD.
        ///   - rangedGetStatus: what `/install` answers a GET carrying `Range`.
        init(
            headStatus: Int, rangedGetStatus: Int, version: String = "2.0.0",
            dropGET: Bool = false
        ) throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue
            let box = Box()
            self.box = box

            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    data, _, _, _ in
                    let request = String(decoding: data ?? Data(), as: UTF8.self)
                    let line = request.split(separator: "\r\n").first.map(String.init) ?? ""
                    let parts = line.split(separator: " ").map(String.init)
                    let method = parts.first ?? ""
                    let path = parts.count > 1 ? parts[1] : ""
                    queue.async {
                        box.seen.append("\(method) \(path)")
                        box.heads.append(request)
                    }

                    // Answer nothing and hang up: models a host that accepts the
                    // connection and then times out or resets mid-request.
                    if dropGET, method == "GET" { conn.cancel(); return }

                    let status: Int
                    var body = ""
                    if path.hasPrefix("/feed") {
                        status = 200
                        body = #"{"version":"\#(version)"}"#
                    } else if method == "HEAD" {
                        status = headStatus
                    } else {
                        status = rangedGetStatus
                    }
                    let payload = Data(body.utf8)
                    var header = "HTTP/1.1 \(status) X\r\n"
                    header += "Content-Type: application/json\r\n"
                    header += "Content-Length: \(payload.count)\r\n"
                    header += "Connection: close\r\n\r\n"
                    conn.send(
                        content: Data(header.utf8) + payload,
                        completion: .contentProcessed { _ in conn.cancel() })
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

        final class Box: @unchecked Sendable {
            var seen: [String] = []
            var heads: [String] = []
        }
        private let box: Box

        var feedURL: URL { URL(string: "http://127.0.0.1:\(port)/feed")! }
        var installURL: URL { URL(string: "http://127.0.0.1:\(port)/install")! }
        /// Every request line the server saw, e.g. `HEAD /install`. Only
        /// meaningful for plaintext requests — a TLS handshake lands here as
        /// binary, which is why `connectionCount()` exists alongside it.
        func requests() -> [String] { queue.sync { box.seen } }
        func connectionCount() -> Int { queue.sync { box.seen.count } }
        /// Full request heads, for asserting on headers.
        func heads() -> [String] { queue.sync { box.heads } }
        func stop() { listener.cancel() }
    }

    private static func recipe(_ server: MethodAwareServer) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.subject",
            url: server.feedURL,
            mode: .responseBody,
            versionPattern: #""version":"([0-9.]+)""#,
            install: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
    }

    // MARK: - what the probe concludes

    @Test func aServedURLIsOK() async throws {
        let server = try MethodAwareServer(headStatus: 200, rangedGetStatus: 206)
        defer { server.stop() }
        let result = await VendorProbeSource().installURLReachability(
            server.installURL, spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
        #expect(result == .ok)
    }

    @Test func aVendorThatDeletedTheArtifactIsGone() async throws {
        let server = try MethodAwareServer(headStatus: 404, rangedGetStatus: 404)
        defer { server.stop() }
        let result = await VendorProbeSource().installURLReachability(
            server.installURL, spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
        #expect(result == .gone(status: 404))
    }

    /// The false-accusation guard, and the reason this probe costs two requests
    /// instead of one. Several download hosts refuse HEAD outright and serve the
    /// very same URL to a GET; a HEAD-only rule would file issues against
    /// recipes whose one-click works perfectly.
    @Test func aHostThatRefusesHEADButServesGETIsNotAccused() async throws {
        let server = try MethodAwareServer(headStatus: 405, rangedGetStatus: 206)
        defer { server.stop() }
        let result = await VendorProbeSource().installURLReachability(
            server.installURL, spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
        #expect(result == .ok, "405-to-HEAD must be resolved by the ranged GET, not reported")
        #expect(server.requests().contains("GET /install"), "the ranged GET must actually happen")
    }

    @Test func aVendorHavingABadMinuteIsTransientNotBroken() async throws {
        let server = try MethodAwareServer(headStatus: 503, rangedGetStatus: 503)
        defer { server.stop() }
        let result = await VendorProbeSource().installURLReachability(
            server.installURL, spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
        #expect(result == .transient(status: 503))
    }

    // MARK: - what the sweep does with it

    /// The mapping that decides whether an issue gets filed, checked without a
    /// socket. `gone` and `transient` must land on DIFFERENT warnings: one is
    /// aged by `Baseline`'s transient machinery and stays quiet, the other is
    /// actionable immediately, and swapping them either buries a dead URL or
    /// files an issue every time a CDN has a bad minute.
    @Test func reachabilityMapsOntoTheRightWarning() {
        #expect(VendorProbeSource.warning(for: .ok) == nil)
        #expect(VendorProbeSource.warning(for: .gone(status: 404))
                == .installURLNotFound(status: 404))
        #expect(VendorProbeSource.warning(for: .transient(status: 503))
                == .installURLTransient(status: 503))
    }

    /// The cost guard, and the only end-to-end assertion that survives contact
    /// with `preferHTTPS`.
    ///
    /// `resolveInstall` rewrites every `http://` installer URL to `https://`
    /// before returning it — correctly, since that is the URL the installer would
    /// download — so a plain-HTTP stub cannot answer the probe and there is no
    /// point asserting on the resulting warning here (the socket-level semantics
    /// are covered above). What this CAN prove, and what actually matters, is
    /// whether the install URL is contacted at all: `probeOutcome` is shared with
    /// the ordinary update path, so a default-on probe would put an extra request
    /// per app on every user's every check. Counting connections proves the
    /// default is off by observation rather than by trusting the flag.
    @Test func onlyTheSweepTouchesTheInstallURL() async throws {
        let quiet = try MethodAwareServer(headStatus: 404, rangedGetStatus: 404)
        defer { quiet.stop() }
        _ = await VendorProbeSource().probeDiagnostic(Self.recipe(quiet))
        #expect(quiet.connectionCount() == 1,
                "an update check must fetch the feed and nothing else, saw \(quiet.connectionCount())")

        let swept = try MethodAwareServer(headStatus: 404, rangedGetStatus: 404)
        defer { swept.stop() }
        _ = await VendorProbeSource()
            .probeDiagnostic(Self.recipe(swept), checkingInstallURL: true)
        #expect(swept.connectionCount() > 1,
                "the sweep must contact the install URL, saw \(swept.connectionCount())")
    }

    /// A transport failure on the ranged GET must NOT be read as "the vendor
    /// deleted this".
    ///
    /// This branch shipped wrong once. The `guard ... else` returned `.gone`,
    /// which is the verdict that files a public issue accusing a vendor — off a
    /// timeout, with no retry, on the very hosts most likely to need the GET
    /// fallback in the first place (the ones that refuse HEAD). The identical
    /// condition on the HEAD path was already treated as transient; the two must
    /// agree, because "we never got an answer" is not evidence of deletion.
    @Test func noAnswerToTheRangedGETIsNotEvidenceOfDeletion() async throws {
        let server = try MethodAwareServer(
            headStatus: 404, rangedGetStatus: 404, dropGET: true)
        defer { server.stop() }
        let result = await VendorProbeSource().installURLReachability(
            server.installURL,
            spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
        #expect(result == .transient(status: 404),
                "a dropped GET must age as transient, never accuse the vendor")
    }

    /// A `Range` refusal is not a missing artifact — the URL plainly exists to
    /// have rejected a range against it.
    @Test func aRangeRefusalIsNotAMissingArtifact() async throws {
        for status in [416, 501] {
            let server = try MethodAwareServer(headStatus: 405, rangedGetStatus: status)
            defer { server.stop() }
            let result = await VendorProbeSource().installURLReachability(
                server.installURL,
                spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))
            #expect(result == .transient(status: status),
                    "HTTP \(status) says the range was refused, not that the file is gone")
        }
    }

    /// The one mistake this change actually made, pinned.
    ///
    /// The probe first shipped sending this type's browser-like version-endpoint
    /// agent. SourceForge answers **403 to that and 200 to `DuoUpdater/0.1`**, so
    /// the sweep accused TigerVNC and GrandPerspective of losing installers that
    /// were being served the whole time. A curl spot check cannot see this — only
    /// the production request can — so the agent has to be asserted here or
    /// nothing holds it.
    @Test func theProbeSendsExactlyTheAgentTheDownloaderSends() async throws {
        let server = try MethodAwareServer(headStatus: 405, rangedGetStatus: 206)
        defer { server.stop() }
        _ = await VendorProbeSource().installURLReachability(
            server.installURL,
            spec: VendorInstallSpec(urlSource: .fixed(server.installURL), kind: .zip))

        let heads = server.heads()
        #expect(heads.count >= 2, "expected a HEAD and the ranged GET, saw \(heads.count)")
        for head in heads {
            #expect(head.contains("User-Agent: \(Downloader.userAgent)"),
                    "every probe request must carry the downloader's agent")
            #expect(!head.lowercased().contains("mozilla"),
                    "the browser-like version-endpoint agent must never be used here")
        }
        #expect(heads.contains { $0.contains("Range: bytes=0-0") })
    }

    /// `spec.requestHeaders` is what the real download layers on top, so it must
    /// win here too — that is the only way a per-vendor WAF workaround (Oray's
    /// `Referer`) reaches the probe.
    @Test func specHeadersReachTheProbeAndOverrideTheDefault() async throws {
        let server = try MethodAwareServer(headStatus: 405, rangedGetStatus: 206)
        defer { server.stop() }
        _ = await VendorProbeSource().installURLReachability(
            server.installURL,
            spec: VendorInstallSpec(
                urlSource: .fixed(server.installURL), kind: .zip,
                requestHeaders: ["Referer": "https://example.invalid/dl",
                                 "User-Agent": "Override/9"]))
        for head in server.heads() {
            #expect(head.contains("Referer: https://example.invalid/dl"))
            #expect(head.contains("User-Agent: Override/9"),
                    "a spec-level agent must override the downloader default")
        }
    }

    /// The wiring, not the mapping: deleting `warnings.append(...)` in
    /// `probeOutcome` must break something.
    ///
    /// Uses an unreachable HTTPS install URL rather than the stub, because
    /// `resolveInstall` rewrites every `http://` through `preferHTTPS` — so a
    /// plaintext stub can never answer the probe (see `onlyTheSweepTouchesTheInstallURL`).
    /// A refused connection reaches the same append by the transient path.
    @Test func theWarningActuallyReachesTheOutcome() async throws {
        let server = try MethodAwareServer(headStatus: 200, rangedGetStatus: 206)
        defer { server.stop() }
        let recipe = VendorProbeRecipe(
            bundleID: "com.example.subject",
            url: server.feedURL,
            mode: .responseBody,
            versionPattern: #""version":"([0-9.]+)""#,
            install: VendorInstallSpec(
                urlSource: .fixed(URL(string: "https://127.0.0.1:1/nothing-listens-here")!),
                kind: .zip))

        let swept = await VendorProbeSource().probeDiagnostic(recipe, checkingInstallURL: true)
        #expect(swept.warnings.map(\.kind).contains("installURLTransient"),
                "the probe's verdict must reach ProbeOutcome.warnings, saw \(swept.warnings.map(\.kind))")

        let checked = await VendorProbeSource().probeDiagnostic(recipe)
        #expect(checked.warnings.isEmpty,
                "and must not appear on the ordinary update path")
    }

    // MARK: - the registry-derived coverage check

    /// Derived from the registry rather than a hand-written list, so adding a
    /// recipe or a `URLSource` cannot quietly fall out of coverage.
    ///
    /// `provesReachabilityWhenResolved` is the switch that decides whether a
    /// recipe gets probed at all, so getting it wrong in the "true" direction is
    /// silent: the recipe simply never gets checked. This re-derives the same
    /// fact a second, independent way (pattern-matching `.redirect` directly) and
    /// requires both groups to be non-empty, which is what stops the whole thing
    /// degenerating into a constant.
    @Test func onlyRedirectSourcesAreConsideredAlreadyProven() {
        var proven: [String] = []
        var probed: [String] = []
        for recipe in VendorProbeRegistry.recipes {
            guard let spec = recipe.install else { continue }
            let isRedirect: Bool
            if case .redirect = spec.urlSource { isRedirect = true } else { isRedirect = false }
            #expect(
                spec.urlSource.provesReachabilityWhenResolved == isRedirect,
                "\(recipe.recipeID): provesReachabilityWhenResolved disagrees with .redirect")
            if isRedirect { proven.append(recipe.recipeID) } else { probed.append(recipe.recipeID) }
        }
        #expect(!proven.isEmpty, "no .redirect recipe left — this check has gone vacuous")
        #expect(!probed.isEmpty, "nothing would be probed — this check has gone vacuous")
        // The gap #159 was filed about: the probed group is the large one.
        #expect(probed.count > proven.count)
    }

    @Test func theNewWarningIsDistinctFromAPatternMiss() {
        #expect(ProbeWarning.installURLNotFound(status: 404).kind == "installURLNotFound")
        #expect(ProbeWarning.installURLNotFound(status: 404) != ProbeWarning.installURLUnresolved)
        #expect(ProbeWarning.installURLNotFound(status: 404)
                != ProbeWarning.installURLTransient(status: 404))
    }
}
