import Testing
import Foundation
@testable import DuoUpdaterCore

@Suite("StagedNudgeLedger")
struct StagedNudgeLedgerTests {
    private let chatGPT = "/Applications/ChatGPT.app"

    /// The complaint that produced this type: a staged build the user isn't ready to
    /// relaunch was re-announced by every pass. The same pair is announced once.
    @Test func theSameStagedBuildIsAnnouncedOnce() {
        var ledger = StagedNudgeLedger()
        #expect(ledger.isNew(key: chatGPT, version: "1.2026.238"))
        ledger.record(key: chatGPT, version: "1.2026.238")
        #expect(!ledger.isNew(key: chatGPT, version: "1.2026.238"))
        // Every later pass keeps saying no — this is what replaces the 5-minute timer.
        for _ in 0..<10 { #expect(!ledger.isNew(key: chatGPT, version: "1.2026.238")) }
    }

    /// The other half of the ask: an app that sat un-relaunched for weeks and then
    /// stages a *newer* build has something new to say, so it gets a banner again.
    @Test func aNewStagedBuildIsAnnouncedAgain() {
        var ledger = StagedNudgeLedger()
        ledger.record(key: chatGPT, version: "1.2026.238")
        #expect(ledger.isNew(key: chatGPT, version: "1.2026.245"))
        ledger.record(key: chatGPT, version: "1.2026.245")
        #expect(!ledger.isNew(key: chatGPT, version: "1.2026.245"))
        // Recording the newer build replaced the older entry rather than accumulating.
        #expect(ledger.entries == [chatGPT: "1.2026.245"])
    }

    /// Apps are independent: announcing one must not silence another that happens
    /// to have staged the same version string.
    @Test func appsAreIndependent() {
        var ledger = StagedNudgeLedger()
        ledger.record(key: chatGPT, version: "1.0.0")
        #expect(ledger.isNew(key: "/Applications/Spotify.app", version: "1.0.0"))
    }

    /// Withdrawing the banner withdraws the entry with it, so the build can be
    /// announced again once the user un-hides the app. Without it, ignoring an app
    /// (which clears the delivered banner) and then un-ignoring it would restore the
    /// row and the badge with nothing in Notification Center to match, permanently.
    @Test func forgettingLetsTheSameBuildBeAnnouncedAgain() {
        var ledger = StagedNudgeLedger([chatGPT: "1.2026.238"])
        ledger.forget(key: chatGPT)
        #expect(ledger.isNew(key: chatGPT, version: "1.2026.238"))
        #expect(ledger.entries.isEmpty)
    }

    /// Forgetting one app leaves the others alone.
    @Test func forgettingIsScopedToOneApp() {
        var ledger = StagedNudgeLedger([chatGPT: "1.0", "/Applications/Spotify.app": "2.0"])
        ledger.forget(key: chatGPT)
        #expect(ledger.entries == ["/Applications/Spotify.app": "2.0"])
    }

    /// Uninstalled apps drop out so the persisted map can't grow forever.
    @Test func pruneForgetsAppsThatAreGone() {
        var ledger = StagedNudgeLedger([chatGPT: "1.2026.238", "/Applications/Gone.app": "3.1"])
        ledger.prune(liveKeys: [chatGPT])
        #expect(ledger.entries == [chatGPT: "1.2026.238"])
    }

    /// Pruning is scoped to apps that are gone, not to what is currently staged.
    /// An entry has to survive the moment its staged build is applied and the
    /// staging disappears — otherwise seeing that same build staged once more (a
    /// pass mid-apply, say) would announce it a second time.
    @Test func pruneKeepsAnAppWhoseStagingIsGone() {
        var ledger = StagedNudgeLedger([chatGPT: "1.2026.238"])
        ledger.prune(liveKeys: [chatGPT, "/Applications/Spotify.app"])
        #expect(!ledger.isNew(key: chatGPT, version: "1.2026.238"))
    }

    /// Round-trips through the plain dictionary that `Preferences` persists.
    @Test func survivesAStorageRoundTrip() {
        var ledger = StagedNudgeLedger()
        ledger.record(key: chatGPT, version: "1.2026.238")
        #expect(StagedNudgeLedger(ledger.entries) == ledger)
        #expect(!StagedNudgeLedger(ledger.entries).isNew(key: chatGPT, version: "1.2026.238"))
    }

    /// The ledger's stated invariant — "when the app stages a different build,
    /// that is a new pair and it is announced again" — held only for apps whose
    /// marketing version moves. The caller keyed on `staged.version`, so an app
    /// shipping many builds under one marketing string was announced once and then
    /// silenced: quiet becoming silence, the exact failure the type documents
    /// itself as avoiding. `buildIdentity` is what the caller keys on now.
    @Test func buildIdentityDistinguishesBuildsSharingOneMarketingVersion() {
        func amp(_ build: String?) -> StagedSelfUpdate {
            StagedSelfUpdate(version: "1.0", buildVersion: build,
                             stagedBundlePath: URL(fileURLWithPath: "/tmp/Amp.app"))
        }
        var ledger = StagedNudgeLedger()
        let key = "/Applications/Amp.app"

        // Ten builds, one marketing version — every one is its own announcement.
        for build in ["121", "122", "130"] {
            #expect(ledger.isNew(key: key, version: amp(build).buildIdentity),
                    "build \(build) shares \"1.0\" with the last one and was swallowed")
            ledger.record(key: key, version: amp(build).buildIdentity)
        }
        // ...and the same build still announces only once.
        #expect(!ledger.isNew(key: key, version: amp("130").buildIdentity))

        // A staged bundle with no CFBundleVersion falls back to the marketing
        // string, which is the only identity it has.
        #expect(amp(nil).buildIdentity == "1.0")
    }
}
