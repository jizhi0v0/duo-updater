import Foundation

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

    @discardableResult
    static func run(_ arguments: [String], stdin: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments

        let output = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = output
        process.standardError = errorPipe

        let input = Pipe()
        if stdin != nil { process.standardInput = input }

        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        let out = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw Error(description: "gh \(arguments.first ?? "") failed "
                + "(\(process.terminationStatus)): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bodies go through a temp file rather than argv: they contain newlines,
    /// backticks and captured vendor markup, and `gh issue create --body` on a
    /// multi-kilobyte string is a shell-quoting accident waiting to happen.
    private static func withBodyFile<T>(_ body: String, _ work: (URL) throws -> T) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-issue-\(UUID().uuidString).md")
        try Data(body.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try work(url)
    }

    /// Returns the new issue's number.
    static func createIssue(title: String, body: String, label: String) throws -> Int {
        ensureLabel(label)
        let url = try withBodyFile(body) { file in
            try run(["issue", "create", "--title", title, "--body-file", file.path,
                     "--label", label])
        }
        // `gh issue create` prints the issue URL; the number is its last path
        // component.
        guard let number = Int(url.split(separator: "/").last.map(String.init) ?? "") else {
            throw Error(description: "could not read an issue number out of '\(url)'")
        }
        return number
    }

    static func comment(issue: Int, body: String) throws {
        try withBodyFile(body) { file in
            try run(["issue", "comment", "\(issue)", "--body-file", file.path])
        }
    }

    static func close(issue: Int, comment: String) throws {
        try run(["issue", "close", "\(issue)", "--comment", comment])
    }

    static func reopen(issue: Int, comment: String) throws {
        try run(["issue", "reopen", "\(issue)"])
        try self.comment(issue: issue, body: comment)
    }

    /// Create the label if it isn't there yet. Failure is fine — the usual cause
    /// is that it already exists, and a missing label must never be the reason a
    /// breakage goes unreported.
    private static func ensureLabel(_ name: String) {
        _ = try? run(["label", "create", name,
                      "--description", "A detection or changelog recipe stopped working",
                      "--color", "B60205"])
    }
}
