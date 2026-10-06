import Foundation

/// Clears a staged self-update that `UpdatePolicy.clearsStagedBuild` says is in
/// the way of our install, by whichever updater staged it.
public enum StagedBuildClearance {
    public static func clear(
        for app: InstalledApp,
        staged: StagedSelfUpdate
    ) async -> SparkleStagingClearance.Outcome {
        switch staged.updater {
        case .magpie:
            return MagpieStagingClearance.clear(for: app, staged: staged)
        default:
            return await SparkleStagingClearance.clear(for: app, staged: staged)
        }
    }
}

/// Takes away the build magpie's own updater staged, so the swap it makes on
/// quit cannot replace ours (see `SelfUpdaterStaging.magpieStaged`).
///
/// magpie keeps "a build is staged" in its process's memory, not on disk, so
/// there is no installer to stop: what it acts on at quit is the path
/// `.magpie-update/app/magpie.app`. Its swap first renames the current bundle into
/// `.magpie-update/app/old.app`; with the directory gone that rename fails, magpie
/// returns the error and the bundle on disk stays as it is (`Install` in magpie's
/// `internal/update/update.go`).
///
/// The directory is renamed away in one step and only then deleted, so magpie
/// never sees a half-deleted staged bundle — a partial delete in place would leave
/// `app/magpie.app` present and broken, and magpie would swap that in. **Fails
/// closed:** if the rename does not happen, nothing was touched and the caller
/// yields as before. A failed delete after the rename leaves only a hidden
/// directory nobody reads.
public enum MagpieStagingClearance {
    public static func clear(
        for app: InstalledApp,
        staged: StagedSelfUpdate,
        fileManager: FileManager = .default
    ) -> SparkleStagingClearance.Outcome {
        let outcome = attempt(for: app, staged: staged, fileManager: fileManager)
        switch outcome {
        case .cleared:
            Log.install.notice("cleared magpie staging: \(app.name, privacy: .public) had \(staged.version, privacy: .public) staged")
        case .notCleared(let reason, _):
            Log.install.error("magpie staging not cleared: \(app.name, privacy: .public) \(staged.version, privacy: .public) — \(reason, privacy: .public)")
        }
        return outcome
    }

    static func attempt(
        for app: InstalledApp,
        staged: StagedSelfUpdate,
        fileManager: FileManager
    ) -> SparkleStagingClearance.Outcome {
        guard staged.updater == .magpie else {
            return .notCleared(reason: "not a magpie staging", touchedInstaller: false)
        }
        let dir = SelfUpdaterStaging.magpieStagingDirectory(for: app).standardizedFileURL
        // Only the directory this staging was read from.
        guard staged.stagedBundlePath.standardizedFileURL.path.hasPrefix(dir.path + "/") else {
            return .notCleared(
                reason: "staged build is not under \(dir.path)", touchedInstaller: false)
        }
        let aside = dir.deletingLastPathComponent()
            .appendingPathComponent(".magpie-update.duo-cleared-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.moveItem(at: dir, to: aside)
        } catch {
            return .notCleared(
                reason: "could not move \(dir.path) aside: \(error.localizedDescription)",
                touchedInstaller: false)
        }
        do {
            try fileManager.removeItem(at: aside)
        } catch {
            Log.install.error("magpie staging moved aside but not deleted: \(aside.path, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        }
        return .cleared
    }
}
