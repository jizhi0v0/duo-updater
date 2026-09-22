import Foundation

/// Installs an Xcode `.xip` from Apple's developer site over the installed copy,
/// at the installed copy's own path — the `.xcode` route of `InstallCoordinator`.
///
/// Two phases, like every archive route, so the coordinator can hold a download
/// permit only while bytes move and an apply permit only while the disk works:
///
/// - `download` hands the authorized URL (see `XcodeReleasesSource`) to the
///   host's `XcodeArchiveDownloading`, which owns the Apple ID session.
/// - `apply` checks, in order: room on the scratch volume to expand the archive
///   (`requiredFreeBytes`); the archive's own signature, which must be Apple's
///   software-update identity (`pkgutil --check-signature`, parsed by
///   `appleSoftwareSignatureProblem`); `xip --expand` into a subdirectory of the
///   scratch dir; exactly one top-level `.app` (`expandedApp`); then the bundle
///   gates every swap runs (`SignatureVerifier.verifyInstallArtifact`: code
///   signature, Team ID, bundle id, architecture, macOS floor) against the
///   installed copy; and finally `InPlaceSwap.replace`, which keeps the path.
///
/// **Overwrite keeps the path.** A beta at `Xcode-beta.app` updated to the RC or
/// GA stays at `Xcode-beta.app`, although the RC/GA archive expands to
/// `Xcode.app` — the expanded bundle's own name is never used for anything.
///
/// **A running Xcode is refused, never swapped and never quit.** Unlike the
/// vendor and Sparkle routes, which replace a running app's bundle and ask for
/// a restart, this route will not replace Xcode under itself: Xcode keeps
/// loading plugins, frameworks and tools out of its bundle long after launch
/// (a user decision, not a measurement). Asked twice — before the download,
/// so gigabytes are not spent on an install that would be refused, and again
/// right before the swap, because it may have been opened meanwhile. Matched by
/// the executables running from inside THIS bundle's path (`runningRefusal`),
/// never by bundle id: every Xcode is `com.apple.dt.Xcode`, and the App Store
/// `Xcode.app` running must not block `Xcode-beta.app`.
///
/// **Quarantine** is not handled here: `InPlaceSwap.replace` strips
/// `com.apple.quarantine` recursively from the new bundle after the gates pass,
/// the same as for every other route. Whether `xip` carries a quarantined
/// archive's flag into the bundle is therefore not load-bearing (and was not
/// measured).
public enum XcodeInstaller {

    public enum InstallError: LocalizedError, Equatable {
        case notXcodeUpdate
        case noDownloadURL
        /// The downloader returned a file that is not inside the scratch directory
        /// it was given — which would then be neither verified where we think nor
        /// cleaned up with it.
        case archiveOutsideWorkDir(String)
        case notEnoughSpace(needed: Int64, available: Int64)
        case packageSignatureRejected(String)
        case expandFailed(String)
        case unexpectedArchiveContents(String)
        /// `name` is the installed bundle's name ("Xcode-beta").
        case xcodeRunning(name: String)

        public var errorDescription: String? {
            switch self {
            case .notXcodeUpdate:
                return "This update is not an Xcode archive."
            case .noDownloadURL:
                return "The Xcode update has no download URL."
            case .archiveOutsideWorkDir(let path):
                return "The Xcode download was written outside its scratch folder (\(path)). Nothing was changed."
            case .notEnoughSpace(let needed, let available):
                let format = ByteCountFormatter()
                format.countStyle = .file
                return "Not enough free space to expand Xcode: it needs \(format.string(fromByteCount: needed)) free and \(format.string(fromByteCount: available)) is available. Nothing was changed."
            case .packageSignatureRejected(let why):
                return "The Xcode archive is not signed by Apple (\(why)). Nothing was changed."
            case .expandFailed(let why):
                return "The Xcode archive could not be expanded: \(why). Nothing was changed."
            case .unexpectedArchiveContents(let why):
                return "The Xcode archive did not contain one app: \(why). Nothing was changed."
            case .xcodeRunning(let name):
                return "\(name) is running. Quit it, then click Update again. Nothing was changed."
            }
        }
    }

    // MARK: - Download

    /// Phase 1: fetch the archive into a scratch directory this function creates.
    ///
    /// On success the directory is left for the caller (see `DownloadedUpdate`),
    /// with the archive renamed to `archiveName` inside it so nothing downstream —
    /// `pkgutil`'s output in particular, which echoes the file name — depends on
    /// a name the download chose. On any failure the directory is removed here.
    ///
    /// Refused up front, before any byte moves, when this Xcode is running.
    ///
    /// `scratchRoot` and `runningExecutables` are seams for tests; production
    /// uses the temporary directory, like the other routes, and the live process
    /// list.
    static func download(
        _ result: UpdateResult,
        using downloader: any XcodeArchiveDownloading,
        scratchRoot: URL = FileManager.default.temporaryDirectory,
        runningExecutables: @Sendable () -> [String] = AppRestarter.runningExecutablePaths,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> DownloadedUpdate {
        guard let remote = result.remote, remote.sourceName == XcodeReleasesSource.sourceName else {
            throw InstallError.notXcodeUpdate
        }
        guard let url = remote.downloadURL else { throw InstallError.noDownloadURL }
        if let refusal = Self.runningRefusal(
            installedAt: Self.processPath(of: result.app.path),
            runningExecutables: runningExecutables()) {
            throw refusal
        }

        // `displayVersion` goes through `filesystemSafeToken` for the reason
        // `VendorInstaller.download` gives: it must stay ONE path component.
        let workDir = scratchRoot.appendingPathComponent(
            "DuoUpdater-xcode-\(result.app.scratchSlug)-\((remote.displayVersion ?? "new").filesystemSafeToken)",
            isDirectory: true)
        await removeItemOffCooperativePool(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        do {
            let fetched = try await downloader.downloadXcodeArchive(
                from: url, into: workDir,
                progress: { onStage(.downloading(fraction: $0)) })
            guard Self.isInside(fetched.fileURL, directory: workDir),
                  FileManager.default.fileExists(atPath: fetched.fileURL.path) else {
                throw InstallError.archiveOutsideWorkDir(fetched.fileURL.path)
            }
            let archive = workDir.appendingPathComponent(Self.archiveName)
            if fetched.fileURL.standardizedFileURL != archive.standardizedFileURL {
                try FileManager.default.moveItem(at: fetched.fileURL, to: archive)
            }
            return DownloadedUpdate(
                archiveURL: archive, bytesDownloaded: fetched.bytesDownloaded,
                workDir: workDir, finalHost: fetched.finalHost)
        } catch {
            // Up to a few GB of partial download: removed off the pool.
            await removeItemOffCooperativePool(at: workDir)
            throw error
        }
    }

    static let archiveName = "Xcode-download.xip"

    /// Whether `file` is strictly inside `directory`, symlinks resolved on both
    /// sides (`/var/folders` is `/private/var/folders`).
    static func isInside(_ file: URL, directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = file.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(root + "/")
    }

    // MARK: - Apply

    /// Phase 2: verify, expand, gate and swap. Throws on the first failure, with
    /// the installed copy untouched.
    static func apply(
        _ result: UpdateResult,
        download: DownloadedUpdate,
        runningExecutables: @Sendable @escaping () -> [String] = AppRestarter.runningExecutablePaths,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws {
        let newApp = try await verifiedExpansion(
            of: download.archiveURL, in: download.workDir, onStage: onStage)

        // (e) The gates every swap runs, against the copy being replaced.
        onStage(.verifyingCodeSignature)
        try await SignatureVerifier.verifyInstallArtifact(
            downloadedApp: newApp, installedApp: result.app.path)

        // (f) Replace in place, at the installed path — unless this Xcode was
        // opened while we downloaded (g). Quarantine (h) is stripped inside
        // `replace`.
        onStage(.installing)
        try await Self.swapUnlessRunning(
            over: result.app.path, runningExecutables: runningExecutables,
            swap: { _ = try await InPlaceSwap.replace(newApp: newApp, over: result.app.path) })
        onStage(.done)
    }

    /// Steps (a)–(d) of `apply`, shared with `XcodeSideBySideInstaller`: room to
    /// expand, Apple's signature on the archive, `xip --expand` into
    /// `workDir/expanded`, and the one `.app` that came out. Nothing outside
    /// `workDir` is touched.
    static func verifiedExpansion(
        of archive: URL,
        in workDir: URL,
        onStage: @Sendable @escaping (InstallStage) -> Void
    ) async throws -> URL {
        // (a) Room to expand, before spending a minute on it.
        onStage(.verifyingSignature)
        let (archiveBytes, available) = try await offCooperativePool {
            let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64 ?? 0
            // A fresh URL, not one that may carry cached resource values.
            let values = try URL(fileURLWithPath: workDir.path)
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return (size, values.volumeAvailableCapacityForImportantUsage ?? 0)
        }
        try Self.checkRoomToExpand(archiveBytes: archiveBytes, availableBytes: available)

        // (b) Apple's own signature on the archive.
        let check = try await ChildProcess.run(
            "/usr/sbin/pkgutil", ["--check-signature", archive.path],
            standardError: .mergeIntoOutput,
            onCancel: .terminateChild)
        let output = String(decoding: check.standardOutput, as: UTF8.self)
        if let problem = Self.appleSoftwareSignatureProblem(inPkgutilOutput: output) {
            throw InstallError.packageSignatureRejected(problem)
        }
        guard check.succeeded else {
            throw InstallError.packageSignatureRejected("pkgutil exited \(check.terminationStatus)")
        }

        // (c) Expand. `xip` writes into its working directory, so it gets one of
        // its own. Killed on cancel: it only ever writes inside the scratch dir,
        // which its owner (the coordinator, or the side-by-side install) removes
        // on every exit.
        onStage(.extracting)
        let expanded = workDir.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)
        let expand = try await ChildProcess.run(
            "/usr/bin/xip", ["--expand", archive.path],
            workingDirectory: expanded,
            standardOutput: .discard,
            standardError: .capture,
            onCancel: .terminateChild)
        guard expand.succeeded else {
            let stderr = String(decoding: expand.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError.expandFailed(
                "xip exited \(expand.terminationStatus)\(stderr.isEmpty ? "" : ": \(stderr)")")
        }

        // (d) Exactly one app came out.
        return try await offCooperativePool { try Self.expandedApp(in: expanded) }
    }

    /// The last look before the disk changes: refuse if anything is running from
    /// inside `target`, otherwise `swap`. Split out so the ordering — ask, THEN
    /// swap — is testable with a fake swap.
    static func swapUnlessRunning(
        over target: URL,
        runningExecutables: @Sendable () -> [String],
        swap: () async throws -> Void
    ) async throws {
        if let refusal = runningRefusal(
            installedAt: processPath(of: target), runningExecutables: runningExecutables()) {
            throw refusal
        }
        try await swap()
    }

    /// Why this Xcode cannot be replaced right now, or nil when nothing runs from
    /// it. Pure: `bundlePath` is the installed bundle as the kernel reports paths
    /// (symlinks resolved), `runningExecutables` every process's executable path.
    ///
    /// Containment by path component, so `/Applications/Xcode.app` running never
    /// blocks `/Applications/Xcode-beta.app` (or `Xcode.app.old`).
    ///
    /// Only the app itself (`Contents/MacOS/…`) counts, not every executable in
    /// the bundle. Helpers outlive the app: on 2026-09-22, with the App Store
    /// Xcode not running, `ibtoold` and a `Python` from inside its bundle were
    /// still up. Refusing on those would block a user who has already quit Xcode,
    /// on a process they cannot see; the app is what holds unsaved work, and a
    /// replaced helper is started afresh the next time Xcode runs.
    static func runningRefusal(installedAt bundlePath: String, runningExecutables: [String]) -> InstallError? {
        let bundle = URL(fileURLWithPath: bundlePath)
        let appDir = bundle.appendingPathComponent("Contents/MacOS").path
        guard runningExecutables.contains(where: {
            AppRestarter.isExecutable($0, insideBundlePath: appDir)
        }) else { return nil }
        return .xcodeRunning(name: bundle.deletingPathExtension().lastPathComponent)
    }

    /// `path` as `proc_pidpath` spells it: symlinks resolved.
    static func processPath(of path: URL) -> String {
        path.resolvingSymlinksInPath().path
    }

    /// Free bytes the scratch volume needs, with the archive already on it, before
    /// expanding. Measured 2026-09-22: a 2.01 GB xip expanded to a 3.8 GB bundle
    /// (1.9×). Three times the archive covers that with about 1× the archive to
    /// spare — the swap itself is a same-volume rename and needs nothing more,
    /// and the rollback point taken before the download is an APFS clone.
    static func checkRoomToExpand(archiveBytes: Int64, availableBytes: Int64) throws {
        let needed = requiredFreeBytes(archiveBytes: archiveBytes)
        guard availableBytes >= needed else {
            throw InstallError.notEnoughSpace(needed: needed, available: availableBytes)
        }
    }

    static func requiredFreeBytes(archiveBytes: Int64) -> Int64 {
        let (product, overflow) = archiveBytes.multipliedReportingOverflow(by: freeSpaceMultiple)
        return overflow ? .max : product
    }

    static let freeSpaceMultiple: Int64 = 3

    /// Why `pkgutil --check-signature` output does NOT show Apple's software-update
    /// signature, or nil when it does. Both must hold:
    ///
    ///     Status: signed Apple Software
    ///     Certificate Chain:
    ///      1. Software Update
    ///
    /// (captured from the real Xcode 27 RC xip, 2026-09-22). The status alone
    /// would also describe other Apple-signed software; the leaf pins the identity
    /// Apple ships Xcode under. Lines are compared whole, trimmed, so a Developer
    /// ID package ("Status: signed by a developer certificate…", leaf
    /// "Developer ID Installer: …") and an unsigned one both fail.
    static func appleSoftwareSignatureProblem(inPkgutilOutput output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let status = lines.first(where: { $0.hasPrefix("Status:") }) else {
            return "pkgutil printed no status"
        }
        guard status == "Status: signed Apple Software" else {
            return "pkgutil says “\(status)”"
        }
        guard let chain = lines.firstIndex(of: "Certificate Chain:"),
              let leaf = lines[(chain + 1)...].first(where: { !$0.isEmpty })
        else {
            return "pkgutil printed no certificate chain"
        }
        guard leaf == "1. Software Update" else {
            return "signed by “\(leaf)”, not Apple's Software Update certificate"
        }
        return nil
    }

    /// The one `.app` directly inside `directory`. Throws when there is none,
    /// more than one, or it is a symlink rather than a bundle. Anything else at
    /// the top level is ignored — it is never installed.
    static func expandedApp(in directory: URL) throws -> URL {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        let apps = entries.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else {
            throw InstallError.unexpectedArchiveContents(
                apps.isEmpty
                    ? "no .app at its top level"
                    : "\(apps.count) apps at its top level (\(apps.map(\.lastPathComponent).sorted().joined(separator: ", ")))")
        }
        let values = try app.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw InstallError.unexpectedArchiveContents("“\(app.lastPathComponent)” is not a bundle directory")
        }
        return app
    }
}
