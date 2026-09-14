import Foundation
import AppKit
import CryptoKit
import Darwin

/// Handles updates that ship as an installer package (`pkg` casks like AweSun,
/// Tailscale). We can't swap those in place, and a non-interactive `brew` can't
/// elevate to run the installer — so we download the official package (the same
/// URL Homebrew would use) and hand it to macOS's own installer, which prompts
/// for admin itself. The user confirms the install in a trusted, native UI.
///
/// Architecture limitation (#205): this route does NOT run
/// `SignatureVerifier.verifyRunnableArchitecture` (Gate 5) or
/// `verifyNoArchitectureDowngrade` (Gate 5b). We inspect package metadata, not
/// the payload's Mach-O executables. Signature, Team ID and destination checks
/// therefore do not prevent an Intel-only package from replacing a native app.
/// This applies to every caller, including packages unwrapped from disk images.
///
/// We deliberately avoid full payload expansion here: it adds disk space and
/// unpacking work proportional to the payload, potentially gigabytes. A vendor's
/// `hostArchitectures` declaration is not proof of the installed app's slices.
///
/// ⚠️ **That declaration has now been measured, and it cannot stand in for the
/// gates** — worth knowing before reaching for it, because "just read
/// `hostArchitectures`" is the obvious repair and it does not work. Across the
/// whole pkg route on 2026-09-07 (#415): 15 packages declared, **every one of
/// them universal**, 7 declared nothing, 1 was not a flat package. The
/// declaration has never once said "Intel-only" here, so a gate on it would not
/// have fired. And the only architecture-specific packages in the registry are
/// exactly the ones that declare nothing — WeChat DevTools ships
/// `wechat_devtools_..._darwin_arm64.pkg` with no declaration at all. Where
/// architecture varies the declaration is blind; where it exists architecture
/// does not vary. `duo verify --pkgarch` now tracks it for DRIFT on that basis,
/// which is not the same claim as checking what will be installed.
/// Handoff also returns before installation completes, so this actor performs no
/// post-install architecture verification or automatic architecture rollback.
/// Architecture compatibility on this route remains dependent on the vendor's
/// package and system installer; it is not a DuoUpdater architecture guarantee.
///
/// ## Which `SignatureVerifier` gates this route runs, as of #639
///
/// | Gate | pkg route |
/// | --- | --- |
/// | 1 EdDSA over the download | caller's `verifyDownload` (Sparkle only) |
/// | 2 code signature | **no** — `pkgutil --check-signature` on the package instead |
/// | 3 Team ID match | yes, against the package's Developer ID Installer cert |
/// | 4 bundle identifier match | **no** — replaced by the destination check below |
/// | 5 runnable architecture | **no** (#205, above) |
/// | 5b architecture downgrade | **no** (#205, above) |
/// | 6 runnable system version | **yes, best-effort** — `verifyPayloadSystemVersion` below |
///
/// Every "yes" above except gate 6 is fail-CLOSED: it refuses when it cannot
/// read what it needs. **Gate 6 is fail-open**, and reading it as a guarantee is
/// the mistake this row is worded to prevent. It refuses a package whose payload
/// app declares an `LSMinimumSystemVersion` above this Mac, and it lets through
/// a `pbzx`-compressed payload, a payload member that is not a readable plist, a
/// package whose Bom never names this app's `Info.plist`, and a package whose
/// metadata could not be read at all. Each fail-open is logged with which one it
/// was (`PayloadFloor`), because "no floor" standing for four different
/// situations is how a gate quietly stops firing.
///
/// Gate 6 used to be absent here entirely, and the note above said nothing about
/// it — so a pkg declaring a floor above this Mac installed to completion, was
/// reported as a success, and then would not launch. It now runs against the
/// payload's own plist, through the same
/// `SignatureVerifier.canRun(minimumSystemVersion:on:)` the `.app` routes use.
/// Measured end to end on two real packages (2026-09-15): UU Remote 4.35.0, the
/// vendor package for one of the pkg recipes in the registry, whose payload
/// declares `11.0`; and `pkgbuild`/`productbuild` output in both payload shapes.
///
/// Two things gate 6 on this route deliberately does NOT do, recorded so the
/// next reader does not take either for a bug:
///
/// - **A refusal costs the download again on the next attempt.** This gate sits
///   after the bytes are on disk, because the floor is inside them, and there is
///   no row state for "this pkg needs a newer macOS" — so the row keeps offering
///   Update and each attempt re-downloads before refusing. Making the refusal
///   visible before the download is detection-side work (`.needsNewerMacOS`),
///   not something this gate can do.
/// - **It reads the FIRST payload path that names this app's `Info.plist`.** A
///   package containing two bundles of the same name would have its floor read
///   from whichever the Bom lists first. No package in the registry has that
///   shape, and the destination gate has already established which app this
///   package updates, so the cost would be a wrong floor rather than a wrong app.
public actor PackageInstaller {

    /// The final hand-over keeps its integrity check and `NSWorkspace.open` in one
    /// MainActor turn. Injectable so tests can observe it without a live Installer.
    private let handOff: @Sendable (
        URL, @Sendable () throws -> Void
    ) async throws -> Void
    /// Test seam for the package gate. Production always uses `verifyOpenable`;
    /// tests can substitute a deterministic byte-level gate.
    private let packageGate: (@Sendable (URL, URL) async throws -> Void)?
    /// What gate 6 compares the payload's floor against. A parameter rather than
    /// a `ProcessInfo` read inside the gate, so a test can pin "this Mac" without
    /// its answer depending on the machine it runs on (CLAUDE.md).
    private let osVersion: String

    public init(osVersion: String = HostOS.numericVersion()) {
        self.handOff = { url, finalIntegrityCheck in
            try await MainActor.run {
                // No suspension is allowed between this lightweight metadata
                // check and LaunchServices consuming the path. Full content hashing
                // stays off MainActor so a large package cannot freeze the UI.
                try finalIntegrityCheck()
                _ = NSWorkspace.shared.open(url)
            }
        }
        self.packageGate = nil
        self.osVersion = osVersion
    }

    init(
        opener: @escaping @Sendable (URL) async -> Void,
        packageGate: (@Sendable (URL, URL) async throws -> Void)? = nil,
        osVersion: String = HostOS.numericVersion()
    ) {
        self.handOff = { url, finalIntegrityCheck in
            try finalIntegrityCheck()
            await opener(url)
        }
        self.packageGate = packageGate
        self.osVersion = osVersion
    }

    public enum PackageError: LocalizedError {
        case noURL
        case downloadFailed(String)
        case unsignedPackage
        case noInstallablePackage
        case packageTeamIdentifierMissing
        case packageTeamIdentifierMismatch(installed: String, package: String)
        case packageDestinationMismatch(installed: String, destinations: [String])
        case packageDestinationsUnreadable
        case packageRequiresNewerSystem(required: String, host: String)

        public var errorDescription: String? {
            switch self {
            case .noURL: return "This update has no download URL."
            case .downloadFailed(let m): return "Could not prepare the installer: \(m)"
            case .unsignedPackage:
                return "The downloaded installer package isn't signed by a valid Developer ID — it may be corrupt or tampered. Nothing was installed."
            case .noInstallablePackage:
                return "The downloaded disk image did not contain an installer package DuoUpdater could verify. Nothing was opened."
            case .packageTeamIdentifierMissing:
                return "Could not read the installer package's Developer ID team. Nothing was opened."
            case .packageDestinationsUnreadable:
                return "Could not read where this package installs, so it was not opened."
            case .packageDestinationMismatch(let installed, let destinations):
                return "This package installs to \(destinations.joined(separator: ", ")), not to \(installed). Refusing to install."
            case .packageTeamIdentifierMismatch(let installed, let package):
                return "Installer Team Identifier mismatch: installed “\(installed)” vs package “\(package)”. Refusing to open it."
            case .packageRequiresNewerSystem(let required, let host):
                return "This installer package requires macOS \(required) and this Mac runs macOS \(host). Refusing to install a build it cannot launch."
            }
        }
    }

    /// What `downloadAndOpen` handed to the system installer.
    ///
    /// `packageURL` is kept so the caller can offer to re-open the *same* download
    /// later — the work directory deliberately outlives this call (see
    /// `sweepStaleWorkDirectories`), so a user who closed the installer window
    /// shouldn't have to pull the package down again.
    public struct OpenedPackage: Sendable {
        /// Exact bytes downloaded, for per-app traffic accounting.
        public let bytesDownloaded: Int64
        /// The `.pkg`/`.mpkg` actually opened (already unwrapped from a `.dmg`).
        public let packageURL: URL
        /// The host that actually served the bytes after redirects, for the
        /// per-host install gate (see `Downloader.finalHost`).
        public let finalHost: String?

        public init(bytesDownloaded: Int64, packageURL: URL, finalHost: String? = nil) {
            self.bytesDownloaded = bytesDownloaded
            self.packageURL = packageURL
            self.finalHost = finalHost
        }
    }

    /// Download `url` and open the resulting installer (or the disk image that
    /// contains it). Returns once the installer has been launched — the actual
    /// install happens in macOS's installer, under the user's control.
    /// - Parameter beforeOpen: runs after a preliminary package gate and immediately
    ///   before the final gate + Installer hand-over, so a caller retiring the window
    ///   this package supersedes does it while Installer is idle. Not called when the
    ///   download or preliminary gate fails.
    @discardableResult
    public func downloadAndOpen(
        url: URL?,
        installedApp: URL,
        headers: [String: String] = [:],
        onStage: @Sendable @escaping (InstallStage) -> Void,
        verifyDownload: @Sendable (URL) throws -> Data? = { _ in nil },
        beforeOpen: @Sendable () async -> Void = {}
    ) async throws -> OpenedPackage {
        guard let url else { throw PackageError.noURL }

        // Each install below gets its own dir that we deliberately never delete
        // (the system Installer keeps reading the package after we return), so
        // make good on "drop stale copies on the next run" here: clear out the
        // ones old enough that no Installer window could still be using them.
        Self.sweepStaleWorkDirectories()

        // Keep each download in its own scratch directory where the system
        // installer can read it for the whole session. This method awaits during
        // the download, so the actor may be re-entered by another package update;
        // a shared `/tmp/DuoUpdater-pkg/mnt` would let concurrent installs collide
        // or remove a package an already-open Installer window is still reading.
        let workDir = Self.workDirectory(forInstalledApp: installedApp)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        var keepWorkDirectory = false
        defer {
            // Installer keeps reading a successfully opened package after this
            // method returns. Every failure/cancellation path, however, has no
            // consumer and must release the potentially very large download now.
            if !keepWorkDirectory { try? FileManager.default.removeItem(at: workDir) }
        }

        let downloader = Downloader(destinationDir: workDir) { fraction in
            onStage(.downloading(fraction: fraction))
        }
        let file = try await downloader.download(url, headers: headers)
        let bytesDownloaded = downloader.bytesDownloaded

        // Source-specific proof over the original downloaded bytes belongs before
        // any parsing or mounting. Sparkle uses this seam for its enclosure EdDSA;
        // Vendor/Homebrew packages use the no-op default and retain the common pkg
        // gate in `handOver` below — signature, Team ID, destination and gate 6;
        // the header table is the one list of what that is.
        let sourceFingerprint = try verifyDownload(file)
        // A signed DMG is about to be parsed into a different inner file, so prove
        // the pathname still holds the exact enclosure whose EdDSA check passed.
        // A direct pkg is not re-read here; it carries this proof into `handOver`
        // as `approvedFingerprint`, which is then what the seals there are pinned
        // against. It is NOT an extra full read saved — `handOver` hashes the file
        // whole twice either way, deliberately (see its two-seal comment) — only
        // one the DMG route pays on a different file.
        if file.pathExtension.lowercased() == "dmg", let sourceFingerprint {
            // Hashing hundreds of megabytes is blocking work, and this is reached
            // from an async install. See `offCooperativePool`.
            let seen = try await offCooperativePool { try Self.contentFingerprint(of: file) }
            guard seen == sourceFingerprint else {
                throw PackageError.downloadFailed(
                    "The download changed after source verification. Nothing was opened.")
            }
        }

        onStage(.installing)
        // The DMG route mounts with `hdiutil` and copies with `ditto`, awaited
        // through `ChildProcess` rather than parked on a thread.
        let toOpen = try await resolveInstaller(
            from: file, workDir: workDir, installedApp: installedApp)
        let directSourceFingerprint = toOpen.standardizedFileURL == file.standardizedFileURL
            ? sourceFingerprint : nil
        try await handOver(
            toOpen, installedApp: installedApp,
            approvedFingerprint: directSourceFingerprint,
            beforeOpen: beforeOpen)
        keepWorkDirectory = true
        onStage(.done)
        return OpenedPackage(
            bytesDownloaded: bytesDownloaded,
            packageURL: toOpen,
            finalHost: downloader.finalHost)
    }

    /// Re-open a package this installer already downloaded, without fetching it
    /// again. The work directory outlives `downloadAndOpen` by design, so a user
    /// who dismissed the installer window (or relaunched DuoUpdater) can resume
    /// from the local copy — these packages run to hundreds of megabytes.
    ///
    /// Re-runs the whole gate (see the header table) rather than trusting the
    /// earlier pass: the file has been sitting in a world-readable temp directory since
    /// then, and this is the same fail-closed posture as the first open — the
    /// package runs install scripts with admin rights the moment the user
    /// confirms.
    ///
    /// Opening a package the system installer already has open does *not* spawn a
    /// second window — macOS treats it as the same document and brings the
    /// existing one forward (verified against Installer.app on macOS 27).
    public func reopen(package: URL, installedApp: URL) async throws {
        guard FileManager.default.fileExists(atPath: package.path) else {
            throw PackageError.noInstallablePackage
        }
        try await handOver(package, installedApp: installedApp)
    }

    /// Gate and fingerprint the package, let the caller settle whatever this open
    /// supersedes, then re-establish both properties and hand it to Installer.
    ///
    /// The order is the point. `beforeOpen` is where the caller closes the stale
    /// Installer window this package replaces, and both neighbours matter:
    ///
    /// - *After* the gate, so a package that fails verification never costs the user
    ///   the window they already have open.
    /// - *Before* the final gate + open, so the close lands while Installer is idle.
    ///   A pinned content fingerprint prevents another valid package from the same
    ///   Team inheriting the selected enclosure's approval, while the second Team
    ///   gate re-establishes the package identity after the async callback. Doing
    ///   the close after opening instead put an AX press into the exact window in
    ///   which Installer is
    ///   opening a new document — the state its own `AXDocument` reads go blank in,
    ///   and the state a macOS 26.6 Installer crashed in (`_volumeAppeared:` messaging
    ///   a dead object one second after we opened a third package into it).
    private func handOver(
        _ toOpen: URL,
        installedApp: URL,
        approvedFingerprint: Data? = nil,
        beforeOpen: @Sendable () async -> Void = {}
    ) async throws {
        // Preliminary gate: an ordinary bad package must not retire the valid
        // Installer window it was meant to replace.
        //
        // Gate, then seal, and the order between them is load-bearing. They used to
        // share ONE `offCooperativePool` hop so that nothing could come between
        // them; they are two statements now because the gate's `pkgutil`/`xar`/
        // `lsbom` are awaited through `ChildProcess` and cannot run inside a
        // synchronous hop. The gate hops its own `SecStaticCode…` call (the #351
        // call) and the seal hops its hashing — 375 MB for ToDesk. See
        // `offCooperativePool`.
        try await applyPackageGate(toOpen, installedApp: installedApp)
        let preliminarySeal = try await offCooperativePool { try Self.contentSeal(of: toOpen) }
        let pinnedFingerprint = approvedFingerprint ?? preliminarySeal.fingerprint
        if approvedFingerprint != nil,
           preliminarySeal.fingerprint != pinnedFingerprint {
            throw PackageError.downloadFailed(
                "The installer changed after source verification. Nothing was opened.")
        }
        await beforeOpen()
        // Final gate: `beforeOpen` is async, so the user-owned temp path may have
        // changed while it ran. Re-establish every signature/identity invariant
        // immediately before handing the path to Installer.
        try await applyPackageGate(toOpen, installedApp: installedApp)
        let finalSeal = try await offCooperativePool { try Self.contentSeal(of: toOpen) }
        guard finalSeal.fingerprint == pinnedFingerprint else {
            throw PackageError.downloadFailed(
                "The installer changed after verification. Nothing was opened.")
        }
        try await handOff(toOpen) {
            guard try Self.integritySnapshot(of: toOpen) == finalSeal.snapshot else {
                throw PackageError.downloadFailed(
                    "The installer changed after verification. Nothing was opened.")
            }
        }
    }

    private struct ContentSeal: Sendable {
        let fingerprint: Data
        let snapshot: [FileSnapshot]
    }

    private struct FileSnapshot: Sendable, Equatable {
        let relativePath: String
        let device: UInt64
        let inode: UInt64
        let mode: UInt16
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    /// Hash content off MainActor, bracketing it with kernel metadata snapshots so
    /// a file changing *during* the read is rejected too. The final hand-off only
    /// has to repeat the cheap snapshot: inode catches replacement; ctime catches
    /// in-place writes and chmod even if an attacker restores size and mtime.
    private static func contentSeal(of file: URL) throws -> ContentSeal {
        let before = try integritySnapshot(of: file)
        let fingerprint = try contentFingerprint(of: file)
        let after = try integritySnapshot(of: file)
        guard before == after else {
            throw PackageError.downloadFailed(
                "The installer changed while it was being verified. Nothing was opened.")
        }
        return ContentSeal(fingerprint: fingerprint, snapshot: after)
    }

    private static func integritySnapshot(of root: URL) throws -> [FileSnapshot] {
        let values = try root.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw PackageError.downloadFailed("The installer package is a symbolic link.")
        }
        let entries: [URL]
        if values.isDirectory == true {
            entries = [root] + (try directoryEntries(in: root))
        } else if values.isRegularFile == true {
            entries = [root]
        } else {
            throw PackageError.noInstallablePackage
        }
        let rootPath = root.standardizedFileURL.path
        return try entries.map { entry in
            let path = entry.standardizedFileURL.path
            let relative = path == rootPath ? "" : String(path.dropFirst(rootPath.count + 1))
            return try fileSnapshot(entry, relativePath: relative)
        }
    }

    private static func fileSnapshot(_ file: URL, relativePath: String) throws -> FileSnapshot {
        var info = stat()
        let status = file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &info)
        }
        guard status == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return FileSnapshot(
            relativePath: relativePath,
            device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
            mode: UInt16(info.st_mode), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    static func contentFingerprint(of file: URL) throws -> Data {
        let values = try file.resourceValues(forKeys: [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw PackageError.downloadFailed("The installer package is a symbolic link.")
        }

        var hasher = SHA256()
        if values.isRegularFile == true {
            try hashFileContents(file, into: &hasher)
        } else if values.isDirectory == true {
            try hashDirectoryTree(file, into: &hasher)
        } else {
            throw PackageError.noInstallablePackage
        }
        return Data(hasher.finalize())
    }

    private static func hashDirectoryTree(_ root: URL, into hasher: inout SHA256) throws {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        let entries = try directoryEntries(in: root)

        for entry in entries {
            let path = entry.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else {
                throw PackageError.downloadFailed("The installer package escaped its directory.")
            }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            let values = try entry.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            ])
            let kind: UInt8
            if values.isDirectory == true { kind = 0x44 }       // D
            else if values.isRegularFile == true { kind = 0x46 } // F
            else { throw PackageError.noInstallablePackage }

            hasher.update(data: Data([kind]))
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            let attributes = try fm.attributesOfItem(atPath: entry.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            var bigEndianPermissions = permissions.bigEndian
            withUnsafeBytes(of: &bigEndianPermissions) { hasher.update(bufferPointer: $0) }
            // Length-prefix file bytes so two different directory layouts cannot
            // hash to the same record stream merely by moving a would-be next
            // entry header into the previous file's contents.
            let size = kind == 0x46
                ? (attributes[.size] as? NSNumber)?.uint64Value ?? 0 : 0
            var bigEndianSize = size.bigEndian
            withUnsafeBytes(of: &bigEndianSize) { hasher.update(bufferPointer: $0) }
            if kind == 0x46 { try hashFileContents(entry, into: &hasher) }
        }
    }

    private static func directoryEntries(in root: URL) throws -> [URL] {
        let fm = FileManager.default
        var entries: [URL] = []
        var directories = [root]
        while let directory = directories.popLast() {
            for entry in try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ]) {
                let values = try entry.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ])
                guard values.isSymbolicLink != true else {
                    throw PackageError.downloadFailed(
                        "The installer package contained a symbolic link.")
                }
                entries.append(entry)
                if values.isDirectory == true { directories.append(entry) }
            }
        }
        entries.sort { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
        return entries
    }

    private static func hashFileContents(_ file: URL, into hasher: inout SHA256) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
    }

    /// `nonisolated`, like the helpers it reaches (`verifyOpenable`,
    /// `packageSignature`, `runCapturingOutput`, `run`, `resolveInstaller`): all of
    /// them read only `let` state, and a `nonisolated async` function runs off
    /// this actor, so the actor is free while their child processes run. The
    /// actor was never the thing ordering these anyway — `handOver` already
    /// suspends between its two gates, and `downloadAndOpen` awaits its download.
    private nonisolated func applyPackageGate(_ package: URL, installedApp: URL) async throws {
        if let packageGate {
            try await packageGate(package, installedApp)
        } else {
            try await verifyOpenable(package, installedApp: installedApp)
        }
    }

    /// The gate: only a signed `.pkg`/`.mpkg` whose Team ID matches the installed
    /// app, that writes to the app being updated, and whose payload does not
    /// declare an OS floor above this Mac, may be handed to the system installer.
    /// Shared by the first open and every re-open. Fail-closed except for gate 6,
    /// which is best-effort and fails open — the header table says which is which,
    /// and it is the one list; do not restate it here.
    private nonisolated func verifyOpenable(_ toOpen: URL, installedApp: URL) async throws {
        // A `.pkg`/`.mpkg` runs install scripts (often with admin rights) the moment
        // the user confirms. The download's filename/extension is server-controlled
        // (`suggestedFilename`), so a hijacked or misconfigured endpoint could
        // resolve to something else — refuse it rather than open an arbitrary
        // downloaded file (which would sidestep the Developer-ID/Team-ID check
        // entirely). A `.dmg` is already resolved to its inner pkg by the caller.
        let ext = toOpen.pathExtension.lowercased()
        guard ext == "pkg" || ext == "mpkg" else {
            throw PackageError.noInstallablePackage
        }
        // `SecStaticCode…` blocks, so it hops; the `pkgutil` and `xar` below are
        // awaited. See `offCooperativePool`.
        guard let installedTeam = try await offCooperativePool({
            try SignatureVerifier.teamIdentifier(at: installedApp)
        }) else {
            throw SignatureVerifier.VerifyError.noTeamIdentifier(which: "installed")
        }
        let signature = await packageSignature(toOpen)
        guard signature.isValid else {
            throw PackageError.unsignedPackage
        }
        guard let packageTeam = signature.teamIdentifier else {
            throw PackageError.packageTeamIdentifierMissing
        }
        guard packageTeam == installedTeam else {
            throw PackageError.packageTeamIdentifierMismatch(
                installed: installedTeam,
                package: packageTeam)
        }

        // Team ID alone permits any app from the same vendor — the `.app` routes
        // pair it with a bundle-identifier check (`SignatureVerifier` Gate 4,
        // :181), but a `.pkg` has no single bundle identity to compare: it is a
        // container that may declare hundreds of bundles (Microsoft Word's
        // Distribution lists 206) or, like Tailscale's, not declare the app's own
        // identifier at all. Comparing identifiers was measured against real
        // vendor packages and rejects legitimate updates, so it is not the gate.
        //
        // What every package does declare is where it writes. Require that the app
        // being updated is one of those destinations, which is what stops a
        // same-Team substitution (Google Earth's package targets
        // `/Applications/Google Earth.app`, never Chrome's bundle).
        // Fail-closed: a package whose destinations cannot be read does not get
        // handed to the installer.
        //
        // This started out fail-open, on the reasoning that most pkg recipes were
        // untested and refusing an install that works today would be worse than
        // letting an unreadable one through. That reasoning does not survive
        // contact with what the gate is for: an attacker substituting a package
        // does not need to defeat the parser, only to hand us one it cannot read,
        // and "we could not check" is not a reason to install. Every pkg recipe in
        // the registry has since been checked against its real vendor package, so
        // the exemption has nothing left to protect.
        //
        // Checked against the real vendor package for all 16 pkg recipes, on
        // 2026-08-19: Word, Excel, PowerPoint, OneNote, Outlook, Teams, Edge, Edge
        // Beta, Edge Dev, OneDrive, Tailscale, WeChat DevTools, UU Remote, Shottr,
        // ToDesk and AweSun. Every one is a flat xar archive and every one declares
        // the app it updates, so there is no shape here this cannot read.
        //
        // ToDesk and AweSun took a second attempt worth recording: a plain `curl`
        // gets a bot-challenge page from both (ToDesk a "Security Verification"
        // page, AweSun an Aliyun WAF script), which looked like the one-click was
        // broken. It is not — `Downloader` gets the real 375 MB and 145 MB payloads
        // from the same URLs with the same declared headers. When checking a vendor
        // endpoint, reproduce the production client; curl is not a stand-in for it,
        // in either direction.
        //
        // A vendor that ships a shape this cannot read will fail closed and be
        // reported rather than silently downgraded to the Team-only check — which
        // is the outcome we want, because it is visible.
        //
        // Note what this gate does NOT cover: `preinstall`/`postinstall` scripts run
        // as root whatever the declared destinations say. It narrows which package
        // may be handed over; it does not make an accepted one harmless.
        //
        // Read ONCE, here: gate 6 below needs the same components (their
        // `install-location` and Bom), and re-deriving them would mean a second
        // `xar -tf` plus a second extraction of every `PackageInfo` and `Bom`.
        let components = await Self.readComponents(toOpen)
        let destinations = components.reduce(into: Set<String>()) {
            $0.formUnion($1.destinations)
        }
        guard !destinations.isEmpty else {
            throw PackageError.packageDestinationsUnreadable
        }

        let target = installedApp.resolvingSymlinksInPath().standardizedFileURL.path
        try Self.verifyDestination(target: target, destinations: destinations)

        // Gate 6, the last thing before the package is eligible to be handed over.
        // Ordered after the destination check on purpose: it extracts a payload,
        // which is the expensive part of this gate, and a package that is not even
        // for this app should be refused for that reason and without paying it.
        try await verifyPayloadSystemVersion(
            toOpen, components: components, installedApp: installedApp)
    }

    /// The package must write to the app being updated. Split out of
    /// `verifyOpenable` so its three accept/refuse paths are one expression the
    /// gate that follows cannot be skipped by — each of them used to `return`
    /// straight out of the gate, which is how a check appended after them would
    /// silently not run for two of the three.
    static func verifyDestination(
        target: String, destinations: Set<String>
    ) throws {
        guard !destinations.contains(target) else { return }

        // The same app kept somewhere other than `/Applications` is still the same
        // app. `AppScanner` also scans `~/Applications`, `/Applications/Utilities`
        // and the Input Methods directories, and a vendor package always names the
        // system location, so comparing full paths alone would refuse every pkg
        // update for an app the user keeps elsewhere. Fall back to the bundle name,
        // which is what actually distinguishes one product from another — Google
        // Earth's package names `Google Earth.app`, never `Google Chrome.app`.
        //
        // Only for an app that is NOT in `/Applications`, though. Allowing the name
        // to stand in for the path unconditionally would let a same-Team package
        // that installs a like-named app somewhere else entirely — say
        // `/Library/Application Support/Vendor/Foo.app` — satisfy the gate for
        // `/Applications/Foo.app`, which it never touches. Restricting the fallback
        // to the case it was added for keeps the non-standard location working
        // without opening that up.
        guard !target.hasPrefix("/Applications/") else {
            throw PackageError.packageDestinationMismatch(
                installed: target,
                destinations: destinations.sorted())
        }
        let targetName = (target as NSString).lastPathComponent
        let namesMatch = destinations.contains {
            ($0 as NSString).lastPathComponent.compare(
                targetName, options: .caseInsensitive) == .orderedSame
        }
        guard !namesMatch else { return }

        throw PackageError.packageDestinationMismatch(
            installed: target,
            destinations: destinations.sorted())
    }

    // MARK: Gate 6 on the pkg route

    /// Refuse a package whose payload app declares an OS floor above this Mac.
    ///
    /// The comparison is `SignatureVerifier.canRun(minimumSystemVersion:on:)` and
    /// the value read is `LSMinimumSystemVersion` — the same rule, from the same
    /// source, as gate 6 on the `.app` routes. Never a second implementation: a
    /// detection-time and an install-time gate that disagree by a patch component
    /// produce an update offered forever that fails at the last step every time
    /// (see `HostOS` and `RowActionState`).
    ///
    /// **This gate is best-effort, and that is not a detail.** It fails OPEN on
    /// every shape it cannot read, and the shapes are enumerated in
    /// `PayloadFloor` below: a `pbzx`-compressed payload, a payload member that
    /// is not a readable plist, a package whose Bom never names this app's
    /// `Info.plist`, a package whose metadata could not be read at all. Each is
    /// logged with WHICH of those it was, because "no floor" covering four
    /// different situations is how a gate quietly stops firing.
    ///
    /// Failing open matches gate 6's own posture (`canRun` returns true for a nil
    /// floor) and it is the only honest default: this gate exists to catch a
    /// package we can PROVE is wrong for the machine, and a pkg route that
    /// started refusing whatever it could not parse would break installs that
    /// work today. So "the pkg route checks the OS floor" means "it refuses the
    /// packages it can read a floor out of", never "a pkg that needs a newer
    /// macOS can no longer reach the installer".
    nonisolated func verifyPayloadSystemVersion(
        _ pkg: URL, components: [Component], installedApp: URL
    ) async throws {
        let appName = installedApp.deletingPathExtension().lastPathComponent
        let outcome = await Self.payloadMinimumSystemVersion(
            pkg, components: components, appName: appName)
        guard !SignatureVerifier.canRun(
            minimumSystemVersion: outcome.declared, on: osVersion) else {
            if outcome.declared == nil {
                // The `.app` route logs the same sentence, but there it can only
                // ever mean `noKey` — it is holding the bundle. Here the reason
                // is the useful half.
                Log.install.info("""
                    gate 6 (pkg) no floor read from \
                    \(pkg.lastPathComponent, privacy: .public) \
                    (\(outcome.reason, privacy: .public)) — allowing
                    """)
            }
            return
        }
        // Non-nil here: `canRun` calls a nil floor runnable by definition.
        throw PackageError.packageRequiresNewerSystem(
            required: outcome.declared ?? "?", host: osVersion)
    }

    /// What gate 6 got out of a package's payload, and when it got nothing, which
    /// of the fail-open shapes it was.
    ///
    /// A single `String?` collapsed four different situations into one, and the
    /// log line then said the same thing for "this app declares no floor" (the
    /// normal case for 3 of the 143 bundles measured for gate 6) as for "this
    /// gate never found the plist" (a silent loss of coverage). They are not the
    /// same event and only one of them is expected.
    enum PayloadFloor: Sendable, Equatable {
        /// The payload's plist declares this floor.
        case floor(String)
        /// The plist was read and declares no macOS floor — or declares an iOS
        /// one, which `SignatureVerifier` refuses to compare against macOS.
        case noKey
        /// The member came out of the payload but is not a plist we could parse.
        case unparsedPlist
        /// No component's payload could be read, or the one holding this app
        /// could not be extracted — a `pbzx` payload lands here.
        case unreadablePayload
        /// No component names this app's `Info.plist` at all.
        case noMember
        /// The package's own metadata could not be read.
        case noComponents

        var declared: String? {
            if case .floor(let value) = self { return value }
            return nil
        }

        var reason: String {
            switch self {
            case .floor(let value): return "floor \(value)"
            case .noKey: return "no LSMinimumSystemVersion in the payload's plist"
            case .unparsedPlist: return "the payload's plist did not parse"
            case .unreadablePayload: return "the payload could not be read"
            case .noMember: return "no Info.plist for this app in the payload"
            case .noComponents: return "the package metadata could not be read"
            }
        }
    }

    /// What `appName`'s payload plist says about the OS floor.
    ///
    /// **Which component's payload is opened is decided from metadata already
    /// read, not by unpacking anything.** `readComponents` has the Bom — the
    /// actual list of paths each component writes — so the component holding
    /// this app's `Info.plist`, and the member name inside it, are both known
    /// before a single byte of payload is touched. Exactly one `Payload` is
    /// extracted, and only when a component claims to hold the plist. The first
    /// version scanned every component and ran `tar -tf` on each to find out,
    /// which meant a package whose plist declared no floor — the ordinary
    /// fail-open case — unpacked every remaining component, twice, since
    /// `handOver` runs this gate before and after `beforeOpen`.
    ///
    /// The route the header rejects for the architecture gate — `pkgutil
    /// --expand-full`, or anything else that unpacks the payload to disk — is
    /// rejected here for the same reason, and the measurements are this file's
    /// own, taken on the real 66 MB UU Remote 4.35.0 package on 2026-09-15:
    /// `--expand-full` took 0.53 s and left **154 MB** on disk. What runs instead
    /// costs the extracted `Payload` member and nothing more: `xar -xf` copies it
    /// out as stored (0.10 s, 66 MB — the member is already compressed, so `xar`
    /// does not recompress), then one `tar -xOf` reads the cpio archive *through*
    /// its decompressor without ever writing the expansion down (0.20 s). The
    /// member is removed before this returns.
    ///
    /// **Streaming and stopping early would buy nothing, which is worth knowing
    /// before optimising this.** Measured on that same package: the app's
    /// `Info.plist` is entry **189 of 190**, at byte 160,919,634 of the
    /// 160,923,136-byte decompressed stream — 99.998% of the way in. A cpio
    /// payload has no index; the plist is wherever the archiver put it, and here
    /// that is the end.
    ///
    /// `tar` is `/usr/bin/tar`, i.e. libarchive, which sniffs both the container
    /// and the compression. Both packages read for this change — that vendor one
    /// and `pkgbuild`'s output — ship a gzip'd `odc` cpio. **Not measured: a
    /// `pbzx`-wrapped payload**, which Apple's own installers use and which
    /// libarchive does not decode. No package with a pbzx payload was available
    /// on this machine to test against, and none was downloaded for this change.
    /// Such a payload lands on `.unreadablePayload`, i.e. installs exactly as it
    /// does today.
    ///
    /// `scratchRoot` is a parameter for the same reason `osVersion` is: a test
    /// asserting that this leaves nothing behind must be able to look at a
    /// directory only its own call writes to. Reading the shared temp directory
    /// instead measures whatever else happens to be running — which is not a
    /// theoretical objection, it is how the first version of that test passed on
    /// a 14-core machine and failed on a 3-core runner, where sibling tests in
    /// the same suite were still holding their own scratch when it looked.
    static func payloadMinimumSystemVersion(
        _ pkg: URL,
        components: [Component],
        appName: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
    ) async -> PayloadFloor {
        guard !components.isEmpty else { return .noComponents }

        // Every component that claims this app's plist, in package order. More
        // than one is possible in principle; the first is taken and the rest are
        // a known limitation rather than a merge.
        var candidate: (component: Component, member: String)?
        for component in components {
            if let member = Self.plistMember(
                inPayloadListing: component.payloadPaths,
                appName: appName,
                installLocation: component.installLocation) {
                candidate = (component, member)
                break
            }
        }
        guard let candidate else { return .noMember }

        // Named so `sweepStaleWorkDirectories` reclaims it: this directory holds a
        // whole `Payload` (69 MB for that vendor package, hundreds for ToDesk),
        // and a crash between the extraction and the removal below would
        // otherwise leak it forever — nothing else sweeps the temp directory.
        let scratch = scratchRoot
            .appendingPathComponent(
                "\(Self.osFloorScratchPrefix)\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true)) != nil
        else { return .unreadablePayload }

        // One exit, so the scratch removal cannot be skipped. `defer` is what this
        // would be, but `defer` cannot `await` and these removals must run off the
        // cooperative pool.
        let outcome = await Self.readFloor(
            pkg, candidate: candidate, into: scratch)
        await removeItemOffCooperativePool(at: scratch)
        return outcome
    }

    /// Convenience for callers that have no components in hand (tests, and any
    /// future caller outside `verifyOpenable`). Production goes through
    /// `verifyOpenable`, which already read them.
    static func payloadMinimumSystemVersion(
        _ pkg: URL,
        appName: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory
    ) async -> PayloadFloor {
        await payloadMinimumSystemVersion(
            pkg, components: await readComponents(pkg),
            appName: appName, scratchRoot: scratchRoot)
    }

    private static func readFloor(
        _ pkg: URL, candidate: (component: Component, member: String), into scratch: URL
    ) async -> PayloadFloor {
        let name = candidate.component.payloadMember
        guard let payload = Self.scratchMember(named: name, under: scratch) else {
            return .unreadablePayload
        }
        guard await Self.runCapturing(
            "/usr/bin/xar", ["-xf", pkg.path, name], cwd: scratch).code == 0
        else { return .unreadablePayload }

        let body = await Self.runCapturingBytes(
            "/usr/bin/tar", ["-xOf", payload.path, candidate.member])
        // A `Payload` runs to hundreds of megabytes, so its removal is off the
        // cooperative pool, and it happens here rather than being left to the
        // scratch removal so the two are independent.
        await removeItemOffCooperativePool(at: payload)

        guard body.code == 0 else { return .unreadablePayload }
        guard let declared = SignatureVerifier.declaredMinimumSystemVersion(
            inInfoPlist: body.output)
        else {
            // Told apart because they are different events: a plist that parses
            // and simply has no macOS floor is ordinary, one that does not parse
            // means this gate read the wrong bytes.
            return SignatureVerifier.infoPlistParses(body.output) ? .noKey : .unparsedPlist
        }
        return .floor(declared)
    }

    /// Deliberately inside `sweepStaleWorkDirectories`'s `DuoUpdater-pkg-`
    /// namespace: this directory holds a whole `Payload`, and a crash between the
    /// extraction and the removal would otherwise leave it in the temp directory
    /// with nothing on this machine that reclaims it.
    static let osFloorScratchPrefix = "DuoUpdater-pkg-osfloor-"

    /// Where `xar` will put the member called `name`, or nil if that is not
    /// inside `scratch`.
    ///
    /// The member NAME comes out of the package, and the caller deletes the file
    /// it resolves to — so a name containing `..` would let a package choose what
    /// gets removed. `declaredDestinations` extracts by name too and needs no
    /// such guard, because it only ever removes the whole scratch directory; do
    /// not read its shape as saying this one is unnecessary.
    static func scratchMember(named name: String, under scratch: URL) -> URL? {
        let member = scratch.appendingPathComponent(name).standardizedFileURL
        let base = scratch.standardizedFileURL.path
        guard member.path.hasPrefix(base + "/") else { return nil }
        return member
    }

    /// Pick the payload path holding `appName`'s own `Info.plist` out of one
    /// component's paths, which are relative to its `install-location`.
    ///
    /// **The join with `install-location` is the whole point, not tidiness.** A
    /// payload's own paths do not identify the bundle on their own, because the
    /// two real shapes spell it differently:
    ///
    /// - payload root is `/`, so the path is `./Applications/Foo.app/Contents/Info.plist`;
    /// - payload root IS the bundle, so the path is just `./Contents/Info.plist`
    ///   and `install-location` carries the `Foo.app` — the shape Tailscale's
    ///   package has, one of the pkg recipes in the registry, and confirmed here
    ///   against `pkgbuild --install-location "/Applications/ZZFixture.app"`.
    ///
    /// Matching the payload path alone finds the first and can NEVER match the
    /// second, and because this gate fails open the miss is silent. Joining first
    /// makes both one rule: the absolute path must end in
    /// `/<appName>.app/Contents/Info.plist`.
    ///
    /// Case-insensitive, to agree with `verifyDestination`'s name fallback, which
    /// is case-insensitive because the filesystem is and vendors are inconsistent
    /// — two comparisons of the same bundle name that disagreed about case would
    /// let a package pass the destination gate and then silently skip this one.
    ///
    /// `._Info.plist` is an AppleDouble sidecar carrying another file's extended
    /// attributes — `pkgbuild` emits one beside every file, and a real vendor
    /// payload carries them too — and it is not a plist. It does not end in
    /// `/Info.plist`, so this excludes it; stated because the same sidecars
    /// already needed handling in `appBundlePrefixes` and a looser match here
    /// would read one and get `.unparsedPlist`.
    ///
    /// A nested bundle with the SAME name as the app (`…/Foo.app/…/Foo.app`)
    /// would satisfy this too, and package order decides which wins. Known
    /// limitation: no package in the registry has that shape, and the cost of
    /// getting it wrong is a wrong floor rather than a wrong app — the
    /// destination gate has already established which app this package updates.
    static func plistMember(
        inPayloadListing paths: [String], appName: String, installLocation: String
    ) -> String? {
        let needle = "/\(appName).app/Contents/Info.plist".lowercased()
        return paths.first { path in
            let joined = (installLocation as NSString).appendingPathComponent(path)
            return (joined as NSString).standardizingPath.lowercased().hasSuffix(needle)
        }
    }

    /// The `.app` destinations a package declares, as absolute paths.
    ///
    /// A flat component package carries one `PackageInfo`; a product archive
    /// carries a `Distribution` plus one `PackageInfo` per nested component. Both
    /// spell the destination the same way: `install-location` is the payload root,
    /// and each `<bundle path=…>` is relative to it. Tailscale's package sets
    /// `install-location` to the app bundle itself and lists only the bundles
    /// *inside* it, so the root counts as a destination in its own right.
    static func declaredDestinations(_ pkg: URL) async -> Set<String> {
        await readComponents(pkg).reduce(into: Set<String>()) {
            $0.formUnion($1.destinations)
        }
    }

    /// One component of a package: a flat package has exactly one, a product
    /// archive one per nested `*.pkg` directory.
    ///
    /// Read once and passed down, because the same three answers feed two gates —
    /// the destination check wants `destinations`, gate 6 wants
    /// `installLocation` + `payloadPaths` to find the app's plist without
    /// unpacking anything.
    struct Component: Sendable, Equatable {
        /// The member-name prefix inside the package: `""` for a flat package,
        /// `"Foo.pkg"` for a component of a product archive.
        let directory: String
        /// The payload root this component unpacks into, defaulting to `/`.
        let installLocation: String
        /// Payload-relative paths from this component's Bom — the actual list of
        /// files the installer will write. Empty when the Bom was unreadable.
        let payloadPaths: [String]
        /// Absolute `.app` destinations this component declares.
        let destinations: Set<String>

        /// The `Payload` member's name inside the package.
        var payloadMember: String {
            directory.isEmpty ? "Payload" : directory + "/Payload"
        }
    }

    static func readComponents(_ pkg: URL) async -> [Component] {
        let listing = await Self.runCapturing("/usr/bin/xar", ["-tf", pkg.path])
        guard listing.code == 0 else { return [] }
        let infos = listing.output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0 == "PackageInfo" || $0.hasSuffix("/PackageInfo") }
        guard !infos.isEmpty else { return [] }

        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("duo-pkg-dest-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil
        else { return [] }
        // Synchronous on purpose, unlike the bundle-sized removals elsewhere: the
        // scratch holds only the `PackageInfo` and `Bom` members `xar` extracted
        // below, never the payload.
        defer { try? fm.removeItem(at: scratch) }

        var out: [Component] = []
        for name in infos {
            guard await Self.runCapturing(
                "/usr/bin/xar", ["-xf", pkg.path, name], cwd: scratch).code == 0,
                let body = try? String(
                    contentsOf: scratch.appendingPathComponent(name), encoding: .utf8)
            else { continue }
            let directory = (name as NSString).deletingLastPathComponent
            let installLocation = Self.installLocation(inPackageInfo: body)
            var destinations = Self.destinations(inPackageInfo: body)

            // The `<bundle>` elements are a vendor's *description* of the payload.
            // The Bom beside them is the payload: the actual list of paths the
            // installer will write. Reading both means a package that declares no
            // bundles — which the XML path yields nothing for, and which now fails
            // closed — is still understood, and it removes the dependence on each
            // vendor's XML habits.
            let bom = directory.isEmpty ? "Bom" : directory + "/Bom"
            var payloadPaths: [String] = []
            if await Self.runCapturing(
                "/usr/bin/xar", ["-xf", pkg.path, bom], cwd: scratch).code == 0 {
                let bomListing = await Self.runCapturing(
                    "/usr/bin/lsbom", ["-s", scratch.appendingPathComponent(bom).path])
                if bomListing.code == 0 {
                    payloadPaths = bomListing.output.split(separator: "\n").map(String.init)
                    destinations.formUnion(Self.destinations(
                        inBomListing: bomListing.output, installLocation: installLocation))
                }
            }
            out.append(Component(
                directory: directory,
                installLocation: installLocation,
                payloadPaths: payloadPaths,
                destinations: destinations))
        }
        return out
    }

    /// Absolute `.app` destinations from one component's Bom listing.
    ///
    /// `lsbom -s` prints one payload path per line, relative to the component's
    /// `install-location`. Only the lines that name an app bundle matter, and a
    /// Bom lists every file inside one, so this keeps the bundle and discards its
    /// contents rather than emitting thousands of paths.
    static func destinations(
        inBomListing listing: String, installLocation: String
    ) -> Set<String> {
        var out: Set<String> = []
        for line in listing.split(separator: "\n") {
            let path = String(line)
            guard path.lowercased().contains(".app") else { continue }
            let joined = (installLocation as NSString).appendingPathComponent(path)
            out.formUnion(appBundlePrefixes(in: (joined as NSString).standardizingPath))
        }
        return out
    }

    /// The payload root a component unpacks into, defaulting to `/`.
    static func installLocation(inPackageInfo body: String) -> String {
        guard let doc = try? XMLDocument(xmlString: body, options: [.nodePreserveWhitespace]),
              let value = (try? doc.nodes(forXPath: "/pkg-info/@install-location"))?
                .first?.stringValue
        else { return "/" }
        return value.isEmpty ? "/" : value
    }

    /// Parse one `PackageInfo` body into absolute `.app` destinations. Split out so
    /// the path arithmetic is testable without building a package.
    ///
    /// Parsed as XML rather than scanned with regexes: an attribute pattern also
    /// matches `search-path`, does not decode `&amp;` in an app name, and happily
    /// reads a destination out of a commented-out element. None of those is a
    /// signature bypass — `PackageInfo` is covered by the package signature, which
    /// `pkgutil --check-signature` has already verified by this point — but each
    /// one is a way to refuse a legitimate update.
    static func destinations(inPackageInfo body: String) -> Set<String> {
        guard let doc = try? XMLDocument(xmlString: body, options: [.nodePreserveWhitespace])
        else { return [] }

        let location = (try? doc.nodes(forXPath: "/pkg-info/@install-location"))?
            .first?.stringValue ?? "/"
        var out: Set<String> = []
        // The payload root itself, when the package unpacks straight into a bundle.
        if isAppBundlePath(location) {
            out.insert((location as NSString).standardizingPath)
        }
        for node in (try? doc.nodes(forXPath: "//bundle/@path")) ?? [] {
            guard let path = node.stringValue else { continue }
            let joined = (location as NSString).appendingPathComponent(path)
            out.formUnion(appBundlePrefixes(in: (joined as NSString).standardizingPath))
        }
        return out
    }

    /// Every prefix of `path` that ends in an app bundle.
    ///
    /// Neither the first nor the last `.app` component is reliably the one that
    /// matters. Taking the first truncates on a reverse-DNS directory such as
    /// `com.vendor.app`, throwing away the real bundle further along — and because
    /// the truncated prefix still ends in `.app` the result is non-empty but wrong,
    /// which sails past the "could not read the layout" fallback and refuses a
    /// legitimate update. Taking the last picks a helper out of a package whose
    /// payload root is the app itself, as Tailscale's is.
    ///
    /// Returning every candidate keeps the real destination in the set whichever
    /// shape the package has. The extra entries are all paths the package genuinely
    /// writes, and none of them can make a different product match: the comparison
    /// is against the installed bundle's own path and name, so Google Earth's
    /// package still never resolves to Chrome.
    static func appBundlePrefixes(in path: String) -> Set<String> {
        var out: Set<String> = []
        var walked: [String] = []
        for component in (path as NSString).pathComponents {
            walked.append(component)
            // `._Foo.app` is an AppleDouble sidecar carrying another file's
            // extended attributes, not a bundle. Reading the Bom surfaces them
            // because they are genuinely in the payload — Shottr's package ships
            // one next to the app — and treating them as destinations puts paths
            // in a refusal message that no app was ever installed at.
            guard !component.hasPrefix("._") else { continue }
            if isAppBundlePath(component) {
                out.insert(NSString.path(withComponents: walked))
            }
        }
        return out
    }

    /// Case-insensitive because the filesystem is, and vendors are inconsistent.
    private static func isAppBundlePath(_ component: String) -> Bool {
        component.lowercased().hasSuffix(".app")
    }

    /// `runCapturingOutput`, but usable from the static helpers above and able to
    /// run in a working directory (`xar -xf` extracts relative to cwd). stdout and
    /// stderr share one pipe, as they did.
    ///
    /// `.runToCompletion`, like every child on this route, including the reads:
    /// these answers feed a fail-closed gate, and a `xar` killed by a cancellation
    /// would come back as "the package declares nothing" rather than as a
    /// cancellation. They are short; there is nothing to save by killing them.
    private static func runCapturing(
        _ launchPath: String, _ args: [String], cwd: URL? = nil
    ) async -> (code: Int32, output: String) {
        guard let outcome = try? await ChildProcess.run(
            launchPath, args, workingDirectory: cwd,
            standardError: .mergeIntoOutput, onCancel: .runToCompletion)
        else { return (-1, "") }
        return (outcome.terminationStatus, String(decoding: outcome.standardOutput, as: UTF8.self))
    }

    /// `runCapturing`, but the bytes as they came.
    ///
    /// Two differences from it, both load-bearing for reading a plist out of a
    /// payload: the output is not decoded as UTF-8 (a bundle's `Info.plist` is
    /// often a *binary* plist, which that decoding would replacement-char its
    /// way through — UU Remote's happens to be XML, so "binary" is what this must
    /// survive, not what it will always get), and standard error is discarded rather than merged into the
    /// output (a warning from `tar` merged into the stream would corrupt the
    /// plist it is meant to be returning). `.runToCompletion` for the same reason
    /// as every other child here: a killed read reports "no floor declared",
    /// which is this gate's fail-open answer.
    private static func runCapturingBytes(
        _ launchPath: String, _ args: [String], cwd: URL? = nil
    ) async -> (code: Int32, output: Data) {
        guard let outcome = try? await ChildProcess.run(
            launchPath, args, workingDirectory: cwd,
            standardError: .discard, onCancel: .runToCompletion)
        else { return (-1, Data()) }
        return (outcome.terminationStatus, outcome.standardOutput)
    }

    /// Given a downloaded file, return the thing to hand to the system installer.
    /// For a `.dmg` we mount it, copy the contained `.pkg` out (so the installer
    /// keeps working after we unmount), and return that; otherwise we open the
    /// file itself (a bare `.pkg`, or the `.dmg`/folder as a fallback).
    private nonisolated func resolveInstaller(from file: URL, workDir: URL, installedApp: URL) async throws -> URL {
        guard file.pathExtension.lowercased() == "dmg" else { return file }

        let mountPoint = workDir.appendingPathComponent("mnt")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = await run("/usr/bin/hdiutil", [
            "attach", file.path, "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mountPoint.path
        ])
        guard attach == 0 else { throw PackageError.noInstallablePackage }
        // Detached on every path out, as the `defer` that used to sit here did —
        // spelled out because a `defer` cannot await.
        let copied: Result<URL, Error>
        do {
            copied = .success(try await copyPackage(
                outOf: mountPoint, into: workDir, installedApp: installedApp))
        } catch {
            copied = .failure(error)
        }
        _ = await run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
        return try copied.get()
    }

    private nonisolated func copyPackage(
        outOf mountPoint: URL, into workDir: URL, installedApp: URL
    ) async throws -> URL {
        // Pass the installed app's name so a multi-pkg image is matched to *this*
        // product (see `preferredPackage`).
        let appName = installedApp.deletingPathExtension().lastPathComponent
        guard let pkg = Self.preferredPackage(in: mountPoint, preferring: appName) else {
            throw PackageError.noInstallablePackage
        }
        let dest = workDir.appendingPathComponent(pkg.lastPathComponent)
        // A leftover here can be a flat package of hundreds of megabytes or a
        // bundle-format one, so its removal is off the pool.
        await removeItemOffCooperativePool(at: dest)
        guard await run("/usr/bin/ditto", [pkg.path, dest.path]) == 0 else {
            throw PackageError.downloadFailed("Could not copy the installer package out of the disk image.")
        }
        return dest
    }

    static func workDirectory(forInstalledApp installedApp: URL) -> URL {
        let appName = installedApp.deletingPathExtension().lastPathComponent
        let safeName = safePathComponent(appName.isEmpty ? "app" : appName)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoUpdater-pkg-\(safeName)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Best-effort removal of leftover package scratch dirs from earlier installs.
    /// Because each `downloadAndOpen` keeps its own UUID dir alive for the system
    /// Installer, they would otherwise pile up across installs. We only drop dirs
    /// untouched for a full day — long after any Installer window has finished
    /// reading the package — so an in-flight or recent install is never disturbed.
    static func sweepStaleWorkDirectories() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries where entry.lastPathComponent.hasPrefix("DuoUpdater-pkg-") {
            let modified = (try? entry.resourceValues(
                forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    /// Drop the scratch directory holding `package`, ahead of the 24-hour sweep.
    ///
    /// Only for a package nothing is reading any more — the caller must have
    /// confirmed the Installer window for it is closed (`InstallerWindowCloser`).
    /// Pulling the file out from under an open Installer window breaks the install
    /// in progress, so this is deliberately not called on a best-effort basis.
    ///
    /// Refuses anything that isn't one of our own `DuoUpdater-pkg-…` directories
    /// under the temp directory: the path travels through preferences, and a
    /// recursive delete driven by persisted state gets a hard shape check.
    @discardableResult
    public static func discardWorkDirectory(containing package: URL) -> Bool {
        let fm = FileManager.default
        let dir = package.deletingLastPathComponent().standardizedFileURL
        guard dir.lastPathComponent.hasPrefix("DuoUpdater-pkg-") else { return false }
        let tempBase = fm.temporaryDirectory.resolvingSymlinksInPath()
            .standardizedFileURL.path
        let parent = dir.deletingLastPathComponent().resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard parent == tempBase else { return false }
        do {
            try fm.removeItem(at: dir)
            return true
        } catch {
            return false
        }
    }

    private static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return collapsed.isEmpty ? "app" : collapsed
    }

    /// `pkgutil --check-signature` validates the package chain and prints the
    /// Developer ID Installer certificate, whose parenthesized OU is the Team ID.
    private nonisolated func packageSignature(_ pkg: URL) async -> (isValid: Bool, teamIdentifier: String?) {
        let result = await runCapturingOutput("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
        guard result.code == 0 else { return (false, nil) }
        return (true, Self.packageTeamIdentifier(fromPkgutilOutput: result.output))
    }

    /// Pick a package only when the answer is unambiguous. A single package needs
    /// no naming convention. On a multi-package image, accept an exact product name
    /// or a unique product name followed by a numeric version (`Foo-2.0.pkg`); never
    /// let a substring such as `FooHelper.pkg` stand in for `Foo.app`, and never
    /// fall back to whichever unrelated package sorts first.
    static func preferredPackage(in dir: URL, preferring appName: String) -> URL? {
        let fm = FileManager.default
        let dirBase = dir.resolvingSymlinksInPath().standardizedFileURL.path
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let valid = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { Self.isPackageEntry($0, insideResolvedPath: dirBase) }
        guard valid.count > 1 else { return valid.first }

        func normalized(_ value: String) -> String {
            value.lowercased().unicodeScalars
                .filter(CharacterSet.alphanumerics.contains)
                .map(String.init).joined()
        }

        let needle = normalized(appName)
        guard !needle.isEmpty else { return nil }
        let names = valid.map { ($0, normalized($0.deletingPathExtension().lastPathComponent)) }

        let exact = names.filter { $0.1 == needle }
        if exact.count == 1 { return exact[0].0 }
        if exact.count > 1 { return nil }

        // Preserve separators for version matching. Requiring a boundary before
        // the version and consuming the *entire* suffix prevents sibling products
        // such as Foo360, Foo2Helper, and Foov2Agent from winning this gate.
        let appTokens = appName.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.map(NSRegularExpression.escapedPattern(for:))
        guard !appTokens.isEmpty else { return nil }
        let productPattern = appTokens.joined(separator: #"[\s._-]*"#)
        // Suffixes are a closed vocabulary: enough for common prerelease and
        // architecture-qualified installers without reopening the old
        // "anything after a leading digit" ambiguity.
        let qualifier = #"(?:alpha\d*|beta\d*|rc\d*|preview\d*|arm64|aarch64|x86_64|universal)"#
        let versionPattern = #"^"# + productPattern
            + #"[\s._-]+v?\d+(?:[._-]\d+)*(?:a\d+|b\d+|rc\d+)?(?:[\s._-]+"#
            + qualifier + #")*$"#
        let versioned = valid.filter { package in
            let base = package.deletingPathExtension().lastPathComponent
            return base.range(of: versionPattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return versioned.count == 1 ? versioned[0] : nil
    }

    static func isPackageEntry(_ url: URL, insideResolvedPath dirBase: String) -> Bool {
        guard ["pkg", "mpkg"].contains(url.pathExtension.lowercased()) else {
            return false
        }
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if vals?.isSymbolicLink == true { return false }
        guard vals?.isDirectory == true || vals?.isRegularFile == true else { return false }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == dirBase || resolved.hasPrefix(dirBase + "/")
    }

    /// Exit status only; both streams are drained and dropped. Not killed on
    /// cancellation — see `runCapturing` (and a mount left behind by a killed
    /// `hdiutil detach` is exactly the leak this route must not have).
    @discardableResult
    private nonisolated func run(_ launchPath: String, _ args: [String]) async -> Int32 {
        guard let outcome = try? await ChildProcess.run(
            launchPath, args,
            standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion)
        else { return -1 }
        return outcome.terminationStatus
    }

    @discardableResult
    private nonisolated func runCapturingOutput(_ launchPath: String, _ args: [String]) async -> (code: Int32, output: String) {
        await Self.runCapturing(launchPath, args)
    }

    static func packageTeamIdentifier(fromPkgutilOutput output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard line.range(of: "Developer ID Installer:", options: .caseInsensitive) != nil,
                  let open = line.lastIndex(of: "("),
                  let close = line[open...].firstIndex(of: ")") else {
                continue
            }
            let team = line[line.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil {
                return team
            }
        }
        return nil
    }
}
