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
        let script = try Self.script("sleep 0.2; echo zzfixture-token")
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
        let script = try Self.script("sleep 0.2; echo 'Logged in to github.com account zzfixture' >&2")
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
        let script = try Self.script("sleep 0.2; echo '987654321  ZZFixture (1.0 -> 1.1)'")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let path = script.path
        let ids = await Self.cancelledBeforeStart {
            await MASInstaller.outdatedAdamIDs(mas: path)
        }
        #expect(ids == [987654321])
    }

    /// The vendor probe's `unzip`. Mutation: `.terminateChild` in
    /// `VendorProbeSource.extractZipEntry` → `archiveExtractionFailed`, which the
    /// diagnostics file as a recipe fault.
    @Test func aCancelledZipEntryReadStillAnswers() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("ZZFixture-zipread-\(UUID().uuidString)", isDirectory: true)
        let stub = dir.appendingPathComponent("ZZStub.app/Contents", isDirectory: true)
        try fm.createDirectory(at: stub, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Data("zzfixture-payload".utf8).write(to: stub.appendingPathComponent("Info.plist"))
        let zip = dir.appendingPathComponent("stub.zip")
        let made = try await ChildProcess.run(
            "/usr/bin/ditto",
            ["-c", "-k", "--keepParent", dir.appendingPathComponent("ZZStub.app").path, zip.path],
            onCancel: .runToCompletion)
        #expect(made.succeeded)

        let result = await Self.cancelledBeforeStart {
            await VendorProbeSource.extractZipEntry(archive: zip, entry: "ZZStub.app/Contents/Info.plist")
        }
        guard case .success(let data) = result else {
            Issue.record("expected the entry, got \(result)")
            return
        }
        #expect(String(decoding: data, as: UTF8.self) == "zzfixture-payload")
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

    /// An executable `/bin/sh` script in a fresh scratch directory.
    private static func script(_ body: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("zzfixture-tool")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
