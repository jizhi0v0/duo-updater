import Foundation
import Testing
@testable import DuoUpdaterCore

/// `RecipeHealth` has to key GitHub rules by the per-rule id, not by the
/// `owner/repo` slug two rules can share.
///
/// Zed is the case in hand: `dev.zed.Zed` and `dev.zed.Zed-Preview` are two rules
/// over `zed-industries/zed`, with different version patterns and different
/// endpoints. Keyed by slug, whichever ran LAST decided the verdict for both — a
/// Preview rule whose `-pre` pattern had stopped matching was reported healthy on
/// the strength of the stable rule's success, while every Preview row quietly went
/// `.unknown`. The diagnostics panel is the only surface that says a recipe broke,
/// so masking there is the whole failure.
@Suite(.serialized)
struct RecipeHealthKeyTests {

    /// Serves a well-formed but assetless `v1.0.0` release from every endpoint, so
    /// any rule pointed at it fetches fine and then fails to produce a version —
    /// either its tag pattern doesn't match or no release carries its macOS asset,
    /// both of which are shapes `RecipeHealth` records a miss for.
    ///
    /// It has to answer the exact-tag endpoint too, and with the release-state
    /// fields: a rule with `installedTagPrefix` (UTM Beta) probes channel discovery
    /// FIRST and returns before `resolve` when that probe can't complete, which
    /// records no health at all. An empty list made that rule look like the bug
    /// this suite is about.
    private final class EmptyReleasesProtocol: URLProtocol, @unchecked Sendable {
        /// Endpoint path → body, for a test that needs one endpoint to succeed.
        nonisolated(unsafe) static var answering: [String: String] = [:]

        static func release(tag: String) -> String {
            """
            {"tag_name":"\(tag)","prerelease":true,"draft":false,
             "published_at":"2026-09-13T00:00:00Z","assets":[]}
            """
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let path = request.url?.path ?? ""
            let body: String
            if let scripted = Self.answering[path] {
                body = scripted
            } else if let range = path.range(of: "/releases/tags/") {
                body = Self.release(tag: String(path[range.upperBound...]).removingPercentEncoding
                    ?? String(path[range.upperBound...]))
            } else if path.hasSuffix("/releases/latest") {
                body = Self.release(tag: "v1.0.0")
            } else {
                body = "[\(Self.release(tag: "v1.0.0"))]"
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func source(rules: [GitHubReleaseRule]) -> GitHubReleasesSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmptyReleasesProtocol.self]
        return GitHubReleasesSource(
            rules: rules, session: URLSession(configuration: configuration))
    }

    private func rule(bundleID: String) throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID })
    }

    /// A miss on the Preview rule must survive a success on the stable rule that
    /// shares its slug. With both filed under `zed-industries/zed`, the success
    /// landed second and the panel showed one healthy row.
    @Test func aBrokenChannelRuleIsNotMaskedByItsHealthySibling() async throws {
        let preview = try rule(bundleID: "dev.zed.Zed-Preview")
        let stable = try rule(bundleID: "dev.zed.Zed")
        // The stable rule reads `/releases/latest`; the Preview rule reads the
        // list. Only the first answers, so the Preview rule misses and the stable
        // rule succeeds — in that order, which is the order that used to lose.
        EmptyReleasesProtocol.answering = [
            "/repos/zed-industries/zed/releases/latest": """
            {"tag_name":"v1.5.3","prerelease":false,"draft":false,
             "assets":[{"name":"Zed-aarch64.dmg",
                        "browser_download_url":"https://example.invalid/Zed-aarch64.dmg",
                        "size":1}]}
            """,
        ]
        defer { EmptyReleasesProtocol.answering = [:] }

        _ = await source(rules: [preview]).resolveDiagnostic(preview)
        _ = await source(rules: [stable]).resolveDiagnostic(stable)

        let entries = await RecipeHealth.shared.snapshot()
        let previewEntry = try #require(
            entries.first { $0.id == preview.recipeID && $0.source == "GitHub" },
            "the Preview rule needs its own health entry, not a shared one")
        #expect(previewEntry.isHealthy == false)
        let stableEntry = try #require(
            entries.first { $0.id == stable.recipeID && $0.source == "GitHub" })
        #expect(stableEntry.isHealthy == true)
    }

    /// The vendor half of the same bug. Android Studio is the live case — Stable
    /// and Canary are two recipes under `com.google.android.studio` — so a broken
    /// Canary recipe was reported healthy every time the Stable one answered.
    /// Synthetic recipes rather than the registry's, so the test does not depend
    /// on which of a vendor's endpoints happens to be reachable.
    @Test func twoVendorRecipesUnderOneBundleIDRecordSeparately() async throws {
        let bundleID = "com.zzfixture.twochannels"
        func recipe(_ channel: ReleaseChannel, pattern: String) -> VendorProbeRecipe {
            VendorProbeRecipe(
                bundleID: bundleID,
                url: URL(string: "https://zzfixture.invalid/\(channel.rawValue).json")!,
                mode: .responseBody,
                versionPattern: pattern,
                channel: channel)
        }
        // Stable's pattern matches the served body; Canary's does not, which is the
        // "vendor changed their page" shape — and it runs FIRST, so only a
        // per-recipe key can keep it from being cleared by Stable's success.
        let canary = recipe(.canary, pattern: #""canaryVersion"\s*:\s*"([0-9.]+)""#)
        let stable = recipe(.stable, pattern: #""version"\s*:\s*"([0-9.]+)""#)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmptyReleasesProtocol.self]
        EmptyReleasesProtocol.answering = [
            "/canary.json": #"{"version":"1.2.3"}"#,
            "/stable.json": #"{"version":"1.2.3"}"#,
        ]
        defer { EmptyReleasesProtocol.answering = [:] }
        let source = VendorProbeSource(
            recipes: [canary, stable], session: URLSession(configuration: configuration))

        func app(_ channel: ReleaseChannel) -> InstalledApp {
            let path = URL(fileURLWithPath: "/Applications/ZZFixture-TwoChannels.app")
            #expect(!FileManager.default.fileExists(atPath: path.path))
            return InstalledApp(
                name: "ZZFixture", bundleID: bundleID, shortVersion: "1.0.0", buildVersion: nil,
                path: path, isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil,
                releaseChannel: channel)
        }
        _ = try? await source.latestVersion(for: app(.canary))
        _ = try? await source.latestVersion(for: app(.stable))

        // Scoped to this fixture's own bundle id: `RecipeHealth.shared` is process-
        // wide and other suites run beside this one, so "every Vendor entry" would
        // be measuring whatever else happened to check in the same second.
        let entries = await RecipeHealth.shared.snapshot()
            .filter { $0.source == "Vendor" && $0.id.contains(bundleID) }
        #expect(entries.map(\.id).sorted() == [canary.recipeID, stable.recipeID].sorted())
        #expect(entries.first { $0.id == canary.recipeID }?.isHealthy == false)
        #expect(entries.first { $0.id == stable.recipeID }?.isHealthy == true)
    }

    /// Keying by recipe id moved the diagnostics rows off bare bundle ids, so the
    /// panel's name lookup has to reach INTO the id. Both halves matter: the name
    /// (a raw `vendor:…:beta` row is not what a reader is looking for) and the id
    /// beside it (drop it and two channels of one app render identically).
    @Test func aRecipeIDStillResolvesTheAppsName() {
        let names = ["com.example.editor": "Editor"]
        func entry(_ id: String) -> RecipeHealth.Entry {
            RecipeHealth.Entry(id: id, source: "Vendor")
        }
        #expect(entry("vendor:com.example.editor:beta").displayName(resolving: names)
                == "Editor · vendor:com.example.editor:beta")
        #expect(entry("vendor:com.example.editor:stable").displayName(resolving: names)
                != entry("vendor:com.example.editor:beta").displayName(resolving: names))
        // A source that keys by the bare bundle id keeps the plain name.
        #expect(entry("com.example.editor").displayName(resolving: names) == "Editor")
        // Nothing to resolve — a GitHub rule's id names a repo, not an app.
        #expect(entry("github:owner/repo:stable").displayName(resolving: names)
                == "github:owner/repo:stable")
    }

    /// Derived from the registry: every rule that shares a slug with another must
    /// still land in its own `RecipeHealth` row. Written as "run them all and count
    /// the rows" rather than as an assertion about ids, so it measures what the
    /// source records rather than what the registry could record.
    @Test func rulesSharingASlugRecordSeparateHealthEntries() async throws {
        let shared = Dictionary(grouping: GitHubReleaseRegistry.rules, by: \.slug)
            .filter { $0.value.count > 1 }
        #expect(!shared.isEmpty, "no slug is shared any more — this test has nothing to measure")

        for (slug, rules) in shared {
            for rule in rules {
                _ = await source(rules: [rule]).resolveDiagnostic(rule)
            }
            let recorded = await RecipeHealth.shared.snapshot()
                .filter { $0.source == "GitHub" && $0.id.contains(slug) }
            let expected = rules.map(\.recipeID).sorted()
            let got = recorded.map(\.id).sorted()
            #expect(
                recorded.count == rules.count,
                "\(slug): \(expected) should each have their own health entry, got \(got)")
        }
    }
}
