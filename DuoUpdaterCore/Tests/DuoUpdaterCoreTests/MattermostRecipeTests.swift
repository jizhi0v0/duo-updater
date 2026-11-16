import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite(.serialized)
struct MattermostRecipeTests {
    private let bundleID = "Mattermost.Desktop"

    private func rules() -> [GitHubReleaseRule] {
        GitHubReleaseRegistry.rules.filter { $0.bundleID == bundleID }
    }

    private func rcRecipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID && $0.channel == .rc })
    }

    @Test func nightlyRegistryIncludesEachSupportedCopyGroupAndOnlySignedInstallerRoutes() {
        let rules = GitHubReleaseRegistry.rules.filter { $0.owner == "mattermost" && $0.repo == "desktop" }
        #expect(Set(rules.map(\.recipeID)) == [
            "github:mattermost/desktop:stable",
            "github:mattermost/desktop:stable:legacy-electron", "github:mattermost/desktop:stable:legacy-mattermost"])
        #expect(Set(rules.filter { $0.installAssetPattern != nil }.map(\.recipeID)) == [
            "github:mattermost/desktop:stable"])
        let probes = VendorProbeRegistry.recipes.filter { $0.bundleID == bundleID }
        #expect(Set(probes.map(\.recipeID)) == ["vendor:Mattermost.Desktop:rc"])
        #expect(probes.first?.channel == .rc)
        #expect(probes.first?.install != nil)
        #expect(probes.first?.url.absoluteString == "https://releases.mattermost.com/desktop/rc.txt")
        let ids = Set([bundleID, "com.electron.electron-mattermost", "com.electron.mattermost"])
        #expect(Set(ChangelogRecipeRegistry.recipes.filter { ids.contains($0.bundleID) }.map(\.recipeID)) == [
            "changelog:Mattermost.Desktop:stable", "changelog:com.electron.electron-mattermost:stable",
            "changelog:com.electron.mattermost:stable"])
    }

    @Test func stableTagsAndRCFeedResponsesStayOnTheirOwnTracks() throws {
        let stable = try #require(rules().first { $0.channel == .stable })
        let rc = try rcRecipe()
        for tag in ["v6.4.0", "4.3.2", "v7.0.0", "v7.1"] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern) != nil)
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rc.versionPattern) == nil)
        }
        for tag in ["v6.1.0-rc.4", "v5.0.0-rc1"] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern) == nil)
        }
        for version in ["6.2.5-rc.5", "6.1.0-rc.4", "5.0.0-rc1"] {
            #expect(VendorProbeRecipe.extractVersion(from: "\(version)\n", pattern: rc.versionPattern) == version)
        }
        for body in ["6.4.0", "6.2.5-rc.5-extra", "6.2.5-rc.5\nunrelated"] {
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: rc.versionPattern) == nil)
        }
        for tag in ["v6.4.0-beta.1", "v6.4.0-extra", "latest"] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: stable.versionPattern) == nil)
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rc.versionPattern) == nil)
        }
        let stablePattern = try #require(stable.installAssetPattern)
        func matches(_ name: String, _ pattern: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(matches("mattermost-desktop-6.4.0-mac-arm64.zip", stablePattern))
        #expect(matches("mattermost-desktop-5.13.8-mac-m1.zip", stablePattern))
        for name in ["mattermost-desktop-6.4.0-mac-x64.zip", "mattermost-desktop-6.4.0-mac-arm64.dmg",
                     "mattermost-desktop-6.4.0-mac-arm64.zip.blockmap", "mattermost-desktop-6.1.0-rc.4-mac-arm64.zip"] {
            #expect(!matches(name, stablePattern))
        }
    }

    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var requested: [String] = []
        static func reset() { lock.lock(); requested = []; lock.unlock() }
        static var paths: [String] { lock.lock(); defer { lock.unlock() }; return requested }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let path = request.url!.path
            Self.lock.lock(); Self.requested.append(path); Self.lock.unlock()
            let body: String
            switch path {
            case "/repos/mattermost/desktop/releases/latest": body = Self.release("6.4.0")
            case "/desktop/rc.txt": body = "6.2.5-rc.5\n"
            default: body = "{}"
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: body == "{}" ? 404 : 200,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
        private static func release(_ version: String) -> String {
            let name = "mattermost-desktop-\(version)-mac-arm64.zip"
            return """
            {"tag_name":"v\(version)","prerelease":\(version.contains("-rc")),"draft":false,
             "html_url":"https://github.com/mattermost/desktop/releases/tag/v\(version)",
             "published_at":"2026-02-19T21:08:50Z",
             "assets":[{"name":"\(name)","size":113761398,
             "browser_download_url":"https://github.com/mattermost/desktop/releases/download/v\(version)/\(name)"}]}
            """
        }
    }

    private func session() -> URLSession {
        FixtureProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func source() -> GitHubReleasesSource {
        return GitHubReleasesSource(rules: GitHubReleaseRegistry.rules.filter { $0.repo == "desktop" && $0.owner == "mattermost" },
                                    session: session())
    }
    private func app(_ version: String, bundleID: String = "Mattermost.Desktop") -> InstalledApp {
        InstalledApp(name: "Mattermost", bundleID: bundleID, shortVersion: version, buildVersion: version,
                     path: URL(fileURLWithPath: "/Applications/Mattermost.app"),
                     isMASApp: false, isToolboxManaged: false, sparkleFeedURL: nil,
                     releaseChannel: ReleaseChannel.detect(
                        name: "Mattermost", bundleID: bundleID, keystoneChannel: nil, version: version))
    }

    @Test func publishedRCVersionSuffixIsLocalAndScopedToMattermost() {
        for version in ["6.1.0-rc.4", "5.0.0-rc1"] {
            #expect(app(version).releaseChannel == .rc)
            #expect(app(version, bundleID: "com.deepseek.dsh").releaseChannel == .stable)
        }
        for version in ["6.4.0", "6.1.0", "6.1.0-rc", "6.1.0-rc.4+build", "6.1.0-rc.4.extra"] {
            #expect(app(version).releaseChannel == .stable)
        }
    }

    @Test func anRCInstallWithNoGitHubTagReadsOnlyTheOfficialRCFeed() async throws {
        let installed = app("6.1.0-rc.4")
        #expect(installed.releaseChannel == .rc)
        let gitHub = source()
        #expect(try await gitHub.latestVersion(for: installed) == nil)
        #expect(FixtureProtocol.paths.isEmpty)
        let vendor = VendorProbeSource(recipes: [try rcRecipe()], session: session())
        let remote = try #require(try await vendor.latestVersion(for: installed))
        #expect(remote.displayVersion == "6.2.5-rc.5")
        #expect(UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: "6.2.5-rc.5"))
            .effectiveReleaseChannel == .rc)
        #expect(remote.vendorInstallerKind == .zip)
        #expect(!remote.requiresManualInstaller)
        #expect(remote.downloadURL?.absoluteString
                == "https://releases.mattermost.com/desktop/6.2.5-rc.5/mattermost-desktop-6.2.5-rc.5-mac-arm64.zip")
        // Exact-tag endpoints all answer 404; the current vendor RC need not
        // have a GitHub release at all. There is no stable /latest fallback.
        #expect(FixtureProtocol.paths == ["/desktop/rc.txt"])
        #expect(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .rc) == nil)
    }

    @Test func stableInstallUsesStableZIPWithoutAnExactTagRequest() async throws {
        let remote = try #require(try await source().latestVersion(for: app("6.3.2")))
        #expect(remote.displayVersion == "6.4.0")
        #expect(remote.releaseChannel == .stable)
        #expect(remote.downloadURL?.lastPathComponent == "mattermost-desktop-6.4.0-mac-arm64.zip")
        #expect(FixtureProtocol.paths == ["/repos/mattermost/desktop/releases/latest"])
    }

    @Test func unsignedLegacyBundleIDsDetectStableWithoutAnInstaller() async throws {
        for id in ["com.electron.electron-mattermost", "com.electron.mattermost"] {
            let remote = try #require(try await source().latestVersion(for: app("1.0.0", bundleID: id)))
            #expect(remote.displayVersion == "6.4.0")
            #expect(remote.requiresManualInstaller)
            #expect(remote.vendorInstallerKind == nil)
            #expect(ChangelogRecipeRegistry.recipe(forBundleID: id, channel: .stable) != nil)
        }
    }

    @Test func signedOldIDUsesCurrentRulesWithinTheObservedMigrationBound() async throws {
        let installed = app("4.1.0", bundleID: "com.mattermost.desktop")
        #expect(installed.recipeBundleID == bundleID)
        let remote = try #require(try await source().latestVersion(for: installed))
        #expect(remote.displayVersion == "6.4.0")
        #expect(remote.vendorInstallerKind == .zip)
        #expect(BundleIDMigration.migration(
            installed: "com.mattermost.desktop", downloaded: bundleID, installedVersion: "4.1.0",
            installedTeam: "UQ8HT4Q2XM", downloadedTeam: "UQ8HT4Q2XM") != nil)
        #expect(BundleIDMigration.migration(
            installed: "com.mattermost.desktop", downloaded: bundleID, installedVersion: "4.1.0",
            installedTeam: "OTHERTEAM", downloadedTeam: "UQ8HT4Q2XM") == nil)
        #expect(app("6.3.2", bundleID: "com.mattermost.desktop").recipeBundleID == "com.mattermost.desktop")
    }

    @Test func vendorNotesKeepPatchesSeparateFromTheBaseReleaseAndRetainHeadings() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .stable))
        let fixture = """
        ## Release v6.4
        **v6.4.0 release day: 2026-11-16**
        **Download Binaries:** [Mattermost Desktop on GitHub](https://github.com/mattermost/desktop/releases/latest)
        ### Bug Fixes
        #### macOS
        - Fixed keyboard shortcuts so that ``Cmd+W`` targets windows other than the main window when one of those windows is focused.
        #### All Platforms
        - Fixed an issue where servers configured with a subpath could show a &quot;Team not found&quot; error in some cases.
        ## Release v6.3
        - **v6.3.2, released 2026-11-02**
          - Upgraded to Electron v43.8.3.
        - **v6.3.1, released 2026-10-15**
          - Updated file download finalization handling for saved downloads.
        - **v6.3.0, released 2026-08-14**
          - Original v6.3.0 release
        **Download Binaries:** [Mattermost Desktop on GitHub](https://github.com/mattermost/desktop/releases/v6.3.2)
        ### Improvements
        #### All Platforms
        - Added koffi native module, and added connectors for macOS and Windows native session attributes.
        """
        let changelog = try #require(ChangelogExtractor.extract(from: fixture, using: recipe))
        #expect(changelog.entries.map(\.version) == ["6.4.0", "6.3.2", "6.3.1", "6.3.0"])
        #expect(changelog.entries.map(\.date) == ["2026-11-16", "2026-11-02", "2026-10-15", "2026-08-14"])
        #expect(changelog.entries[0].content.contains(.heading("macOS")))
        #expect(changelog.entries[0].content.contains(.heading("All Platforms")))
        #expect(changelog.entries[0].items[0].contains("Cmd+W"))
        #expect(changelog.entries[0].items[1].contains("\"Team not found\""))
        #expect(changelog.entries[1].items == ["Upgraded to Electron v43.8.3."])
        #expect(changelog.entries[3].items.count == 1)
        #expect(!changelog.entries.flatMap(\.items).contains { $0.contains("Download Binaries") || $0.contains("Original v") })
    }
}
