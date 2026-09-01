import Foundation
import CryptoKit

/// Installs an in-place update for an *official-website* app that we detect via a
/// `VendorProbeSource` recipe (VS Code, ChatWise, Codex, Conductor, …).
///
/// A vendor download is the same channel the app was installed from, so this
/// never mixes channels. There's no EdDSA feed signature to lean on, so the
/// trust comes from the gates below, of which only the checksum is optional.
/// They are numbered as `SignatureVerifier` numbers them, so the body comments
/// and this list agree:
///   - (optional) SHA-512 match when the feed publishes one — transport integrity.
///   - **Gates 2 + 3: code signature valid AND identical Team ID to the installed
///     app** — the real guarantee that the download is the same vendor's
///     notarized build, not a substituted bundle.
///   - **Gate 4: bundle identifier match**, so a vendor's *other* app can't take
///     this one's place.
///   - **Gate 5** is not about trust but about liveness: the bundle must have a
///     Mach-O slice this Mac can launch (assets are chosen by filename, and
///     filenames lie).
///   - **Gate 5b**, run only once gate 5 has already passed: the download must
///     not drop the arm64 slice the INSTALLED bundle has. Gate 5 alone answers
///     "can this Mac run it" — on Apple silicon with Rosetta that is true of an
///     Intel-only build too, so without this a native install silently becomes
///     translated, permanently (see `SignatureVerifier.verifyNoArchitectureDowngrade`).
///   - **Gate 6**, liveness too: this Mac must not be below the
///     `LSMinimumSystemVersion` the bundle declares. Vendor probes and GitHub
///     releases mostly publish no OS requirement anywhere we can read before
///     downloading, so the artifact is the first place the answer exists.
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
        /// The download unpacked, but the payload a stub was supposed to be
        /// carrying is not where the recipe says it is. Carries the detail,
        /// because the fix is a recipe edit and the path is the whole diagnosis.
        case nestedPayloadMissing(String)

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
            case .nestedPayloadMissing(let detail):
                return "The installer package did not contain the app: \(detail)"
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
        preferDelta: Bool = true,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> DownloadedUpdate {
        // Accept any source whose RemoteVersion carries a resolved installer
        // archive we vet ourselves: the vendor-probe registry ("Vendor") and
        // GitHub release rules with an asset pattern ("GitHub"), and
        // electron-builder manifests ("Electron"). All three download a notarized
        // build and gate on a Team-ID match below, so the swap stays
        // same-channel — adding a source name here widens what may flow through
        // the gates, never which gates run. Sparkle/Homebrew install through their
        // own pipelines.
        guard let remote = result.remote,
              remote.sourceName == "Vendor" || remote.sourceName == "GitHub"
                || remote.sourceName == "Electron" else {
            throw InstallError.notVendorUpdate
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }
        guard let kind = remote.vendorInstallerKind, kind != .pkg else {
            throw InstallError.unknownKind  // pkg goes through PackageInstaller
        }

        // A patch published for exactly the build on disk. Vendors reached through
        // a probe can still serve a Sparkle appcast — ChatGPT does, and every one
        // of its installs comes through here rather than SparkleInstaller, so the
        // delta route has to exist on this side too or it misses the app it was
        // built for. `preferDelta` is false on the coordinator's retry.
        let patch = preferDelta && DeltaApplier.isAvailable
            ? DeltaApplier.patch(for: result.app, in: remote)
            : nil
        if let patch {
            // The comparison is what makes this line useful, so omit it rather
            // than print a placeholder when the source publishes no archive size
            // (vendor probes generally do not).
            let saving = remote.downloadSize.map { " instead of \($0) B" } ?? ""
            let patchSize = patch.size.map(String.init) ?? "unknown"
            Log.install.info("delta route: \(result.app.name, privacy: .public) build \(patch.fromBuild, privacy: .public) → \(remote.version ?? remote.shortVersion ?? "?", privacy: .public), patch \(patchSize, privacy: .public) B\(saving, privacy: .public)")
        } else if preferDelta, !remote.deltas.isEmpty {
            Log.install.info("delta unavailable: \(result.app.name, privacy: .public) build \(result.app.buildVersion ?? "?", privacy: .public) not among \(remote.deltas.count, privacy: .public) published patches — taking the full archive")
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
            let downloaded = try await downloader.download(
                patch?.url ?? downloadURL, headers: remote.downloadHeaders)

            // Ensure the file carries an extension matching its kind, so the
            // extractor dispatches correctly even for extensionless CDN-asset URLs.
            // Skipped for a patch: `kind` describes the ARCHIVE, and renaming a
            // `.delta` to `.zip` would only mislead the extractor it never reaches.
            let archive = patch == nil
                ? try normalizedArchive(downloaded, kind: kind, workDir: workDir)
                : downloaded
            return DownloadedUpdate(
                archiveURL: archive,
                bytesDownloaded: downloader.bytesDownloaded,
                workDir: workDir,
                finalHost: downloader.finalHost,
                appliedPatch: patch)
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
        guard download.appliedPatch != nil else {
            return try applyVerified(result, download: download, onStage: onStage)
        }
        // Any failure on the patch route is recoverable by taking the full archive,
        // which is always published alongside it; the coordinator retries on this
        // type alone, so a real gate failure on the full route still stops.
        do {
            try applyVerified(result, download: download, onStage: onStage)
        } catch {
            // A liveness gate (OS floor, architecture) fails identically on the
            // full archive, so re-downloading it spends the bytes to learn
            // nothing. See `deltaRouteFailureIsWorthRetrying`.
            guard deltaRouteFailureIsWorthRetrying(error) else { throw error }
            throw DeltaRouteFailure(
                underlying: error, bytesSpent: download.bytesDownloaded)
        }
    }

    private func applyVerified(
        _ result: UpdateResult,
        download: DownloadedUpdate,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) throws {
        guard let remote = result.remote else {
            throw InstallError.notVendorUpdate
        }

        var newApp: URL
        // The delta branch below reconstructs the app from the installed copy and
        // never sees an archive, so `nestedArchivePath` does not apply to it and is
        // not consulted there. Unreachable today — the one recipe that declares a
        // nested payload publishes no patches — but if a stub-shipping vendor ever
        // also served an appcast, the symptom would be a bundle-id refusal rather
        // than anything unsafe.
        if let patch = download.appliedPatch {
            // `expectedSHA512` describes the ARCHIVE, so it cannot speak for these
            // bytes and is deliberately not applied here. `reconstruct` checks what
            // can be checked — the baseline, then the patch's own EdDSA signature
            // when the vendor publishes one and the app carries the key. ChatGPT
            // does both (45 of 45 patches signed), so its patch route ends up better
            // proven than this installer's full-archive path, which has no signature
            // to check at all.
            newApp = try DeltaApplier.reconstruct(
                installedApp: result.app.path,
                patch: patch,
                patchFile: download.archiveURL,
                workDir: download.workDir,
                edPublicKey: result.app.sparkleEdPublicKey,
                onStage: onStage)
        } else {
            // 2. Gate 1 (optional) — SHA-512 over the exact bytes we downloaded.
            if let expected = remote.expectedSHA512 {
                onStage(.verifyingSignature)
                try verifyChecksum(download.archiveURL, expectedBase64: expected)
            }

            // 3. Unpack the .app.
            onStage(.extracting)
            newApp = try ArchiveExtractor.extractApp(
                from: download.archiveURL, workDir: download.workDir)
            // 3b. Some vendors ship an installer stub with the app inside it —
            // see `VendorInstallSpec.nestedArchivePath`. Unwrap one level, having
            // first proven the stub is the vendor's: the nested archive sits under
            // `Contents/Resources`, which the stub's own signature seals, so a
            // valid signature from the installed app's Team is a statement about
            // the payload we are about to take out of it. Bundle id is NOT pinned
            // here — a stub's id is a sibling of the app's by construction
            // (`…doubaoime.installer` vs `…doubaoime`) — and everything below,
            // including the id pin, then runs against the payload itself.
            if let nested = remote.nestedArchivePath {
                try SignatureVerifier.verifyCodeSignature(appAt: newApp)
                try SignatureVerifier.verifyTeamIdentifierMatch(
                    installedApp: result.app.path,
                    downloadedApp: newApp
                )
                newApp = try unwrapNestedPayload(at: nested, inside: newApp, workDir: download.workDir)
            }
        }

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
        // Gate 5 — and it is a build this Mac can launch. The download was chosen
        // by filename, which cannot see inside a Mach-O; this reads the real
        // slices, so a mis-named artifact is refused instead of installed.
        try SignatureVerifier.verifyRunnableArchitecture(appAt: newApp)
        // Gate 5b — and it is not a WORSE build than what's already here. Must run
        // AFTER gate 5, not before: a package that is both unrunnable and a
        // downgrade (arm64 host, no Rosetta, Intel-only download) has to fail
        // with gate 5's "cannot launch" message, the true and more severe
        // problem — gate 5b's "this would run translated" is only correct once
        // gate 5 has already confirmed the download CAN launch here. Runs
        // identically for both routes above (full archive and delta
        // reconstruction) — `DeltaApplier.reconstruct` states plainly that its
        // output "goes through exactly the same gates a downloaded archive
        // does", and this is one of them; the patch is cut by the vendor and
        // nothing here assumes its architecture set matches the baseline's.
        try SignatureVerifier.verifyNoArchitectureDowngrade(
            installedApp: result.app.path,
            downloadedApp: newApp
        )
        // Gate 6 — and this Mac is not below the OS floor the bundle declares.
        // Same shape of claim as gate 5 and the same blind spot behind it: the
        // download was selected from what a source published, and most sources
        // publish no OS requirement at all, so the artifact's own plist is the
        // first place the answer exists.
        try SignatureVerifier.verifyRunnableSystemVersion(appAt: newApp)

        // 5. Swap the bundle into place. We do this even while the app is
        // running: macOS keeps the live process on the code it already mapped,
        // so it keeps working on the old version until the user restarts it (the
        // caller surfaces a "Restart" prompt). We never force a quit — that would
        // skip the app's own save-on-quit flow.
        onStage(.installing)
        try installApp(newApp, over: result.app.path)

        onStage(.done)
    }

    /// Extract the archive at `relativePath` inside the installer stub `stub`, and
    /// return the `.app` it holds.
    ///
    /// The path is resolved and then checked to still be inside `stub`, the same
    /// containment check `ArchiveExtractor` makes about the bundle it returns: a
    /// registry string is not user input, but a `..` in one would otherwise reach
    /// anywhere on disk, and this is two steps upstream of a privileged swap.
    private func unwrapNestedPayload(at relativePath: String, inside stub: URL, workDir: URL) throws -> URL {
        let nested = stub.appendingPathComponent(relativePath).standardizedFileURL
        let root = stub.standardizedFileURL.path
        guard nested.path.hasPrefix(root + "/"),
              FileManager.default.fileExists(atPath: nested.path) else {
            throw InstallError.nestedPayloadMissing(
                "“\(stub.lastPathComponent)” does not hold \(relativePath).")
        }
        // Its own scratch directory: `extractApp` unpacks into `workDir`, and
        // pointing it there a second time would have it choose between the stub it
        // already unpacked and the payload it is unpacking now.
        let inner = workDir.appendingPathComponent("nested-payload", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        return try ArchiveExtractor.extractApp(from: nested, workDir: inner)
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
