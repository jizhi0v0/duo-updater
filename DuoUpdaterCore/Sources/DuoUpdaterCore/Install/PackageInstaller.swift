import Foundation
import AppKit
import CryptoKit
import Darwin

/// Handles updates that ship as an installer package (`pkg` casks like AweSun,
/// Tailscale). We can't swap those in place, and a non-interactive `brew` can't
/// elevate to run the installer — so we download the official package (the same
/// URL Homebrew would use) and hand it to macOS's own installer, which prompts
/// for admin itself. The user confirms the install in a trusted, native UI.
public actor PackageInstaller {

    /// The final hand-over keeps its integrity check and `NSWorkspace.open` in one
    /// MainActor turn. Injectable so tests can observe it without a live Installer.
    private let handOff: @Sendable (
        URL, @Sendable () throws -> Void
    ) async throws -> Void
    /// Test seam for the package gate. Production always uses `verifyOpenable`;
    /// tests can substitute a deterministic byte-level gate.
    private let packageGate: (@Sendable (URL, URL) throws -> Void)?

    public init() {
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
    }

    init(
        opener: @escaping @Sendable (URL) async -> Void,
        packageGate: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        self.handOff = { url, finalIntegrityCheck in
            try finalIntegrityCheck()
            await opener(url)
        }
        self.packageGate = packageGate
    }

    public enum PackageError: LocalizedError {
        case noURL
        case downloadFailed(String)
        case unsignedPackage
        case noInstallablePackage
        case packageTeamIdentifierMissing
        case packageTeamIdentifierMismatch(installed: String, package: String)
        case packageDestinationMismatch(installed: String, destinations: [String])

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
            case .packageDestinationMismatch(let installed, let destinations):
                return "This package installs to \(destinations.joined(separator: ", ")), not to \(installed). Refusing to install."
            case .packageTeamIdentifierMismatch(let installed, let package):
                return "Installer Team Identifier mismatch: installed “\(installed)” vs package “\(package)”. Refusing to open it."
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
        // signature + Team-ID gate in `handOver` below.
        let sourceFingerprint = try verifyDownload(file)
        // A signed DMG is about to be parsed into a different inner file, so prove
        // the pathname still holds the exact enclosure whose EdDSA check passed.
        // A direct pkg carries this proof into `handOver` instead, avoiding an
        // extra full read of a potentially hundreds-of-megabytes package.
        if file.pathExtension.lowercased() == "dmg", let sourceFingerprint,
           try Self.contentFingerprint(of: file) != sourceFingerprint {
            throw PackageError.downloadFailed(
                "The download changed after source verification. Nothing was opened.")
        }

        onStage(.installing)
        let toOpen = try resolveInstaller(from: file, workDir: workDir, installedApp: installedApp)
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
    /// Re-runs the full signature/Team-ID gate rather than trusting the earlier
    /// pass: the file has been sitting in a world-readable temp directory since
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
        try applyPackageGate(toOpen, installedApp: installedApp)
        let preliminarySeal = try Self.contentSeal(of: toOpen)
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
        try applyPackageGate(toOpen, installedApp: installedApp)
        let finalSeal = try Self.contentSeal(of: toOpen)
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

    private func applyPackageGate(_ package: URL, installedApp: URL) throws {
        if let packageGate {
            try packageGate(package, installedApp)
        } else {
            try verifyOpenable(package, installedApp: installedApp)
        }
    }

    /// The fail-closed gate: only a signed `.pkg`/`.mpkg` whose Team ID matches the
    /// installed app may be handed to the system installer. Shared by the first
    /// open and every re-open.
    private func verifyOpenable(_ toOpen: URL, installedApp: URL) throws {
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
        guard let installedTeam = try SignatureVerifier.teamIdentifier(at: installedApp) else {
            throw SignatureVerifier.VerifyError.noTeamIdentifier(which: "installed")
        }
        let signature = packageSignature(toOpen)
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
        // An empty set means the package's layout could not be read — a bundle-format
        // `.mpkg` is not a xar archive at all, and a component may be missing or
        // unreadable — not that the package writes nowhere. Verified non-empty on
        // Tailscale, Microsoft Word, Edge, OneDrive, WeChat DevTools and UU Remote,
        // covering all three package shapes, but the remaining pkg recipes are
        // untested, so an unreadable layout falls back to the Team-only gate rather
        // than blocking an install that works today.
        //
        // Note what this gate does NOT cover: `preinstall`/`postinstall` scripts run
        // as root whatever the declared destinations say. It narrows which package
        // may be handed over; it does not make an accepted one harmless.
        let destinations = Self.declaredDestinations(toOpen)
        guard !destinations.isEmpty else { return }

        let target = installedApp.resolvingSymlinksInPath().standardizedFileURL.path
        guard !destinations.contains(target) else { return }

        // The same app kept somewhere other than `/Applications` is still the same
        // app. `AppScanner` also scans `~/Applications`, `/Applications/Utilities`
        // and the Input Methods directories, and a vendor package always names the
        // system location, so comparing full paths alone would refuse every pkg
        // update for an app the user keeps elsewhere. Fall back to the bundle name,
        // which is what actually distinguishes one product from another — Google
        // Earth's package names `Google Earth.app`, never `Google Chrome.app`.
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

    /// The `.app` destinations a package declares, as absolute paths.
    ///
    /// A flat component package carries one `PackageInfo`; a product archive
    /// carries a `Distribution` plus one `PackageInfo` per nested component. Both
    /// spell the destination the same way: `install-location` is the payload root,
    /// and each `<bundle path=…>` is relative to it. Tailscale's package sets
    /// `install-location` to the app bundle itself and lists only the bundles
    /// *inside* it, so the root counts as a destination in its own right.
    static func declaredDestinations(_ pkg: URL) -> Set<String> {
        let listing = Self.runCapturing("/usr/bin/xar", ["-tf", pkg.path])
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
        defer { try? fm.removeItem(at: scratch) }

        var out: Set<String> = []
        for name in infos {
            guard Self.runCapturing(
                "/usr/bin/xar", ["-xf", pkg.path, name], cwd: scratch).code == 0,
                let body = try? String(
                    contentsOf: scratch.appendingPathComponent(name), encoding: .utf8)
            else { continue }
            out.formUnion(Self.destinations(inPackageInfo: body))
        }
        return out
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
    /// run in a working directory (`xar -xf` extracts relative to cwd).
    private static func runCapturing(
        _ launchPath: String, _ args: [String], cwd: URL? = nil
    ) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Given a downloaded file, return the thing to hand to the system installer.
    /// For a `.dmg` we mount it, copy the contained `.pkg` out (so the installer
    /// keeps working after we unmount), and return that; otherwise we open the
    /// file itself (a bare `.pkg`, or the `.dmg`/folder as a fallback).
    private func resolveInstaller(from file: URL, workDir: URL, installedApp: URL) throws -> URL {
        guard file.pathExtension.lowercased() == "dmg" else { return file }

        let mountPoint = workDir.appendingPathComponent("mnt")
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = run("/usr/bin/hdiutil", [
            "attach", file.path, "-nobrowse", "-readonly", "-noverify",
            "-mountpoint", mountPoint.path
        ])
        guard attach == 0 else { throw PackageError.noInstallablePackage }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"]) }

        // Pass the installed app's name so a multi-pkg image is matched to *this*
        // product (see `preferredPackage`).
        let appName = installedApp.deletingPathExtension().lastPathComponent
        guard let pkg = Self.preferredPackage(in: mountPoint, preferring: appName) else {
            throw PackageError.noInstallablePackage
        }
        let dest = workDir.appendingPathComponent(pkg.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        guard run("/usr/bin/ditto", [pkg.path, dest.path]) == 0 else {
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
    private func packageSignature(_ pkg: URL) -> (isValid: Bool, teamIdentifier: String?) {
        let result = runCapturingOutput("/usr/sbin/pkgutil", ["--check-signature", pkg.path])
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

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        // We use only the exit status, so discard output to /dev/null rather than to
        // undrained `Pipe()`s — an unread pipe deadlocks once the child fills its
        // ~64KB buffer (the child blocks on write(), we block in waitUntilExit()).
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    @discardableResult
    private func runCapturingOutput(_ launchPath: String, _ args: [String]) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
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
