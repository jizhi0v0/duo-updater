import Foundation

/// Stages emitted as an install proceeds, for driving UI.
public enum InstallStage: Sendable, Equatable {
    /// Waiting for a slot in the global install queue — too many installs are
    /// already in flight, so this one is parked until one of them finishes.
    case queued
    /// Re-verifying the app still needs updating before acting on it.
    case checking
    /// Copying the bundle as it is now into a restore point, before anything
    /// is fetched. Set by the host, which takes the backup; no installer
    /// reports it.
    case backingUp
    case downloading(fraction: Double)
    case verifyingSignature
    case extracting
    case verifyingCodeSignature
    case installing
    /// A command-line installer (Homebrew) is running; payload is its latest
    /// output line.
    case runningCommand(String)
    case done

    /// The case's name without its payload — `downloading`, not
    /// `downloading(fraction: 0.4)`. What a log line and `duo install --json`
    /// call the stage.
    public var name: String {
        switch self {
        case .queued: return "queued"
        case .checking: return "checking"
        case .backingUp: return "backingUp"
        case .downloading: return "downloading"
        case .verifyingSignature: return "verifyingSignature"
        case .extracting: return "extracting"
        case .verifyingCodeSignature: return "verifyingCodeSignature"
        case .installing: return "installing"
        case .runningCommand: return "runningCommand"
        case .done: return "done"
        }
    }
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
        preferDelta: Bool = true,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> DownloadedUpdate {
        guard let remote = result.remote, remote.sourceName == "Sparkle" else {
            throw InstallError.notSparkleUpdate
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }

        // Prefer a patch when the feed published one for exactly this build and
        // this build can apply it. `preferDelta` is false on the retry the
        // coordinator makes after a patch route fails, so a broken patch degrades
        // to the full archive rather than failing the install — the same fallback
        // Sparkle itself performs.
        let patch = preferDelta && DeltaApplier.isAvailable
            ? DeltaApplier.patch(for: result.app, in: remote)
            : nil
        // Which route this install took is otherwise invisible: both end in the
        // same swap, and the only outward difference is a byte count nothing prints.
        if let patch {
            // The comparison is what makes this line useful, so omit it rather
            // than print a placeholder when the source publishes no archive size
            // (vendor probes generally do not).
            let saving = remote.downloadSize.map { " instead of \($0) B" } ?? ""
            let patchSize = patch.size.map(String.init) ?? "unknown"
            Log.install.info("delta route: \(result.app.name, privacy: .public) build \(patch.fromBuild, privacy: .public) → \(remote.version ?? "?", privacy: .public), patch \(patchSize, privacy: .public) B\(saving, privacy: .public)")
        } else if preferDelta, !remote.deltas.isEmpty {
            Log.install.info("delta unavailable: \(result.app.name, privacy: .public) build \(result.app.buildVersion ?? "?", privacy: .public) not among \(remote.deltas.count, privacy: .public) published patches — taking the full archive")
        }

        // Scratch dir we own. Removed up front so a retry starts clean; on
        // failure we remove it again below; on success it stays for `apply`.
        //
        // `displayVersion` is the FEED's string, and it goes through
        // `filesystemSafeToken` for the reason that helper exists: interpolated
        // raw, a version such as `999.0/../../../../Users/me/Documents` makes this
        // URL resolve outside the scratch dir — `appendingPathComponent` keeps `/`
        // as a separator and the kernel follows `..` — so the `removeItem` below
        // (and the caller's `defer`, and the failure path at the catch) recursively
        // deletes whatever directory the feed named. Measured: a workDir built this
        // way resolved to the target and the cleanup destroyed it. That runs before
        // the EdDSA and Team-ID gates, so it is reachable from a hijacked feed that
        // every signature check downstream would have refused. `scratchSlug` was
        // already sanitized (`InstalledApp.safePathComponent`); only this half was
        // not.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DuoUpdater-\(result.app.scratchSlug)-\((remote.displayVersion ?? "new").filesystemSafeToken)")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        InstallJournal.noteWorkDirectory(workDir)
        do {
            let downloader = Downloader(destinationDir: workDir) { fraction in
                onStage(.downloading(fraction: fraction))
            }
            let archive = try await downloader.download(patch?.url ?? downloadURL)
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
    ) async throws {
        guard download.appliedPatch != nil else {
            return try await applyVerified(result, download: download, onStage: onStage)
        }
        // Everything that can go wrong on the patch route is recoverable by taking
        // the full archive instead — a patch that won't apply, a signature that
        // won't verify, a reconstructed bundle whose TRUST gates fail — with one
        // exception: a LIVENESS gate (OS floor, architecture) refuses the full
        // archive for the identical reason, so that error is re-thrown unwrapped
        // instead of retried (see `deltaRouteFailureIsWorthRetrying`). Sparkle
        // makes the same choice ("in any case where a binary delta update fails to
        // install, Sparkle falls back to downloading and installing the regular
        // full update"), and it holds here for the same reason: the patch is an
        // optimisation over a download that is always available, so nothing is lost
        // by abandoning it. The full route's failures are NOT wrapped — there the
        // gate really is telling us not to install.
        do {
            try await applyVerified(result, download: download, onStage: onStage)
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
    ) async throws {
        guard let remote = result.remote, remote.sourceName == "Sparkle" else {
            throw InstallError.notSparkleUpdate
        }
        // Which trust this install rests on is decided here, once, from the
        // installed copy on disk — never from the scan's `installedLacksTeamIdentifier`
        // (a `try?` that reads an unreadable signature as "no Team"). A copy with
        // no Team ID takes its own route, whose only anchor is its update key.
        let installedApp = result.app.path
        let installedTeam = try await offCooperativePool {
            try SignatureVerifier.teamIdentifier(at: installedApp)
        }
        guard installedTeam != nil else {
            return try await applyKeyOnly(result, remote: remote, download: download, onStage: onStage)
        }

        // EdDSA is verified only when the app ships an `SUPublicEDKey` — the
        // normal, strongly-signed Sparkle feed. Some vendors publish an UNSIGNED
        // feed (no `SUPublicEDKey` in the bundle, no `sparkle:edSignature` in the
        // appcast — e.g. Fork) and lean on HTTPS plus the download's own Developer
        // ID code signature for authenticity. For those we fall back to the SAME
        // best-effort gate the Vendor/GitHub paths use: code signature valid +
        // same Team ID + same bundle id as installed (Gates 2/3/4, run via
        // `SignatureVerifier.verifyInstallArtifact` below), which fails closed,
        // so an app we can't verify that way is simply not installed.
        // We only skip EdDSA when there's NO key at all — a feed that ships a key
        // must still produce a signature (a key'd feed silently dropping its
        // signature is suspicious), so `verifyEdSignature` stays mandatory there.
        let publicKey = result.app.sparkleEdPublicKey
        let verifiesWithEdDSA = !(publicKey?.isEmpty ?? true)

        // 2. Gate 1 — EdDSA signature over the exact bytes we downloaded. Skipped
        // for an unsigned feed (no key); the code-signature + Team gate below then
        // carries the trust on its own. See the note above.
        //
        // A `edSignatureInvalid` failure is held rather than thrown: it may be a
        // vendor key rotation, which we can only tell apart after extracting the
        // new bundle (step 3b).
        var heldEdFailure: Error?
        var archiveData: Data?
        // Skipped wholesale on the patch route: every line below reasons about the
        // ARCHIVE's signature and the rotation it might reveal, neither of which
        // describes a `.delta`. The patch carries its own proof and `reconstruct`
        // checks it before the patch tool ever sees the file.
        if verifiesWithEdDSA, download.appliedPatch == nil {
            onStage(.verifyingSignature)
            let fileData = try Data(contentsOf: download.archiveURL, options: .mappedIfSafe)
            do {
                try SignatureVerifier.verifyEdSignature(
                    fileData: fileData,
                    signatureBase64: remote.edSignature,
                    publicKeyBase64: publicKey!
                )
            } catch SignatureVerifier.VerifyError.edSignatureInvalid {
                heldEdFailure = SignatureVerifier.VerifyError.edSignatureInvalid
                archiveData = fileData
            }
        }

        // 3. Produce the new .app — unpacked from the archive, or reconstructed
        // from the installed bundle plus the patch. Either way what comes out is an
        // ordinary bundle that must clear every gate below; the patch buys bytes,
        // never trust. `result.app.path` is read only, so a patch that fails here
        // leaves the installed app untouched for the full-archive retry.
        onStage(.extracting)
        let newApp: URL
        if let patch = download.appliedPatch {
            // Awaited in place: `BinaryDelta` runs through `ChildProcess`, which
            // waits without parking a thread, and it runs to completion if this task is
            // cancelled — see `DeltaApplier.apply`.
            newApp = try await DeltaApplier.reconstruct(
                installedApp: result.app.path,
                patch: patch,
                patchFile: download.archiveURL,
                workDir: download.workDir,
                edPublicKey: publicKey,
                onStage: onStage)
        } else {
            // Awaited in place, for the same reason: see `extractApp`.
            newApp = try await ArchiveExtractor.extractApp(
                from: download.archiveURL, workDir: download.workDir)
        }

        // 3b. The signature didn't match the key we hold. If the download ships a
        // DIFFERENT `SUPublicEDKey` and the feed's signature verifies against it,
        // the vendor rotated its Sparkle key without a transition release — the
        // app's own Sparkle is equally stuck. Fall through to the Vendor/GitHub
        // gate below (code signature + Team ID + bundle id, fails closed) instead
        // of blocking a legitimate update forever. Anything else — a wrong key
        // with no rotation, a tampered archive — throws the original failure.
        // Note `edSignatureMissing` is NOT recoverable here: a key'd feed that
        // drops its signature is suspicious and never reaches this branch.
        if let heldEdFailure {
            guard SignatureVerifier.isEdKeyRotation(
                fileData: archiveData!,
                signatureBase64: remote.edSignature,
                installedKeyBase64: publicKey!,
                downloadedApp: newApp
            ) else { throw heldEdFailure }
        }

        // 4. Validate the final app, whether unpacked or reconstructed from a delta.
        onStage(.verifyingCodeSignature)
        let stagedCheck = try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: newApp,
            installedApp: result.app.path
        )
        // Gate 7: no older build than the installed one, whatever the feed called
        // it. Sparkle-only; see `verifyNoBundleVersionDowngrade`.
        try SignatureVerifier.verifyNoBundleVersionDowngrade(
            installedApp: result.app.path, downloadedApp: newApp)

        // 5. Swap the bundle into place. We do this even while the app is
        // running: macOS keeps the live process on the code it already mapped,
        // so it keeps working on the old version until the user restarts it (the
        // caller surfaces a "Restart" prompt). We never force a quit — that would
        // skip the app's own save-on-quit flow.
        onStage(.installing)
        try await installApp(newApp, over: result.app.path, stagedCheck: stagedCheck)

        onStage(.done)
    }

    /// The route for an installed copy without a Team ID (ad-hoc, or signed with
    /// its own certificate). Trust rests on one thing, as it does for the app's
    /// own Sparkle: the update is signed by the key in the installed copy's
    /// `SUPublicEDKey`. So, unlike the route above:
    ///
    /// - the key is read from the installed bundle on disk, and is required — no
    ///   key falls into no unsigned-feed fallback, because there is no Team-ID
    ///   gate to fall back on;
    /// - the signature is checked before anything is extracted or reconstructed,
    ///   over exactly the bytes downloaded (the patch's own signature on the patch
    ///   route), and a bad one throws at once: no key-rotation fallback, which is
    ///   only safe when gate 3 follows it;
    /// - the identity gate is `verifySparkleKeyOnlyIdentity`: signing never
    ///   changes kind, and the bundle is the same app.
    ///
    /// Gates 2, 5, 5b, 6 and 7 are the same as on the route above.
    private func applyKeyOnly(
        _ result: UpdateResult,
        remote: RemoteVersion,
        download: DownloadedUpdate,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        let installedApp = result.app.path
        let patch = download.appliedPatch
        if let patch, patch.format != .sparkle {
            throw SignatureVerifier.VerifyError.edSignatureMissing
        }
        onStage(.verifyingSignature)
        let file = download.archiveURL
        // The patch's own signature on the patch route, never the archive's.
        let signature = patch.map(\.edSignature) ?? remote.edSignature
        let proof = try await offCooperativePool {
            try SignatureVerifier.verifySparkleSignature(
                of: file, signatureBase64: signature, installedApp: installedApp)
        }

        onStage(.extracting)
        let newApp: URL
        if let patch {
            // The same key `verifySparkleSignature` just used; `reconstruct`
            // checks the patch against it again before applying it.
            newApp = try await DeltaApplier.reconstruct(
                installedApp: installedApp,
                patch: patch,
                patchFile: file,
                workDir: download.workDir,
                edPublicKey: SignatureVerifier.embeddedEdPublicKey(at: installedApp),
                onStage: onStage)
        } else {
            newApp = try await ArchiveExtractor.extractApp(from: file, workDir: download.workDir)
        }

        onStage(.verifyingCodeSignature)
        let trust = SignatureVerifier.ArtifactTrust.sparkleSignature(proof)
        let stagedCheck = try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: newApp,
            installedApp: installedApp,
            trust: trust
        )
        try SignatureVerifier.verifyNoBundleVersionDowngrade(
            installedApp: installedApp, downloadedApp: newApp)

        onStage(.installing)
        let archiveAlone = await offCooperativePool {
            SignatureVerifier.originRestsOnArchiveAlone(trust: trust, installedApp: installedApp)
        }
        try await installApp(
            newApp, over: installedApp, stagedCheck: stagedCheck, refuseElevation: archiveAlone)
        onStage(.done)
    }

    // MARK: - Install

    /// Replace the bundle at `target` with `newApp`. Validation, quarantine
    /// removal, atomic same-volume swap, and the privileged fallback all live in
    /// `InPlaceSwap`, shared with `VendorInstaller`.
    private func installApp(
        _ newApp: URL, over target: URL, stagedCheck: InPlaceSwap.StagedCopyRequirement?,
        refuseElevation: Bool = false
    ) async throws {
        // Awaited in place: the swap's child processes (including the privileged
        // `osascript` that waits on the administrator panel) go through
        // `ChildProcess`, and the swap runs to completion if this task is
        // cancelled. See `InPlaceSwap.replace`.
        //
        // This route's point of no return: a cancel that lands before it stops
        // the install with only the scratch directory to clear; one that lands
        // after it is not seen. See `InstallCommit`.
        //
        // The `SwapOutcome` is dropped on purpose, and said so with `_ =`: both
        // cases mean the new version is live, and a cleanup failure's reason is
        // logged by `replace` itself, in its `defer` —
        // `aCleanupFailureReasonReachesTheInstallLog` reads it back.
        _ = try await InstallCommit.run("swap") {
            try await InPlaceSwap.replace(
                newApp: newApp, over: target, stagedCheck: stagedCheck,
                refuseElevation: refuseElevation)
        }
    }
}
