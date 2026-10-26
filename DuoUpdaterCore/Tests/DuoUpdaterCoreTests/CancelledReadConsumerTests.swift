import Foundation
import Testing
@testable import DuoUpdaterCore

/// Reads whose answer is still used after the caller is cancelled must not be
/// killed by that cancellation — otherwise the caller carries on with a result
/// that says "nothing" (no token, not logged in, could not check). Each site runs
/// an invented script standing in for its tool, from a task cancelled before it
/// starts: under `.terminateChild` such a task never spawns at all, so the
/// mutations below fail deterministically.
@Suite struct CancelledReadConsumerTests {

    /// `gh auth token`. Mutation: `.terminateChild` in `GitHubToken.run` → nil,
    /// which `ChangelogService` would cache as "no token" for ten minutes.
    @Test func aCancelledGhTokenReadStillAnswers() async throws {
        let script = try await Self.script("sleep 0.2; echo zzfixture-token")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let path = script.path
        let answer = await Self.cancelledBeforeStart {
            await GitHubToken.run(path, [])
        }
        #expect(answer?.trimmingCharacters(in: .whitespacesAndNewlines) == "zzfixture-token")
    }

    /// `gh auth status`. Mutation: `.terminateChild` in
    /// `GitHubToken.runCapturingStderr` → ("", false), "not logged in".
    @Test func aCancelledGhStatusReadStillAnswers() async throws {
        let script = try await Self.script("sleep 0.2; echo 'Logged in to github.com account zzfixture' >&2")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let path = script.path
        let (text, ok) = await Self.cancelledBeforeStart {
            await GitHubToken.runCapturingStderr(path, [])
        }
        #expect(ok)
        #expect(GitHubToken.parseLogin(from: text) == "zzfixture")
    }

    /// `mas outdated`. Mutation: `.terminateChild` in `outdatedAdamIDs` → nil,
    /// "could not check", which the App Store pre-flight treats as leave to skip.
    @Test func aCancelledMasOutdatedStillAnswers() async throws {
        let script = try await Self.script("sleep 0.2; echo '987654321  ZZFixture (1.0 -> 1.1)'")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let path = script.path
        let ids = await Self.cancelledBeforeStart {
            await MASInstaller.outdatedAdamIDs(mas: path)
        }
        #expect(ids == [987654321])
    }

    // MARK: - Helpers

    private static func cancelledBeforeStart<T: Sendable>(
        _ body: @escaping @Sendable () async -> T
    ) async -> T {
        let task = Task { () async -> T in
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(Task.isCancelled, "the fixture task must really be cancelled")
            return await body()
        }
        return await task.value
    }

    /// An executable `/bin/sh` script in a fresh scratch directory, run once
    /// before it is handed back. The first exec of a freshly written script waits
    /// for Gatekeeper's first-launch scan, which syspolicyd does one at a time for
    /// the whole machine (see `HerdrUpdaterTests`). On the busy minis 2026-10-26,
    /// `outdatedAdamIDs` came back nil twice in a row after 52 s and 62 s; the
    /// likely cause, not confirmed from the runner's log, is that wait outrunning
    /// its 20 s deadline. A second exec of the same path skips the scan: on the
    /// idle mini (macOS 26.7, 2026-10-26) a fresh script's first exec took 0.27 s
    /// and the next two 0.011 s, five scripts out of five. Under load it holds too:
    /// with 80 fresh scripts queued, an already-run script took 0.007–0.014 s
    /// while one more fresh script took 59.5 s. So the cancelled read under test
    /// only times the script itself.
    private static func script(_ body: String) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("zzfixture-tool")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        _ = try await ChildProcess.run(url.path, onCancel: .runToCompletion)
        return url
    }
}
