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
/// The decision is tested as a function, because nothing in this process can make
/// `replaceItemAt` land-then-throw on demand; that integration path stays a manual
/// check. The two identities it is fed are NOT assumed, though: the last two tests
/// run the real exchange each path performs (a `Contents` rotation, and the
/// elevated shell, whose cleanup is made to fail with a `uchg` file) and assert
/// that the inodes it hands the classifier really do move. Every fixture path is
/// invented (`ZZFixture-…`) and lives in a fresh scratch directory, so no test here
/// depends on what this machine has installed.
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

    // MARK: - The identities the two other exchange paths hand it

    /// A rotation (input methods) exchanges what is INSIDE the bundle, so the
    /// identity it must ask about is `Contents`. Run against a real exchange rather
    /// than made-up numbers, because the claim is about what `replaceItemAt` does to
    /// the two inodes — and the second assertion is the whole reason `rotateContents`
    /// may not reuse the whole-bundle question: the bundle's own inode is the thing
    /// a rotation deliberately does not change, so asking it would answer
    /// "unchanged" for a landed update as readily as for a failed one.
    @Test func aRotationsIdentityLivesInContentsNotInTheOuterBundle() throws {
        let fm = FileManager.default
        let scratch = try scratch()
        defer { try? fm.removeItem(at: scratch) }
        let app = scratch.appendingPathComponent("ZZFixture-Rotation.app")
        try fm.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: app.appendingPathComponent("Contents/old"))
        let staged = app.appendingPathComponent(InPlaceSwap.rotationStagedName)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: staged.appendingPathComponent("new"))

        let live = app.appendingPathComponent("Contents")
        let bundleBefore = try inode(of: app)
        let contentsBefore = try inode(of: live)
        _ = try fm.replaceItemAt(
            live, withItemAt: staged,
            backupItemName: InPlaceSwap.rotationBackupName, options: [])
        let contentsAfter = try inode(of: live)
        let bundleAfter = try inode(of: app)

        // The exchange really happened: new payload live, old gone.
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Contents/new").path))
        #expect(!fm.fileExists(atPath: app.appendingPathComponent("Contents/old").path))
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: contentsBefore, identityAfter: contentsAfter)
            == .replacedThenCleanupFailed)
        // Same exchange, wrong question.
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: bundleBefore, identityAfter: bundleAfter)
            == .unchanged)
    }

    /// The elevated shell's last clause — `{ chown …; rm -rf old; }` — runs after
    /// the two renames, so a failure in it exits the chain non-zero with the new
    /// bundle already live. That is the majority route (every root-owned bundle
    /// takes it), and it used to come out as `SwapError.notReplaceable`.
    ///
    /// Reproduced for real, without a password panel: a `uchg` file inside the
    /// bundle survives the rename (flags travel with the inode) and then makes
    /// `rm -rf` fail with EPERM. The assertion is on the pair — non-zero status AND
    /// a changed identity — which is precisely the input `privilegedReplace` now
    /// classifies on.
    @Test func anElevatedSwapWhoseCleanupFailsHasAlreadyPutTheNewBundleLive() throws {
        let fm = FileManager.default
        let scratch = try scratch()
        defer {
            _ = try? shell("/usr/bin/chflags -R nouchg '\(scratch.path)'")
            try? fm.removeItem(at: scratch)
        }
        let target = scratch.appendingPathComponent("ZZFixture-Elevated.app")
        let incoming = scratch.appendingPathComponent("ZZFixture-Incoming.app")
        for (bundle, marker) in [(target, "old"), (incoming, "new")] {
            try fm.createDirectory(
                at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: bundle.appendingPathComponent("Contents/\(marker)"))
        }
        // The thing the trailing `rm -rf` will not be able to remove. Inside the
        // bundle, not the bundle itself: a `uchg` bundle could not be renamed
        // either, and then the exchange would never land — which is the other
        // outcome, not this one.
        let stubborn = target.appendingPathComponent("Contents/pinned")
        try Data("pinned".utf8).write(to: stubborn)
        #expect(try shell("/usr/bin/chflags uchg '\(stubborn.path)'") == 0)

        let before = try inode(of: target)
        let status = try shell(InPlaceSwap.privilegedReplacementShell(
            newApp: incoming, target: target))
        let after = try inode(of: target)

        // The cleanup failed…
        #expect(status != 0)
        // …but the app at that path is the new one.
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
        #expect(InPlaceSwap.classifySwapFailure(
            targetExists: true, identityBefore: before, identityAfter: after)
            == .replacedThenCleanupFailed)
    }

    /// The whole thing, end to end, on the rotation path — the land-then-throw CAN
    /// be produced after all, and this is what it looks like: a `uchg` file inside
    /// the `Contents` being displaced makes `replaceItemAt` install the new one and
    /// then fail deleting the old, with `NSCocoaErrorDomain 513` — the same code
    /// `isAppManagementDenial` matches, measured here, not assumed.
    ///
    /// `rotateContents` must therefore RETURN rather than throw: the input method on
    /// disk is the new build, and the caller has to go on to re-check it.
    @Test func aRotationWhoseCleanupFailsReportsSuccessWithAWarning() throws {
        let fm = FileManager.default
        let scratch = try scratch()
        defer {
            _ = try? shell("/usr/bin/chflags -R nouchg '\(scratch.path)'")
            try? fm.removeItem(at: scratch)
        }
        let target = scratch.appendingPathComponent("ZZFixture-Rotation.app")
        let incoming = scratch.appendingPathComponent("ZZFixture-RotationNew.app")
        for (bundle, marker) in [(target, "old"), (incoming, "new")] {
            try fm.createDirectory(
                at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: bundle.appendingPathComponent("Contents/\(marker)"))
        }
        let stubborn = target.appendingPathComponent("Contents/pinned")
        try Data("pinned".utf8).write(to: stubborn)
        #expect(try shell("/usr/bin/chflags uchg '\(stubborn.path)'") == 0)

        let outcome = try InPlaceSwap.rotateContents(newApp: incoming, over: target)

        #expect(outcome != .replaced)
        if case .replacedButCleanupFailed = outcome {} else {
            Issue.record("expected a cleanup-failure outcome, got \(outcome)")
        }
        // The new build is what an input method would now load.
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
    }

    /// And the same thing through `replace` itself on the unprivileged whole-bundle
    /// path — the finding's original shape. Before this, the 513 went to
    /// `isAppManagementDenial`, the row said "macOS blocked the update: … App
    /// Management permission", and the app on disk was already the new version.
    @Test func anUnprivilegedSwapWhoseCleanupFailsReportsSuccessWithAWarning() throws {
        let fm = FileManager.default
        let scratch = try scratch()
        defer {
            _ = try? shell("/usr/bin/chflags -R nouchg '\(scratch.path)'")
            try? fm.removeItem(at: scratch)
        }
        let target = scratch.appendingPathComponent("ZZFixture-Unprivileged.app")
        let incoming = scratch.appendingPathComponent("ZZFixture-UnprivilegedNew.app")
        for (bundle, marker) in [(target, "old"), (incoming, "new")] {
            try fm.createDirectory(
                at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: bundle.appendingPathComponent("Contents/\(marker)"))
        }
        let stubborn = target.appendingPathComponent("Contents/pinned")
        try Data("pinned".utf8).write(to: stubborn)
        #expect(try shell("/usr/bin/chflags uchg '\(stubborn.path)'") == 0)

        let outcome = try InPlaceSwap.replace(newApp: incoming, over: target)

        if case .replacedButCleanupFailed = outcome {} else {
            Issue.record("expected a cleanup-failure outcome, got \(outcome)")
        }
        #expect(fm.fileExists(atPath: target.appendingPathComponent("Contents/new").path))
    }

    // MARK: - Helpers

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoSwapClassifyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func inode(of url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attrs[.systemFileNumber] as? NSNumber).uint64Value
    }

    private func shell(_ command: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
