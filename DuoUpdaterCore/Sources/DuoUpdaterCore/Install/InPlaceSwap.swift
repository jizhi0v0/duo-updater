import CryptoKit
import Foundation
import Security

/// Thrown when the in-place swap is blocked by the **App Management** privacy
/// gate (`kTCCServiceSystemPolicyAppBundles`): replacing another installed app's
/// bundle fails with `EPERM` until the user grants the permission. This is a
/// distinct, recoverable condition — the UI layer catches it to drive the user
/// to System Settings rather than surfacing a raw "Operation not permitted".
public struct AppManagementRequiredError: LocalizedError {
    /// The app bundle we were trying to replace, for messaging.
    public let targetPath: String

    public var errorDescription: String? {
        "macOS blocked the update: DuoUpdater needs App Management permission to replace an installed app."
    }
}

/// Thrown when the elevated swap was offered and the user **dismissed the
/// administrator prompt**. Distinct from every other swap failure on purpose:
/// nothing is broken and retrying identically would just re-prompt, so the UI
/// records the refusal against this install path and stops offering a one-click
/// Update for it until the user asks again. `osascript` reports the dismissal as
/// AppleScript error `-128` ("User canceled"), which is what `replace` matches.
public struct AuthorizationDeclinedError: LocalizedError {
    /// The app bundle whose replacement was declined — the identity the caller
    /// remembers the refusal under (an install PATH, never a bundle id).
    public let targetPath: String

    public var errorDescription: String? {
        "The update needs an administrator to replace this app, and the request was declined."
    }
}

/// Thrown, before any administrator prompt, when a restore would need one and
/// there is nothing to check the backup against: the installed copy carries no
/// developer certificate, or there is no installed copy at all. The backup and
/// the manifest it is checked against sit in one store this user can rewrite,
/// so root would be putting back whatever is there.
public struct UnverifiableRestoreError: LocalizedError {
    public let targetPath: String

    public var errorDescription: String? {
        let name = URL(fileURLWithPath: targetPath).deletingPathExtension().lastPathComponent
        return String(localized: "Restoring \(name) needs an administrator, and the installed copy has no developer signature to check the backup against — or there is no installed copy. It was not restored. Copy it back by hand from the backup, or reinstall it.")
    }
}

/// The final, destructive step shared by `SparkleInstaller` and `VendorInstaller`:
/// replace the verified `newApp` bundle over the installed `target` bundle.
///
/// Safety properties this enforces, in order:
///   1. **Target validation** — `target` must be an absolute path to an existing
///      `.app` directory that is not a symlink. This runs *before* any destructive
///      action, so a malformed/empty/symlinked path can never reach the privileged
///      `rm -rf`.
///   2. **Quarantine removal** — a bundle that arrives carrying
///      `com.apple.quarantine` keeps it through the swap; left in place, Gatekeeper
///      may block or re-prompt on relaunch, and on macOS 27 launchd will not
///      bootstrap a quarantined plist file (see `stripQuarantine`). Our own downloads
///      were measured carrying none (the #589 probe), so this matters for sources
///      that were already quarantined. We strip it only *after* the caller's
///      signature gates pass.
///   3. **Atomicity** — on a user-writable location we stage the new bundle beside
///      the target and `replaceItemAt` (an atomic same-volume exchange), so a
///      failure leaves the original app fully intact rather than trashed-then-gone.
public enum InPlaceSwap {

    /// Held across the administrator panel in `privilegedReplace`, so two
    /// installs running in parallel raise one panel after the other rather than
    /// two at once. Nothing else takes it, so it cannot deadlock.
    ///
    /// One apply permit of an `InstallPermits` is a FIFO lock whose waiters
    /// suspend. It was an `NSLock` while the wait for `osascript` was a parked
    /// thread anyway; a lock cannot be held across the `await` that replaced it,
    /// and a second installer blocking a thread on it for as long as the first
    /// user takes to answer would bring the parked thread straight back. Its
    /// waiters are not woken by cancellation, which is what a swap wants.
    private static let elevationPanel = InstallPermits(downloads: 0, applies: 1)

    /// Tests only: run the privileged shell this way instead of through
    /// `osascript … with administrator privileges`, so a test can drive the
    /// elevated route — and a mutation that wrongly reaches it — without a
    /// password panel. A task-local, so it reaches every `await` beneath the
    /// test's `withValue`, `InstallCommit`'s inheriting `Task { }` included.
    @TaskLocal static var elevatedShellOverride: (@Sendable (String) async throws -> ChildProcess.Outcome)?

    /// Run one privileged shell: `osascript`, or the test override.
    ///
    /// `.runToCompletion`: once the shell is running, killing `osascript` could
    /// land between `mv tgt old` and `mv new tgt`. stdout is discarded; the
    /// shell's commands print nothing on it.
    private static func runElevated(_ shell: String) async throws -> ChildProcess.Outcome {
        if let elevatedShellOverride { return try await elevatedShellOverride(shell) }
        let appleScript = "do shell script \"\(escapeForAppleScript(shell))\" with administrator privileges"
        return try await ChildProcess.run(
            "/usr/bin/osascript", ["-e", appleScript],
            standardOutput: .discard, onCancel: .runToCompletion)
    }

    /// Recover from a privileged swap (`privilegedReplace`) that was interrupted
    /// between its two renames: the installed app is then sitting at
    /// `<App>.app.duoupdater-old` while `<App>.app` itself is missing. Sweep
    /// `directory` and rename any such orphan back into place — turning a would-be
    /// bricked app back into a working one — and clear stale `.duoupdater-new`/
    /// `-staged` (and present-app `.duoupdater-old`) leftovers, and try the root-owned
    /// `.duoupdater-stage.*` directories a privileged shell left. Best-effort; safe to
    /// run on every launch. Only the non-admin / read-only-parent install path can
    /// leave these behind (the common admin path is a truly atomic `replaceItemAt`),
    /// and only builds from before it staged in root's own directory under
    /// `/private/var/tmp` (`privilegedStagingRoot`), which this sweep does not reach.
    ///
    /// Takes the machine-wide install lock first, like every other path that
    /// replaces a bundle. Without it this sweep is not recovery but interference:
    /// `<App>.app.duoupdater-new` is exactly what a live install has parked beside
    /// its target, so the menu-bar app's first refresh could delete the staging
    /// directory `duo` is still `ditto`-ing into. The claim is non-blocking, as
    /// `InstallLock` always is — a launch-time sweep has nothing to wait for, and
    /// whatever it skips it will find again next launch.
    ///
    /// It is `ProcessInstallLock`, so an install running in *this* process joins
    /// the claim rather than refusing it. That is the documented refcount and it
    /// is what lets the app apply two updates at once; it does mean this sweep is
    /// serialised only against other processes.
    ///
    /// Returns whether the directory was actually swept. False means only that
    /// the lock was busy, and the caller must not treat that as "done": a
    /// caller latching a once-per-session flag on a deferred sweep would leave a
    /// genuine leftover from an earlier crash unrecovered until the next launch,
    /// which is the opposite of what this exists for.
    @discardableResult
    public static func recoverInterruptedSwaps(
        in directory: URL, lock: ProcessInstallLock = .shared
    ) async -> Bool {
        do {
            try await lock.claim()
        } catch {
            Log.install.notice(
                "another installer holds the install lock, sweep deferred: \(error, privacy: .public)")
            return false
        }
        defer { await lock.release() }
        // Off the cooperative pool: the sweep validates every orphan it finds with
        // `SecStaticCodeCheckValidity`, which is the exact call #351 measured
        // parking all three cooperative threads on a 3-core runner, and this is
        // reached from a `Task.detached` that runs on that same pool. See
        // `offCooperativePool`.
        await offCooperativePool(qos: .utility) { sweepInterruptedSwaps(in: directory) }
        return true
    }

    /// The sweep itself, once the lock is held.
    private static func sweepInterruptedSwaps(in directory: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: []) else { return }
        let oldSuffix = ".duoupdater-old"
        let newSuffix = ".duoupdater-new"
        let stagedPrefix = ".duoupdater-staged-"
        for entry in entries {
            let name = entry.lastPathComponent
            if name.hasSuffix(oldSuffix) {
                let appURL = directory.appendingPathComponent(String(name.dropLast(oldSuffix.count)))
                if fm.fileExists(atPath: appURL.path) {
                    try? fm.removeItem(at: entry)             // real app present → stale copy
                } else if !orphanSignatureLooksValid(entry) {
                    // Verify before promoting: this runs on every launch and acts on
                    // any `*.app.duoupdater-old` it finds. An attacker who can write to
                    // an app directory could plant a malicious `<App>.app.duoupdater-old`
                    // (with `<App>.app` absent) and have us auto-promote it to the live
                    // app — so we refuse to promote an orphan whose present code
                    // signature no longer validates (corruption/tampering). Leave it in
                    // place rather than deleting it, so a later manual investigation is
                    // still possible. A genuinely unsigned bundle is still allowed below
                    // (the helper distinguishes that from a failed present signature),
                    // matching BackupStore's tolerance.
                    Log.install.error(
                        "refusing to recover \(appURL.lastPathComponent, privacy: .public): its pre-swap backup failed signature validation (may be corrupted or planted) — left in place")
                } else if (try? fm.moveItem(at: entry, to: appURL)) != nil {
                    Log.install.error(
                        "recovered an interrupted update: restored \(appURL.lastPathComponent, privacy: .public) from its pre-swap backup")
                }
            } else if name.hasSuffix(newSuffix) || name.hasPrefix(stagedPrefix) {
                try? fm.removeItem(at: entry)                 // unused new/staged leftover
            } else if name.contains(privilegedStagingInfix) {
                // A privileged shell's `mktemp -d` staging directory: root-owned
                // and 0700, so this unprivileged sweep normally cannot remove it.
                // The next privileged swap or place-back of the same app clears
                // every one of these first (`privilegedStagingPrologue`); said
                // here so a leftover is not silent until then.
                do { try fm.removeItem(at: entry) } catch {
                    Log.install.notice(
                        "left \(name, privacy: .public) for the next privileged swap of that app to clear — \(error.localizedDescription, privacy: .public)")
                }
            } else if name.hasSuffix(".app"), usesContentsRotation(target: entry) {
                recoverInterruptedRotation(in: entry)
            }
        }
    }

    /// Recover a `rotateContents` interrupted between its two renames: the
    /// bundle's `Contents` is gone while `.Contents.duoupdater-old` still holds the
    /// copy it displaced, leaving an input method the system can no longer load.
    /// Puts it back, and clears both staging directories once the real `Contents`
    /// is present. Best-effort, like the whole-bundle sweep it runs beside.
    private static func recoverInterruptedRotation(in app: URL) {
        let fm = FileManager.default
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let staged = app.appendingPathComponent(rotationStagedName)
        let backup = app.appendingPathComponent(rotationBackupName)

        if !fm.fileExists(atPath: contents.path), fm.fileExists(atPath: backup.path) {
            guard (try? fm.moveItem(at: backup, to: contents)) != nil else {
                Log.install.error(
                    "could not restore \(app.lastPathComponent, privacy: .public)/Contents from its pre-swap copy — the input method is still unloadable")
                return
            }
            // Validated AFTER the promotion, not before: `codesign` reads a bundle,
            // and a bare `Contents` directory is not one — so the only way to ask
            // is with it in place, and to undo the move when the answer is no.
            //
            // The threat model differs from the whole-bundle sweep's on purpose.
            // There, the orphan sits in the *enclosing* directory, which may be far
            // more writable than the app; here it sits INSIDE the bundle, so anyone
            // who could plant it could equally have overwritten `Contents` outright
            // and never involved us. What this check is actually worth is catching
            // the copy that is merely broken — a `ditto` cut off mid-write.
            if orphanSignatureLooksValid(app) {
                Log.install.error(
                    "recovered an interrupted update: restored \(app.lastPathComponent, privacy: .public)/Contents from its pre-swap copy")
            } else {
                try? fm.moveItem(at: contents, to: backup)
                Log.install.error(
                    "refusing to recover \(app.lastPathComponent, privacy: .public)/Contents: the pre-swap copy fails signature validation (may be truncated) — left in place")
                return
            }
        }

        guard fm.fileExists(atPath: contents.path) else { return }
        for leftover in [staged, backup] where fm.fileExists(atPath: leftover.path) {
            do { try fm.removeItem(at: leftover) } catch {
                // Named rather than swallowed, and this one is not housekeeping: ANY
                // entry at a bundle's root breaks its seal, hidden and empty
                // included. Measured on a copy of the real DoubaoIme bundle —
                // `codesign --verify --strict` goes from "valid on disk" to
                // "unsealed contents present in the bundle root" the moment an empty
                // `.Contents.duoupdater-new` exists, and back again when it is
                // removed. (`.DS_Store` is exempt by the signing rules; ours is
                // not.) A leftover we cannot clear is an input method that fails
                // Gatekeeper, so it has to be said out loud.
                Log.install.error(
                    "could not clear \(leftover.lastPathComponent, privacy: .public) inside \(app.lastPathComponent, privacy: .public) — its code signature will not validate while that is there: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// True if the orphaned `*.duoupdater-old` bundle either validates cleanly or is
    /// simply unsigned; false only when a present signature fails to validate
    /// (corruption/tampering). Mirrors `BackupStore.backupSignatureLooksValid` but is
    /// kept local on purpose — recovery in Core must not depend on the App-layer
    /// backup store. The threat it guards: this runs unattended on every launch, so a
    /// planted `*.duoupdater-old` could otherwise be auto-promoted to a live app.
    private static func orphanSignatureLooksValid(_ bundle: URL) -> Bool {
        do {
            try SignatureVerifier.verifyCodeSignature(appAt: bundle)
            return true
        } catch let SignatureVerifier.VerifyError.codeSignatureInvalid(status)
                    where status == errSecCSUnsigned {
            return true
        } catch {
            return false
        }
    }

    enum SwapError: LocalizedError {
        case invalidTarget(String)
        case notReplaceable(String)

        var errorDescription: String? {
            switch self {
            case .invalidTarget(let msg):
                return "Refusing to replace the installed app: \(msg)"
            case .notReplaceable(let msg):
                return "Could not replace the installed app: \(msg)"
            }
        }
    }

    /// Where the bundle stood when a swap threw. Decided by the target's identity
    /// before and after, not by its existence: after a successful replacement the
    /// path exists too, so `fileExists` answers the same for two opposite outcomes.
    ///
    /// Pure and separately testable because the branch it drives is the difference
    /// between "the update failed, go grant App Management" and "the update is
    /// live". `replaceItemAt` really does produce the middle case — observed
    /// restoring ToDesk on 2026-08-26, where the new bundle was in place and the
    /// error came from removing the one it displaced — and `NSCocoaErrorDomain 513`
    /// is exactly what `isAppManagementDenial` matches, so that landed install was
    /// reported as a permission failure.
    ///
    /// Fail-closed: an identity we could not read on either side counts as
    /// `unchanged`, i.e. a failure, rather than being promoted to a success.
    enum SwapFailureSite: Equatable {
        /// The exchange landed; the error came afterwards, from the cleanup. The
        /// new version is live.
        case replacedThenCleanupFailed
        /// The app on disk is the one that was there before.
        case unchanged
        /// The target is gone from disk (the privileged path moved it aside and
        /// could not restore it).
        case targetMissing
    }

    static func classifySwapFailure(
        targetExists: Bool, identityBefore: UInt64?, identityAfter: UInt64?
    ) -> SwapFailureSite {
        guard targetExists else { return .targetMissing }
        if let before = identityBefore, let after = identityAfter, before != after {
            return .replacedThenCleanupFailed
        }
        return .unchanged
    }

    /// What a completed `replace` did. Both cases are success — `replace` returning
    /// at all means the new version is live — and no caller branches on this today:
    /// they discard it, which is the point of the second case existing instead of a
    /// throw. The debris the cleanup left behind is reported in the log, not to the
    /// row. (Surfacing it as a note on the row would need a channel through
    /// `InstallCoordinator.Outcome`; deliberately not built.)
    enum SwapOutcome: Equatable {
        case replaced
        /// The exchange landed and then threw while clearing up after itself — the
        /// bundle it displaced left behind, typically. The version on disk HAS
        /// changed, so the install is finished: re-check and restart info must be
        /// computed exactly as for `.replaced`.
        case replacedButCleanupFailed(String)
    }

    /// Replace `target` with `newApp`. Tries a user-level atomic swap first; if the
    /// location needs admin rights, falls back to an authenticated copy.
    ///
    /// Runs to completion once started, even if the calling task is cancelled.
    /// Nothing in here checks for cancellation, and each child process it starts
    /// (`xattr`, `chmod`, the privileged `osascript`) is `.runToCompletion`, so a
    /// cancel can neither stop the sequence between its renames nor kill the
    /// shell that is performing them: the target ends up the old bundle or the new
    /// one, never a mixture. That is what the `offCooperativePool` hop callers
    /// used to make guaranteed, and they no longer make it.
    ///
    /// `stagedCheck` is what the privileged shell re-checks its staged copy
    /// against: for an install, what `verifyInstallArtifact` returned for
    /// `newApp`; for a restore, what `BackupStore.verifyRestoreAuthenticity`
    /// returned — the installed copy's designated requirement, checked without
    /// resources, because a faithful backup of an app that writes inside its own
    /// bundle is signature-invalid by nature (`BackupManifest`). Nil adds no check.
    ///
    /// `refuseElevationWithoutCheck`: a restore's. With no `stagedCheck` there
    /// is nothing this user cannot rewrite that says what root should accept —
    /// the backup's manifest sits in the same store as the backup — so the
    /// elevated route throws `UnverifiableRestoreError` before any panel. Asked
    /// here, where the route is decided, not by the caller beforehand: making a
    /// bundle this user owns read-only would otherwise turn the answer.
    @discardableResult
    static func replace(
        newApp: URL, over target: URL, stagedCheck: StagedCopyRequirement? = nil,
        refuseElevationWithoutCheck: Bool = false
    ) async throws -> SwapOutcome {
        try validateTarget(target)
        await stripQuarantine(newApp)
        // The single moment the user's disk actually changes. Logged at `.notice`
        // on both sides, because "the app was never replaced" — the state behind
        // an update that reports done and changes nothing — was previously
        // indistinguishable from "replaced successfully" in every record we kept.
        //
        // The completion flag matters: a bare `defer` would announce the same line
        // whether the swap worked or threw, and "it said it finished" that means
        // nothing either way is the exact ambiguity this is here to remove.
        let elevated = needsElevatedReplace(target: target)
        var replaced = false
        // The bundle's identity before we touch it. `fileExists` cannot answer the
        // question the failure branch asks: after a successful replacement the path
        // exists too, so it reported "the app on disk is unchanged" for both
        // outcomes. `replaceItemAt` can put the new bundle in place and *then*
        // throw while removing the one it displaced — observed restoring ToDesk on
        // 2026-08-26, where the app really had been replaced and the log said the
        // opposite. The inode distinguishes them.
        // For a rotation the outer bundle is deliberately the thing that does NOT
        // change, so asking it would answer "unchanged" for every outcome — the
        // failure this line exists to distinguish (`replaceItemAt` lands the new
        // item and then throws while removing what it displaced) would be reported
        // as "the app on disk is unchanged" with the new version live. Ask the
        // thing the exchange actually replaces.
        let identityTarget = usesContentsRotation(target: target)
            ? target.appendingPathComponent("Contents", isDirectory: true)
            : target
        let identityBefore = inode(of: identityTarget)
        var cleanupFailure: String?
        Log.install.notice(
            "swap start: \(target.lastPathComponent, privacy: .public) elevated=\(elevated, privacy: .public)")
        defer {
            if replaced {
                if let cleanupFailure {
                    Log.install.error(
                        "swap replaced \(target.lastPathComponent, privacy: .public) but its cleanup failed — the new version is live and the caller is told to carry on: \(cleanupFailure, privacy: .public)")
                } else {
                    Log.install.notice("swap done: \(target.lastPathComponent, privacy: .public)")
                }
            } else if FileManager.default.fileExists(atPath: identityTarget.path) {
                switch Self.classifySwapFailure(
                    targetExists: true,
                    identityBefore: identityBefore,
                    identityAfter: inode(of: identityTarget)) {
                case .replacedThenCleanupFailed:
                    // A backstop, and deliberately kept as one. All three exchange
                    // paths now classify themselves and RETURN on this outcome, so
                    // nothing throws its way here today — but a future throw added
                    // after an exchange would otherwise be logged as "the app on
                    // disk is unchanged", which is the untrue half of the pair this
                    // whole comparison exists to separate.
                    Log.install.error(
                        "swap threw for \(target.lastPathComponent, privacy: .public) but the bundle at that path was REPLACED anyway — the error came after the exchange, so the new version is live and the failure is in the cleanup")
                case .unchanged, .targetMissing:
                    Log.install.error(
                        "swap did NOT replace \(target.lastPathComponent, privacy: .public) — the app on disk is unchanged")
                }
            } else {
                // The privileged path moves the target aside before moving the new
                // bundle in, and restores it if that fails. If the restore ALSO
                // fails the app is missing from disk — and this is the one moment
                // the line is load-bearing, so it must not claim the opposite.
                // The pre-swap copy is parked in root's staging directory, which
                // the shell then keeps and names on stderr; the launch sweep
                // cannot reach it there (`privilegedStagingPrologue`).
                Log.install.error(
                    "swap did NOT complete and \(target.lastPathComponent, privacy: .public) is MISSING from disk — its pre-swap copy was kept in root's staging folder under \(privilegedStagingRoot, privacy: .public)")
            }
        }

        // Input methods keep their outer `.app` and exchange what is inside it —
        // see `usesContentsRotation`. Never elevated, and that is not a shortcut:
        // the elevated route cannot do this at all (see `rotateContents`).
        if usesContentsRotation(target: target) {
            let outcome = try await rotateContents(newApp: newApp, over: target)
            replaced = true
            if case .replacedButCleanupFailed(let reason) = outcome { cleanupFailure = reason }
            return outcome
        }

        if !elevated {
            // Off the cooperative pool: the exchange is synchronous disk work, and
            // `replaceItemAt` deletes the bundle it displaces — a whole app, which
            // for a large one is seconds of I/O. The hop it used to sit in (every
            // caller reached `replace` through `offCooperativePool`) is gone now
            // that the child processes around it are awaited, so this segment
            // takes its own. See `offCooperativePool`.
            let outcome = try await offCooperativePool(qos: .userInitiated) {
                try exchangeUnprivileged(
                    newApp: newApp, over: target,
                    identityTarget: identityTarget, identityBefore: identityBefore)
            }
            replaced = true
            if case .replacedButCleanupFailed(let reason) = outcome { cleanupFailure = reason }
            return outcome
        }

        if refuseElevationWithoutCheck, stagedCheck == nil {
            throw UnverifiableRestoreError(targetPath: target.path)
        }
        let elevatedOutcome = try await privilegedReplace(
            newApp: newApp, target: target, stagedCheck: stagedCheck)
        replaced = true
        if case .replacedButCleanupFailed(let reason) = elevatedOutcome { cleanupFailure = reason }
        return elevatedOutcome
    }

    // MARK: - Place back

    /// Whether nothing at all is at `target` — not a bundle, not a symlink, not
    /// a file. `lstat`, not `fileExists`: a dangling symlink is something, and
    /// it belongs to `replace`, whose validation refuses it.
    static func isAbsent(_ target: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: target.path)) == nil
    }

    /// Put `newApp` at `target`, where there is nothing — a restore whose app
    /// vanished. `brew install --cask --force` removes the old bundle from
    /// `/Applications` before it moves the new one in; cut off between the two
    /// (a signal skips its revert, and a dead pipe likely breaks it), the app is
    /// simply gone. There is nothing to exchange with, and `replace` refuses a
    /// missing target on purpose (`validateTarget`), so this is the separate,
    /// smaller operation.
    ///
    /// Never overwrites: a target that appears in the meantime makes this fail
    /// rather than be replaced or, worse, have the copy moved inside it.
    ///
    /// Runs to completion once started, as `replace` does: nothing checks for
    /// cancellation and the privileged shell is `.runToCompletion`.
    ///
    /// `stagedCheck` and `refuseElevationWithoutCheck` as for `replace`. Every
    /// caller today is a restore, and with nothing installed there is no
    /// signature to check against, so its elevated route is refused.
    static func placeBack(
        newApp: URL, at target: URL, stagedCheck: StagedCopyRequirement? = nil,
        refuseElevationWithoutCheck: Bool = false
    ) async throws {
        try validatePlacement(target)
        await stripQuarantine(newApp)
        let elevated = placeBackNeedsElevation(at: target)
        Log.install.notice(
            "place back start: \(target.lastPathComponent, privacy: .public) elevated=\(elevated, privacy: .public)")
        if elevated {
            if refuseElevationWithoutCheck, stagedCheck == nil {
                throw UnverifiableRestoreError(targetPath: target.path)
            }
            try await privilegedPlaceBack(newApp: newApp, target: target, stagedCheck: stagedCheck)
        } else {
            // Off the pool: the first move can be a whole-bundle copy when the
            // scratch copy is on another volume.
            try await offCooperativePool(qos: .userInitiated) {
                try placeUnprivileged(newApp: newApp, at: target)
            }
        }
        Log.install.notice("place back done: \(target.lastPathComponent, privacy: .public)")
    }

    /// Whether putting a bundle at `target` has to go through the administrator
    /// prompt. Only the enclosing directory is asked: there is no bundle to
    /// unlink, which is the other half of `needsElevatedReplace`'s question.
    static func placeBackNeedsElevation(at target: URL) -> Bool {
        !FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    /// `validateTarget`'s path rules, for a target that must NOT exist, in a
    /// directory that must.
    static func validatePlacement(_ target: URL) throws {
        let path = target.path
        guard target.isFileURL, path.hasPrefix("/"), path.hasSuffix(".app"), path.count > 4 else {
            throw SwapError.invalidTarget("“\(path)” is not an absolute .app path.")
        }
        guard isAbsent(target) else {
            throw SwapError.invalidTarget("“\(path)” already exists.")
        }
        let parent = target.deletingLastPathComponent()
        let vals = try? parent.resourceValues(forKeys: [.isDirectoryKey])
        guard vals?.isDirectory == true else {
            throw SwapError.invalidTarget("“\(parent.path)” is not an existing folder.")
        }
    }

    /// The unprivileged place-back: stage beside the target under the name the
    /// launch sweep already clears (`.duoupdater-staged-`), then one rename. So
    /// the app appears whole or not at all — a copy cut off across volumes
    /// leaves only a hidden leftover — and `moveItem` refuses to overwrite.
    private static func placeUnprivileged(newApp: URL, at target: URL) throws {
        let fm = FileManager.default
        let staged = target.deletingLastPathComponent()
            .appendingPathComponent(".duoupdater-staged-\(target.lastPathComponent)")
        try? fm.removeItem(at: staged)
        do {
            try fm.moveItem(at: newApp, to: staged)
            try fm.moveItem(at: staged, to: target)
        } catch {
            try? fm.removeItem(at: staged)
            Log.install.error(
                "place back: \(target.lastPathComponent, privacy: .public) was not put back — \(error.localizedDescription, privacy: .public)")
            if isAppManagementDenial(error) {
                throw AppManagementRequiredError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(error.localizedDescription)
        }
    }

    /// The administrator half: one `osascript` shell, behind the same one-panel
    /// lock as `privilegedReplace`, and declining it reads the same way.
    private static func privilegedPlaceBack(
        newApp: URL, target: URL, stagedCheck: StagedCopyRequirement?
    ) async throws {
        let shell = privilegedPlacementShell(newApp: newApp, target: target, requirement: stagedCheck)
        let outcome = try await elevationPanel.withApplyPermit {
            try await runElevated(shell)
        }
        guard outcome.terminationStatus == 0 else {
            let msg = String(data: outcome.standardError, encoding: .utf8) ?? "unknown error"
            if isAuthorizationDeclined(msg) {
                throw AuthorizationDeclinedError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(msg)
        }
    }

    /// The authenticated shell for a place-back, split out so it can be run in a
    /// temporary directory without a password panel.
    ///
    /// The copy is materialised in a root-owned `mktemp -d` directory beside the
    /// target (`privilegedStagingPrologue`), re-checked there when `requirement`
    /// is given (see `placeBack`), then renamed in.
    /// The rename is guarded by `test ! -e` and `test ! -L`: `mv` onto an existing
    /// directory does not fail, it moves the source INSIDE it, so without the
    /// guard a bundle that appeared in the meantime would get a second app
    /// nested in it. Every exit removes the staging directory.
    ///
    /// Ownership is left as `ditto` makes it — the source's, i.e. the user's.
    /// `privilegedReplacementShell` copies the owner off the bundle it replaces;
    /// here there is none to copy from, and inventing one is not this
    /// function's call.
    static func privilegedPlacementShell(
        newApp: URL, target: URL, requirement: StagedCopyRequirement? = nil
    ) -> String {
        let new = stagedPath(for: target)
        let tgt = shellQuote(target.path)
        let src = shellQuote(newApp.path)
        return """
        \(privilegedStagingPrologue(target: target))\
        /usr/bin/ditto \(src) \(new) && \
        \(stagedCopyCheck(new, requirement))\
        /bin/test ! -e \(tgt) && /bin/test ! -L \(tgt) && \
        /bin/mv \(new) \(tgt)
        """
    }

    // MARK: - Privileged staging

    /// What builds before root staged in `privilegedStagingRoot` named their
    /// staging directory: `<App>.app` + this + `mktemp`'s six random characters,
    /// beside the target. The launch sweep and the prologue still clear them.
    static let privilegedStagingInfix = ".duoupdater-stage."

    /// Where root stages. Not beside the target: `/Applications` is
    /// `root:admin` 775 and not sticky, so the user can rename root's own 0700
    /// directory there and put one of its own at that name — measured
    /// 2026-10-25, macOS 27.2: `mv` of a root 0700 directory in `/Applications`
    /// as the admin user, status 0, then `mkdir` at the old name, status 0.
    /// Root's `ditto`, `codesign` and `mv` all go by that name, so the bytes it
    /// checked and the bytes it moved in could come from a directory the user
    /// writes. `/private/var/tmp` is `root:wheel` 1777: sticky, so an entry
    /// root made can be renamed or removed by root alone.
    static let privilegedStagingRoot = "/private/var/tmp"

    /// The name root's staging directories for `target` start with in
    /// `privilegedStagingRoot`, before `mktemp`'s six characters. Per target, so
    /// a shell clears what an earlier one for the same app left without
    /// touching another install's; hashed, so nothing in a path reaches a
    /// `find -name` pattern.
    static func privilegedStagingPrefix(for target: URL) -> String {
        let digest = SHA256.hash(data: Data(target.path.utf8))
        return "duoupdater-stage." + digest.prefix(8).map { String(format: "%02x", $0) }.joined() + "."
    }

    /// What every privileged shell opens with. A fixed name is one the user can
    /// place a symlink or a directory of its own at between root's `rm` and its
    /// `ditto`; `mktemp -d` makes a directory that did not exist, mode 0700 and
    /// owned by root, in `privilegedStagingRoot`, where it stays root's.
    ///
    /// The final `mv` into place has to be a rename — across volumes `mv` falls
    /// back to copying, and the app would be half there while it does — so a
    /// target whose folder is on another volume is refused here, before
    /// anything is copied or moved. (Same device on the development machine
    /// for `/Applications`, `~/Applications` and `/private/var/tmp`, 16777229,
    /// measured 2026-10-25: all on the Data volume.)
    ///
    /// The trap removes the directory on every exit, success included — unless
    /// the target is missing and the bundle it displaced is parked in it
    /// (`stagedOldPath`): then it is the only copy of the app, and stays where
    /// only root can reach it rather than being deleted; the shell says where
    /// on stderr. The `find` clears what a killed shell left for this target,
    /// root-owned ones only, and only when the target is there, for the same
    /// reason. The leading `rm` clears the beside-target names older builds
    /// used. `rm` acts on a symlink itself, never its target.
    static func privilegedStagingPrologue(target: URL, alsoRemoving extra: String = "") -> String {
        let tgt = shellQuote(target.path)
        let parent = shellQuote(target.deletingLastPathComponent().path)
        let root = privilegedStagingRoot
        let prefix = privilegedStagingPrefix(for: target)
        return "/bin/rm -rf \(extra)\(tgt)\(privilegedStagingInfix)*; "
            + "/bin/test -e \(tgt) && /usr/bin/find \(root) -maxdepth 1 -name '\(prefix)*' -type d -user 0 "
            + "-exec /bin/rm -rf {} +; "
            + "S=$(/usr/bin/mktemp -d \(root)/\(prefix)XXXXXX) || exit 1; "
            + "T=\(tgt); O=\(stagedOldPath(for: target)); "
            + "trap 'if /bin/test -e \"$T\" || /bin/test ! -e \"$O\"; then /bin/rm -rf \"$S\"; "
            + "else echo \"The app was moved aside and could not be put back. It is at $O.\" >&2; fi' EXIT; "
            + "/bin/test \"$(/usr/bin/stat -f %d \"$S\")\" = \"$(/usr/bin/stat -f %d \(parent))\" || "
            + "{ echo \"The app's folder is not on the same disk as \(root), where DuoUpdater stages an "
            + "administrator install. Nothing was changed.\" >&2; exit 1; }; "
    }

    /// The staged copy's path inside the prologue's directory, for the shell.
    static func stagedPath(for target: URL, appending component: String? = nil) -> String {
        let name = component.map { target.lastPathComponent + "/" + $0 } ?? target.lastPathComponent
        return "\"$S\"/" + shellQuote(name)
    }

    /// Where a privileged swap parks the bundle it displaces: inside the
    /// prologue's directory, for the reason the staged copy is there. A fixed
    /// `<App>.app.duoupdater-old` beside the target is a name the user can put
    /// a directory at, and `mv` onto a directory moves INTO it.
    static func stagedOldPath(for target: URL) -> String {
        "\"$S\"/" + shellQuote(target.lastPathComponent + ".duoupdater-old")
    }

    /// What a staged copy must still satisfy when root is about to rename it in.
    /// The Swift gates ran on a bundle in a user-writable scratch directory and
    /// root then copies it from there, so the copy root holds is checked again,
    /// by root, in the same shell. Made by `verifyInstallArtifact`, at the gate
    /// (`stagedCopyRequirement`), for an install, and by
    /// `BackupStore.verifyRestoreAuthenticity` for a restore.
    struct StagedCopyRequirement: Equatable, Sendable {
        let text: String
        /// Check every slice. A cdhash names one slice's signature, so that
        /// form is checked on this Mac's slice only.
        let allArchitectures: Bool
        /// False for a restore: the check `verifyRestoreAuthenticity` made,
        /// without resources (`stagedCopyCheck`).
        let validatesResources: Bool
        /// An install's gate-2 cdhash beside a `text` that is a designated
        /// requirement, checked as well: the requirement names a signer, and
        /// every build that signer ever shipped meets it.
        let pinnedCdhash: String?

        init(
            text: String, allArchitectures: Bool, validatesResources: Bool = true,
            pinnedCdhash: String? = nil
        ) {
            self.text = text
            self.allArchitectures = allArchitectures
            self.validatesResources = validatesResources
            self.pinnedCdhash = pinnedCdhash
        }
    }

    /// Decided at the gate, from what the gate saw:
    /// - An installed copy signed with a certificate: its designated
    ///   requirement, re-aimed at the download's identifier on a rename — gate
    ///   3b's rule (`SignatureVerifier.verifySignedLikeInstalledCopy`) — AND
    ///   `gatedCdhash`. The requirement alone keeps out another signer, not
    ///   another build of this one: an older, vulnerable release of the same
    ///   app meets it just as well, and could be put in the download's place
    ///   while the administrator panel is up. The cdhash names the build gate
    ///   2 passed.
    /// - Otherwise (an ad-hoc installed copy, whose requirement is its own
    ///   cdhash, or an unsigned one): `gatedCdhash`, which gate 2 read off the
    ///   `SecStaticCode` it had just validated
    ///   (`verifyCodeSignatureCapturingCdhash`) — so the staged copy must carry
    ///   the code directory that passed gate 2.
    /// - Neither (gate 2 reported no cdhash): nil, and the shell checks
    ///   nothing. Gate 2 refuses an unsigned download, so this is not expected
    ///   on an install; it is a residual, not a guarantee.
    ///
    /// Blocking Security calls; callers stay off the cooperative pool.
    static func stagedCopyRequirement(
        installed: URL, downloaded: URL, gatedCdhash: String?
    ) -> StagedCopyRequirement? {
        if let summary = SignatureVerifier.signingSummary(at: installed),
           !summary.authorities.isEmpty, !summary.flags.contains("adhoc"),
           let text = try? SignatureVerifier.installedSignerRequirement(
               installedApp: installed, downloadedApp: downloaded) {
            return StagedCopyRequirement(text: text, allArchitectures: true, pinnedCdhash: gatedCdhash)
        }
        guard let gatedCdhash else { return nil }
        return StagedCopyRequirement(text: "cdhash H\"\(gatedCdhash)\"", allArchitectures: false)
    }

    /// The `codesign` clause for `quotedPath`, `&&`-terminated, or empty when
    /// there is nothing to check.
    ///
    /// A restore's (`validatesResources` false) is `verifyRestoreAuthenticity`'s
    /// check: `--ignore-resources` is codesign(1)'s "do not validate the
    /// contents of the code's resources", and on ten tampered copies of a
    /// Developer ID app it refused and passed exactly what
    /// `SecStaticCodeCheckValidity` with `kSecCSDoNotValidateResources` did
    /// (2026-10-25; the code directory, Info.plist and every slice of the main
    /// executable are still checked). No `--deep`/`--strict`: both reach into
    /// resources. What resource validation would have caught structurally is
    /// asked instead: `Contents` and `Contents/MacOS` must not be links. With
    /// `Contents/MacOS` pointing out of the bundle every signature check passes
    /// on a genuine copy, `ditto` keeps the link, and once root has renamed the
    /// bundle in, the main executable is whatever that outside file becomes.
    static func stagedCopyCheck(_ quotedPath: String, _ requirement: StagedCopyRequirement?) -> String {
        guard let requirement else { return "" }
        let archs = requirement.allArchitectures ? "--all-architectures " : ""
        let req = shellQuote("=" + requirement.text)
        guard requirement.validatesResources else {
            return "/bin/test ! -L \(quotedPath)/Contents && /bin/test ! -L \(quotedPath)/Contents/MacOS && "
                + "/usr/bin/codesign --verify --ignore-resources \(archs)-R \(req) \(quotedPath) && "
        }
        // The pin is this Mac's slice only (a cdhash names one), and without
        // resources: the clause before it has just validated them, on every
        // slice, in a directory only root can write, and the code directory the
        // cdhash names seals them. Asking again would hash a whole Xcode twice.
        let pin = requirement.pinnedCdhash.map {
            "/usr/bin/codesign --verify --ignore-resources -R \(shellQuote("=cdhash H\"\($0)\"")) \(quotedPath) && "
        } ?? ""
        return "/usr/bin/codesign --verify --deep --strict \(archs)-R \(req) \(quotedPath) && " + pin
    }

    /// The unprivileged whole-bundle exchange — `replace`'s non-elevated route,
    /// synchronous so it can run in one `offCooperativePool` hop. Returns
    /// `.replaced`, or `.replacedButCleanupFailed` when the exchange landed and its
    /// cleanup threw; throws when the bundle on disk is unchanged.
    private static func exchangeUnprivileged(
        newApp: URL, over target: URL, identityTarget: URL, identityBefore: UInt64?
    ) throws -> SwapOutcome {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        // Stage the new bundle beside the target (same volume), then atomically
        // exchange it in. `replaceItemAt` renames on success and leaves the
        // original untouched on failure — no window where the app is missing.
        let staged = parent.appendingPathComponent(".duoupdater-staged-\(target.lastPathComponent)")
        try? fm.removeItem(at: staged)
        try fm.moveItem(at: newApp, to: staged)
        do {
            _ = try fm.replaceItemAt(target, withItemAt: staged, backupItemName: nil, options: [])
        } catch {
            // What actually went wrong, before it is folded into one of two
            // user-facing shapes. Both of those describe a cause rather than
            // report the error, so without this line a misclassification is
            // indistinguishable from the real thing — which is how a ToDesk
            // restore that had already landed came out as "grant App
            // Management", with `duo doctor` saying it was granted all along.
            let ns = error as NSError
            Log.install.error(
                "swap: replaceItemAt threw for \(target.lastPathComponent, privacy: .public) — \(ns.domain, privacy: .public) \(ns.code, privacy: .public): \(ns.localizedDescription, privacy: .public)")
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                Log.install.error(
                    "swap: underlying \(underlying.domain, privacy: .public) \(underlying.code, privacy: .public): \(underlying.localizedDescription, privacy: .public)")
            }
            // A staged sibling we cannot clear is left in `/Applications` for
            // good — root-owned after a package install, and `try?` said
            // nothing about it. `recoverInterruptedSwaps` sweeps unprivileged
            // and cannot remove it either, so name it here or nobody learns.
            if fm.fileExists(atPath: staged.path) {
                do { try fm.removeItem(at: staged) } catch {
                    Log.install.error(
                        "swap: left \(staged.lastPathComponent, privacy: .public) behind in \(parent.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                }
            }
            // Which of the two opposite things just happened. `replaceItemAt`
            // can land the new bundle and then throw while removing the one it
            // displaced, and both user-facing shapes below describe a CAUSE for
            // an update that did not happen — so classifying first is what
            // stops a landed install from being reported as a missing
            // permission (the ToDesk restore of 2026-08-26: 513 both times).
            // The cleanup failure is still said out loud, in the `defer`.
            let site = Self.classifySwapFailure(
                targetExists: fm.fileExists(atPath: identityTarget.path),
                identityBefore: identityBefore,
                identityAfter: inode(of: identityTarget))
            if site == .replacedThenCleanupFailed {
                return .replacedButCleanupFailed(error.localizedDescription)
            }
            // `/Applications` is group-writable for admins, so we took the
            // user-level path — but replacing *another app's* bundle is gated
            // by App Management on macOS 13+. That denial surfaces as EPERM;
            // hand it to the UI as a recoverable, typed error.
            if isAppManagementDenial(error) {
                throw AppManagementRequiredError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(error.localizedDescription)
        }
        return .replaced
    }

    /// Whether replacing `target` has to go through the administrator prompt.
    ///
    /// **Both** the bundle and its enclosing directory have to be writable before
    /// we may skip escalation, and each half catches a case the other misses:
    ///
    ///   * the **parent**, because `replaceItemAt` stages its exchange as a
    ///     sibling — a bundle we could write into but whose enclosing directory we
    ///     cannot (`/Library/Input Methods` is `root:wheel` 755, while
    ///     `WeType.app` inside it is `root:staff` 775) still cannot be swapped
    ///     unprivileged;
    ///   * the **bundle**, because the swap ends by deleting the bundle it
    ///     replaced, and unlinking a tree needs write permission on the
    ///     directories *inside* it. Every App Store app is `root:wheel` 755 in an
    ///     `/Applications` that is `root:admin` 775 — writable parent, unwritable
    ///     bundle — and so is every app a `.pkg` laid down as root.
    ///
    /// The parent-only test this used to be sent that whole second category down
    /// the unprivileged path, where it could not work. Measured against a bundle
    /// with those exact permissions: `replaceItemAt` throws
    /// `NSCocoaErrorDomain 513` (`NSFileWriteNoPermissionError`) and leaves the app
    /// on disk **unchanged** — and 513 is precisely what `isAppManagementDenial`
    /// matches, so the failure was reported as `AppManagementRequiredError` and the
    /// user was sent to grant an App Management permission that could not have
    /// helped: the obstacle is POSIX ownership, not TCC. Sparkle's
    /// `SPUSystemNeedsAuthorizationAccessForBundlePath` requires the same pair
    /// (`isWritableFileAtPath:bundlePath && isWritableFileAtPath:parent`) before it
    /// will skip escalation.
    ///
    /// Exposed so the UI can answer "will clicking Update raise a password
    /// prompt?" from the same predicate the swap itself branches on. A separately
    /// derived copy would drift, and the two disagreeing means either a prompt the
    /// row promised wouldn't appear, or one it never warned about.
    public static func needsElevatedReplace(target: URL) -> Bool {
        let fm = FileManager.default
        // An input method is updated by exchanging what is inside its bundle, so
        // the enclosing directory is never written and its permissions are not
        // part of the question. Without this exception every input method reads as
        // "needs an administrator" — `/Library/Input Methods` is `root:wheel` 755 —
        // and the row would promise a password panel that the install then does
        // not raise. The bundle itself is still required to be writable, because
        // that is the one permission the exchange actually uses.
        if usesContentsRotation(target: target) {
            return !fm.isWritableFile(atPath: target.path)
        }
        return !fm.isWritableFile(atPath: target.path)
            || !fm.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    /// `InstallEnvironment.elevationRequiredPaths` for a set of installed bundles,
    /// normalized the same way running paths are. Lives here, beside the predicate
    /// and the swap that branches on it, so the app and the CLI cannot answer this
    /// question differently — the one disagreement that would be invisible, since
    /// each answer is individually plausible.
    public static func elevationRequiredPaths(for bundles: some Sequence<URL>) -> Set<String> {
        var paths: Set<String> = []
        for bundle in bundles where needsElevatedReplace(target: bundle) {
            paths.insert(UpdatePolicy.runtimeBundlePath(bundle))
        }
        return paths
    }

    /// Whether an `osascript … with administrator privileges` failure is the user
    /// dismissing the prompt rather than the script going wrong. AppleScript
    /// reports a cancelled authentication as error `-128`, and the code is the
    /// *only* thing matched: the message beside it is localized.
    ///
    /// **The shape, measured rather than assumed.** osascript prints one line,
    /// LF-terminated (hence the trim), and renders the code as its final
    /// parenthesised token. Run on this machine across five languages, the text
    /// changes and the token does not:
    ///
    ///     en      0:17: execution error: User canceled. (-128)
    ///     en-GB   0:17: execution error: User cancelled. (-128)
    ///     de      0:17: execution error: Von Benutzer:in abgebrochen. (-128)
    ///     zh-Hans 0:17: execution error: 用户已取消。 (-128)
    ///
    /// So the trailing token is read and nothing else. `-128` anywhere earlier is
    /// a different fact — the start of a longer code (`-12805`), a path the
    /// failing command echoed (`Foo-128.app`), or the shell's own stderr: TN2065
    /// specifies that a non-zero exit makes `do shell script` raise the *status*
    /// as the error number and the child's stderr as the message, so
    /// `… Foo-128.app: Operation not permitted (1)` is a real failure that a
    /// substring match recorded as the user's decision. (The parentheses are
    /// osascript's own rendering of the number; TN2065 describes the AppleScript
    /// error, not the formatting.)
    ///
    /// **No English backstop.** Matching `"User canceled"` as well used to look
    /// like cheap insurance and was the same defect one clause over: it fires on a
    /// genuine `mv` failure under a path called `User Canceled.app`, and it cannot
    /// buy a single true positive, because every osascript error line carries the
    /// code. It did not even cover the English it was named for — en-GB and en-AU
    /// spell it `User cancelled.`, which that needle misses.
    static func isAuthorizationDeclined(_ stderr: String) -> Bool {
        stderr.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("(-128)")
    }

    /// `target` must be an absolute path to an existing, non-symlink `.app`
    /// directory. Guards the privileged path from acting on `/`, "", or a symlink.
    static func validateTarget(_ target: URL) throws {
        let path = target.path
        guard target.isFileURL, path.hasPrefix("/"), path.hasSuffix(".app"), path.count > 4 else {
            throw SwapError.invalidTarget("“\(path)” is not an absolute .app path.")
        }
        let vals = try? target.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if vals?.isSymbolicLink == true {
            throw SwapError.invalidTarget("“\(path)” is a symlink.")
        }
        guard vals?.isDirectory == true else {
            throw SwapError.invalidTarget("“\(path)” is not an existing app bundle.")
        }
    }

    /// What `stripQuarantine` left behind.
    struct QuarantineStripResult: Equatable {
        /// `xattr`'s exit status, or nil when it could not be launched.
        let exitStatus: Int32?
        /// Paths relative to the bundle ("" is the bundle itself) that still carry
        /// `com.apple.quarantine`, sorted. Only walked when `xattr` did not exit 0,
        /// so a clean strip costs no second pass over a bundle that can hold tens
        /// of thousands of files.
        let remaining: [String]
        /// Paths the walk could not read the xattr of (EACCES on a 000 file or
        /// directory, say), so whether they — and, for a directory, anything inside
        /// it — are still quarantined is unknown. Kept apart from `remaining` so
        /// the log never reports them as cleared.
        var unreadable: [String] = []
    }

    /// Best-effort recursive removal of the quarantine xattr. Still non-fatal —
    /// the swap goes ahead — but no longer silent.
    ///
    /// `xattr -dr` cannot clear the attribute from a file it may not write: a
    /// read-only file, a read-only directory, a `uchg` file. It prints one line per
    /// such path and exits 1, and both used to go to /dev/null, so a partial strip
    /// was indistinguishable from a complete one. (Measured 2026-09-13 on a fixture
    /// bundle with a 0444 file, a 0555 directory and a `uchg` file: exit 1, those
    /// three still quarantined, everything else cleared.)
    ///
    /// The old comment put the worst case at "Gatekeeper re-prompts". On macOS 27
    /// it can be worse: launchd no longer loads a property list file that carries
    /// `com.apple.quarantine` (release note 166415497). Measured 2026-09-13 on
    /// 27.0 (26A428): `launchctl bootstrap gui/<uid>` of a plist carrying
    /// `0181;…` fails with `5: Input/output error`, the same bytes without it load.
    /// How far that reaches into a bundle is narrower than it sounds. An agent
    /// registered with `SMAppService.agent(plistName:)` from a fixture whose
    /// embedded plist (and, in a second fixture, every entry but the helper
    /// binary) was quarantined registered as `enabled` and ran — smd submits the
    /// job, launchd does not read the file. What stays exposed is an app that
    /// copies its embedded plist out and bootstraps that copy: `cp`, `ditto` and
    /// `FileManager.copyItem` all carried the xattr onto the copy (same day). So
    /// what was left gets named in the log.
    ///
    /// Not escalated to a failure: nothing shows yet that an app swapped in this
    /// state is broken, and refusing a verified build over an xattr would be the
    /// worse trade.
    ///
    /// `-s` is load-bearing for the exit status to mean anything. Without it
    /// `xattr` follows symlinks: it never clears a link's own xattr (which
    /// `ditto -x -k` of a quarantined zip does set) yet exits 0, and it exits 1 on
    /// a dangling link or one pointing at a file outside the bundle it may not
    /// write, with nothing quarantined. Measured 2026-09-13: `-drs` clears the
    /// links and exits 0 on both of those, and still exits 1 on 0444 and `uchg`.
    ///
    /// Not killed on cancellation — see `replace`. The walk after a failed strip
    /// visits every entry of the bundle, so it goes to Dispatch
    /// (`offCooperativePool`); `xattr` itself is awaited through `ChildProcess`.
    @discardableResult
    static func stripQuarantine(_ app: URL) async -> QuarantineStripResult {
        let result: QuarantineStripResult
        do {
            let outcome = try await ChildProcess.run(
                "/usr/bin/xattr", ["-drs", "com.apple.quarantine", app.path],
                standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion)
            if outcome.terminationStatus == 0 {
                result = QuarantineStripResult(exitStatus: 0, remaining: [])
            } else {
                let scan = await offCooperativePool(qos: .userInitiated) { quarantineScan(in: app) }
                result = QuarantineStripResult(
                    exitStatus: outcome.terminationStatus, remaining: scan.quarantined,
                    unreadable: scan.unreadable)
            }
        } catch {
            let scan = await offCooperativePool(qos: .userInitiated) { quarantineScan(in: app) }
            result = QuarantineStripResult(
                exitStatus: nil, remaining: scan.quarantined, unreadable: scan.unreadable)
        }
        if let line = quarantineStripLogLine(result, app: app.lastPathComponent) {
            Log.install.error("\(line, privacy: .public)")
        }
        return result
    }

    /// The log line for a strip that did not finish, or nil for one that did. Split
    /// out so what the line says is testable without reading the unified log.
    static func quarantineStripLogLine(_ result: QuarantineStripResult, app: String) -> String? {
        guard result.exitStatus != 0 else { return nil }
        let status = result.exitStatus.map { "exited \($0)" } ?? "could not be launched"
        guard !result.remaining.isEmpty || !result.unreadable.isEmpty else {
            return "strip quarantine: xattr \(status) for \(app), but nothing in it is still quarantined"
        }
        func listed(_ paths: [String]) -> String {
            let shown = 20
            let names = paths.prefix(shown).map { $0.isEmpty ? "." : $0 }
            let more = paths.count > shown ? " (+\(paths.count - shown) more)" : ""
            return names.joined(separator: ", ") + more
        }
        var parts: [String] = []
        if !result.remaining.isEmpty {
            parts.append("\(result.remaining.count) path(s) still carry com.apple.quarantine (on macOS 27 launchd will not bootstrap a quarantined plist file): \(listed(result.remaining))")
        }
        if !result.unreadable.isEmpty {
            parts.append("\(result.unreadable.count) path(s) could not be read, so whether they (or anything inside them) are still quarantined is unknown: \(listed(result.unreadable))")
        }
        return "strip quarantine: xattr \(status) for \(app) — " + parts.joined(separator: "; ")
    }

    /// Every path under `bundle`, itself included, that carries
    /// `com.apple.quarantine` on the entry itself (symlinks not followed), and
    /// every path whose xattr could not be read at all.
    ///
    /// Only `ENOATTR` counts as "not quarantined". Any other `getxattr` failure is
    /// an unknown, not a no: a 000 file answers EACCES whether or not it carries
    /// the attribute, and an earlier version counted that as cleared, so the log
    /// said "nothing in it is still quarantined" over a file `xattr` had just
    /// failed on. The enumerator's own errors are not recorded separately:
    /// measured 2026-09-13, every directory it could not open (000, 0300) had
    /// already answered EACCES to `getxattr`, 000 and 0200 files likewise.
    static func quarantineScan(in bundle: URL) -> (quarantined: [String], unreadable: [String]) {
        var quarantined: [String] = []
        var unreadable: [String] = []
        let root = bundle.standardizedFileURL.path
        func classify(_ path: String, as rel: String) {
            if getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0 {
                quarantined.append(rel)
            } else if errno != ENOATTR {
                unreadable.append(rel)
            }
        }
        classify(root, as: "")
        let walker = FileManager.default.enumerator(
            at: bundle, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, _ in true })
        while let url = walker?.nextObject() as? URL {
            let path = url.standardizedFileURL.path
            classify(path, as: path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path)
        }
        return (quarantined.sorted(), unreadable.sorted())
    }

    // MARK: - Input methods: rotate Contents, keep the outer bundle

    /// Suffixes of the two staging directories the rotation renames through, kept
    /// inside the bundle beside `Contents`.
    ///
    /// Deliberately NOT the names the vendors use for the same job
    /// (`.Contents.update` / `.Contents.old` / `.Contents.abandoned` for WeType,
    /// `Contents_update` / `Contents_backup` for DoubaoIme): a collision would let
    /// our leading `rm -rf` delete a copy their updater is mid-way through, or let
    /// their cleanup delete ours.
    static let rotationStagedName = ".Contents.duoupdater-new"
    static let rotationBackupName = ".Contents.duoupdater-old"

    /// The vendors' own staging directory for a replacement `Contents` — the one
    /// that means an update of theirs is part-way through, so rotating underneath
    /// it would race a process about to rename `Contents` itself.
    ///
    /// Only the *staging* names, deliberately. WeType's `.Contents.old` /
    /// `.Contents.abandoned` and DoubaoIme's `Contents_backup` are the copies that
    /// were displaced, and WeType's own updater carries `cleanup old Contents
    /// failed:` / `abandoned Contents removed failed:` — it expects them to be
    /// left behind sometimes. Treating a leftover as "in flight" would refuse the
    /// one-click permanently, with a message claiming an update is running that
    /// finished days ago.
    private static let vendorRotationStagingNames = [".Contents.update", "Contents_update"]

    /// Everything either vendor is known to put beside `Contents` inside the
    /// bundle, staging and leftovers alike. `requireOnlyContents` ignores these:
    /// two of them are not hidden (`Contents_update`, `Contents_backup`), so
    /// without this a bundle mid-way through — or after — a vendor update would be
    /// refused by the wrong guard, with a message about the top level instead of
    /// the accurate one about a racing update.
    private static let vendorRotationEntryNames = [
        ".Contents.update", ".Contents.old", ".Contents.abandoned",
        "Contents_update", "Contents_backup",
    ]

    /// Whether `target` is maintained by exchanging its `Contents` rather than by
    /// replacing the whole bundle.
    ///
    /// Input methods are the one class where the outer `.app` directory is an
    /// identity and not merely a container: it is the path
    /// `TISRegisterInputSource` was handed, and it is what the system's input
    /// source list points at. Both vendors' own updaters keep it and rotate what
    /// is inside — WeType's updater carries the strings
    /// `/Library/Input Methods/WeType.app/.Contents.update`, `.Contents.old`,
    /// `.Contents.abandoned` and `will exchange Contents: previous=`; DoubaoIme
    /// uses `Contents_update` / `Contents_backup`. Replacing the outer directory
    /// is what their *installers* do, and an installer does more than copy:
    /// WeType's carries `Registered input source from …, result:` and restarts the
    /// text-input agents. Rotating `Contents` is the update-shaped half of that
    /// work, and it is the half that is ours to do correctly.
    ///
    /// Matched on the install location, like `UpdatePolicy.isInputMethod` and for
    /// the same reason: the next input method should inherit this without anyone
    /// remembering to register it.
    static func usesContentsRotation(target: URL) -> Bool {
        UpdatePolicy.isInputMethod(target)
    }

    /// Replace `target/Contents` with `newApp/Contents`, leaving the outer bundle
    /// directory — its inode, and whatever the system has attached to it — exactly
    /// where it was.
    ///
    /// **Never elevated, and elevation did not work when it was tried.** Writing
    /// *inside* another app's bundle appears to be gated by App Management
    /// (`kTCCServiceSystemPolicyAppBundles`) in a way that being root does not
    /// lift. What was actually measured is one pair of `ditto` runs — one root
    /// shell, one directory, this machine, 2026-08-28:
    ///
    ///     uid 0  ditto → /Library/Input Methods/.probe                 status 0
    ///     uid 0  ditto → /Library/Input Methods/DoubaoIme.app/.probe   EPERM
    ///
    /// The reading — that the `osascript … with administrator privileges` child
    /// carries no TCC identity of its own, while DuoUpdater itself holds App
    /// Management — explains both halves and explains why the same `ditto` from
    /// our own process succeeds. It also explains why the whole-bundle path is
    /// unaffected: everything it writes (`.duoupdater-new`, `.duoupdater-old`) and
    /// everything it renames sits BESIDE the bundle, so it only ever modifies the
    /// enclosing directory's entries, never a bundle's interior. That reading is
    /// an inference from two data points, not something Apple documents here; the
    /// measurement is what the decision rests on.
    ///
    /// The first version of this raised a password panel and then failed with
    /// `ditto: …/.Contents.duoupdater-new: Operation not permitted`. Anyone
    /// tempted to "fix" a permission problem here by adding elevation should read
    /// the two lines above first.
    ///
    /// What we give up by staying unprivileged is the vendor's `root:staff`
    /// ownership of `Contents`; it comes back as ours. For the installs this runs
    /// on that changes nothing about who may write it — both are `775` with group
    /// `staff`, so the group already had exactly the owner's rights — and the
    /// vendor's own installer restores `root:staff` the next time it runs. It is
    /// logged rather than left silent.
    @discardableResult
    static func rotateContents(newApp: URL, over target: URL) async throws -> SwapOutcome {
        // Both halves around the `chmod` are synchronous disk work and go to
        // Dispatch: staging can be a copy (the download's `Contents` may sit on
        // another volume) and the exchange deletes the `Contents` it displaces.
        // They used to share the caller's `offCooperativePool` hop; the `chmod`
        // between them is awaited now. See `offCooperativePool`.
        let staged = try await offCooperativePool(qos: .userInitiated) {
            try stageRotation(newApp: newApp, over: target)
        }
        let liveContents = target.appendingPathComponent("Contents", isDirectory: true)
        // Carry the live install's group-write posture onto the replacement, for
        // the reason `modePreservationCommands` gives: the vendor's own updater
        // has to be able to delete the `Contents` it displaces, and unlinking a
        // tree needs write permission on every directory inside it.
        // `replaceItemAt` preserves the mode of the directory it replaces, but
        // only at that top level (measured).
        // Not killed on cancellation — see `replace`. (stdout was inherited
        // before; `chmod -R` prints nothing on it.)
        if let mode = directoryMode(at: liveContents), mode & 0o020 != 0 {
            let chmod = try? await ChildProcess.run(
                "/bin/chmod", ["-R", "g+w", staged.path],
                standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion)
            if chmod?.succeeded != true {
                Log.install.error(
                    "rotate: could not carry the group-write bit onto the new Contents of \(target.lastPathComponent, privacy: .public) — its own updater may not be able to clean up after its next update")
            }
        }

        return try await offCooperativePool(qos: .userInitiated) {
            try finishRotation(staged: staged, over: target)
        }
    }

    /// `rotateContents`' first half: the refusals, then `newApp/Contents` moved to
    /// the staging name inside `target`. Returns the staged directory.
    private static func stageRotation(newApp: URL, over target: URL) throws -> URL {
        let fm = FileManager.default
        let sourceContents = newApp.appendingPathComponent("Contents", isDirectory: true)

        // Rotation replaces `Contents` and nothing else. A bundle that keeps
        // anything else at its top level would come out of the exchange as new
        // code beside the old copy's leftovers — a state no gate downstream
        // inspects — so refuse instead of half-installing. Both input methods on
        // record hold `Contents` alone.
        // In-flight first: two of the vendors' staging names are not hidden, so
        // the top-level check would otherwise reject them with a message about the
        // wrong thing.
        for name in vendorRotationStagingNames
        where fm.fileExists(atPath: target.appendingPathComponent(name).path) {
            throw SwapError.notReplaceable(
                "“\(target.lastPathComponent)” has its vendor updater's “\(name)” staged inside it — "
                + "that update is still in flight, so this one would race it.")
        }
        try requireOnlyContents(at: target, describedAs: "The installed")
        try requireOnlyContents(at: newApp, describedAs: "The downloaded")
        // The one permission the exchange uses, checked before anything moves so
        // the refusal is a sentence rather than a half-finished rename. Elevation
        // is deliberately not offered as a way past this: see above.
        guard fm.isWritableFile(atPath: target.path) else {
            throw SwapError.notReplaceable(
                "“\(target.lastPathComponent)” is not writable by you, and an input method can only be "
                + "updated from inside its own bundle — this copy has to be updated by the vendor's installer.")
        }

        let staged = target.appendingPathComponent(rotationStagedName)
        try? fm.removeItem(at: staged)
        do {
            try fm.moveItem(at: sourceContents, to: staged)
        } catch {
            if isAppManagementDenial(error) {
                throw AppManagementRequiredError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(error.localizedDescription)
        }
        return staged
    }

    /// `rotateContents`' second half: the exchange and its classification.
    private static func finishRotation(staged: URL, over target: URL) throws -> SwapOutcome {
        let fm = FileManager.default
        let liveContents = target.appendingPathComponent("Contents", isDirectory: true)
        let ownerBefore = (try? fm.attributesOfItem(atPath: liveContents.path))?[.ownerAccountName]
            as? String
        // The identity of the thing this exchange replaces — `Contents`, not the
        // bundle. Asking the bundle would answer "unchanged" for every outcome: a
        // rotation deliberately leaves the outer directory's inode alone.
        let identityBefore = inode(of: liveContents)
        var cleanupFailure: String?
        do {
            // A named backup, not `nil`. `replaceItemAt` deletes it on success
            // (measured: the bundle holds `Contents` alone afterwards), so this
            // costs nothing in the ordinary case — but if the exchange is cut off
            // partway, the copy it displaced is sitting under a name the launch
            // sweep knows to look for. With `nil` the same interruption leaves it
            // under a name FileManager chose, which is to say unrecoverable: an
            // input method with no `Contents` is one macOS cannot load.
            _ = try fm.replaceItemAt(
                liveContents, withItemAt: staged,
                backupItemName: rotationBackupName, options: [])
        } catch {
            let ns = error as NSError
            Log.install.error(
                "rotate: replaceItemAt threw for \(target.lastPathComponent, privacy: .public)/Contents — \(ns.domain, privacy: .public) \(ns.code, privacy: .public): \(ns.localizedDescription, privacy: .public)")
            if fm.fileExists(atPath: staged.path) {
                do { try fm.removeItem(at: staged) } catch {
                    Log.install.error(
                        "rotate: left \(rotationStagedName, privacy: .public) inside \(target.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                }
            }
            // `replaceItemAt` here can land the new `Contents` and then throw while
            // removing the one it displaced, exactly as on the whole-bundle path —
            // and it raises the same `NSCocoaErrorDomain 513` an App Management
            // denial does, so the error cannot be asked. When it landed, the input
            // method on disk IS the new build: fall through to the ownership carry
            // below (which describes what is now live) and report a cleanup
            // failure rather than throwing an update that happened away.
            let site = classifySwapFailure(
                targetExists: fm.fileExists(atPath: liveContents.path),
                identityBefore: identityBefore,
                identityAfter: inode(of: liveContents))
            if site == .replacedThenCleanupFailed {
                cleanupFailure = error.localizedDescription
            } else if isAppManagementDenial(error) {
                throw AppManagementRequiredError(targetPath: target.path)
            } else {
                throw SwapError.notReplaceable(error.localizedDescription)
            }
        }
        let ownerAfter = (try? fm.attributesOfItem(atPath: liveContents.path))?[.ownerAccountName]
            as? String
        if let ownerBefore, ownerBefore != ownerAfter {
            Log.install.notice(
                "rotate: \(target.lastPathComponent, privacy: .public)/Contents changed owner from \(ownerBefore, privacy: .public) to \(ownerAfter ?? "?", privacy: .public) — unprivileged by necessity, see rotateContents")
        }
        if let cleanupFailure { return .replacedButCleanupFailed(cleanupFailure) }
        return .replaced
    }

    /// Refuse a rotation on a bundle that holds more than `Contents`. Hidden
    /// entries and the vendors' own in-bundle staging/backup names are ignored:
    /// `.DS_Store` is not payload, and the vendor names are checked separately by
    /// the guard that can say something accurate about them.
    private static func requireOnlyContents(at bundle: URL, describedAs role: String) throws {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: bundle.path)) ?? []
        let visible = entries
            .filter { !$0.hasPrefix(".") && !vendorRotationEntryNames.contains($0) }
            .sorted()
        guard visible == ["Contents"] else {
            throw SwapError.notReplaceable(
                "\(role) “\(bundle.lastPathComponent)” holds \(visible.joined(separator: ", ")) at its top level, "
                + "and an input method is updated by exchanging Contents alone.")
        }
    }

    private static func privilegedReplace(
        newApp: URL, target: URL, stagedCheck: StagedCopyRequirement?
    ) async throws -> SwapOutcome {
        // Read before anything moves. The shell's last clause —
        // `{ chown …; rm -rf old; }` — runs AFTER the two renames have put the new
        // bundle at `target`, so a failure there exits the chain non-zero with the
        // update already live. Every other way the chain can fail leaves `target`'s
        // identity where it was: `ditto` failing, `mv tgt old` failing, or
        // `mv new tgt` failing and the in-band `mv old tgt` putting the original
        // back (a rename preserves the inode, so the restored bundle answers with
        // the same number it started with).
        let identityBefore = inode(of: target)
        let shell = privilegedReplacementShell(newApp: newApp, target: target, requirement: stagedCheck)

        // One password panel at a time. The apply pool allows two concurrent
        // swaps, and now that every root-owned bundle takes this path (28 apps in
        // `/Applications` on the development machine, 22 of them store-installed)
        // a batch can reach it twice at once — two system panels stacked over each
        // other, neither saying which app it belongs to. The second swap suspends
        // on `elevationPanel` for as long as the first user takes to answer; no
        // thread waits with it. (Until `ChildProcess` this was an `NSLock` that
        // parked whatever thread `replace` ran on, which is why every caller had
        // to reach `replace` through `offCooperativePool`.)
        //
        // `.runToCompletion`: once the shell is running, killing `osascript` could
        // land between `mv tgt old` and `mv new tgt`. stdout was inherited before;
        // the shell's commands print nothing on it.
        let outcome = try await elevationPanel.withApplyPermit {
            try await runElevated(shell)
        }
        guard outcome.terminationStatus == 0 else {
            let msg = String(data: outcome.standardError, encoding: .utf8) ?? "unknown error"
            // Dismissing the password panel is a decision, not a fault: nothing was
            // touched (the shell never ran), and the honest response is to stop
            // offering the one-click rather than to show a red failure the user
            // caused deliberately and would keep re-triggering.
            if isAuthorizationDeclined(msg) {
                throw AuthorizationDeclinedError(targetPath: target.path)
            }
            // Asked after the declined check, which is about a shell that never
            // ran. This is the majority route — every root-owned bundle takes it,
            // 28 apps in `/Applications` on the development machine by this file's
            // own count — so "the cleanup failed" being reported as "the update
            // failed" is not an edge case: the app really is on the new version and
            // the row would have said otherwise.
            if classifySwapFailure(
                targetExists: FileManager.default.fileExists(atPath: target.path),
                identityBefore: identityBefore,
                identityAfter: inode(of: target)) == .replacedThenCleanupFailed {
                // The osascript stderr, unedited: it is the only account of what the
                // shell could not finish (a `.duoupdater-old` left behind, most
                // likely), and it goes into the log line `replace` emits.
                return .replacedButCleanupFailed(msg)
            }
            throw SwapError.notReplaceable(msg)
        }
        return .replaced
    }

    /// The authenticated shell transaction, split out so its metadata guarantees
    /// can be exercised in a temporary directory without raising a password panel.
    /// Reading the live modes and building this command happen before osascript is
    /// launched, while the old bundle is still present and authoritative.
    /// `requirement` is `replace`'s `stagedCheck`: nil adds no check.
    static func privilegedReplacementShell(
        newApp: URL, target: URL, requirement: StagedCopyRequirement? = nil
    ) -> String {
        // Materialize the replacement *fully* before the original is touched, then
        // swap via two same-volume renames. Never `rm` the original before its
        // replacement exists on disk: a `rm -rf target && ditto` would, if the
        // process were killed (or power lost) in the gap, leave the user with a
        // destroyed app and no recovery — contradicting this module's atomicity
        // guarantee. The copy goes into a root-owned `mktemp -d` directory under
        // `/private/var/tmp`, not beside the target, and an install's copy is
        // re-checked there before it moves (`privilegedStagingPrologue`,
        // `stagedCopyRequirement`). With this ordering:
        //   • killed after ditto, before the renames → original intact, staging
        //     directory leftover (cleared by the prologue's `find` on the next attempt);
        //   • killed between the two renames → original is at `.duoupdater-old`
        //     in that directory, and the trailing `||` restores it in-band.
        // Each `mv` of a directory on the same volume is an atomic rename, so the
        // only missing-app window is the microscopic gap between two renames, and
        // even that leaves the original whole, in root's staging directory.
        let new = stagedPath(for: target)
        let old = stagedOldPath(for: target)
        let tgt = shellQuote(target.path)
        let src = shellQuote(newApp.path)
        let newContents = stagedPath(for: target, appending: "Contents")

        // Preserve the directory modes that define how this particular install is
        // maintained. Downloaded archives normally unpack as 755 (measured on the
        // vendor's own payload: every one of the 81 directories in `DoubaoIme.zip`
        // is 755), but both WeType and DoubaoIme are installed root:staff 775 under
        // `/Library/Input Methods`; their own updaters stage the next Contents
        // directory inside the outer app and need that group-write bit. Replacing
        // either with an archive-default bundle silently leaves its vendor updater
        // unable to stage the next build — which is why `rotateContents` carries
        // the bit recursively for those two, and why THIS path deliberately does
        // not. Input methods never reach here any more; every other app that does
        // would be widened on a rule measured from theirs. Two apps on the
        // development machine take this path with a group-writable root (Microsoft
        // Word and Excel, `root:wheel` 775) and would have had their whole
        // interiors opened to the group on the next update, for no stated reason.
        //
        // So the guarantee here is exactly two levels, in both directions: the
        // bundle and `Contents` come back with the modes the install had, and
        // below that the source archive's own modes stand. See
        // `aPrivilegedSwapDoesNotWidenA755Install`, which pins the limit as well as
        // the rule.
        //
        // Apply modes to the staged copy BEFORE its live rename. macOS can attach
        // `com.apple.macl` as soon as a bundle occupies a registered app path; a
        // later chmod was measured returning EPERM even under `with administrator
        // privileges`. The staging directory itself is root-owned 0700, so an
        // interrupted copy is cleared by the next privileged shell, not the
        // unprivileged sweep (`privilegedStagingPrologue`).
        let bundleMode = directoryMode(at: target)
        let contentsMode = directoryMode(
            at: target.appendingPathComponent("Contents", isDirectory: true))
        let preserveModes = modePreservationCommands([(bundleMode, new), (contentsMode, newContents)])
        // Keep the replaced bundle's ownership. `ditto` running as root preserves
        // the *source's* owner, and every source we hand it — a download we
        // extracted, a rollback copy we made — belongs to the user. Without this
        // the privileged path quietly converts a `root:wheel` app into a
        // user-owned one: measured on a real store-installed app, whose bundle
        // came back as `bobby:staff` after a rollback that was otherwise perfect.
        // That relaxes who can write to an app in `/Applications` without anyone
        // asking for it, and it makes `needsElevatedReplace` flip to false for the
        // same app afterwards. Sparkle preserves ownership for the same reason
        // (`changeOwnerAndGroupOfItemAtRootURL:toMatchURL:`).
        //
        // Non-fatal (`;`, not `&&`): the ids are read off the bundle we are about
        // to replace, so failing here means something is wrong with the numbers,
        // not with the update — and refusing to install a verified build over an
        // ownership detail would be the worse trade. Interpolated as integers
        // straight from `stat`, so there is nothing quotable in them.
        //
        // Applied to the app *after* it is in place, not to the staged copy
        // before the renames. (It was first placed here so a stale user-owned
        // `.duoupdater-new` stayed removable by the unprivileged sweep; staging is
        // root-owned now and cleared by the shell itself.) An interruption before
        // the chown lands exactly the user-owned app that shipped before this
        // existed — no worse than the status quo.
        let ownership: String = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
            guard let uid = (attrs?[.ownerAccountID] as? NSNumber)?.uint32Value,
                  let gid = (attrs?[.groupOwnerAccountID] as? NSNumber)?.uint32Value
            else { return "" }
            return "/usr/sbin/chown -R \(uid):\(gid) \(tgt); "
        }()
        let shell = """
        \(privilegedStagingPrologue(target: target, alsoRemoving: shellQuote(target.path + ".duoupdater-old") + " "))\
        /usr/bin/ditto \(src) \(new) && \
        \(stagedCopyCheck(new, requirement))\
        \(preserveModes)/bin/mv \(tgt) \(old) && \
        { /bin/mv \(new) \(tgt) || { /bin/mv \(old) \(tgt); false; }; } && \
        { \(ownership)/bin/rm -rf \(old); }
        """
        return shell
    }

    /// The `chmod` clauses that carry a live install's directory modes onto the
    /// staged replacement, each already `&&`-terminated so the caller can splice
    /// the result straight into its command chain (empty when nothing is known).
    ///
    /// Best-effort by construction — a mode we could not read is simply not
    /// restated, exactly like the ownership block, and for the same reason:
    /// refusing to install a verified build because one `stat` came back empty is
    /// the worse trade, and *every* root-owned app on the machine takes this path.
    /// The `chmod`s themselves stay `&&`-chained: once we do know the mode,
    /// failing to apply it means the install would land misconfigured, and the
    /// original is still untouched at that point in the chain.
    ///
    private static func modePreservationCommands(
        _ pairs: [(mode: Int?, quotedPath: String)]
    ) -> String {
        pairs.compactMap { pair -> String? in
            guard let mode = pair.mode else { return nil }
            return "/bin/chmod \(String(mode, radix: 8)) \(pair.quotedPath) && "
        }.joined()
    }

    /// The POSIX mode of a directory, or nil when it cannot be read. Includes the
    /// setuid/setgid/sticky bits deliberately: they are part of how the install is
    /// maintained, and dropping them on a swap would be a silent change.
    private static func directoryMode(at url: URL) -> Int? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let raw = attrs?[.posixPermissions] as? NSNumber else { return nil }
        return raw.intValue & 0o7777
    }

    /// Whether an error (or anything in its underlying-error chain) is the
    /// `EPERM`/`NSFileWriteNoPermission` denial that the App Management gate
    /// raises when we try to overwrite another app's bundle.
    /// The bundle's inode, or nil when it cannot be read. Identity rather than
    /// existence: it is what lets the failure path tell "never replaced" from
    /// "replaced, then threw", which look identical to `fileExists`.
    private static func inode(of url: URL) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber]
            .flatMap { ($0 as? NSNumber)?.uint64Value }
    }

    static func isAppManagementDenial(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == NSPOSIXErrorDomain, e.code == Int(EPERM) { return true }
            if e.domain == NSCocoaErrorDomain, e.code == NSFileWriteNoPermissionError { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
