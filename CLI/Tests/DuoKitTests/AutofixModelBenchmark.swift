import Testing
import Foundation
import DuoUpdaterCore
@testable import DuoKit

/// Replays changelog breakages a human already fixed through the production
/// `ChangelogAutofix.attempt`, once per model, and records what each model's
/// answer did: the gate that stopped it or "reached the worktree", what it cost,
/// and whether its entries are the reference fix's entries.
///
/// Off unless `DUO_AUTOFIX_BENCH` names a directory for the results and the page
/// cache. Real model calls through the local `claude`, billed to its login.
///
///     DUO_AUTOFIX_BENCH=<dir> \
///     DUO_AUTOFIX_BENCH_MODELS=claude-haiku-5-5@high,claude-sonnet-5-5,human \
///     DUO_AUTOFIX_BENCH_REPS=3 swift test --package-path CLI --filter AutofixModelBenchmark
///
/// - A model is `id` or `id@effort` (`--effort`). `human` answers with the
///   reference fix itself: the most the gates let through.
/// - The cases are `CLI/Tests/autofix-benchmark-cases.json`. A page with a
///   Wayback timestamp there is the archived copy from when the recipe was broken,
///   downloaded once into `<dir>/pages`; any other page, including one a model
///   proposes, is fetched live through the production fetch, once per run.
/// - The attempt stops where the worktree build would start: G4–G7 do not run.
/// - Results: one JSON line per attempt in `<dir>/results.jsonl`
///   (`DUO_AUTOFIX_BENCH_OUT` renames it).
///
/// With no models it only checks the cases: the broken recipe must read nothing
/// on its page, and the reference must read it.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DUO_AUTOFIX_BENCH"] != nil))
struct AutofixModelBenchmark {

    struct Values: Codable { let source: String; let entryPattern: String; let itemPatterns: [String] }
    struct Case: Codable {
        let name: String
        let issue: Int?
        let recipeID: String
        /// The commit that fixed it; its parent holds the family file as it broke.
        let fixCommit: String
        let lastGoodVersion: String?
        let lastGoodEntryCount: Int?
        /// "noEntries" (the default) or "collapse".
        let trigger: String?
        let broken: Values
        /// The reference answer; nil for this checkout's recipe, which the
        /// nightly sweep keeps reading its live page.
        let human: Values?
        /// Page URL → Wayback timestamp.
        let wayback: [String: String]
    }

    static let env = ProcessInfo.processInfo.environment
    static var dir: URL { URL(fileURLWithPath: env["DUO_AUTOFIX_BENCH"] ?? "/nonexistent") }
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    struct Stop: Error {}

    actor Pages {
        var bodies: [String: String?] = [:]
        var live: [String] = []

        func body(_ recipe: ChangelogRecipe, _ c: Case) async -> String? {
            let url = recipe.source.absoluteString
            if let stamp = c.wayback[url] { return await archived(url, stamp) }
            if let cached = bodies[url] { return cached }
            let probe = (try? recipe.replacing(itemPatternsCleared: ())) ?? recipe
            let diagnostic = await ChangelogService.loadDiagnostic(probe, feedPage: nil)
            let body = diagnostic.fetchFailed ? nil : diagnostic.bodySample
            bodies[url] = body
            live.append(url)
            return body
        }

        /// The raw capture (`id_`), as the vendor served it, cached on disk.
        func archived(_ url: String, _ stamp: String) async -> String? {
            let name = "\(stamp)-" + url.unicodeScalars
                .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
            let file = dir.appendingPathComponent("pages/\(name).html")
            if let text = try? String(contentsOf: file, encoding: .utf8) { return text }
            guard let from = URL(string: "https://web.archive.org/web/\(stamp)id_/\(url)"),
                  let (data, response) = try? await URLSession.shared.data(from: from),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            let text = String(decoding: data, as: UTF8.self)
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
            return text
        }
    }

    static func recipe(_ c: Case, _ values: Values) throws -> ChangelogRecipe {
        let main = try #require(ChangelogRecipeRegistry.recipes.first { $0.recipeID == c.recipeID })
        return try main.replacing(RecipeLiteralEditor.Edit(
            source: URL(string: values.source)!, entryPattern: values.entryPattern,
            itemPatterns: values.itemPatterns))
    }

    static func reference(_ c: Case) throws -> ChangelogRecipe {
        if let human = c.human { return try recipe(c, human) }
        return try #require(ChangelogRecipeRegistry.recipes.first { $0.recipeID == c.recipeID })
    }

    static func entries(_ recipe: ChangelogRecipe, _ c: Case, pages: Pages) async -> [Changelog.Entry] {
        guard let body = await pages.body(recipe, c) else { return [] }
        return ChangelogExtractor.extract(from: body, using: recipe)?.entries ?? []
    }

    /// "claude-haiku-5-5@high" → the model, and `--effort high`.
    static func split(_ spec: String) -> (model: String, effort: String?) {
        let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }

    static func git(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path] + args
        let out = Pipe(); p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// `ClaudeCLI.ask`, keeping the whole JSON document for its cost, tokens and
    /// duration.
    static func ask(_ prompt: String, model spec: String, raw: inout Data) async throws -> String {
        let (model, effort) = split(spec)
        let system = try String(
            contentsOf: repo.appendingPathComponent(ChangelogAutofix.promptPath), encoding: .utf8)
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-claude-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GH_TOKEN")
        environment.removeValue(forKey: "GITHUB_TOKEN")
        environment.removeValue(forKey: "CLAUDE_CODE_EFFORT_LEVEL")
        let seconds = Int64(ClaudeCLI.timeout)
        let outcome = try await ChildProcess.run(
            "/usr/bin/env", ["claude"] + ClaudeCLI.arguments(
                model: model, effort: effort, jsonSchema: ChangelogAutofix.proposalSchema, systemPrompt: system),
            environment: environment, workingDirectory: sandbox,
            standardInput: Data(prompt.utf8),
            deadline: .init(terminateAfter: .seconds(seconds), killAfter: .seconds(seconds + 10)),
            onCancel: .terminateChild)
        raw = outcome.standardOutput
        if outcome.timedOut { throw ClaudeCLI.Failure(description: "claude timed out") }
        return try ClaudeCLI.answer(
            from: outcome.standardOutput, status: outcome.terminationStatus,
            standardError: String(decoding: outcome.standardError, as: UTF8.self))
    }

    final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

    static func run(_ c: Case, model: String, rep: Int, pages: Pages) async throws -> Data {
        let broken = try recipe(c, c.broken)
        let human = try reference(c)
        let location = try #require(ChangelogAutofix.location(of: broken))
        let collapse = c.trigger == "collapse"
        let finding = Finding(
            recipeID: c.recipeID, registry: .changelog, bundleID: broken.bundleID, channel: "-",
            status: collapse ? .warn : .broken, failureKind: collapse ? nil : "noEntriesExtracted",
            warnings: collapse ? [Baseline.collapseComplaintPrefix + " since the last sweep"] : [],
            endpointHost: broken.source.host ?? "")
        var entry = Baseline.Entry()
        entry.lastGoodVersion = c.lastGoodVersion
        entry.lastGoodEntryCount = c.lastGoodEntryCount

        let tree = FileManager.default.temporaryDirectory.appendingPathComponent("duo-bench-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tree) }
        let familyPath = "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/\(location.family).swift"
        let replies = Box<[String]>([])
        let raws = Box<[Data]>([])
        let steps = ChangelogAutofix.Steps(
            fetch: { recipe in
                let body = await pages.body(recipe, c)
                return .init(
                    changelog: body.flatMap { ChangelogExtractor.extract(from: $0, using: recipe) },
                    resolvedURL: recipe.source, httpStatus: body == nil ? nil : 200,
                    fetchFailed: body == nil, bodySample: body)
            },
            ask: { prompt in
                var data = Data()
                defer { raws.value.append(data) }
                let text = model == "human"
                    ? String(decoding: try JSONEncoder().encode(Values(
                        source: human.source.absoluteString, entryPattern: human.entryPattern,
                        itemPatterns: human.itemPatterns)), as: UTF8.self)
                    : try await ask(prompt, model: model, raw: &data)
                replies.value.append(text)
                return text
            },
            model: model,
            // Reached only after G7, which the benchmark never runs.
            check: { _ in throw Stop() },
            tree: tree,
            prepareTree: {
                // The family file as it was when it broke, when it still lines up
                // with this checkout's registry; otherwise this checkout's file with
                // the broken values written back by the editor.
                let revert = RecipeLiteralEditor.Edit(
                    source: broken.source, entryPattern: broken.entryPattern,
                    itemPatterns: broken.itemPatterns)
                let then = try git(["show", "\(c.fixCommit)^1:\(familyPath)"])
                let family: String
                if (try? RecipeLiteralEditor.apply(
                    revert, toChangelogAt: location.index, count: location.count,
                    bundleID: broken.bundleID, in: then)) != nil {
                    family = then
                } else {
                    family = try RecipeLiteralEditor.apply(
                        revert, toChangelogAt: location.index, count: location.count,
                        bundleID: broken.bundleID,
                        in: String(contentsOf: repo.appendingPathComponent(familyPath), encoding: .utf8))
                }
                for (path, text) in [
                    (familyPath, family),
                    (ChangelogAutofix.generationPath, try String(
                        contentsOf: repo.appendingPathComponent(ChangelogAutofix.generationPath), encoding: .utf8)),
                    (ChangelogAutofix.generationPinPath, try String(
                        contentsOf: repo.appendingPathComponent(ChangelogAutofix.generationPinPath), encoding: .utf8)),
                ] {
                    let url = tree.appendingPathComponent(path)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(text.utf8).write(to: url)
                }
            },
            // G4 onwards needs the full build; the benchmark stops here.
            recordGoldens: { throw Stop() },
            committedFile: { _ in throw Stop() }, changedPaths: { throw Stop() },
            makeTest: { throw Stop() }, verify: { _ in throw Stop() })

        let started = Date()
        let outcome = await ChangelogAutofix.attempt(
            finding, trigger: collapse ? .collapse : .noEntries, recipe: broken,
            issue: c.issue ?? 0, entry: entry, location: location, steps: steps)
        var record: [String: Any] = [
            "case": c.name, "model": model, "rep": rep, "asks": replies.value.count,
            "wall_s": Date().timeIntervalSince(started),
        ]
        switch outcome {
        case .notAttempted(let why): record["outcome"] = "notAttempted"; record["why"] = why
        case .refused(let why): record["outcome"] = "refused"; record["why"] = why
        case .ready: record["outcome"] = "ready"
        case .error(let why):
            // A family file the editor cannot write is the editor refusing it.
            record["outcome"] = why.contains("Stop()") ? "reachedWorktree"
                : why.contains("not a string literal") ? "refused" : "error"
            record["why"] = why
        }
        // Summed over the model's answers: two when the page moved.
        var cost = 0.0, apiMs = 0, output = 0, thinking = 0
        for data in raws.value {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            cost += json["total_cost_usd"] as? Double ?? 0
            apiMs += json["duration_api_ms"] as? Int ?? 0
            output += (json["usage"] as? [String: Any])?["output_tokens"] as? Int ?? 0
            if let usage = (json["modelUsage"] as? [String: Any])?[split(model).model] as? [String: Any] {
                thinking += usage["thinkingTokens"] as? Int ?? 0
            }
        }
        record["total_cost_usd"] = cost
        record["duration_api_ms"] = apiMs
        record["output_tokens"] = output
        record["thinking_tokens"] = thinking
        record["replies"] = replies.value

        // Quality: the entries of what the answers describe, against the reference's.
        let referenceEntries = await entries(human, c, pages: pages)
        record["reference_versions"] = referenceEntries.map(\.version)
        if let first = replies.value.first.flatMap({ try? ChangelogAutofix.parse($0) }),
           var candidate = (try? ChangelogAutofix.candidate(broken, applying: first))?.recipe {
            if replies.value.count > 1,
               let second = try? ChangelogAutofix.parse(replies.value[1]),
               let patterned = (try? ChangelogAutofix.candidate(candidate, applying: .init(
                    diagnosis: nil, source: nil, entryPattern: second.entryPattern,
                    itemPatterns: second.itemPatterns, confidence: nil)))?.recipe {
                candidate = patterned
            }
            let got = await entries(candidate, c, pages: pages)
            record["proposed_source"] = candidate.source.absoluteString
            record["versions"] = got.map(\.version)
            record["same_versions"] = got.map(\.version) == referenceEntries.map(\.version)
            record["same_entries"] = got.map(\.version) == referenceEntries.map(\.version)
                && got.map(\.items) == referenceEntries.map(\.items)
        }
        return try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    }

    @Test func benchmark() async throws {
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: Self.repo
            .appendingPathComponent("CLI/Tests/autofix-benchmark-cases.json")))
        let only = Self.env["DUO_AUTOFIX_BENCH_CASES"].map { Set($0.split(separator: ",").map(String.init)) }
        let selected = cases.filter { only?.contains($0.name) ?? true }
        let pages = Pages()

        for c in selected {
            let broken = await Self.entries(try Self.recipe(c, c.broken), c, pages: pages)
            let reference = await Self.entries(try Self.reference(c), c, pages: pages)
            print("CASE \(c.name): broken reads \(broken.count), reference reads \(reference.count) "
                + "\(reference.prefix(3).map(\.version))")
            let collapse = c.trigger == "collapse"
            #expect(collapse ? broken.count == 1 : broken.isEmpty, "\(c.name): the broken recipe still reads")
            #expect(reference.count > (collapse ? 1 : 0), "\(c.name): the reference does not read")
        }

        let models = (Self.env["DUO_AUTOFIX_BENCH_MODELS"] ?? "").split(separator: ",").map(String.init)
        let reps = Int(Self.env["DUO_AUTOFIX_BENCH_REPS"] ?? "1") ?? 1
        let parallel = Int(Self.env["DUO_AUTOFIX_BENCH_PARALLEL"] ?? "6") ?? 6
        var jobs: [(Case, String, Int)] = []
        for rep in 0..<reps { for c in selected { for m in models { jobs.append((c, m, rep)) } } }
        guard !jobs.isEmpty else { return }

        let results = Self.dir.appendingPathComponent(Self.env["DUO_AUTOFIX_BENCH_OUT"] ?? "results.jsonl")
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: results.path, contents: nil)
        let handle = try FileHandle(forWritingTo: results)
        defer { try? handle.close() }
        var next = 0
        try await withThrowingTaskGroup(of: Data.self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (c, m, r) = jobs[next]; next += 1
                group.addTask { try await Self.run(c, model: m, rep: r, pages: pages) }
            }
            for _ in 0..<parallel { add() }
            while let line = try await group.next() {
                handle.write(line + Data("\n".utf8))
                let record = try JSONSerialization.jsonObject(with: line) as? [String: Any] ?? [:]
                print("RESULT \(record["case"]!) \(record["model"]!) #\(record["rep"]!): "
                    + "\(record["outcome"]!) \(record["same_entries"] ?? "-")")
                add()
            }
        }
        print("LIVE \(await pages.live)")
    }
}
