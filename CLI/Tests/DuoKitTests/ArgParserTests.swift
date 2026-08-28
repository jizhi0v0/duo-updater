import Foundation
import Testing
@testable import DuoKit

/// What `duo` does with a command line it doesn't recognise.
///
/// It used to do nothing at all. An unread flag parsed as absent, and absent is
/// not a neutral default: `duo verify --help` printed no help and swept all
/// three registries instead — ~150 requests against real vendor endpoints, and
/// the unauthenticated GitHub rate limit spent on the way past. Every typo
/// widened the sweep the same way, `--githubb` and `--vendors` and an `--only`
/// with nothing after it alike.
///
/// The accepted set is declared nowhere. It is whatever the subcommand's branch
/// in `main.swift` read, so these tests read flags the way a branch does and
/// then ask what was left over.
@Suite struct ArgParserTests {

    private func args(_ argv: String...) -> Args { Args(["duo"] + argv)! }

    @Test func aFlagNobodyReadsIsRefusedAndTheAlternativesAreNamed() {
        let args = self.args("verify", "--githubb")
        _ = args.has("github")
        _ = args.has("vendor")

        let problem = args.unrecognised()?.description
        #expect(problem?.contains("unknown flag '--githubb'") == true)
        #expect(problem?.contains("accepted: --github --vendor") == true)
    }

    @Test func aFlagTheCommandReadsIsFine() {
        let args = self.args("verify", "--samples", "--only=workbuddy")
        #expect(args.has("samples"))
        #expect(args.value("only") == "workbuddy")
        #expect(args.unrecognised() == nil)
    }

    /// `duo verify --only workbuddy --vendor` — narrowing the sweep two ways at
    /// once, which is the whole point of having the flags, so it has to survive.
    @Test func aValueFlagDoesNotSwallowTheFlagAfterIt() {
        let args = self.args("verify", "--only", "workbuddy", "--vendor")
        #expect(args.value("only") == "workbuddy")
        #expect(args.has("vendor"))
        #expect(args.unrecognised() == nil)
    }

    /// Both spellings of the same slip. `--only --samples` is the nastier one:
    /// it used to bind `--samples` as the value, so the sweep ran scoped to a
    /// bundle id no recipe has and the sample dump silently never happened.
    @Test func aValueFlagWithNothingUsableAfterItIsRefused() {
        for tail in [[] as [String], ["--samples"]] {
            let args = Args(["duo", "verify", "--only"] + tail)!
            _ = args.value("only")
            _ = args.has("samples")
            #expect(args.unrecognised()?.description == "--only needs a value")
        }
    }

    /// Derived from the enum rather than spelled out: a fourth registry would
    /// otherwise get a flag that nothing checks is still accepted.
    @Test func everyRegistryIsAcceptedUnderItsOwnName() {
        for registry in Registry.allCases {
            let args = self.args("verify", "--\(registry.rawValue)")
            _ = Registry.allCases.filter { args.has($0.rawValue) }
            #expect(args.unrecognised() == nil, "--\(registry.rawValue) should be accepted")
        }
    }

    /// `duo verify workbuddy` is the `--only` you forgot to type, and it used to
    /// cost the full sweep.
    @Test func aStrayWordIsRefusedByACommandThatReadsNoOperands() {
        let args = self.args("verify", "workbuddy")
        _ = args.value("only")
        #expect(args.unrecognised()?.description.contains("takes no arguments, got 'workbuddy'") == true)
    }

    @Test func aCommandThatTakesAppsStillTakesThem() {
        let args = self.args("check", "Alcove", "Docker")
        #expect(args.operands == ["Alcove", "Docker"])
        #expect(args.unrecognised() == nil)
    }

    /// One dash short. No app is called `-json`, so resolving it as a name would
    /// only report the wrong failure.
    @Test func aFlagMissingADashIsNotAnAppName() {
        let args = self.args("check", "-json")
        #expect(args.operands == ["-json"])
        #expect(args.unrecognised()?.description.contains("unknown flag '-json'") == true)
    }

    @Test func aCommandWithNoFlagsOfItsOwnSaysThatInstead() {
        let args = self.args("restart", "--json")
        _ = args.operands
        #expect(args.unrecognised()?.description.contains("`duo restart` takes no flags") == true)
    }

    /// `CLI/Sources`, so the tests below can read what the CLI actually does
    /// rather than a copy of it kept here.
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // CLI
        .appendingPathComponent("Sources")

    /// `valueFlags` is the one hand-maintained list left in the parser, and it
    /// fails quietly in both directions — so read the truth out of the sources
    /// rather than restating it here, where the restatement would drift too.
    ///
    /// Missing an entry swallows the value into `operands` and the reader sees
    /// its default. A spare entry is worse now than it was: `unrecognised()`
    /// judges a command line against what the subcommand read, so a declared
    /// flag nobody reads is refused. `--timeout` sat here unread from the first
    /// commit and turned into `unknown flag '--timeout'` in 0.3.68 (#114).
    @Test func valueFlagsMatchesTheFlagsReadAsValues() throws {
        // Tolerant of a wrapped call and of a camelCase name, so a read the
        // scan cannot see stays rare — an invisible read reports as a declared
        // flag nobody reads, which is a nudge to delete a needed entry.
        let asValue = /\.(?:value|int|list)\(\s*"([A-Za-z0-9-]+)"\s*\)/

        let files = try #require(
            FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        var read: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            for match in try String(contentsOf: file, encoding: .utf8).matches(of: asValue) {
                read.insert(String(match.1))
            }
        }

        // A regex or a layout that stopped matching would satisfy the
        // comparison below by making it vacuous, which is the same silent
        // drift this test exists to catch.
        #expect(read.count > 5, "only \(read.count) flag reads found under \(Self.sources.path)")
        #expect(Args.valueFlags == read, """
            valueFlags and the flags read as values have drifted.
            declared, no read found (unrecognised() refuses it): \(Args.valueFlags.subtracting(read).sorted())
            read, not declared (the value lands in operands): \(read.subtracting(Args.valueFlags).sorted())
            """)
    }

    /// The usage text is the CLI's other hand-maintained list, and the one
    /// users actually read — so it drifts the same two ways, and until this
    /// test nothing looked at it. `--budget` bounded a triage run from the
    /// commit that added it and was named nowhere in `--help`; `--max-calls`
    /// advertised a default of 20 that was 6 in that same commit. The mirror
    /// case is worse now: a flag that stays documented after its reader goes
    /// away is one `unrecognised()` refuses while `--help` still offers it.
    ///
    /// What it does not see, listed rather than counted, since the next blind
    /// spot belongs on this list too: it compares the two sets whole rather
    /// than section by section, so a flag documented under the wrong
    /// subcommand passes; it only knows `--` spellings, because a single dash
    /// matched in prose picks up the tail of every hyphenated word, which
    /// leaves `-h` outside it; it cannot check a *default* stated in the
    /// prose, which is what `--max-calls` got wrong; it reads flags out of
    /// `main.swift` alone, so moving a branch's option-building into `DuoKit`
    /// fails it on a legitimate change; a read whose name is not a literal is
    /// invisible to it, which is why the registries come from the enum; and it
    /// strips `//` comments only, so a read commented out inside `/* */` still
    /// counts as a read.
    @Test func theUsageTextAndTheFlagsArgsReadsAgree() throws {
        let main = try String(
            contentsOf: Self.sources.appendingPathComponent("duo/main.swift"), encoding: .utf8)
        // Located rather than split on: `split` with no separator found hands
        // back the whole file, which would compare the flags against a superset
        // of the usage text and pass while seeing nothing.
        let opening = try #require(main.firstRange(of: "let usage = \"\"\""),
                                   "the usage literal has moved out of main.swift")
        let closing = try #require(
            main.range(of: "\n\"\"\"", range: opening.upperBound..<main.endIndex),
            "the usage literal no longer ends at the start of a line")
        let usage = main[opening.upperBound..<closing.lowerBound]

        let documented = Set(usage.matches(of: /--([a-z][a-z0-9-]*)/).map { String($0.1) })
        // The read side gets sliced too, and for the reason the documented side
        // did: a flag named only in a comment — or in the usage text itself —
        // would count as read, and a reader deleted while its comment survived
        // is exactly the drift being looked for. Whole-line comments only, so
        // this can never truncate a line that carries code.
        let code = main.replacingCharacters(in: opening.lowerBound..<closing.upperBound, with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let readInMain = Set(
            code.matches(of: /\.(?:value|int|list|has)\(\s*"([A-Za-z0-9-]+)"\s*\)/)
                .map { String($0.1) })
        // Both sides are scanned, so both sides need a floor: a regex that
        // stopped matching would otherwise agree with anything.
        #expect(readInMain.count > 15, "only \(readInMain.count) flag reads found in main.swift")
        #expect(documented.count > 15, "only \(documented.count) flags found in the usage text")

        // `verify` names the registries from the enum rather than one call per
        // flag, so the scan cannot see them; take them from the enum too.
        let read = readInMain.union(Registry.allCases.map(\.rawValue))
        // `--help` and `-h` are answered off `CommandLine.arguments` before
        // `Args` exists, so no scan of flag reads can find them. Read off that
        // line rather than written down here — and off that line only, so a
        // `== "--all"` written somewhere else later cannot quietly excuse a
        // flag from the check below.
        let shortCircuit = try #require(
            code.split(separator: "\n").first { $0.contains("CommandLine.arguments") },
            "the pre-parse --help short-circuit has moved")
        let answeredBeforeParsing = Set(
            shortCircuit.matches(of: /"-{1,2}([a-z][a-z0-9-]*)"/).map { String($0.1) })

        #expect(read.subtracting(documented).isEmpty,
                "flags the CLI reads that `--help` never mentions: \(read.subtracting(documented).sorted())")
        let orphanedDocs = documented.subtracting(read).subtracting(answeredBeforeParsing)
        #expect(orphanedDocs.isEmpty,
                "flags `--help` offers that no branch reads, so unrecognised() refuses them: \(orphanedDocs.sorted())")
    }
}
