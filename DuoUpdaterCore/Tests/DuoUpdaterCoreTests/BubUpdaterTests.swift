import Testing
import Foundation
@testable import DuoUpdaterCore

/// Running bub's one-click update: what is run, with which environment, what the
/// row is told while it runs and afterwards.
///
/// The venv's `bin/bub` here is a `#!/bin/sh` script that prints what `bub update
/// bub` printed in a scratch HOME on 2026-10-01 (bub 0.4.4 → 0.5.0, uv 0.9.18)
/// and swaps the dist-info the way uv does. The busy check, the scanner's home and
/// the base environment are injected — nothing reads the host's process table,
/// home, uv or network.
@Suite struct BubUpdaterTests {

    func updater(
        _ box: BubSandbox, busy: @escaping BubUpdater.BusyCheck = { _ in nil },
        environment: [String: String] = [:],
        deadline: ChildProcess.Deadline = BubUpdater.defaultDeadline
    ) -> BubUpdater {
        BubUpdater(busy: busy, scanner: box.scanner, environment: { environment }, deadline: deadline)
    }

    /// The installer's venv at 0.4.4 whose `bin/bub` runs `body`.
    func install(_ box: BubSandbox, bub body: String) throws -> BubInstall {
        try box.venv(box.installerVenv, version: "0.4.4")
        try box.write(box.installerVenv + "/bin/bub", "#!/bin/sh\n" + body + "\n", executable: true)
        return try #require(box.scanner.scan().first)
    }

    /// What `bub update bub` printed (and did) when it moved 0.4.4 → 0.5.0.
    func upgradingBub(_ box: BubSandbox) -> String {
        let sitePackages = box.path(box.installerVenv + "/lib/python3.12/site-packages")
        return """
            echo "PATH=$PATH"
            echo "ARGS=$*"
            echo "Resolved 62 packages in 435ms"
            echo "Prepared 1 package in 632ms"
            rm -r "\(sitePackages)/bub-0.4.4.dist-info"
            mkdir "\(sitePackages)/bub-0.5.0.dist-info"
            printf 'Metadata-Version: 2.5\\nName: bub\\nVersion: 0.5.0\\n' > "\(sitePackages)/bub-0.5.0.dist-info/METADATA"
            echo " - bub==0.4.4"
            echo " + bub==0.5.0"
            """
    }

    func status(_ install: BubInstall, uv: String? = "/fake/uv/bin/uv") async -> CLIToolStatus {
        await BubCheck(latest: { "0.5.0" }, uv: { _ in uv }).status(of: install, busy: nil)
    }

    // MARK: - Nothing run

    @Test func noOneClickRunsNothingAndAsksNothing() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "touch '\(box.path("ran"))'")
        let status = await status(install, uv: nil)
        #expect(status.oneClick == nil)
        let asked = BubSandboxRecorder()
        let outcome = await updater(box, busy: { _ in asked.add("busy?"); return .uv(1) }).update(status)
        #expect(outcome == .notOffered)
        #expect(asked.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: box.path("ran")))
    }

    @Test func anotherToolsStatusIsNotRun() async throws {
        let box = try BubSandbox()
        let foreign = CLIToolStatus(
            kind: .fx, path: "/x", installedVersion: "1", latestVersion: "2", channel: nil, state: .updateAvailable,
            oneClick: CLIToolCommand(executable: "/bin/echo", arguments: [], pathPrefix: nil), withheld: nil,
            note: nil, detail: .fx(FxInstall(path: "/x", version: "1")))
        #expect(await updater(box).update(foreign) == .notOffered)
    }

    /// Something started changing the venv between the check and the click: the
    /// command is not run, and the row is told what is running instead.
    @Test func aChangeStartedSinceTheCheckIsNotRaced() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "touch '\(box.path("ran"))'")
        let asked = BubSandboxRecorder()
        let outcome = await updater(box, busy: { asked.add($0.path); return .bubCommand("install", pid: 42) })
            .update(await status(install))
        #expect(outcome == .busy("bub install is running (pid 42)"))
        #expect(asked.all == [install.path])
        #expect(!FileManager.default.fileExists(atPath: box.path("ran")))
    }

    @Test func theRecheckAppliesTheActivityRuleToTheProcessesNow() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "touch '\(box.path("ran"))'")
        let running = [ClaudeCodeActivity.Process(
            pid: 9, arguments: [install.path + "/bin/python", install.executable, "update", "bub"])]
        let outcome = await updater(box, busy: { BubActivity.busy($0, processes: running) }).update(await status(install))
        #expect(outcome == .busy("bub update is running (pid 9)"))
    }

    // MARK: - Success

    /// The command `BubCheck` offers, run for real against the fake install: every
    /// line reaches `progress`, `PATH` is the uv's directory then the system's and
    /// nothing inherited, the rest of the environment passes through, and the
    /// version reported is the one on disk afterwards.
    @Test func updateReportsTheVersionOnDiskAfterwards() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "echo \"proxy=$https_proxy\"\n" + upgradingBub(box))
        let lines = BubSandboxRecorder()
        let outcome = await updater(box, environment: ["PATH": "/inherited/bin", "https_proxy": "http://127.0.0.1:6152"])
            .update(await status(install), progress: { lines.add($0) })
        #expect(outcome == .updated(version: "0.5.0"))
        #expect(lines.all == [
            "proxy=http://127.0.0.1:6152",
            "PATH=/fake/uv/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "ARGS=update bub",
            "Resolved 62 packages in 435ms",
            "Prepared 1 package in 632ms",
            " - bub==0.4.4",
            " + bub==0.5.0",
        ])
    }

    /// Exit 0 with bub where it was — what a project left without bub does
    /// ("Resolved 1 package … Audited", measured) — is not an update.
    @Test func exitZeroWithoutAChangeIsAFailure() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "echo 'Resolved 1 package in 4ms'\necho 'Audited in 0.03ms'")
        let outcome = await updater(box).update(await status(install))
        #expect(outcome == .failed(
            message: "bub update bub finished, but bub is still 0.4.4",
            output: "Resolved 1 package in 4ms\nAudited in 0.03ms"))
    }

    /// When the version cannot be read afterwards, exit 0 is all there is to go on.
    @Test func anUnreadableVersionAfterwardsIsStillUpdated() async throws {
        let box = try BubSandbox()
        let sitePackages = box.path(box.installerVenv + "/lib/python3.12/site-packages")
        let install = try install(box, bub: "rm -r '\(sitePackages)/bub-0.4.4.dist-info'")
        #expect(await updater(box).update(await status(install)) == .updated(version: nil))
    }

    // MARK: - Failure

    @Test func aFailedRunReportsUvsRootCause() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: """
            echo 'error: Failed to fetch: `https://pypi.org/simple/bub/`' >&2
            echo '  Caused by: Request failed after 3 retries' >&2
            echo '  Caused by: dns error' >&2
            echo '  Caused by: failed to lookup address information: nodename nor servname provided, or not known' >&2
            echo "Command 'uv sync --active --inexact --upgrade-package bub' failed with exit code 2." >&2
            exit 2
            """)
        guard case .failed(let message, let output) = await updater(box).update(await status(install)) else {
            Issue.record("expected a failure"); return
        }
        #expect(message == "failed to lookup address information: nodename nor servname provided, or not known")
        #expect(output.hasSuffix("failed with exit code 2."))
    }

    @Test func aHungUpdateIsStopped() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "echo started\nexec sleep 30")
        let outcome = await updater(box, deadline: .init(terminateAfter: .seconds(1), killAfter: .seconds(3)))
            .update(await status(install))
        // The message only: whether "started" lands before SIGTERM is the
        // scheduler's business (see ClaudeCodeUpdaterTests' twin).
        guard case .failed(let message, _) = outcome else {
            Issue.record("expected a failure, got \(outcome)"); return
        }
        #expect(message == "stopped: still running after 1 s")
    }

    @Test func aCommandThatCannotStartSaysSo() async throws {
        let box = try BubSandbox()
        let install = try install(box, bub: "true")
        try FileManager.default.removeItem(atPath: install.executable)
        guard case .failed(let message, _) = await updater(box).update(await status(install)) else {
            Issue.record("expected a failure"); return
        }
        #expect(message.hasPrefix("could not run \(install.executable)"))
    }

    // MARK: - The failure line

    func message(_ text: String, status: Int32 = 2) -> String {
        let outcome = ChildProcess.Outcome(
            terminationStatus: status, uncaughtSignal: false, timedOut: false, standardOutput: Data(), standardError: Data())
        return BubUpdater.failureMessage(
            text.components(separatedBy: "\n"), outcome, deadline: BubUpdater.defaultDeadline)
    }

    /// Through a dead proxy, while creating the project (measured).
    @Test func theDeepestCauseIsTheReason() {
        #expect(message("""
            Initialized project `bub-project`
            error: Failed to fetch: `https://files.pythonhosted.org/packages/27/c4/f0f6/bub-0.5.0-py3-none-any.whl.metadata`
              Caused by: Request failed after 3 retries
              Caused by: tcp connect error
              Caused by: Connection refused (os error 61)
            Command 'uv add --active --no-sync bub' failed with exit code 2.
            """) == "Connection refused (os error 61)")
    }

    /// uv's resolver diagnostic, wrapped at 80 columns (measured).
    @Test func aResolverDiagnosticIsItsCauseUnwrapped() {
        #expect(message("""
              × No solution found when resolving dependencies:
              ╰─▶ Because only bub<=0.5.0 is available and your project depends on bub>99,
                  we can conclude that your project's requirements are unsatisfiable.
            Command 'uv sync --active --inexact --upgrade-package bub' failed with exit code 1.
            """, status: 1)
            == "Because only bub<=0.5.0 is available and your project depends on bub>99, we can conclude that your project's requirements are unsatisfiable.")
    }

    @Test func aBareUVErrorIsItsOwnReason() {
        #expect(message("""
            error: No `project` table found in: `/u/.bub/bub-project/pyproject.toml`
            Command 'uv sync --active --inexact --upgrade-package bub' failed with exit code 2.
            """) == "No `project` table found in: `/u/.bub/bub-project/pyproject.toml`")
    }

    /// No uv anywhere (measured): Python's traceback box, then the exception.
    @Test func aMissingUVIsTheLineAfterTheTraceback() {
        #expect(message("""
            ╭───────────────────── Traceback (most recent call last) ──────────────────────╮
            │ ❱ 193 │   │   raise FileNotFoundError("uv executable not found in PATH or    │
            ╰──────────────────────────────────────────────────────────────────────────────╯
            FileNotFoundError: uv executable not found in PATH or scripts directory.
            """, status: 1) == "FileNotFoundError: uv executable not found in PATH or scripts directory.")
    }

    /// bub's own wrapper is never the reason when uv gave one, and is the last
    /// resort when it did not.
    @Test func bubsWrapperIsOnlyALastResort() {
        #expect(message("Command 'uv sync --active' failed with exit code 2.")
                == "Command 'uv sync --active' failed with exit code 2.")
        #expect(message("") == "exited with status 2")
        #expect(message("Resolving…\nsomething uv said without a prefix\nCommand 'uv sync --active' failed with exit code 2.")
                == "something uv said without a prefix")
        #expect(BubUpdater.isBubWrapper("Command 'uv add --active --no-sync bub' failed with exit code 2."))
        #expect(!BubUpdater.isBubWrapper("error: Command failed"))
    }
}
