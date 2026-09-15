import Testing
import Foundation
@testable import DuoUpdaterCore

/// The equivalence gate for moving recipe data out of Swift literals (step 3 of the
/// recipe refactor): whatever builds `AppRecipeIndex.all` — the literals under
/// `Recipes/` today, JSON5 resource files later — must build exactly what the
/// committed goldens under `DuoUpdaterCore/Tests/RecipeGoldens/` say.
///
/// ## What it pins
///
/// Every stored property of every entry of every kind of every family, one leaf
/// per line (`RecipeGoldenDump` describes the format): arrays in declaration
/// order, sets and dictionaries sorted, `nil` distinct from `""`, `Bool`/`Int`/
/// `Double` distinct, enums by case name and labelled payload. One golden per
/// family, named `<family>.txt`, so two recipe PRs touching different apps do not
/// conflict in one shared file. The goldens and the families must be the same set.
///
/// Not pinned: the order of families in `AppRecipeIndex.all`.
/// `AppRecipeIndexTests.theIndexIsSortedBySlug` already makes that order a function
/// of the family set, and no production lookup crosses families (every one is
/// grouped by bundle id, and `noBundleIDBelongsToTwoFamilies` holds).
///
/// ## Why not a Codable round trip
///
/// A round trip through the same coder is circular: an encoder and decoder that
/// share a mistake agree with each other. Before step 3's S0, `ChangelogRecipe`
/// decoded an explicit `null` `maxEntries` as 40; decode(encode(x)) never noticed.
/// This reads the values by reflection instead, and shares no code with the
/// `Codable` conformances.
///
/// ## When it fails
///
/// A recipe PR changes recipe data on purpose, so its goldens change with it.
/// Regenerate them from the repository root, read the diff, and commit it:
///
///     DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests
///
/// A recording run rewrites every golden, deletes the ones whose family is gone,
/// and then fails on purpose, so it can never be mistaken for a passing run. Run
/// the same command without the variable to see it pass. CI never sets it.
///
/// The floors in `theDumpIsNotVacuous` do not read the goldens, so a dump that
/// silently degraded is caught even in the run that records it.
///
/// ## Lifetime
///
/// Retired once every family is converted (S9): at that point the JSON files are
/// the source and there is no second representation left to hold them to.
struct RecipeGoldenTests {

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .appendingPathComponent("RecipeGoldens")

    static let fileExtension = "txt"

    /// Every family's dump, or the reasons some could not be dumped.
    static let live: (families: [RecipeGoldenDump.Family], failures: [String]) = {
        var families: [RecipeGoldenDump.Family] = []
        var failures: [String] = []
        for set in AppRecipeIndex.all {
            do { families.append(try RecipeGoldenDump.family(set)) } catch {
                failures.append("\(set.family): \(error)")
            }
        }
        return (families, failures)
    }()

    // MARK: - The gate

    /// Mutations: change one character of one pattern in a family file (that
    /// family's golden differs); swap two probes of one bundle id; delete a golden
    /// or add a stray one; drop a family from `AppRecipeIndex.all`.
    @Test func theRegistryMatchesTheGoldens() throws {
        let live = Self.live
        #expect(live.failures.isEmpty, Comment(rawValue: live.failures.joined(separator: "\n")))
        guard live.failures.isEmpty else { return }

        let fileManager = FileManager.default
        if ProcessInfo.processInfo.environment[RecipeGoldenCommand.environmentKey]?.isEmpty == false {
            try record(live.families)
            return
        }

        let names = try goldenFileNames()
        let expected = Set(live.families.map { "\($0.family).\(Self.fileExtension)" })
        for missing in expected.subtracting(names).sorted() {
            Issue.record(Comment(rawValue: """
                no golden for family \(missing.dropLast(Self.fileExtension.count + 1)) \
                (expected \(Self.directory.path)/\(missing)).
                Regenerate: \(RecipeGoldenCommand.record)
                """))
        }
        for orphan in names.subtracting(expected).sorted() {
            Issue.record(Comment(rawValue: """
                orphan golden \(orphan): no family in AppRecipeIndex.all is named \
                \(orphan.hasSuffix("." + Self.fileExtension) ? String(orphan.dropLast(Self.fileExtension.count + 1)) : orphan) \
                (deleted or renamed?).
                Regenerate: \(RecipeGoldenCommand.record)
                """))
        }
        #expect(names.count == AppRecipeIndex.all.count,
                "\(names.count) golden files for \(AppRecipeIndex.all.count) families")

        for family in live.families {
            let url = Self.directory.appendingPathComponent("\(family.family).\(Self.fileExtension)")
            guard let golden = fileManager.contents(atPath: url.path) else { continue }
            guard !golden.elementsEqual(family.text.utf8) else { continue }
            let want = String(decoding: golden, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            let have = family.text.split(separator: "\n", omittingEmptySubsequences: false)
            let index = zip(want, have).enumerated()
                .first { !$0.element.0.utf8.elementsEqual($0.element.1.utf8) }?.offset
                ?? min(want.count, have.count)
            func line(_ lines: [Substring]) -> String {
                index < lines.count ? String(lines[index]) : "<end of file>"
            }
            Issue.record(Comment(rawValue: """
                family \(family.family) differs from its golden at line \(index + 1)
                  expected (golden): \(line(want))
                  actual (registry): \(line(have))
                If the recipe change is intended, regenerate and commit the diff:
                  \(RecipeGoldenCommand.record)
                """))
        }
    }

    private func goldenFileNames() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: Self.directory.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .filter { !$0.hasPrefix(".") })
    }

    private func record(_ families: [RecipeGoldenDump.Family]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var written = 0
        for family in families {
            let url = Self.directory.appendingPathComponent("\(family.family).\(Self.fileExtension)")
            if fileManager.contents(atPath: url.path).map({ $0.elementsEqual(family.text.utf8) }) != true {
                try Data(family.text.utf8).write(to: url, options: .atomic)
                written += 1
            }
        }
        let expected = Set(families.map { "\($0.family).\(Self.fileExtension)" })
        let orphans = try goldenFileNames().subtracting(expected).sorted()
        for orphan in orphans {
            try fileManager.removeItem(at: Self.directory.appendingPathComponent(orphan))
        }
        Issue.record(Comment(rawValue: """
            recorded \(families.count) recipe goldens under \(Self.directory.path): \
            \(written) rewritten, \(orphans.count) orphans removed\(orphans.isEmpty ? "" : " (\(orphans.joined(separator: ", ")))").
            A recording run always fails. Review `git diff` of the goldens, then run \
            without \(RecipeGoldenCommand.environmentKey) to confirm: \(RecipeGoldenCommand.compare)
            """))
    }

    // MARK: - Floors (never read the goldens)

    /// A dump that stopped reading something agrees with goldens recorded from it.
    /// These hold the text itself to the registry, independently of the goldens.
    ///
    /// Mutations: make `RecipeGoldenDump.family` return a constant text (record
    /// counts); return `.leaf("…")` for a struct nested below a record (struct
    /// instance counts); collapse an enum payload (distinct records).
    @Test func theDumpIsNotVacuous() throws {
        let live = Self.live
        #expect(live.failures.isEmpty, Comment(rawValue: live.failures.joined(separator: "\n")))
        let families = live.families
        #expect(families.count == AppRecipeIndex.all.count)
        #expect(families.count >= 150, "only \(families.count) families dumped")
        #expect(families.map(\.family) == AppRecipeIndex.all.map(\.family))

        var problems: [String] = []
        // Per kind, across the registry: every record's lines with its own path
        // taken off, and each record's value encoded as sorted-key JSON. The JSON
        // is only a count of how many entries are genuinely different — the
        // registry does hold equal values under different keys — so the dump must
        // tell apart exactly as many as that, no fewer.
        var recordDumps: [String: [String]] = [:]
        var recordJSON: [String: Set<Data>] = [:]
        var structInstances: [String: Int] = [:]
        var structKeys: [String: Int] = [:]
        var structLabels: [String: [String]] = [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for (set, family) in zip(AppRecipeIndex.all, families) {
            let lines = parse(family.text)
            let at = family.family
            let setLabels = Mirror(reflecting: set).children.compactMap(\.label)
            for label in setLabels where !lines.contains(where: { $0.path == label }) {
                problems.append("\(at): no line for AppRecipeSet.\(label)")
            }

            for child in Mirror(reflecting: set).children {
                guard let kind = child.label, kind != "family" else { continue }
                guard let collection = child.value as? any Collection else {
                    problems.append("\(at).\(kind): \(type(of: child.value)) is not a collection")
                    continue
                }
                let records = records(of: kind, in: lines)
                if records.count != collection.count {
                    problems.append("\(at).\(kind): \(records.count) records dumped, \(collection.count) in the registry")
                }
                recordDumps[kind, default: []] += records.map { record in
                    record.lines.map { String($0.dropFirst(record.path.count)) }.joined(separator: "\n")
                }
                for element in elements(of: collection) {
                    let value = Mirror(reflecting: element).displayStyle == .tuple
                        ? Mirror(reflecting: element).children.first { $0.label == "value" }?.value as Any
                        : element
                    let entry = Mirror(reflecting: element).displayStyle == .tuple
                        ? Mirror(reflecting: element).children.first { $0.label == "key" }.map { "\($0.value)" } ?? "?"
                        : "#"
                    guard let encodable = value as? any Encodable else {
                        problems.append("\(at).\(kind)[\(entry)]: \(type(of: value)) is not Encodable")
                        continue
                    }
                    recordJSON[kind, default: []].insert(try encoder.encode(encodable))
                }
                countStructs(child.value, instances: &structInstances, keys: &structKeys, labels: &structLabels)
            }
        }

        for (kind, dumps) in recordDumps.sorted(by: { $0.key < $1.key }) {
            let distinct = Set(dumps).count
            let expected = recordJSON[kind]?.count ?? 0
            if distinct != expected {
                problems.append("\(kind): \(distinct) distinct record dumps for \(expected) distinct values (\(dumps.count) records)")
            }
        }

        // Every struct, at every depth: as many `struct T` lines as the registry
        // holds values of T, and under each, a line for every stored property.
        var headers: [String: Int] = [:]
        for family in families {
            let lines = parse(family.text)
            let paths = Set(lines.map(\.path))
            for line in lines where line.value.hasPrefix("struct ") {
                let name = String(line.value.dropFirst("struct ".count))
                headers[name, default: 0] += 1
                for label in structLabels[name] ?? [] {
                    let direct = line.path + "." + label
                    let present = paths.contains(direct)
                        || (1...4).contains { paths.contains(direct + String(repeating: "?", count: $0)) }
                    if !present {
                        problems.append("\(family.family): \(line.path) (\(name)) has no line for .\(label)")
                    }
                }
            }
        }
        for name in Set(headers.keys).union(structInstances.keys).sorted()
        where headers[name] != structInstances[name] {
            problems.append("struct \(name): \(headers[name] ?? 0) dumped, \(structInstances[name] ?? 0) in the registry")
        }
        // A struct used as a dictionary key is written inline in its entry's path,
        // `kind[Name(label: …, …)]`, not as `struct` lines.
        for (name, count) in structKeys.sorted(by: { $0.key < $1.key }) {
            var dumped = 0
            for family in families {
                for line in parse(family.text) where line.path.hasSuffix(")]") && line.path.contains("[\(name)(") {
                    dumped += 1
                    for label in structLabels[name] ?? [] where !line.path.contains("\(label): ") {
                        problems.append("\(family.family): key \(line.path) (\(name)) has no .\(label)")
                    }
                }
            }
            if dumped != count {
                problems.append("dictionary key \(name): \(dumped) dumped, \(count) in the registry")
            }
        }
        #expect(!structKeys.isEmpty, "no struct dictionary keys found; the key check above checked nothing")
        #expect(structInstances.values.reduce(0, +) > 500, "only \(structInstances) struct values found")

        #expect(problems.isEmpty, Comment(rawValue: problems.joined(separator: "\n")))
    }

    /// Mutations: drop the `sorted` from `.set` or `.dictionary` in
    /// `RecipeGoldenDump.node`. The registry's own sets are too small to catch that
    /// reliably (a two-element set comes out sorted half the time, by per-instance
    /// hash seeding), so this uses 24 elements: one ordering in 24! is sorted.
    @Test func setsAndDictionariesAreDumpedSorted() throws {
        let names = (0..<24).map { String(format: "k%02d", $0) }
        let set = Set(names.reversed())
        let dictionary = Dictionary(uniqueKeysWithValues: names.reversed().map { ($0, $0.uppercased()) })

        var lines: [String] = []
        RecipeGoldenDump.render(try RecipeGoldenDump.node(set, at: "s"), at: "s", into: &lines)
        #expect(lines.dropFirst().map { $0.components(separatedBy: " = ")[1] } == names.map { "\"\($0)\"" })

        lines = []
        RecipeGoldenDump.render(try RecipeGoldenDump.node(dictionary, at: "d"), at: "d", into: &lines)
        #expect(lines.dropFirst() == names.map { "d[\"\($0)\"] = \"\($0.uppercased())\"" }[...])
    }

    // MARK: - Leaves and refusals

    struct Leaves {
        let absent: String?
        let empty: String?
        let flag: Bool
        let count: Int
        let ratio: Double
        let link: URL
        let bytes: Data
        let text: String
    }

    /// Mutations: render `.none` and `.some` the same; read `Bool` through `as? Int`;
    /// escape with `String(describing:)`.
    @Test func leavesAreDistinctAndEscaped() throws {
        let value = Leaves(
            absent: nil, empty: "", flag: true, count: 1, ratio: 1,
            link: URL(string: "https://example.invalid/a?b=c")!, bytes: Data([0, 255]),
            text: "q\"\\\n\t é e\u{301}")
        var lines: [String] = []
        RecipeGoldenDump.render(try RecipeGoldenDump.node(value, at: "v"), at: "v", into: &lines)
        #expect(lines == [
            "v = struct DuoUpdaterCoreTests.RecipeGoldenTests.Leaves",
            "v.absent = nil",
            "v.empty? = \"\"",
            "v.flag = true",
            "v.count = 1",
            "v.ratio = Double(1.0)",
            "v.link = URL(\"https://example.invalid/a?b=c\")",
            "v.bytes = Data(base64: \"AP8=\")",
            #"v.text = "q\"\\\n\t \u{E9} e\u{301}""#,
        ])
        // NFC and NFD of one character are `==` in Swift; their dumps must not be.
        #expect(RecipeGoldenDump.quote("\u{E9}") != RecipeGoldenDump.quote("e\u{301}"))
    }

    enum Payloads { case bare, one(String), labelled(key: String), mixed(String, base: Int) }

    @Test func enumsDumpCaseAndLabelledPayload() throws {
        var lines: [String] = []
        for (index, value) in [Payloads.bare, .one("a"), .labelled(key: "b"), .mixed("c", base: 2)].enumerated() {
            RecipeGoldenDump.render(try RecipeGoldenDump.node(value, at: "e\(index)"), at: "e\(index)", into: &lines)
        }
        #expect(lines == [
            "e0 = .bare",
            "e1 = .one(_:)", "e1.0 = \"a\"",
            "e2 = .labelled(key:)", "e2.key = \"b\"",
            "e3 = .mixed(_:base:)", "e3.0 = \"c\"", "e3.base = 2",
        ])
    }

    struct HoldsFloat { let value: Float }
    struct HoldsFunction { let value: @Sendable (Int) -> Int }
    final class Reference { let value = 1 }
    struct HoldsReference { let value: Reference }
    struct Hiding: CustomReflectable {
        let secret: String
        var customMirror: Mirror { Mirror(self, children: []) }
    }
    struct HoldsHiding { let value: Hiding }
    enum Described: CustomStringConvertible { case real; var description: String { "fake" } }
    struct HoldsDescribed { let value: Described }

    /// Each refusal names what it refused. Mutation: return `.leaf("")` from the
    /// `nil` display style — the first three go green.
    @Test func whatCannotBeReadFaithfullyIsRefused() {
        func refusal(_ value: Any) -> String {
            do {
                _ = try RecipeGoldenDump.node(value, at: "x")
                return "<dumped>"
            } catch {
                return "\(error)"
            }
        }
        #expect(refusal(HoldsFloat(value: 1)).contains("unknown leaf type Swift.Float"))
        #expect(refusal(HoldsFunction(value: { $0 })).contains("function value"))
        #expect(refusal(HoldsReference(value: Reference())).contains("class"))
        #expect(refusal(HoldsHiding(value: Hiding(secret: "s"))).contains("CustomReflectable"))
        #expect(refusal(HoldsDescribed(value: .real)).contains("customises its description"))
        #expect(refusal(HoldsFloat(value: 1)).hasPrefix("x.value: "))
    }
}

// MARK: - Reading the text back

private func elements<C: Collection>(of collection: C) -> [Any] { collection.map { $0 } }

private struct DumpLine {
    let path: String
    let value: String
    let raw: String
}

/// Splits each `path = value` line at the first ` = ` that is not inside a quoted
/// string (dictionary keys in a path can contain one).
private func parse(_ text: String) -> [DumpLine] {
    text.split(separator: "\n").compactMap { substring in
        let line = String(substring)
        guard !line.hasPrefix("//") else { return nil }
        var inString = false
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if line[index...].hasPrefix(" = ") {
                return DumpLine(path: String(line[..<index]),
                                value: String(line[line.index(index, offsetBy: 3)...]), raw: line)
            }
            index = line.index(after: index)
        }
        return DumpLine(path: line, value: "", raw: line)
    }
}

/// The records of one kind: each `kind[…]` line with nothing after the bracket,
/// plus every following line under that path.
private func records(of kind: String, in lines: [DumpLine]) -> [(path: String, lines: [String])] {
    var out: [(path: String, lines: [String])] = []
    for line in lines {
        if isRecordPath(line.path, kind: kind) {
            out.append((line.path, [line.raw]))
        } else if let last = out.last, line.path.hasPrefix(last.path),
                  let next = line.path.dropFirst(last.path.count).first, ".[{?".contains(next) {
            out[out.count - 1].lines.append(line.raw)
        }
    }
    return out
}

private func isRecordPath(_ path: String, kind: String) -> Bool {
    guard path.hasPrefix(kind + "["), path.hasSuffix("]") else { return false }
    var inString = false
    var escaped = false
    var depth = 0
    for (offset, character) in path.dropFirst(kind.count).enumerated() {
        if inString {
            if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            continue
        }
        switch character {
        case "\"": inString = true
        case "[", "(": depth += 1
        case "]", ")":
            depth -= 1
            if depth == 0 { return offset == path.count - kind.count - 1 }
        default: break
        }
    }
    return false
}

/// Counts struct values by type — dictionary keys separately — and records each
/// type's stored property labels, by its own reflection walk (not
/// `RecipeGoldenDump`'s).
private func countStructs(
    _ value: Any, instances: inout [String: Int], keys: inout [String: Int],
    labels: inout [String: [String]]
) {
    if value is String || value is URL || value is Data { return }
    let mirror = Mirror(reflecting: value)
    func name(_ value: Any) -> String {
        String(reflecting: type(of: value)).replacingOccurrences(of: "DuoUpdaterCore.", with: "")
    }
    switch mirror.displayStyle {
    case .struct:
        instances[name(value), default: 0] += 1
        labels[name(value)] = mirror.children.compactMap(\.label)
    case .dictionary:
        for pair in mirror.children {
            let parts = Array(Mirror(reflecting: pair.value).children)
            guard parts.count == 2 else { continue }
            let key = Mirror(reflecting: parts[0].value)
            if key.displayStyle == .struct, !(parts[0].value is String || parts[0].value is URL || parts[0].value is Data) {
                keys[name(parts[0].value), default: 0] += 1
                labels[name(parts[0].value)] = key.children.compactMap(\.label)
            }
            countStructs(parts[1].value, instances: &instances, keys: &keys, labels: &labels)
        }
        return
    default:
        break
    }
    for child in mirror.children {
        countStructs(child.value, instances: &instances, keys: &keys, labels: &labels)
    }
}
