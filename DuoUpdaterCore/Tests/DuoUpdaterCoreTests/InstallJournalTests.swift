import Testing
import Foundation
import Security
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
          try await InstallJournal.$temporaryDirectoryOverride.withValue(dir) {
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
    }

    private let bundleID = "com.example.zzfixture.journal"

    /// `withExecutable` copies `/usr/bin/true` in as the bundle's executable,
    /// so `codesign` signs real code pages a test can then cut short.
    /// `withHelper` adds a second copy as nested code (`Contents/Helpers`),
    /// which ``adHocSign(_:)`` signs before the app, as `codesign` requires.
    @discardableResult
    private func makeApp(
        in dir: URL, version: String, name: String = "ZZFixture-Journal.app",
        withExecutable: Bool = false, withHelper: Bool = false
    ) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try? FileManager.default.removeItem(at: app)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "ZZFixture-Journal",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        if withExecutable {
            try FileManager.default.createDirectory(
                at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "/usr/bin/true"),
                to: contents.appendingPathComponent("MacOS/ZZFixture"))
            plist["CFBundleExecutable"] = "ZZFixture"
        }
        if withHelper {
            try FileManager.default.createDirectory(
                at: contents.appendingPathComponent("Helpers"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "/usr/bin/true"),
                to: contents.appendingPathComponent("Helpers/ZZFixtureHelper"))
        }
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
    ///
    /// The wait is capped at 30 s. `onCancel: .runToCompletion` means nothing on
    /// this side reaps the child, so a run killed between the spawn and the `go`
    /// file would otherwise leave a `sh` stat-ing a path no one will create, for
    /// as long as the machine is up: on 2026-10-30 the mini had two of them,
    /// 1 d 19 h old, from cancelled CI jobs. A cap the spawn cannot outlive
    /// survives even `SIGKILL` of this process, which an `atexit` handler does
    /// not.
    private func runWaitingChild(_ stamp: @escaping @Sendable (pid_t) -> Void) async throws {
        let go = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-journal-go-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: go) }
        _ = try await ChildProcess.run(
            "/bin/sh",
            ["-c", "n=0; while [ ! -e \"$1\" ] && [ $n -lt 3000 ]; do sleep 0.01; n=$((n+1)); done",
             "sh", go.path],
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
        mounts: [InstallJournal.Mount] = [], damage: InstallJournal.Damage? = nil,
        siblings: [String]? = []
    ) -> InstallJournal.Entry {
        var made = InstallJournal.Entry(
            job: UUID().uuidString, appID: app.path, appName: "ZZFixture-Journal",
            bundleID: bundleID, appPath: app.path,
            oldVersion: oldVersion, oldBuild: nil, oldCDHash: oldCDHash,
            targetVersion: target, targetBuild: nil, route: "homebrew",
            backupKey: BackupStore.key(bundleID: bundleID, path: app),
            startedAt: Date(), owner: owner, child: child,
            workDirectories: workDirs.map(\.path), mounts: mounts, damage: damage)
        made.sameIDSiblings = siblings
        return made
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
    ///
    /// The child's loop is capped at 300 s for the reason in `runWaitingChild`:
    /// it writes to a path this process deletes, and nothing reaps it if the run
    /// is killed first.
    @Test func leftoversWaitForTheOrphanedChildThenGoAndAMissingAppIsInterrupted() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("orphan")
            let app = scratch.apps.appendingPathComponent("ZZFixture-Journal.app")  // never created
            let pids = AsyncStream<pid_t>.makeStream()
            let child = Task {
                try await ChildProcess.run(
                    "/bin/sh",
                    ["-c", "n=0; while [ ! -e stop ] && [ $n -lt 6000 ]; do echo x >> out; sleep 0.05; n=$((n+1)); done"],
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

    /// A bundle copied into place file by file and cut off between its
    /// Info.plist and its executable reads as the target version but does not
    /// run: interrupted, its file kept (and with it the rollback point, which
    /// the sweep keeps for a journaled app). One with no `CFBundleExecutable`
    /// at all stays completed (`anAppAtTheTargetVersionResolvesAsCompleted`).
    /// Mutation: drop the `namesAMissingExecutable` check in `classify` → red
    /// (`.resolved(.completed)`).
    @Test func anAppAtTheTargetVersionWithoutItsExecutableIsInterrupted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            let file = try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .unreadable)])
            #expect(FileManager.default.fileExists(atPath: file.path))
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
        let helper = app.appendingPathComponent("Contents/Helpers/ZZFixtureHelper")
        if FileManager.default.fileExists(atPath: helper.path) {
            let nested = try await ChildProcess.run(
                "/usr/bin/codesign",
                ["--force", "--sign", "-", "--identifier", "com.example.zzfixture.helper", helper.path],
                onCancel: .runToCompletion)
            try #require(nested.succeeded, "\(String(decoding: nested.standardError, as: UTF8.self))")
        }
        let signed = try await ChildProcess.run(
            "/usr/bin/codesign", ["--force", "--sign", "-", app.path], onCancel: .runToCompletion)
        try #require(signed.succeeded, "\(String(decoding: signed.standardError, as: UTF8.self))")
    }

    /// The target version landed and then rewrote a resource of its own
    /// bundle, so its seal over resources no longer holds. That is a working
    /// app, not a cut-off swap: offering to put the old version back over it
    /// would downgrade it.
    @Test func aLandedVersionThatRewroteItsOwnResourceIsCompleted() async throws {
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
            try Data("state".utf8).write(
                to: app.appendingPathComponent("Contents/Resources/marker.txt"))
            #expect(CLIToolProcesses.fileCDHash(app.path)
                .map { $0.map { String(format: "%02x", $0) }.joined() } != old)

            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .completed)])
        }
    }

    /// Signed before the install; after it, a new signature that is not the
    /// target, over an executable cut short — a copy that stopped halfway.
    @Test func aSwapCutOffInTheCodeIsInterrupted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew,
                target: VersionSide(marketing: "2.0")))
            try #require(recording.snapshot.oldCDHash != nil)
            var stale = recording.snapshot
            stale.owner = try await deadProcess()
            InstallJournal.write(stale, to: recording.file)

            try makeApp(in: scratch.apps, version: "1.5", withExecutable: true)
            try await adHocSign(app)
            try cutShort(app.appendingPathComponent("Contents/MacOS/ZZFixture"))

            #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .signatureBroken)])
        }
    }

    private func cutShort(_ file: URL) throws {
        let data = try Data(contentsOf: file)
        try data.prefix(data.count / 2).write(to: file)
    }

    /// The measurement behind `InstallJournal.signature(of:)`'s flags, on an
    /// ad-hoc signed bundle with real code: a rewritten resource fails the
    /// default check and passes with resources left out; code cut short fails.
    @Test func theSignatureCheckIgnoresResourcesButNotCode() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            // Blocking Security calls, so off the pool as the code under test does.
            func status(_ bundle: URL) async -> InstallJournal.SignatureStatus {
                await offCooperativePool { InstallJournal.signature(of: bundle) }
            }
            #expect(await status(app) == .valid)

            try Data("state".utf8).write(
                to: app.appendingPathComponent("Contents/Resources/marker.txt"))
            let byDefault = await offCooperativePool { () -> OSStatus? in
                var code: SecStaticCode?
                guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
                      let code else { return nil }
                return SecStaticCodeCheckValidity(code, [], nil)
            }
            #expect(byDefault != nil && byDefault != errSecSuccess)
            #expect(await status(app) == .valid)

            try cutShort(app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            #expect(await status(app) == .invalid)

            let unsigned = try makeApp(in: scratch.apps, version: "1.0", name: "ZZFixture-Unsigned.app")
            #expect(await status(unsigned) == .unsigned)
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

            await recording.finish(succeeded: false)
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

extension InstallJournalTests {

    /// A child we started that runs until `stop` is called.
    ///
    /// Capped at 180 s, like `runWaitingChild`: `onCancel: .runToCompletion`
    /// leaves nothing to reap it, so a test that throws before `stop()` would
    /// otherwise strand a `sh` for the life of the machine.
    final class LoopingChild: @unchecked Sendable {
        let stamp: InstallJournal.ProcessStamp
        private let stopFile: URL
        private let task: Task<ChildProcess.Outcome, Error>

        init(in dir: URL) async throws {
            let stopFile = dir.appendingPathComponent("stop-\(UUID().uuidString)")
            self.stopFile = stopFile
            let pids = AsyncStream<pid_t>.makeStream()
            task = Task {
                try await ChildProcess.run(
                    "/bin/sh",
                    ["-c", "n=0; while [ ! -e \"$1\" ] && [ $n -lt 9000 ]; do sleep 0.02; n=$((n+1)); done",
                     "sh", stopFile.path],
                    standardOutput: .discard, standardError: .discard, onCancel: .runToCompletion,
                    onLaunch: { pids.continuation.yield($0) })
            }
            var iterator = pids.stream.makeAsyncIterator()
            let pid = try #require(await iterator.next())
            stamp = try #require(InstallJournal.ProcessStamp.of(pid))
        }

        func stop() async throws {
            FileManager.default.createFile(atPath: stopFile.path, contents: nil)
            _ = try await task.value
        }
    }

    // MARK: - Standing (round 2, #1)

    /// An orphaned child of an earlier install, or another process's install
    /// of the app, still running: a host refuses, naming the pid.
    @Test(arguments: [true, false])
    func anAppWhoseEarlierInstallStillRunsIsRefused(viaChild: Bool) async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let other = try await LoopingChild(in: scratch.dir)
            let owner = viaChild ? try await deadProcess() : other.stamp
            try store(entry(for: app, owner: owner, child: viaChild ? other.stamp : nil), in: scratch)
            #expect(InstallJournal.standing(of: app) == .stillRunning(pid: other.stamp.pid))
            // Nor is it copied over meanwhile (round 3, #2): it may be mid-swap.
            #expect(await InstallCoordinator.backUp(installed(app, version: "1.0"), route: .homebrew)
                == .skippedForEarlierInstall(.stillRunning(pid: other.stamp.pid)))
            try await other.stop()
            #expect(InstallJournal.standing(of: app) == .interrupted)
        }
    }

    /// This process's own install of the app, with no child running, is not an
    /// earlier one; nothing at all is clear.
    @Test func thisProcesssOwnRecordIsNotAnEarlierInstall() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            #expect(InstallJournal.standing(of: app) == .clear)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(InstallJournal.standing(of: app) == .clear)
            await recording.finish(succeeded: false)
        }
    }

    /// A reinstall over an interrupted install that leaves the app readable
    /// but not verifiably at its target keeps the earlier way back: the
    /// rollback point, and the interrupted record pointing at it.
    @Test func aReinstallThatDidNotRepairKeepsTheEarlierWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try makeApp(in: scratch.apps, version: "1.5")
            let earlier = try store(entry(
                for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)

            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.5"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "1.5"), journal: recording, succeeded: false) == .kept)
            await recording.finish(succeeded: false)

            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
            #expect(FileManager.default.fileExists(atPath: earlier.path))
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(InstallJournal.interruptedInstalls().map(\.restoreFrom?.purpose) == [.installRollbackPoint])
        }
    }

    /// One that leaves it at its target with its signature holding repairs it:
    /// the point and the interrupted record both go.
    @Test func aReinstallThatRepairedClearsTheEarlierWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            let earlier = try store(entry(
                for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)

            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try await adHocSign(app)
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "2.0"), journal: recording, succeeded: false) == .discarded)
            await recording.finish(succeeded: false)

            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
            #expect(!FileManager.default.fileExists(atPath: earlier.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    /// At the target version but with its code cut short is not repaired.
    @Test func aReinstallAtTheTargetWithBrokenCodeDidNotRepair() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            try store(entry(for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try await adHocSign(app)
            try cutShort(app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            #expect(await InstallJournal.mayDiscardRollbackPoint(for: app) == false)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
    }

    // MARK: - An install that ends with the app gone (round 2, #6)

    /// Past its commit point (round 3, #3: recorded by `InstallCommit.run`).
    @Test func anInstallThatEndsWithTheAppGoneStaysAsInterrupted() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(recording.snapshot.committed == nil)
            try await InstallJournal.recording(recording) {
                try await InstallCommit.run("brew upgrade") { try FileManager.default.removeItem(at: app) }
            }
            #expect(recording.snapshot.committed == true)
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "1.0"), journal: recording, succeeded: false) == .kept)
            await recording.finish(succeeded: false)

            #expect(FileManager.default.fileExists(atPath: recording.file.path))
            let interrupted = InstallJournal.interruptedInstalls()
            #expect(interrupted.map(\.damage) == [.missing])
            #expect(interrupted.first?.restoreFrom?.purpose == .installRollbackPoint)
        }
    }

    /// A cancel before the commit point (package J) ends the item with the app
    /// untouched: that is "nothing happened", so the entry goes, even though
    /// `finish` runs in the cancelled task.
    @Test func aCancelledItemWithTheAppUntouchedLeavesNoEntry() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            let item = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                #expect(Task.isCancelled)
                await recording.finish(succeeded: false)
            }
            await item.value
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    // MARK: - Re-checked before each destructive step (round 2, #2b)

    /// An install of the same app starting while processing waits on
    /// `hdiutil`: its image is not ejected, its directory not deleted.
    @Test(arguments: [true, false])
    func anInstallThatStartsMidProcessingKeepsItsMountAndDirectory(attached: Bool) async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("raced")
            let mount = InstallJournal.Mount(
                mountPoint: work.appendingPathComponent("mnt-ZZFixture.dmg").path,
                image: work.appendingPathComponent("ZZFixture.dmg").path)
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try store(entry(
                for: app, owner: try await deadProcess(), workDirs: [work], mounts: [mount]), in: scratch)
            let me = try #require(InstallJournal.ProcessStamp.of(getpid()))
            let other = scratch.apps.appendingPathComponent("ZZFixture-Other.app")
            let racer = entry(for: other, owner: me, workDirs: [work], mounts: [mount])
            let journal = scratch.journal
            let detached = JournalBox(false)
            let cleanup = InstallJournal.Cleanup(
                attachment: { _ in
                    // The other install writes its record while this lookup runs.
                    InstallJournal.write(racer, to: journal.appendingPathComponent("\(racer.job).json"))
                    return attached ? .disk("/dev/disk99") : .none
                },
                detach: { _, _ in detached.set(true); return true })
            _ = try await process(scratch, cleanup: cleanup)
            #expect(!detached.value)
            #expect(FileManager.default.fileExists(atPath: work.path))
        }
    }

    // MARK: - Shape of the delete (round 2, #5)

    @Test func aScratchNameOutsideTheTemporaryDirectoryIsNotRemoved() async throws {
        try await withScratch { scratch in
            let nested = scratch.dir.appendingPathComponent("sub/DuoUpdater-ZZFixture-nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try store(entry(
                for: try makeApp(in: scratch.apps, version: "1.0"),
                owner: try await deadProcess(), workDirs: [nested]), in: scratch)
            _ = try await process(scratch)
            #expect(FileManager.default.fileExists(atPath: nested.path))
        }
    }
}

extension InstallJournalTests {

    private func cdhash(_ app: URL) -> String? {
        CLIToolProcesses.fileCDHash(app.path).map { $0.map { String(format: "%02x", $0) }.joined() }
    }

    /// Rewrite the file `finish` kept as another process sees it: written by a
    /// process that is still running and is not this one — the menu-bar app,
    /// seen from `duo`.
    private func ownedByAnotherLiveProcess(_ file: URL, _ other: LoopingChild) throws {
        var kept = try JSONDecoder().decode(InstallJournal.Entry.self, from: Data(contentsOf: file))
        kept.owner = other.stamp
        try #require(InstallJournal.write(kept, to: file))
    }

    // MARK: - Nothing deletes an interrupted app's way back (round 3, #1)

    /// With backups on no rollback point is taken, so the user's backup is the
    /// only way back for an app the install left missing. "Nothing at the
    /// recorded path" is what makes a backup an orphan — and what an
    /// interrupted install looks like. An orphan with no journal file still goes.
    @Test func pruningOrphansKeepsTheBackupOfAnInterruptedApp() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: bundleID)
            let gone = try makeApp(in: scratch.apps, version: "1.0", name: "ZZFixture-Uninstalled.app")
            let goneKey = BackupStore.key(bundleID: "com.example.zzfixture.uninstalled", path: gone)
            try await BackupStore.save(
                appPath: gone, key: goneKey, version: "1.0", bundleID: "com.example.zzfixture.uninstalled")
            try FileManager.default.removeItem(at: app)
            try FileManager.default.removeItem(at: gone)
            try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)

            _ = BackupStore.pruneOrphans()
            #expect(BackupStore.backup(forKey: key) != nil)
            #expect(BackupStore.backup(forKey: goneKey) == nil)
            #expect(InstallJournal.interruptedInstalls().first?.restoreFrom?.purpose == .userBackup)
        }
    }

    /// Freeing space deletes other apps' backups oldest first; not the one an
    /// interrupted app would be restored from, however old.
    @Test func reclaimingSpaceKeepsTheBackupOfAnInterruptedApp() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: bundleID)
            let other = try makeApp(in: scratch.apps, version: "1.0", name: "ZZFixture-Other.app")
            let otherKey = BackupStore.key(bundleID: "com.example.zzfixture.other", path: other)
            try await BackupStore.save(
                appPath: other, key: otherKey, version: "1.0", bundleID: "com.example.zzfixture.other")
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)

            let recovered = await BackupStore.$freeBytesOverride.withValue({ 1 }) {
                await BackupStore.reclaimFreeSpace(sparing: "nobody")
            }
            #expect(!recovered)
            #expect(BackupStore.backup(forKey: key) != nil)
            #expect(BackupStore.backup(forKey: otherKey) == nil)
        }
    }

    // MARK: - The copy itself refuses to overwrite the way back (round 3, #2)

    /// An app an earlier install left damaged (1.5 on disk, cut off on its way
    /// to 2.0), whose way back is the 1.0 backup. A backup taken now — by an
    /// install, or by a Relaunch (`StagedRelaunchBackup.take`), which never
    /// asked the journal — would replace 1.0 with the damaged bundle.
    @Test func aBackupOverAnInterruptedInstallKeepsTheWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.save(appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try makeApp(in: scratch.apps, version: "1.5")
            try store(entry(for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)
            let damaged = installed(app, version: "1.5")

            #expect(await InstallCoordinator.backUp(damaged, route: .homebrew)
                == .skippedForEarlierInstall(.interrupted))
            #expect(BackupStore.backup(forKey: key)?.version == "1.0")

            let taken = await StagedRelaunchBackup.take(
                damaged, keepBackups: true, old: VersionSide(marketing: "1.5"),
                runningBefore: [4242],
                system: StagedRelaunchBackup.System(
                    diskVersion: { VersionSide(marketing: "1.5") }, runningPIDs: { [4242] },
                    claimLock: {}, releaseLock: {},
                    backUp: { await InstallCoordinator.backUp(damaged, route: .sparkle) },
                    remove: { Issue.record("nothing was stored, so nothing is removed") }))
            #expect(BackupStore.backup(forKey: key)?.version == "1.0")
            #expect(taken == .attempted(.skippedForEarlierInstall(.interrupted)))
        }
    }

    /// The same for the install rollback point: the 1.0 point stays.
    @Test func aRollbackPointOverAnInterruptedInstallKeepsTheWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try makeApp(in: scratch.apps, version: "1.5")
            try store(entry(for: app, owner: try await deadProcess(), damage: .signatureBroken), in: scratch)

            let took = await InstallCoordinator.takeInstallRollbackPoint(
                installed(app, version: "1.5"), route: .homebrew)
            #expect(!took)
            #expect(BackupStore.rollbackPoint(forKey: key)?.version == "1.0")
            await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "1.5"), journal: nil, succeeded: false)
        }
    }

    // MARK: - Only an install past its commit point leaves an interrupted one (round 3, #3)

    /// The user trashed the app after the scan; the install's re-check stopped
    /// it before its commit point. It did nothing, so it leaves nothing — not
    /// a row offering to bring back an app the user deleted.
    @Test func anInstallStoppedBeforeItsCommitWithTheAppAlreadyGoneLeavesNoEntry() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try FileManager.default.removeItem(at: app)
            await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "1.0"), journal: recording, succeeded: false)
            await recording.finish(succeeded: false)
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
            #expect(InstallJournal.standing(of: app) == .clear)
        }
    }

    /// The same, with the app trashed while its rollback point was taken:
    /// the point is a copy of an app nobody's install removed. Kept, nothing
    /// would ever list or discard it — the sweep keeps every point whose app
    /// does not read — so the settle discards it.
    @Test func aRollbackPointOfAnAppGoneBeforeTheCommitIsDiscarded() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(await InstallCoordinator.takeInstallRollbackPoint(installed(app, version: "1.0"), route: .homebrew))
            try FileManager.default.removeItem(at: app)
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: installed(app, version: "1.0"), journal: recording, succeeded: false) == .discarded)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    // MARK: - A kept entry is not a running install (round 3, #4)

    /// What `finish` keeps, seen from another process while the one that
    /// wrote it still runs: an interrupted install, not a running one — `duo`
    /// installs over it (without a backup) instead of refusing, and launch
    /// processing looks at it and at a dead entry for the same app.
    @Test func anEntryFinishKeptReadsAsInterruptedNotRunning() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try await InstallJournal.recording(recording) {
                try await InstallCommit.run("swap") { try FileManager.default.removeItem(at: app) }
            }
            await recording.finish(succeeded: false)
            try #require(FileManager.default.fileExists(atPath: recording.file.path))
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)

            let other = try await LoopingChild(in: scratch.dir)
            try ownedByAnotherLiveProcess(recording.file, other)
            #expect(InstallJournal.standing(of: app) == .interrupted)
            let processed = try await process(scratch)
            #expect(processed == [
                .interrupted(app: "ZZFixture-Journal", .missing),
                .interrupted(app: "ZZFixture-Journal", .missing),
            ])
            try await other.stop()
        }
    }

    /// In the same process: a later install that leaves the app verifiably at
    /// its target clears the entry an earlier one kept — the menu-bar app runs
    /// for days, and its launch processing is not coming.
    @Test func aRepairingReinstallInTheSameSessionClearsWhatFinishKept() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let first = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try await InstallJournal.recording(first) {
                try await InstallCommit.run("swap") { try FileManager.default.removeItem(at: app) }
            }
            await first.finish(succeeded: false)
            try #require(InstallJournal.interruptedInstalls().count == 1)

            let second = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try await adHocSign(app)
            await second.finish(succeeded: false)
            #expect(!FileManager.default.fileExists(atPath: first.file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    // MARK: - "Verifiably good" is strict (round 3, #5)

    /// A reinstall at its target whose sealed nested helper is gone: the
    /// lenient check passes it (resources are not read), the strict one not.
    @Test func aReinstallMissingANestedBinaryDidNotRepair() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true, withHelper: true)
            try await adHocSign(app)
            try store(entry(
                for: app, owner: try await deadProcess(), oldCDHash: cdhash(app),
                damage: .signatureBroken), in: scratch)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true, withHelper: true)
            try await adHocSign(app)
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Helpers/ZZFixtureHelper"))
            #expect(await InstallJournal.mayDiscardRollbackPoint(for: app) == false)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
    }

    /// Signed before the first install; its main executable gone by the time
    /// of the second, whose own record therefore reads it as unsigned (no
    /// cdhash). The second leaves an unsigned bundle: that is not the app as
    /// it was, so it did not repair — the earliest record says it was signed.
    @Test func signedBeforeIsJudgedFromTheEarliestRecord() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let signedBefore = try #require(cdhash(app))
            try store(entry(
                for: app, owner: try await deadProcess(), oldCDHash: signedBefore,
                damage: .signatureBroken), in: scratch)
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(recording.snapshot.oldCDHash == nil)
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            let executable = app.appendingPathComponent("Contents/MacOS/ZZFixture")
            let stripped = try await ChildProcess.run(
                "/usr/bin/codesign", ["--remove-signature", executable.path], onCancel: .runToCompletion)
            try #require(stripped.succeeded)
            #expect(await offCooperativePool { InstallJournal.signature(of: app) } == .unsigned)
            #expect(await InstallJournal.mayDiscardRollbackPoint(for: app) == false)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
    }

    /// A cask renamed in its new version: the install was cut off after brew
    /// put "… Pro.app" in place and took the old one away. Not missing —
    /// moved: no Restore row (it would put the old version back beside the
    /// new one), the file goes, and so does the old path's rollback point,
    /// which the sweep would otherwise keep for good. A same-ID app below the
    /// target is no such move: still missing, point kept.
    /// A same-ID app that was already beside it when the install began — a
    /// channel sibling (DB Browser for SQLite Nightly, Android Studio's
    /// previews), however new — is no move either: the app is missing and its
    /// rollback point stays. Neither is anything for a file written before the
    /// siblings were recorded.
    /// Mutations: drop the `movedCopy` check in `classify` → `.missing`, red;
    /// drop the point's removal → the point stays, red; drop the version
    /// floor in `movedCopy` → the second case resolves, red; drop the
    /// `siblings` exclusion → the third resolves, red; treat nil as none → the
    /// fourth resolves, red; `≥` instead of `=` the target → the fifth (an
    /// app newer than the update installs) resolves, red.
    @Test func aCaskRenamedByItsUpdateIsMovedNotMissing() async throws {
        let sibling = "ZZFixture-Journal Pro.app"
        for (renamedVersion, siblingsAtStart, moved) in [
            ("2.0", [] as [String]?, true), ("1.0", [], false), ("3.0", [sibling], false), ("2.0", nil, false),
            ("2.1", [], false),
        ] {
            try await withScratch { scratch in
                let app = try makeApp(in: scratch.apps, version: "1.0")
                let key = BackupStore.key(bundleID: bundleID, path: app)
                try await BackupStore.saveInstallRollbackPoint(
                    appPath: app, key: key, version: "1.0", bundleID: bundleID)
                try FileManager.default.removeItem(at: app)
                let renamed = try makeApp(in: scratch.apps, version: renamedVersion, name: sibling, withExecutable: true)
                let file = try store(
                    entry(for: app, owner: try await deadProcess(),
                          siblings: siblingsAtStart?.map { _ in renamed.path }),
                    in: scratch)

                let processed = try await process(scratch)
                if moved {
                    #expect(processed == [.resolved(app: "ZZFixture-Journal", .moved)])
                    #expect(!FileManager.default.fileExists(atPath: file.path))
                    #expect(BackupStore.rollbackPoint(forKey: key) == nil)
                    #expect(InstallJournal.interruptedInstalls().isEmpty)
                } else {
                    #expect(processed == [.interrupted(app: "ZZFixture-Journal", .missing)])
                    #expect(BackupStore.rollbackPoint(forKey: key) != nil)
                }
            }
        }
    }

    /// The line that records an interrupted install says what its row can
    /// offer — the copy it would restore, or that there is none and the row
    /// has no Restore — so a report about a row that will not go away is
    /// answered from the log.
    /// Mutation: always say "way back" → the first check red.
    @Test func theLogSaysWhetherAnInterruptedInstallHasAWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let none = entry(for: app, owner: try await deadProcess(), damage: .missing)
            #expect(InstallJournal.wayBackForTheLog(none).hasPrefix("no way back: no rollback point and no backup"))
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: none.backupKey, version: "1.0", bundleID: bundleID)
            #expect(InstallJournal.wayBackForTheLog(none) == "way back: rollback point 1.0 under \(none.backupKey)")
        }
    }

    /// A file already found cut off (or kept by `finish`) describes an
    /// install that is over: a same-ID app at the target turning up beside it
    /// afterwards — a channel sibling installed since — is no move of it. The
    /// app stays missing, its rollback point kept, its Restore offered.
    /// Mutation: drop the `damage == nil, ended != true` guard in `classify`
    /// → resolved as moved, point deleted, red.
    @Test func aSameIDAppArrivingAfterTheCutOffIsNoMove() async throws {
        for kept in [InstallJournal.Damage.missing, nil] {
            try await withScratch { scratch in
                let app = try makeApp(in: scratch.apps, version: "1.0")
                let key = BackupStore.key(bundleID: bundleID, path: app)
                try await BackupStore.saveInstallRollbackPoint(
                    appPath: app, key: key, version: "1.0", bundleID: bundleID)
                try FileManager.default.removeItem(at: app)
                var cut = entry(for: app, owner: try await deadProcess(), damage: kept)
                if kept == nil { cut.ended = true }
                try store(cut, in: scratch)
                try makeApp(in: scratch.apps, version: "2.0", name: "ZZFixture-Journal Nightly.app", withExecutable: true)

                #expect(try await process(scratch) == [.interrupted(app: "ZZFixture-Journal", .missing)])
                #expect(BackupStore.rollbackPoint(forKey: key) != nil)
                #expect(InstallJournal.interruptedInstalls().count == 1)
            }
        }
    }

    /// A reinstall over an interrupted install that moves the app (a renamed
    /// cask) repaired it: the earlier file is cleared, verified where the app
    /// went, and the old path's rollback point goes with it.
    /// One that was there before the reinstall began (`begin` records it) is
    /// not where the app went.
    /// Mutations: verify at the old path only → the interrupted row stays,
    /// red; `begin` records no siblings → the second case clears, red.
    @Test func aReinstallThatMovedTheAppClearsTheInterruptedOne() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try await adHocSign(try makeApp(
                in: scratch.apps, version: "3.0", name: "ZZFixture-Journal Nightly.app", withExecutable: true))
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            await recording.finish(succeeded: true)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)
            #expect(InstallJournal.interruptedInstalls().count == 1)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try await adHocSign(try makeApp(
                in: scratch.apps, version: "2.0", name: "ZZFixture-Journal Pro.app", withExecutable: true))
            await recording.finish(succeeded: true)
            #expect(InstallJournal.interruptedInstalls().isEmpty)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
        }
    }

    /// Unsigned before and after, at the target — but the executable its
    /// Info.plist names is not there. Not an app that runs.
    @Test func aReinstallWithoutItsExecutableDidNotRepair() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try store(entry(for: app, owner: try await deadProcess(), damage: .unreadable), in: scratch)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            #expect(await InstallJournal.mayDiscardRollbackPoint(for: app) == false)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
    }

    /// The measurement behind the two modes of `InstallJournal.signature(of:strict:)`,
    /// on ad-hoc signed bundles with a main executable and a nested helper
    /// (`Contents/Helpers`), each damaged one way. `SecStaticCodeCheckValidity`
    /// returned, on macOS 27.2 (2026-10-18), lenient
    /// (`kSecCSDoNotValidateResources`) / strict (`kSecCSCheckNestedCode |
    /// kSecCSCheckAllArchitectures`):
    ///
    /// | bundle                     | lenient | strict | cdhash |
    /// |----------------------------|---------|--------|--------|
    /// | intact                     | 0       | 0      | yes    |
    /// | a resource rewritten       | 0       | -67054 | yes    |
    /// | nested helper deleted      | 0       | -67054 | yes    |
    /// | nested helper cut short    | 0       | -67049 | yes    |
    /// | main executable deleted    | -67062  | -67062 | none   |
    /// | main executable cut short  | -67049  | -67049 | none   |
    ///
    /// -67054 errSecCSBadResource, -67049 errSecCSBadObjectFormat, -67062
    /// errSecCSUnsigned (CSCommon.h). The default flags (0) gave the strict
    /// column on every row. Asserted here as the statuses they map to, not
    /// the raw codes, which are the OS's to change.
    @Test func theStrictCheckFailsWhatTheLenientOnePasses() async throws {
        try await withScratch { scratch in
            func fixture(_ name: String, damage: (URL) throws -> Void) async throws -> URL {
                let app = try makeApp(
                    in: scratch.apps, version: "1.0", name: "ZZFixture-\(name).app",
                    withExecutable: true, withHelper: true)
                try await adHocSign(app)
                try damage(app.appendingPathComponent("Contents"))
                return app
            }
            func statuses(_ app: URL) async -> [InstallJournal.SignatureStatus] {
                await offCooperativePool {
                    [InstallJournal.signature(of: app), InstallJournal.signature(of: app, strict: true)]
                }
            }
            let fm = FileManager.default
            let intact = try await fixture("Intact") { _ in }
            #expect(await statuses(intact) == [.valid, .valid])
            #expect(cdhash(intact) != nil && InstallJournal.hasMainExecutable(intact))

            let resource = try await fixture("Resource") {
                try Data("state".utf8).write(to: $0.appendingPathComponent("Resources/marker.txt"))
            }
            #expect(await statuses(resource) == [.valid, .invalid])

            let helperGone = try await fixture("HelperGone") {
                try fm.removeItem(at: $0.appendingPathComponent("Helpers/ZZFixtureHelper"))
            }
            #expect(await statuses(helperGone) == [.valid, .invalid])

            let helperCut = try await fixture("HelperCut") {
                try cutShort($0.appendingPathComponent("Helpers/ZZFixtureHelper"))
            }
            #expect(await statuses(helperCut) == [.valid, .invalid])

            let mainGone = try await fixture("MainGone") {
                try fm.removeItem(at: $0.appendingPathComponent("MacOS/ZZFixture"))
            }
            #expect(await statuses(mainGone) == [.unsigned, .unsigned])
            #expect(cdhash(mainGone) == nil)
            #expect(!InstallJournal.hasMainExecutable(mainGone))

            let mainCut = try await fixture("MainCut") {
                try cutShort($0.appendingPathComponent("MacOS/ZZFixture"))
            }
            #expect(await statuses(mainCut) == [.invalid, .invalid])
            #expect(cdhash(mainCut) == nil)
        }
    }

    // MARK: - Leftovers are processing's (round 3, #6b)

    /// An earlier install whose leftovers were never cleaned (the lock was
    /// busy at launch, or its image would not come off) is not unlinked by a
    /// repairing reinstall: its directory and mount would then belong to no
    /// file, and launch processing is what cleans them.
    @Test func aRepairingReinstallLeavesAnEarlierEntryWithLeftovers() async throws {
        try await withScratch { scratch in
            let work = try scratch.workDir("unprocessed")
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let earlier = try store(entry(
                for: app, owner: try await deadProcess(), oldCDHash: cdhash(app), workDirs: [work]), in: scratch)
            let recording = try #require(await InstallJournal.begin(
                app: installed(app, version: "1.0"), route: .homebrew, target: VersionSide(marketing: "2.0")))
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try await adHocSign(app)
            await recording.finish(succeeded: false)
            #expect(FileManager.default.fileExists(atPath: earlier.path))
            #expect(try await process(scratch) == [.resolved(app: "ZZFixture-Journal", .completed)])
            #expect(!FileManager.default.fileExists(atPath: work.path))
        }
    }

    /// The way back `duo` names over an install launch processing has not
    /// looked at yet (no damage recorded): its point when there is one, and
    /// nothing when there is nothing (round 3, #6a).
    @Test func theWayBackOfAnUnclassifiedInstallIsWhatIsStored() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            #expect(InstallJournal.standing(of: app) == .interrupted)
            #expect(InstallJournal.wayBack(for: app) == nil)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: BackupStore.key(bundleID: bundleID, path: app),
                version: "1.0", bundleID: bundleID)
            #expect(InstallJournal.wayBack(for: app)?.purpose == .installRollbackPoint)
        }
    }

    // MARK: - A cancel over an earlier interrupted install (round 3, #7)

    /// Replaces `aCancelledItemWithTheAppUntouchedLeavesNoEntry`'s blind spot:
    /// there was no earlier entry, so `finish` returned before its only await.
    /// Here there is one — its way back the 1.0 point, the app on disk at the
    /// target with its code cut short — and the item is cancelled after the
    /// rollback-point step: the point is still 1.0, and the earlier entry
    /// stays, though `finish`'s signature read ran in a cancelled task.
    @Test func aCancelOverAnInterruptedInstallKeepsItsWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0", withExecutable: true)
            try await adHocSign(app)
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            let earlier = try store(entry(
                for: app, owner: try await deadProcess(), oldCDHash: cdhash(app),
                damage: .signatureBroken), in: scratch)
            try makeApp(in: scratch.apps, version: "2.0", withExecutable: true)
            try await adHocSign(app)
            try cutShort(app.appendingPathComponent("Contents/MacOS/ZZFixture"))
            let damaged = installed(app, version: "2.0")

            let recording = try #require(await InstallJournal.begin(
                app: damaged, route: .homebrew, target: VersionSide(marketing: "2.0")))
            let item = Task {
                await InstallCoordinator.takeInstallRollbackPoint(damaged, route: .homebrew)
                withUnsafeCurrentTask { $0?.cancel() }
                #expect(Task.isCancelled)
                #expect(await InstallCoordinator.settleInstallRollbackPoint(for: damaged, journal: recording, succeeded: false) == .kept)
                await recording.finish(succeeded: false)
            }
            await item.value
            #expect(BackupStore.rollbackPoint(forKey: key)?.version == "1.0")
            #expect(FileManager.default.fileExists(atPath: earlier.path))
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(InstallJournal.interruptedInstalls().map(\.restoreFrom?.purpose) == [.installRollbackPoint])
        }
    }
}

extension InstallJournalTests {

    // MARK: - A successful install that moved the app (round 4, #1)

    /// brew upgrades a cask whose new version installs under another name:
    /// `Moved#delete` removes the whole old folder when the successor has no
    /// artifact with the same target (Homebrew 7.0.9 `cask/artifact/moved.rb`),
    /// so the old path is empty after a SUCCESS. The host says it succeeded;
    /// that is not an interrupted install, and its rollback point is not the
    /// way back to anything.
    @Test func aSuccessfulInstallThatMovedTheAppLeavesNoInterruptedEntry() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            let old = installed(app, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: old, route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(await InstallCoordinator.takeInstallRollbackPoint(old, route: .homebrew))
            let renamed = scratch.apps.appendingPathComponent("ZZFixture-Renamed.app")
            try await InstallJournal.recording(recording) {
                try await InstallCommit.run("brew upgrade") {
                    try FileManager.default.moveItem(at: app, to: renamed)
                }
            }
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: old, journal: recording, succeeded: true) == .discarded)
            #expect(BackupStore.rollbackPoint(forKey: key) == nil)
            await recording.finish(succeeded: true)
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    /// A success over an earlier install of the app that was cut off: the
    /// point may be that install's way back, so a success that left the old
    /// path empty does not discard it, and the earlier entry stays.
    @Test func aSuccessOverAnEarlierInterruptedInstallKeepsItsWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            let earlier = try store(entry(for: app, owner: try await deadProcess(), damage: .missing), in: scratch)
            let old = installed(app, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: old, route: .homebrew, target: VersionSide(marketing: "2.0")))
            try await InstallJournal.recording(recording) {
                try await InstallCommit.run("brew upgrade") {}
            }
            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: old, journal: recording, succeeded: true) == .kept)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
            await recording.finish(succeeded: true)
            #expect(FileManager.default.fileExists(atPath: earlier.path))
            #expect(!FileManager.default.fileExists(atPath: recording.file.path))
        }
    }

    // MARK: - The commit fact is the recording's, not the disk's (round 4, #5)

    /// The commit ran, but its note could not be written (the journal
    /// directory refused the write). Settle and finish must agree that it ran
    /// — the in-memory fact — and so keep the point of the app it left gone,
    /// rather than reading "no commit" from the file and discarding it.
    @Test func aCommitWhoseNoteFailedToWriteStillKeepsTheWayBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            let old = installed(app, version: "1.0")
            let recording = try #require(await InstallJournal.begin(
                app: old, route: .homebrew, target: VersionSide(marketing: "2.0")))
            #expect(await InstallCoordinator.takeInstallRollbackPoint(old, route: .homebrew))
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scratch.journal.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scratch.journal.path) }
            try await InstallJournal.recording(recording) {
                try await InstallCommit.run("brew upgrade") { try FileManager.default.removeItem(at: app) }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scratch.journal.path)
            let onDisk = try JSONDecoder().decode(
                InstallJournal.Entry.self, from: Data(contentsOf: recording.file))
            try #require(onDisk.committed == nil, "the note's write was meant to fail")
            #expect(recording.snapshot.committed == true)

            #expect(await InstallCoordinator.settleInstallRollbackPoint(for: old, journal: recording, succeeded: false) == .kept)
            #expect(BackupStore.rollbackPoint(forKey: key) != nil)
            await recording.finish(succeeded: false)
            #expect(InstallJournal.interruptedInstalls().map(\.damage) == [.missing])
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

extension InstallJournalTests {

    // MARK: - Restore from a row (`restoreInterrupted`)

    /// The app was cut off, then came back by itself before Restore was
    /// clicked (the store finished writing): the click looks again first and
    /// restores nothing over it.
    /// Mutation: skip the `processLeftovers` re-check → the stale verdict
    /// stands and 1.0 is restored over the 2.0 that landed, red.
    @Test func aRestoreLooksAgainFirstAndLeavesAnAppThatReadsAgain() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            _ = try await process(scratch)
            try #require(InstallJournal.interruptedInstalls().count == 1)

            try makeApp(in: scratch.apps, version: "2.0")
            let outcome = try await InstallJournal.restoreInterrupted(
                at: app, lock: scratch.lock, cleanup: Self.noMounts)
            #expect(outcome == .noLongerInterrupted)
            #expect(InstallJournal.versions(at: app).marketing == "2.0")
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    /// Still gone: restored from the rollback point, put back where nothing
    /// is, and the interrupted install is cleared.
    @Test func aRestoreOfAMissingAppPutsItBack() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            _ = try await process(scratch)

            let outcome = try await InstallJournal.restoreInterrupted(
                at: app, lock: scratch.lock, cleanup: Self.noMounts)
            guard case .restored(let restored) = outcome else {
                Issue.record("not restored: \(outcome)")
                return
            }
            #expect(restored.version == "1.0")
            #expect(InstallJournal.versions(at: app).marketing == "1.0")
            #expect(InstallJournal.interruptedInstalls().isEmpty)
        }
    }

    /// Cut off with nothing kept: no restore, and the answer says why.
    @Test func aRestoreWithNoWayBackSaysSo() async throws {
        try await withScratch { scratch in
            let app = scratch.apps.appendingPathComponent("ZZFixture-Journal.app")
            try store(entry(for: app, owner: try await deadProcess()), in: scratch)
            _ = try await process(scratch)
            try #require(InstallJournal.interruptedInstalls().first?.restoreFrom == nil)

            let outcome = try await InstallJournal.restoreInterrupted(
                at: app, lock: scratch.lock, cleanup: Self.noMounts)
            #expect(outcome == .noWayBack)
            #expect(InstallJournal.interruptedInstalls().count == 1)
        }
    }

    /// A file whose owner is gone but whose child still runs is an orphaned
    /// child — what a host watches for to process again once it exits; one
    /// whose owner runs (this process) is not, and neither is one whose child
    /// has exited.
    /// Mutation: drop `!ownerIsRunning` → the live-owner case red; drop
    /// `childIsRunning` → the exited-child case red.
    @Test func anOrphanedChildIsSeenUntilItExits() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            #expect(!InstallJournal.hasOrphanedChild())
            let child = try await LoopingChild(in: scratch.dir)
            let mine = try #require(InstallJournal.ProcessStamp.of(getpid()))
            let live = try store(entry(for: app, owner: mine, child: child.stamp), in: scratch)
            #expect(!InstallJournal.hasOrphanedChild())
            try FileManager.default.removeItem(at: live)

            try store(entry(for: app, owner: try await deadProcess(), child: child.stamp), in: scratch)
            #expect(InstallJournal.hasOrphanedChild())
            try await child.stop()
            #expect(!InstallJournal.hasOrphanedChild())
        }
    }

    /// An install of the app still running — an orphaned child — is not
    /// raced: nothing restored.
    @Test func aRestoreWhileAnInstallOfTheAppRunsWaits() async throws {
        try await withScratch { scratch in
            let app = try makeApp(in: scratch.apps, version: "1.0")
            let key = BackupStore.key(bundleID: bundleID, path: app)
            try await BackupStore.saveInstallRollbackPoint(
                appPath: app, key: key, version: "1.0", bundleID: bundleID)
            try FileManager.default.removeItem(at: app)
            let child = try await LoopingChild(in: scratch.dir)
            try store(entry(for: app, owner: try await deadProcess(), child: child.stamp), in: scratch)

            let outcome = try await InstallJournal.restoreInterrupted(
                at: app, lock: scratch.lock, cleanup: Self.noMounts)
            try await child.stop()
            #expect(outcome == .stillRunning(pid: child.stamp.pid))
            #expect(!FileManager.default.fileExists(atPath: app.path))
        }
    }
}
