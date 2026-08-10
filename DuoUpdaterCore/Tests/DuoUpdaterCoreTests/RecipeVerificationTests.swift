import Testing
import Foundation
import Network
@testable import DuoUpdaterCore

/// The acceptance suite for automated recipe verification.
///
/// The whole point of `probeDiagnostic` + `RecipeSanity` is to find recipe
/// breakage *before* someone stumbles over it in the menu bar. So the bar these
/// tests hold it to is not "does it compile" but: **would it have caught the
/// breakages we actually shipped?**
///
/// Two real ones are replayed here, both from 2026-08-08, both found by accident:
///
///  • `2fcbc0a` — JetBrains added a fourth version segment; IntelliJ's pattern
///    was pinned to three, matched nothing, and the row read "unknown".
///  • `92d6e30` — Brave Beta's appcast reports Brave's own `1.94.104.0` while the
///    bundle reports Chromium-prefixed `151.1.94.104`, so the engine read the
///    installed copy as newer and the row said "up to date" forever.
///
/// They fail in completely different ways — the first is a loud nil, the second
/// never fails at all — which is exactly why one check isn't enough.
///
/// (The third fix from that day, `67960a9`, was `SparkleAppcastSource` dropping
/// every item in a feed with delta enclosures. That source has no diagnostic path
/// yet, so it is out of this suite's reach — noted so the gap stays visible.)
@Suite struct RecipeVerificationTests {

    /// Loopback HTTP/1.1 server with a canned status and body, so the production
    /// fetch path can be driven into each failure mode on demand.
    ///
    /// Dedicated serial queue for Network.framework callbacks, matching the
    /// starvation note in `DownloaderTrafficTests`.
    final class StubServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "RecipeVerificationStub")
        let port: UInt16

        init(status: Int = 200, body: String, contentType: String = "application/json") throws {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            let queue = self.queue

            listener.newConnectionHandler = { conn in
                conn.start(queue: queue)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                    let payload = Data(body.utf8)
                    var header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
                    header += "Content-Type: \(contentType)\r\n"
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

        var url: URL { URL(string: "http://127.0.0.1:\(port)/feed")! }
        func stop() { listener.cancel() }
    }

    private static func recipe(
        url: URL, pattern: String, install: VendorInstallSpec? = nil,
        versionIsBuild: Bool = false, displayVersionPattern: String? = nil
    ) -> VendorProbeRecipe {
        VendorProbeRecipe(
            bundleID: "com.example.subject", url: url, mode: .responseBody,
            versionPattern: pattern, versionIsBuild: versionIsBuild,
            displayVersionPattern: displayVersionPattern, install: install)
    }

    // MARK: - the loud failure: a pattern that stopped matching

    /// The exact IntelliJ regression from `2fcbc0a`, replayed end to end: the
    /// pre-fix pattern against the response JetBrains actually shipped.
    ///
    /// The old behaviour was `latestVersion(for:)` returning nil — indistinguishable
    /// from "no recipe applies" or "the wifi dropped". This asserts the sweep now
    /// names it, and names it as *the recipe's* problem rather than infrastructure.
    @Test func intelliJPreFixPatternIsReportedAsAPatternMiss() async throws {
        let body = #"{"majorVersion":"2026.2","version":"2026.2.0.1","build":"262.8665.337"}"#
        let server = try StubServer(body: body)
        defer { server.stop() }

        // The pattern as it was before the fix: exactly three segments.
        let preFix = Self.recipe(
            url: server.url, pattern: #""version"\s*:\s*"([0-9]{4}\.[0-9]+\.[0-9]+)""#)
        let outcome = await VendorProbeSource().probeDiagnostic(preFix)

        #expect(outcome.remote == nil)
        let failure = try #require(outcome.failure)
        #expect(failure.kind == "versionPatternNoMatch")
        #expect(failure.classification == .recipe, "a stale pattern must be actionable, not infra")
        // The body sample is what a human (or a triage step) needs to fix it.
        #expect(outcome.bodySample?.contains("2026.2.0.1") == true)
    }

    /// Control: the shipping pattern reads the same body correctly, so the test
    /// above is pinning the pattern change and not something incidental.
    @Test func intelliJShippingPatternReadsTheFourSegmentVersion() async throws {
        let body = #"{"majorVersion":"2026.2","version":"2026.2.0.1","build":"262.8665.337"}"#
        let server = try StubServer(body: body)
        defer { server.stop() }

        let shipping = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.jetbrains.intellij" })
        let outcome = await VendorProbeSource().probeDiagnostic(
            Self.recipe(url: server.url, pattern: shipping.versionPattern))

        #expect(outcome.failure == nil)
        #expect(outcome.remote?.shortVersion == "2026.2.0.1")
        #expect(RecipeSanity.complaints(
            version: "2026.2.0.1",
            recipe: Self.recipe(url: server.url, pattern: shipping.versionPattern)).isEmpty)
    }

    // MARK: - the silent failure: a pattern that matched the wrong scheme

    /// The Brave Beta regression from `92d6e30`. Nothing here fails: the fetch
    /// succeeds, the pattern matches, a perfectly well-formed version comes back.
    /// Only comparing it against the installed copy reveals that the feed is
    /// *behind* what's on disk — which is impossible for a vendor's own feed and
    /// is the fingerprint of two different version schemes.
    @Test func braveSchemeMismatchIsCaughtByComparingAgainstTheInstalledCopy() {
        // Pre-fix: the recipe read `sparkle:shortVersionString`, Brave's own
        // numbering, and compared it to the bundle's Chromium-prefixed string.
        let preFix = RemoteVersion(
            shortVersion: "1.94.104.0", version: nil, downloadURL: nil, sourceName: "Vendor")
        let complaint = RecipeSanity.remoteBehindInstalled(
            remote: preFix, installedMarketing: "151.1.94.104", installedBuild: "194.104")
        #expect(complaint != nil, "1.94.104.0 vs installed 151.1.94.104 must be flagged")
        #expect(complaint?.contains("BEHIND") == true)

        // Post-fix: `versionIsBuild` routes `sparkle:version` into `version`, which
        // is exactly the bundle's CFBundleVersion, and the marketing string rides
        // along for display only. Comparing on the right field, nothing is wrong.
        let postFix = RemoteVersion(
            shortVersion: "1.94.104.0", version: "194.104", downloadURL: nil, sourceName: "Vendor")
        #expect(RecipeSanity.remoteBehindInstalled(
            remote: postFix, installedMarketing: "151.1.94.104", installedBuild: "194.104") == nil,
            "the fixed recipe compares build to build and must stay quiet")
    }

    /// A newer feed than the installed copy is the normal case and must never be
    /// flagged — otherwise every app with an available update looks broken.
    @Test func anAvailableUpdateIsNotMistakenForASchemeMismatch() {
        let remote = RemoteVersion(shortVersion: "2.0.0", version: nil, downloadURL: nil, sourceName: "Vendor")
        #expect(RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: "1.9.0", installedBuild: nil) == nil)
        #expect(RecipeSanity.remoteBehindInstalled(
            remote: remote, installedMarketing: "2.0.0", installedBuild: nil) == nil)
    }

    // MARK: - failure taxonomy

    /// A 4xx means the URL in the recipe is wrong — someone has to edit it. A 5xx
    /// means the vendor is having a bad day. Collapsing those into one bucket is
    /// what makes an automated sweep either noisy or useless.
    @Test func clientErrorsAreActionableAndServerErrorsAreNot() async throws {
        let notFound = try StubServer(status: 404, body: "nope")
        defer { notFound.stop() }
        let outcome404 = await VendorProbeSource().probeDiagnostic(
            Self.recipe(url: notFound.url, pattern: #"([0-9.]+)"#))
        #expect(outcome404.failure?.kind == "httpStatus404")
        #expect(outcome404.failure?.classification == .recipe)

        let unavailable = try StubServer(status: 503, body: "later")
        defer { unavailable.stop() }
        let outcome503 = await VendorProbeSource().probeDiagnostic(
            Self.recipe(url: unavailable.url, pattern: #"([0-9.]+)"#))
        #expect(outcome503.failure?.kind == "httpStatus503")
        #expect(outcome503.failure?.classification == .infra)

        // Nothing listening: transport, never the recipe's fault.
        let dead = Self.recipe(
            url: URL(string: "http://127.0.0.1:1/feed")!, pattern: #"([0-9.]+)"#)
        let outcomeDead = await VendorProbeSource().probeDiagnostic(dead)
        #expect(outcomeDead.failure?.classification == .infra)
    }

    /// The half-broken recipe: version still reads, one-click is dead.
    ///
    /// Completely invisible before — `resolveInstall` failing just degrades the
    /// result to detection-only and the row keeps looking healthy. The first full
    /// sweep found two live instances of exactly this (Outlook's `Update Version
    /// Location` key is gone; Signal Beta's installer is named
    /// `signal-desktop-beta-mac-universal-…` while the pattern still expects
    /// `signal-desktop-mac-universal-…`), so this is a real shape, not a
    /// hypothetical one.
    @Test func aDeadInstallerPatternIsFlaggedEvenThoughTheVersionStillReads() async throws {
        let body = """
        version: 8.23.0-beta.1
        files:
          - url: signal-desktop-beta-mac-universal-8.23.0-beta.1.dmg
            sha512: bm90LWEtcmVhbC1oYXNo
        """
        let server = try StubServer(body: body, contentType: "text/yaml")
        defer { server.stop() }

        let stale = Self.recipe(
            url: server.url, pattern: #"version:\s*([0-9][^\s]*)"#,
            install: VendorInstallSpec(
                urlSource: .bodyPatternRelative(
                    #"(signal-desktop-mac-universal-[^\s]+\.dmg)"#,
                    base: URL(string: "https://updates.signal.org/desktop/")!),
                kind: .dmg))
        let outcome = await VendorProbeSource().probeDiagnostic(stale)

        // The version is fine — which is the whole problem.
        #expect(outcome.remote?.shortVersion == "8.23.0-beta.1")
        #expect(outcome.failure == nil)
        #expect(outcome.warnings.contains(.installURLUnresolved))
    }

    /// A checksum pattern that no longer matches means the download would install
    /// unverified. The version still reads, so nothing else notices.
    @Test func aStaleChecksumPatternIsFlaggedRatherThanInstallingUnverified() async throws {
        let body = """
        version: 3.1.0
        url: https://example.invalid/app-3.1.0.dmg
        digest: bm90LWEtcmVhbC1oYXNo
        """
        let server = try StubServer(body: body, contentType: "text/yaml")
        defer { server.stop() }

        let stale = Self.recipe(
            url: server.url, pattern: #"version:\s*([0-9][^\s]*)"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"(https://example\.invalid/[^\s]+\.dmg)"#),
                kind: .dmg,
                // The vendor renamed `sha512:` to `digest:`.
                checksumPattern: #"sha512:\s*([A-Za-z0-9+/=]+)"#))
        let outcome = await VendorProbeSource().probeDiagnostic(stale)

        #expect(outcome.remote?.shortVersion == "3.1.0")
        #expect(outcome.warnings.contains(.checksumPatternNoMatch))
    }

    // MARK: - the sanity checks must stay quiet on healthy recipes

    /// A check that fires on working recipes gets ignored, and then it catches
    /// nothing at all. These are the shapes in the live registry that a naive
    /// "must start with a digit" rule would wrongly flag.
    @Test func sanityChecksDoNotFireOnTheShippingRegistry() {
        let cases: [(String, String)] = [
            ("com.sublimemerge", "Build 2125"),
            ("com.sublimetext.4", "Build 4200"),
            ("com.microsoft.Outlook", "16.109.26053122"),
            ("com.jetbrains.intellij", "2026.2.0.1"),
            // Seven segments, all of them the app's own: 0.YYYY.MM.DD.HH.MM.NN.
            ("dev.warp.Warp-Stable", "0.2026.08.05.09.03.01"),
            ("dev.warp.Warp-Dev", "0.2026.08.07.08.31.00"),
        ]
        for (bundleID, version) in cases {
            let recipe = try! #require(
                VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
            #expect(
                RecipeSanity.complaints(version: version, recipe: recipe).isEmpty,
                "\(bundleID) '\(version)' should not be flagged")
        }
    }

    /// …but the shapes that mean "we grabbed a label, not a version" must fire.
    @Test func sanityChecksFireOnValuesThatArePlainlyNotVersions() {
        let recipe = Self.recipe(
            url: URL(string: "https://example.invalid/feed")!, pattern: #"(.+)"#)
        #expect(!RecipeSanity.complaints(version: "latest", recipe: recipe).isEmpty)
        #expect(!RecipeSanity.complaints(version: "2026", recipe: recipe).isEmpty)
        #expect(!RecipeSanity.complaints(version: ".1.2", recipe: recipe).isEmpty)
        #expect(!RecipeSanity.complaints(version: "1.2.3.4.5.6.7.8", recipe: recipe).isEmpty)
    }

    /// The pattern matching the request URL instead of the response is a real
    /// authoring slip, and it produces a version-shaped answer that never changes.
    @Test func aVersionThatCameFromTheRequestURLIsFlagged() {
        let recipe = Self.recipe(
            url: URL(string: "https://example.invalid/v2.4.0/latest.json")!,
            pattern: #"([0-9.]+)"#)
        let complaints = RecipeSanity.complaints(version: "2.4.0", recipe: recipe)
        #expect(complaints.contains { $0.contains("request URL") })
    }
}
