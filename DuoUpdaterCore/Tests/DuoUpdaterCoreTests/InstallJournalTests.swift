import Testing
import Foundation
@testable import DuoUpdaterCore

/// The install journal: what an install writes down before it touches an app,
/// and what the next launch does with the files a killed process left.
///
/// Every path is a scratch fixture (`ZZFixture-…`, `DuoUpdater-ZZFixture-…`
/// under a per-test directory); no real app, no real `$TMPDIR` entry, no real
/// disk image. Disk images are replayed through `InstallJournal.Cleanup` and
/// `InstallScratchSweep.Mounts`.
///
/// Serialized like `InstallRollbackPointTests`, whose stores it binds too.
@Suite(.serialized)
struct InstallJournalTests {

    struct Scratch {
        let dir: URL
        let journal: URL
        let apps: URL
        let backups: URL
        var lock: ProcessInstallLock { ProcessInstallLock(url: lockURL) }
        var lockURL: URL { dir.appendingPathComponent("install.lock") }

        func workDir(_ name: String) throws -> URL {
            let url = dir.appendingPathComponent("DuoUpdater-ZZFixture-\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: url.appendingPathComponent("archive.partial"))
            return url
        }
    }

    private func withScratch(_ body: (Scratch) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-journal-\(UUID().uuidString)", isDirectory: true)
        let scratch = Scratch(
            dir: dir,
            journal: dir.appendingPathComponent("install-journal", isDirectory: true),
            apps: dir.appendingPathComponent("Apps", isDirectory: true),
            backups: dir.appendingPathComponent("Backups", isDirectory: true))
        for url in [scratch.journal, scratch.apps, scratch.backups] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        try await InstallJournal.$rootOverride.withValue(scratch.journal) {
            try await BackupStore.$rootOverride.withValue(scratch.backups) {
                try await BackupStore.$destinationOverride.withValue(.local) {
                    try await BackupFactsLibrary.$rootOverride.withValue(
                        dir.appendingPathComponent("Facts")
                    ) {
                        try await body(scratch)
                    }
                }
            }
        }
    }

    private let bundleID = "com.example.zzfixture.journal"

    @discardableResult
    private func makeApp(
        in dir: URL, version: String, name: String = "ZZFixture-Journal.app"
    ) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "ZZFixture-Journal",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data(version.utf8).write(to: contents.appendingPathComponent("Resources/marker.txt"))
        return app
    }

    private func installed(_ app: URL, version: String) -> InstalledApp {
        InstalledApp(
            name: "ZZFixture-Journal", bundleID: bundleID, shortVersion: version,
            buildVersion: nil, path: app, isMASApp: false, sparkleFeedURL: nil)
    }

    /// Run a child that waits until `onLaunch` has had `stamp` called with its
    /// pid, then exits. A child that exits at once can be gone before
    /// `onLaunch` reads it — seen under the full parallel suite, where a
    /// `/usr/bin/true` child no longer answered `proc_pidinfo` by then.
    private func runWaitingChild(_ stamp: @escaping @Sendable (pid_t) -> Void) async throws {
        let go = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-journal-go-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: go) }
        _ = try await ChildProcess.run(
            "/bin/sh", ["-c", "while [ ! -e \"$1\" ]; do sleep 0.01; done", "sh", go.path],
            standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion,
            onLaunch: { pid in
                stamp(pid)
                FileManager.default.createFile(atPath: go.path, contents: nil)
            })
    }

    /// A process that has exited: one we started, stamped while it ran.
    private func deadProcess() async throws -> InstallJournal.ProcessStamp {
        let stamp = JournalBox<InstallJournal.ProcessStamp?>(nil)
        try await runWaitingChild { stamp.set(InstallJournal.ProcessStamp.of($0)) }
        let dead = try #require(stamp.value)
        try #require(!dead.isRunning)
        return dead
    }

    private func entry(
        for app: URL, owner: InstallJournal.ProcessStamp,
        child: InstallJournal.ProcessStamp? = nil,
        oldVersion: String = "1.0", target: String? = "2.0",
        oldCDHash: String? = nil, workDirs: [URL] = [],
        mounts: [InstallJournal.Mount] = [], damage: InstallJournal.Damage? = nil
    ) -> InstallJournal.Entry {
        InstallJournal.Entry(
            job: UUID().uuidString, appID: app.path, appName: "ZZFixture-Journal",
            bundleID: bundleID, appPath: app.path,
            oldVersion: oldVersion, oldBuild: nil, oldCDHash: oldCDHash,
            targetVersion: target, targetBuild: nil, route: "homebrew",
            backupKey: BackupStore.key(bundleID: bundleID, path: app),
            startedAt: Date(), owner: owner, child: child,
            workDirectories: workDirs.map(\.path), mounts: mounts, damage: damage)
    }

    @discardableResult
    private func store(_ entry: InstallJournal.Entry, in scratch: Scratch) throws -> URL {
        let file = scratch.journal.appendingPathComponent("\(entry.job).json")
        try #require(InstallJournal.write(entry, to: file))
        return file
    }

    private static let noMounts = InstallJournal.Cleanup(
        attachment: { _ in .none }, detach: { _, _ in true })

    private func process(
        _ scratch: Scratch, cleanup: InstallJournal.Cleanup = noMounts
    ) async throws -> [InstallJournal.Processed] {
        try #require(await InstallJournal.processLeftovers(lock: scratch.lock, cleanup: cleanup))
    }

    // MARK: - §11: a killed installer and its orphaned child

    /// The installer side is gone (its stamp is a process that exited), the
    /// third party it started is still writing into the scratch directory. The
    /// launch must not touch that directory while the child lives; once it has
    /// exited the directory goes, and the app it deleted reads as interrupted.
    @Test func leftoversWaitForTheOrphanedChildThenGoAndAMissingAppIsInterrupted() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("orphan")
            let app = scratch.apps.appendingPathComponent("ZZFixture-Journal.app")  // never created
            let pids = AsyncStream<pid_t>.makeStream()
            let child = Task {
                try await ChildProcess.run(
                    "/bin/sh", ["-c", "while [ ! -e stop ]; do echo x >> out; sleep 0.05; done"],
                    workingDirectory: work, standardOutput: .discard, standardError: .discard,
                    onCancel: .runToCompletion,
                    onLaunch: { pids.continuation.yield($0) })
            }
            var iterator = pids.stream.makeAsyncIterator()
            let pid = try #require(await iterator.next())
            let childStamp = try #require(InstallJournal.ProcessStamp.of(pid))
            while !FileManager.default.fileExists(atPath: work.appendingPathComponent("out").path) {
                try await Task.sleep(for: .milliseconds(10))
            }
            let file = try store(
                entry(for: app, owner: try await deadProcess(), child: childStamp, workDirs: [work]),
                in: scratch)

            #expect(try await process(scratch) == [.stillRunning(app: "ZZFixture-Journal")])
            #expect(FileManager.default.fileExists(atPath: work.path))
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)

            try Data().write(to: work.appendingPathComponent("stop"))
            _ = try await child.value
            try #require(!childStamp.isRunning)

            #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .missing)])
            #expect(!FileManager.default.fileExists(atPath: work.path))
            let interrupted = InstallJournal.interruptedInstalls()
            #expect(interrupted.map(\.appPath) == [app])
            #expect(interrupted.first?.damage == .missing)
            #expect(interrupted.first?.oldVersion == "1.0")
        }
    }

    /// The file of an install whose own process is alive — this one, which
    /// shares the lock — is not a leftover, whatever its app looks like.
    @Test func anInstallWhoseProcessRunsIsLeftAlone() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("live")
            let app = scratch.apps.appendingPathComponent("ZZFixture-Journal.app")
            let me = try #require(InstallJournal.ProcessStamp.of(getpid()))
            let file = try store(entry(for: app, owner: me, workDirs: [work]), in: scratch)

            #expect(try await process(scratch) == [.stillRunning(app: "ZZFixture-Journal")])
            #expect(FileManager.default.fileExists(atPath: work.path))
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    /// A dead install of an app this process is installing again right now:
    /// the app may be mid-swap, and the two may share a scratch directory name
    /// (Sparkle, Vendor and Xcode name theirs by app and version).
    @Test func aDeadInstallOfAnAppBeingInstalledNowWaits() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("shared")
            let app = scratch.apps.appendingPathComponent("ZZFixture-Journal.app")
            let me = try #require(InstallJournal.ProcessStamp.of(getpid()))
            try store(entry(for: app, owner: me, workDirs: [work]), in: scratch)
            let dead = try store(
                entry(for: app, owner: try await deadProcess(), workDirs: [work]), in: scratch)

            let processed = try await process(scratch)
            #expect(processed == [.stillRunning(app: "ZZFixture-Journal"), .stillRunning(app: "ZZFixture-Journal")])
            #expect(FileManager.default.fileExists(atPath: work.path))
            #expect(FileManager.default.fileExists(atPath: dead.path))
        }
    }

    /// The live install's scratch directory survives the dead one's cleanup
    /// even when they are installing different apps.
    @Test func aDeadInstallsCleanupSparesADirectoryALiveOneUses() async throws {
        try await withScratch { scratch in
            let shared = try scratch.workDir("shared")
            let own = try scratch.workDir("own")
            let me = try #require(InstallJournal.ProcessStamp.of(getpid()))
            try store(entry(
                for: scratch.apps.appendingPathComponent("ZZFixture-Other.app"),
                owner: me, workDirs: [shared]), in: scratch)
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try store(entry(
                for: app, owner: try await deadProcess(), workDirs: [shared, own]), in: scratch)

            _ = try await process(scratch)
            #expect(FileManager.default.fileExists(atPath: shared.path))
            #expect(!FileManager.default.fileExists(atPath: own.path))
        }
    }

    // MARK: - What became of the app

    @Test func anUntouchedAppResolvesAndTheFileGoes() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let file = try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .unchanged)])
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    @Test func anAppAtTheTargetVersionResolvesAsCompleted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "2.0")
            let file = try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .completed)])
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    /// Brew empties a bundle whose successor has the same name: the directory
    /// is there, its Info.plist is not.
    @Test func anEmptiedBundleIsInterruptedAsUnreadable() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents"))
            let file = try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .unreadable)])
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    private func adHocSign(_ app: URL) async throws {
        let signed = try await ChildProcess.run(
            "/usr/bin/codesign", ["--force", "--sign", "-", app.path], onCancel: .runToCompletion)
        try #require(signed.succeeded, "\(String(decoding: signed.standardError, as: UTF8.self))")
    }

    /// Signed before the install, a new cdhash after it, and a seal that no
    /// longer holds: a swap cut off halfway. It reads, so only the signature
    /// can say so.
    @Test func aBundleWhoseNewSignatureIsBrokenIsInterrupted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try await adHocSign(app)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew,
                target: VersionSide(marketing: "2.0")))
            let old = try #require(recording.snapshot.oldCDHash)
            var stale = recording.snapshot
            stale.owner = try await deadProcess()
            InstallJournal.write(stale, to: recording.file)

            try makeApp(in: scratch.apps, version: "2.0")
            try await adHocSign(app)
            try Data("half".utf8).write(
                to: app.appendingPathComponent("Contents/Resources/marker.txt"))
            #expect(CLIToolProcesses.fileCDHash(app.path)
                .map { $0.map { String(format: "%02x", $0) }.joined() } != old)

            #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .signatureBroken)])
        }
    }

    /// The same signed app with its new signature intact is an update that
    /// landed.
    @Test func aBundleWhoseNewSignatureHoldsResolvesAsCompleted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try await adHocSign(app)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew,
                target: VersionSide(marketing: "2.0")))
            var stale = recording.snapshot
            stale.owner = try await deadProcess()
            InstallJournal.write(stale, to: recording.file)

            try makeApp(in: scratch.apps, version: "2.0")
            try await adHocSign(app)

            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .completed)])
        }
    }

    /// An app that writes files into its own bundle breaks its seal without
    /// any install: its cdhash is the one recorded, so it is not "broken".
    @Test func anAppThatWroteIntoItsOwnBundleIsUnchanged() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try await adHocSign(app)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew,
                target: VersionSide(marketing: "2.0")))
            var stale = recording.snapshot
            stale.owner = try await deadProcess()
            InstallJournal.write(stale, to: recording.file)
            try Data("state".utf8).write(
                to: app.appendingPathComponent("Contents/Resources/marker.txt"))

            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .unchanged)])
        }
    }

    // MARK: - Disk images

    @Test func anAttachedImageIsDetachedBeforeItsDirectoryGoes() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("dmg")
            let mount = InstallJournal.Mount(
                mountPoint: work.appendingPathComponent("mnt").path,
                image: work.appendingPathComponent("ZZFixture.dmg").path)
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try store(entry(
                for: app, owner: try await deadProcess(), workDirs: [work], mounts: [mount]),
                in: scratch)
            let detached = JournalBox<[String]>([])
            let cleanup = InstallJournal.Cleanup(
                attachment: { _ in .disk("/dev/disk99") },
                detach: { point, _ in
                    // The directory must still be there while the detach runs.
                    detached.set(detached.value + [point.path]
                        + (FileManager.default.fileExists(atPath: work.path) ? ["dir-present"] : []))
                    return true
                })
            #expect(try await process(scratch, cleanup: cleanup) == [.resolved(app: "ZZFixture-Journal", .unchanged)])
            #expect(detached.value == [mount.mountPoint, "dir-present"])
            #expect(!FileManager.default.fileExists(atPath: work.path))
        }
    }

    /// An image that will not come off, or a table that cannot be read: the
    /// directory holding the mount point stays, and so does the file.
    @Test(arguments: [true, false])
    func aMountThatStaysKeepsItsLeftovers(readable: Bool) async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("stuck")
            let mount = InstallJournal.Mount(
                mountPoint: work.appendingPathComponent("mnt").path,
                image: work.appendingPathComponent("ZZFixture.dmg").path)
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let file = try store(entry(
                for: app, owner: try await deadProcess(), workDirs: [work], mounts: [mount]),
                in: scratch)
            let cleanup = InstallJournal.Cleanup(
                attachment: { _ in readable ? .disk("/dev/disk99") : .unknown },
                detach: { _, _ in false })
            #expect(try await process(scratch, cleanup: cleanup) == [.leftoversRemain(app: "ZZFixture-Journal")])
            #expect(FileManager.default.fileExists(atPath: work.path))
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    // MARK: - Lock

    @Test func anotherProcessHoldingTheLockDefersEverything() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("locked")
            let file = try store(entry(
                for: scratch.apps.appendingPathComponent("ZZFixture-Journal.app"),
                owner: try await deadProcess(), workDirs: [work]), in: scratch)
            let other = try InstallLock.acquire(at: scratch.lockURL)
            defer { other.release() }
            #expect(await InstallJournal.processLeftovers(lock: scratch.lock, cleanup: Self.noMounts) == nil)
            #expect(FileManager.default.fileExists(atPath: work.path))
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    /// The path in a file is persisted state; a delete driven by it gets a
    /// shape check.
    @Test func onlyOurScratchDirectoriesAreRemoved() async throws {
        try await withScratch { scratch in
            let foreign = scratch.dir.appendingPathComponent("ZZFixture-NotScratch", isDirectory: true)
            try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
            try store(entry(
                for: try makeApp(in: scratch.apps, version: "1.0"),
                owner: try await deadProcess(), workDirs: [foreign]), in: scratch)
            _ = try await process(scratch)
            #expect(FileManager.default.fileExists(atPath: foreign.path))
        }
    }

    // MARK: - Recording

    /// What an install writes: the app's state before the swap, then each
    /// scratch directory, mount and child as it appears; and nothing once it
    /// has finished.
    @Test func aRecordingWritesAsTheInstallGoesAndFinishRemovesIt() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew,
                target: VersionSide(marketing: "2.0")))
            func onDisk() throws -> InstallJournal.Entry {
                try JSONDecoder().decode(
                    InstallJournal.Entry.self, from: Data(contentsOf: recording.file))
            }
            var written = try onDisk()
            #expect(written.appPath == app.path)
            #expect(written.oldVersion == "1.0")
            #expect(written.targetVersion == "2.0")
            #expect(written.route == "homebrew")
            #expect(written.backupKey == BackupStore.key(bundleID: bundleID, path: app))
            #expect(written.owner.pid == getpid())
            #expect(written.child == nil)

            let work = try scratch.workDir("recorded")
            let pid = JournalBox<pid_t>(0)
            try await InstallJournal.recording(recording) {
                InstallJournal.noteWorkDirectory(work)
                InstallJournal.noteMount(work.appendingPathComponent("mnt"), image: work.appendingPathComponent("a.dmg"))
                let journal = InstallJournal.current
                try await runWaitingChild { pid.set($0); journal?.noteChild($0) }
            }
            InstallJournal.noteWorkDirectory(scratch.dir)  // outside: not recorded
            written = try onDisk()
            #expect(written.workDirectories == [work.path])
            #expect(written.mounts == [InstallJournal.Mount(
                mountPoint: work.appendingPathComponent("mnt").path,
                image: work.appendingPathComponent("a.dmg").path)])
            #expect(written.child?.pid == pid.value)

            recording.finish()
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.journal.path).isEmpty)
        }
    }

    // MARK: - Rollback points and restore

    /// The rollback sweep discards a point whose app reads. An app found cut
    /// off with a broken signature still reads — and its point is its only way
    /// back, so the two must agree to keep it.
    @Test func theRollbackSweepKeepsThePointOfAJournaledApp() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try store(entry(
                for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)

            #expect(await InstallCoordinator.sweepSettledInstallRollbackPoints(lock: scratch.lock) == 0)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
        }
    }

    /// The interrupted install points at the rollback point when there is one,
    /// over an older user backup of the same app; a restore from it puts the
    /// app back where nothing was, and clears the interrupted install.
    @Test func anInterruptedInstallRestoresFromItsRollbackPointAndIsCleared() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "0.9")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.save(appPath: app, key: key, version: "0.9", bundleID: bundleID)
            try makeApp(in: scratch.apps, version: "1.0")
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            _ = try await process(scratch)

            let interrupted = try #require(InstallJournal.interruptedInstalls().first)
            let source = try #require(interrupted.restoreFrom)
            #expect(source.purpose == .installRollbackPoint)
            #expect(source.version == "1.0")
            #expect(interrupted.iconSource == source.bundle)
            #expect(source.bundle != nil)

            try await BackupStore.restoreReportingUserData(
                forKey: source.key, over: interrupted.appPath, from: source.purpose)
            #expect(InstallJournal.versions(at: app).marketing == "1.0")
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    /// No rollback point: the user's backup is the way back.
    @Test func withoutARollbackPointTheUserBackupIsTheSource() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)
            let source = try #require(InstallJournal.interruptedInstalls().first?.restoreFrom)
            #expect(source.purpose == .userBackup)
            #expect(source.key == key)
        }
    }
}

/// A value set from a `@Sendable` callback and read after it.
final class JournalBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func set(_ value: T) { lock.withLock { stored = value } }
}
