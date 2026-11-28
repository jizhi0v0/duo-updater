import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct KodiRecipeTests {
    @Test func stableMirrorRowsKeepTheSelectedVersionAndDownloadTogether() async throws {
        let recipe = try #require(org_xbmc_kodi.set.probes.first)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KodiMirrorFixture.self]
        let source = VendorProbeSource(
            recipes: [recipe], session: URLSession(configuration: configuration))

        let offered = try await source.latestVersion(for: Self.app("21.2."))
        let remote = try #require(offered)
        #expect(remote.shortVersion == "21.3")
        #expect(remote.downloadURL?.absoluteString ==
            "https://mirrors.kodi.tv/releases/osx/arm64/kodi-21.3-Omega-arm64.dmg?https=1")
        #expect(remote.vendorInstallerKind == .dmg)
        #expect(VersionComparator.isNewer(remote.versionSide, than: .init(marketing: "21.2.")))
        #expect(!VersionComparator.isNewer(remote.versionSide, than: .init(marketing: "21.3.")))
    }

    @Test(arguments: ["22.0.rc2", "22.0.beta2", "23.0.alpha1"])
    func aTaggedCopyCannotUseTheStableMirrorEvenIfClassifiedAsStable(version: String) async throws {
        let recipe = try #require(org_xbmc_kodi.set.probes.first)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KodiMirrorFixture.self]
        let source = VendorProbeSource(
            recipes: [recipe], session: URLSession(configuration: configuration))

        #expect(try await source.latestVersion(for: Self.app(version)) == nil)
    }

    @Test func rssRetainsStableReleaseCategoriesAndOmitsPrereleaseItems() throws {
        let recipe = try #require(org_xbmc_kodi.set.changelogs.first)
        let changelog = try #require(ChangelogExtractor.extract(from: Self.rss, using: recipe))

        #expect(changelog.entries.map(\.version) == ["21.3", "21.2"])
        let latest = try #require(changelog.entries.first)
        #expect(latest.date == "Tue, 16 Dec 2025 10:01:11 GMT")
        #expect(latest.content == [
            .heading("Video"),
            .note("Fixed Blu-ray playback on Linux"),
            .heading("Peripherals"),
            .note("Fixed enabling and disabling Pulse-Eight CEC adapters"),
        ])
        #expect(changelog.entries.last?.content.first == .heading("Library/Sources and Management"))
    }

    private static func app(_ version: String) -> InstalledApp {
        InstalledApp(
            name: "Kodi", bundleID: "org.xbmc.kodi", shortVersion: version, buildVersion: "20251031-a3a448d26b",
            path: URL(fileURLWithPath: "/Applications/ZZFixture-Kodi.app"), isMASApp: false,
            sparkleFeedURL: nil, releaseChannel: .stable)
    }

    private final class KodiMirrorFixture: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url,
                  url.absoluteString == "https://mirrors.kodi.tv/releases/osx/arm64/",
                  let response = HTTPURLResponse(
                      url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "text/html; charset=utf-8"])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.mirror.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        // Rows from the official directory, with Stable entries reversed.
        // The foreign Intel and external URL entries exercise the link boundary.
        private static let mirror = #"""
            <tr><td><a href="kodi-22.0-Piers_rc2-arm64.dmg" title="kodi-22.0-Piers_rc2-arm64.dmg">kodi-22.0-Piers_rc2-arm64.dmg</a></td><td>67.9 MiB</td><td>2026-Nov-10 05:12</td></tr>
            <tr><td><a href="kodi-22.0-Piers_beta2-arm64.dmg" title="kodi-22.0-Piers_beta2-arm64.dmg">kodi-22.0-Piers_beta2-arm64.dmg</a></td><td>67.3 MiB</td><td>2026-Sep-01 03:24</td></tr>
            <tr><td><a href="kodi-22.0-Piers-x86_64.dmg">kodi-22.0-Piers-x86_64.dmg</a></td></tr>
            <tr><td><a href="https://example.invalid/kodi-22.0-Piers-arm64.dmg">kodi-22.0-Piers-arm64.dmg</a></td></tr>
            <tr><td><a href="kodi-21.2-Omega-arm64.dmg" title="kodi-21.2-Omega-arm64.dmg">kodi-21.2-Omega-arm64.dmg</a></td><td>72.5 MiB</td><td>2025-Jan-18 19:27</td></tr>
            <tr><td><a href="kodi-21.3-Omega-arm64.dmg" title="kodi-21.3-Omega-arm64.dmg">kodi-21.3-Omega-arm64.dmg</a></td><td>72.5 MiB</td><td>2025-Dec-13 14:56</td></tr>
            """#
    }

    // Excerpts from the Kodi Foundation RSS feed, which escapes the HTML once.
    private static let rss = #"""
        <item><title>Kodi 22 &quot;Piers&quot; RC 2</title><pubDate>Thu, 12 Nov 2026 15:11:00 GMT</pubDate><content:encoded>
        &lt;ul&gt;&lt;li&gt;Added chapter, scene marker, and bookmark jumping using Up/Down during video playback&lt;/li&gt;&lt;/ul&gt;
        </content:encoded><category>Prerelease</category></item>
        <item><title>Kodi 21.3 &quot;Omega&quot; - Release</title><pubDate>Tue, 16 Dec 2025 10:01:11 GMT</pubDate><content:encoded>
        &lt;p&gt;&lt;strong&gt;Video&lt;/strong&gt;&lt;/p&gt;
        &lt;ul&gt;&lt;li&gt;Fixed Blu-ray playback on Linux&lt;/li&gt;&lt;/ul&gt;
        &lt;p&gt;&lt;strong&gt;Peripherals&lt;/strong&gt;&lt;/p&gt;
        &lt;ul&gt;&lt;li&gt;Fixed enabling and disabling &lt;a href=&quot;https://www.pulse-eight.com&quot;&gt;Pulse-Eight&lt;/a&gt; CEC adapters&lt;/li&gt;&lt;/ul&gt;
        &lt;p&gt;&lt;strong&gt;Windows Store/Android Deployment&lt;/strong&gt;&lt;/p&gt;
        &lt;p&gt;Due to the internal and external hoops we need to jump through, it might be a little while.&lt;/p&gt;
        </content:encoded><category>Release</category></item>
        <item><title>Kodi 21.2 &quot;Omega&quot; - Release</title><pubDate>Sun, 19 Jan 2025 12:50:59 GMT</pubDate><content:encoded>
        &lt;p&gt;&lt;strong&gt;Library/Sources and Management&lt;/strong&gt;&lt;/p&gt;
        &lt;ul&gt;&lt;li&gt;Restore performance of movie addition to the library to v20 (Nexus) level&lt;/li&gt;&lt;/ul&gt;
        </content:encoded><category>Release</category></item>
        """#
}
