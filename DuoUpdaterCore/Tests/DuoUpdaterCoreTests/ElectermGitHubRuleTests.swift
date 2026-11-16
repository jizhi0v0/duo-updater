import Foundation
import Testing

@testable import DuoUpdaterCore

@Suite struct ElectermGitHubRuleTests {
    private static let bundleID = "org.electerm.electerm"

    private func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == Self.bundleID })
    }

    @Test(arguments: [
        ("v5.11.8", "5.11.8"), ("2.4.35", "2.4.35"),
        ("1.13.4", "1.13.4"), ("1.10.0", "1.10.0"),
        ("v6.0.0", "6.0.0"), ("6.0", "6.0"),
        ("v6.0.0-rc.1", nil), ("v6.0.0-beta.1", nil),
        ("nightly-v6.0.0", nil), ("v5.11.8 release", nil),
    ])
    func tagsReadTheWholeNumericVersion(tag: String, expected: String?) throws {
        #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: try rule().versionPattern)
                == expected)
    }

    /// Trimmed from v5.11.8's real multi-platform asset list and bilingual notes.
    /// A 5.10.0 copy must receive the native DMG, with the vendor's section
    /// headings retained. Dropping the asset pattern's end anchor admits a
    /// blockmap instead of a mountable archive.
    @Test func nativeDMGAndStructuredNotesResolveTogether() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLatest.self]
        let source = GitHubReleasesSource(
            rules: [try rule()], session: URLSession(configuration: config))
        let installed = InstalledApp(
            name: "electerm", bundleID: Self.bundleID,
            shortVersion: "5.10.0", buildVersion: "5.10.0.1",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-electerm.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .stable)

        let remote = try #require(try await source.latestVersion(for: installed))
        #expect(remote.shortVersion == "5.11.8")
        #expect(remote.downloadURL?.lastPathComponent == "electerm-5.11.8-mac-arm64.dmg")
        #expect(remote.electronBlockmapURL == nil, "the delta route consumes ZIPs, not DMGs")
        let entry = try #require(remote.structuredChangelog?.entries.first)
        #expect(entry.items == [
            "Add per-bookmark custom server watchers",
            "Improve app init speed",
            "Fix terminal search performance, avoid stuck",
            "支持为每个书签添加自定义服务器监控",
        ])
        #expect(entry.content.compactMap { block -> String? in
            if case .heading(let title) = block { return title }
            return nil
        } == ["Major updates", "New features/UI/Updates", "Bug fixes", "重大更新"])
    }

    final class StubLatest: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let base = "https://github.com/electerm/electerm/releases/download/v5.11.8/"
            let assets = [
                "electerm-5.11.8-mac10-x64.dmg",
                "electerm-5.11.8-mac-x64.dmg",
                "electerm-5.11.8-mac-arm64.dmg.blockmap",
                "electerm-5.11.8-linux-arm64.tar.gz",
                "electerm-5.11.8-mac-arm64.dmg",
            ].map {
                ["name": $0, "browser_download_url": base + $0, "size": 1000] as [String: Any]
            }
            let release: [String: Any] = [
                "tag_name": "v5.11.8", "name": "v5.11.8",
                "draft": false, "prerelease": false,
                "published_at": "2026-11-16T00:23:02Z",
                "html_url": "https://github.com/electerm/electerm/releases/tag/v5.11.8",
                "body": """
                ### Major updates

                - Add per-bookmark custom server watchers (#4730)

                ### New features/UI/Updates

                - Improve app init speed

                ### Bug fixes

                - Fix terminal search performance, avoid stuck

                -----

                ### 重大更新

                - 支持为每个书签添加自定义服务器监控 (#4730)
                """,
                "assets": assets,
            ]
            let payload: Any = request.url?.path.hasSuffix("/latest") == true ? release : [release]
            let body = try! JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
