import Foundation
import Testing
@testable import DuoUpdaterCore

struct AutomaticUpdateDiagnosticsTests {
    private func event(_ fields: [String: String], at date: Date = Date()) throws -> DuoEvent {
        DuoEvent(date: date, payload: .unknown(kind: "automaticUpdate",
            json: String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)))
    }

    @Test func repeatedBlockerIsStoredOnceWithAffectedAttemptsAndTimes() {
        let pass = AutomaticUpdateDiagnostics()
        let blocker = AutomaticProcessDiagnostic(kind: .unresolvedIdentity, pid: 123,
            probes: [.init(.pidPath, 0, ENOENT)])
        pass.record(blocker, attemptID: "a", now: Date(timeIntervalSince1970: 10))
        pass.record(blocker, attemptID: "a", now: Date(timeIntervalSince1970: 11))
        pass.record(blocker, attemptID: "b", now: Date(timeIntervalSince1970: 12))
        #expect(pass.snapshot.count == 1)
        #expect(pass.snapshot.first?.occurrences == 3)
        #expect(pass.snapshot.first?.attempts == ["a", "b"])
        #expect(pass.snapshot.first?.first == Date(timeIntervalSince1970: 10))
        #expect(pass.snapshot.first?.last == Date(timeIntervalSince1970: 12))
        #expect(pass.references(for: "a") == pass.references(for: "b"))
    }

    @Test func enumerationFailuresAndTruncationFailClosedWithCapturedErrors() {
        let bundle = URL(fileURLWithPath: "/Applications/Example.app")
        NestedAppGuard.$listPIDs.withValue({ _, _ in errno = EACCES; return 0 }) {
            var diagnostics: [AutomaticProcessDiagnostic] = []
            let processes = NestedAppGuard.liveProcesses(includeUninspectable: true) { diagnostics.append($0) }
            #expect(diagnostics.first?.kind == .enumerationFailed)
            #expect(diagnostics.first?.probes == [.init(.listSize, 0, EACCES)])
            #expect(throws: AutomaticInstall.Deferred.self) {
                try AutomaticInstall.checkProcesses(at: bundle, processes: processes)
            }
        }
        NestedAppGuard.$listPIDs.withValue({ buffer, _ in
            if buffer == nil { return 1 }
            errno = EIO; return 0
        }) {
            var diagnostics: [AutomaticProcessDiagnostic] = []
            _ = NestedAppGuard.liveProcesses(includeUninspectable: true) { diagnostics.append($0) }
            #expect(diagnostics.first?.kind == .enumerationFailed)
            #expect(diagnostics.first?.probes == [.init(.listPIDs, 0, EIO)])
        }
        NestedAppGuard.$listPIDs.withValue({ buffer, bytes in
            buffer == nil ? 1 : bytes / Int32(MemoryLayout<pid_t>.size)
        }) {
            var diagnostics: [AutomaticProcessDiagnostic] = []
            let processes = NestedAppGuard.liveProcesses(includeUninspectable: true) { diagnostics.append($0) }
            #expect(diagnostics.first?.kind == .enumerationTruncated)
            #expect(processes.count == 1)
            #expect(throws: AutomaticInstall.Deferred.self) {
                try AutomaticInstall.checkProcesses(at: bundle, processes: processes)
            }
        }
    }

    @Test func classificationDoesNotConfuseExitPermissionAndUnknown() {
        #expect(AutomaticProcessDiagnostic.unresolvedKind(alive: false, lifecycleState: nil,
            probes: [.init(.existence, -1, ESRCH), .init(.lifecycleInfo, 0, ESRCH)]) == .exited)
        #expect(AutomaticProcessDiagnostic.unresolvedKind(alive: true, lifecycleState: nil,
            probes: [.init(.pidPath, 0, EACCES)]) == .permissionDenied)
        #expect(AutomaticProcessDiagnostic.unresolvedKind(alive: true, lifecycleState: nil,
            probes: [.init(.pidPath, 0, ENOENT)]) == .unresolvedIdentity)
        #expect(AutomaticProcessDiagnostic.unresolvedKind(alive: true, lifecycleState: UInt32(SZOMB),
            probes: [.init(.pidPath, 0, ESRCH)]) == .zombie)
    }

    @Test func historySurvivesReloadAndEndsChainAfterSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.sqlite")
        let store = EventStore(fileURL: url, now: { Date(timeIntervalSince1970: 30) })
        let deferred = try event(["appID": "private-copy", "toVersion": "2", "status": "deferred",
            "attemptID": "first", "chainID": "first"], at: Date(timeIntervalSince1970: 10))
        await store.append(deferred)
        await store.flush()
        let reloaded = EventStore(fileURL: url, now: { Date(timeIntervalSince1970: 30) })
        let history = await reloaded.events(.init(kind: "automaticUpdate", limit: 100))
        #expect(AutomaticUpdateDiagnostics.predecessor(in: history, appID: "private-copy", version: "2")?["attemptID"] == "first")
        #expect(AutomaticUpdateDiagnostics.predecessor(in: history, appID: "other-copy", version: "2") == nil)
        #expect(AutomaticUpdateDiagnostics.predecessor(in: history, appID: "private-copy", version: "3") == nil)
        let installed = try event(["appID": "private-copy", "toVersion": "2", "status": "installed",
            "attemptID": "second", "recoveredFrom": "first"], at: Date(timeIntervalSince1970: 20))
        #expect(AutomaticUpdateDiagnostics.predecessor(in: history + [installed], appID: "private-copy", version: "2") == nil)
    }

    @Test func sanitizedExportCannotContainIdentityOrFreeText() throws {
        let pass = AutomaticUpdateDiagnostics()
        pass.record(.init(kind: .permissionDenied, pid: 87654, parentPID: 45678,
            lifecycleState: 2, processName: "private-process", probes: [.init(.pidPath, 0, EACCES)]), attemptID: "sensitive-attempt")
        let events = [try event(["appID": "/Users/private/Private.app", "appName": "PrivateApp",
            "reason": "credential-secret", "status": "installed", "recoveredFrom": "sensitive-attempt"]),
            try event(["status": "diagnostics", "passID": pass.passID, "diagnostics": pass.json])]
        let report = AutomaticUpdateDiagnostics.sanitizedReport(events)
        for secret in ["/Users", "private-process", "PrivateApp", "credential-secret", "sensitive-attempt", "87654", "45678", pass.passID, "first", "last"] {
            #expect(!report.contains(secret))
        }
        #expect(report.contains("permissionDenied"))
        #expect(report.contains("recovered"))
        #expect(report.contains("pidPath"))
    }

    @Test func unidentifiedLiveProcessStillPreventsFileExchange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Target.app")
        let incoming = root.appendingPathComponent("Incoming.app")
        for bundle in [target, incoming] {
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        }
        let marker = target.appendingPathComponent("version")
        try Data("old".utf8).write(to: marker)
        try Data("new".utf8).write(to: incoming.appendingPathComponent("version"))
        // The test process is verifiably alive; model both identity probes failing.
        #expect(kill(getpid(), 0) == 0)
        let unknown = NestedAppGuard.RunningProcess(pid: getpid(), parentPID: getppid(),
            executablePath: nil, isRegularApp: false)
        await InPlaceSwap.$preExchangeCheck.withValue({
            try AutomaticInstall.checkProcesses(at: target, processes: [unknown])
        }) {
            await #expect(throws: AutomaticInstall.Deferred.self) {
                try await InPlaceSwap.replace(newApp: incoming, over: target)
            }
        }
        #expect(try Data(contentsOf: marker) == Data("old".utf8))
    }

    @Test func realZombieIsDiagnosedAndDoesNotBlockAutomaticInstall() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appendingPathComponent("pid")
        let release = root.appendingPathComponent("reap")
        let script = """
        my $p = fork(); die "fork" unless defined $p;
        if (!$p) { exit 0; }
        open(my $f, '>', $ARGV[0]) or die $!; print $f $p; close $f;
        for (1..6000) { last if -e $ARGV[1]; select(undef, undef, undef, 0.01); }
        waitpid($p, 0);
        """
        let child = Task {
            try await ChildProcess.run("/usr/bin/perl", ["-e", script, pidFile.path, release.path],
                standardOutput: .discard, standardError: .discard, onCancel: .terminateChild)
        }
        do {
            var pid: Int32?
            for _ in 0..<200 {
                if let value = try? String(contentsOf: pidFile, encoding: .utf8), let number = Int32(value) { pid = number; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let zombiePID = try #require(pid)
            var diagnostic: AutomaticProcessDiagnostic?
            var observed: [NestedAppGuard.RunningProcess] = []
            for _ in 0..<100 {
                observed = NestedAppGuard.liveProcesses(includeUninspectable: true) {
                    if $0.pid == zombiePID { diagnostic = $0 }
                }
                if diagnostic?.kind == .zombie { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let blocker = try #require(diagnostic)
            #expect(blocker.kind == .zombie)
            #expect(blocker.parentPID != nil)
            #expect(blocker.processName == "perl")
            #expect(blocker.lifecycleState == UInt32(SZOMB))
            #expect(blocker.probes.contains { $0.name == .pidPath && $0.result == 0 && $0.error != 0 })
            #expect(blocker.probes.contains { $0.name == .procargsSize })
            #expect(!observed.contains { $0.pid == zombiePID })
            #expect(kill(zombiePID, 0) == 0, "Fixture must remain unreaped throughout installation")
            // No diagnostic callback: lifecycle policy must still run. A failed
            // or partial answer must never treat its buffer as confirmed SZOMB.
            for partial in [false, true] {
                NestedAppGuard.$lifecycleInfo.withValue({ _, buffer, size in
                    buffer.assumingMemoryBound(to: proc_bsdshortinfo.self).pointee.pbsi_status = UInt32(SZOMB)
                    errno = partial ? 0 : EPERM
                    return partial ? size - 1 : 0
                }) {
                    let unresolved = NestedAppGuard.liveProcesses(includeUninspectable: true)
                        .filter { $0.pid == zombiePID || $0.pid == getpid() }
                    #expect(unresolved.contains { $0.pid == zombiePID && $0.executablePath == nil })
                    #expect(throws: AutomaticInstall.Deferred.self) {
                        try AutomaticInstall.checkProcesses(at: root, processes: unresolved)
                    }
                }
            }
            let target = root.appendingPathComponent("Target.app")
            let incoming = root.appendingPathComponent("Incoming.app")
            for bundle in [target, incoming] {
                try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            }
            try Data("old".utf8).write(to: target.appendingPathComponent("version"))
            try Data("new".utf8).write(to: incoming.appendingPathComponent("version"))
            // Scope the fixture to its two owned PIDs so unrelated host blockers
            // cannot make the recovery assertion vacuously fail.
            let guardFixture: @Sendable () throws -> Void = {
                let processes = NestedAppGuard.liveProcesses(includeUninspectable: true)
                    .filter { $0.pid == zombiePID || $0.pid == getpid() }
                try AutomaticInstall.checkProcesses(at: target, processes: processes)
            }
            try await InPlaceSwap.$preExchangeCheck.withValue(guardFixture) {
                try await InPlaceSwap.replace(newApp: incoming, over: target)
            }
            #expect(kill(zombiePID, 0) == 0, "Success must not depend on reaping the zombie")
            try Data().write(to: release)
            _ = try await child.value
            #expect(!NestedAppGuard.liveProcesses(includeUninspectable: true).contains { $0.pid == zombiePID })
            #expect(try Data(contentsOf: target.appendingPathComponent("version")) == Data("new".utf8))
            print("1866 live zombie: probes=\(blocker.probes), state=\(blocker.lifecycleState ?? 0); installation succeeded while zombie remained unreaped; then reaped")
        } catch {
            try? Data().write(to: release)
            _ = await child.result
            throw error
        }
    }
}
