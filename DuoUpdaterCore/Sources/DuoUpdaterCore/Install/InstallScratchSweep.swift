import Foundation

/// The backstop behind ``InstallJournal``: scratch directories in `$TMPDIR`
/// that no journal accounts for — an install killed before its file was
/// written, a file that could not be written, a restore's or a verify's own
/// scratch — and disk images still attached under them.
///
/// Before this only `DuoUpdater-pkg-` directories were ever swept
/// (`PackageInstaller.sweepStaleWorkDirectories`); of the eleven
/// `"DuoUpdater-` names in the code, the rest stayed until something reused
/// the exact name — for the Sparkle, Vendor and Xcode routes, an install of the
/// same app at the same version. Modelled on that sweep: only directories
/// untouched for ``staleAfter``, far longer than any install runs.
public enum InstallScratchSweep {

    /// How old a scratch directory must be before it is swept. Three days: no
    /// install, Xcode's included, keeps one that long, and a package handed to
    /// Installer is read within the day its own sweep allows.
    public static let staleAfter: TimeInterval = 3 * 24 * 3600

    /// Test seam: the directory swept. Production sweeps `$TMPDIR`.
    @TaskLocal static var rootOverride: URL?

    /// Test seam: the clock ages are measured against.
    @TaskLocal static var nowOverride: Date?

    /// `$TMPDIR`, or nil in a test process that bound no root: a test must not
    /// sweep the real temporary directory the running app shares.
    static var root: URL? {
        if let rootOverride { return rootOverride }
        if DuoStateDirectory.isTestProcess { return nil }
        return FileManager.default.temporaryDirectory
    }

    /// What the sweep runs against attached disk images, so a test can replay
    /// one without attaching a real image. Production uses `live`.
    struct Mounts: Sendable {
        var listing: @Sendable () async -> Data?
        var detach: @Sendable (_ mountPoint: URL, _ image: URL) async -> Bool

        static let live = Mounts(
            listing: { await DiskImageMount.infoListing() },
            detach: { await DiskImageMount.detach($0, image: $1) })
    }

    /// Sweep once. Returns how many directories went, or nil when another
    /// process holds the install lock (nothing was touched).
    ///
    /// The lock is taken non-blocking, like the launch sweeps: another process
    /// mid-install may be using any of these. Inside this process it is
    /// shared, so directories a running install has journaled are skipped as
    /// well — the age alone would cover them, this does not rely on it.
    @discardableResult
    public static func sweep(lock: ProcessInstallLock = .shared) async -> Int? {
        await sweep(lock: lock, mounts: .live)
    }

    static func sweep(lock: ProcessInstallLock, mounts: Mounts) async -> Int? {
        guard let root else { return 0 }
        do {
            try await lock.claim()
        } catch {
            Log.install.notice("scratch sweep: another installer holds the install lock, skipped")
            return nil
        }
        let stale = staleDirectories(in: root)
        var removed = 0
        if !stale.isEmpty {
            let live = InstallJournal.liveWorkDirectories()
            // One merged listing for the whole sweep; nil means `hdiutil` could
            // not be read at all, and then no directory is removed — one could
            // hold a mount nobody can see.
            let attached = await DiskImageMount.attachedImages(listing: mounts.listing)
            for directory in stale where !live.contains(InstallJournal.standardized(directory.path)) {
                guard let attached else { break }
                let prefix = InstallJournal.standardized(directory.path) + "/"
                var clear = true
                for image in attached
                where image.image.hasPrefix(prefix) || image.mountPoints.contains(where: { $0.hasPrefix(prefix) }) {
                    let mountPoint = image.mountPoints.first
                        ?? (image.image as NSString).deletingLastPathComponent
                    if await mounts.detach(
                        URL(fileURLWithPath: mountPoint), URL(fileURLWithPath: image.image)) {
                        Log.install.notice(
                            "scratch sweep: detached \((image.image as NSString).lastPathComponent, privacy: .public) under \(directory.lastPathComponent, privacy: .public)")
                    } else {
                        clear = false
                    }
                }
                guard clear else {
                    Log.install.error(
                        "scratch sweep: a disk image under \(directory.lastPathComponent, privacy: .public) would not detach; the directory stays")
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: directory)
                    removed += 1
                } catch {
                    Log.install.error(
                        "scratch sweep: could not remove \(directory.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        await lock.release()
        if removed > 0 {
            Log.install.notice("scratch sweep: removed \(removed, privacy: .public) stale scratch directories")
        }
        return removed
    }

    /// The `DuoUpdater-…` directories directly in `root` last modified before
    /// ``staleAfter`` ago.
    static func staleDirectories(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = (nowOverride ?? Date()).addingTimeInterval(-staleAfter)
        return entries.filter { entry in
            guard entry.lastPathComponent.hasPrefix("DuoUpdater-"),
                  let values = try? entry.resourceValues(
                    forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true,
                  let modified = values.contentModificationDate
            else { return false }
            return modified < cutoff
        }
    }

    /// Sweep now and then every `interval` until cancelled. The menu-bar app
    /// calls it at launch; `duo` sweeps once before it installs instead, as it
    /// does for `ResumableDownloadStore`.
    @discardableResult
    public static func startSweeping(every interval: Duration = .seconds(24 * 3600)) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            while !Task.isCancelled {
                await sweep()
                // cancel-ok: the loop checks Task.isCancelled on every pass.
                try? await Task.sleep(for: interval)
            }
        }
    }
}
