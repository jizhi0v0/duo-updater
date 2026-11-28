import Foundation
import Testing

@testable import DuoUpdaterCore

@Suite struct CleanClipRecipeTests {
    private static let bundleID = "com.antiless.cleanclip.mac"
    private static let stableDigest = "a5e4d694dbd97a1b5371e88bef148dc4e31311bf1f05fdda7693285bdafb088b"

    @Test func installedChannelSelectsItsOwnOfficialDMG() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseFixture.self]
        let source = GitHubReleasesSource(
            rules: com_antiless_cleanclip_mac.set.githubRules,
            session: URLSession(configuration: configuration))

        let stable = try #require(try await source.latestVersion(for: Self.installed("2.4.6")))
        #expect(stable.shortVersion == "2.4.7")
        #expect(stable.downloadURL?.lastPathComponent == "CleanClip-2.4.7.dmg")
        #expect(stable.vendorInstallerKind == .dmg)
        #expect(stable.expectedSHA256 == Self.stableDigest)

        let betaApp = Self.installed("2.2.0-beta.1")
        #expect(betaApp.releaseChannel == .beta)
        let beta = try #require(try await source.latestVersion(for: betaApp))
        #expect(beta.shortVersion == "2.4.1-beta.1")
        #expect(beta.downloadURL?.lastPathComponent == "CleanClip-2.4.1-beta.1.dmg")
        #expect(beta.expectedSHA256 == nil)
        #expect(try await source.latestVersion(for: Self.installed("2.4.6", isMASApp: true)) == nil)
    }

    @Test func notesSeparateChannelsAndPreserveSectionsWithoutDownloadText() throws {
        let recipes = com_antiless_cleanclip_mac.set.changelogs
        let stable = try #require(recipes.first { $0.channel == .stable })
        let stableEntries = try #require(ChangelogExtractor.extract(from: Self.html, using: stable)).entries
        #expect(stableEntries.map(\.version) == ["2.4.7", "2.4.6"])
        #expect(stableEntries.first?.date == "2026-05-27")
        #expect(stableEntries.first?.items == ["Improved Paste Queue reliability."])
        #expect(stableEntries.last?.content == [
            .heading("🎨 UI Improvements"),
            .note("Unified styling in PinnedView"),
            .heading("Shortcuts"),
            .note("Paste menu"),
            .note("Cmd+Number: Switch between groups"),
        ])

        let beta = try #require(recipes.first { $0.channel == .beta })
        let betaEntries = try #require(ChangelogExtractor.extract(from: Self.html, using: beta)).entries
        #expect(betaEntries.map(\.version) == ["2.4.1-beta.1"])
        #expect(betaEntries.first?.items == ["Support for Core Data data backup"])
    }

    private static func installed(_ version: String, isMASApp: Bool = false) -> InstalledApp {
        InstalledApp(
            name: "CleanClip", bundleID: bundleID,
            shortVersion: version, buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/ZZFixture-CleanClip.app"),
            isMASApp: isMASApp, sparkleFeedURL: nil,
            releaseChannel: .detect(name: "CleanClip", bundleID: bundleID, keystoneChannel: nil, version: version))
    }

    private final class ReleaseFixture: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let releasePath = "/repos/CleanClip/CleanClipApp/releases"
            guard let url = request.url, url.host == "api.github.com",
                  url.path == releasePath || url.path == releasePath + "/latest"
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            let stable = release("2.4.7", prerelease: false, digest: CleanClipRecipeTests.stableDigest)
            let beta = release("2.4.1-beta.1", prerelease: true)
            let olderBeta = release("2.2.0-beta.1", prerelease: true)
            // An older beta deliberately comes before the latest beta in the list.
            let payload: Any = url.path.hasSuffix("/latest") ? stable : [stable, olderBeta, beta]
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        private func release(_ version: String, prerelease: Bool, digest: String? = nil) -> [String: Any] {
            let upstream = "https://github.com/CleanClip/CleanClipApp/releases"
            let assets: [[String: Any]] = ["zip", "dmg"].map { archiveType in
                let name = "CleanClip-\(version).\(archiveType)"
                var asset: [String: Any] = [
                    "name": name,
                    "browser_download_url": "\(upstream)/download/\(version)/\(name)",
                    "size": 22_001_000,
                ]
                if archiveType == "dmg", let digest {
                    asset["digest"] = "sha256:\(digest)"
                }
                return asset
            }
            return [
                "tag_name": version,
                "draft": false,
                "prerelease": prerelease,
                "html_url": "\(upstream)/tag/\(version)",
                "assets": assets,
            ]
        }
    }

    // Excerpts from the website's VuePress release blocks and the nested-list variant.
    private static let html = #"""
        <h2 id="_2-4-7"><a href="#_2-4-7" class="header-anchor">#</a> 2.4.7</h2>
        <p>Date: 2026-05-27</p>
        <ul><li><p>Improved Paste Queue reliability.
        <a href="https://cleanclip.cc/releases/download/v2.4.7/CleanClip.dmg" target="_blank">Download<span class="sr-only">(opens new window)</span></a></p></li></ul>
        <h2 id="_2-4-6"><a href="#_2-4-6" class="header-anchor">#</a> 2.4.6</h2>
        <p>Date: 2026-01-11</p>
        <h3 id="ui"><a href="#ui" class="header-anchor">#</a> 🎨 UI Improvements</h3>
        <ul><li>Unified styling in PinnedView</li></ul>
        <h3 id="keys"><a href="#keys" class="header-anchor">#</a> Shortcuts</h3>
        <ul><li><p><strong>Paste menu</strong></p><ul><li>Cmd+Number: Switch between groups</li></ul></li></ul>
        <h2 id="_2-4-1-beta-1"><a href="#_2-4-1-beta-1" class="header-anchor">#</a> 2.4.1-beta.1</h2>
        <p>Date: 2025-04-27</p>
        <h3 id="features"><a href="#features" class="header-anchor">#</a> Features</h3>
        <ul><li>Support for Core Data data backup</li></ul>
        <footer><ul><li>Unrelated footer text</li></ul></footer>
        """#
}
