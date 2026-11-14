import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct PackageHelperExecutionTests {
    @Test func helperCompletionIsAppliedAndDoesNotOpenInstaller() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let opened = Calls()
        let executed = Calls()
        let installer = PackageInstaller(opener: { await opened.add($0) }, packageGate: { _, _ in })
        let outcome = try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
            onStage: { _ in }, executor: { package, app, fingerprint, progress in
                #expect(app == fixture.app)
                let actual = try PackageInstaller.contentFingerprint(of: package)
                #expect(actual == fingerprint)
                await executed.add(package)
                progress("installer:%100")
            })
        #expect(outcome.applied)
        #expect(await opened.urls.isEmpty)
        #expect(await executed.urls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: outcome.packageURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.package.path))
    }

    @Test func aHelperFailureIsNotReplayedInTheInteractiveInstaller() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let opened = Calls()
        let installer = PackageInstaller(opener: { await opened.add($0) }, packageGate: { _, _ in })
        await #expect(throws: PackageInstaller.PackageError.self) {
            try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
                onStage: { _ in }, executor: { _, _, _, _ in
                    throw PackageInstaller.PackageError.installationFailed("signature rejected")
                })
        }
        #expect(await opened.urls.isEmpty)
    }

    @Test func aPackageThatRequiresInteractionFallsBackOnlyForManualWork() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let opened = Calls()
        let installer = PackageInstaller(opener: { await opened.add($0) }, packageGate: { _, _ in })
        let executor: PackageInstaller.Executor = { _, _, _, _ in
            throw PackageInstaller.PackageError.requiresInteractiveInstaller("Requires a restart")
        }
        let manual = try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
            onStage: { _ in }, executor: executor)
        #expect(!manual.applied)
        #expect(await opened.urls.count == 1)
        await AutomaticInstall.$active.withValue(true) {
            await AutomaticInstall.$permission.withValue({ true }) {
                await AutomaticInstall.$packageProcesses.withValue({ [Self.unrelatedProcess] }) {
                    await #expect(throws: AutomaticInstall.Deferred.self) {
                        try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
                            onStage: { _ in }, executor: executor)
                    }
                }
            }
        }
        #expect(await opened.urls.count == 1)
    }

    @Test func cancellingBeforeTheCommitNeverCallsTheHelper() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let calls = Calls()
        let gate = Gate()
        let installer = PackageInstaller(opener: { _ in Issue.record("Unexpected Installer") }, packageGate: { _, _ in })
        let task = Task {
            try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
                onStage: { _ in }, beforeOpen: { await gate.pause() }, executor: { url, _, _, _ in
                    await calls.add(url)
                })
        }
        await gate.waitForArrival()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await calls.urls.isEmpty)
    }

    @Test func cancellingAfterTheCommitStillWaitsForTheHelperToFinish() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let gate = Gate()
        let completed = Calls()
        let installer = PackageInstaller(opener: { _ in Issue.record("Unexpected Installer") }, packageGate: { _, _ in })
        let task = Task {
            try await installer.downloadAndOpen(url: fixture.package, installedApp: fixture.app,
                onStage: { _ in }, executor: { url, _, _, _ in
                    await gate.pause()
                    try Task.checkCancellation()
                    await completed.add(url)
                })
        }
        await gate.waitForArrival()
        task.cancel()
        await gate.release()
        #expect(try await task.value.applied)
        #expect(await completed.urls.count == 1)
    }

    @Test func onlyAnAvailablePackageExecutorExtendsTheUnattendedRoutes() {
        for route in InstallCoordinator.Route.allCases {
            #expect(AutomaticInstall.supports(route, packageInstallerAvailable: true)
                    == [.vendor, .sparkle, .installer].contains(route))
        }
        #expect(!AutomaticInstall.supports(.installer))
    }

    private static let unrelatedProcess = NestedAppGuard.RunningProcess(pid: 7, parentPID: 1,
        executablePath: "/usr/bin/true", isRegularApp: false)

    private actor Calls {
        var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }

    private actor Gate {
        private var arrived = false
        private var released = false
        private var waiting: CheckedContinuation<Void, Never>?
        private var arrivals: [CheckedContinuation<Void, Never>] = []
        func pause() async {
            arrived = true
            arrivals.forEach { $0.resume() }
            arrivals.removeAll()
            if released { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func waitForArrival() async {
            if arrived { return }
            await withCheckedContinuation { arrivals.append($0) }
        }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }

    private struct Fixture: Sendable {
        let root: URL
        let package: URL
        let app: URL
        let prefix: String
        init() throws {
            let name = "PkgExecutor-\(UUID().uuidString)"
            prefix = "DuoUpdater-pkg-\(name)-"
            root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            package = root.appendingPathComponent("update.pkg")
            app = URL(fileURLWithPath: "/Applications/\(name).app")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try Data("package bytes".utf8).write(to: package)
        }
        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            let temporary = FileManager.default.temporaryDirectory
            let entries = (try? FileManager.default.contentsOfDirectory(at: temporary,
                includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
                guard entry.deletingLastPathComponent().standardizedFileURL == temporary.standardizedFileURL else { continue }
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
