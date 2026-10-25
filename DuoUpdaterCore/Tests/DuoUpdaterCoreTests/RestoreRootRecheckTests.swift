import Foundation
import Testing
@testable import DuoUpdaterCore

/// A restore's privileged route: root re-checks the copy it made, against the
/// installed copy's designated requirement, and a restore with nothing to check
/// against does not take that route at all.
///
/// The Swift gates run on a scratch copy in this user's temporary directory and
/// root then copies it from there, so anything running as this user could put
/// something else in its place between the two. No password panel is ever
/// raised: the elevated route runs through `InPlaceSwap.elevatedShellOverride`,
/// which either runs the shell as this user (the parent folder made writable
/// again first) or only records that it was reached.
@Suite struct RestoreRootRecheckTests {

    static let team = "ZZTEAM0005"
    static let identifier = "zz.duoupdater.restore"
    static let appName = "ZZRestore.app"

    /// Records each shell the elevated route was asked to run.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var shells: [String] = []
        func add(_ shell: String) { lock.withLock { shells.append(shell) } }
        var all: [String] { lock.withLock { shells } }
    }

    struct Fixture {
        let dir: URL
        let apps: URL
        let store: URL
        let target: URL
        let vendor: SelfSignedCodeSigner.Identity
        var key: String { BackupStore.key(bundleID: RestoreRootRecheckTests.identifier, path: target) }
    }

    /// A scratch tree: `apps/` holds the target, `store/` the backup store.
    private func withFixture(_ label: String, _ body: (Fixture) async throws -> Void) async throws {
        let fm = FileManager.default
        let dir = try DigestOnlyInstallTests.scratch("restore-root-\(label)")
        let apps = dir.appendingPathComponent("apps", isDirectory: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        defer {
            chmod(apps.path, 0o755)
            try? fm.removeItem(at: dir)
        }
        let vendor = try await SelfSignedCodeSigner.mint(team: Self.team, label: "vendor", in: dir)
        let fixture = Fixture(
            dir: dir, apps: apps, store: dir.appendingPathComponent("store", isDirectory: true),
            target: apps.appendingPathComponent(Self.appName), vendor: vendor)
        try await body(fixture)
    }

    @discardableResult
    private func signed(_ url: URL, build: String, with identity: SelfSignedCodeSigner.Identity) async throws -> URL {
        try await SelfSignedCodeSigner.makeSignedApp(
            at: url, identifier: Self.identifier, build: build, team: Self.team, with: identity)
    }

    private func build(of app: URL) -> String? {
        SignatureVerifier.infoPlist(of: app)["CFBundleVersion"] as? String
    }

    /// What `privilegedReplacementShell`/`privilegedPlacementShell` would do as
    /// root, done as this user: the parent is made writable again (the test made
    /// it read-only to send the restore down the elevated route), then the shell
    /// runs. `beforeRunning` is the moment between the Swift gates and root's
    /// copy — the window this suite is about.
    private func runAsThisUser(
        _ fixture: Fixture, calls: Calls, beforeRunning: @escaping @Sendable () throws -> Void = {}
    ) -> @Sendable (String) async throws -> ChildProcess.Outcome {
        let apps = fixture.apps
        return { shell in
            calls.add(shell)
            chmod(apps.path, 0o755)
            try beforeRunning()
            return try await ChildProcess.run("/bin/sh", ["-c", shell], onCancel: .runToCompletion)
        }
    }

    /// Records, runs nothing, reports failure.
    private func recordOnly(_ calls: Calls) -> @Sendable (String) async throws -> ChildProcess.Outcome {
        { shell in
            calls.add(shell)
            return try await ChildProcess.run("/usr/bin/false", [], onCancel: .runToCompletion)
        }
    }

    /// The restore's own scratch copy of the backup, found while the restore is
    /// suspended in the elevated route.
    private static func scratchCopy(forKey key: String) throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let dirs = try fm.contentsOfDirectory(atPath: tmp.path)
            .filter { $0.hasPrefix("DuoUpdater-rollback-\(key)-") }
        guard dirs.count == 1 else {
            throw SelfSignedCodeSigner.Failure(description: "expected one scratch copy, found \(dirs)")
        }
        return tmp.appendingPathComponent(dirs[0]).appendingPathComponent(appName)
    }

    /// The installed copy at build 1 is backed up, then updated to build 2.
    private func backUpThenUpdate(_ fixture: Fixture) async throws -> URL {
        try await signed(fixture.target, build: "1", with: fixture.vendor)
        let saved = try await BackupStore.save(
            appPath: fixture.target, key: fixture.key, version: "1", bundleID: Self.identifier)
        try FileManager.default.removeItem(at: fixture.target)
        try await signed(fixture.target, build: "2", with: fixture.vendor)
        return saved.bundlePath
    }

    /// Recompute the stored copy's manifest into its sidecar — what anyone who
    /// can write the store can do.
    private func rewriteSidecar(_ fixture: Fixture, bundle: URL) throws {
        let url = fixture.store.appendingPathComponent(fixture.key).appendingPathComponent("backup.json")
        var sidecar = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let manifest = try #require(BackupManifest.compute(for: bundle))
        sidecar["manifest"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest))
        try JSONSerialization.data(withJSONObject: sidecar).write(to: url)
    }

    private static func isUnverifiableRestore(_ error: Error) -> Bool {
        String(describing: type(of: error)) == "UnverifiableRestoreError"
    }

    // MARK: - T1: the copy root makes is re-checked

    /// The backup passes every Swift gate; then, while the restore is in the
    /// elevated route, the scratch copy is replaced by a build of the same
    /// identifier and Team signed with another certificate. Root must refuse
    /// what it copied.
    ///
    /// Mutation: drop the `stagedCheck` the restore hands `replace` → build 9
    /// lands.
    @Test func aCopySwappedAfterTheGatesIsRefusedByRoot() async throws {
        try await withFixture("swap") { fixture in
            let other = try await SelfSignedCodeSigner.mint(team: Self.team, label: "other", in: fixture.dir)
            let forged = fixture.dir.appendingPathComponent("forged/\(Self.appName)")
            try await signed(forged, build: "9", with: other)
            let calls = Calls()
            let key = fixture.key
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                _ = try await backUpThenUpdate(fixture)
                chmod(fixture.apps.path, 0o555)
                let runner = runAsThisUser(fixture, calls: calls) {
                    let scratch = try Self.scratchCopy(forKey: key)
                    try FileManager.default.removeItem(at: scratch)
                    try FileManager.default.copyItem(at: forged, to: scratch)
                }
                try await InPlaceSwap.$elevatedShellOverride.withValue(runner) {
                    await #expect(throws: (any Error).self) {
                        try await BackupStore.restore(forKey: key, over: fixture.target)
                    }
                }
            }
            #expect(calls.all.count == 1, "the restore must have reached the elevated route")
            #expect(build(of: fixture.target) == "2", "the substitute must not land")
            #expect(try stagingLeftovers(in: fixture.apps).isEmpty)
        }
    }

    // MARK: - T2: a faithful copy of an app that writes inside itself still goes back

    /// State written inside the bundle — a sealed resource changed, a file
    /// added — breaks the resource seal of the installed copy and so of any
    /// faithful backup. Root's check must still let it through, and must be
    /// the resource-blind form.
    @Test func aFaithfulBackupOfAStatefulAppIsRestoredThroughTheElevatedRoute() async throws {
        try await withFixture("stateful") { fixture in
            let calls = Calls()
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                try await signed(fixture.target, build: "1", with: fixture.vendor)
                try Data("state".utf8).write(
                    to: fixture.target.appendingPathComponent("Contents/Resources/r.txt"))
                try Data("mmkv".utf8).write(
                    to: fixture.target.appendingPathComponent("Contents/state.mmkv"))
                try await BackupStore.save(
                    appPath: fixture.target, key: fixture.key, version: "1", bundleID: Self.identifier)
                try FileManager.default.removeItem(at: fixture.target)
                try await signed(fixture.target, build: "2", with: fixture.vendor)
                chmod(fixture.apps.path, 0o555)
                try await InPlaceSwap.$elevatedShellOverride.withValue(runAsThisUser(fixture, calls: calls)) {
                    let version = try await BackupStore.restore(forKey: fixture.key, over: fixture.target)
                    #expect(version == "1")
                }
            }
            #expect(build(of: fixture.target) == "1")
            let shell = try #require(calls.all.first)
            #expect(shell.contains("/usr/bin/codesign --verify --ignore-resources --all-architectures -R "),
                    "root must re-check the copy: \(shell)")
            #expect(!shell.contains("--deep"), "a resource-validating check refuses this app: \(shell)")
            #expect(!shell.contains("--strict"), "a resource-validating check refuses this app: \(shell)")
        }
    }

    // MARK: - T3: Contents/MacOS pointing out of the bundle

    /// A genuine copy, outside the bundle, that `Contents/MacOS` points into:
    /// every signature check passes on it, and once placed the executable it
    /// resolves to is whatever that outside file is later made into.
    private func macOSLinkedOut(_ genuine: URL, in dir: URL) throws -> URL {
        let fm = FileManager.default
        let outside = dir.appendingPathComponent("outside/\(Self.appName)")
        try fm.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: genuine, to: outside)
        let macOS = genuine.appendingPathComponent("Contents/MacOS")
        try fm.removeItem(at: macOS)
        try fm.createSymbolicLink(at: macOS, withDestinationURL: outside.appendingPathComponent("Contents/MacOS"))
        return genuine
    }

    /// End to end: the stored copy's `Contents/MacOS` is replaced by a link out
    /// of the bundle and the sidecar rewritten to match. It must not be put back.
    @Test func aBackupWhoseMacOSFolderLinksOutIsNotRestored() async throws {
        try await withFixture("macos-link") { fixture in
            let calls = Calls()
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                let stored = try await backUpThenUpdate(fixture)
                _ = try macOSLinkedOut(stored, in: fixture.dir)
                try rewriteSidecar(fixture, bundle: stored)
                chmod(fixture.apps.path, 0o555)
                try await InPlaceSwap.$elevatedShellOverride.withValue(runAsThisUser(fixture, calls: calls)) {
                    await #expect(throws: (any Error).self) {
                        try await BackupStore.restore(forKey: fixture.key, over: fixture.target)
                    }
                }
            }
            #expect(build(of: fixture.target) == "2")
            let macOS = fixture.target.appendingPathComponent("Contents/MacOS")
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: macOS.path)) == nil)
        }
    }

    /// The Swift gate alone refuses it.
    ///
    /// Mutation: drop the symlink check in `verifyRestoreAuthenticity` → passes.
    @Test func theSwiftGateRefusesAMacOSFolderThatLinksOut() async throws {
        try await withFixture("macos-link-swift") { fixture in
            try await signed(fixture.target, build: "2", with: fixture.vendor)
            let staged = try await signed(
                fixture.dir.appendingPathComponent("staged/\(Self.appName)"), build: "1", with: fixture.vendor)
            _ = try macOSLinkedOut(staged, in: fixture.dir)
            let target = fixture.target
            await #expect(throws: BackupStore.BackupError.self) {
                try await offCooperativePool { _ = try BackupStore.verifyRestoreAuthenticity(staged: staged, over: target) }
            }
        }
    }

    /// Root's own check refuses it, on its own copy: the requirement is taken
    /// from the genuine copy, then `Contents/MacOS` is linked out — what a
    /// substitute put in the scratch copy's place after the Swift gates looks
    /// like. `codesign --ignore-resources` alone passes it.
    ///
    /// Mutation: drop the `test ! -L` clauses from `stagedCopyCheck` → it lands.
    @Test func rootRefusesACopyWhoseMacOSFolderLinksOut() async throws {
        try await withFixture("macos-link-root") { fixture in
            try await signed(fixture.target, build: "2", with: fixture.vendor)
            let staged = try await signed(
                fixture.dir.appendingPathComponent("staged/\(Self.appName)"), build: "1", with: fixture.vendor)
            let target = fixture.target
            let check = try #require(
                try await offCooperativePool { try BackupStore.verifyRestoreAuthenticity(staged: staged, over: target) })
            #expect(!check.validatesResources)
            _ = try macOSLinkedOut(staged, in: fixture.dir)

            let replace = InPlaceSwap.privilegedReplacementShell(newApp: staged, target: target, requirement: check)
            #expect(try await SelfSignedCodeSigner.shell(replace) != 0)
            #expect(build(of: target) == "2")
            let gone = fixture.apps.appendingPathComponent("ZZGone.app")
            let place = InPlaceSwap.privilegedPlacementShell(newApp: staged, target: gone, requirement: check)
            #expect(try await SelfSignedCodeSigner.shell(place) != 0)
            #expect(!FileManager.default.fileExists(atPath: gone.path))
            #expect(try stagingLeftovers(in: fixture.apps).isEmpty)
        }
    }

    // MARK: - T4: the Swift gate's structural checks

    /// The main executable, or the whole `Contents`, linked out of the bundle.
    /// `kSecCSStrictValidate` refuses both without validating resources.
    ///
    /// Mutation: drop `kSecCSStrictValidate` from `checkValidity` → both pass.
    @Test func theSwiftGateRefusesAMainExecutableOrContentsThatLinksOut() async throws {
        try await withFixture("strict") { fixture in
            let fm = FileManager.default
            try await signed(fixture.target, build: "2", with: fixture.vendor)
            let outside = try await signed(
                fixture.dir.appendingPathComponent("outside/\(Self.appName)"), build: "1", with: fixture.vendor)

            let exeLinked = fixture.dir.appendingPathComponent("exe/\(Self.appName)")
            try fm.createDirectory(at: exeLinked.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: outside, to: exeLinked)
            let exe = exeLinked.appendingPathComponent("Contents/MacOS/zz")
            try fm.removeItem(at: exe)
            try fm.createSymbolicLink(at: exe, withDestinationURL: outside.appendingPathComponent("Contents/MacOS/zz"))

            let contentsLinked = fixture.dir.appendingPathComponent("contents/\(Self.appName)")
            try fm.createDirectory(at: contentsLinked, withIntermediateDirectories: true)
            try fm.createSymbolicLink(
                at: contentsLinked.appendingPathComponent("Contents"),
                withDestinationURL: outside.appendingPathComponent("Contents"))

            let target = fixture.target
            for staged in [exeLinked, contentsLinked] {
                await #expect(throws: BackupStore.BackupError.self, "\(staged.deletingLastPathComponent().lastPathComponent)") {
                    try await offCooperativePool { _ = try BackupStore.verifyRestoreAuthenticity(staged: staged, over: target) }
                }
            }
            // Vacuity guard: the genuine copy itself passes.
            try await offCooperativePool { _ = try BackupStore.verifyRestoreAuthenticity(staged: outside, over: target) }
        }
    }

    // MARK: - T5: no installed signature to check against

    /// The app is gone and its folder needs an administrator: nothing on this
    /// Mac that this user cannot rewrite says what the backup should be, so the
    /// elevated route is not taken — and no panel is raised.
    ///
    /// Mutation: drop the refusal in `placeBack` → the elevated route is reached.
    @Test func aRestoreWithNothingToCheckAgainstDoesNotElevateIntoAMissingApp() async throws {
        try await withFixture("absent") { fixture in
            let calls = Calls()
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                try await signed(fixture.target, build: "1", with: fixture.vendor)
                try await BackupStore.save(
                    appPath: fixture.target, key: fixture.key, version: "1", bundleID: Self.identifier)
                try FileManager.default.removeItem(at: fixture.target)
                chmod(fixture.apps.path, 0o555)
                try await InPlaceSwap.$elevatedShellOverride.withValue(recordOnly(calls)) {
                    do {
                        _ = try await BackupStore.restore(forKey: fixture.key, over: fixture.target)
                        Issue.record("restored with nothing to check the backup against")
                    } catch {
                        #expect(Self.isUnverifiableRestore(error), "\(error)")
                    }
                }
            }
            #expect(calls.all.isEmpty, "the elevated route must not be reached")
            #expect(!FileManager.default.fileExists(atPath: fixture.target.path))
        }
    }

    /// Over an ad-hoc installed copy that needs an administrator to replace.
    ///
    /// Mutation: drop the refusal in `replace` → the elevated route is reached.
    @Test func aRestoreWithNothingToCheckAgainstDoesNotElevateOverAnAdHocApp() async throws {
        try await withFixture("adhoc") { fixture in
            let calls = Calls()
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                try await DigestOnlyInstallTests.makeApp(
                    at: fixture.target, bundleID: Self.identifier, build: "1", signing: .sealed(identifier: nil))
                try await BackupStore.save(
                    appPath: fixture.target, key: fixture.key, version: "1", bundleID: Self.identifier)
                try FileManager.default.removeItem(at: fixture.target)
                try await DigestOnlyInstallTests.makeApp(
                    at: fixture.target, bundleID: Self.identifier, build: "2", signing: .sealed(identifier: nil))
                chmod(fixture.apps.path, 0o555)
                try await InPlaceSwap.$elevatedShellOverride.withValue(recordOnly(calls)) {
                    do {
                        _ = try await BackupStore.restore(forKey: fixture.key, over: fixture.target)
                        Issue.record("restored with nothing to check the backup against")
                    } catch {
                        #expect(Self.isUnverifiableRestore(error), "\(error)")
                    }
                }
            }
            #expect(calls.all.isEmpty, "the elevated route must not be reached")
            #expect(build(of: fixture.target) == "2")
        }
    }

    /// Where no administrator is needed nothing changes: the interrupted-install
    /// case — the app gone from a folder this user can write — still restores.
    @Test func aRestoreWithNothingToCheckAgainstStillWorksWithoutElevation() async throws {
        try await withFixture("absent-writable") { fixture in
            let calls = Calls()
            try await BackupStore.$rootOverride.withValue(fixture.store) {
                try await signed(fixture.target, build: "1", with: fixture.vendor)
                try await BackupStore.save(
                    appPath: fixture.target, key: fixture.key, version: "1", bundleID: Self.identifier)
                try FileManager.default.removeItem(at: fixture.target)
                try await InPlaceSwap.$elevatedShellOverride.withValue(recordOnly(calls)) {
                    let version = try await BackupStore.restore(forKey: fixture.key, over: fixture.target)
                    #expect(version == "1")
                }
            }
            #expect(calls.all.isEmpty)
            #expect(build(of: fixture.target) == "1")
        }
    }

    private func stagingLeftovers(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(InPlaceSwap.privilegedStagingInfix) }
    }
}
