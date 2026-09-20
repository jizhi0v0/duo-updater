import Foundation
import Testing

@testable import DuoUpdaterCore

/// The input-method user-data snapshot on the way to a backup disk and back.
///
/// The snapshot is the reason the input-method one-click was reinstated at all
/// (see `InputMethodDataBackup`), and until 0.4.1 it did not survive the move to
/// an external destination: the transfer packed the bundle, wrote a sidecar that
/// looked complete, and deleted the outbox directory the snapshot was living in.
/// Measured on a real machine on 2026-09-20 — every generation on the backup disk
/// held `<App>.aar` + `backup.json` and nothing else, including two input methods
/// that definitely had one. A rollback from that disk then restored the bundle
/// alone, silently, which is the exact downgrade-onto-newer-data case the
/// snapshot exists to prevent.
///
/// So these tests are about a round trip, not about a function: what matters is
/// that data written before an update comes back after a rollback *from the
/// disk*, and that when it cannot, the caller is told rather than the log.
///
/// Every seam here is task-local, so the suite runs in parallel with the rest.
@Suite struct BackupStoreUserDataTransferTests {

    // MARK: - Fixtures

    /// An outbox, an external destination carrying its marker, a scratch home for
    /// the user data, and an `Input Methods` directory — the install location is
    /// what makes `UpdatePolicy.isInputMethod` (and therefore the whole user-data
    /// path) apply, so the fixture bundle has to live in one.
    private func withInputMethodStores(
        _ body: (_ fixture: Fixture) async throws -> Void
    ) async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("DuoIMEUserData-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let outbox = base.appendingPathComponent("outbox", isDirectory: true)
        let disk = base.appendingPathComponent("disk", isDirectory: true)
        let home = base.appendingPathComponent("home", isDirectory: true)
        // The literal suffix `UpdatePolicy.isInputMethod` matches on.
        let installed = base.appendingPathComponent("Library/Input Methods", isDirectory: true)
        for dir in [outbox, disk, installed, home.appendingPathComponent("Library/Preferences")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let identity = UUID().uuidString
        try BackupVolumeMarker(identity: identity, volumeName: "TestDisk").write(to: disk)
        let destination = BackupDestination(
            kind: .external, path: disk.path, identity: identity, volumeName: "TestDisk")

        let fixture = Fixture(outbox: outbox, disk: disk, home: home, installed: installed)
        try await BackupStore.$rootOverride.withValue(outbox) {
            try await BackupStore.$destinationOverride.withValue(destination) {
                try await InputMethodDataBackup.$homeOverride.withValue(home) {
                    try await body(fixture)
                }
            }
        }
    }

    private struct Fixture {
        let outbox: URL
        let disk: URL
        let home: URL
        let installed: URL

        static let bundleName = "Fixture"
        static let bundleID = "com.example.ime"

        var app: URL { installed.appendingPathComponent("\(Self.bundleName).app") }
        var key: String { BackupStore.key(bundleID: Self.bundleID, path: app) }
        /// The learned dictionary — what a user actually loses when a rollback
        /// restores the bundle alone.
        var dictionary: URL {
            home.appendingPathComponent(
                "Library/Application Support/\(Self.bundleName)/words.db")
        }

        /// Write the bundle at the install location with `marker` inside it, the
        /// way an update replaces one.
        @discardableResult
        func writeApp(marker: String) throws -> URL {
            let fm = FileManager.default
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try? fm.removeItem(at: app)
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>CFBundleExecutable</key><string>App</string>
              <key>CFBundleIdentifier</key><string>\(Self.bundleID)</string>
              <key>CFBundleName</key><string>\(Self.bundleName)</string>
              <key>CFBundlePackageType</key><string>APPL</string>
            </dict></plist>
            """.utf8).write(to: contents.appendingPathComponent("Info.plist"))
            try Data(marker.utf8).write(to: contents.appendingPathComponent("marker.txt"))
            return app
        }

        func appMarker() -> String? {
            try? String(
                contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
        }

        func writeDictionary(_ text: String) throws {
            try FileManager.default.createDirectory(
                at: dictionary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: dictionary)
        }

        func readDictionary() -> String? {
            try? String(contentsOf: dictionary, encoding: .utf8)
        }

        /// Everything `InstallCoordinator.backUp` does for an input method:
        /// the bundle rollback point, then the snapshot beside it.
        func backUp(version: String) async throws {
            try await BackupStore.save(
                appPath: app, key: key, version: version, bundleID: Self.bundleID)
            let captured = await InputMethodDataBackup.save(
                bundleName: Self.bundleName, bundleID: Self.bundleID, key: key)
            #expect(!captured.isEmpty, "the fixture's own snapshot must have been taken")
        }

        func diskEntries() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(
                atPath: disk.appendingPathComponent(key).path)) ?? []).sorted()
        }
    }

    // MARK: - Round trip

    /// The whole point: an input method backed up on this Mac, moved to a backup
    /// disk, updated, and rolled back **from the disk** gets its dictionary back.
    ///
    /// This is the assertion the bug would have failed. It is written as a data
    /// round trip rather than as "a `UserData.aar` exists" on purpose — the file
    /// being present proves nothing about whether a restore can read it, and it
    /// was the restore side that had no path to the snapshot at all.
    @Test func aSnapshotSurvivesTheMoveToTheDiskAndComesBackOnRollback() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("the words the user taught it")
            try await fixture.backUp(version: "1.0")

            try await BackupStore.transferToDestination(forKey: fixture.key)
            // The generation is now on the disk only — the local copy is gone, so
            // nothing below can be quietly reading it instead.
            #expect(!FileManager.default.fileExists(
                atPath: fixture.outbox.appendingPathComponent(fixture.key).path))
            #expect(fixture.diskEntries() == ["Fixture.aar", "UserData.aar", "backup.json"])
            #expect(BackupStore.backup(forKey: fixture.key)?.location == .destination)

            // The update lands, and the new version rewrites the dictionary.
            try fixture.writeApp(marker: "v2")
            try fixture.writeDictionary("what the new version made of it")

            let outcome = try await BackupStore.restoreReportingUserData(
                forKey: fixture.key, over: fixture.app)
            #expect(outcome.version == "1.0")
            #expect(outcome.userData == .restored(1))
            #expect(fixture.appMarker() == "v1")
            #expect(fixture.readDictionary() == "the words the user taught it")
        }
    }

    /// A rollback must not consume the snapshot it rolled back to — the disk copy
    /// is now the only one, and the first rollback might be the one that goes
    /// wrong. The archive is unpacked into the rollback's scratch, which is
    /// deleted on the way out, so this also pins that the unpack reads the disk
    /// rather than moving off it.
    @Test func rollingBackTwiceFromTheDiskStillRestoresTheData() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("original")
            try await fixture.backUp(version: "1.0")
            try await BackupStore.transferToDestination(forKey: fixture.key)

            for attempt in ["mangled", "mangled again"] {
                try fixture.writeApp(marker: "v2")
                try fixture.writeDictionary(attempt)
                let outcome = try await BackupStore.restoreReportingUserData(
                    forKey: fixture.key, over: fixture.app)
                #expect(outcome.userData == .restored(1))
                #expect(fixture.readDictionary() == "original")
            }
        }
    }

    // MARK: - Nothing to restore

    /// The case the user has to hear about: an input-method generation with no
    /// snapshot restores the bundle and says so, rather than logging it.
    ///
    /// The snapshot archive is deleted from the disk rather than never taken, so
    /// this stands in for both a generation from before snapshots travelled and
    /// one whose archive did not survive the disk.
    @Test func aRollbackWithNoSnapshotOnTheDiskReportsBundleOnly() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("original")
            try await fixture.backUp(version: "1.0")
            try await BackupStore.transferToDestination(forKey: fixture.key)
            try FileManager.default.removeItem(
                at: fixture.disk.appendingPathComponent("\(fixture.key)/UserData.aar"))

            try fixture.writeApp(marker: "v2")
            try fixture.writeDictionary("newer data")

            let outcome = try await BackupStore.restoreReportingUserData(
                forKey: fixture.key, over: fixture.app)
            #expect(outcome.userData == .noSnapshot)
            #expect(outcome.userData.isBundleOnly)
            // The bundle still went back — a missing snapshot degrades a rollback,
            // it does not cancel it — and the live data was left exactly as it was
            // rather than half-written.
            #expect(fixture.appMarker() == "v1")
            #expect(fixture.readDictionary() == "newer data")
        }
    }

    /// A truncated or tampered snapshot archive is treated as no snapshot rather
    /// than unpacked over the user's live data. The bundle half stays fatal on a
    /// digest mismatch; this half degrades, because a wrong dictionary put back
    /// over the right one cannot be undone.
    @Test func aTamperedSnapshotArchiveDegradesToBundleOnly() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("original")
            try await fixture.backUp(version: "1.0")
            try await BackupStore.transferToDestination(forKey: fixture.key)

            let archive = fixture.disk.appendingPathComponent("\(fixture.key)/UserData.aar")
            var bytes = try Data(contentsOf: archive)
            bytes[bytes.count - 1] ^= 0xFF
            try bytes.write(to: archive)

            try fixture.writeApp(marker: "v2")
            try fixture.writeDictionary("newer data")
            let outcome = try await BackupStore.restoreReportingUserData(
                forKey: fixture.key, over: fixture.app)
            #expect(outcome.userData == .noSnapshot)
            #expect(fixture.appMarker() == "v1")
            #expect(fixture.readDictionary() == "newer data")
        }
    }

    /// An app that is not an input method has no user data to speak of — its
    /// state is inside the bundle that was just restored — so a rollback must not
    /// report a gap it does not have. Without this, every ordinary rollback would
    /// start telling the user their settings were left behind.
    @Test func anOrdinaryAppReportsNoUserDataQuestion() async throws {
        try await withInputMethodStores { fixture in
            let apps = fixture.home.appendingPathComponent("Applications", isDirectory: true)
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let app = apps.appendingPathComponent("Ordinary.app")
            let contents = app.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try Data("v1".utf8).write(to: contents.appendingPathComponent("marker.txt"))
            let key = BackupStore.key(bundleID: "com.example.ordinary", path: app)
            try await BackupStore.save(
                appPath: app, key: key, version: "1.0", bundleID: "com.example.ordinary")
            try await BackupStore.transferToDestination(forKey: key)

            try Data("v2".utf8).write(to: contents.appendingPathComponent("marker.txt"))
            let outcome = try await BackupStore.restoreReportingUserData(forKey: key, over: app)
            #expect(outcome.userData == .notApplicable)
            #expect(!outcome.userData.isBundleOnly)
        }
    }

    // MARK: - Finding the generations already affected

    /// What can be said about the generations a pre-0.4.1 build already moved.
    /// They are recognised by the install path in their sidecar, in whichever
    /// store they are in, and an ordinary app is never one of them.
    @Test func generationsWithNoSnapshotAreFoundOnTheDisk() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("original")
            try await fixture.backUp(version: "1.0")
            try await BackupStore.transferToDestination(forKey: fixture.key)

            // Nothing to report while the snapshot is where it belongs.
            #expect(BackupStore.generationsMissingUserDataSnapshot().isEmpty)

            // Now the state a pre-0.4.1 transfer left: bundle and sidecar, no
            // snapshot. Both halves are removed, because a sidecar naming an
            // archive that is not there is its own kind of missing.
            let dir = fixture.disk.appendingPathComponent(fixture.key, isDirectory: true)
            try FileManager.default.removeItem(at: dir.appendingPathComponent("UserData.aar"))
            let sidecar = dir.appendingPathComponent("backup.json")
            var decoded = try #require(try JSONSerialization.jsonObject(
                with: Data(contentsOf: sidecar)) as? [String: Any])
            decoded["userDataArchiveName"] = nil
            decoded["userDataArchiveSHA256"] = nil
            try JSONSerialization.data(withJSONObject: decoded).write(to: sidecar)

            let found = BackupStore.generationsMissingUserDataSnapshot()
            #expect(found.count == 1)
            #expect(found.first?.key == fixture.key)
            #expect(found.first?.name == "Fixture")
            #expect(found.first?.version == "1.0")
            #expect(found.first?.store.location == .destination)
        }
    }

    /// The same question asked of the outbox, and the guard against the cheap
    /// wrong answer: a `UserData` directory with no manifest cannot be restored
    /// from, so it must not count as a snapshot. `restore` reads the manifest, so
    /// anything looser here would report a rollback point that is not one.
    @Test func anOutboxGenerationWithoutAManifestCountsAsMissing() async throws {
        try await withInputMethodStores { fixture in
            try fixture.writeApp(marker: "v1")
            try fixture.writeDictionary("original")
            try await fixture.backUp(version: "1.0")
            #expect(BackupStore.generationsMissingUserDataSnapshot().isEmpty)

            try FileManager.default.removeItem(
                at: fixture.outbox
                    .appendingPathComponent(fixture.key)
                    .appendingPathComponent("UserData/userdata.json"))
            #expect(BackupStore.generationsMissingUserDataSnapshot().map(\.key) == [fixture.key])
        }
    }
}
