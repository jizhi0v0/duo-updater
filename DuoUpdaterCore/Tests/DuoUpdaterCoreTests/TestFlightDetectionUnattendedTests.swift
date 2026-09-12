import Foundation
import Testing
@testable import DuoUpdaterCore

/// The rule an unattended trigger reads the TestFlight container by.
///
/// This lives in Core for one reason: the way to get it wrong — reaching for
/// `TCCPreflight.admitsOtherAppsData` instead — is invisible on any Mac that has
/// actually granted Full Disk Access, because the two agree everywhere except
/// `.unknown`. A machine where the feature is being developed is exactly such a Mac,
/// so "it worked when I ran it" cannot catch this one.
@Suite struct TestFlightDetectionUnattendedTests {

    /// The case that separates this rule from the preflight. `admitsOtherAppsData`
    /// returns true here; an unattended read must not, because it is the read that
    /// raises the "access data from other apps" prompt.
    ///
    /// Mutation: `readsStore && TCCPreflight.admitsOtherAppsData(fullDiskAccess:)` —
    /// this fails, and a background timer becomes able to put up a TCC dialog.
    @Test func nothingUnattendedReadsWhenTheGrantIsUnknown() {
        #expect(TCCPreflight.admitsOtherAppsData(fullDiskAccess: .unknown))
        #expect(!TestFlightDetection.keepFresh.readsStoreUnattended(fullDiskAccess: .unknown))
    }

    /// With the grant the read is silent, so the whole point of the caution is gone.
    ///
    /// Mutation: `return false` — this fails, and the store watcher and the poll both
    /// become dead code on every Mac that granted access.
    @Test func aGrantedMacReadsNormally() {
        #expect(TestFlightDetection.keepFresh.readsStoreUnattended(fullDiskAccess: .granted))
        #expect(TestFlightDetection.whenAsked.readsStoreUnattended(fullDiskAccess: .granted))
    }

    /// The setting still outranks the grant: `off` means nothing is read, however the
    /// permission stands.
    ///
    /// Mutation: drop the `readsStore &&` conjunct — this fails, and turning detection
    /// off stops stopping the unattended readers.
    @Test func offOutranksTheGrant() {
        #expect(!TestFlightDetection.off.readsStoreUnattended(fullDiskAccess: .granted))
    }

    /// A refused or unasked grant refuses, which is the same answer the preflight gives
    /// — pinned so a future "simplification" to `fullDiskAccess == .granted` is seen to
    /// be equivalent here and not merely assumed to be.
    ///
    /// Mutation: `fullDiskAccess != .denied` — this fails here on `.notDetermined`, and
    /// also reddens `nothingUnattendedReadsWhenTheGrantIsUnknown` (verified: 2 issues
    /// across the two cases). Both are the same defect seen from two sides.
    @Test func deniedAndNotDeterminedBothRefuse() {
        #expect(!TestFlightDetection.keepFresh.readsStoreUnattended(fullDiskAccess: .denied))
        #expect(!TestFlightDetection.keepFresh.readsStoreUnattended(fullDiskAccess: .notDetermined))
    }
}
