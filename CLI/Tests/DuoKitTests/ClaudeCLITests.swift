import Testing
import Foundation
@testable import DuoKit

/// The model reads a page anyone who controls it can write to. These pin the
/// flags that leave it with nothing to act with, and the reading of its answer.
@Suite struct ClaudeCLITests {

    /// Each flag is one lock; `ClaudeCLI` says what each does. A refactor that
    /// drops one fails here rather than in a sandbox nobody re-checks.
    @Test func everySandboxFlagIsPassed() {
        let args = ClaudeCLI.arguments(model: "claude-sonnet-5-5", jsonSchema: "{}", systemPrompt: "SYSTEM")
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        #expect(args.first == "-p")
        #expect(value(after: "--tools") == "")
        for flag in ["--restricted", "--safe-mode", "--strict-mcp-config", "--no-session-persistence"] {
            #expect(args.contains(flag), "\(flag)")
        }
        #expect(!args.contains("--mcp-config"))
        #expect(!args.contains { $0.contains("dangerously") || $0 == "bypassPermissions" })
        #expect(value(after: "--permission-mode") == "dontAsk")
        #expect(value(after: "--model") == "claude-sonnet-5-5")
        #expect(value(after: "--output-format") == "json")
        #expect(value(after: "--json-schema") == "{}")
        #expect(value(after: "--system-prompt") == "SYSTEM")
        #expect(!args.contains("--effort"))
        let high = ClaudeCLI.arguments(model: "claude-opus-5-5", effort: "high", jsonSchema: "{}", systemPrompt: "SYSTEM")
        #expect(high.suffix(2) == ["--effort", "high"])
        #expect(Array(high.dropLast(2)) == ClaudeCLI.arguments(model: "claude-opus-5-5", jsonSchema: "{}", systemPrompt: "SYSTEM"))
    }

    @Test func theAnswerIsTheStructuredOutput() throws {
        let json = #"{"type":"result","is_error":false,"result":"prose","structured_output":{"diagnosis":"ok"}}"#
        #expect(try ClaudeCLI.answer(from: Data(json.utf8), status: 0, standardError: "") == #"{"diagnosis":"ok"}"#)
        let none = #"{"type":"result","is_error":false,"result":"{\"diagnosis\":\"ok\"}"}"#
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data(none.utf8), status: 0, standardError: "")
        }
        // A bare value would crash `JSONSerialization.data(withJSONObject:)`; it is refused instead.
        for value in [#""ok""#, "3", "[1]", "null"] {
            let bare = #"{"type":"result","is_error":false,"structured_output":"# + value + "}"
            #expect(throws: (any Error).self) {
                try ClaudeCLI.answer(from: Data(bare.utf8), status: 0, standardError: "")
            }
        }
    }

    /// Seen on the mini on 2026-10-11: not logged in arrives as a JSON document
    /// whose `result` is the error sentence.
    @Test func anErrorIsNeverMistakenForAnAnswer() {
        let notLoggedIn = #"{"is_error":true,"subtype":"success","result":"Not logged in · Please run /login"}"#
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data(notLoggedIn.utf8), status: 1, standardError: "")
        }
        // The flag alone is enough: an exit status of 0 does not make it an answer.
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data(notLoggedIn.utf8), status: 0, standardError: "")
        }
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data(#"{"is_error":false,"result":"x"}"#.utf8), status: 2, standardError: "")
        }
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data("not json".utf8), status: 0, standardError: "boom")
        }
        #expect(throws: (any Error).self) {
            try ClaudeCLI.answer(from: Data(#"{"is_error":false}"#.utf8), status: 0, standardError: "")
        }
    }

    /// The instructions the workflow hands the model are a file the checkout
    /// must carry, and they describe the schema `ChangelogAutofix.parse` reads.
    @Test func thePromptFileDescribesTheReplySchema() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let text = try String(
            contentsOf: root.appendingPathComponent(ChangelogAutofix.promptPath), encoding: .utf8)
        for key in ["\"diagnosis\"", "\"source\"", "\"entryPattern\"", "\"itemPatterns\"", "\"confidence\""] {
            #expect(text.contains(key), "\(key)")
        }
        #expect(text.contains("untrusted data"))
        #expect(!text.hasPrefix("---"), "frontmatter is opencode's; claude -p would read it as instructions")
    }
}
