import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticUpdateChoicesTests {
    @Test func awaitingRelaunchDoesNotRemoveTheSavedPolicyControl() {
        let remote = RemoteVersion(shortVersion: "27.3.2", version: "851", downloadURL: nil, sourceName: "Sparkle")
        #expect(!AutomaticUpdateChoices.canConfigure(remote: remote, installable: false))
        #expect(AutomaticUpdateChoices.canConfigure(remote: remote, installable: false, awaitingRelaunch: true))
    }

    @Test func subscriptionWithoutAnOfferStillAllowsSavingAPolicy() {
        let remote = RemoteVersion(shortVersion: "27.3.0", version: "843", downloadURL: nil,
            sourceName: "Sparkle", subscriptionHold: SubscriptionHold(version: "27.3.2", coveredBefore: nil))
        #expect(AutomaticUpdateChoices.canConfigure(remote: remote, installable: false))
        // Saving a policy does not manufacture an installable offer.
        #expect(remote.downloadURL == nil)
    }

    @Test func manualRoutesAndOtherRefusalsStayOutsidePolicyColumns() {
        for source in ["Homebrew", "App Store", "Sparkle", "Vendor"] {
            let remote = RemoteVersion(shortVersion: nil, version: "1", downloadURL: nil, sourceName: source)
            #expect(!AutomaticUpdateChoices.canConfigure(remote: remote, installable: false))
        }
        let package = RemoteVersion(shortVersion: nil, version: "1", downloadURL: URL(string: "https://example.com/app.pkg"),
            sourceName: "Sparkle", subscriptionHold: SubscriptionHold(version: "2", coveredBefore: nil))
        #expect(!AutomaticUpdateChoices.canConfigure(remote: package, installable: false))
        #expect(AutomaticUpdateChoices.canConfigure(remote: nil, installable: nil))
        #expect(AutomaticUpdateChoices.canConfigure(remote: nil, installable: true))
    }

    private func isolated(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "automatic-choice-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func aConfirmedDefaultSurvivesReloadAndNewRecommendations() throws {
        try isolated { defaults in
            var choices = AutomaticUpdateChoices(defaults: defaults)
            #expect(choices.explicitMode(key: "path", legacyKey: "id") == nil)
            #expect(choices.setupMode(key: "path", legacyKey: "id", suggested: false) == .whenClosed)
            choices.set(.whenClosed, key: "path", legacyKey: "id")
            choices.save(to: defaults)
            let reloaded = AutomaticUpdateChoices(defaults: defaults)
            #expect(reloaded.explicitMode(key: "path", legacyKey: "id") == .whenClosed)
            #expect(reloaded.setupMode(key: "path", legacyKey: "id", suggested: true) == .whenClosed)
            #expect(reloaded.explicitMode(key: "another-copy", legacyKey: "id") == nil)
        }
    }

    @Test func oldChoicesKeepExclusionPrecedenceAndDoNotGrantNewPermission() throws {
        try isolated { defaults in
            defaults.set(["path", "other-id"], forKey: AutomaticUpdateChoices.runningKey)
            defaults.set(["id"], forKey: AutomaticUpdateChoices.excludedKey)
            let choices = AutomaticUpdateChoices(defaults: defaults)
            #expect(choices.explicitMode(key: "path", legacyKey: "id") == .never)
            #expect(choices.explicitMode(key: "other-path", legacyKey: "other-id") == .alsoWhenRunning)
            #expect(choices.explicitMode(key: "unset", legacyKey: "unset-id") == nil)
            #expect(choices.setupMode(key: "unset", legacyKey: "unset-id", suggested: false) == .whenClosed)
        }
    }

    @Test func anExplicitChangeClearsLegacyStateAndRenameCarriesIt() throws {
        try isolated { defaults in
            defaults.set(["id"], forKey: AutomaticUpdateChoices.excludedKey)
            var choices = AutomaticUpdateChoices(defaults: defaults)
            choices.set(.alsoWhenRunning, key: "old", legacyKey: "id")
            #expect(choices.explicitMode(key: "old", legacyKey: "id") == .alsoWhenRunning)
            choices.set(.whenClosed, key: "old", legacyKey: "id")
            choices.migrate(from: "old", to: "new")
            choices.save(to: defaults)
            let reloaded = AutomaticUpdateChoices(defaults: defaults)
            #expect(reloaded.explicitMode(key: "new", legacyKey: "id") == .whenClosed)
            #expect(reloaded.explicitMode(key: "old", legacyKey: "id") == nil)
            #expect(reloaded.running.isEmpty && reloaded.excluded.isEmpty)
        }
    }

    @Test func invalidOrIncompleteObservationsNeverBecomeRecommendations() throws {
        try isolated { defaults in
            defaults.set(Data("{bad json".utf8), forKey: AutomaticUpdateChoices.observationsKey)
            #expect(AutomaticUpdateChoices.observations(from: defaults).isEmpty)
            defaults.set(Data(#"{"path":{"bundleID":"test.app"}}"#.utf8), forKey: AutomaticUpdateChoices.observationsKey)
            #expect(AutomaticUpdateChoices.observations(from: defaults).isEmpty)
        }
    }
}
