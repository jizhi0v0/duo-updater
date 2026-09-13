import Foundation
import DuoUpdaterCore

/// The thinnest possible wrapper over the `gh` CLI.
///
/// `gh` rather than the REST API on purpose: on a self-hosted runner it already
/// picks up `GH_TOKEN`/`GITHUB_TOKEN` from the environment, and locally it uses
/// the developer's existing login — so the same command works in both places
/// with no token handling of our own. Tokens never pass through argv (where any
/// process could read them from `ps`), only the environment.
enum GitHub {

    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
    }

    /// nil when `gh` is usable; otherwise why it isn't, phrased for someone
    /// reading a CI log.
    static func unavailableReason() async -> String? {
        do {
            _ = try await run(["--version"])
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// `gh <arguments>`, found on `PATH` through `/usr/bin/env`, stdout returned
    /// trimmed. A non-zero exit throws with gh's stderr.
    ///
    /// Both pipes drain concurrently (`ChildProcess` always does) — `gh` writes
    /// progress, deprecation and auth notices to stderr, and reading stdout to
    /// EOF first deadlocked as soon as those filled stderr's buffer.
    ///
    /// `.runToCompletion`: `gh issue create` torn down after the issue exists but
    /// before its URL is read back would file an issue the baseline never
    /// records, and the next sweep would file it again.
    @discardableResult
    static func run(_ arguments: [String], stdin: String? = nil) async throws -> String {
        let outcome = try await ChildProcess.run(
            "/usr/bin/env", ["gh"] + arguments,
            standardInput: stdin.map { Data($0.utf8) },
            onCancel: .runToCompletion)
        let err = String(decoding: outcome.standardError, as: UTF8.self)
        guard outcome.terminationStatus == 0 else {
            throw Error(description: "gh \(arguments.first ?? "") failed "
                + "(\(outcome.terminationStatus)): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return String(decoding: outcome.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bodies go through a temp file rather than argv: they contain newlines,
    /// backticks and captured vendor markup, and `gh issue create --body` on a
    /// multi-kilobyte string is a shell-quoting accident waiting to happen.
    private static func withBodyFile<T>(
        _ body: String, _ work: (URL) async throws -> T
    ) async throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-issue-\(UUID().uuidString).md")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await work(url)
    }

    /// Returns the new issue's number.
    static func createIssue(title: String, body: String, label: String) async throws -> Int {
        await ensureLabel(label)
        let url = try await withBodyFile(body) { file in
            try await run(["issue", "create", "--title", title, "--body-file", file.path,
                     "--label", label])
        }
        // `gh issue create` prints the issue URL; the number is its last path
        // component.
        guard let number = Int(url.split(separator: "/").last.map(String.init) ?? "") else {
            throw Error(description: "could not read an issue number out of '\(url)'")
        }
        return number
    }

    static func comment(issue: Int, body: String) async throws {
        try await withBodyFile(body) { file in
            try await run(["issue", "comment", "\(issue)", "--body-file", file.path])
        }
    }

    static func close(issue: Int, comment: String) async throws {
        try await run(["issue", "close", "\(issue)", "--comment", comment])
    }

    static func reopen(issue: Int, comment: String) async throws {
        try await run(["issue", "reopen", "\(issue)"])
        try await self.comment(issue: issue, body: comment)
    }

    /// Create the label if it isn't there yet. Failure is fine — the usual cause
    /// is that it already exists, and a missing label must never be the reason a
    /// breakage goes unreported.
    private static func ensureLabel(_ name: String) async {
        _ = try? await run(["label", "create", name,
                      "--description", "A detection or changelog recipe stopped working",
                      "--color", "B60205"])
    }
}
