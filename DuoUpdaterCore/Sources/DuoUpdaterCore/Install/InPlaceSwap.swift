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

        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()

        if fm.isWritableFile(atPath: parent.path) {
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
            return
        }

        try privilegedReplace(newApp: newApp, target: target)
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
