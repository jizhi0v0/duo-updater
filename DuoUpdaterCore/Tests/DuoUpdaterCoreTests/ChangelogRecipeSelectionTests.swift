import Foundation
import Testing
@testable import DuoUpdaterCore

struct ChangelogRecipeSelectionTests {
    private func app(store: Bool, bundleID: String = "com.tencent.xinWeChat",
                     version: String = "4.0") -> InstalledApp {
        InstalledApp(name: "Fixture", bundleID: bundleID, shortVersion: version,
                     buildVersion: "100", path: URL(fileURLWithPath: "/Applications/Fixture.app"),
                     isMASApp: store, sparkleFeedURL: nil)
    }

    @Test func storeCopiesNeverSelectVendorNotes() {
        let storeAnswer = RemoteVersion(
            shortVersion: "4.1", version: "101", downloadURL: nil, sourceName: "App Store",
            appStore: AppStoreAvailability(trackID: 1, availableRegion: "cn",
                                           homeRegion: "cn", storeName: nil))
        let vendorAnswer = RemoteVersion(
            shortVersion: "4.1", version: "101", downloadURL: nil, sourceName: "Vendor")
        // Include an inconsistent vendor answer: local receipt provenance wins.
        for remote in [nil, storeAnswer, vendorAnswer] {
            for status in [UpdateStatus.unknown, .error("store lookup failed"), .upToDate] {
                let result = UpdateResult(app: app(store: true), remote: remote, status: status)
                #expect(ChangelogRecipeSelection.recipe(for: result) == nil)
            }
        }
        // Retain the old remote-answer defense even without a local receipt.
        let result = UpdateResult(app: app(store: false), remote: storeAnswer, status: .upToDate)
        #expect(ChangelogRecipeSelection.recipe(for: result) == nil)
    }

    @Test func directCopyKeepsNotesWhenLookupMissesOrFails() {
        for status in [UpdateStatus.unknown, .error("lookup failed"), .upToDate] {
            let result = UpdateResult(app: app(store: false), remote: nil, status: status)
            #expect(ChangelogRecipeSelection.recipe(for: result) != nil)
            #expect(ChangelogRecipeSelection.targetVersion(for: result) == "4.0")
        }
    }

    @Test func offeredVersionSelectsTheMatchingRecipeWindow() throws {
        let installed = app(store: false, bundleID: "com.raycast.macos", version: "1.99.0")
        let remote = RemoteVersion(shortVersion: "2.0.0", version: "200",
                                   downloadURL: nil, sourceName: "Vendor")
        let before = UpdateResult(app: installed, remote: nil, status: .unknown)
        let after = UpdateResult(app: installed, remote: remote, status: .updateAvailable(latest: "2.0.0"))
        let old = try #require(ChangelogRecipeSelection.recipe(for: before))
        let new = try #require(ChangelogRecipeSelection.recipe(for: after))
        #expect(old.source != new.source)
        #expect(ChangelogRecipeSelection.targetVersion(for: after) == "2.0.0")
    }

    // MARK: - The fallback page, which is the other half of the same rule

    /// Mutation: drop the `!result.app.isMASApp || isAppStoreListing(curated)`
    /// guard in `fallbackPage` and this goes red — a store copy is handed the
    /// vendor page the recipe half just refused.
    @Test func aStoreCopyIsNotHandedACuratedVendorPage() {
        // Ghostty is in BOTH registries, so it is the shape the guard is about:
        // refusing the recipe alone still leaves a vendor URL behind it.
        let installed = app(store: true, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let result = UpdateResult(app: installed, remote: nil, status: .unknown)
        #expect(ChangelogRecipeSelection.recipe(for: result) == nil)
        let page = ChangelogRecipeSelection.fallbackPage(for: result)
        #expect(page.url == nil)
        #expect(page.origin == .catalogWithheld)
    }

    /// The same row without a receipt must still get the page — otherwise the
    /// test above would pass just as well against a `fallbackPage` that returns
    /// nil for everything.
    @Test func aDirectCopyStillGetsItsCuratedVendorPage() {
        let installed = app(store: false, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: nil, status: .unknown))
        #expect(page.origin == .catalog)
        #expect(page.url?.host == "ghostty.org")
    }

    /// Mutation: narrow the guard to a bare `!result.app.isMASApp` and this goes
    /// red. WhatsApp is iOS-on-Mac, so it is ALWAYS `isMASApp`, and its catalog
    /// entry exists only to show the store page while the check is in flight —
    /// a blanket provenance gate deletes that entry's reason to exist.
    @Test func aStoreListingSurvivesTheGateForAStoreCopy() {
        let installed = app(store: true, bundleID: "net.whatsapp.whatsapp", version: "2.0")
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: nil, status: .unknown))
        #expect(page.origin == .catalog)
        #expect(page.url?.host == "apps.apple.com")
    }

    /// Mutation: make `isAppStoreListing` a suffix test (`hasSuffix(".apple.com")`
    /// or `contains`) and this goes red. A host whose owner appended the store's
    /// name to their own domain is not the store.
    @Test func onlyTheWholeHostCountsAsAStoreListing() {
        #expect(ChangelogRecipeSelection.isAppStoreListing(
            URL(string: "https://apps.apple.com/app/id310633997?platform=mac")!))
        #expect(ChangelogRecipeSelection.isAppStoreListing(
            URL(string: "https://ITUNES.Apple.com/app/id1")!))
        #expect(!ChangelogRecipeSelection.isAppStoreListing(
            URL(string: "https://apps.apple.com.example.invalid/app/id1")!))
        #expect(!ChangelogRecipeSelection.isAppStoreListing(
            URL(string: "https://notapps.apple.com/app/id1")!))
    }

    /// Mutation: reorder `fallbackPage` to consult the catalog first and this
    /// goes red. The source's own URL wins — for a store copy that is the store
    /// listing, which is why the `remote` half needs no gate of its own.
    @Test func theSourcesOwnPageOutranksTheCatalog() {
        let installed = app(store: false, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let remote = RemoteVersion(
            shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Vendor",
            changelogURL: URL(string: "https://example.invalid/notes"))
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: remote, status: .upToDate))
        #expect(page.origin == .remote)
        #expect(page.url?.host == "example.invalid")
    }
}
