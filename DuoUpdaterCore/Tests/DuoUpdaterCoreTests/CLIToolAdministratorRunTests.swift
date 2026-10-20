import Testing
import Foundation
@testable import DuoUpdaterCore

/// `CLIToolAdministratorRun`: the shell line handed to the administrator panel,
/// and the following of the background run it starts.
///
/// No panel is raised here. Where a run is followed, the "authorization" is a
/// stand-in that runs the very line the panel would be given with `/bin/sh` as
/// this user — so what is checked is the line itself (its environment, its
/// output directory, its backgrounding) and the polling, never root. Run as
/// this user, `mktemp` makes the output directory in the fixture as this
/// user's; that it is root's in `/private/tmp` on a real run is checked from
/// the line and the host's `/private/tmp`, not by running as root.
@Suite struct CLIToolAdministratorRunTests {

    final class Sandbox: @unchecked Sendable {
        let root: URL
        private let lock = NSLock()
        private var shells: [String] = []

        init() throws {
            let made = FileManager.default.temporaryDirectory.appendingPathComponent("ZZFixture-admin-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            root = URL(fileURLWithPath: try #require(LuvusScanner.canonicalPath(made.path)))
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var given: [String] { lock.withLock { shells } }

        /// Runs the line as this user and answers as the panel would have.
        /// Everything the run said and the moment the panel was raised, in order.
        private var events: [String] = []
        var said: [String] { lock.withLock { events } }
        func say(_ line: String) { lock.withLock { events.append("line: " + line) } }

        /// `whilePanelIsUp` is another process of the user's, acting before
        /// the user answers.
        func asUser(answer: CLIToolAdministratorRun.Authorization? = nil,
                    whilePanelIsUp: (@Sendable () -> Void)? = nil) -> CLIToolAdministratorRun.Authorize {
            { shell in
                self.lock.withLock { self.shells.append(shell); self.events.append("panel") }
                whilePanelIsUp?()
                if let answer { return answer }
                guard let (printed, said) = Sandbox.sh(shell) else { return .error(number: 1, message: "sh failed") }
                return printed.isEmpty ? .error(number: 1, message: said) : .authorized(printed)
            }
        }

        /// Runs the line and returns its standard output and error once it
        /// exits: like `do shell script` on it, the shell returns at once, the
        /// command going on in the background. The line prints only on
        /// success, so nothing printed stands for the failure `do shell
        /// script` would raise.
        /// offpool-lint:allow — stands in for the panel's synchronous main-actor
        /// call, so it cannot await `ChildProcess`; it reads only the
        /// foreground line's output, which ends once it backgrounds the command.
        static func sh(_ line: String) -> (String, String)? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            // Under the strictest umask a user may have (`launchctl config user
            // umask 077`), not this process's 022 — so it is the line's own
            // `umask 022` that leaves `log` and `status` readable here.
            process.arguments = ["-c", "umask 077; " + line]
            // What `do shell script` hands root (TN2065: the parent's
            // environment) — the app's, which `env -i` must keep out.
            process.environment = [
                "HOME": "/Users/ZZFixture-ann", "HELM_INSTALL_DIR": "/elsewhere", "PATH": "/usr/bin:/bin",
                "TMPDIR": "/var/folders/ZZFixture/T/",
            ]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            do { try process.run() } catch { return nil }
            let printed = output.fileHandleForReading.readDataToEndOfFile()
            let said = errors.fileHandleForReading.readDataToEndOfFile()
            return (String(decoding: printed, as: UTF8.self), String(decoding: said, as: UTF8.self))
        }

        /// `linger` outlasts every test that does not wait for the removal,
        /// so a late poll still finds the status.
        func shell(answer: CLIToolAdministratorRun.Authorization? = nil, environment: [String: String] = [:],
                   deadline: Duration = .seconds(20), linger: Int = 60,
                   whilePanelIsUp: (@Sendable () -> Void)? = nil) -> CLIToolAdministratorRun.Shell {
            CLIToolAdministratorRun.Shell(
                authorize: asUser(answer: answer, whilePanelIsUp: whilePanelIsUp), workRoot: root,
                environment: { environment }, poll: .milliseconds(20), beforePanel: .zero, linger: linger,
                deadline: ChildProcess.Deadline(terminateAfter: deadline, killAfter: deadline))
        }

        var leftovers: [String] { (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] }
    }

    static func ran(_ result: CLIToolAdministratorRun.Result) -> CLIToolCommandRunner.Run? {
        guard case .ran(let run) = result else { return nil }
        return run
    }

    static func outcome(_ run: CLIToolCommandRunner.Run?) -> ChildProcess.Outcome? {
        guard case .finished(let outcome)? = run?.result else { return nil }
        return outcome
    }

    /// The command's output, line by line, and its exit status; the panel was
    /// asked once; the line made one output directory, readable but writable
    /// only by its owner, with `log` and `status` likewise.
    /// Mutations: drop the final `drain()`; read the status before the line
    /// ends; drop the `chmod 755`; drop the umask.
    @Test func followsTheRunToItsStatus() async throws {
        let box = try Sandbox()
        let lines = LockedLines()
        let result = await box.shell().run("echo one; echo two >&2; exit 3") { lines.append($0) }
        let run = try #require(Self.ran(result))
        #expect(run.lines == ["one", "two"])
        let outcome = try #require(Self.outcome(run))
        #expect(outcome.terminationStatus == 3)
        #expect(!outcome.timedOut)
        #expect(lines.all == ["Waiting for an administrator password…", "Running as root…", "one", "two"])
        #expect(box.given.count == 1)
        #expect(box.leftovers.count == 1)
        let made = try #require(box.leftovers.first)
        #expect(made.hasPrefix(CLIToolAdministratorRun.outputPrefix))
        func mode(_ name: String) throws -> Int {
            let path = box.root.appendingPathComponent(made).appendingPathComponent(name).path
            return try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        }
        #expect(try mode("") == 0o755)
        #expect(try mode("log") == 0o644)
        #expect(try mode("status") == 0o644)
    }

    /// The line deletes its output directory `linger` seconds after the
    /// status — this process cannot delete root's. Only the removal is
    /// checked: under a starved pool the poll may wake after it.
    /// Mutation: drop the `rm -rf`.
    @Test func removesItsOutputDirectoryAfterTheLinger() async throws {
        let box = try Sandbox()
        _ = await box.shell(deadline: .seconds(3), linger: 1).run("echo one") { _ in }
        for _ in 0..<1000 where !box.leftovers.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(box.leftovers.isEmpty)
    }

    /// Root gets root's `HOME`, `/` and umask 022, the system `PATH` with
    /// `/usr/local/bin` last, the proxy variables and nothing else of the app's
    /// environment.
    /// Mutations: drop `env -i`; keep the app's `HOME`; drop the proxy filter.
    @Test func rootGetsItsOwnHomeAndNothingElse() async throws {
        let box = try Sandbox()
        let environment = [
            "https_proxy": "http://127.0.0.1:6152", "NO_PROXY": "localhost", "HOME": "/Users/ZZFixture-ann",
            "HELM_INSTALL_DIR": "/elsewhere",
        ]
        let result = await box.shell(environment: environment).run("pwd; umask; /usr/bin/env | /usr/bin/sort") { _ in }
        let run = try #require(Self.ran(result))
        #expect(run.lines.first == "/")
        #expect(run.lines.dropFirst().first == "0022")
        let env = Set(run.lines.dropFirst(2))
        #expect(env.contains("HOME=/var/root"))
        #expect(env.contains("USER=root"))
        #expect(env.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"))
        #expect(env.contains("https_proxy=http://127.0.0.1:6152"))
        #expect(env.contains("NO_PROXY=localhost"))
        #expect(!env.contains { $0.hasPrefix("HELM_INSTALL_DIR=") })
        #expect(!env.contains { $0.contains("ZZFixture") })
    }

    /// Dismissing the panel is `.declined`; any other refusal carries the
    /// system's words; neither runs anything or leaves anything behind.
    /// Mutation: map every error to `.refused`.
    @Test func aDismissedOrRefusedPanelRunsNothing() async throws {
        let box = try Sandbox()
        let marker = box.root.appendingPathComponent("RAN").path
        let declined = await box.shell(answer: .error(number: -128, message: "User canceled."))
            .run("touch \(marker)") { _ in }
        guard case .declined = declined else { Issue.record("expected declined, got \(declined)"); return }
        let refused = await box.shell(answer: .error(number: -60005, message: "The administrator user name or password was incorrect."))
            .run("touch \(marker)") { _ in }
        guard case .refused(let reason) = refused else { Issue.record("expected refused, got \(refused)"); return }
        #expect(reason == "The administrator user name or password was incorrect.")
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(box.leftovers.isEmpty)
    }

    /// The row is told the panel is coming before it is raised: once
    /// `NSAppleScript` holds the main thread, no later line is drawn until the
    /// user answers. Mutations: drop the line; say it after the panel.
    @Test func saysThePanelIsComingBeforeRaisingIt() async throws {
        let box = try Sandbox()
        _ = await box.shell(answer: .error(number: -128, message: "User canceled.")).run("true") { box.say($0) }
        #expect(box.said == ["line: Waiting for an administrator password…", "panel"])
    }

    /// Whoever bound `CLIToolAdministratorPanel.answered` is told once the
    /// panel has its answer — authorized or dismissed — before the command's
    /// first line, so the app's Update All can raise the next panel without
    /// waiting for this command to finish. An authorized panel's row says
    /// so first (`authorizedLine`), so it does not sit on "Waiting for an
    /// administrator password…" behind the next panel; a dismissed one does not.
    /// Mutations: drop the call; make it after `follow`; drop the
    /// `authorizedLine`; say it for any answer.
    @Test func tellsWhoeverWaitsThatThePanelWasAnswered() async throws {
        let box = try Sandbox()
        let tell: @MainActor @Sendable () -> Void = { box.say("answered") }
        _ = await CLIToolAdministratorPanel.$answered.withValue(tell) {
            await box.shell().run("echo one") { box.say($0) }
        }
        #expect(box.said == ["line: Waiting for an administrator password…", "panel", "line: Running as root…",
                             "line: answered", "line: one"])
        let declined = try Sandbox()
        let tellDeclined: @MainActor @Sendable () -> Void = { declined.say("answered") }
        _ = await CLIToolAdministratorPanel.$answered.withValue(tellDeclined) {
            await declined.shell(answer: .error(number: -128, message: "User canceled.")).run("true") { declined.say($0) }
        }
        #expect(declined.said == ["line: Waiting for an administrator password…", "panel", "line: answered"])
    }

    /// A run still going at the deadline is reported as timed out, not waited on.
    ///
    /// The command lasts until the test lets it go, not for a set time. With
    /// `sleep 2` it read as exit 0, not timed out, on every hosted-runner push
    /// run from #1127 on. Holding every `.medium` pool thread for 3 s reproduces
    /// that locally: the poll's `Task.sleep` wakes after `sleep 2` has written
    /// exit 0, and the loop reads the status before the clock. (That the
    /// parallel suite starves the pool the same way on CI is inferred, not
    /// instrumented.) Held, the deadline is the only way out however late the
    /// poll wakes.
    /// Mutation: drop the deadline test from the loop (the command then gives
    /// up on its own after ~300 s and reads as exit 0).
    @Test func aRunPastTheDeadlineTimesOut() async throws {
        let box = try Sandbox()
        let hold = box.root.appendingPathComponent("hold")
        FileManager.default.createFile(atPath: hold.path, contents: nil)
        let held = CLIToolAdministratorRun.quote(hold.path)
        let result = await box.shell(deadline: .milliseconds(300))
            .run("n=0; while [ -e \(held) ] && [ $n -lt 3000 ]; do sleep 0.1; n=$((n+1)); done") { _ in }
        try FileManager.default.removeItem(at: hold)
        let outcome = try #require(Self.outcome(Self.ran(result)))
        #expect(outcome.timedOut)
        #expect(!outcome.succeeded)
    }

    /// A process of the user's that, while the panel is up, points `log` at
    /// a FIFO it reads and `status` at a character device (`/dev/null`)
    /// gets nothing: there is no output directory yet to plant in, and the
    /// one root makes is its own. With the directory made by the app before
    /// the panel (until 2026-10-20) bash 3.2's noclobber opened both links —
    /// the output went through the FIFO (to whichever reader came first:
    /// this one, or the app's own follow), the status to `/dev/null`, and the
    /// run read as timed out. The app's follow, opening `log` to read it,
    /// also waited for the FIFO's next writer for ever (seen as a hang
    /// mutating back to it); a writer opened and closed every 20 ms until the
    /// run ends lets such an open go, so the old line fails here rather than
    /// hangs.
    /// Mutation: make the directory before the panel and hand it to the line.
    @Test func linksPlantedWhileThePanelIsUpCatchNothing() async throws {
        let box = try Sandbox()
        let attacker = try Sandbox()
        let fifo = attacker.root.appendingPathComponent("fifo").path
        #expect(mkfifo(fifo, 0o600) == 0)
        // A reader already there, so a writer's open does not wait for one.
        let reader = open(fifo, O_RDONLY | O_NONBLOCK)
        #expect(reader >= 0)
        defer { close(reader) }
        let root = box.root
        let shell = box.shell(deadline: .seconds(3), whilePanelIsUp: {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
                let directory = root.appendingPathComponent(name)
                try? FileManager.default.createSymbolicLink(
                    atPath: directory.appendingPathComponent("log").path, withDestinationPath: fifo)
                try? FileManager.default.createSymbolicLink(
                    atPath: directory.appendingPathComponent("status").path, withDestinationPath: "/dev/null")
            }
        })
        let ended = InstallCommitTests.Flag()
        let running = Task { () async -> CLIToolAdministratorRun.Result in
            let result = await shell.run("echo one") { _ in }
            ended.set()
            return result
        }
        while !ended.value {
            let writer = open(fifo, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = await running.value
        var buffer = [UInt8](repeating: 0, count: 256)
        let caught = read(reader, &buffer, buffer.count)
        #expect(caught <= 0, "the FIFO's reader got \(String(decoding: buffer.prefix(max(caught, 0)), as: UTF8.self))")
        let run = try #require(Self.ran(result))
        #expect(run.lines == ["one"])
        let outcome = try #require(Self.outcome(run))
        #expect(outcome.terminationStatus == 0)
        #expect(!outcome.timedOut)
    }

    /// A process of the user's that, while the panel is up, swaps whatever
    /// directory it finds for a link to one of its choosing (standing in for
    /// a root-only one such as `/etc/paths.d`) gets nothing written there.
    /// With the app's own directory made before the panel (until 2026-10-20)
    /// root followed the link and wrote `log` and `status` into it.
    /// Mutation: make the directory before the panel and hand it to the line.
    @Test func aDirectorySwappedForALinkWhileThePanelIsUpGetsNothing() async throws {
        let box = try Sandbox()
        let target = try Sandbox()
        let root = box.root
        let result = await box.shell(deadline: .seconds(3), whilePanelIsUp: {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
                let directory = root.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: directory)
                try? FileManager.default.createSymbolicLink(atPath: directory.path, withDestinationPath: target.root.path)
            }
        }).run("echo one") { _ in }
        #expect(target.leftovers.isEmpty)
        let run = try #require(Self.ran(result))
        #expect(run.lines == ["one"])
    }

    /// On a real run the output directory is made in `/private/tmp`, which
    /// is root's, sticky and not a link — so no one else can rename, remove
    /// or write into what root's `mktemp` made there.
    /// Mutation: make `liveWorkRoot` the user's temporary directory.
    @Test func theLiveOutputIsMadeInRootsStickyTmp() {
        var info = stat()
        #expect(lstat(CLIToolAdministratorRun.liveWorkRoot, &info) == 0)
        #expect((info.st_mode & S_IFMT) == S_IFDIR)
        #expect(info.st_uid == 0)
        #expect((info.st_mode & S_ISVTX) != 0)
    }

    /// Only a directory `mktemp` made right in the work root from the line's
    /// template is followed.
    /// Mutation: drop the `/` test.
    @Test func followsOnlyADirectoryMadeFromTheTemplate() throws {
        let box = try Sandbox()
        let shell = box.shell()
        let made = box.root.path + "/" + CLIToolAdministratorRun.outputPrefix + "AbC123xY"
        #expect(shell.outputDirectory(made + "\n")?.path == made)
        #expect(shell.outputDirectory(made + "/../../etc") == nil)
        #expect(shell.outputDirectory(box.root.path + "/" + CLIToolAdministratorRun.outputPrefix) == nil)
        #expect(shell.outputDirectory("/etc/paths.d") == nil)
        #expect(shell.outputDirectory("") == nil)
    }

    /// A line that cannot make its output directory fails, and its command
    /// does not run.
    /// Mutation: drop the `|| exit 1`s (the line then prints an empty path).
    @Test func noOutputDirectoryRunsNothing() async throws {
        let box = try Sandbox()
        let marker = box.root.appendingPathComponent("RAN").path
        let missing = CLIToolAdministratorRun.Shell(
            authorize: box.asUser(), workRoot: box.root.appendingPathComponent("absent"), environment: { [:] },
            poll: .milliseconds(20), beforePanel: .zero, linger: 60,
            deadline: ChildProcess.Deadline(terminateAfter: .seconds(3), killAfter: .seconds(3)))
        let result = await missing.run("touch \(CLIToolAdministratorRun.quote(marker))") { _ in }
        guard case .refused = result else { Issue.record("expected refused, got \(result)"); return }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    /// Cancelled before the panel: no panel, nothing run, nothing left behind.
    /// The panel is the tool's point of no return (`InstallCommit`).
    /// Mutation: drop the commit → the panel is raised and the command runs, red.
    @Test func aCancelledCallerRaisesNoPanel() async throws {
        let box = try Sandbox()
        let marker = box.root.appendingPathComponent("RAN").path
        let shell = box.shell()
        let task = Task { () async -> CLIToolAdministratorRun.Result in
            withUnsafeCurrentTask { $0?.cancel() }
            return await shell.run("touch \(CLIToolAdministratorRun.quote(marker))") { _ in }
        }
        let result = await task.value
        guard case .refused = result else { Issue.record("expected refused, got \(result)"); return }
        #expect(box.given.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(box.leftovers.isEmpty)
    }

    /// Cancelled once the panel has authorized: the command is root's and is
    /// followed to its status as if nothing happened. The following runs where
    /// the cancel does not reach — its `try?` poll sleep would spin on a
    /// cancelled task, returning at once on every turn until the status lands.
    /// Mutation: drop the commit → the lines arrive in a cancelled task, red.
    @Test func aCancelAfterThePanelIsNotSeenByTheFollowing() async throws {
        let box = try Sandbox()
        let hold = box.root.appendingPathComponent("hold")
        FileManager.default.createFile(atPath: hold.path, contents: nil)
        let held = CLIToolAdministratorRun.quote(hold.path)
        let sawCancel = InstallCommitTests.Flag()
        let started = InstallCommitTests.Signal()
        let shell = box.shell()
        let task = Task { () async -> CLIToolAdministratorRun.Result in
            await shell.run(
                "echo started; n=0; while [ -e \(held) ] && [ $n -lt 3000 ]; do sleep 0.02; n=$((n+1)); done; echo done"
            ) { line in
                if line == CLIToolAdministratorRun.waitingLine { return }
                if Task.isCancelled { sawCancel.set() }
                if line == "started" { started.fire() }
            }
        }
        await started.wait()
        task.cancel()
        // A few polls' worth while cancelled, then let the command end.
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: hold)
        let run = try #require(Self.ran(await task.value))
        #expect(run.lines == ["started", "done"])
        let outcome = try #require(Self.outcome(run))
        #expect(outcome.terminationStatus == 0)
        #expect(!outcome.timedOut)
        #expect(!sawCancel.value)
    }

    /// The line survives both quotings: the shell's and AppleScript's.
    /// Mutations: drop either escape in `appleScript(for:)`; drop `quote`'s.
    @Test func quotesSurviveBothLanguages() {
        #expect(CLIToolAdministratorRun.quote("it's") == #"'it'\''s'"#)
        #expect(CLIToolAdministratorRun.appleScript(for: #"echo "a\b""#)
            == #"do shell script "echo \"a\\b\"" with administrator privileges"#)
        let line = CLIToolAdministratorRun.shell(
            command: "curl -sS https://starship.rs/install.sh | sh -s -- -y", workRoot: "/tmp/ZZFixture dir",
            linger: 60, proxies: ["https_proxy": "http://h:1"])
        #expect(line.hasPrefix("cd / || exit 1; umask 022; d=$(/usr/bin/mktemp -d '/tmp/ZZFixture dir/duoupdater-admin.XXXXXXXX') || exit 1; "))
        #expect(line.contains("( /usr/bin/env -i HOME=/var/root "))
        #expect(line.contains(" https_proxy='http://h:1' /bin/sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y' "))
        #expect(line.contains(#"> "$d/log" 2>&1; echo $? > "$d/status"; /bin/sleep 60; /bin/rm -rf "$d" )"#))
        #expect(line.hasSuffix(#"< /dev/null > /dev/null 2>&1 & echo "$d""#))
    }

    /// Only `/usr/local/bin` itself can be root's default; never a fixture or a
    /// spelling of it. (Whether this Mac's `/usr/local/bin` is root's is the
    /// host's, so it is not asserted.)
    /// Mutation: drop the path test.
    @Test func onlyTheDefaultDirectoryCounts() throws {
        let box = try Sandbox()
        #expect(!CLIToolAdministratorRun.isRootsDefault(box.root.path))
        #expect(!CLIToolAdministratorRun.isRootsDefault("/usr/local/bin/"))
        #expect(!CLIToolAdministratorRun.isRootsDefault("/usr/local/../local/bin"))
        #expect(!CLIToolAdministratorRun.isRootsDefault("/usr/bin"))
    }
}

final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

extension InstallJobsTests {
    /// A dismissed panel ran nothing, so the job is preparing again; a panel
    /// that authorized ran root's command, and the job stays committing.
    /// Mutation: drop the run's `landed` predicate → the dismissed job stays
    /// committing, red.
    @Test func aDismissedAdministratorPanelLeavesTheJobPreparing() async throws {
        let box = try CLIToolAdministratorRunTests.Sandbox()
        let declined = Self.id()
        InstallJobs.register(declined, cancel: {})
        defer { InstallJobs.unregister(declined) }
        let shell = box.shell(answer: .error(number: -128, message: "User canceled."))
        _ = await InstallJobs.$currentID.withValue(declined) { await shell.run("true") { _ in } }
        #expect(InstallJobs.phase(of: declined) == .preparing)

        let ran = Self.id()
        InstallJobs.register(ran, cancel: {})
        defer { InstallJobs.unregister(ran) }
        let authorized = box.shell()
        _ = await InstallJobs.$currentID.withValue(ran) { await authorized.run("true") { _ in } }
        #expect(InstallJobs.phase(of: ran) == .committing)
    }
}
