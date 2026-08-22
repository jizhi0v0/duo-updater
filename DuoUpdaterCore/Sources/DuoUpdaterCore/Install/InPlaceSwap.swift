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
        Log.install.notice(
            "swap start: \(target.lastPathComponent, privacy: .public) elevated=\(elevated, privacy: .public)")
        defer {
            if replaced {
                Log.install.notice("swap done: \(target.lastPathComponent, privacy: .public)")
            } else {
                Log.install.error(
                    "swap did NOT replace \(target.lastPathComponent, privacy: .public) — the app on disk is unchanged")
            }
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
                try? fm.removeItem(at: staged)
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
    /// The test is the **parent directory**, not the bundle: `replaceItemAt`
    /// stages its exchange as a sibling, so a bundle we could write into but whose
    /// enclosing directory we cannot (`/Library/Input Methods` is `root:wheel`
    /// 755, while `WeType.app` inside it is `root:staff` 775) still cannot be
    /// swapped unprivileged. Sparkle reaches the same conclusion the same way, in
    /// `SPUSystemNeedsAuthorizationAccessForBundlePath` — it requires writability
    /// of the bundle *and* of its parent before it will skip escalation.
    ///
    /// Exposed so the UI can answer "will clicking Update raise a password
    /// prompt?" from the same predicate the swap itself branches on. A separately
    /// derived copy would drift, and the two disagreeing means either a prompt the
    /// row promised wouldn't appear, or one it never warned about.
    public static func needsElevatedReplace(target: URL) -> Bool {
        !FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
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
    static func isAuthorizationDeclined(_ stderr: String) -> Bool {
        stderr.contains("-128") || stderr.localizedCaseInsensitiveContains("User canceled")
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

    private static func privilegedReplace(newApp: URL, target: URL) throws {
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
        let shell = """
        /bin/rm -rf \(new) \(old); \
        /usr/bin/ditto \(src) \(new) && \
        /bin/mv \(tgt) \(old) && \
        { /bin/mv \(new) \(tgt) || { /bin/mv \(old) \(tgt); false; }; } && \
        /bin/rm -rf \(old)
        """
        let appleScript = "do shell script \"\(escapeForAppleScript(shell))\" with administrator privileges"

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

    /// Whether an error (or anything in its underlying-error chain) is the
    /// `EPERM`/`NSFileWriteNoPermission` denial that the App Management gate
    /// raises when we try to overwrite another app's bundle.
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
