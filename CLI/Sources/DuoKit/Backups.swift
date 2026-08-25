import Foundation
import DuoUpdaterCore

/// `duo backups` — inspect and roll back the rollback points `BackupStore`
/// keeps, from the command line.
///
/// This is a thin front end: every safety property (signature verification
/// before a restore, retention, atomic swap) already lives in `BackupStore`
/// and `InPlaceSwap` in Core, exactly as the menu-bar app calls them. Nothing
/// here re-implements or loosens that — it only adds app-name resolution,
/// confirmation, and the machine-wide install lock that a CLI needs and the
/// GUI gets from its own event loop.
///
/// One thing this deliberately does NOT do, matching the app's own
/// `AppListModel.rollback`: it does not refuse or defer when the target app is
/// running. Replacing the bundle on disk is safe with the process still up —
/// the running copy keeps its already-mapped pages — so the restore proceeds
/// and this only adds a note to restart, the same as the app's `needsRestart`
/// banner.
public enum Backups {

    public struct Options: Sendable {
        public enum Operation: Sendable, Equatable {
            case list
            /// `app` is resolved the same way `duo install`'s queries are —
            /// path, then bundle id, then name prefix — but must land on
            /// exactly one install, since a restore needs a single target.
            case restore(app: String)
        }
        public var operation: Operation
        public var json = false
        public var assumeYes = false
        public init(operation: Operation) { self.operation = operation }
    }

    public static func run(_ options: Options) async -> Int32 {
        switch options.operation {
        case .list:
            return await list(json: options.json)
        case .restore(let query):
            return await restore(query, assumeYes: options.assumeYes, json: options.json)
        }
    }

    // MARK: - List

    struct Row: Encodable {
        let app: String
        let bundleID: String?
        let path: String?
        let key: String
        let version: String?
        let savedAt: Date
        let bytes: Int64
    }

    static func list(json: Bool) async -> Int32 {
        let settings = Settings.load()
        let installed = await Inventory.scan(settings)
        let rows = rows(installed: installed, backups: BackupStore.allBackups())
        json ? emitJSON(rows) : emitText(rows)
        return 0
    }

    /// Pair every backup on disk with the installed app it belongs to, the same
    /// way the app's own `refreshBackupIndex` does (try each `keyCandidates`
    /// entry against the backup map). `BackupStore` retains a backup after its
    /// app is uninstalled or moved — that disk space is real either way — so a
    /// backup nothing currently installed claims is still listed, just under
    /// its raw key instead of a resolved app name: `BackupStore.Backup` does
    /// not expose the original bundle id or path, only what it stored under.
    static func rows(
        installed: [InstalledApp], backups: [String: BackupStore.Backup]
    ) -> [Row] {
        var matchedKeys = Set<String>()
        var out: [Row] = []
        for app in installed {
            guard let key = BackupStore.keyCandidates(bundleID: app.bundleID, path: app.path)
                .first(where: { backups[$0] != nil }),
                let backup = backups[key]
            else { continue }
            matchedKeys.insert(key)
            out.append(Row(
                app: app.name, bundleID: app.bundleID, path: app.path.path,
                key: key, version: backup.version, savedAt: backup.savedAt,
                bytes: backupSize(backup)))
        }
        for (key, backup) in backups where !matchedKeys.contains(key) {
            out.append(Row(
                app: key, bundleID: nil, path: nil,
                key: key, version: backup.version, savedAt: backup.savedAt,
                bytes: backupSize(backup)))
        }
        return out.sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    /// `BackupStore.totalSize()` only sums every backup at once; there is no
    /// public per-backup size, so this walks the one bundle the same way.
    static func backupSize(_ backup: BackupStore.Backup) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: backup.bundlePath, includingPropertiesForKeys: [.fileSizeKey],
            options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    static func emitJSON(_ rows: [Row]) {
        NDJSON.begin("backups list")
        for row in rows { NDJSON.row(row) }
    }

    static func emitText(_ rows: [Row]) {
        guard !rows.isEmpty else {
            print("No backups stored.")
            return
        }
        let nameWidth = min(38, rows.map(\.app.count).max() ?? 10)
        let byteFormatter = ByteCountFormatter()
        byteFormatter.countStyle = .file
        let when = ISO8601DateFormatter()
        for row in rows {
            let name = row.app.count > nameWidth
                ? String(row.app.prefix(nameWidth - 1)) + "…"
                : row.app.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            print("  \(name)  \(row.version ?? "?")"
                + "  \(when.string(from: row.savedAt))"
                + "  \(byteFormatter.string(fromByteCount: row.bytes))")
        }
        print("\n  \(rows.count) backup\(rows.count == 1 ? "" : "s"), "
            + "\(byteFormatter.string(fromByteCount: rows.reduce(0) { $0 + $1.bytes })) total.")
    }

    // MARK: - Restore

    static func restore(_ query: String, assumeYes: Bool, json: Bool) async -> Int32 {
        let settings = Settings.load()
        let installed = await Inventory.scan(settings)
        let app: InstalledApp
        switch resolveTarget(query: query, installed: installed) {
        case .success(let matched): app = matched
        case .failure(let failure):
            FileHandle.standardError.write(Data("duo: \(failure)\n".utf8))
            return 2
        }

        guard let key = resolveKey(for: app) else {
            FileHandle.standardError.write(Data(
                "duo: no backup stored for \(app.name)\n".utf8))
            return 1
        }
        let stored = BackupStore.backup(forKey: key)
        let previousVersion = stored?.version

        if !json {
            print("Will restore \(app.name)  \(app.shortVersion ?? "?")"
                + "  →  \(previousVersion ?? "?")")
            print("  \(app.path.path)")
            // Said before the confirmation, not after: a pkg lays down helpers,
            // daemons and launch items beside the .app and we only copy the
            // bundle, so this particular rollback is partial and the user should
            // know that while deciding.
            if stored?.fromPackageInstall == true {
                print("""
                  Note: this version was installed by a .pkg. Only the app bundle
                  is restored — any helper, daemon or launch item the package
                  installed stays at its newer version.
                """)
            }
            // Same reason, different limit: the bundle comes back whole, but the
            // store's opinion of it doesn't change. It lists the update again at
            // once, and re-applies it by itself when automatic app updates are on
            // — so this rollback can be undone without the user doing anything.
            if stored?.fromAppStore == true {
                print("""
                  Note: this app updates through the App Store. Rolling back
                  replaces the bundle, but the store will offer the update again
                  straight away — and re-install it on its own if automatic app
                  updates are turned on.
                """)
            }
        }
        guard assumeYes || confirm(app: app.name) else {
            print("Cancelled.")
            return 0
        }

        // Same machine-wide claim `duo install` takes around a swap: the app
        // and the CLI both write the backup store and replace bundles under
        // it, and two of them doing that to the same app at once is a
        // corrupted install, not a race worth retrying through.
        do {
            try await ProcessInstallLock.shared.claim()
        } catch {
            FileHandle.standardError.write(Data("duo: \(error)\n".utf8))
            return 1
        }
        let code = await performRestore(app: app, key: key, json: json)
        await ProcessInstallLock.shared.release()
        return code
    }

    /// Everything on either side of the actual restore call — argument
    /// resolution, confirmation, the lock — is deliberately pure or CLI-only,
    /// so this is the one place `BackupStore.restore` (and therefore its
    /// signature check) actually runs. Held to its own function mainly so
    /// `run` reads as claim → do the one destructive thing → release, matching
    /// `Install.run`'s shape.
    private static func performRestore(app: InstalledApp, key: String, json: Bool) async -> Int32 {
        do {
            let restored = try await Task.detached(priority: .userInitiated) { () -> String? in
                try BackupStore.restore(forKey: key, over: app.path)
            }.value
            if json {
                emitRestoreJSON(app: app.name, key: key, restoredVersion: restored)
            } else {
                print("   restored\(restored.map { " → \($0)" } ?? "").")
                if Check.runningBundlePaths().contains(UpdatePolicy.runtimeBundlePath(app.path)) {
                    print("   \(app.name) is running — restart it to use the restored version.")
                }
            }
            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
            return 1
        }
    }

    static func emitRestoreJSON(app: String, key: String, restoredVersion: String?) {
        NDJSON.begin("backups restore")
        var payload: [String: Any] = ["app": app, "key": key]
        // Omitted rather than null: the store cannot always name the version it
        // put back, and `NSNull` in a stream of otherwise-typed values trips
        // naive readers.
        if let restoredVersion { payload["restoredVersion"] = restoredVersion }
        NDJSON.emit(payload)
    }

    /// Narrow `query` to exactly the one install a restore can target.
    /// `Inventory.select` legitimately returns several matches for one query
    /// when a bundle id is shared (Android Studio channels, Thunderbird
    /// stable/esr) — the right outcome for `check`/`install`, which act on all
    /// of them, but not for a restore, which overwrites one specific bundle.
    static func resolveTarget(
        query: String, installed: [InstalledApp]
    ) -> Result<InstalledApp, Inventory.SelectionFailure> {
        switch Inventory.select(installed, matching: [query]) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let matched):
            guard matched.count == 1, let app = matched.first else {
                let names = matched.map { "  \($0.name) — \($0.path.path)" }.joined(separator: "\n")
                return .failure(Inventory.SelectionFailure(description:
                    "'\(query)' matches \(matched.count) apps:\n\(names)\n"
                    + "Name one exactly, or pass its path."))
            }
            return .success(app)
        }
    }

    /// The backup key `app`'s rollback point is actually stored under, mirroring
    /// `AppListModel.rollback`: try the current path-scoped key, then the
    /// pre-path-scoping legacy key, and use whichever one `BackupStore` has a
    /// backup for. Returns nil rather than falling back to the canonical key —
    /// unlike the save path, a restore with nothing to restore is not something
    /// to paper over with a key `BackupStore.restore` would just reject.
    static func resolveKey(for app: InstalledApp) -> String? {
        BackupStore.keyCandidates(bundleID: app.bundleID, path: app.path)
            .first { BackupStore.backup(forKey: $0) != nil }
    }

    /// Ask before overwriting the installed bundle. Mirrors `Install.confirm`:
    /// with no terminal there is nobody to ask, so a piped or scripted run must
    /// pass `--yes` explicitly rather than having consent assumed for it.
    static func confirm(app: String) -> Bool {
        guard isatty(STDIN_FILENO) == 1 else {
            FileHandle.standardError.write(Data(
                "duo: not a terminal — pass --yes to restore without confirmation\n".utf8))
            return false
        }
        print("Restore \(app) from backup, overwriting the installed copy? [y/N] ", terminator: "")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        else { return false }
        return answer == "y" || answer == "yes"
    }
}
