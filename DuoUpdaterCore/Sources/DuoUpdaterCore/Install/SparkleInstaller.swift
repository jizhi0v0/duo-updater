import Foundation
import AppKit

/// Stages emitted as an install proceeds, for driving UI.
public enum InstallStage: Sendable, Equatable {
    /// Re-verifying the app still needs updating before acting on it.
    case checking
    case downloading(fraction: Double)
    case verifyingSignature
    case extracting
    case verifyingCodeSignature
    case installing
    case relaunching
    /// A command-line installer (Homebrew) is running; payload is its latest
    /// output line.
    case runningCommand(String)
    case done
}

/// Drives the full Sparkle update pipeline for a single app:
/// download → EdDSA verify → extract → code-signature + Team ID verify →
/// quit running instance → swap bundle → relaunch.
///
/// Every gate must pass; a failure throws and leaves the installed app
/// untouched (we only delete the old bundle once the new one is fully verified).
public actor SparkleInstaller {

    public init() {}

    public enum InstallError: LocalizedError {
        case notSparkleUpdate
        case noPublicKey
        case noDownloadURL
        case targetNotReplaceable(String)
        case appWouldNotQuit(String)

        public var errorDescription: String? {
            switch self {
            case .notSparkleUpdate:
                return "This update did not come from a Sparkle feed."
            case .noPublicKey:
                return "The app has no SUPublicEDKey, so the download can't be verified. Update it manually."
            case .noDownloadURL:
                return "The update has no download URL."
            case .targetNotReplaceable(let msg):
                return "Could not replace the installed app: \(msg)"
            case .appWouldNotQuit(let name):
                return "\(name) wouldn’t quit (it may have unsaved changes). Quit it yourself, then update again. Nothing was changed."
            }
        }
    }

    public func install(
        _ result: UpdateResult,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        guard let remote = result.remote, remote.sourceName == "Sparkle" else {
            throw InstallError.notSparkleUpdate
        }
        guard let publicKey = result.app.sparkleEdPublicKey, !publicKey.isEmpty else {
            throw InstallError.noPublicKey
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }

        // Scratch dir we own and clean up no matter what.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater-\(result.app.id)-\(remote.displayVersion ?? "new")")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. Download
        let downloader = Downloader(destinationDir: workDir) { fraction in
            onStage(.downloading(fraction: fraction))
        }
        let archive = try await downloader.download(downloadURL)

        // 2. Gate 1 — EdDSA signature over the exact bytes we downloaded
        onStage(.verifyingSignature)
        let fileData = try Data(contentsOf: archive, options: .mappedIfSafe)
        try SignatureVerifier.verifyEdSignature(
            fileData: fileData,
            signatureBase64: remote.edSignature,
            publicKeyBase64: publicKey
        )

        // 3. Extract the .app
        onStage(.extracting)
        let newApp = try ArchiveExtractor.extractApp(from: archive, workDir: workDir)

        // 4. Gate 2 + 3 — code signature valid AND same Team ID as installed
        onStage(.verifyingCodeSignature)
        try SignatureVerifier.verifyCodeSignature(appAt: newApp)
        try SignatureVerifier.verifyTeamIdentifierMatch(
            installedApp: result.app.path,
            downloadedApp: newApp
        )

        // 5. Quit the running instance (if any) so we can swap the bundle.
        // Aborts (before touching anything) if it won't quit gracefully — we
        // never force-kill, to avoid destroying unsaved work.
        let bundleID = result.app.bundleID
        let wasRunning = try await quitRunningInstance(bundleID: bundleID)

        // 6. Swap the bundle into place
        onStage(.installing)
        try installApp(newApp, over: result.app.path)

        // 7. Relaunch if it had been running
        if wasRunning {
            onStage(.relaunching)
            await relaunch(at: result.app.path)
        }

        onStage(.done)
    }

    // MARK: - Quit / relaunch

    /// Ask a running instance to quit gracefully (like Cmd-Q, so the app can run
    /// its own save prompts). Returns whether it had been running. Throws if it
    /// won't quit within the grace period — we deliberately never force-kill,
    /// because that would discard unsaved work. Pre-swap, so aborting is safe.
    @MainActor
    private func quitRunningInstance(bundleID: String?) async throws -> Bool {
        guard let bundleID else { return false }
        var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return false }
        let name = running.first?.localizedName ?? "The app"

        for app in running { app.terminate() }

        // Give it a few seconds to exit gracefully.
        for _ in 0..<30 {
            running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if running.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // Still alive — most likely a blocking prompt (unsaved changes). Bail
        // out rather than force-terminate.
        throw InstallError.appWouldNotQuit(name)
    }

    @MainActor
    private func relaunch(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: - Install

    /// Replace the bundle at `target` with `newApp`. Tries a user-level swap
    /// first; if the location requires admin rights, falls back to an
    /// authenticated copy (one macOS password prompt).
    private func installApp(_ newApp: URL, over target: URL) throws {
        let fm = FileManager.default

        if fm.isWritableFile(atPath: target.deletingLastPathComponent().path) {
            // Move the old bundle to the Trash, then move the new one in.
            try? fm.trashItem(at: target, resultingItemURL: nil)
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: target)
            }
            try fm.moveItem(at: newApp, to: target)
            return
        }

        // Privileged path: remove old + copy new via an authenticated shell.
        try privilegedReplace(newApp: newApp, target: target)
    }

    private func privilegedReplace(newApp: URL, target: URL) throws {
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
            throw InstallError.targetNotReplaceable(msg)
        }
    }

    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
