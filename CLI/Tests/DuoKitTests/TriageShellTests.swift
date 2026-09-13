import Foundation
import Testing
@testable import DuoKit

/// `Triage.shell` against `/bin/sh` scripts — the call site's own policy on top of
/// `ChildProcess`: its error strings, its timeout, its working directory. No
/// opencode involved; `shell` runs whatever it is given through `/usr/bin/env`.
@Suite struct TriageShellTests {

    /// Past the timeout the call fails as a timeout, even for a child that
    /// ignores SIGTERM (it is SIGKILLed) — not as "opencode exited 9". The child
    /// gives up by itself after ~30 s, so a broken timeout is a wrong message, not
    /// a hang.
    ///
    /// Mutation: drop the `outcome.timedOut` check in `shell` → the error reads
    /// "opencode exited 9".
    @Test func aCallPastItsTimeoutIsReportedAsATimeout() async throws {
        do {
            _ = try await Triage.shell(
                ["sh", "-c", "trap '' TERM; i=0; while [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done"],
                cwd: FileManager.default.temporaryDirectory, timeout: 1)
            Issue.record("a call past its timeout returned")
        } catch {
            #expect("\(error)" == "timed out after 1s")
        }
    }

    /// A non-zero exit is reported as itself, with the child's stderr.
    ///
    /// Mutation: build the message from `standardOutput` → "opencode exited 3:
    /// on stdout".
    @Test func aNonZeroExitCarriesItsStatusAndStderr() async throws {
        do {
            _ = try await Triage.shell(
                ["sh", "-c", "echo on stdout; echo the real reason >&2; exit 3"],
                cwd: FileManager.default.temporaryDirectory, timeout: 60)
            Issue.record("a failing call returned")
        } catch {
            #expect("\(error)" == "opencode exited 3: the real reason")
        }
    }

    /// opencode is pointed at a sandbox directory and run from inside it.
    ///
    /// Mutation: drop `workingDirectory: cwd` → `pwd` prints the test runner's.
    @Test func itRunsInTheGivenDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-triage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let printed = try await Triage.shell(["pwd", "-P"], cwd: dir, timeout: 60)

        let expected = realpath(dir.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        #expect(printed.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
    }
}
