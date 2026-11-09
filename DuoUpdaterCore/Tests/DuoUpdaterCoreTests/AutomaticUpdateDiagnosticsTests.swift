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

    @Test func aDeferralIsWrittenOnceUntilItsVersionOrReasonChanges() throws {
        let waiting = try event(["appID": "a", "toVersion": "2", "status": "deferred",
            "reason": "running", "attemptID": "1"], at: Date(timeIntervalSince1970: 10))
        let history = AutomaticUpdateDiagnostics.History([waiting])
        #expect(history.repeatsLastDeferral(appID: "a", version: "2", reason: "running"))
        #expect(!history.repeatsLastDeferral(appID: "a", version: "2", reason: "in front"))
        #expect(!history.repeatsLastDeferral(appID: "a", version: "3", reason: "running"))
        #expect(!history.repeatsLastDeferral(appID: "b", version: "2", reason: "running"))
        // Once anything else happened to the app, the same wait is news again.
        let failed = try event(["appID": "a", "toVersion": "2", "status": "notInstalled",
            "attemptID": "2"], at: Date(timeIntervalSince1970: 20))
        #expect(!AutomaticUpdateDiagnostics.History([waiting, failed])
            .repeatsLastDeferral(appID: "a", version: "2", reason: "running"))
    }

    @Test func onlyAFailedOrCutOffAttemptMakesAnInstallARecovery() throws {
        let deferred = try event(["appID": "a", "toVersion": "2", "status": "deferred",
            "attemptID": "1"], at: Date(timeIntervalSince1970: 10))
        #expect(!AutomaticUpdateDiagnostics.History([deferred]).recovers(appID: "a", version: "2"))
        let failed = try event(["appID": "a", "toVersion": "2", "status": "notInstalled",
            "attemptID": "2"], at: Date(timeIntervalSince1970: 20))
        #expect(AutomaticUpdateDiagnostics.History([deferred, failed]).recovers(appID: "a", version: "2"))
        // Started and never finished: DuoUpdater quit mid-install.
        let started = try event(["appID": "a", "toVersion": "3", "status": "started",
            "attemptID": "3"], at: Date(timeIntervalSince1970: 30))
        #expect(AutomaticUpdateDiagnostics.History([started]).recovers(appID: "a", version: "3"))
        let finished = try event(["appID": "a", "toVersion": "3", "status": "deferred",
            "attemptID": "3"], at: Date(timeIntervalSince1970: 31))
        #expect(!AutomaticUpdateDiagnostics.History([started, finished]).recovers(appID: "a", version: "3"))
        // An install ends the trouble for the next attempt.
        let installed = try event(["appID": "a", "toVersion": "2", "status": "installed",
            "attemptID": "4"], at: Date(timeIntervalSince1970: 40))
        #expect(!AutomaticUpdateDiagnostics.History([deferred, failed, installed]).recovers(appID: "a", version: "2"))
    }

    @Test func discardedAttemptsLeaveNoDiagnostics() {
        let diagnostics = AutomaticUpdateDiagnostics()
        let blocker = AutomaticProcessDiagnostic(kind: .targetRunning, pid: 9, processName: "Helper")
        diagnostics.record(blocker, attemptID: "repeat")
        diagnostics.record(blocker, attemptID: "kept")
        diagnostics.discard(attemptID: "repeat")
        #expect(diagnostics.snapshot.map(\.attempts) == [["kept"]])
        diagnostics.discard(attemptID: "kept")
        #expect(diagnostics.isEmpty)
    }

    @Test func sanitizedExportCannotContainIdentityOrFreeText() throws {
        let pass = AutomaticUpdateDiagnostics()
        pass.record(.init(kind: .permissionDenied, pid: 87654, parentPID: 45678,
            lifecycleState: 2, processName: "private-process", probes: [.init(.pidPath, 0, EACCES)]), attemptID: "sensitive-attempt")
        pass.record(.init(kind: .targetRunning, pid: 87655, processName: "private-helper",
            bundlePath: "Contents/MacOS/private-helper", parentName: "private-parent",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)), attemptID: "sensitive-attempt")
        let events = [try event(["appID": "/Users/private/Private.app", "appName": "PrivateApp",
            "reason": "credential-secret", "status": "installed", "recoveredFrom": "sensitive-attempt"]),
            try event(["status": "diagnostics", "passID": pass.passID, "diagnostics": pass.json])]
        let report = AutomaticUpdateDiagnostics.sanitizedReport(events)
        for secret in ["/Users", "private-process", "PrivateApp", "credential-secret", "sensitive-attempt", "87654", "45678", pass.passID, "first", "last",
                       "private-helper", "Contents/", "private-parent", "startedAt", "2023"] {
            #expect(!report.contains(secret))
        }
        #expect(report.contains("permissionDenied"))
        #expect(report.contains("recovered"))
        #expect(report.contains("pidPath"))
    }

    @Test func runningTargetIsDescribedFromItsSnapshot() throws {
        let bundle = URL(fileURLWithPath: "/Applications/Example.app")
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let parent = NestedAppGuard.RunningProcess(pid: 10, parentPID: 1,
            executablePath: "/Applications/Example.app/Contents/MacOS/Example", isRegularApp: false)
        let helper = NestedAppGuard.RunningProcess(pid: 11, parentPID: 10,
            executablePath: "/Applications/Example.app/Contents/XPCServices/Web.xpc/Contents/MacOS/Web",
            isRegularApp: false, startedAt: started)
        let orphan = NestedAppGuard.RunningProcess(pid: 12, parentPID: 999,
            executablePath: "/Applications/Example.app/Contents/MacOS/Example", isRegularApp: false)
        let snapshot = [parent, helper, orphan]

        let d = AutomaticProcessDiagnostic.targetRunning(helper, in: bundle, among: snapshot)
        #expect(d.kind == .targetRunning)
        #expect(d.pid == 11 && d.parentPID == 10)
        #expect(d.processName == "Web")
        #expect(d.bundlePath == "Contents/XPCServices/Web.xpc/Contents/MacOS/Web")
        #expect(d.parentName == "Example")
        #expect(d.startedAt == started)

        let unknownParent = AutomaticProcessDiagnostic.targetRunning(orphan, in: bundle, among: snapshot)
        #expect(unknownParent.parentName == nil)
        #expect(unknownParent.startedAt == nil)

        // Older records lack the snapshot fields and still decode.
        let old = #"{"kind":"targetRunning","pid":5,"parentPID":1,"probes":[]}"#
        let decoded = try JSONDecoder().decode(AutomaticProcessDiagnostic.self, from: Data(old.utf8))
        #expect(decoded.pid == 5 && decoded.bundlePath == nil && decoded.parentName == nil && decoded.startedAt == nil)
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

struct AutomaticUpdateActivityTests {
    private func event(_ fields: [String: String], at seconds: TimeInterval) throws -> DuoEvent {
        DuoEvent(date: Date(timeIntervalSince1970: seconds), payload: .unknown(kind: "automaticUpdate",
            json: String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)))
    }

    private func diagnostics(_ pass: String, attempts: [String], at seconds: TimeInterval) throws -> DuoEvent {
        let recorder = AutomaticUpdateDiagnostics()
        for attempt in attempts {
            recorder.record(.init(kind: .targetRunning, pid: 42), attemptID: attempt, now: Date(timeIntervalSince1970: seconds))
        }
        return try event(["passID": pass, "status": "diagnostics", "diagnostics": recorder.json], at: seconds)
    }

    private func deferral(_ pass: String, _ attempt: String, at seconds: TimeInterval,
                          reason: String = "running") throws -> DuoEvent {
        try event(["passID": pass, "attemptID": attempt, "chainID": "chain", "appID": "/Applications/Cua.app",
                   "fromVersion": "1", "toVersion": "2", "status": "deferred", "reason": reason], at: seconds)
    }

    @Test func mergesAttemptStatesAndAttachesItsOwnDiagnostics() throws {
        let rows = AutomaticUpdateActivity.rows(from: try [
            event(["passID": "p", "attemptID": "a", "appID": "/A.app", "status": "started"], at: 1),
            deferral("p", "b", at: 2),
            event(["passID": "p", "attemptID": "a", "appID": "/A.app", "status": "installed"], at: 3),
            diagnostics("p", attempts: ["b"], at: 4),
            event(["passID": "q", "status": "diagnostics", "diagnostics": "[]"], at: 5),
        ].reversed())
        #expect(rows.map(\.id) == ["a", "b"])
        #expect(rows[0].status == "installed")
        #expect(rows[0].first == Date(timeIntervalSince1970: 1))
        #expect(rows[0].last == Date(timeIntervalSince1970: 3))
        #expect(rows[0].diagnostics.isEmpty)
        #expect(rows[1].diagnostics.count == 1)
    }

    @Test func repeatedDeferralsCollapseUntilSomethingChanges() throws {
        let rows = AutomaticUpdateActivity.rows(from: try [
            deferral("p1", "a1", at: 1),
            deferral("p2", "a2", at: 2),
            diagnostics("p2", attempts: ["a2"], at: 2.5),
            deferral("p3", "a3", at: 3),
            deferral("p4", "a4", at: 4, reason: "other"),
            deferral("p5", "a5", at: 5),
        ])
        #expect(rows.map(\.count) == [1, 1, 3])
        #expect(rows[2].first == Date(timeIntervalSince1970: 1))
        #expect(rows[2].last == Date(timeIntervalSince1970: 3))
        // The latest attempt's diagnostics, not an earlier one's.
        #expect(rows[2].diagnostics.isEmpty)
    }

    @Test func installsNeverCollapseAndUndecodableDiagnosticsAreKept() throws {
        let rows = AutomaticUpdateActivity.rows(from: try [
            event(["appName": "A", "status": "installed"], at: 1),
            event(["appName": "A", "status": "installed"], at: 2),
            event(["passID": "p", "attemptID": "x", "status": "notInstalled"], at: 3),
            event(["passID": "p", "status": "diagnostics", "diagnostics": "not json"], at: 4),
        ])
        #expect(rows.count == 3)
        #expect(rows[0].undecodedDiagnostics == "not json")
    }
}
