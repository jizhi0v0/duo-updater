import Foundation

/// Minimal argument parsing: a subcommand, then flags and positional operands.
///
/// Hand-rolled rather than swift-argument-parser because the shipping binary is
/// built by XcodeGen, where an SPM dependency means threading a third remote
/// package through `App/project.yml` — and because the core package's
/// zero-dependency stance is deliberate. The cost is that `--help` is written by
/// hand in `Usage.swift`.
public struct Args {
    public let subcommand: String
    /// `--flag` (value `""`) and `--flag value` / `--flag=value`.
    private(set) var flags: [String: String] = [:]
    /// Everything that isn't a flag or a flag's value.
    private(set) var operands: [String] = []

    /// Flags that take a following value. Anything not listed is a boolean, so
    /// `duo verify --json --only foo` parses the way you'd expect rather than
    /// swallowing `--only` as `--json`'s value.
    static let valueFlags: Set<String> = [
        "only", "route", "max-concurrency", "timeout", "source",
        "baseline", "report", "markdown", "out", "max-calls",
    ]

    public init?(_ argv: [String]) {
        var rest = Array(argv.dropFirst())
        guard let first = rest.first, !first.hasPrefix("-") else { return nil }
        subcommand = first
        rest.removeFirst()

        var i = 0
        while i < rest.count {
            let token = rest[i]
            guard token.hasPrefix("--") else {
                operands.append(token)
                i += 1
                continue
            }
            let body = String(token.dropFirst(2))
            if let eq = body.firstIndex(of: "=") {
                flags[String(body[body.startIndex..<eq])] = String(body[body.index(after: eq)...])
            } else if Self.valueFlags.contains(body), i + 1 < rest.count {
                flags[body] = rest[i + 1]
                i += 1
            } else {
                flags[body] = ""
            }
            i += 1
        }
    }

    public func has(_ name: String) -> Bool { flags[name] != nil }
    public func value(_ name: String) -> String? {
        guard let raw = flags[name], !raw.isEmpty else { return nil }
        return raw
    }
    public func int(_ name: String) -> Int? { value(name).flatMap(Int.init) }
}

public func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}
