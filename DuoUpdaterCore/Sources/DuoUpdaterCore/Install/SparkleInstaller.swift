import Foundation

/// Stages emitted as an install proceeds, for driving UI.
public enum InstallStage: Sendable, Equatable {
    /// Waiting for a slot in the global install queue — too many installs are
    /// already in flight, so this one is parked until one of them finishes.
    case queued
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
/// The pipeline runs as TWO explicit phases — `download`, then `apply` — so the
/// caller can hold a *download* permit only while fetching bytes and an *apply*
/// permit while verifying/extracting/swapping (see `InstallPermits`). The seam
/// is deliberate: only the download is network-bound, and one permit covering
/// both stages would couple the two resources for no reason — a slot would sit
/// idle on the network while its install swaps, and vice versa.
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
        case noDownloadURL

        public var errorDescription: String? {
            switch self {
            case .notSparkleUpdate:
                return "This update did not come from a Sparkle feed."
            case .noDownloadURL:
                return "The update has no download URL."
            }
        }
    }

    /// Phase 1 — network only: fetch the update's archive into a scratch dir we
    /// own and return it (with the exact byte count, for traffic accounting) as
    /// a `DownloadedUpdate` for `apply`. On failure the scratch dir is removed
    /// here; on success it is left in place, owned by the caller until `apply`
    /// (or a cancellation landing between the phases) is done with it.
    public func download(
        _ result: UpdateResult,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> DownloadedUpdate {
        guard let remote = result.remote, remote.sourceName == "Sparkle" else {
            throw InstallError.notSparkleUpdate
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }

        // Scratch dir we own. Removed up front so a retry starts clean; on
        // failure we remove it again below; on success it stays for `apply`.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater-\(result.app.scratchSlug)-\(remote.displayVersion ?? "new")")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        do {
            let downloader = Downloader(destinationDir: workDir) { fraction in
                onStage(.downloading(fraction: fraction))
            }
            let archive = try await downloader.download(downloadURL)
            return DownloadedUpdate(
                archiveURL: archive,
                bytesDownloaded: downloader.bytesDownloaded,
                workDir: workDir,
                finalHost: downloader.finalHost)
        } catch {
            // A failed (or partially-written) download leaves nothing behind.
            try? FileManager.default.removeItem(at: workDir)
            throw error
        }
    }

    /// Phase 2 — disk + privileged only, no network: verify, extract, and swap
    /// the archive `download` produced. Returns once the new bundle has been
    /// swapped in place ("the swap has landed"); everything the caller does
    /// after this is restart bookkeeping and needs no permit.
    public func apply(
        _ result: UpdateResult,
        download: DownloadedUpdate,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) throws {
        guard let remote = result.remote, remote.sourceName == "Sparkle" else {
            throw InstallError.notSparkleUpdate
        }
        // EdDSA is verified only when the app ships an `SUPublicEDKey` — the
        // normal, strongly-signed Sparkle feed. Some vendors publish an UNSIGNED
        // feed (no `SUPublicEDKey` in the bundle, no `sparkle:edSignature` in the
        // appcast — e.g. Fork) and lean on HTTPS plus the download's own Developer
        // ID code signature for authenticity. For those we fall back to the SAME
        // best-effort gate the Vendor/GitHub paths use: code signature valid +
        // same Team ID + same bundle id as installed (Gates 2/3/4 below), which
        // fails closed, so an app we can't verify that way is simply not installed.
        // We only skip EdDSA when there's NO key at all — a feed that ships a key
        // must still produce a signature (a key'd feed silently dropping its
        // signature is suspicious), so `verifyEdSignature` stays mandatory there.
        let publicKey = result.app.sparkleEdPublicKey
        let verifiesWithEdDSA = !(publicKey?.isEmpty ?? true)

        // 2. Gate 1 — EdDSA signature over the exact bytes we downloaded. Skipped
        // for an unsigned feed (no key); the code-signature + Team gate below then
        // carries the trust on its own. See the note above.
        if verifiesWithEdDSA {
            onStage(.verifyingSignature)
            let fileData = try Data(contentsOf: download.archiveURL, options: .mappedIfSafe)
            try SignatureVerifier.verifyEdSignature(
                fileData: fileData,
                signatureBase64: remote.edSignature,
                publicKeyBase64: publicKey!
            )
        }

        // 3. Extract the .app
        onStage(.extracting)
        let newApp = try ArchiveExtractor.extractApp(from: download.archiveURL, workDir: download.workDir)

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
    }

    // MARK: - Install

    /// Replace the bundle at `target` with `newApp`. Validation, quarantine
    /// removal, atomic same-volume swap, and the privileged fallback all live in
    /// `InPlaceSwap`, shared with `VendorInstaller`.
    private func installApp(_ newApp: URL, over target: URL) throws {
        try InPlaceSwap.replace(newApp: newApp, over: target)
    }
}
