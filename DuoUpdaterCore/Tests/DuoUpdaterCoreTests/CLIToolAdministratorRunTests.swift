import Testing
import Foundation
@testable import DuoUpdaterCore

/// `CLIToolAdministratorRun`: the shell line handed to the administrator panel,
/// and the following of the background run it starts.
///
/// No panel is raised here. Where a run is followed, the "authorization" is a
/// stand-in that runs the very line the panel would be given with `/bin/sh` as
/// this user — so what is checked is the line itself (its environment, its
/// noclobber, its backgrounding) and the polling, never root.
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

        func asUser(answer: CLIToolAdministratorRun.Authorization? = nil) -> CLIToolAdministratorRun.Authorize {
            { shell in
                self.lock.withLock { self.shells.append(shell); self.events.append("panel") }
                if let answer { return answer }
                return Sandbox.sh(shell) ? .authorized : .error(number: 1, message: "sh failed")
            }
        }

        /// Starts the line and does not wait: like `do shell script` on it, the
        /// shell returns at once, the command going on in the background.
        /// offpool-lint:allow — stands in for the panel's synchronous main-actor
        /// call, so it cannot await `ChildProcess`; it starts the shell and
        /// never waits on it.
        static func sh(_ line: String) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", line]
            // What `do shell script` hands root (TN2065: the parent's
            // environment) — the app's, which `env -i` must keep out.
            process.environment = [
                "HOME": "/Users/ZZFixture-ann", "HELM_INSTALL_DIR": "/elsewhere", "PATH": "/usr/bin:/bin",
                "TMPDIR": "/var/folders/ZZFixture/T/",
            ]
            do { try process.run() } catch { return false }
            return true
        }

        func shell(answer: CLIToolAdministratorRun.Authorization? = nil, environment: [String: String] = [:],
                   deadline: Duration = .seconds(20)) -> CLIToolAdministratorRun.Shell {
            CLIToolAdministratorRun.Shell(
                authorize: asUser(answer: answer), workRoot: root, environment: { environment },
                poll: .milliseconds(20), beforePanel: .zero, deadline: ChildProcess.Deadline(terminateAfter: deadline, killAfter: deadline))
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
    /// asked once; nothing is left in the working directory.
    /// Mutations: drop the final `drain()`; read the status before the line ends.
    @Test func followsTheRunToItsStatus() async throws {
        let box = try Sandbox()
        let lines = LockedLines()
        let result = await box.shell().run("echo one; echo two >&2; exit 3") { lines.append($0) }
        let run = try #require(Self.ran(result))
        #expect(run.lines == ["one", "two"])
        let outcome = try #require(Self.outcome(run))
        #expect(outcome.terminationStatus == 3)
        #expect(!outcome.timedOut)
        #expect(lines.all == ["Waiting for an administrator password…", "one", "two"])
        #expect(box.given.count == 1)
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

    /// The root shell creates its files with noclobber: a link planted at
    /// `log` is refused, not written through, and the command does not run.
    /// Mutation: drop `set -C`.
    @Test func aPlantedLinkIsNotWrittenThrough() async throws {
        let box = try Sandbox()
        let directory = box.root.appendingPathComponent("run")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let victim = box.root.appendingPathComponent("victim")
        try Data("keep\n".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("log").path,
                                                   withDestinationPath: victim.path)
        let marker = box.root.appendingPathComponent("RAN").path
        let line = CLIToolAdministratorRun.shell(command: "echo clobbered; touch \(marker)", directory: directory.path,
                                                 proxies: [:])
        #expect(Sandbox.sh(line))
        let status = directory.appendingPathComponent("status")
        for _ in 0..<500 where CLIToolAdministratorRun.Shell.status(at: status) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(CLIToolAdministratorRun.Shell.status(at: status) != 0)
        #expect(try String(contentsOf: victim, encoding: .utf8) == "keep\n")
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    /// The line survives both quotings: the shell's and AppleScript's.
    /// Mutations: drop either escape in `appleScript(for:)`; drop `quote`'s.
    @Test func quotesSurviveBothLanguages() {
        #expect(CLIToolAdministratorRun.quote("it's") == #"'it'\''s'"#)
        #expect(CLIToolAdministratorRun.appleScript(for: #"echo "a\b""#)
            == #"do shell script "echo \"a\\b\"" with administrator privileges"#)
        let line = CLIToolAdministratorRun.shell(
            command: "curl -sS https://starship.rs/install.sh | sh -s -- -y", directory: "/tmp/ZZFixture dir",
            proxies: ["https_proxy": "http://h:1"])
        #expect(line.hasPrefix("( set -C; cd / && umask 022 && /usr/bin/env -i HOME=/var/root "))
        #expect(line.contains(" https_proxy='http://h:1' /bin/sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y' "))
        #expect(line.contains("> '/tmp/ZZFixture dir/log' 2>&1; echo $? > '/tmp/ZZFixture dir/status' )"))
        #expect(line.hasSuffix("< /dev/null > /dev/null 2>&1 &"))
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
