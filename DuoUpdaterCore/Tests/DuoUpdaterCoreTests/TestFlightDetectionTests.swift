import Testing
import Foundation
@testable import DuoUpdaterCore

/// #547: the user's choice about TestFlight betas, and the two questions every
/// call site asks of it.
///
/// Every case names the mutation it kills, and each was run against this suite.
@Suite("TestFlightDetection")
struct TestFlightDetectionTests {

    // MARK: - What each state allows

    /// Mutation: `readsStore` → `true`. Off is the only state that reads nothing,
    /// and it is the single question every read site asks — a `readsStore` that
    /// answered yes everywhere would leave the setting with no effect at all while
    /// the picker still showed the user's choice.
    @Test("off is the only state that reads nothing")
    func offIsTheOnlyStateThatReadsNothing() {
        #expect(TestFlightDetection.off.readsStore == false)
        #expect(TestFlightDetection.whenAsked.readsStore)
        #expect(TestFlightDetection.keepFresh.readsStore)
    }

    /// Mutation: `syncsUnasked` → `self != .off`. That is the plausible wrong
    /// answer, not an arbitrary one: it makes "on" mean one thing, which is exactly
    /// the collapse this type exists to prevent — `whenAsked` would then start a
    /// hidden TestFlight the user never asked for, which is the whole cost #547
    /// gives back to them to decide.
    @Test("only keep-it-fresh may start TestFlight without being asked")
    func onlyKeepFreshSyncsUnasked() {
        #expect(TestFlightDetection.keepFresh.syncsUnasked)
        #expect(TestFlightDetection.whenAsked.syncsUnasked == false)
        #expect(TestFlightDetection.off.syncsUnasked == false)
    }

    /// Not a mutation of either property — a mutation of any FUTURE state added
    /// beside them. A state that syncs but does not read would ask TestFlight to
    /// bring a store up to date that nothing then opens: the sync is only
    /// observable through the store. Derived from `allCases` so a fourth state is
    /// covered without anyone remembering this file.
    @Test("a state that syncs also reads", arguments: TestFlightDetection.allCases)
    func syncingImpliesReading(_ detection: TestFlightDetection) {
        if detection.syncsUnasked { #expect(detection.readsStore) }
    }

    // MARK: - What is persisted

    /// Mutation: rename any raw value (`whenAsked` → `manual`, say). These strings
    /// are what is written to `UserDefaults`, so a rename is not a refactor: every
    /// existing choice stops parsing, and `Preferences` reads an unrecognized value
    /// as `.off` — silently switching TestFlight off for everyone who had it on,
    /// with the picker showing "Off" as though they had chosen it.
    @Test("the persisted spellings are fixed")
    func persistedSpellingsAreFixed() {
        #expect(TestFlightDetection.off.rawValue == "off")
        #expect(TestFlightDetection.whenAsked.rawValue == "whenAsked")
        #expect(TestFlightDetection.keepFresh.rawValue == "keepFresh")
        #expect(TestFlightDetection(rawValue: "keepFresh") == .keepFresh)
    }

    // MARK: - The first-run default

    /// Mutation: invert the ternary in `firstRunDefault`. Granted means TestFlight
    /// rows are answering today; starting such a Mac at `.off` would take a working
    /// feature away on update, with nothing said about it.
    @Test("a Mac that already has the grant starts at when-I-refresh")
    func grantedStartsAtWhenAsked() {
        #expect(TestFlightDetection.firstRunDefault(fullDiskAccess: .granted) == .whenAsked)
    }

    /// Mutation: `firstRunDefault` → `.whenAsked` unconditionally. Without the
    /// grant nothing can be read, so starting anywhere but `.off` would mean a new
    /// user's first rounds attempt a read that cannot succeed — the "Data Access
    /// Blocked" notices this setting exists to be able to stop.
    @Test("a Mac without the grant starts off", arguments: [TCCAuthStatus.denied, .notDetermined])
    func withoutTheGrantStartsOff(_ status: TCCAuthStatus) {
        #expect(TestFlightDetection.firstRunDefault(fullDiskAccess: status) == .off)
    }

    /// Mutation: `TCCPreflight.admitsOtherAppsData(fullDiskAccess:)` →
    /// `fullDiskAccess == .granted`. `.unknown` means the preflight SPI is gone, not
    /// that the permission is missing, and every read site already treats it as
    /// granted — a first run that read it as missing would switch TestFlight off for
    /// someone using it because an undocumented symbol was renamed.
    @Test("an unreadable permission starts where a granted one does")
    func unknownStartsAtWhenAsked() {
        #expect(TestFlightDetection.firstRunDefault(fullDiskAccess: .unknown) == .whenAsked)
        #expect(TestFlightDetection.firstRunDefault(fullDiskAccess: .unknown)
            == TestFlightDetection.firstRunDefault(fullDiskAccess: .granted))
    }

    // MARK: - Why a row cannot bound its beta

    /// Mutation: ask `fullDiskAccessMissing` first. Both are true on a Mac that has
    /// detection off and never granted Full Disk Access — the common case, since
    /// that is exactly the pair `firstRunDefault` produces — and naming the
    /// permission there sends the user to grant something that would change
    /// nothing, because the read is off regardless.
    @Test("off outranks a missing permission")
    func offOutranksAMissingPermission() {
        #expect(TestFlightUnboundedReason.of(detection: .off, fullDiskAccessMissing: true)
            == .checkingOff)
        #expect(TestFlightUnboundedReason.of(detection: .off, fullDiskAccessMissing: false)
            == .checkingOff)
    }

    /// Mutation: return `.storeSilent` whenever the store is read. The row would
    /// then say TestFlight had not told us this build — "asked, and not told" — on a
    /// Mac where nothing was ever able to ask, and the tip would drop the Grant…
    /// button that is the only way out of that state.
    @Test("with detection on, the permission decides which of the two it is")
    func detectionOnDefersToThePermission() {
        for detection in TestFlightDetection.allCases where detection.readsStore {
            #expect(TestFlightUnboundedReason.of(detection: detection, fullDiskAccessMissing: true)
                == .noFullDiskAccess)
            #expect(TestFlightUnboundedReason.of(detection: detection, fullDiskAccessMissing: false)
                == .storeSilent)
        }
    }
}
