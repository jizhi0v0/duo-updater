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

    // MARK: - Which name the page must carry

    /// The product page is the *store's* page, so the store's listing title is what
    /// binds us to it — not the installed bundle's name. Measured on DingTalk
    /// (2026-09-04): the page's hero lockup renders "DingDing: Redefine Work in AI"
    /// and, once rendered, carries the string "DingTalk" nowhere at all. Keying the
    /// binding on the bundle name meant every lookup after the page settled returned
    /// nil, so the whole download reported 0%.
    @Test func theProductPageIsRecognisedByTheStoresOwnTitle() {
        let dingTalk = AppStoreAXInstaller.AppNames(
            bundle: "DingTalk", store: "DingDing: Redefine Work in AI")
        #expect(dingTalk.page == "DingDing: Redefine Work in AI")
        // Both are tried, the store's first: the lookup asks for no language, so the
        // title we hold is the storefront's default while App Store renders the user's
        // ("钉钉 - AI时代的工作方式" for this very app under lang=zh_cn). One needle would
        // fail every poll on a non-English Mac.
        #expect(dingTalk.needles == ["DingDing: Redefine Work in AI", "DingTalk"])
    }

    /// One needle when both names are the same string — a second pass over the same
    /// text can only cost time, and on the Updates list it would also let a loose
    /// match run twice before any other name got its exact one.
    @Test func anAppNamedTheSameInBothPlacesIsLookedUpOnce() {
        #expect(AppStoreAXInstaller.AppNames(bundle: "QQ", store: "QQ").needles == ["QQ"])
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: nil).needles == ["Keka"])
    }

    /// Invisible marks and stray spaces are not identity. `app.name` is already run
    /// through `stripInvisibleMarks` (installed WhatsApp is "\u{200E}WhatsApp.app" on
    /// disk), and the Updates list compares row strings with `==`, where one space is
    /// the difference between a match and none.
    @Test func aStoreTitleIsCleanedTheSameWayTheBundleNameIs() {
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: "  Keka  ").page == "Keka")
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: "\u{200E}").page == "Keka")
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: "\u{200E}Keka").page == "Keka")
    }

    /// An exact match on *any* needle beats a loose match on the first one, because a
    /// contains-match here lands on whatever row happens to carry the substring. The
    /// cn storefront really does carry both of these, both cn-only, so both take the
    /// Updates-list path and can share one list.
    @Test func aRowThatIsReallyOursNeverLosesToSomeoneElsesSubstring() {
        // The rows are the real cn listings — "QQ" (451108668) and "QQ音乐 - #听我想听#"
        // (595615424), both cn-only, so both reach this path and can share one list.
        // The needles are the case that makes order decide: the store title we hold is
        // not on the list as written (a different storefront or language renders it
        // differently), while the bundle name is — and the title we hold is a substring
        // of somebody else's row.
        let rows = [["QQ音乐 - #听我想听#", "Today"], ["QQ", "Yesterday"]]
        let hit = AppStoreAXInstaller.rowIndex(matching: ["QQ音乐", "QQ"], in: rows)
        #expect(hit?.index == 1)       // QQ's own row…
        #expect(hit?.exact == true)    // …because every exact is tried before any loose.
        #expect(hit?.needle == "QQ")
        // Trying each needle exact-then-loose instead would press QQ Music's button.
    }

    /// Loose is still the last resort — a label that carries decoration around the
    /// name has to be reachable, or region-locked apps stop updating entirely.
    @Test func aDecoratedLabelIsStillFoundWhenNothingMatchesExactly() {
        let rows = [["Something Else", "Today"], ["WeChat — 微信", "Yesterday"]]
        let hit = AppStoreAXInstaller.rowIndex(matching: ["WeChat"], in: rows)
        #expect(hit?.index == 1)
        #expect(hit?.exact == false)
        #expect(AppStoreAXInstaller.rowIndex(matching: ["Nothing Here"], in: rows) == nil)
    }

    /// No store title (the lookup didn't supply one) leaves the bundle name as the
    /// only thing to match on — the behaviour every App Store update had before.
    /// A blank one counts as none: matching on "" makes `heroOwns` false for every
    /// page (Foundation's `contains("")` is false), which would fail the update
    /// closed rather than fall back to the name that might have worked.
    @Test func withoutAStoreTitleTheBundleNameIsAllThereIs() {
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: nil).page == "Keka")
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: "").page == "Keka")
        #expect(AppStoreAXInstaller.AppNames(bundle: "Keka", store: "  \n ").page == "Keka")
    }

    // MARK: - What the probe logs

    /// The probe writes to disk on every reading it considers new, and a download
    /// reports ~2 readings a second — so "new" has to mean a change of kind, not a
    /// change of digits, or one large app buries its own diagnosis in thousands of
    /// lines. Percentages collapse; everything else still counts as a transition.
    @Test func onlyAChangeOfKindIsWorthALogLine() {
        let a = #"role=AXButton AXTitle="3% loaded" AXDescription="3% loaded""#
        let b = #"role=AXButton AXTitle="76.6% loaded" AXDescription="76.6% loaded""#
        #expect(AppStoreAXInstaller.readingShape(a) == AppStoreAXInstaller.readingShape(b))

        let loading = #"role=AXButton AXTitle="Loading" AXDescription="Loading""#
        let settled = #"role=AXButton AXTitle="Update" AXDescription="Update""#
        #expect(AppStoreAXInstaller.readingShape(loading) != AppStoreAXInstaller.readingShape(a))
        #expect(AppStoreAXInstaller.readingShape(settled) != AppStoreAXInstaller.readingShape(a))
        // The reading that broke DingTalk: the button going missing entirely.
        #expect(AppStoreAXInstaller.readingShape("button=nil") != AppStoreAXInstaller.readingShape(a))
    }

    // MARK: - Finishing the swap

    /// App Store reports the swap on the offer button itself. Pinned against the exact
    /// string it renders, because this reading is what keeps a long install alive.
    @Test func readsTheInstallPercentageAppStoreShowsWhileSwapping() {
        #expect(AppStoreAXInstaller.progressFraction("Installing: 20% Complete") == 0.2)
        #expect(AppStoreAXInstaller.progressFraction("80% loaded") == 0.8)
    }

    /// A settled button carries no percentage, and must not read as progress — that is
    /// what tells a stalled swap apart from a working one.
    @Test func settledButtonTitlesCarryNoProgress() {
        for title in ["Update", "Open", "Get", "Purchased"] {
            #expect(AppStoreAXInstaller.progressFraction(title) == nil, "\(title) must not parse as progress")
        }
    }

    /// The swap deadline counts polls with *nothing moving*, never polls since Continue.
    /// A flat deadline from Continue failed large apps outright: Excel (2.56 GB) needed
    /// ~2 min and Word (2.73 GB) landed just past 90 s, so a finished update was
    /// reported as a timeout and the row showed an error for an app that had updated.
    @Test func theSwapDeadlineMeasuresStallingNotElapsedTime() {
        #expect(!AppStoreAXInstaller.swapHasStalled(stalledPolls: 224, progressReadable: true))
        #expect(AppStoreAXInstaller.swapHasStalled(stalledPolls: 225, progressReadable: true))
        // The point of the change: any number of polls is fine while progress moves,
        // because a moving install resets the count to zero every time.
        #expect(!AppStoreAXInstaller.swapHasStalled(stalledPolls: 0, progressReadable: true))
    }

    /// The ~90s cap only means anything when there is a percentage to watch. On the
    /// Updates-list path the row leaves the list as it installs, so `installProgress`
    /// reads nil on every poll and the count is a blind stopwatch, not a stall — and a
    /// blind 90s is the flat deadline that failed Word all over again. No reading buys
    /// the generous cap instead. Judged per poll, not latched on a reading seen earlier:
    /// an Updates-list row can report a percentage or two before it drops out of the
    /// list, and latching on those would put the rest of the swap back under 90s.
    @Test func aSwapWithNoReadableProgressGetsTheGenerousCap() {
        #expect(!AppStoreAXInstaller.swapHasStalled(stalledPolls: 225, progressReadable: false),
                "~90s of silence on a path that cannot report progress is not evidence of a stall")
        #expect(!AppStoreAXInstaller.swapHasStalled(stalledPolls: 749, progressReadable: false))
        #expect(AppStoreAXInstaller.swapHasStalled(stalledPolls: 750, progressReadable: false))
    }

    // MARK: - Leftover sheets

    /// The regression. App Store can leave its "Close This App to Update" sheet up for
    /// minutes after the update it belonged to has landed — the page behind it had
    /// already flipped to "Open". Acting on that leftover on the *next* install either
    /// bails it as a purchase sheet or asks the user to Relaunch for a swap that is not
    /// pending, so a sheet that predates our press is ignored.
    @Test func aSheetAlreadyUpBeforeWePressedIsNotOurs() {
        let (isOurs, carry) = AppStoreAXInstaller.classifySheet(onScreen: true, ignoringLeftover: true)
        #expect(!isOurs)
        #expect(carry, "must keep ignoring it while it is still up")
    }

    /// Once the screen has been clear for even one poll, the leftover is gone and the
    /// next sheet is the one our own install raised.
    @Test func aSheetRaisedAfterTheScreenClearedIsOurs() {
        let cleared = AppStoreAXInstaller.classifySheet(onScreen: false, ignoringLeftover: true)
        #expect(!cleared.isOurs)
        #expect(!cleared.ignoringLeftover, "a clear screen retires the leftover")

        let ours = AppStoreAXInstaller.classifySheet(onScreen: true, ignoringLeftover: cleared.ignoringLeftover)
        #expect(ours.isOurs)
    }

    /// The ordinary case — nothing was up when we pressed — must be untouched by the
    /// filter, or every close-to-update sheet would be ignored and no update could
    /// finish while its app was running.
    @Test func withNoLeftoverEverySheetIsOurs() {
        #expect(AppStoreAXInstaller.classifySheet(onScreen: true, ignoringLeftover: false).isOurs)
        #expect(!AppStoreAXInstaller.classifySheet(onScreen: false, ignoringLeftover: false).isOurs)
    }

    /// The rule the flat deadline got wrong: a swap that keeps reporting new
    /// percentages never accumulates stall, however long it runs. Driven far past the
    /// old ~90s deadline (225 polls) to pin that explicitly.
    @Test func aMovingInstallNeverAccumulatesStallHoweverLongItRuns() {
        var last: Double?
        var stalled = 0
        for poll in 0..<400 {
            let reading = Double(poll) / 400          // still climbing
            (last, stalled) = AppStoreAXInstaller.swapWatchdog(
                progress: reading, last: last, stalledPolls: stalled)
            #expect(stalled == 0, "movement at poll \(poll) must reset the count")
            #expect(!AppStoreAXInstaller.swapHasStalled(stalledPolls: stalled, progressReadable: true))
        }
    }

    /// No reading at all — normal right after Continue, before the install starts
    /// reporting — counts as no movement, so a swap that never starts still bails.
    @Test func pollsWithNoReadingCountAsStalled() {
        var last: Double?
        var stalled = 0
        for _ in 0..<225 {
            (last, stalled) = AppStoreAXInstaller.swapWatchdog(
                progress: nil, last: last, stalledPolls: stalled)
        }
        #expect(stalled == 225)
        #expect(AppStoreAXInstaller.swapHasStalled(stalledPolls: stalled, progressReadable: true))
    }

    /// A percentage frozen on the same number is not movement — a wedged install must
    /// not be kept alive forever by a button still reading "Installing: 40% Complete".
    @Test func aFrozenPercentageCountsAsStalled() {
        var last: Double? = 0.4
        var stalled = 0
        for _ in 0..<10 {
            (last, stalled) = AppStoreAXInstaller.swapWatchdog(
                progress: 0.4, last: last, stalledPolls: stalled)
        }
        #expect(stalled == 10)
        #expect(last == 0.4)
    }
}
#endif
