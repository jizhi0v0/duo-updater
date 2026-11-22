import Foundation
import Testing
@testable import DuoUpdaterCore

struct McBopomofoProbeTests {
    private static let bundleID = "org.openvanilla.inputmethod.McBopomofo"
    private static let archive = "https://github.com/openvanilla/McBopomofo/releases/download/3.1.1/McBopomofo-Installer-3.1.1.zip"
    private static let digest = "7e6ae8b717d2c36cbd11a4ad0d23cb8dbaeb6b9e6c48b2de1c4f83655203827a"

    // The installer asset fields from GitHub's latest release response.
    private static let release = #"""
    {
      "tag_name": "3.1.1",
      "assets": [
        {
          "url": "https://api.github.com/repos/openvanilla/McBopomofo/releases/assets/540762105",
          "name": "McBopomofo-Installer-3.1.1.zip",
          "digest": "sha256:\#(digest)",
          "browser_download_url": "\#(archive)"
        }
      ]
    }
    """#

    @Test func anExplicitHandoffIsAvailableOnlyAtTheVendorsUserPath() async throws {
        let outcome = try await Self.probe(Self.release)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "3.1.1")
        #expect(remote.downloadURL?.absoluteString == Self.archive)
        #expect(remote.expectedSHA256 == Self.digest)
        #expect(remote.vendorInstallerApp?.bundleIdentifier == "org.openvanilla.McBopomofo.McBopomofoInstaller")
        #expect(outcome.warnings.isEmpty)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let destination = home.appendingPathComponent("Library/Input Methods/McBopomofo.app")
        let paths = [
            destination,
            URL(fileURLWithPath: "/Library/Input Methods/McBopomofo.app"),
            home.appendingPathComponent("Library/Input Methods/McBopomofo Copy.app"),
        ]
        let environment = InstallEnvironment(isHelperEnabled: true, runningAppPaths: [],
            stagedSelfUpdates: [:], packageInstallerAvailable: true)
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
        for path in paths {
            let app = InstalledApp(name: "McBopomofo", bundleID: Self.bundleID,
                shortVersion: "3.1", buildVersion: "3.1", path: path, isMASApp: false, sparkleFeedURL: nil)
            let result = UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: "3.1.1"))
            #expect(UpdatePolicy.requiresInstaller(result, environment: environment) == (path == destination))
            #expect(!UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
        }
    }

    @Test func aDigestOnAnotherAssetCannotAuthorizeTheInstaller() async throws {
        let body = Self.release.replacingOccurrences(
            of: #""digest": "sha256:\#(Self.digest)","#, with: "")
            .replacingOccurrences(of: #""assets": ["#, with: #"""
            "assets": [
                {
                  "url": "https://api.github.com/repos/openvanilla/McBopomofo/releases/assets/513099",
                  "name": "AnotherAsset.zip",
                  "digest": "sha256:\#(Self.digest)",
                  "browser_download_url": "https://github.com/openvanilla/McBopomofo/releases/download/3.1.1/AnotherAsset.zip"
                },
            """#)
        let outcome = try await Self.probe(body)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "3.1.1")
        #expect(remote.vendorInstallerApp == nil)
    }

    private static func probe(_ body: String) async throws -> ProbeOutcome {
        let fixture = try RecipeVerificationTests.StubServer(body: body)
        defer { fixture.stop() }
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID })
        return await VendorProbeSource().probeDiagnostic(recipe.with(url: fixture.url))
    }
}
