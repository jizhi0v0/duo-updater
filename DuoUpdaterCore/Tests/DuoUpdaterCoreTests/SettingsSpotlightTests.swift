import Testing
import Foundation
@testable import DuoUpdaterCore

private let catalog = [
    SettingsSpotlight(id: "runtime-tags", introducedIn: "0.3.77"),
    SettingsSpotlight(id: "older-thing", introducedIn: "0.3.70"),
]

@Test func aFreshInstallIsToldNothingIsNew() {
    // No recorded previous version AND no prior state: the whole app is new to
    // them, so every dot would be noise.
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.77",
        previousVersion: nil, hasPriorHistory: false, acknowledged: []) == [])
}

@Test func anUpgradeFromBeforeTheLedgerExistedStillGetsTold() {
    // The build that introduces this ledger has no previous version recorded — but
    // the install has history, which is what separates it from a first run.
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.77",
        previousVersion: nil, hasPriorHistory: true, acknowledged: [])
        == ["runtime-tags", "older-thing"])
}

@Test func onlySpotlightsNewerThanTheVersionTheyLastRanArePending() {
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.77",
        previousVersion: "0.3.76", hasPriorHistory: true, acknowledged: [])
        == ["runtime-tags"])
}

@Test func nothingIsPendingWhenTheyWereAlreadyOnThisVersion() {
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.77",
        previousVersion: "0.3.77", hasPriorHistory: true, acknowledged: []) == [])
}

@Test func acknowledgedSpotlightsNeverComeBack() {
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.77",
        previousVersion: "0.3.76", hasPriorHistory: true, acknowledged: ["runtime-tags"]) == [])
}

@Test func aSettingThisBuildDoesNotHaveYetIsNeverAnnounced() {
    // Running an older build than a spotlight's version — a downgrade, or a
    // catalog entry written ahead of its release. Pointing at a control that isn't
    // rendered is worse than saying nothing.
    #expect(SettingsSpotlightLedger.pending(
        catalog: catalog, currentVersion: "0.3.76",
        previousVersion: "0.3.70", hasPriorHistory: true, acknowledged: []) == [])
}
