import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct OneSwitchRecipeTests {
    private let bundleID = "studio.fireball.OneSwitch"
    private let feed = "https://fireball.studio/api/release_manager/studio.fireball.OneSwitchOfficial.xml"
    private let notes = "https://fireball.studio/api/release_manager/releasenotes"

    @Test func onlyARealBooleanTrueEnablesBeta() {
        #expect(studio_fireball_OneSwitch.enablesBeta(kCFBooleanTrue))
        #expect(!studio_fireball_OneSwitch.enablesBeta(kCFBooleanFalse))
        #expect(!studio_fireball_OneSwitch.enablesBeta(nil))
        #expect(!studio_fireball_OneSwitch.enablesBeta(NSNumber(value: 2)))
        #expect(!studio_fireball_OneSwitch.enablesBeta("true" as NSString))
    }

    private func offer(
        from installed: String?, to offered: String?, source: String = "Sparkle",
        installedID: String? = nil, provenMarketing: Bool = true, package: Bool = false
    ) -> UpdateResult {
        let app = InstalledApp(
            name: "One Switch", bundleID: installedID ?? bundleID, shortVersion: installed,
            buildVersion: "429", path: URL(fileURLWithPath: "/Applications/One Switch Fixture.app"),
            isMASApp: false, sparkleFeedURL: URL(string: feed),
            sparkleEdPublicKey: "fixture-key")
        let remote = RemoteVersion(
            shortVersion: offered, version: "462", marketingMatchesBundle: provenMarketing,
            downloadURL: URL(string: "https://example.invalid/one-switch.zip"),
            edSignature: "fixture-signature", sourceName: source, sparklePackageEnclosure: package)
        return UpdateResult(app: app, remote: remote, status: .updateAvailable(latest: offered ?? "462"))
    }

    @Test func oneClickGateKeepsOnlyTheProtectedSparkleMigrationWithTheVendor() async throws {
        let settings = UpdateSettings(appStoreUpdateStrategy: .full, vendorInstallPolicy: .alwaysOverwrite)
        let environment = InstallEnvironment(isHelperEnabled: false, runningAppPaths: [], stagedSelfUpdates: [:])
        let migration = offer(from: "1.35.2", to: "2.0")
        let gate = try #require(OneClickGateRegistry.withholding(migration.app, offering: migration.remote))
        #expect(migration.nativeUpdaterRequirementReason == gate.reason)
        #expect(migration.remote?.downloadURL != nil)
        #expect(!UpdatePolicy.canAutoInstall(migration, settings: settings, environment: environment))
        #expect(UpdatePolicy.defersToSelfUpdater(migration, settings: settings, environment: environment))

        let coordinator = InstallCoordinator(permits: InstallPermits(downloads: 1, applies: 1))
        await #expect(throws: OneClickGateRegistry.Withheld.self) {
            _ = try await coordinator.perform(
                migration, route: .sparkle, installedPopulation: [migration.app],
                digestOnlyAllowed: false, progress: { _ in })
        }

        let packageMigration = offer(from: "1.35.2", to: "2.0", package: true)
        #expect(!UpdatePolicy.requiresInstaller(packageMigration, environment: environment))

        for result in [offer(from: "1.35.2", to: "1.35.4"), offer(from: "2.0", to: "2.1")] {
            #expect(OneClickGateRegistry.withholding(result.app, offering: result.remote) == nil)
            #expect(UpdatePolicy.canAutoInstall(result, settings: settings, environment: environment))
            #expect(!UpdatePolicy.defersToSelfUpdater(result, settings: settings, environment: environment))
        }
        for result in [
            offer(from: "1.35.2", to: "2.0", source: "Homebrew"),
            offer(from: "1.35.2", to: "2.0", source: "Setapp"),
            offer(from: "1.35.2", to: "2.0", installedID: bundleID + "-setapp"),
        ] {
            #expect(OneClickGateRegistry.withholding(result.app, offering: result.remote) == nil)
        }
    }

    @Test func sparkleMigrationGateFailsClosedForUnprovenVersionIdentity() {
        for result in [
            offer(from: nil, to: "2.0"),
            offer(from: "2.0/injected", to: "2.1"),
            offer(from: "1.35.2", to: nil),
            offer(from: "1.35.2", to: "2.0\n1.35.4"),
            offer(from: "2.0", to: "2.1", provenMarketing: false),
        ] {
            #expect(OneClickGateRegistry.withholding(result.app, offering: result.remote) != nil)
        }
    }

    @Test func betaPreferenceAloneCanChooseThePreviewFeed() throws {
        let stable = try #require(studio_fireball_OneSwitch.resolve(includeBeta: false))
        #expect(stable.channel == .stable)
        #expect(stable.feedOverride?.absoluteString == feed)
        let beta = try #require(studio_fireball_OneSwitch.resolve(includeBeta: true))
        #expect(beta.channel == .beta)
        #expect(beta.feedOverride?.absoluteString == feed + "?beta=1")
        #expect(studio_fireball_OneSwitch.resolve(
            includeBeta: true, declaredFeed: URL(string: feed)) == beta)
        #expect(studio_fireball_OneSwitch.resolve(
            includeBeta: true, declaredFeed: URL(string: "https://fireball.studio/other-appcast.xml")) == nil)
        #expect(!ChannelBinding.boundBundleIDs.contains(bundleID.lowercased() + "-setapp"))

        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .beta))
        #expect(recipe.source == beta.feedOverride)
        let betaNotes = URL(string: "\(notes)/462/en/studio.fireball.OneSwitchOfficial.xml")
        #expect(recipe.acceptedFeedPage(betaNotes) == betaNotes)
    }

    @Test func officialFeedKeepsTheAppcastBuildAndLanguage() throws {
        let officialFeed = try #require(studio_fireball_OneSwitch.resolve(includeBeta: false)?.feedOverride)
        #expect(officialFeed.absoluteString == feed)

        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .stable))
        #expect(recipe.source == officialFeed)
        let appcast = """
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
        <channel><item>
          <title>440</title>
          <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
          <sparkle:releaseNotesLink xml:lang="zh-Hans">\(notes)/440/zh-Hans/studio.fireball.OneSwitchOfficial.xml</sparkle:releaseNotesLink>
          <sparkle:releaseNotesLink xml:lang="en">\(notes)/440/en/studio.fireball.OneSwitchOfficial.xml</sparkle:releaseNotesLink>
          <enclosure url="https://fireball.studio/api/release_manager/downloads/studio.fireball.OneSwitchOfficial/440.zip"
            sparkle:version="440" sparkle:shortVersionString="1.35.4"/>
        </item></channel></rss>
        """
        for (preference, locale) in [("en-US", "en"), ("zh-Hans-CN", "zh-Hans")] {
            let item = try #require(SparkleAppcastParser.parse(
                Data(appcast.utf8), preferredLanguages: [preference]).first)
            let accepted = recipe.acceptedFeedPage(item.releaseNotesLink)
            #expect(accepted?.absoluteString == "\(notes)/440/\(locale)/studio.fireball.OneSwitchOfficial.xml")
            #expect(item.version == "440")
            #expect(item.shortVersionString == "1.35.4")
        }
        let otherEdition = URL(string: "\(notes)/440/en/studio.fireball.OneSwitchSetapp.xml")
        #expect(recipe.acceptedFeedPage(otherEdition) == nil)
    }

    @Test func latestProsePageBecomesAChangelogEntry() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
        let html = #"""
        <!DOCTYPE html>
        <html><head><title>One Switch Official</title></head>
        <body><div class="content">
        <p>The &quot;Do Not Disturb&quot; feature is now working on macOS 15 and macOS 26.</p>
        </div></body></html>
        """#
        let entries = try #require(ChangelogExtractor.extract(from: html, using: recipe)?.entries)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.title == "One Switch Official")
        #expect(entry.items == [#"The "Do Not Disturb" feature is now working on macOS 15 and macOS 26."#])
    }

    @Test func precedingReleasePreservesSectionHeadings() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID))
        let html = #"""
        <!DOCTYPE html>
        <html><head><title>One Switch Official</title></head>
        <body><div class="content">
        <p>1.35.2 Update:</p>
        <ul><li>Screen Clean: Resolve the appearance issue of the Exit Button in dark mode.</li></ul>
        <p>Recent Update：</p>
        <ul><li>Adapted and optimized for macOS 26.</li></ul>
        </div></body></html>
        """#
        let entry = try #require(ChangelogExtractor.extract(from: html, using: recipe)?.entries.first)
        #expect(entry.content == [
            .heading("1.35.2 Update:"),
            .note("Screen Clean: Resolve the appearance issue of the Exit Button in dark mode."),
            .heading("Recent Update："),
            .note("Adapted and optimized for macOS 26."),
        ])
    }
}
