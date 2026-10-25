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
///   - **Digest-only** (`InstallTrust.publishedDigestOnly`, GitHub rules for
///     ad-hoc signed apps): no Team ID on either side, so gates 3 and 4 become
///     the SHA-256 GitHub publishes for the asset — checked before unpacking —
///     plus the bundle id and version from the bundle's own `Info.plist`. Only
///     while the user allows it; trust is never lowered (see
///     `SignatureVerifier.verifyDigestOnlyIdentity`).
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

    /// Where `SelfUpdaterStash` looks for what an app's own updater parked:
    /// electron-updater's caches root and Cindy's Application Support root. Nil
    /// is the user's real directory; tests point them at scratch directories. A
    /// `DUO_DEV_HOOKS` build also reads `DUO_SELF_UPDATER_CACHES_DIR`, so the
    /// installed `duo` can be shown a fabricated stash without touching another
    /// app's real cache.
    private let stashCachesDirectory: URL?
    private let stashApplicationSupportDirectory: URL?

    public init(stashCachesDirectory: URL? = nil, stashApplicationSupportDirectory: URL? = nil) {
        self.stashApplicationSupportDirectory = stashApplicationSupportDirectory
        #if DUO_DEV_HOOKS
        self.stashCachesDirectory = stashCachesDirectory
            ?? ProcessInfo.processInfo.environment["DUO_SELF_UPDATER_CACHES_DIR"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        #else
        self.stashCachesDirectory = stashCachesDirectory
        #endif
    }

    public enum InstallError: LocalizedError {
        case notVendorUpdate
        case noDownloadURL
        case unknownKind
        case checksumMismatch
        /// The download unpacked, but the payload a stub was supposed to be
        /// carrying is not where the recipe says it is. Carries the detail,
        /// because the fix is a recipe edit and the path is the whole diagnosis.
        case nestedPayloadMissing(String)
        /// A digest-only update reached the installer while the user has not
        /// allowed them (or turned it off after the row was offered).
        case digestOnlyNotAllowed
        /// A digest-only update arrived as something other than the downloaded
        /// asset itself — a stash or a patch — so the published digest cannot
        /// speak for these bytes.
        case digestOnlyNeedsTheAsset
        /// The downloaded app does not carry the edition marker of the
        /// package it was offered as, or carries another edition's
        /// (`OneClickGateRegistry.packageMarkers`).
        case packageEditionMismatch

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
            case .digestOnlyNotAllowed:
                return String(localized: "This app has no developer signature, and one-click updates for such apps are turned off in Settings. Nothing was changed.")
            case .digestOnlyNeedsTheAsset:
                return "Only the release asset itself can be checked against GitHub's published hash. Nothing was changed."
            case .packageEditionMismatch:
                return "The downloaded app is not the edition this copy is. Nothing was changed."
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
        useLocalStash: Bool = true,
        population: [InstalledApp]?,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> DownloadedUpdate {
        // Accept any source whose RemoteVersion carries a resolved installer
        // archive we vet ourselves: the vendor-probe registry ("Vendor") and
        // GitHub release rules with an asset pattern ("GitHub"), and
        // electron-builder manifests ("Electron"), and MyGo manifests ("MyGo"). All
        // download a build we gate on a Team-ID match below — or, for an ad-hoc
        // signed app, on the route its `installTrust` names — so the swap stays
        // same-channel — adding a source name here widens what may flow through
        // the gates, never which gates run. Sparkle/Homebrew install through their
        // own pipelines.
        guard let remote = result.remote,
              remote.sourceName == "Vendor" || remote.sourceName == "GitHub"
                || remote.sourceName == "Electron"
                || remote.sourceName == MyGoUpdateSource.sourceName else {
            throw InstallError.notVendorUpdate
        }
        guard let downloadURL = remote.downloadURL else {
            throw InstallError.noDownloadURL
        }
        guard let kind = remote.vendorInstallerKind, kind != .pkg else {
            throw InstallError.unknownKind  // pkg goes through PackageInstaller
        }

        // Bytes this app's OWN updater has already fetched for exactly this release.
        //
        // Asked BEFORE the delta patch is resolved, not just before it is used: the
        // patch lookup rebuilds install state and then LOGS the route it picked, so
        // resolving it first printed "delta route: … patch N B instead of M B" for a
        // route the stash was about to make moot — a saving that never happened,
        // contradicted three lines later by "bytes=0". A patch is a small download
        // and this is no download at all, so the cheaper answer has to be asked
        // first for the log to be true. See `SelfUpdaterStash` for the gates, and
        // `applyVerified` for what the substitution switches off.
        //
        // Neither a stash nor a patch for a digest-only update: GitHub's digest
        // describes the release asset, and those are other bytes.
        //
        // `useLocalStash` is false on the coordinator's retry after a stash failed
        // to verify or unpack (`LocalStashFailure`): the same file would be picked
        // again until the app's own updater replaced it.
        let digestOnly = remote.installTrust == .publishedDigestOnly
        let stash = digestOnly || !useLocalStash
            ? nil : await SelfUpdaterStash.resolve(
                for: result, population: population, cachesDirectory: stashCachesDirectory,
                applicationSupportDirectory: stashApplicationSupportDirectory)

        // A patch published for exactly the build on disk. Vendors reached through
        // a probe can still serve a Sparkle appcast — ChatGPT does, and every one
        // of its installs comes through here rather than SparkleInstaller, so the
        // delta route has to exist on this side too or it misses the app it was
        // built for. `preferDelta` is false on the coordinator's retry. Whether
        // this build can apply the patch is asked of the patch's format, not up
        // front: a MyGo patch needs no `BinaryDelta`. (Kept out of
        // `patch(for:in:)`, which stays a pure function of the app and the feed.)
        let patch = stash == nil && !digestOnly && preferDelta
            ? DeltaApplier.patch(for: result.app, in: remote).flatMap {
                DeltaApplier.canApply($0.format) ? $0 : nil
            }
            : nil
        if let patch {
            // The comparison is what makes this line useful, so omit it rather
            // than print a placeholder when the source publishes no archive size
            // (vendor probes generally do not).
            let saving = remote.downloadSize.map { " instead of \($0) B" } ?? ""
            let patchSize = patch.size.map(String.init) ?? "unknown"
            Log.install.info("delta route: \(result.app.name, privacy: .public) build \(patch.fromBuild, privacy: .public) → \(remote.version ?? remote.shortVersion ?? "?", privacy: .public), patch \(patchSize, privacy: .public) B\(saving, privacy: .public)")
        } else if stash == nil, preferDelta, !remote.deltas.isEmpty {
            Log.install.info("delta unavailable: \(result.app.name, privacy: .public) build \(result.app.buildVersion ?? "?", privacy: .public) not among \(remote.deltas.count, privacy: .public) published patches — taking the full archive")
        }

        // Scratch dir we own. Removed up front so a retry starts clean; on
        // failure we remove it again below; on success it stays for `apply`.
        //
        // `displayVersion` is vendor-supplied and goes through
        // `filesystemSafeToken` — see the same construction in `SparkleInstaller`
        // for the measured traversal (`999.0/../../…`) that a raw interpolation
        // turns into a recursive delete outside the scratch dir.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DuoUpdater-vendor-\(result.app.scratchSlug)-\((remote.displayVersion ?? "new").filesystemSafeToken)")
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        InstallJournal.noteWorkDirectory(workDir)
        do {
            if let stash {
                // No `.downloading` stage: nothing is fetched, and reporting one
                // made `electron-verify` print "downloading 100%" directly above
                // its own "bytes=0". The next stage the caller sees is `.extracting`.
                return try await adopt(stash, into: workDir)
            }

            // A web page where the archive should be is retried: some vendors
            // answer part of their requests with their home page (HTTP 200,
            // `text/html`) — corkmac.app did about one in two until its fix
            // (2026-10-17, buresdv/Cork#687). Not for a patch, whose bytes are
            // not an archive this check knows.
            var downloader: Downloader!
            var bytesDownloaded: Int64 = 0
            let downloaded = try await Self.fetchArchive(
                maxAttempts: patch == nil ? Self.htmlBodyMaxAttempts : 1
            ) {
                downloader = Downloader(destinationDir: workDir) { fraction in
                    onStage(.downloading(fraction: fraction))
                }
                let file = try await downloader.download(
                    patch?.url ?? downloadURL, headers: remote.downloadHeaders)
                bytesDownloaded += downloader.bytesDownloaded
                return file
            }

            // Ensure the file carries an extension matching its kind, so the
            // extractor dispatches correctly even for extensionless CDN-asset URLs.
            // Skipped for a patch: `kind` describes the ARCHIVE, and renaming a
            // `.delta` to `.zip` would only mislead the extractor it never reaches.
            let archive = patch == nil
                ? try Self.normalizedArchive(downloaded, kind: kind, workDir: workDir)
                : downloaded
            return DownloadedUpdate(
                archiveURL: archive,
                bytesDownloaded: bytesDownloaded,
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
    ///
    /// `digestOnlyAllowed` is the user's setting as it stands at click time
    /// (`UpdateSettings.allowsDigestOnlyInstalls`). No default: every caller has
    /// to say, because the offer the row showed may predate turning it off.
    public func apply(
        _ result: UpdateResult,
        download: DownloadedUpdate,
        digestOnlyAllowed: Bool,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        guard download.appliedPatch != nil else {
            return try await applyVerified(
                result, download: download, digestOnlyAllowed: digestOnlyAllowed, onStage: onStage)
        }
        // A failure on the patch route is recoverable by taking the full archive,
        // which is always published alongside it — except a liveness gate (OS
        // floor, architecture), which refuses the full archive for the identical
        // reason and is re-thrown unwrapped instead. The coordinator retries on
        // this type alone, so a real gate failure on the full route still stops.
        do {
            try await applyVerified(
                result, download: download, digestOnlyAllowed: digestOnlyAllowed, onStage: onStage)
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
        digestOnlyAllowed: Bool,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        let newApp: URL
        let stagedCheck: InPlaceSwap.StagedCopyRequirement?
        do {
            (newApp, stagedCheck) = try await verifiedBundle(
                result, download: download, digestOnlyAllowed: digestOnlyAllowed, onStage: onStage)
        } catch where download.localStash != nil && localStashFailureIsWorthRetrying(error) {
            // The stash is another updater's container, not the route's artifact,
            // so a refusal here speaks for those bytes alone. Only failures before
            // the swap are wrapped: once a bundle has passed every gate, a swap
            // failure would happen identically to the route's own download.
            throw LocalStashFailure(underlying: error)
        }

        // 5. Swap the bundle into place. We do this even while the app is
        // running: macOS keeps the live process on the code it already mapped,
        // so it keeps working on the old version until the user restarts it (the
        // caller surfaces a "Restart" prompt). We never force a quit — that would
        // skip the app's own save-on-quit flow.
        onStage(.installing)
        try await installApp(newApp, over: result.app.path, stagedCheck: stagedCheck)

        onStage(.done)
    }

    /// Steps 1–4 of `applyVerified`: every gate, and the bundle that passed them
    /// with what its privileged swap re-checks (`verifyInstallArtifact`).
    private func verifiedBundle(
        _ result: UpdateResult,
        download: DownloadedUpdate,
        digestOnlyAllowed: Bool,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> (URL, InPlaceSwap.StagedCopyRequirement?) {
        guard let remote = result.remote else {
            throw InstallError.notVendorUpdate
        }

        // Digest-only (ad-hoc signed, no Team ID to gate on): the published
        // digest over the exact archive about to be unpacked is the whole proof of
        // origin, so it runs before anything is extracted — and only if the user
        // still allows this route now. See `InstallTrust.publishedDigestOnly`.
        var trust: SignatureVerifier.ArtifactTrust = .developerID
        if remote.installTrust == .publishedDigestOnly {
            guard digestOnlyAllowed else { throw InstallError.digestOnlyNotAllowed }
            guard download.localStash == nil, download.appliedPatch == nil else {
                throw InstallError.digestOnlyNeedsTheAsset
            }
            onStage(.verifyingSignature)
            let archive = download.archiveURL
            let expected = remote.expectedSHA256
            let proof = try await offCooperativePool {
                try SignatureVerifier.verifyPublishedDigest(of: archive, expected: expected)
            }
            trust = .publishedDigest(
                proof, bundleID: result.app.bundleID ?? "",
                version: remote.shortVersion ?? "")
        }
        // MyGo ad-hoc (`InstallTrust.myGoSignatureOnly`): the vendor's signature
        // over exactly the bytes about to be used is the proof of origin — the
        // patch's own when a patch was downloaded, else the archive's. Checked
        // here, before anything is unpacked or reconstructed, so the identity
        // gates below cannot run without it; the archive and patch paths check
        // it again on their own, which costs one more hash of a few megabytes.
        if remote.installTrust == .myGoSignatureOnly {
            guard download.localStash == nil else { throw InstallError.digestOnlyNeedsTheAsset }
            let signed: (signature: String?, key: String)
            if let patch = download.appliedPatch {
                guard patch.format == .myGo, let key = patch.publicKey else {
                    throw SignatureVerifier.VerifyError.myGoSignatureMissing
                }
                signed = (patch.edSignature, key)
            } else {
                guard let myGo = remote.myGoSignature else {
                    throw SignatureVerifier.VerifyError.myGoSignatureMissing
                }
                signed = (myGo.signature, myGo.publicKey)
            }
            onStage(.verifyingSignature)
            let file = download.archiveURL
            let proof = try await offCooperativePool {
                try SignatureVerifier.verifyMyGoSignature(
                    fileData: try Data(contentsOf: file, options: .mappedIfSafe),
                    signatureBase64: signed.signature, publicKeyBase64: signed.key)
            }
            trust = .myGoSignature(
                proof, bundleID: result.app.bundleID ?? "",
                version: remote.shortVersion ?? "")
        }

        var newApp: URL
        // The delta branch below reconstructs the app from the installed copy and
        // never sees an archive, so `nestedArchivePath` does not apply to it and is
        // not consulted there. Unreachable today — neither recipe that declares a
        // nested payload publishes patches — but if a stub-shipping vendor ever
        // also served an appcast, the symptom would be a bundle-id refusal rather
        // than anything unsafe.
        if let patch = download.appliedPatch {
            // `expectedSHA512` describes the ARCHIVE, so it cannot speak for these
            // bytes and is deliberately not applied here. `reconstruct` checks what
            // can be checked — the baseline, then the patch's own EdDSA signature
            // when the vendor publishes one and the key is known (the app's
            // `SUPublicEDKey` for Sparkle, the recipe's `myGoPublicKey` for MyGo).
            // ChatGPT does both (45 of 45 patches signed), so its patch route ends
            // up better proven than its full-archive path, which has no signature
            // to check; a MyGo archive does (`remote.myGoSignature`, below).
            // Awaited in place: `BinaryDelta` runs through `ChildProcess`, which
            // waits without parking a thread, and it runs to completion if this task is
            // cancelled — see `DeltaApplier.apply`.
            newApp = try await DeltaApplier.reconstruct(
                installedApp: result.app.path,
                patch: patch,
                patchFile: download.archiveURL,
                workDir: download.workDir,
                edPublicKey: result.app.sparkleEdPublicKey,
                onStage: onStage)
        } else {
            let installed = result.app.path
            newApp = try await Self.unpackVerified(
                remote, download: download,
                // The installed copy names the bundle, not the archive.
                bundleName: installed.deletingPathExtension().lastPathComponent,
                onStage: onStage,
                vetStub: Self.stubSignedByTeam(of: installed))
        }

        // 3c. The edition the offer was gated as (`OneClickGate.offering`):
        // the package itself must carry that edition's marker and, read whole,
        // lack the other edition's, so an asset whose name says one edition and
        // whose binary is the other (or both) cannot replace a copy. No markers
        // for every app but those with edition-scoped gates. Before the
        // signature gates only because it needs no signature to refuse; both
        // run before anything is swapped.
        for required in OneClickGateRegistry.packageMarkers(
            for: result.app.recipeBundleID, offering: remote) {
            let app = newApp
            let presence = await offCooperativePool {
                ExecutableMarker.presenceUncached(required.marker, inMainExecutableOf: app)
            }
            guard presence == (required.present ? .present : .absent) else {
                throw InstallError.packageEditionMismatch
            }
        }

        // 4. Validate the final app, whether unpacked or reconstructed from a delta.
        onStage(.verifyingCodeSignature)
        let stagedCheck = try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: newApp,
            installedApp: result.app.path,
            trust: trust
        )
        return (newApp, stagedCheck)
    }

    /// Gate 1 and unpacking for a full archive: the published digests and MyGo
    /// signature over the exact bytes downloaded, then the `.app` out of them —
    /// through `ContentsPayload` or one level of installer stub when the recipe
    /// says so. Returns the bundle the identity gates are to read.
    ///
    /// Split out of `applyVerified` so `duo verify-install` runs these same steps
    /// on a machine with nothing installed. Everything here is about the download
    /// alone, except two things a caller supplies: the bundle's name for an
    /// assembled `ContentsPayload`, and `vetStub` — what proves an installer stub
    /// is the vendor's before its payload is taken out (production: a valid
    /// signature from the installed app's Team). `vetStub` runs off the
    /// cooperative pool, as the Security calls in it need (#351).
    static func unpackVerified(
        _ remote: RemoteVersion,
        download: DownloadedUpdate,
        bundleName: String,
        onStage: @Sendable @escaping (InstallStage) -> Void,
        vetStub: @Sendable @escaping (URL) throws -> Void
    ) async throws -> URL {
        var newApp: URL
        // 2. Gate 1 (optional) — SHA-512 over the exact bytes we downloaded.
        //
        // Skipped for a local stash, which is a DIFFERENT container from the
        // artifact this digest describes. Run here it could not pass, and it
        // would fail as `checksumMismatch` ("may be corrupt or tampered") for a
        // file that is neither. Its replacement already ran:
        // `SelfUpdaterStash.resolve` checks these exact bytes against the digest
        // the app's own updater recorded for them. See
        // `docs/engine-notes/self-updater-stash.md` §6.
        if let expected = remote.expectedSHA512, download.localStash == nil {
            onStage(.verifyingSignature)
            try Self.verifyChecksum(download.archiveURL, expectedBase64: expected)
        }
        // The same gate for a vendor that publishes SHA-256 hex
        // (`VendorInstallSpec.checksumFormat`) and for a GitHub asset with a
        // `digest`. A digest-only download already had its SHA-256 checked
        // above, as its proof of origin.
        if remote.installTrust == .developerID, let expected = remote.expectedSHA256,
           download.localStash == nil {
            onStage(.verifyingSignature)
            let archive = download.archiveURL
            try await offCooperativePool { try Self.verifySHA256(archive, expectedHex: expected) }
        }
        // A MyGo vendor's own signature of the archive, over its SHA-256, with
        // the key the recipe states. Required once a key is stated: a missing
        // signature fails here as `myGoSignatureMissing`.
        // Skipped for a local stash for the reason the digests above are.
        if let myGo = remote.myGoSignature, download.localStash == nil {
            onStage(.verifyingSignature)
            let archive = download.archiveURL
            try await offCooperativePool {
                let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
                try SignatureVerifier.verifyMyGoSignature(
                    fileData: bytes,
                    signatureBase64: myGo.signature,
                    publicKeyBase64: myGo.publicKey)
            }
        }

        // 3. Unpack the .app.
        onStage(.extracting)
        // Awaited in place: see `extractApp` for why it needs no hop; a cancel
        // tears the tool down and throws `CancellationError`.
        if let pattern = remote.contentsArchivePattern, download.localStash == nil {
            // A package that carries the app's INSIDE rather than the app —
            // see `ContentsPayload`, which unpacks both levels and assembles a
            // bundle for the gates below to read. It replaces `extractApp`
            // rather than following it: there is no `.app` at either level, so
            // extraction would answer `noAppFound` before this could run.
            //
            // Skipped for a local stash, and for the same reason as the
            // checksum and `nestedArchivePath` above: this describes one
            // vendor's own update package, and a stash is by definition some
            // other updater's container. The consequence if one ever appears
            // for an app of this shape is a loud `noAppFound` from the line
            // below, not a wrong install.
            newApp = try await ContentsPayload.assemble(
                outerArchive: download.archiveURL,
                innerArchivePattern: pattern,
                bundleName: bundleName,
                workDir: download.workDir)
        } else {
            newApp = try await ArchiveExtractor.extractApp(
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
            //
            // Also skipped for a local stash, and for the same reason as the
            // checksum above: this path describes where a payload sits inside one
            // particular stub installer the vendor publishes. A zip of the app is
            // not that stub, so the lookup would fail as `nestedPayloadMissing` —
            // naming a file the archive was never supposed to hold. ⚠️ No test
            // pins this one; `LocalStashInstallWiringTests` says why.
            if let nested = remote.nestedArchivePath, download.localStash == nil {
                let outer = newApp
                try await offCooperativePool { try vetStub(outer) }
                newApp = try await unwrapNestedPayload(at: nested, inside: newApp, workDir: download.workDir)
            }
        }
        return newApp
    }

    /// Production's `vetStub`: the stub's seal verifies, its Team is the
    /// installed copy's, and it is signed the way the installed copy's
    /// designated requirement says — a Team string alone is only what a
    /// certificate claims (`verifySignedLikeInstalledCopy`). The stub's own
    /// identifier differs from the app's, so the requirement is re-aimed at it.
    /// Built here, outside any `async` body, because it only ever runs inside
    /// `unpackVerified`'s `offCooperativePool` hop.
    static func stubSignedByTeam(of installed: URL) -> @Sendable (URL) throws -> Void {
        { stub in
            try SignatureVerifier.verifyCodeSignature(appAt: stub)
            try SignatureVerifier.verifyTeamIdentifierMatch(
                installedApp: installed, downloadedApp: stub)
            try SignatureVerifier.verifySignedLikeInstalledCopy(
                installedApp: installed, downloadedApp: stub)
        }
    }

    /// Extract the archive at `relativePath` inside the installer stub `stub`, and
    /// return the `.app` it holds.
    ///
    /// The path is resolved and then checked to still be inside `stub`, the same
    /// containment check `ArchiveExtractor` makes about the bundle it returns: a
    /// registry string is not user input, but a `..` in one would otherwise reach
    /// anywhere on disk, and this is two steps upstream of a privileged swap.
    ///
    /// Internal, not `private`, for `NestedPayloadUnwrapTests`: the route reaches
    /// it only after the stub's signature verifies, which an unsigned fixture
    /// never does (`LocalStashInstallWiringTests` says why).
    static func unwrapNestedPayload(
        at relativePath: String, inside stub: URL, workDir: URL
    ) async throws -> URL {
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
        // Awaited, like the outer extraction — see `extractApp`.
        return try await ArchiveExtractor.extractApp(from: nested, workDir: inner)
    }

    // MARK: - Checksum

    /// `checksumMismatch` unless `file`'s SHA-256 is `expectedHex` (any case).
    static func verifySHA256(_ file: URL, expectedHex: String) throws {
        guard CLIToolTrust.matches(try BundleArchive.sha256(of: file), published: expectedHex) else {
            throw InstallError.checksumMismatch
        }
    }

    static func verifyChecksum(_ file: URL, expectedBase64: String) throws {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA512.hash(data: data)
        let actual = Data(digest).base64EncodedString()
        // Vendors publish base64; compare exactly (trim incidental whitespace).
        guard actual == expectedBase64.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw InstallError.checksumMismatch
        }
    }

    /// Take over an installer the app's own updater already downloaded: copy it
    /// into our scratch directory and describe it as a `DownloadedUpdate` the apply
    /// phase can consume unchanged.
    ///
    /// Extracted from `download` so it can be tested without a cache directory on
    /// this machine to point at — the resolution in front of it
    /// (`SelfUpdaterStash.resolve`) has its own suite, and this is the part that
    /// decides what the rest of the install sees.
    ///
    /// **Copied, never used in place and never deleted.** The file belongs to the
    /// other updater, which is free to clear `pending/` or overwrite it while we
    /// work, and `workDir` is removed wholesale by our caller — pointing
    /// `archiveURL` at the original would make that cleanup delete another
    /// updater's download.
    ///
    /// `kind` comes from the stash, not from the route: they can differ (see
    /// `docs/engine-notes/self-updater-stash.md` §6).
    func adopt(
        _ stash: LocalStagedInstaller, into workDir: URL
    ) async throws -> DownloadedUpdate {
        let local = workDir.appendingPathComponent(stash.archiveURL.lastPathComponent)
        let from = stash.archiveURL
        try await offCooperativePool {
            try FileManager.default.copyItem(at: from, to: local)
        }
        return DownloadedUpdate(
            archiveURL: try Self.normalizedArchive(local, kind: stash.kind, workDir: workDir),
            // Zero: the field is what went over the network, and nothing did.
            // Reporting the file size here would put the whole archive in the
            // traffic ledger for a transfer that never happened, which is the one
            // number that ledger exists to be trusted on.
            bytesDownloaded: 0,
            workDir: workDir, finalHost: nil, localStash: stash)
    }

    /// Downloads of an archive that come back as a web page before one is kept.
    /// At one in two (Cork's server before its 2026-10-17 fix), four attempts
    /// all failing is 1 in 16.
    static let htmlBodyMaxAttempts = 4

    /// Runs `fetch` until the file it returns is not an HTML document, at most
    /// `maxAttempts` times; each HTML body is deleted. The last one is returned
    /// as is, so the extractor reports the failure it always has.
    static func fetchArchive(
        maxAttempts: Int, _ fetch: () async throws -> URL
    ) async throws -> URL {
        var attempt = 1
        while true {
            let file = try await fetch()
            guard attempt < maxAttempts, isHTMLDocument(at: file) else { return file }
            Log.install.info("download was a web page, not an archive: retry \(attempt, privacy: .public)/\(maxAttempts - 1, privacy: .public)")
            try? FileManager.default.removeItem(at: file)
            attempt += 1
        }
    }

    /// Whether a downloaded file is an HTML document: its first bytes, after an
    /// optional UTF-8 BOM and whitespace, open `<!DOCTYPE html` or `<html`. No
    /// zip (`PK`), tar.gz (`1f 8b`) or disk image starts that way.
    static func isHTMLDocument(at file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 512), !head.isEmpty else { return false }
        var bytes = head[...]
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let text = String(decoding: bytes, as: UTF8.self)
            .drop { $0.isWhitespace }.prefix(14).lowercased()
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html")
    }

    /// Move/rename the download so its extension reflects `kind`. The Tauri/CDN
    /// case has no extension in the URL, which would defeat extraction-by-suffix.
    static func normalizedArchive(_ file: URL, kind: VendorInstallerKind, workDir: URL) throws -> URL {
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
    private func installApp(
        _ newApp: URL, over target: URL, stagedCheck: InPlaceSwap.StagedCopyRequirement?
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
            try await InPlaceSwap.replace(newApp: newApp, over: target, stagedCheck: stagedCheck)
        }
    }
}

/// A local stash (`DownloadedUpdate.localStash`) that failed before the swap —
/// it did not unpack, or the bundle in it did not pass a gate. The coordinator
/// retries once with `useLocalStash: false`, so the route's own artifact is
/// downloaded and verified as usual; nothing else lands there. The stash file
/// itself is left alone: it belongs to the other app's updater.
///
/// Carries no byte count, unlike `DeltaRouteFailure`: taking a stash spends no
/// network bytes (`VendorInstaller.adopt` reports 0), so the retry's own
/// download is the whole total.
public struct LocalStashFailure: LocalizedError {
    public let underlying: Error

    public init(underlying: Error) {
        self.underlying = underlying
    }

    /// Reads as the underlying problem, as `DeltaRouteFailure` does.
    public var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? underlying.localizedDescription
    }
}

/// Whether a failure on a local stash is one the route's own artifact could
/// avoid. Everything before the swap is, by default: the stash is another
/// updater's container for the same release (§6 of
/// `docs/engine-notes/self-updater-stash.md`), so a bad zip, a bundle with the
/// wrong Team or no notarization, or the wrong architecture slice says nothing
/// about the route's download. The exceptions are the failures the download
/// would hit for the same reason, or that are not about the bytes at all:
///   - cancellation — the user stopped this install;
///   - no free space — a download needs more room, not less;
///   - the digest-only setting turned off since the row was offered;
///   - the OS floor — `LSMinimumSystemVersion` belongs to the version, and the
///     stash already matched the route's version.
public func localStashFailureIsWorthRetrying(_ error: Error) -> Bool {
    if error is CancellationError { return false }
    if error is DiskSpaceGuard.InsufficientSpace { return false }
    if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return false }
    if let posix = error as? POSIXError, posix.code == .ENOSPC { return false }
    if case ArchiveExtractor.ExtractError.toolFailed(_, _, let output) = error,
       output.localizedCaseInsensitiveContains("No space left on device") {
        return false
    }
    if case VendorInstaller.InstallError.digestOnlyNotAllowed = error { return false }
    if case SignatureVerifier.VerifyError.unsupportedSystemVersion = error { return false }
    return true
}
