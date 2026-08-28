import Foundation
import Testing
@testable import DuoUpdaterCore

/// The safety net the input-method one-click came back with: an input method's
/// dictionary and settings live outside its bundle, so the bundle rollback point
/// cannot speak for them.
///
/// Both overrides are task-local, so these run alongside other suites without
/// leaking a scratch home or a scratch backup root into them.
@Suite struct InputMethodDataBackupTests {

    // MARK: - Discovery

    /// The two naming conventions the real apps follow, and the reason both rules
    /// are needed rather than one:
    ///
    ///   * DoubaoIme's preferences are all under its bundle id
    ///     (`…doubaoime`, `.settings`, `.installer`) — a bundle-id rule finds them.
    ///   * WeType's settings pane writes `com.tencent.WeTypeSettings`, which shares
    ///     no prefix with `com.tencent.inputmethod.wetype` — only a name rule
    ///     finds it.
    ///
    /// A rule that dropped either half would silently leave real settings out of
    /// the snapshot, which is the exact failure this module exists to prevent.
    @Test func discoveryFindsSupportByNameAndPreferencesByIdOrName() throws {
        try withScratchHome { home in
            let library = home.appendingPathComponent("Library")
            try makeDirectory(library.appendingPathComponent("Application Support/WeType"))
            try makeDirectory(library.appendingPathComponent("Application Support/Unrelated"))
            let prefs = library.appendingPathComponent("Preferences")
            try makeDirectory(prefs)
            for name in [
                "com.tencent.inputmethod.wetype.plist",     // the bundle id itself
                "com.tencent.inputmethod.wetype.helper.plist", // a suffixed sibling
                "com.tencent.WeTypeSettings.plist",         // reachable only by name
                "com.tencent.QQMusic.plist",                // same vendor, not ours
                "com.example.other.plist",
            ] {
                try Data("x".utf8).write(to: prefs.appendingPathComponent(name))
            }

            let found = InputMethodDataBackup.locations(
                bundleName: "WeType", bundleID: "com.tencent.inputmethod.wetype")
            let leaves = Set(found.map(\.original.lastPathComponent))
            #expect(leaves == [
                "WeType",
                "com.tencent.inputmethod.wetype.plist",
                "com.tencent.inputmethod.wetype.helper.plist",
                "com.tencent.WeTypeSettings.plist",
            ])
        }
    }

    /// Discovery reports only what exists — an app with no data yet must produce
    /// an empty snapshot rather than a set of paths that cannot be copied.
    @Test func discoverySkipsWhatIsNotThere() throws {
        try withScratchHome { home in
            try makeDirectory(home.appendingPathComponent("Library/Preferences"))
            #expect(InputMethodDataBackup.locations(
                bundleName: "Absent", bundleID: "com.example.absent").isEmpty)
        }
    }

    // MARK: - Round trip

    /// The whole point, end to end: snapshot, let the update (or the app's own
    /// migration after it) mangle the data, roll back, get it back.
    @Test func aSnapshotRestoresTheDataTheUpdateChanged() throws {
        try withScratchHome { home in
            try withScratchBackupRoot { root in
                let key = "com.example.ime-Fixture"
                // The snapshot attaches to a bundle backup that already landed.
                try makeDirectory(root.appendingPathComponent(key))

                let support = home.appendingPathComponent("Library/Application Support/Fixture")
                try makeDirectory(support.appendingPathComponent("userDict"))
                let dict = support.appendingPathComponent("userDict/words.db")
                try Data("the words the user taught it".utf8).write(to: dict)
                let prefs = home.appendingPathComponent("Library/Preferences")
                try makeDirectory(prefs)
                let plist = prefs.appendingPathComponent("com.example.ime.plist")
                try Data("settings".utf8).write(to: plist)

                let captured = InputMethodDataBackup.save(
                    bundleName: "Fixture", bundleID: "com.example.ime", key: key)
                #expect(captured.count == 2)

                // The update happens, and the app rewrites its own data.
                try Data("wiped".utf8).write(to: dict)
                try FileManager.default.removeItem(at: plist)

                let restored = try InputMethodDataBackup.restore(forKey: key)
                #expect(restored.count == 2)
                #expect(try String(contentsOf: dict, encoding: .utf8)
                    == "the words the user taught it")
                #expect(try String(contentsOf: plist, encoding: .utf8) == "settings")
            }
        }
    }

    /// A rollback must not consume the copy it rolled back to: restoring twice has
    /// to work, because the first restore might be the one that goes wrong.
    @Test func restoringDoesNotConsumeTheSnapshot() throws {
        try withScratchHome { home in
            try withScratchBackupRoot { root in
                let key = "com.example.ime-Fixture"
                try makeDirectory(root.appendingPathComponent(key))
                let support = home.appendingPathComponent("Library/Application Support/Fixture")
                try makeDirectory(support)
                try makeDirectory(home.appendingPathComponent("Library/Preferences"))
                let dict = support.appendingPathComponent("words.db")
                try Data("original".utf8).write(to: dict)

                InputMethodDataBackup.save(
                    bundleName: "Fixture", bundleID: "com.example.ime", key: key)
                try Data("mangled".utf8).write(to: dict)
                _ = try InputMethodDataBackup.restore(forKey: key)
                try Data("mangled again".utf8).write(to: dict)
                _ = try InputMethodDataBackup.restore(forKey: key)

                #expect(try String(contentsOf: dict, encoding: .utf8) == "original")
            }
        }
    }

    /// Never written on its own: a snapshot in a directory `BackupStore` does not
    /// know about would never be pruned, and would outlive the app it belongs to.
    @Test func nothingIsStoredWithoutABundleBackupToAttachTo() throws {
        try withScratchHome { home in
            try withScratchBackupRoot { _ in
                let support = home.appendingPathComponent("Library/Application Support/Fixture")
                try makeDirectory(support)
                try Data("x".utf8).write(to: support.appendingPathComponent("words.db"))
                #expect(InputMethodDataBackup.save(
                    bundleName: "Fixture", bundleID: "com.example.ime",
                    key: "no-such-backup").isEmpty)
            }
        }
    }

    /// Asking to restore something that was never snapshotted is a real answer,
    /// not an empty success — the caller logs the difference.
    @Test func restoringWithoutASnapshotThrows() throws {
        try withScratchBackupRoot { _ in
            #expect(throws: (any Error).self) {
                _ = try InputMethodDataBackup.restore(forKey: "never-saved")
            }
        }
    }

    /// A snapshot whose cleanup never ran must be reclaimed by the next backup for
    /// the same app — which means its staging directory has to be named something
    /// `BackupStore.sweepStagingLeftovers` actually selects.
    ///
    /// Built from the production naming function, not a literal, so this fails if
    /// anyone gives the snapshot a name of its own again. It shipped as
    /// `.userdata-staging-<key>-…` briefly, which the sweep's `.staging-<key>`
    /// prefix does not match: a copy of the user's whole input-method data
    /// directory, stranded for good and invisible while it sat there, because
    /// every scan of the store's root passes `.skipsHiddenFiles` — so retention
    /// would not prune it and `backupSize` would not count it.
    @Test func aStrandedUserDataSnapshotIsReclaimedByTheNextBackup() throws {
        try withScratchBackupRoot { root in
            let key = "com.example.ime-Fixture"
            let stranded = root.appendingPathComponent(
                InputMethodDataBackup.stagingName(key: key), isDirectory: true)
            try makeDirectory(stranded)
            try Data("learned words".utf8)
                .write(to: stranded.appendingPathComponent("words.db"))

            // A different app's leftover must survive: the sweep is keyed per app,
            // and one install must never reclaim another's in-flight snapshot.
            let other = root.appendingPathComponent(
                InputMethodDataBackup.stagingName(key: "com.example.other-Fixture"),
                isDirectory: true)
            try makeDirectory(other)

            BackupStore.sweepStagingLeftovers(in: root, key: key)

            #expect(!FileManager.default.fileExists(atPath: stranded.path))
            #expect(FileManager.default.fileExists(atPath: other.path))
        }
    }

    // MARK: - Helpers

    private func withScratchHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoIMEHome-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try InputMethodDataBackup.$homeOverride.withValue(home) { try body(home) }
    }

    private func withScratchBackupRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoIMEBackups-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try BackupStore.$rootOverride.withValue(root) { try body(root) }
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
