import Foundation
import Testing
@testable import DuoUpdaterCore

struct PrivateInternetAccessProbeTests {
    private static let bundleID = "com.privateinternetaccess.vpn"
    private static let currentArchive = "https://installers.privateinternetaccess.com/download/pia-macos-3.8-08539.zip"
    private static let currentDigest = "824b5a469a7e42a634e98f140e6d31d567d564c8edaa78ebb6b05f0de311008e"

    // Trimmed from the current vendor page, with article order reversed.
    private static let changelog = #"""
    <article class="changelog-release">
      <a class="list-group-item" href="https://installers.privateinternetaccess.com/download/pia-macos-3.7.2-08420.zip">Mac</a>
      <h3 class="text-primary" style="margin-bottom:0px">v3.7.2</h3>
      <p class="sha256">pia-macos-3.7.2-08420.zip:<span class="code">5677fa6fd8ccc1a3d31d568e7c00a99c0887797b359a1db07d75e1de77f4fb0a</span></p>
    </article>
    <article class="changelog-release">
      <a class="list-group-item" href="\#(currentArchive)">Mac</a>
      <h3 class="text-primary" style="margin-bottom:0px">v3.8.0</h3>
      <p class="sha256">pia-macos-3.8-08539.zip:<span class="code">\#(currentDigest)</span></p>
    </article>
    """#

    // Trimmed from the desktop beta endpoint. Linux comes before macOS.
    private static let betaFeed = #"""
    {"latest_version_piax":{"linux_arm64":{"version":"3.6.1-beta.2+08337","download":"https://privateinternetaccess-storage.s3.amazonaws.com/pub/pia_desktop/builds/pia-linux-arm64-3.6.1-beta.2-08337.run"},"mac":{"version":"3.6.1-beta.2+08337","download":"https://privateinternetaccess-storage.s3.amazonaws.com/pub/pia_desktop/builds/pia-macos-3.6.1-beta.2-08337.zip","required":"10.14.0"}}}
    """#

    @Test func officialStableArchiveAndDigestComeFromTheWinningArticle() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.changelog)
        defer { server.stop() }
        let recipe = try Self.recipe(channel: .stable)
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "3.8.0")
        #expect(remote.downloadURL?.absoluteString == Self.currentArchive)
        #expect(remote.expectedSHA256 == Self.currentDigest)
        #expect(remote.requiresManualInstaller)
        #expect(remote.vendorInstallerApp?.bundleIdentifier == Self.bundleID)
        #expect(outcome.warnings.isEmpty)
    }

    @Test func aMissingMacDigestCannotReuseTheOneFromAnotherRelease() async throws {
        let body = Self.changelog.replacingOccurrences(of: Self.currentDigest, with: "")
        let server = try RecipeVerificationTests.StubServer(body: body)
        defer { server.stop() }
        let recipe = try Self.recipe(channel: .stable)
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "3.8.0")
        #expect(remote.vendorInstallerApp == nil)
        #expect(remote.expectedSHA256 == nil)
    }

    @Test func betaOptInUsesTheNewerOfGAAndTheMacBeta() async throws {
        let stable = try RecipeVerificationTests.StubServer(body: Self.changelog)
        defer { stable.stop() }
        let oldBeta = try RecipeVerificationTests.StubServer(body: Self.betaFeed)
        defer { oldBeta.stop() }
        let newerBetaBody = Self.betaFeed.replacingOccurrences(
            of: #""mac":{"version":"3.6.1-beta.2+08337""#,
            with: #""mac":{"version":"3.9.0-beta.1+08540""#)
        let newerBeta = try RecipeVerificationTests.StubServer(body: newerBetaBody)
        defer { newerBeta.stop() }

        let ga = try Self.recipe(channel: .beta).with(url: stable.url)
        let beta = try Self.recipe(channel: .beta, variant: "beta-feed")
        let app = InstalledApp(name: "Private Internet Access", bundleID: Self.bundleID,
            shortVersion: "3.7.2", buildVersion: "3.7.2",
            path: URL(fileURLWithPath: "/Applications/Private Internet Access.app"),
            isMASApp: false, sparkleFeedURL: nil, releaseChannel: .beta)
        let gaRemote = try #require(try await VendorProbeSource(recipes: [ga, beta.with(url: oldBeta.url)])
            .latestVersion(for: app))
        #expect(gaRemote.shortVersion == "3.8.0")
        #expect(gaRemote.vendorInstallerApp != nil)

        let betaRemote = try #require(try await VendorProbeSource(recipes: [ga, beta.with(url: newerBeta.url)])
            .latestVersion(for: app))
        #expect(betaRemote.shortVersion == "3.9.0-beta.1")
        #expect(betaRemote.vendorInstallerApp == nil)
    }

    @Test func aHomebrewCopyKeepsItsExistingUpdatePath() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.changelog)
        defer { server.stop() }
        let vendor = VendorProbeSource(recipes: [
            try Self.recipe(channel: .stable).with(url: server.url),
        ])
        let app = InstalledApp(name: "Private Internet Access", bundleID: Self.bundleID,
            shortVersion: "3.7.2", buildVersion: "3.7.2",
            path: URL(fileURLWithPath: "/Applications/Private Internet Access.app"),
            isMASApp: false, sparkleFeedURL: nil)
        let direct = await UpdateChecker(sources: [vendor]).check(app)
        #expect(direct.remote?.vendorInstallerApp != nil)

        let cask = await UpdateChecker(sources: [CurrentCask(), vendor]).check(app)
        #expect(cask.remote?.sourceName == "Homebrew")
        #expect(cask.homebrewSourceIdentifier == "private-internet-access")
        #expect(cask.status == .upToDate)
    }

    private struct CurrentCask: UpdateSource {
        let name = "Homebrew"

        func latestVersion(for app: InstalledApp) async throws -> RemoteVersion? {
            var remote = RemoteVersion(shortVersion: "3.7.2", version: nil, downloadURL: nil,
                sourceName: name, sourceIdentifier: "private-internet-access")
            remote.homebrewSelfUpdating = true
            return remote
        }
    }

    @Test(arguments: [
        ("{}", ReleaseChannel.stable),
        (#"{"updateChannel":"release","betaUpdateChannel":"beta","offerBetaUpdates":true}"#, .beta),
        (#"{"updateChannel":"release","betaUpdateChannel":"qa_beta","offerBetaUpdates":false}"#, .stable),
        (#"{"updateChannel":"qa_release","offerBetaUpdates":true}"#, .undetermined),
        (#"{"updateChannel":"","offerBetaUpdates":false}"#, .undetermined),
        (#"{"updateChannel":"release","betaUpdateChannel":"qa_beta","offerBetaUpdates":true}"#, .undetermined),
        (#"{"offerBetaUpdates":"true"}"#, .undetermined),
    ])
    func resolveTheVendorsUpdateSettings(input: String, expected: ReleaseChannel) {
        let resolution = PrivateInternetAccessChannel.resolve(settings: Data(input.utf8))
        #expect(resolution.channel == expected)
    }

    private static func recipe(channel: ReleaseChannel, variant: String? = nil) throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first {
            $0.bundleID == bundleID && $0.channel == channel && $0.variant == variant
        })
    }
}
