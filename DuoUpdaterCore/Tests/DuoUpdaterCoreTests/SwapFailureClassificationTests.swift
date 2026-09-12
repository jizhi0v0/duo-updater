import Foundation
import Testing
@testable import DuoUpdaterCore

/// `replaceItemAt` can put the new bundle in place and *then* throw while removing
/// the one it displaced — observed restoring ToDesk on 2026-08-26. The error it
/// throws then is `NSCocoaErrorDomain 513`, the same code an App Management denial
/// raises, so the error alone cannot say which of the two opposite things happened:
/// for a while the swap answered "go grant App Management" for an update that was
/// already live, with `duo doctor` reporting the permission granted all along. Only
/// the bundle's identity before and after settles it, and `fileExists` cannot —
/// after a successful replacement the path exists too.
///
/// Tested as a function rather than through a real swap because nothing in this
/// process can make the OS produce a land-then-throw on demand; the integration
/// path (a vendor swap whose cleanup fails) stays a manual check. No fixture paths
/// appear here on purpose: the classification takes identities, asks the file
/// system nothing of its own, and so gives the same answer on every machine.
@Suite struct SwapFailureClassificationTests {

    /// The case the whole thing exists for.
    @Test func aBundleWhoseIdentityChangedWasReplacedBeforeTheErrorArrived() {
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: 111, identityAfter: 222)
            == .replacedThenCleanupFailed)
    }

    @Test func anUnchangedIdentityIsAFailedSwap() {
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: 111, identityAfter: 111)
            == .unchanged)
    }

    /// Fail-closed. An identity we could not read on either side must not be
    /// promoted to "replaced": reporting a genuinely failed install as a live
    /// update is the more expensive direction to be wrong in — the row would stop
    /// offering the update and the app would stay behind.
    @Test func anUnreadableIdentityCountsAsUnchanged() {
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: nil, identityAfter: 222) == .unchanged)
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: 111, identityAfter: nil) == .unchanged)
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: nil, identityAfter: nil) == .unchanged)
    }

    /// The privileged path moves the target aside before moving the new bundle in,
    /// so "gone from disk" is a third answer rather than a flavour of unchanged —
    /// `recoverInterruptedSwaps` promotes the `.duoupdater-old` copy back on the
    /// next launch, and the log line for it must not claim the app is fine.
    @Test func aMissingTargetIsItsOwnAnswer() {
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: false, identityBefore: 111, identityAfter: nil) == .targetMissing)
        // Even if something else took that path in the meantime: the target this
        // swap was asked about is not there.
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: false, identityBefore: 111, identityAfter: 222) == .targetMissing)
    }
}
