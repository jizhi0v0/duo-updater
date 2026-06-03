import Foundation

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
enum InPlaceSwap {

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
        let shell = """
        /bin/rm -rf \(shellQuote(target.path)) && \
        /usr/bin/ditto \(shellQuote(newApp.path)) \(shellQuote(target.path))
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

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
