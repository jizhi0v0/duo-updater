import Foundation

/// Minimal argument parsing: a subcommand, then flags and positional operands.
///
/// Hand-rolled rather than swift-argument-parser because the shipping binary is
/// built by XcodeGen, where an SPM dependency means threading a third remote
/// package through `App/project.yml` — and because the core package's
/// zero-dependency stance is deliberate. The cost is that `--help` is written
/// by hand — the `usage` literal at the top of `main.swift`, which
/// `ArgParserTests` checks against the flags this actually reads.
public struct Args {
    public let subcommand: String
    /// `--flag` (value `""`) and `--flag value` / `--flag=value`.
    private(set) var flags: [String: String] = [:]
    /// Everything that isn't a flag or a flag's value.
    public var operands: [String] {
        seen.readOperands = true
        return positional
    }
    private var positional: [String] = []
    private let seen = Seen()

    /// What this invocation actually asked the parser for. `unrecognised()`
    /// judges the command line against this rather than against a declared
    /// table of flags per subcommand: a table is a second list, and second
    /// lists drift out of sync with the `case` that reads them — quietly, since
    /// the drift only shows up as a flag nobody validates.
    private final class Seen {
        var flags: Set<String> = []
        /// The subset read as numbers, so `unrecognised()` can refuse a value
        /// that is not one instead of letting it read as absent.
        var integerFlags: Set<String> = []
        var readOperands = false
    }

    /// Flags that take a following value. Anything not listed is a boolean, so
    /// `duo verify --json --only foo` parses the way you'd expect rather than
    /// swallowing `--only` as `--json`'s value.
    /// Adding a flag to the parser and forgetting it here fails quietly: the
    /// flag reads as a bare boolean and its value lands in `operands`, so
    /// `--model deepseek` silently runs the default model. `--model=deepseek`
    /// keeps working either way, which is what makes it hard to notice.
    /// Leaving one here that no subcommand reads is the same drift pointing the
    /// other way, and since `unrecognised()` it is no longer harmless: the flag
    /// is declared and then refused. `--timeout` shipped that way in 0.3.68.
    /// `ArgParserTests` derives both directions from the sources instead.
    static let valueFlags: Set<String> = [
        "triage", "budget",
        "only", "route", "max-concurrency", "source",
        "baseline", "report", "markdown", "out", "max-calls",
        "model", "variant",
    ]

    /// A repeatable comma-separated flag, lowercased and de-duplicated.
    /// `--source vendor,github` and an absent flag both do the obvious thing.
    public func list(_ name: String) -> Set<String> {
        Set((value(name) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    public init?(_ argv: [String]) {
        var rest = Array(argv.dropFirst())
        guard let first = rest.first, !first.hasPrefix("-") else { return nil }
        subcommand = first
        rest.removeFirst()

        var i = 0
        while i < rest.count {
            let token = rest[i]
            guard token.hasPrefix("--") else {
                positional.append(token)
                i += 1
                continue
            }
            let body = String(token.dropFirst(2))
            if let eq = body.firstIndex(of: "=") {
                flags[String(body[body.startIndex..<eq])] = String(body[body.index(after: eq)...])
            } else if Self.valueFlags.contains(body), i + 1 < rest.count,
                      !rest[i + 1].hasPrefix("--") {
                flags[body] = rest[i + 1]
                i += 1
            } else {
                // Either a boolean, or a value flag with nothing usable after
                // it. Recorded as empty either way and sorted out by
                // `unrecognised()`, which knows whether the value was required.
                flags[body] = ""
            }
            i += 1
        }
    }

    public func has(_ name: String) -> Bool {
        seen.flags.insert(name)
        return flags[name] != nil
    }
    public func value(_ name: String) -> String? {
        seen.flags.insert(name)
        guard let raw = flags[name], !raw.isEmpty else { return nil }
        return raw
    }
    public func int(_ name: String) -> Int? {
        seen.integerFlags.insert(name)
        return value(name).flatMap(Int.init)
    }

    /// The first token this invocation can't account for, or nil if it is clean.
    ///
    /// Call it once the options are built and before anything runs — that is the
    /// last moment where refusing is free, and it is also the first moment where
    /// `seen` is complete. Without it an unrecognised flag reads as absent, and
    /// absent is rarely harmless: for `verify` it means the whole ~150-request
    /// sweep instead of the one recipe `--only` was meant to name, and `--githubb`
    /// spends the unauthenticated GitHub rate limit on the way past.
    ///
    /// The corollary for whoever adds the next flag: read it unconditionally,
    /// and read it before this runs. A flag read only inside an `if` is a flag
    /// this refuses whenever that `if` is false, because from here "never asked
    /// about" and "not accepted" are the same thing — and a number flag read
    /// lazily, inside the `run` closure, opts itself out of the check below
    /// the same way.
    public func unrecognised() -> UsageError? {
        let accepted = seen.flags.isEmpty
            ? "`duo \(subcommand)` takes no flags"
            : "accepted: " + seen.flags.sorted().map { "--\($0)" }.joined(separator: " ")

        for name in flags.keys.sorted() where !seen.flags.contains(name) {
            return UsageError("unknown flag '--\(name)' for `duo \(subcommand)`; \(accepted)")
        }
        // `--only --samples` and a trailing `--only` both land here: the value
        // flag is present but empty, which every reader turns back into "not
        // given at all".
        for name in flags.keys.sorted()
        where Self.valueFlags.contains(name) && flags[name]?.isEmpty == true {
            return UsageError("--\(name) needs a value")
        }
        // A number flag holding something that is not a number. `Int.init` fails,
        // `int()` hands back nil, and nil is what "not given at all" looks like
        // from every call site: `duo verify --max-concurrency 1x` swept with the
        // default of four hosts in flight rather than the one asked for, which
        // is the wrong way round for someone slowing a sweep to spare an
        // endpoint. An empty value belongs to the loop above, whose message
        // fits it better.
        for (name, raw) in flags.sorted(by: { $0.key < $1.key })
        where seen.integerFlags.contains(name) && !raw.isEmpty && Int(raw) == nil {
            return UsageError("--\(name) needs a whole number, got '\(raw)'")
        }
        // No operand in this CLI is an app named `-something`, so a leading dash
        // here is a misspelled flag that the unknown-flag loop never saw.
        if let stray = positional.first(where: { $0.hasPrefix("-") }) {
            return UsageError("unknown flag '\(stray)' for `duo \(subcommand)`; \(accepted)")
        }
        if !seen.readOperands, let stray = positional.first {
            return UsageError("`duo \(subcommand)` takes no arguments, got '\(stray)'; \(accepted)")
        }
        return nil
    }
}

/// A malformed invocation, carried back to `main.swift` so the message and the
/// exit code live together instead of each call site inventing both.
public struct UsageError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}
