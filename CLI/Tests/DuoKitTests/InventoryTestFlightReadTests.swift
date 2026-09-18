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
@Suite(.scratchPreferences) struct InventoryTestFlightReadTests {

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

    /// The stores take the decision, not the setting: `reads: false` opens nothing
    /// and hands back the sentinel, `reads: true` opens each once. Counted through
    /// the `open` seam, because a sentinel and a refused read are both
    /// `accessible == false` and a Mac without TestFlight could not tell them apart.
    ///
    /// Mutations: make `testFlightStore` or `testFlightAnnouncements` call `open()`
    /// regardless of `reads`.
    @Test func neitherStoreIsOpenedWhenTheRunDoesNotRead() {
        var storeOpens = 0, noteOpens = 0
        func store() -> TestFlightInventory {
            storeOpens += 1
            return TestFlightInventory(macRows: [], accessible: true)
        }
        func notes() -> TestFlightAnnouncements {
            noteOpens += 1
            return TestFlightAnnouncements(announcements: [], accessible: true)
        }
        let s = Inventory.testFlightStore(reads: false, open: store)
        let n = Inventory.testFlightAnnouncements(reads: false, open: notes)
        #expect(!s.accessible && !n.accessible)
        #expect(storeOpens == 0)
        #expect(noteOpens == 0)

        _ = Inventory.testFlightStore(reads: true, open: store)
        _ = Inventory.testFlightAnnouncements(reads: true, open: notes)
        #expect(storeOpens == 1)
        #expect(noteOpens == 1)
    }

    /// A thread-safe ordered log, for a body that runs on `BoundedScan`'s thread.
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ item: String) { lock.withLock { items.append(item) } }
        var entries: [String] { lock.withLock { items } }
        func probe(_ status: TCCAuthStatus) -> TCCAuthStatus { append("probe"); return status }
    }

    /// `boundedRead` decides before the bound and hands the body the answer. The
    /// order is what keeps `Inventory.fullDiskAccess` from being first initialised
    /// on a thread the bound may abandon; evaluating the decision inside the body
    /// does not compile (the status is a non-escaping autoclosure), so the order
    /// asserted here is the one the compiler leaves possible.
    ///
    /// Mutations: pass `body(true)` / `body(!reads)` in `boundedRead`.
    @Test func boundedReadDecidesFirstAndPassesTheDecisionIn() async {
        for (status, expected) in [(TCCAuthStatus.denied, false), (.granted, true)] {
            let log = Log()
            let reads = await Inventory.boundedRead(
                .keepFresh, fullDiskAccess: log.probe(status), within: .seconds(20)
            ) { reads in
                log.append("body")
                return reads
            }
            #expect(reads == expected, "\(status)")
            #expect(log.entries == ["probe", "body"], "\(status)")
        }
    }

    /// A probe that does not answer in time reads as not granted, so the run does
    /// not read TestFlight; one that answers is taken as it is. The stall is two
    /// seconds, not forever, so the unbounded version fails this test rather than
    /// hanging it.
    ///
    /// Mutation: have `fullDiskAccess(within:probe:)` return `probe()` directly.
    @Test func aStalledFullDiskAccessProbeReadsAsNotGranted() {
        let stalled = Inventory.fullDiskAccess(within: .milliseconds(200)) {
            Thread.sleep(forTimeInterval: 2)
            return .granted
        }
        #expect(stalled == .notDetermined)
        #expect(!Inventory.readsTestFlight(.keepFresh, fullDiskAccess: stalled))

        let answered = Inventory.fullDiskAccess(within: .seconds(20)) { .granted }
        #expect(answered == .granted)
    }

    /// Tripwires over the source tree, for the two properties the compiler cannot
    /// hold on its own.
    ///
    /// 1. Every bounded scan goes through `Inventory.boundedRead` — the only place
    ///    that decides before the bound — so nothing else calls `BoundedScan.result`.
    /// 2. The files that name `Inventory.fullDiskAccess` are the ones checked to use
    ///    it outside any bound. A new file on this list needs that check.
    /// 3. `duo verify` never calls `Settings.load()`, which reads the Keychain and
    ///    may run `gh` with no deadline (`Settings.loadTestFlightDetection`).
    ///
    /// Mutations: put `BoundedScan.result` back in `Verify.installedVersions`; name
    /// `Inventory.fullDiskAccess` in `Verify.swift`; put `Settings.load()` back there.
    @Test func boundedScansAndTheLiveStatusStayWhereTheyWereChecked() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? [])
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        #expect(files.count > 10, "found \(files.count) sources — wrong directory?")
        func naming(_ needle: String) -> [String] {
            files.filter { $0.1.contains(needle) }.map(\.0).sorted()
        }
        #expect(naming("BoundedScan.result(") == ["Inventory.swift"])
        #expect(naming("Inventory.fullDiskAccess") == ["Check.swift", "Inventory.swift"])
        // Code lines only: the doc comment there names the call it must not make.
        let verify = try #require(files.first { $0.0 == "Verify.swift" }?.1)
        let calls = verify.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { $0.contains("Settings.load()") }
        #expect(calls.isEmpty, "\(calls)")
    }

    /// The detection setting read on its own agrees with `Settings.load()`'s, from
    /// one reading of the key. A scratch suite, removed afterwards, so the real
    /// preferences are never touched.
    ///
    /// Mutation: change the fallback in `testFlightDetection(from:)` from `.off`.
    @Test func theDetectionSettingReadsAloneAsItDoesInLoad() {
        let defaults = scratchDefaults()

        #expect(Settings.testFlightDetection(from: defaults) == .off)
        defaults.set("not-a-setting", forKey: UpdateSettings.testFlightDetectionKey)
        #expect(Settings.testFlightDetection(from: defaults) == .off)
        for detection in TestFlightDetection.allCases {
            defaults.set(detection.rawValue, forKey: UpdateSettings.testFlightDetectionKey)
            #expect(Settings.testFlightDetection(from: defaults) == detection)
        }
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
