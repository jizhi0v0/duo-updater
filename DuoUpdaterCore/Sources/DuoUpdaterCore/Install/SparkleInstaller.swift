import Foundation

/// Stages emitted as an install proceeds, for driving UI.
public enum InstallStage: Sendable, Equatable {
    /// Re-verifying the app still needs updating before acting on it.
    case checking
    case downloading(fraction: Double)
    case verifyingSignature
    case extracting
    case verifyingCodeSignature
    case installing
    /// A command-line installer (Homebrew) is running; payload is its latest
    /// output line.
    case runningCommand(String)
    case done
}

/// Drives the full Sparkle update pipeline for a single app:
/// download → EdDSA verify → extract → code-signature + Team ID verify →
/// swap bundle in place.
///
/// The bundle is replaced even while the app is running: macOS keeps the live
/// process on the code it already mapped, so the app keeps working untouched on
/// the old version, and the caller surfaces a "Restart" prompt. We never quit or
/// relaunch the app — the user restarts it on their own schedule, through the
/// app's own quit flow (so its save-on-quit prompts run). A not-running app just
/// updates silently.
///
/// Every gate must pass; a failure throws and leaves the installed app
/// untouched (we only delete the old bundle once the new one is fully verified).
public actor SparkleInstaller {

    public init() {}

    public enum InstallError: LocalizedError {
        case notSparkleUpdate
        case noPublicKey
        case noDownloadURL

        public var errorDescription: String? {
            switch self {
            case .notSparkleUpdate:
                return "This update did not come from a Sparkle feed."
            case .noPublicKey:
                return "The app has no SUPublicEDKey, so the download can't be verified. Update it manually."
            case .noDownloadURL:
                return "The update has no download URL."
            }
        }
    }

    /// Returns the exact number of bytes downloaded for the update, for per-app
    /// traffic accounting.
    @discardableResult
    public func install(
        _ result: UpdateResult,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> Int64 {
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
            .appendingPathComponent("DuoUpdater-\(result.app.scratchSlug)-\(remote.displayVersion ?? "new")")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. Download
        let downloader = Downloader(destinationDir: workDir) { fraction in
            onStage(.downloading(fraction: fraction))
        }
        let archive = try await downloader.download(downloadURL)
        let bytesDownloaded = downloader.bytesDownloaded

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

        // 4. Gate 2 + 3 + 4 — code signature valid, same Team ID, AND same signed
        // bundle identifier as installed (pins the swap to this exact app, not
        // just this vendor/Team).
        onStage(.verifyingCodeSignature)
        try SignatureVerifier.verifyCodeSignature(appAt: newApp)
        try SignatureVerifier.verifyTeamIdentifierMatch(
            installedApp: result.app.path,
            downloadedApp: newApp
        )
        try SignatureVerifier.verifyBundleIdentifierMatch(
            installedApp: result.app.path,
            downloadedApp: newApp
        )

        // 5. Swap the bundle into place. We do this even while the app is
        // running: macOS keeps the live process on the code it already mapped,
        // so it keeps working on the old version until the user restarts it (the
        // caller surfaces a "Restart" prompt). We never force a quit — that would
        // skip the app's own save-on-quit flow.
        onStage(.installing)
        try installApp(newApp, over: result.app.path)

        onStage(.done)
        return bytesDownloaded
    }

    // MARK: - Install

    /// Replace the bundle at `target` with `newApp`. Validation, quarantine
    /// removal, atomic same-volume swap, and the privileged fallback all live in
    /// `InPlaceSwap`, shared with `VendorInstaller`.
    private func installApp(_ newApp: URL, over target: URL) throws {
        try InPlaceSwap.replace(newApp: newApp, over: target)
    }
}
