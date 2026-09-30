import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running the one-click update: what is run, with which environment, what the
/// row is told while it runs and afterwards.
///
/// The "vendor commands" here are `#!/bin/sh` scripts written into a temporary
/// directory that print what the real ones print (lines measured 2026-09-30) and
/// change the fake install on disk the way the real ones change the real one. The
/// busy check, the scanner's home and signature check, and the base environment
/// are all injected — nothing here reads the host's process table, `~/.local`,
/// `~/.cache/claude`, proxy settings or network, and nothing runs the real
/// `claude` or `npm`.
@Suite struct ClaudeCodeUpdaterTests {

    // MARK: - Fixtures

    final class Sandbox {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-code-updater-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("home"), withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func path(_ relative: String) -> String { root.appendingPathComponent(relative).path }

        @discardableResult
        func write(_ relative: String, _ text: String, executable: Bool = false) throws -> URL {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            if executable {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            return url
        }

        /// A `#!/bin/sh` script at `relative`.
        @discardableResult
        func script(_ relative: String, _ body: String) throws -> URL {
            try write(relative, "#!/bin/sh\n" + body + "\n", executable: true)
        }

        func symlink(_ relative: String, to destination: String) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        }

        func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative)) }

        /// Reads this sandbox only: its home, its `p` node prefix, every file
        /// "signed by Anthropic".
        var scanner: ClaudeCodeScanner {
            ClaudeCodeScanner(
                home: home, systemPrefixes: [root.appendingPathComponent("p")], checkSignature: { _ in .anthropic })
        }
    }

    /// Collects what the updater hands out, from whichever thread it calls on.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) { lock.withLock { items.append(item) } }
        var all: [String] { lock.withLock { items } }
    }

    func updater(
        _ box: Sandbox,
        busy: @escaping ClaudeCodeUpdater.BusyCheck = { _ in nil },
        environment: [String: String] = [:],
        deadline: ChildProcess.Deadline = ClaudeCodeUpdater.defaultDeadline
    ) -> ClaudeCodeUpdater {
        ClaudeCodeUpdater(busy: busy, scanner: box.scanner, environment: { environment }, deadline: deadline)
    }

    func status(_ install: ClaudeCodeInstall, oneClick: ClaudeCodeStatus.Command?) -> ClaudeCodeStatus {
        ClaudeCodeStatus(
            install: install, channel: .latest, latestVersion: "2.1.285", versionConfirmed: nil,
            state: .updateAvailable, oneClick: oneClick, note: nil)
    }

    /// A status whose one-click is the script at `relative` — for the tests about
    /// output and exit status, where which install it is does not matter.
    func scriptStatus(_ box: Sandbox, _ relative: String) -> ClaudeCodeStatus {
        let install = ClaudeCodeInstall(
            path: box.path("nowhere/claude"), method: .native, origin: .conventional,
            executable: nil, version: "2.1.280", signature: .anthropic, problem: nil)
        return status(install, oneClick: .init(executable: box.path(relative), arguments: ["update"], pathPrefix: nil))
    }

    /// `~/.local/bin/claude` → `versions/2.1.280`, which is a script behaving like
    /// `claude update`: it prints what 2.1.280 printed and re-points the launcher at
    /// `versions/2.1.285`, as the native installer does.
    func nativeInstall(_ box: Sandbox) throws -> ClaudeCodeInstall {
        let versions = box.home.appendingPathComponent(".local/share/claude/versions").path
        let launcher = box.home.appendingPathComponent(".local/bin/claude").path
        try box.script("home/.local/share/claude/versions/2.1.280", """
            echo "PATH=$PATH"
            echo "Current version: 2.1.280"
            echo "Checking for updates to latest version..."
            echo "Updating to 2.1.285..."
            ln -sfn "\(versions)/2.1.285" "\(launcher)"
            echo "Successfully updated from 2.1.280 to version 2.1.285"
            """)
        try box.script("home/.local/share/claude/versions/2.1.285", "echo 2.1.285")
        try box.symlink("home/.local/bin/claude", to: versions + "/2.1.280")
        let install = try #require(box.scanner.scan().first)
        #expect(install.method == .native && install.version == "2.1.280")
        return install
    }

    // MARK: - Nothing run

    /// No one-click means nothing runs and nothing is asked — not even whether it
    /// is busy, which is an answer to a question nobody may act on.
    @Test func noOneClickRunsNothingAndAsksNothing() async throws {
        let box = try Sandbox()
        let install = try nativeInstall(box)
        let asked = Recorder()
        let outcome = await updater(box, busy: { _ in asked.add("busy?"); return .updateCommand(1) })
            .update(status(install, oneClick: nil))
        #expect(outcome == .notOffered)
        #expect(asked.all.isEmpty)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: install.path).hasSuffix("/2.1.280"))
    }

    /// Something started updating between the check and the click: the command is
    /// not run, and the row is told what is running instead.
    @Test func anUpdateStartedSinceTheCheckIsNotRaced() async throws {
        let box = try Sandbox()
        try box.script("run", "touch '\(box.path("ran"))'")
        let status = scriptStatus(box, "run")
        let asked = Recorder()
        let outcome = await updater(box, busy: { asked.add($0.path); return .staging(version: "2.1.285", pid: 99) })
            .update(status)
        #expect(outcome == .busy(.staging(version: "2.1.285", pid: 99)))
        #expect(!box.exists("ran"))
        #expect(asked.all == [status.install.path])
    }

    /// The re-check is `ClaudeCodeActivity`'s rule over a live process list, not
    /// the verdict the status was built with.
    @Test func theRecheckAppliesTheActivityRuleToTheProcessesNow() async throws {
        let box = try Sandbox()
        let install = try nativeInstall(box)
        let staging = box.root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let running = [ClaudeCodeActivity.Process(pid: 7, arguments: ["/usr/local/bin/claude", "update"])]
        let outcome = await updater(box, busy: {
            ClaudeCodeActivity.busy($0, processes: running, stagingDirectory: staging, isAlive: { _ in false })
        }).update(status(install, oneClick: ClaudeCodeCheck.updateCommand(for: install, channel: .latest)))
        #expect(outcome == .busy(.updateCommand(7)))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: install.path).hasSuffix("/2.1.280"))
    }

    // MARK: - Success

    /// The native command `ClaudeCodeCheck` offers, run for real against the fake
    /// install: every line reaches `progress`, and the version reported is what
    /// the launcher points at *afterwards*. The launcher's own directory is first
    /// on `PATH`, so the real one has no "not in your PATH" warning to print.
    @Test func nativeUpdateReportsTheVersionTheLauncherNowNames() async throws {
        let box = try Sandbox()
        let install = try nativeInstall(box)
        let command = try #require(ClaudeCodeCheck.updateCommand(for: install, channel: .latest))
        let lines = Recorder()
        let outcome = await updater(box).update(status(install, oneClick: command), progress: { lines.add($0) })
        #expect(outcome == .updated(version: "2.1.285"))
        #expect(lines.all == [
            "PATH=\(box.home.path)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "Current version: 2.1.280",
            "Checking for updates to latest version...",
            "Updating to 2.1.285...",
            "Successfully updated from 2.1.280 to version 2.1.285",
        ])
    }

    /// The npm command runs with its own prefix's `bin` first on `PATH` — so
    /// `#!/usr/bin/env node` finds this prefix's node — followed by the system
    /// directories and nothing inherited; the rest of the environment (the proxy)
    /// is passed through. The version is `package.json`'s after the run.
    @Test func npmUpdateRunsWithItsPrefixFirstAndReadsPackageJsonAfter() async throws {
        let box = try Sandbox()
        let package = "p/lib/node_modules/@anthropic-ai/claude-code"
        try box.write(package + "/package.json", #"{"name":"@anthropic-ai/claude-code","version":"2.1.280"}"#)
        var header = [UInt8](repeating: 0, count: 64)
        header[0] = 0xCF; header[1] = 0xFA; header[2] = 0xED; header[3] = 0xFE; header[4] = 0x0C; header[7] = 0x01
        try FileManager.default.createDirectory(
            at: box.root.appendingPathComponent(package + "/bin"), withIntermediateDirectories: true)
        try Data(header).write(to: box.root.appendingPathComponent(package + "/bin/claude.exe"))
        try box.write("p/bin/npm", "#!/usr/bin/env node\n")
        try box.script("p/bin/node", """
            echo "PATH=$PATH"
            echo "proxy=$https_proxy"
            printf '{"name":"@anthropic-ai/claude-code","version":"2.1.285"}' > '\(box.path(package))/package.json'
            echo "changed 2 packages in 3s"
            """)
        let install = try #require(box.scanner.scan().first)
        #expect(install.method == .npm && install.version == "2.1.280")
        let command = try #require(ClaudeCodeCheck.updateCommand(for: install, channel: .latest))

        let lines = Recorder()
        let outcome = await updater(
            box, environment: ["PATH": "/opt/other-node/bin", "https_proxy": "http://proxy.invalid:6152"]
        ).update(status(install, oneClick: command), progress: { lines.add($0) })

        #expect(outcome == .updated(version: "2.1.285"))
        #expect(lines.all == [
            "PATH=\(box.path("p/bin")):/usr/bin:/bin:/usr/sbin:/sbin",
            "proxy=http://proxy.invalid:6152",
            "changed 2 packages in 3s",
        ])
    }

    // MARK: - Failure

    /// What 2.1.285's `claude update` printed when it could not reach the network
    /// (a scratch HOME behind a dead proxy, 2026-09-30): the reason sits between a
    /// headline and a closing hint, and the hint is not the reason.
    @Test func aFailedClaudeUpdateReportsItsReasonNotTheDoctorHint() async throws {
        let box = try Sandbox()
        try box.script("run", #"""
            echo "Current version: 2.1.280"
            echo "Checking for updates to latest version..."
            echo "Error: Failed to install native update" >&2
            echo "TelemetrySafeError: Failed to fetch version from https://downloads.claude.ai/claude-code-releases/latest after 3 attempt(s): connect ECONNREFUSED 127.0.0.1:9" >&2
            echo 'Try running "claude doctor" for diagnostics' >&2
            exit 1
            """#)
        guard case .failed(let message, let output) = await updater(box).update(scriptStatus(box, "run")) else {
            Issue.record("expected a failure"); return
        }
        // Without the internal class name; the log keeps the line as printed.
        #expect(message == "Failed to fetch version from https://downloads.claude.ai/claude-code-releases/latest after 3 attempt(s): connect ECONNREFUSED 127.0.0.1:9")
        #expect(output.contains("\nTelemetrySafeError: Failed to fetch version"))
        // stderr is in the log, in order.
        #expect(output.split(separator: "\n").count == 5)
        #expect(output.hasSuffix(#"Try running "claude doctor" for diagnostics"#))
    }

    /// The measured shape of a failed native download (`claude install`): a bare
    /// `✘` headline, then the reason. The row gets the reason; the detail pane gets
    /// all of it, with the colours stripped.
    @Test func aFailedRunReportsItsLastMeaningfulLine() async throws {
        let box = try Sandbox()
        try box.script("run", #"""
            echo "Current version: 2.1.280"
            printf '\033[?25l\033[31m✘\033[39m Installation failed\n'
            echo "The connection dropped while downloading the update (attempt 3/3: aborted)..."
            echo "---"
            echo ""
            exit 1
            """#)
        let outcome = await updater(box).update(scriptStatus(box, "run"))
        #expect(outcome == .failed(
            message: "The connection dropped while downloading the update (attempt 3/3: aborted)...",
            output: """
                Current version: 2.1.280
                ✘ Installation failed
                The connection dropped while downloading the update (attempt 3/3: aborted)...
                ---
                """))
    }

    /// npm always ends on the pointer to its debug log; the reason is its first
    /// error line that is not a field (output of npm 11, 2026-09-30).
    @Test func aFailedNpmRunReportsNpmsReasonNotItsLogPointer() async throws {
        let box = try Sandbox()
        try box.script("run", """
            echo "npm error code ETARGET"
            echo "npm error notarget No matching version found for @anthropic-ai/claude-code@0.0.0-nope."
            echo "npm error notarget In most cases you or one of your dependencies are requesting"
            echo "npm error notarget a package version that doesn't exist."
            echo "npm error A complete log of this run can be found in: /tmp/x/_logs/2026-09-30T15_18_25_013Z-debug-0.log"
            exit 1
            """)
        guard case .failed(let message, let output) = await updater(box).update(scriptStatus(box, "run")) else {
            Issue.record("expected a failure"); return
        }
        #expect(message == "npm error notarget No matching version found for @anthropic-ai/claude-code@0.0.0-nope.")
        #expect(output.hasSuffix("-debug-0.log"))
    }

    /// The older `npm ERR!` spelling, and the field lines npm puts before the reason.
    @Test func npmReasonSkipsFieldsInBothSpellings() {
        #expect(ClaudeCodeUpdater.npmReason([
            "npm ERR! code EACCES", "npm ERR! syscall mkdir", "npm ERR! path /usr/local/lib/node_modules",
            "npm ERR! errno -13", "npm ERR! Error: EACCES: permission denied, mkdir '/usr/local/lib/node_modules'",
        ]) == "npm ERR! Error: EACCES: permission denied, mkdir '/usr/local/lib/node_modules'")
        #expect(ClaudeCodeUpdater.npmReason(["✘ Installation failed", "npm warn deprecated x"]) == nil)
    }

    @Test func aSilentFailureReportsItsExitStatus() async throws {
        let box = try Sandbox()
        try box.script("run", "echo '12%'\nexit 3")
        #expect(await updater(box).update(scriptStatus(box, "run")) == .failed(message: "exited with status 3", output: "12%"))
    }

    @Test func aCommandThatCannotStartIsAFailure() async throws {
        let box = try Sandbox()
        guard case .failed(let message, _) = await updater(box).update(scriptStatus(box, "missing")) else {
            Issue.record("expected a failure"); return
        }
        #expect(message.hasPrefix("could not run \(box.path("missing"))"))
    }

    /// A child that never exits is stopped at the deadline and reported as such.
    @Test func aHungCommandIsStoppedAtTheDeadline() async throws {
        let box = try Sandbox()
        try box.script("run", "echo started\nexec sleep 30")
        let outcome = await updater(
            box, deadline: .init(terminateAfter: .seconds(1), killAfter: .seconds(3))
        ).update(scriptStatus(box, "run"))
        // The message only. Whether "started" made it into the log before SIGTERM
        // is up to the scheduler: in the full parallel `make test` the child was
        // stopped before its first line (2026-09-30, output ""), so pinning the
        // log here would pin the machine's load, not the deadline rule.
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)"); return
        }
        #expect(message == "stopped: still running after 1 s")
    }

    /// Cancelling the task does not stop the child: an update killed halfway is
    /// worse than one allowed to finish. It runs to its end and the outcome is
    /// reported as if nothing had happened.
    @Test func cancellingLetsTheCommandFinish() async throws {
        let box = try Sandbox()
        try box.script("run", "echo started\nsleep 1\ntouch '\(box.path("finished"))'\necho done")
        let (started, signal) = AsyncStream<Void>.makeStream()
        let update = updater(box)
        let status = scriptStatus(box, "run")
        let task = Task { await update.update(status, progress: { _ in signal.yield() }) }
        for await _ in started { break }
        task.cancel()
        // The fake install is not on disk, so there is no version to re-read.
        #expect(await task.value == .updated(version: nil))
        #expect(box.exists("finished"))
    }

    // MARK: - Output

    /// Chunk boundaries fall anywhere — inside `✘`, inside an escape sequence —
    /// and a `\r` redraw is a line for `progress` but only its last state is kept.
    @Test func outputIsReassembledAsATerminalWouldShowIt() {
        let seen = Recorder()
        let log = ClaudeCodeUpdater.OutputLog(onLine: { seen.add($0) })
        let bytes = Array("\u{1B}[2KDownloading 10%\r\u{1B}[2KDownloading 60%\r\u{1B}[2KDownloading 100%\r\n\u{1B}[31m✘\u{1B}[0m failed\nno newline".utf8)
        // Split inside the escape of the first redraw and inside the UTF-8 of `✘`.
        let cuts = [2, bytes.firstIndex(of: 0xE2)! + 1]
        var start = 0
        for cut in cuts + [bytes.count] {
            log.append(Data(bytes[start..<cut]))
            start = cut
        }
        log.finish()
        #expect(seen.all == ["Downloading 10%", "Downloading 60%", "Downloading 100%", "✘ failed", "no newline"])
        #expect(log.lines == ["Downloading 100%", "✘ failed", "no newline"])
    }

    @Test func escapesOfEveryKindAreStripped() {
        #expect(ClaudeCodeUpdater.stripEscapes("\u{1B}[?25l\u{1B}[1;32mok\u{1B}[0m") == "ok")
        #expect(ClaudeCodeUpdater.stripEscapes("see \u{1B}]8;;https://x.invalid\u{07}docs\u{1B}]8;;\u{07}") == "see docs")
        #expect(ClaudeCodeUpdater.stripEscapes("a\u{1B}]8;;u\u{1B}\\b") == "ab")
        #expect(ClaudeCodeUpdater.stripEscapes("plain") == "plain")
    }
}
