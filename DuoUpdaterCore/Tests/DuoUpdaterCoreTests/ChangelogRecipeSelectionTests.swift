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
        #expect(ChangelogRecipeSelection.fallbackPage(for: result) == .withheld)
    }

    /// The same row without a receipt must still get the page — otherwise the
    /// test above would pass just as well against a `fallbackPage` that returns
    /// nil for everything.
    @Test func aDirectCopyStillGetsItsCuratedVendorPage() {
        let installed = app(store: false, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: nil, status: .unknown))
        #expect(page.url?.host == "ghostty.org")
        #expect(page.logToken == "catalog")
    }

    /// Mutation: narrow the guard to a bare `!result.app.isMASApp` and this goes
    /// red. A store copy SHOULD be shown a store listing — that is the right
    /// distribution's notes, not the wrong one — and WhatsApp's catalog entry
    /// exists precisely to show it while the check is still in flight.
    ///
    /// ⚠️ The fixture says `store: true` because that is the case under test,
    /// NOT because WhatsApp is always a store copy. It is not: WhatsApp also
    /// ships a Developer ID build (`VendorProbeRecipe`, Team `57T9237FN3`), and
    /// that copy is `isMASApp == false` and gets this same store listing — the
    /// inverse of #388, pre-existing and untouched here. An earlier version of
    /// this comment asserted "WhatsApp is iOS-on-Mac, so it is ALWAYS isMASApp",
    /// which is false and hid that case.
    @Test func aStoreListingSurvivesTheGateForAStoreCopy() {
        let installed = app(store: true, bundleID: "net.whatsapp.whatsapp", version: "2.0")
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: nil, status: .unknown))
        #expect(page.url?.host == "apps.apple.com")
        #expect(page.logToken == "catalog")
    }

    /// Two mutations, one per direction, because the two ends fail differently
    /// and an earlier version of this comment named only one of them — and named
    /// it against the assertion that does not pin it.
    ///
    /// Mutation A, `hasSuffix("apps.apple.com")`: `notapps.apple.com` (fourth
    /// assertion) goes red. Mutation B, `contains` or a prefix test:
    /// `apps.apple.com.example.invalid` (third assertion) goes red. Neither
    /// mutation is caught by the other's assertion, which is why both are here.
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

    /// Mutation: add `guard !result.app.isMASApp` to the `remote` branch — the
    /// "tidy" that `fallbackPage`'s comment exists to forbid — and this goes red.
    /// Without it the claim the comment argues hardest for had no test at all:
    /// every other case here uses a direct copy, so gating the ungated half was
    /// a free change.
    @Test func aStoreCopyStillGetsItsOwnSourcesPage() {
        let installed = app(store: true, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let remote = RemoteVersion(
            shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "App Store",
            appStore: AppStoreAvailability(trackID: 1, availableRegion: "us",
                                           homeRegion: "us", storeName: nil),
            changelogURL: URL(string: "https://apps.apple.com/app/id1"))
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: remote, status: .upToDate))
        #expect(page == .fromSource(URL(string: "https://apps.apple.com/app/id1")!))
    }

    /// `fallbackPage`'s comment says no catalog entry is a vendor page for a
    /// bundle id that also has a recipe, and the argument for the whole change is
    /// that the set is expected to MOVE. A hand-transcribed measurement inside a
    /// comment drifts silently, so derive it: this fails when the overlap changes,
    /// pointing the next person at the comment that has to be re-read.
    ///
    /// The assertion is on the SET, not a count — a count stays green when one id
    /// leaves and another arrives, which is exactly the edit worth catching.
    @Test func catalogAndRecipeOverlapIsWhatTheCommentSays() {
        let catalog = Set(ChangelogCatalog.pages.keys)
        let recipes = Set(ChangelogRecipeRegistry.recipes.map { $0.bundleID.lowercased() })
        #expect(catalog.intersection(recipes) == [
            "app.chatwise", "com.electron.ollama", "com.longbridge.app.desktop",
            "com.mitchellh.ghostty", "net.imput.helium",
        ], "The catalog/recipe overlap moved. Re-read ChangelogRecipeSelection.fallbackPage: a new entry here is a vendor page that a store copy could reach through the web view.")
        // The case the whole change is about has no catalog entry, so it lands on
        // "No release notes" rather than a vendor page. If this ever gains one,
        // the gate above is the only thing standing between a store WeChat and
        // the official site's notes.
        #expect(!catalog.contains("com.tencent.xinwechat"))
    }

    /// Mutation: reorder `fallbackPage` to consult the catalog first and this
    /// goes red.
    @Test func theSourcesOwnPageOutranksTheCatalog() {
        let installed = app(store: false, bundleID: "com.mitchellh.ghostty", version: "1.0")
        let remote = RemoteVersion(
            shortVersion: "1.1", version: "2", downloadURL: nil, sourceName: "Vendor",
            changelogURL: URL(string: "https://example.invalid/notes"))
        let page = ChangelogRecipeSelection.fallbackPage(
            for: UpdateResult(app: installed, remote: remote, status: .upToDate))
        #expect(page.url?.host == "example.invalid")
        #expect(page.logToken == "remote")
    }
}
