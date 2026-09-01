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

/// The final, destructive step shared by `SparkleInstaller` and `VendorInstaller`:
/// replace the verified `newApp` bundle over the installed `target` bundle.
///
/// Safety properties this enforces, in order:
///   1. **Target validation** — `target` must be an absolute path to an existing
///      `.app` directory that is not a symlink. This runs *before* any destructive
///      action, so a malformed/empty/symlinked path can never reach the privileged
///      `rm -rf`.
///   2. **Quarantine removal** — the freshly-downloaded bundle carries
///      `com.apple.quarantine`; left in place, Gatekeeper may block or re-prompt on
///      relaunch. We strip it only *after* the caller's signature gates pass.
///   3. **Atomicity** — on a user-writable location we stage the new bundle beside
///      the target and `replaceItemAt` (an atomic same-volume exchange), so a
///      failure leaves the original app fully intact rather than trashed-then-gone.
public enum InPlaceSwap {

    /// Held across the administrator panel in `privilegedReplace`, so two
    /// installs running in parallel raise one panel after the other rather than
    /// two at once. Nothing else takes it, so it cannot deadlock.
    private static let elevationPanel = NSLock()

    /// Recover from a privileged swap (`privilegedReplace`) that was interrupted
    /// between its two renames: the installed app is then sitting at
    /// `<App>.app.duoupdater-old` while `<App>.app` itself is missing. Sweep
    /// `directory` and rename any such orphan back into place — turning a would-be
    /// bricked app back into a working one — and clear stale `.duoupdater-new`/
    /// `-staged` (and present-app `.duoupdater-old`) leftovers. Best-effort; safe to
    /// run on every launch. Only the non-admin / read-only-parent install path can
    /// leave these behind (the common admin path is a truly atomic `replaceItemAt`).
    public static func recoverInterruptedSwaps(in directory: URL) {
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

    /// Replace `target` with `newApp`. Tries a user-level atomic swap first; if the
    /// location needs admin rights, falls back to an authenticated copy.
    static func replace(newApp: URL, over target: URL) throws {
        try validateTarget(target)
        stripQuarantine(newApp)
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
        Log.install.notice(
            "swap start: \(target.lastPathComponent, privacy: .public) elevated=\(elevated, privacy: .public)")
        defer {
            if replaced {
                Log.install.notice("swap done: \(target.lastPathComponent, privacy: .public)")
            } else if FileManager.default.fileExists(atPath: identityTarget.path) {
                let identityAfter = inode(of: identityTarget)
                if let before = identityBefore, let after = identityAfter, before != after {
                    Log.install.error(
                        "swap threw for \(target.lastPathComponent, privacy: .public) but the bundle at that path was REPLACED anyway — the error came after the exchange, so the new version is live and the failure is in the cleanup")
                } else {
                    Log.install.error(
                        "swap did NOT replace \(target.lastPathComponent, privacy: .public) — the app on disk is unchanged")
                }
            } else {
                // The privileged path moves the target aside before moving the new
                // bundle in, and restores it if that fails. If the restore ALSO
                // fails the app is missing from disk — and this is the one moment
                // the line is load-bearing, so it must not claim the opposite.
                // `recoverInterruptedSwaps` promotes the `.duoupdater-old` copy
                // back on the next launch.
                Log.install.error(
                    "swap did NOT complete and \(target.lastPathComponent, privacy: .public) is MISSING from disk — its pre-swap copy should be recovered on next launch")
            }
        }

        // Input methods keep their outer `.app` and exchange what is inside it —
        // see `usesContentsRotation`. Never elevated, and that is not a shortcut:
        // the elevated route cannot do this at all (see `rotateContents`).
        if usesContentsRotation(target: target) {
            try rotateContents(newApp: newApp, over: target)
            replaced = true
            return
        }

        if !elevated {
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
                // `/Applications` is group-writable for admins, so we took the
                // user-level path — but replacing *another app's* bundle is gated
                // by App Management on macOS 13+. That denial surfaces as EPERM;
                // hand it to the UI as a recoverable, typed error.
                if isAppManagementDenial(error) {
                    throw AppManagementRequiredError(targetPath: target.path)
                }
                throw SwapError.notReplaceable(error.localizedDescription)
            }
            replaced = true
            return
        }

        try privilegedReplace(newApp: newApp, target: target)
        replaced = true
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
    /// reports a cancelled authentication as error `-128`; the accompanying text
    /// is localized, so the code is what we match on and the English phrasing is
    /// only a fallback.
    ///
    /// osascript prints one line, and the code is its final token in parentheses:
    /// `0:17: execution error: User canceled. (-128)`. Only that trailing token is
    /// read. `-128` anywhere else is a different fact — the start of a longer code
    /// (`-12805`), a path the failing command echoed (`Foo-128.app`), or, per
    /// TN2065, the shell's own stderr: when the privileged command fails osascript
    /// adopts its stderr as the message and puts the *exit status* in the
    /// parentheses, so `… Foo-128.app: Operation not permitted (1)` is a real
    /// failure that a substring match would record as the user's decision.
    static func isAuthorizationDeclined(_ stderr: String) -> Bool {
        let line = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.hasSuffix("(-128)") || line.localizedCaseInsensitiveContains("User canceled")
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

    /// Best-effort recursive removal of the quarantine xattr. Failure is non-fatal:
    /// worst case Gatekeeper re-prompts, which is no worse than not trying.
    private static func stripQuarantine(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-dr", "com.apple.quarantine", app.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
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
    static func rotateContents(newApp: URL, over target: URL) throws {
        let fm = FileManager.default
        let liveContents = target.appendingPathComponent("Contents", isDirectory: true)
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
        // Carry the live install's group-write posture onto the replacement, for
        // the reason `modePreservationCommands` gives: the vendor's own updater
        // has to be able to delete the `Contents` it displaces, and unlinking a
        // tree needs write permission on every directory inside it.
        // `replaceItemAt` preserves the mode of the directory it replaces, but
        // only at that top level (measured).
        if let mode = directoryMode(at: liveContents), mode & 0o020 != 0 {
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["-R", "g+w", staged.path]
            chmod.standardError = FileHandle.nullDevice
            try? chmod.run()
            chmod.waitUntilExit()
            if chmod.terminationStatus != 0 {
                Log.install.error(
                    "rotate: could not carry the group-write bit onto the new Contents of \(target.lastPathComponent, privacy: .public) — its own updater may not be able to clean up after its next update")
            }
        }

        let ownerBefore = (try? fm.attributesOfItem(atPath: liveContents.path))?[.ownerAccountName]
            as? String
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
            if isAppManagementDenial(error) {
                throw AppManagementRequiredError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(error.localizedDescription)
        }
        let ownerAfter = (try? fm.attributesOfItem(atPath: liveContents.path))?[.ownerAccountName]
            as? String
        if let ownerBefore, ownerBefore != ownerAfter {
            Log.install.notice(
                "rotate: \(target.lastPathComponent, privacy: .public)/Contents changed owner from \(ownerBefore, privacy: .public) to \(ownerAfter ?? "?", privacy: .public) — unprivileged by necessity, see rotateContents")
        }
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

    private static func privilegedReplace(newApp: URL, target: URL) throws {
        let shell = privilegedReplacementShell(newApp: newApp, target: target)
        let appleScript = "do shell script \"\(escapeForAppleScript(shell))\" with administrator privileges"

        // One password panel at a time. The apply pool allows two concurrent
        // swaps, and now that every root-owned bundle takes this path (28 apps in
        // `/Applications` on the development machine, 22 of them store-installed)
        // a batch can reach it twice at once — two system panels stacked over each
        // other, neither saying which app it belongs to. Blocking here rather than
        // making `replace` async is deliberate: the callers are synchronous, and
        // the thread this parks was going to sit in `waitUntilExit` waiting on the
        // same human anyway, so this moves the wait rather than adding one.
        elevationPanel.lock()
        defer { elevationPanel.unlock() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8) ?? "unknown error"
            // Dismissing the password panel is a decision, not a fault: nothing was
            // touched (the shell never ran), and the honest response is to stop
            // offering the one-click rather than to show a red failure the user
            // caused deliberately and would keep re-triggering.
            if isAuthorizationDeclined(msg) {
                throw AuthorizationDeclinedError(targetPath: target.path)
            }
            throw SwapError.notReplaceable(msg)
        }
    }

    /// The authenticated shell transaction, split out so its metadata guarantees
    /// can be exercised in a temporary directory without raising a password panel.
    /// Reading the live modes and building this command happen before osascript is
    /// launched, while the old bundle is still present and authoritative.
    static func privilegedReplacementShell(newApp: URL, target: URL) -> String {
        // Materialize the replacement *fully* before the original is touched, then
        // swap via two same-directory renames. Never `rm` the original before its
        // replacement exists on disk: a `rm -rf target && ditto` would, if the
        // process were killed (or power lost) in the gap, leave the user with a
        // destroyed app and no recovery — contradicting this module's atomicity
        // guarantee. With this ordering:
        //   • killed after ditto, before the renames → original intact, `.duo-new`
        //     leftover (swept by the leading `rm -rf` on the next attempt);
        //   • killed between the two renames → original is at `.duo-old`,
        //     recoverable, and the trailing `||` restores it in-band.
        // Each `mv` of a directory on the same volume is an atomic rename, so the
        // only missing-app window is the microscopic gap between two renames, and
        // even that is recoverable via `.duo-old`.
        let new = shellQuote(target.path + ".duoupdater-new")
        let old = shellQuote(target.path + ".duoupdater-old")
        let tgt = shellQuote(target.path)
        let src = shellQuote(newApp.path)
        let newContents = shellQuote(target.path + ".duoupdater-new/Contents")

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
        // Apply modes to `.duoupdater-new` BEFORE its live rename. macOS can attach
        // `com.apple.macl` as soon as a bundle occupies a registered app path; a
        // later chmod was measured returning EPERM even under `with administrator
        // privileges`. Staging remains user-owned here, so an interrupted copy is
        // still removable by the unprivileged recovery sweep.
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
        // Applied to the app *after* it is in place, not to `.duoupdater-new`
        // before the renames. `recoverInterruptedSwaps` sweeps a stale
        // `.duoupdater-new` unprivileged, with `try? removeItem` — so chowning the
        // staged copy to root would leave a full-size leftover that the sweep
        // silently cannot delete (EACCES on the first unlink inside a root-owned
        // tree), stranded until the next privileged swap of that same app runs
        // the leading `rm -rf`. Doing it last keeps the leftover ours to remove,
        // and an interruption before the chown lands exactly the user-owned app
        // that shipped before this existed — no worse than the status quo.
        let ownership: String = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: target.path)
            guard let uid = (attrs?[.ownerAccountID] as? NSNumber)?.uint32Value,
                  let gid = (attrs?[.groupOwnerAccountID] as? NSNumber)?.uint32Value
            else { return "" }
            return "/usr/sbin/chown -R \(uid):\(gid) \(tgt); "
        }()
        let shell = """
        /bin/rm -rf \(new) \(old); \
        /usr/bin/ditto \(src) \(new) && \
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
