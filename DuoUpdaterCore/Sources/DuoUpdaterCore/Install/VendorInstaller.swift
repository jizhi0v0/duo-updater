import Foundation
import CryptoKit

/// Installs an in-place update for an *official-website* app that we detect via a
/// `VendorProbeSource` recipe (VS Code, ChatWise, Codex, Conductor, …).
///
/// A vendor download is the same channel the app was installed from, so this
/// never mixes channels. There's no EdDSA feed signature to lean on, so the
/// trust comes from two gates, both mandatory:
///   1. (optional) SHA-512 match when the feed publishes one — transport integrity.
///   2. **Code signature valid AND identical Team ID to the installed app** — the
///      real guarantee that the download is the same vendor's notarized build,
///      not a substituted bundle.
///
/// Pipeline: download → (checksum) → unpack → signature/Team gate → swap bundle
/// in place. Any gate failure throws and leaves the installed app untouched (the
/// old bundle is removed only after the new one is fully verified).
///
/// The pipeline runs as TWO explicit phases — `download`, then `apply` — so the
/// caller can hold a *download* permit only while fetching bytes and an *apply*
/// permit while verifying/extracting/swapping (see `InstallPermits`). The seam
/// is deliberate: only the download is network-bound, and one permit covering
/// both stages would couple the two resources for no reason — a slot would sit
/// idle on the network while its install swaps, and vice versa.
///
/// The swap happens even while the app is running — macOS keeps the live process
/// on the code it already mapped, so it keeps working on the old version and the
/// caller surfaces a "Restart" prompt. We never quit or relaunch the app: the
/// user restarts it on their own schedule (so its save-on-quit flow runs). A
/// not-running app just updates silently.
public actor VendorInstaller {

    public init() {}

    public enum InstallError: LocalizedError {
        case notVendorUpdate
        case noDownloadURL
        case unknownKind
        case checksumMismatch

        public var errorDescription: String? {
            switch self {
            case .notVendorUpdate:
                return "This update isn't an in-place installable archive."
            case .noDownloadURL:
                return "The update has no resolved download URL."
            case .unknownKind:
                return "This vendor update has no known installable archive format."
            case .checksumMismatch:
                return "The download's checksum didn't match — it may be corrupt or tampered. Nothing was changed."
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
        // Accept any source whose RemoteVersion carries a resolved installer
        // archive we vet ourselves: the vendor-probe registry ("Vendor") and
        // GitHub release rules with an asset pattern ("GitHub"). Both download a
        // notarized build and gate on a Team-ID match below, so the swap stays
        // same-channel. Sparkle/Homebrew install through their own pipelines.
        guard let remote = result.remote,
              remote.sourceName == "Vendor" || remote.sourceName == "GitHub" else {
            throw InstallError.notVendorUpdate
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }
        guard let kind = remote.vendorInstallerKind, kind != .pkg else {
            throw InstallError.unknownKind  // pkg goes through PackageInstaller
        }

        // Scratch dir we own. Removed up front so a retry starts clean; on
        // failure we remove it again below; on success it stays for `apply`.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater-vendor-\(result.app.scratchSlug)-\(remote.displayVersion ?? "new")")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        do {
            let downloader = Downloader(destinationDir: workDir) { fraction in
                onStage(.downloading(fraction: fraction))
            }
            let downloaded = try await downloader.download(downloadURL, headers: remote.downloadHeaders)

            // Ensure the file carries an extension matching its kind, so the
            // extractor dispatches correctly even for extensionless CDN-asset URLs.
            let archive = try normalizedArchive(downloaded, kind: kind, workDir: workDir)
            return DownloadedUpdate(
                archiveURL: archive,
                bytesDownloaded: downloader.bytesDownloaded,
                workDir: workDir)
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
        guard let remote = result.remote else {
            throw InstallError.notVendorUpdate
        }

        // 2. Gate 1 (optional) — SHA-512 over the exact bytes we downloaded.
        if let expected = remote.expectedSHA512 {
            onStage(.verifyingSignature)
            try verifyChecksum(download.archiveURL, expectedBase64: expected)
        }

        // 3. Unpack the .app.
        onStage(.extracting)
        let newApp = try ArchiveExtractor.extractApp(from: download.archiveURL, workDir: download.workDir)

        // 4. Gate 2 + 3 + 4 — code signature valid, same Team ID, AND same signed
        // bundle identifier as the installed app. The bundle-id pin stops a
        // same-vendor but different app (or a different channel sharing the Team)
        // from being swapped in over this exact install.
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

    // MARK: - Checksum

    private func verifyChecksum(_ file: URL, expectedBase64: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA512.hash(data: data)
        let actual = Data(digest).base64EncodedString()
        // Vendors publish base64; compare exactly (trim incidental whitespace).
        guard actual == expectedBase64.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw InstallError.checksumMismatch
        }
    }

    /// Move/rename the download so its extension reflects `kind`. The Tauri/CDN
    /// case has no extension in the URL, which would defeat extraction-by-suffix.
    private func normalizedArchive(_ file: URL, kind: VendorInstallerKind, workDir: URL) throws -> URL {
        let ext: String
        switch kind {
        case .zip: ext = "zip"
        case .dmg: ext = "dmg"
        case .tarGz: ext = "tar.gz"
        case .pkg: ext = "pkg"
        }
        if file.lastPathComponent.lowercased().hasSuffix(ext) { return file }
        let renamed = workDir.appendingPathComponent("download.\(ext)")
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.moveItem(at: file, to: renamed)
        return renamed
    }

    // MARK: - Install

    /// Validation, quarantine removal, atomic same-volume swap, and the privileged
    /// fallback all live in `InPlaceSwap`, shared with `SparkleInstaller`.
    private func installApp(_ newApp: URL, over target: URL) throws {
        try InPlaceSwap.replace(newApp: newApp, over: target)
    }
}
