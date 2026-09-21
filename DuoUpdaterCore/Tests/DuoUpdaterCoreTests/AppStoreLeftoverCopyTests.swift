import Foundation
import Testing
@testable import DuoUpdaterCore

/// The AndroMeld shape from 2026-09-21: the vendor renamed AndDrive.app to
/// AndroMeld.app, the store updates the new name, and the old copy stays behind
/// under the same bundle id and product id.
private func store(_ path: String, _ version: String, adam: Int? = 6762439757,
                   bundleID: String = "com.catchingnow.andfiles", mas: Bool = true) -> InstalledApp {
    InstalledApp(
        name: "AndroMeld", bundleID: bundleID, shortVersion: version, buildVersion: nil,
        path: URL(fileURLWithPath: path), isMASApp: mas, sparkleFeedURL: nil,
        appStoreAdamID: adam)
}

private let leftover = store("/Applications/AndDrive.app", "1.9.0")

@Test func theRenamedCopyAtTheTargetIsTheOneTheStoreUpdates() {
    let renamed = store("/Applications/AndroMeld.app", "1.10.0")
    let found = AppStoreLeftoverCopy.sibling(of: leftover, target: "1.10.0", among: [leftover, renamed])
    #expect(found?.path.path == "/Applications/AndroMeld.app")
}

@Test func aSiblingStillBehindTheTargetIsNotTheAnswer() {
    // Both copies old: the store has a real update to install, so this is not
    // the leftover case and the install proceeds.
    let renamed = store("/Applications/AndroMeld.app", "1.9.5")
    #expect(AppStoreLeftoverCopy.sibling(of: leftover, target: "1.10.0", among: [renamed]) == nil)
}

@Test func onlyStoreCopiesOfTheSameProductCount() {
    // A Developer ID build of the same bundle id: the store never writes there.
    #expect(AppStoreLeftoverCopy.sibling(
        of: leftover, target: "1.10.0",
        among: [store("/Applications/AndroMeld.app", "1.10.0", adam: nil, mas: false)]) == nil)
    // A different product id under the same bundle id.
    #expect(AppStoreLeftoverCopy.sibling(
        of: leftover, target: "1.10.0",
        among: [store("/Applications/AndroMeld.app", "1.10.0", adam: 1)]) == nil)
    // A different bundle id.
    #expect(AppStoreLeftoverCopy.sibling(
        of: leftover, target: "1.10.0",
        among: [store("/Applications/Other.app", "2.0", bundleID: "com.example.other")]) == nil)
}

@Test func theRowItselfIsNeverItsOwnSibling() {
    let upToDate = store("/Applications/AndDrive.app", "1.10.0")
    #expect(AppStoreLeftoverCopy.sibling(of: upToDate, target: "1.10.0", among: [upToDate]) == nil)
}

private func row(_ app: InstalledApp, latest: String) -> UpdateResult {
    let remote = RemoteVersion(
        shortVersion: latest, version: nil, downloadURL: nil, sourceName: "App Store")
    let current = !VersionComparator.isNewer(latest, than: app.shortVersion ?? "0")
    return UpdateResult(
        app: app, remote: remote,
        status: current ? .upToDate : .updateAvailable(latest: latest))
}

/// The list as the popover had it on 2026-09-21: the renamed copy current, the
/// old one offering an update that could only reinstall the renamed copy.
@Test func theLeftoverRowIsAnOrphanAndTheRenamedOneIsNot() {
    let renamed = store("/Applications/AndroMeld.app", "1.10.0")
    let orphans = AppStoreLeftoverCopy.orphans(
        in: [row(leftover, latest: "1.10.0"), row(renamed, latest: "1.10.0")])
    #expect(orphans.count == 1)
    #expect(orphans[leftover.id]?.path.path == "/Applications/AndroMeld.app")
}

/// Only a row that is offering an update can be an orphan: two copies that are
/// both current, or both behind, are left exactly as they were.
@Test func noOrphanWhenNoRowIsStuck() {
    let renamed = store("/Applications/AndroMeld.app", "1.9.5")
    #expect(AppStoreLeftoverCopy.orphans(
        in: [row(leftover, latest: "1.10.0"), row(renamed, latest: "1.10.0")]).isEmpty)
}

/// The rung: an orphan never reaches the Update button, and says which copy the
/// updates go to instead. Without the sibling the same facts offer Update.
@Test func anOrphanRowStatesWhereItsUpdatesGoInsteadOfOfferingOne() {
    let store = UpdateRoute.appStore(managedHere: false, gate: .none)
    var facts = RowActionFacts(
        status: .updateAvailable(latest: "1.10.0"), isMASApp: true, route: store)
    #expect(RowAction.state(for: facts) == .updateAvailable(store))
    facts.orphanedStoreSibling = ("AndroMeld.app", "1.10.0")
    let state = RowAction.state(for: facts)
    #expect(state == .orphanedStoreCopy(updatedCopy: "AndroMeld.app", version: "1.10.0"))
    #expect(state.needsExplanation)
}
