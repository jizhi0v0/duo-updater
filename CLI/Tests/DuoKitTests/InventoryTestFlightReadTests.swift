import Testing
import Foundation
@testable import DuoKit
import DuoUpdaterCore

/// `duo` does not attempt TestFlight's reads without Full Disk Access — the menu-bar
/// app's rule, taken rather than re-invented.
///
/// Every status is passed in; nothing here asks the host what it has granted. The
/// live status (`Inventory.fullDiskAccess`) is only reached with detection on, and
/// no case below builds settings with detection on.
@Suite struct InventoryTestFlightReadTests {

    /// Spelled out because `TCCAuthStatus` is not `CaseIterable`; the exhaustive
    /// switch in `TCCPreflight.admitsOtherAppsData` is what makes a new case visible.
    private static let statuses: [TCCAuthStatus] = [.granted, .denied, .notDetermined, .unknown]

    private func settings(_ detection: TestFlightDetection) -> Settings {
        Settings(
            updateSettings: UpdateSettings(
                appStoreUpdateStrategy: .full, vendorInstallPolicy: .deferWhenRunning),
            ignoredKeys: [], skippedVersions: [:], customScanPaths: [], maxConcurrency: 12,
            testFlightDetection: detection, keepBackups: true, githubToken: nil, alcove: nil)
    }

    /// The rule is the app's for a refresh the user asked for: detection on, and
    /// `RefreshIntent.userRequested.readsTestFlight(fullDiskAccess:)` — which reads
    /// on `.granted` and `.unknown` and not on `.denied`/`.notDetermined`. Derived
    /// from Core's function across every detection setting and every status, so
    /// the two cannot drift apart without this failing.
    ///
    /// Mutations: drop the Full Disk Access term (reads on `.denied`); drop
    /// `detection.readsStore` (reads with detection off); use `.scheduled`'s rule
    /// (`.unknown` stops reading).
    @Test func theRuleIsTheAppsForARequestedRefresh() {
        for detection in TestFlightDetection.allCases {
            for status in Self.statuses {
                let expected = detection.readsStore
                    && RefreshIntent.userRequested.readsTestFlight(fullDiskAccess: status)
                #expect(
                    Inventory.readsTestFlight(detection, fullDiskAccess: status) == expected,
                    "\(detection) / \(status)")
            }
        }
        // Stated plainly as well, so the derivation above is not the only witness.
        #expect(!Inventory.readsTestFlight(.keepFresh, fullDiskAccess: .denied))
        #expect(!Inventory.readsTestFlight(.whenAsked, fullDiskAccess: .notDetermined))
        #expect(Inventory.readsTestFlight(.whenAsked, fullDiskAccess: .unknown))
    }

    /// Detection off decides without asking: the probe opens files, and a run that
    /// will not read TestFlight has no reason to.
    ///
    /// Mutation: evaluate `fullDiskAccess()` before `detection.readsStore`.
    @Test func detectionOffNeverAsksForFullDiskAccess() {
        var asked = 0
        func probe() -> TCCAuthStatus { asked += 1; return .granted }
        // Outside `#expect`: the macro captures subexpressions for its diagnostics,
        // which evaluates the argument and would count a probe the code never made.
        let reads = Inventory.readsTestFlight(.off, fullDiskAccess: probe())
        #expect(!reads)
        #expect(asked == 0)
    }

    /// The App Store sign-in is read only when the TestFlight store was, as in the
    /// app. The read is counted through the seam, never performed.
    ///
    /// Mutation: `let appStoreSignedIn = appStoreSignIn()` unconditionally.
    @Test func signInIsReadOnlyWhenTheStoreWas() {
        var reads = 0
        let unread = Inventory.checker(
            settings(.off),
            testflight: TestFlightInventory(macRows: [], accessible: false),
            announcements: TestFlightAnnouncements(announcements: [], accessible: false),
            appStoreSignIn: { reads += 1; return false })
        #expect(reads == 0)
        #expect(unread.appStoreSignedIn == nil)

        let read = Inventory.checker(
            settings(.off),
            testflight: TestFlightInventory(macRows: [], accessible: true),
            announcements: TestFlightAnnouncements(announcements: [], accessible: true),
            appStoreSignIn: { reads += 1; return false })
        #expect(reads == 1)
        #expect(read.appStoreSignedIn == false)
    }

    /// Both reads follow the rule: with detection on and Full Disk Access missing
    /// neither store is opened, and with the grant each is opened once. Counted
    /// through the `open` seam, because a sentinel and a refused read are both
    /// `accessible == false` and a Mac without TestFlight could not tell them apart.
    ///
    /// Mutations: have `testFlightStore` or `testFlightAnnouncements` go back to
    /// `settings.testFlightDetection.readsStore` alone.
    @Test func neitherStoreIsOpenedWithoutFullDiskAccess() {
        var storeOpens = 0, noteOpens = 0
        func store() -> TestFlightInventory {
            storeOpens += 1
            return TestFlightInventory(macRows: [], accessible: true)
        }
        func notes() -> TestFlightAnnouncements {
            noteOpens += 1
            return TestFlightAnnouncements(announcements: [], accessible: true)
        }
        for status in [TCCAuthStatus.denied, .notDetermined] {
            let s = Inventory.testFlightStore(settings(.keepFresh), fullDiskAccess: status, open: store)
            let n = Inventory.testFlightAnnouncements(settings(.keepFresh), fullDiskAccess: status, open: notes)
            #expect(!s.accessible && !n.accessible, "\(status)")
        }
        #expect(storeOpens == 0)
        #expect(noteOpens == 0)

        _ = Inventory.testFlightStore(settings(.whenAsked), fullDiskAccess: .granted, open: store)
        _ = Inventory.testFlightAnnouncements(settings(.whenAsked), fullDiskAccess: .granted, open: notes)
        #expect(storeOpens == 1)
        #expect(noteOpens == 1)
    }

    /// `--refresh-testflight` starts TestFlight only when this run may read what it
    /// refreshes, and says why when it does not.
    ///
    /// Mutations: drop the gate (nil for `.denied`); swap the two reasons.
    @Test func aRefreshThatCouldNotBeReadIsNotStartedAndSaysWhy() throws {
        #expect(Check.refreshSkipped(.keepFresh, fullDiskAccess: .granted) == nil)
        #expect(Check.refreshSkipped(.whenAsked, fullDiskAccess: .unknown) == nil)

        let noGrant = try #require(Check.refreshSkipped(.keepFresh, fullDiskAccess: .denied))
        #expect(noGrant.hasPrefix("duo: TestFlight was not started"))
        #expect(noGrant.contains("without Full Disk Access"))

        let off = try #require(Check.refreshSkipped(.off, fullDiskAccess: .granted))
        #expect(off.hasPrefix("duo: TestFlight was not started"))
        #expect(off.contains("detection is off"))
        #expect(!off.contains("Full Disk Access"))
    }
}
