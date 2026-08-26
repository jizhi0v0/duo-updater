#if os(macOS)
import Testing
@testable import DuoUpdaterCore

/// Regression cover for how the App Store (AX) route decides *which* offer button to
/// press on a product page. Getting this wrong does not fail an update — it spends the
/// user's money, so the rules are pinned here rather than left to the traversal.
///
/// Background (mini, macOS 26.6, 2026-08-26): the previous guard asked whether the app's
/// name appeared as text anywhere under App Store's element. That is permanently true for
/// every app we might update, because the Apple menu's **Recent Items** submenu hangs off
/// every app's `AXMenuBar` and lists recently used applications. With the guard always
/// passing, the topmost offer button was pressed on whatever page App Store still had on
/// screen while our deep link was still in flight — a featured app's `$49.99` buy button
/// on the restored Discover page (reproduced 5/5), or the buy button of whichever product
/// page it was parked on.
struct AppStoreOfferButtonTests {

    private typealias ShelfCell = AppStoreAXInstaller.ShelfCell

    // MARK: - Which cell owns a button

    /// The product page's hero lockup — icon, name, subtitle and the offer button we
    /// actually want. Identifier observed on the Microsoft Word product page.
    @Test func theHeroLockupIsOurOwnCell() {
        #expect(ShelfCell(identifier: "AppStore.shelfItem.ProductLockupCollectionViewCell") == .hero)
    }

    /// Every other cell subtype holds a *different* app. `SmallLockup` is the one that
    /// carried both the `$49.99` featured app on Discover and the "Also Included In"
    /// Microsoft 365 subscription sitting directly under Word's own Update button.
    /// Swept over the subtypes actually dumped from App Store so a new one added by
    /// Apple is treated as foreign by default — the safe direction.
    @Test func everyOtherLockupBelongsToSomeoneElse() {
        let foreign = [
            "AppStore.shelfItem.SmallLockupCollectionViewCell",
            "AppStore.shelfItem.BadgeCollectionViewCell",
            "AppStore.shelfItem.ProductMediaItemCollectionViewCell",
            "AppStore.shelfItem.TitledParagraphCollectionViewCell",
            "AppStore.shelfItem.SomeCellAppleHasNotShippedYet",
        ]
        for id in foreign {
            #expect(ShelfCell(identifier: id) == .foreign, "\(id) must not be treated as our own cell")
        }
    }

    /// Non-cell identifiers must not be mistaken for a hero lockup, or the ownership
    /// check could be satisfied by page furniture. `nil` matters most: menu items — the
    /// Recent Items entries that defeated the old guard — carry no identifier at all, so
    /// they can never classify as a hero and can never satisfy the gate.
    @Test func pageFurnitureAndMenuItemsAreNotCells() {
        let notCells: [String?] = [
            nil,
            "AppStore.offerButton",
            "AppStore.productPage",
            "AppStore.productPage.backButton",
            "AppStore.discover",
            "AppStore.tabBar.updates",
            "AppStore.shelf.seeAllButton[id=3,parentId=mostRecentVersion]",  // a shelf, not a shelfItem
        ]
        for id in notCells {
            #expect(ShelfCell(identifier: id) == .notACell, "\(id ?? "nil") must not classify as a cell")
        }
    }

    // MARK: - Press or keep waiting

    /// The happy path: we are on this app's page and exactly one button is ours.
    @Test func pressesWhenThePageIsOursAndOneButtonSurvives() {
        #expect(AppStoreAXInstaller.shouldPress(heroOwnsPage: true, ownButtonCount: 1))
    }

    /// The bug this whole file exists for. App Store is showing *something else* — its
    /// restored Discover page, or another app's product page — and that page has a
    /// perfectly pressable, non-foreign offer button. It is a buy button. Never press it.
    @Test func neverPressesWhileThePageIsNotOurs() {
        #expect(!AppStoreAXInstaller.shouldPress(heroOwnsPage: false, ownButtonCount: 1))
    }

    /// Mid-navigation the outgoing and incoming pages are briefly both in the AX tree
    /// (observed: 8 offer buttons in a single poll). Ambiguity means wait, not guess.
    @Test func neverPressesWhileTwoPagesOverlap() {
        #expect(!AppStoreAXInstaller.shouldPress(heroOwnsPage: true, ownButtonCount: 2))
    }

    /// Nothing to press yet — the page is still rendering. Keep polling.
    @Test func waitsWhenNoButtonIsOurs() {
        #expect(!AppStoreAXInstaller.shouldPress(heroOwnsPage: true, ownButtonCount: 0))
    }

    /// Both conditions are required; neither alone may authorise a press. Written as an
    /// exhaustive sweep so a future "simplification" to a single condition fails here.
    @Test func bothConditionsAreRequired() {
        for owns in [true, false] {
            for count in 0...3 {
                let expected = owns && count == 1
                #expect(
                    AppStoreAXInstaller.shouldPress(heroOwnsPage: owns, ownButtonCount: count) == expected,
                    "heroOwnsPage=\(owns) ownButtonCount=\(count) must be \(expected)")
            }
        }
    }
}
#endif
