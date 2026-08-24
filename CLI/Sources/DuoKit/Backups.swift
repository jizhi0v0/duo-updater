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
            /// Move everything still sitting on this Mac onto the backup disk.
            case sync
            /// Re-check stored backups against what was recorded for them.
            case verify(deep: Bool)
            /// Ask whether a folder could hold the store, without adopting it.
            case probe(path: String)
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
        case .sync:
            return sync(json: options.json)
        case .verify(let deep):
            return verify(deep: deep, json: options.json)
        case .probe(let path):
            return probe(path: path, json: options.json)
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
        // Said before the rows, and on stderr so it cannot corrupt `--json`.
        // Without it a store that lives on a disk in someone's bag prints "No
        // backups stored.", which is a sentence about their data rather than
        // about a cable, and is the difference between reaching for the disk and
        // concluding the backups are gone.
        note(unreachableDestination())
        json ? emitJSON(rows) : emitText(rows)
        return 0
    }

    /// A line explaining why the listing may be short, or nil when it is whole.
    static func unreachableDestination() -> String? {
        switch BackupStore.availability() {
        case .localOnly, .ready:
            return nil
        case .volumeNotMounted(let name, _):
            return "the backup disk \u{201C}\(name ?? "?")\u{201D} isn't connected — "
                + "showing only what is on this Mac"
        case .identityMismatch(_, _, let path):
            return "a different disk is mounted at \u{201C}\(path)\u{201D} — "
                + "showing only what is on this Mac"
        case .notWritable(let path):
            return "\u{201C}\(path)\u{201D} can't be written to — "
                + "showing only what is on this Mac"
        }
    }

    static func note(_ message: String?) {
        guard let message else { return }
        FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
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
    ///
    /// A backup on the external destination is a single archive file, not a
    /// directory, and a directory enumerator over a file yields nothing — so
    /// without the branch every such backup would be reported as 0 bytes, which
    /// looks like an empty backup rather than a compressed one.
    static func backupSize(_ backup: BackupStore.Backup) -> Int64 {
        if backup.location == .destination {
            let size = try? FileManager.default.attributesOfItem(
                atPath: backup.bundlePath.path)[.size] as? Int64
            return size.flatMap { $0 } ?? 0
        }
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

    // MARK: - Sync

    /// Move every backup still sitting on this Mac onto the backup disk, now.
    ///
    /// Synchronous and in this process, not handed to `BackupTransferQueue`.
    /// The queue's whole job — running in the background, holding an App Nap
    /// assertion, backing off around a cable that comes and goes — is only
    /// meaningful for a process that stays alive, and `duo` exits. So this walks
    /// what is owed and reports each move as it lands, which is what a command
    /// line can actually offer: a line per app and an exit code.
    ///
    /// The menu-bar app's queue may be moving the same backups at the same
    /// time. A key that disappears from the outbox mid-run is therefore reported
    /// as already moved rather than as a failure — the outcome is the one that
    /// was asked for, whoever produced it.
    static func sync(json: Bool) -> Int32 {
        // Sweep before asking about the disk, so this is worth running even with
        // no disk configured: a save that was cut off leaves its scratch in the
        // outbox whether or not the store was ever moved, and this is the only
        // command a machine without the menu-bar app running can use to clear it.
        //
        // Without an `excluding` set — this process knows of no transfer in
        // flight, and cannot ask the app's queue — so the age gate is the only
        // guard. The cost of getting that wrong is bounded: a `.partial` removed
        // out from under a live transfer makes that one transfer fail and be
        // redone, never a backup lost.
        BackupStore.sweepStaleScratch()

        switch BackupStore.availability() {
        case .localOnly:
            note("no backup disk is configured — backups stay on this Mac")
            return 0
        case .ready:
            break
        case .volumeNotMounted, .identityMismatch, .notWritable:
            note(unreachableDestination())
            return 1
        }

        let keys = BackupStore.pendingTransferKeys()
        let compression = Settings.backupCompression()
        if json { NDJSON.begin("backups sync") }
        guard !keys.isEmpty else {
            if !json { print("Nothing to move — every backup is already on the disk.") }
            return 0
        }

        var moved = 0
        var movedBytes: Int64 = 0
        var failures = 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        for key in keys {
            let name = BackupStore.displayName(forKey: key) ?? key
            do {
                let backup = try BackupStore.transferToDestination(
                    forKey: key, compression: compression)
                let bytes = (try? FileManager.default.attributesOfItem(
                    atPath: backup.bundlePath.path)[.size] as? Int64).flatMap { $0 } ?? 0
                moved += 1
                movedBytes += bytes
                if json {
                    NDJSON.emit(["app": name, "key": key, "moved": true, "bytes": bytes])
                } else {
                    print("  \(name)  →  \(formatter.string(fromByteCount: bytes))")
                }
            } catch {
                // Gone from the outbox means somebody else moved it, which is the
                // result this command wanted. Anything else is a real failure.
                if BackupStore.backup(forKey: key)?.location == .destination {
                    if json { NDJSON.emit(["app": name, "key": key, "moved": true, "byOther": true]) }
                    continue
                }
                failures += 1
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                if json {
                    NDJSON.emit(["app": name, "key": key, "moved": false, "error": message])
                } else {
                    FileHandle.standardError.write(Data("  \(name): \(message)\n".utf8))
                }
            }
        }
        if !json {
            print("\n  \(moved) moved, \(formatter.string(fromByteCount: movedBytes)) on the disk"
                + (failures == 0 ? "." : ", \(failures) failed."))
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - Verify

    /// Re-check every stored backup against what was recorded when it was
    /// stored, and say plainly which ones could not be checked at all.
    ///
    /// Exits 1 only for a backup that is damaged or unreadable. One that predates
    /// fingerprints is reported and does not fail the run: it is not evidence of
    /// a problem, and making it an error would train anyone scripting this to
    /// ignore the exit code.
    static func verify(deep: Bool, json: Bool) -> Int32 {
        note(unreachableDestination())
        let outcomes = BackupStore.verify(deep: deep)
        if json {
            NDJSON.begin("backups verify")
            for outcome in outcomes { NDJSON.emit(payload(outcome)) }
        } else {
            emitVerifyText(outcomes)
        }
        return outcomes.contains { $0.result.isFailure } ? 1 : 0
    }

    static func payload(_ outcome: BackupStore.VerifyOutcome) -> [String: Any] {
        var row: [String: Any] = [
            "app": outcome.name,
            "key": outcome.key,
            "where": outcome.location == .outbox ? "this Mac" : "backup disk",
            "status": status(outcome.result),
        ]
        if let version = outcome.version { row["version"] = version }
        if let detail = detail(outcome.result) { row["detail"] = detail }
        return row
    }

    static func status(_ result: BackupStore.VerifyOutcome.Result) -> String {
        switch result {
        case .ok:           return "ok"
        case .mismatch:     return "mismatch"
        case .unverifiable: return "unverifiable"
        case .unreadable:   return "unreadable"
        }
    }

    static func detail(_ result: BackupStore.VerifyOutcome.Result) -> String? {
        switch result {
        case .ok: return nil
        case .mismatch(let why), .unverifiable(let why), .unreadable(let why): return why
        }
    }

    static func emitVerifyText(_ outcomes: [BackupStore.VerifyOutcome]) {
        guard !outcomes.isEmpty else {
            print("No backups stored.")
            return
        }
        let width = min(38, outcomes.map(\.name.count).max() ?? 10)
        for outcome in outcomes.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) {
            let name = outcome.name.count > width
                ? String(outcome.name.prefix(width - 1)) + "\u{2026}"
                : outcome.name.padding(toLength: width, withPad: " ", startingAt: 0)
            let mark: String
            switch outcome.result {
            case .ok:           mark = "ok"
            case .mismatch:     mark = "DAMAGED"
            case .unverifiable: mark = "not checkable"
            case .unreadable:   mark = "UNREADABLE"
            }
            let place = outcome.location == .outbox ? "this Mac" : "backup disk"
            print("  \(name)  \(mark)  (\(place))"
                + (detail(outcome.result).map { " — \($0)" } ?? ""))
        }
        let damaged = outcomes.filter { $0.result.isFailure }.count
        let unchecked = outcomes.filter {
            if case .unverifiable = $0.result { return true }
            return false
        }.count
        print("\n  \(outcomes.count) checked, \(damaged) damaged"
            + (unchecked == 0 ? "." : ", \(unchecked) with nothing to check against."))
    }

    // MARK: - Probe

    /// Report what a folder could do as a backup store, without claiming it.
    ///
    /// Deliberately does not adopt: no marker is written and no preference
    /// changes, so this is safe to point at a share you are only considering.
    /// It is also the honest answer to "will this work on my NAS?" — SMB and NFS
    /// cannot be faked in a test, so the project ships the measurement rather
    /// than a claim.
    static func probe(path: String, json: Bool) -> Int32 {
        let directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
        let report: BackupDestinationProbe.Report
        do {
            report = try BackupDestinationProbe.run(at: directory)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
            return 1
        }

        if json {
            NDJSON.begin("backups probe")
            var row: [String: Any] = ["path": directory.path]
            if let free = report.freeBytes { row["freeBytes"] = free }
            if let max = report.maxFileBytes { row["maxFileBytes"] = max }
            if let speed = report.writeBytesPerSecond { row["writeBytesPerSecond"] = speed }
            if let fs = report.filesystem { row["filesystem"] = fs }
            if let removable = report.isRemovable { row["isRemovable"] = removable }
            if let local = report.isLocal { row["isLocal"] = local }
            NDJSON.emit(row)
            return 0
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        print("  \(directory.path)")
        print("  filesystem       \(report.filesystem ?? "?")"
            + (report.isLocal == false ? "  (network)" : "")
            + (report.isRemovable == true ? "  (removable)" : ""))
        print("  free             "
            + (report.freeBytes.map { formatter.string(fromByteCount: $0) } ?? "?"))
        // Stated as the number, not as a verdict. Whether it is enough depends on
        // the largest app being backed up, which this command has no way to know.
        print("  largest file     "
            + (report.maxFileBytes.map { formatter.string(fromByteCount: $0) }
               ?? "no declared limit"))
        print("  write speed      "
            + (report.writeBytesPerSecond
                .map { "\(formatter.string(fromByteCount: Int64($0)))/s" }
               ?? "too fast to measure"))
        return 0
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
