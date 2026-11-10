import Foundation
import Testing

@testable import DuoUpdaterCore

/// Shotcut respins under the old tag with a NEW version: tag `v26.9.27` carries
/// `shotcut-macos-26.9.27.dmg` and `shotcut-macos-26.9.28.dmg`, and the second
/// one's bundle says 26.9.28. The rule reads the offered version off the asset it
/// installs (`assetVersionPattern`), so the offer and the file agree. The stub
/// replays the real v26.9.27 asset list (2026-11-11), Linux respin included.
@Suite struct ShotcutGitHubRuleTests {
    private static let id = "com.Meltytech.Shotcut"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.id })
    }

    private static func installed(_ short: String, build: String? = nil) -> InstalledApp {
        InstalledApp(
            name: "Shotcut", bundleID: id, shortVersion: short, buildVersion: build ?? short,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Shotcut.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private func remote() async throws -> RemoteVersion {
        let source = GitHubReleasesSource(rules: [try rule()], session: Self.stubbedSession())
        return try #require(try await source.latestVersion(for: Self.installed("26.9.27")))
    }

    /// The respin is both what is offered and what installs. Mutation: drop
    /// `assetVersionPattern` → the offer reads 26.9.27 while the file is 26.9.28.
    @Test func theRespinIsOfferedAndInstalled() async throws {
        let remote = try await remote()
        #expect(remote.shortVersion == "26.9.28")
        #expect(remote.downloadURL?.lastPathComponent == "shotcut-macos-26.9.28.dmg")
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(remote.requiresManualInstaller == false)
        #expect(remote.structuredChangelog?.entries.first?.version == "26.9.28")
    }

    /// A copy of the original 26.9.27 build is offered the respin; a copy of the
    /// respin is up to date; a copy from before the dotted scheme (24.04 short,
    /// 24.04.28 build) is offered it too.
    @Test func eachInstalledCopyGetsTheRightVerdict() async throws {
        let remote = try await remote()
        guard case .updateAvailable = UpdateChecker.evaluate(
            installed: Self.installed("26.9.27"), remote: remote) else {
            Issue.record("26.9.27 not offered 26.9.28"); return
        }
        guard case .upToDate = UpdateChecker.evaluate(
            installed: Self.installed("26.9.28"), remote: remote) else {
            Issue.record("26.9.28 not up to date"); return
        }
        guard case .updateAvailable = UpdateChecker.evaluate(
            installed: Self.installed("24.04", build: "24.04.28"), remote: remote) else {
            Issue.record("24.04 not offered 26.9.28"); return
        }
        // A prerelease copy ahead of stable is never offered the older stable.
        if case .updateAvailable = UpdateChecker.evaluate(
            installed: Self.installed("26.10.30"), remote: remote) {
            Issue.record("26.10.30 offered a downgrade to 26.9.28")
        }
    }

    /// Whichever order GitHub lists them in, the highest-named dmg wins, and the
    /// unsigned build never does. Mutation: loosen the pattern to `^shotcut-macos-.*\.dmg$`
    /// → `shotcut-macos-unsigned-26.10.30.dmg` is chosen on the prerelease's list.
    @Test func theUnsignedAndOtherPlatformBuildsAreNeverChosen() throws {
        let pattern = try #require(try rule().installAssetPattern)
        for names in [Self.names, Self.names.reversed()] {
            let chosen = GitHubReleaseRule.installableAsset(
                from: Self.assets(names), matching: pattern,
                preferring: .arm64, allowingIntelTranslation: true)
            #expect(chosen?.url.lastPathComponent == "shotcut-macos-26.9.28.dmg")
        }
        let prerelease = ["shotcut-macos-26.10.30.dmg", "shotcut-macos-unsigned-26.10.30.dmg"]
        #expect(GitHubReleaseRule.installableAsset(
            from: Self.assets(prerelease), matching: pattern,
            preferring: .arm64, allowingIntelTranslation: true)?.url.lastPathComponent
            == "shotcut-macos-26.10.30.dmg")
    }

    /// The tag pattern reads every stable tag shape Shotcut has used and refuses
    /// a suffixed one.
    @Test func theTagPatternReadsBothSchemes() throws {
        let pattern = try rule().versionPattern
        #expect(VendorProbeRecipe.extractVersion(from: "v26.9.27", pattern: pattern) == "26.9.27")
        #expect(VendorProbeRecipe.extractVersion(from: "v25.08.16", pattern: pattern) == "25.08.16")
        #expect(VendorProbeRecipe.extractVersion(from: "v27.1.5", pattern: pattern) == "27.1.5")
        #expect(VendorProbeRecipe.extractVersion(from: "v26.10.30-rc1", pattern: pattern) == nil)
    }

    /// No pattern, no asset or an unreadable name keeps the tag's version.
    @Test func theTagVersionIsTheFallback() {
        #expect(GitHubReleaseRule.offeredVersion(
            tagVersion: "1.2.3", asset: "x-1.2.4.dmg", pattern: nil) == "1.2.3")
        #expect(GitHubReleaseRule.offeredVersion(
            tagVersion: "1.2.3", asset: nil, pattern: #"^x-([0-9.]+)\.dmg$"#) == "1.2.3")
        #expect(GitHubReleaseRule.offeredVersion(
            tagVersion: "1.2.3", asset: "y.dmg", pattern: #"^x-([0-9.]+)\.dmg$"#) == "1.2.3")
        #expect(GitHubReleaseRule.offeredVersion(
            tagVersion: "1.2.3", asset: "x-1.2.4.dmg", pattern: #"^x-([0-9.]+)\.dmg$"#) == "1.2.4")
    }

    /// The asset version is read off the asset the rule installs, so a rule
    /// without one has nothing to read it from.
    @Test func assetVersionPatternNeedsAnInstallAsset() {
        for rule in GitHubReleaseRegistry.rules where rule.assetVersionPattern != nil {
            #expect(rule.installAssetPattern != nil, "\(rule.recipeID) sets assetVersionPattern without installAssetPattern")
        }
    }

    // MARK: - Fixture

    /// The macOS-relevant assets of the real v26.9.27 release, in GitHub's order.
    private static let names = [
        "md5sums.txt", "sha256sums.txt",
        "shotcut-linux-x86_64-26.10.3.AppImage", "shotcut-linux-x86_64-26.9.27.AppImage",
        "shotcut-macos-26.9.27.dmg", "shotcut-macos-26.9.28.dmg",
        "shotcut-src-26.9.27.txz", "shotcut-win64-26.9.27.exe",
    ]

    private static func assets(_ names: [String]) -> [(name: String, url: URL, size: Int64?)] {
        names.map { ($0, URL(string: "https://example.invalid/shotcut/v26.9.27/\($0)")!, 1000) }
    }

    private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let base = "https://example.invalid/shotcut/releases/download/v26.9.27/"
            let encoded = ShotcutGitHubRuleTests.names.map {
                #"{"name":"\#($0)","browser_download_url":"\#(base)\#($0)","size":1000}"#
            }
            let release = """
            {"tag_name":"v26.9.27","name":"v26.9.27","draft":false,"prerelease":false,\
            "published_at":"2026-09-28T00:29:29Z",\
            "html_url":"https://example.invalid/shotcut/releases/tag/v26.9.27",\
            "body":"## What's Changed\\n\\n- Added **Automatic Audio Ducking**.\\n- New logo",\
            "assets":[\(encoded.joined(separator: ","))]}
            """
            let body = request.url?.absoluteString.contains("/releases/latest") == true
                ? release : "[\(release)]"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
