import Foundation
import DuoUpdaterCore

/// One question to Claude through `claude -p`, with nothing to act with.
///
/// The prompt carries a vendor's web page, which anyone who controls that page
/// can write to, so the model gets no tools at all. Each flag below is load-
/// bearing, and all of them were checked against `claude --help` of the version
/// the workflow pins, 2.1.287:
///
/// - `--tools ""` disables every built-in tool; `--restricted` is the second lock
///   on the ones that run code or fetch, should a later default bring one back.
/// - `--safe-mode` skips CLAUDE.md, skills, hooks and plugins, and
///   `--strict-mcp-config` with no config leaves no MCP server.
/// - `--no-session-persistence` keeps the page out of `~/.claude`.
///
/// Measured on 2026-10-11 with that version and `claude-sonnet-5-5`: asked to run
/// `ls /` and create a file outside its directory, it answered in one turn that it
/// had no tools, with no permission denial recorded (it never tried), and the
/// file was not created. It also runs in an empty temporary directory, so even a
/// file tool would find nothing there.
///
/// `--bare` would be tidier but accepts only an API key, not the OAuth token the
/// workflow holds (`CLAUDE_CODE_OAUTH_TOKEN`, the one `claude-review.yml` uses).
public enum ClaudeCLI {

    /// Enough for proposing three values that the gates then check mechanically.
    public static let defaultModel = "claude-sonnet-5-5"

    static let timeout: TimeInterval = 600

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// The arguments after `claude`, prompt excluded: it goes in on stdin.
    static func arguments(model: String, systemPrompt: String) -> [String] {
        [
            "-p",
            "--tools", "",
            "--restricted",
            "--safe-mode",
            "--strict-mcp-config",
            "--no-session-persistence",
            "--permission-mode", "dontAsk",
            "--model", model,
            "--output-format", "json",
            "--system-prompt", systemPrompt,
        ]
    }

    static func ask(prompt: String, systemPrompt: String, model: String) async throws -> String {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // The model's own credential stays; GitHub's go, so nothing that answers
        // here could reach the repository even through a tool that should not exist.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GH_TOKEN")
        environment.removeValue(forKey: "GITHUB_TOKEN")
        let seconds = Int64(timeout)
        let outcome = try await ChildProcess.run(
            "/usr/bin/env", ["claude"] + arguments(model: model, systemPrompt: systemPrompt),
            environment: environment, workingDirectory: sandbox,
            standardInput: Data(prompt.utf8),
            deadline: .init(terminateAfter: .seconds(seconds), killAfter: .seconds(seconds + 10)),
            onCancel: .terminateChild)
        if outcome.timedOut { throw Failure(description: "claude timed out after \(seconds)s") }
        return try answer(
            from: outcome.standardOutput, status: outcome.terminationStatus,
            standardError: String(decoding: outcome.standardError, as: UTF8.self))
    }

    /// The model's text out of `--output-format json`, or why there is none.
    ///
    /// The error is reported as the CLI gave it. "Not logged in · Please run
    /// /login" arrives as a successful-looking JSON document with `is_error`
    /// set (seen 2026-10-11), and reading only `result` would hand that sentence
    /// on as if it were the answer.
    static func answer(from data: Data, status: Int32, standardError: String) throws -> String {
        struct Output: Decodable {
            let result: String?
            let is_error: Bool?
        }
        guard let output = try? JSONDecoder().decode(Output.self, from: data) else {
            let head = String(decoding: data.prefix(300), as: UTF8.self)
            throw Failure(description: "claude exited \(status) without a JSON answer: "
                + (head.isEmpty ? standardError.prefix(300).description : head))
        }
        guard output.is_error != true, status == 0, let result = output.result else {
            throw Failure(description: "claude reported: \(output.result ?? "an unspecified error")")
        }
        return result
    }
}
