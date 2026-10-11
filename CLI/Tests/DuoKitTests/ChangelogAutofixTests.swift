import Testing
import Foundation
import DuoUpdaterCore
@testable import DuoKit

/// `duo autofix` turns a model's reading of a vendor page into a pull request, so
/// every rule that stands between the two is tested here twice: once as the pure
/// function it is, and once in place, by driving `attempt` with each step faked
/// and checking that a failing gate stops everything after it. The second half
/// is what catches a gate that is correct but no longer called.
@Suite struct ChangelogAutofixTests {

    // MARK: - fixtures

    static let source = URL(string: "https://notes.example.com/changelog")!
    static let oldPattern = #"<h2>(?<version>[0-9.]+)</h2>(?<body>(?:(?!<h2>).)*)"#
    static let newPattern = #"<h3 class="v">(?<version>[0-9.]+)</h3>(?<body>(?:(?!<h3).)*)"#
    static let itemPattern = #"<li>(?<item>[^<]+)</li>"#

    static let recipe = ChangelogRecipe(
        bundleID: "com.example.autofix", source: source,
        entryPattern: oldPattern, itemPatterns: [itemPattern])

    /// The page after a restyle the old pattern cannot read: three releases.
    static let restyled = """
        <html><body>
        <h3 class="v">3.0</h3><ul><li>Third release</li></ul>
        <h3 class="v">2.0</h3><ul><li>Second release</li></ul>
        <h3 class="v">1.0</h3><ul><li>First release</li></ul>
        </body></html>
        """

    static let familyFile = """
        import Foundation

        enum test_family {
            static let set = AppRecipeSet(
                family: "test-family",
                probes: [],
                changelogs: [
                // A comment, with (brackets), [more], "quotes" and a comma.
                ChangelogRecipe(
                    bundleID: "com.example.autofix",
                    source: URL(string: "https://notes.example.com/changelog")!,
                    entryPattern: #"\(oldPattern)"#,
                    itemPatterns: [#"\(itemPattern)"#]),
                ],
                githubRules: [])
        }

        """

    static let golden = """
        family = "test-family"

        probes = Array(count: 0)
        changelogs = Array(count: 1)
        changelogs[0] = struct ChangelogRecipe
        changelogs[0].bundleID = "com.example.autofix"
        changelogs[0].source = URL("https://notes.example.com/changelog")
        changelogs[0].entryPattern = \(ChangelogAutofix.goldenQuote(oldPattern))
        changelogs[0].itemPatterns = Array(count: 1)
        changelogs[0].itemPatterns[0] = \(ChangelogAutofix.goldenQuote(itemPattern))
        changelogs[0].acknowledgedStaleEntry = nil

        """

    static let changelogSwift = """
        public struct Changelog {
            /// Generations:
            /// - 18: something earlier.
            public static let parserGeneration = 18
        }

        """

    static let pinTest = """
        struct ChangelogParserGenerationGuardTests {
            @Test func pinnedGeneration() {
                #expect(Changelog.parserGeneration == 18)
            }
        }

        """

    static let familyPath = "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/test-family.swift"
    static let goldenPath = "DuoUpdaterCore/Tests/RecipeGoldens/test-family.txt"

    static func finding(
        status: FindingStatus = .broken, failureKind: String? = "noEntriesExtracted",
        warnings: [String] = [], registry: Registry = .changelog,
        bundleID: String = "com.example.autofix"
    ) -> Finding {
        Finding(
            recipeID: registry == .changelog ? "changelog:\(bundleID):-" : "vendor:\(bundleID):stable",
            registry: registry, bundleID: bundleID, channel: "-", status: status,
            failureKind: failureKind, warnings: warnings, endpointHost: "notes.example.com")
    }

    static let collapse = Baseline.collapseComplaintPrefix + " since the last sweep (3 → 1) — …"

    static func reply(
        source: String? = nil, entryPattern: String? = newPattern, itemPatterns: [String]? = nil
    ) -> String {
        var object: [String: Any] = ["diagnosis": "headings moved to h3", "confidence": 0.8]
        object["source"] = source ?? NSNull()
        object["entryPattern"] = entryPattern ?? NSNull()
        object["itemPatterns"] = itemPatterns ?? NSNull()
        let data = try! JSONSerialization.data(withJSONObject: object)
        return "```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
    }

    // MARK: - which findings

    @Test func noEntriesAndCollapseAreTheOnlyTriggers() {
        typealias A = ChangelogAutofix
        #expect(A.trigger(for: Self.finding()) == .noEntries)
        #expect(A.trigger(for: Self.finding(status: .warn, failureKind: nil, warnings: [Self.collapse]))
            == .collapse)
        // A collapse and the version regression it causes are one finding.
        #expect(A.trigger(for: Self.finding(
            status: .warn, failureKind: nil,
            warnings: [Self.collapse, "version went BACKWARDS since the last sweep (3 → 1)"]))
            == .collapse)
    }

    /// Both trails findings of 2026-10-11 (Helium #1123, Moshi #1177) were not
    /// pattern bugs, and a pattern change would have passed every gate.
    @Test func trailsAndEverythingElseStayIssueOnly() {
        typealias A = ChangelogAutofix
        let trails = "newest changelog entry (0.18.3.1) trails the detected version (0.19.2.1) "
            + "by a whole release — the entry pattern may be reading a stale section"
        #expect(A.trigger(for: Self.finding(status: .warn, failureKind: nil, warnings: [trails])) == nil)
        #expect(A.trigger(for: Self.finding(
            status: .warn, failureKind: nil, warnings: [Self.collapse, trails])) == nil)
        #expect(A.trigger(for: Self.finding(warnings: [trails])) == nil)
        #expect(A.trigger(for: Self.finding(failureKind: "httpStatus404")) == nil)
        #expect(A.trigger(for: Self.finding(failureKind: "entriesOutsideVersionWindow")) == nil)
        #expect(A.trigger(for: Self.finding(failureKind: "noDetailLink")) == nil)
        #expect(A.trigger(for: Self.finding(registry: .vendor)) == nil)
        #expect(A.trigger(for: Self.finding(status: .infra)) == nil)
    }

    @Test func onlyAPlainOneStageRecipeIsInReach() {
        typealias A = ChangelogAutofix
        #expect(A.shapeRefusal(Self.recipe) == nil)
        let source = Self.source
        #expect(A.shapeRefusal(ChangelogRecipe(
            bundleID: "x", source: source, structuredFormat: .gitHubReleases)) != nil)
        #expect(A.shapeRefusal(ChangelogRecipe(
            bundleID: "x", source: source, entryPattern: "a", itemPatterns: ["b"],
            sourceTemplate: "https://notes.example.com/{version}")) != nil)
        #expect(A.shapeRefusal(ChangelogRecipe(
            bundleID: "x", source: source, entryPattern: "a", itemPatterns: ["b"],
            indexLinkPattern: "c")) != nil)
        #expect(A.shapeRefusal(ChangelogRecipe(
            bundleID: "x", source: source, entryPattern: "a", itemPatterns: ["b"],
            feedPagePattern: "c")) != nil)
        #expect(A.shapeRefusal(ChangelogRecipe(
            bundleID: "x", source: source, entryPattern: "a", itemPatterns: ["b"],
            httpMethod: .post)) != nil)
    }

    private func baseline(
        issue: Int? = 42, closed: Bool = false, streak: Int = Baseline.actionableThreshold,
        attempted: String? = nil
    ) -> Baseline {
        var entry = Baseline.Entry()
        entry.issueNumber = issue
        entry.closedAt = closed ? Date() : nil
        entry.consecutiveActionable = streak
        entry.autofixSignature = attempted
        var b = Baseline()
        b.entries[Self.finding().recipeID] = entry
        return b
    }

    @Test func selectAppliesEveryAttemptRule() {
        typealias A = ChangelogAutofix
        let f = Self.finding()
        func chosen(_ b: Baseline, _ findings: [Finding] = [Self.finding()],
                    recipes: [ChangelogRecipe] = [Self.recipe],
                    pulls: [(number: Int, head: String, state: String)] = []) -> Int {
            A.select(findings, baseline: b, recipes: recipes, pullRequests: pulls).chosen.count
        }
        #expect(chosen(baseline()) == 1)
        #expect(chosen(baseline(), [Self.finding(failureKind: "httpStatus404")]) == 0)
        #expect(chosen(baseline(streak: 1)) == 0)
        #expect(chosen(baseline(issue: nil)) == 0)
        #expect(chosen(baseline(closed: true)) == 0)
        #expect(chosen(baseline(attempted: f.signature)) == 0)
        #expect(chosen(baseline(attempted: "an older failure")) == 1)
        #expect(chosen(baseline(), recipes: [ChangelogRecipe(
            bundleID: "com.example.autofix", source: Self.source,
            structuredFormat: .gitHubReleases)]) == 0)
        #expect(chosen(baseline(), pulls: [(7, "recipe-autofix/issue-42", "OPEN")]) == 0)
        let secret = RegistrySecurity.credentialBearingBundleIDs.first!
        var b = Baseline()
        var e = Baseline.Entry()
        e.issueNumber = 1
        e.consecutiveActionable = Baseline.actionableThreshold
        b.entries[Self.finding(bundleID: secret).recipeID] = e
        #expect(A.select([Self.finding(bundleID: secret)], baseline: b, recipes: [ChangelogRecipe(
            bundleID: secret, source: Self.source, entryPattern: "a", itemPatterns: ["b"])],
            pullRequests: []).chosen.isEmpty)
    }

    /// The one-attempt-per-failure rule rests on a field that crosses processes,
    /// and `Baseline.Entry` decodes by hand: a field missing from its decoder is
    /// written every sweep and read back as nil (`lastGoodEntryCount` once
    /// shipped that way). Here that would mean a model call and a full test run
    /// every six hours for the same failure.
    @Test func anAttemptIsRememberedAcrossSweeps() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-autofix-\(UUID().uuidString)/baseline.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        try baseline(attempted: Self.finding().signature).save(to: path)
        let reread = Baseline.load(from: path)
        #expect(ChangelogAutofix.select(
            [Self.finding()], baseline: reread, recipes: [Self.recipe], pullRequests: []).chosen.isEmpty)
    }

    @Test func onlyAnAttemptThatReachedTheModelIsRecorded() {
        typealias A = ChangelogAutofix
        #expect(!A.records(.notAttempted("page did not fetch"), dryRun: false))
        #expect(A.records(.refused("G6"), dryRun: false))
        #expect(A.records(.error("model call failed"), dryRun: false))
        #expect(A.records(.opened("url"), dryRun: false))
        #expect(!A.records(.refused("G6"), dryRun: true))
        #expect(!A.records(.dryRun("x"), dryRun: true))
    }

    @Test func anyPullRequestForTheIssueBlocksAnother() {
        typealias A = ChangelogAutofix
        let branch = A.branchName(issue: 42)
        #expect(branch == "recipe-autofix/issue-42")
        #expect(A.existingPullRequestRefusal(issue: 42, pullRequests: []) == nil)
        for state in ["OPEN", "CLOSED", "MERGED"] {
            #expect(A.existingPullRequestRefusal(issue: 42, pullRequests: [(1, branch, state)]) != nil, "\(state)")
        }
        // Issue 420's branch, or 4's, is not issue 42's.
        #expect(A.existingPullRequestRefusal(
            issue: 42, pullRequests: [(1, A.branchName(issue: 420), "OPEN"), (2, A.branchName(issue: 4), "OPEN")]) == nil)
    }

    /// Review round 1 on #1194: the signatures this acts on are one constant per
    /// kind, so an attempt recorded forever would make every later break of the
    /// same kind "already attempted". A healthy sweep in between ends it.
    @Test func aHealthySweepEndsTheAttemptSoTheNextBreakIsTriedAgain() {
        var b = baseline(attempted: Self.finding().signature)
        #expect(ChangelogAutofix.select(
            [Self.finding()], baseline: b, recipes: [Self.recipe], pullRequests: []).chosen.isEmpty)
        b.reconcile(Finding(
            recipeID: Self.finding().recipeID, registry: .changelog, bundleID: "com.example.autofix",
            channel: "-", status: .ok, version: "3.0", endpointHost: "notes.example.com",
            entryCount: 3, entryVersions: ["3.0", "2.0", "1.0"]))
        #expect(b.entries[Self.finding().recipeID]?.autofixSignature == nil)
        // Broken again, and reported again (the streak restarts).
        b.entries[Self.finding().recipeID]?.consecutiveActionable = Baseline.actionableThreshold
        #expect(ChangelogAutofix.select(
            [Self.finding()], baseline: b, recipes: [Self.recipe], pullRequests: []).chosen.count == 1)
    }

    // MARK: - empty vendor notes

    private func matched(_ hasItems: [Bool]) -> [ChangelogExtractor.MatchedEntry] {
        hasItems.enumerated().map {
            .init(version: "\(9 - $0.offset).0", title: nil, hasItems: $0.element,
                  range: NSRange(location: $0.offset * 10, length: 5))
        }
    }

    @Test func anEmptyNewestReleaseIsLeftToAHuman() {
        typealias A = ChangelogAutofix
        // Helium's shape (#1123).
        #expect(A.emptyNotesRefusal(matched([false, true, true])) != nil)
        // One release, nothing in it: an empty release or a restyle.
        #expect(A.emptyNotesRefusal(matched([false])) != nil)
        // Every past release emptied at once is the markup, not the vendor.
        #expect(A.emptyNotesRefusal(matched([false, false, false])) == nil)
        #expect(A.emptyNotesRefusal(matched([])) == nil)
        #expect(A.emptyNotesRefusal(matched([true, false])) == nil)
    }

    /// The same rule against the production extractor's own reading of a page.
    @Test func matchedEntriesSeesTheReleaseExtractDrops() {
        let page = """
            <h2>2.0</h2><p>No changes.</p>
            <h2>1.0</h2><ul><li>First release</li></ul>
            """
        let matches = ChangelogExtractor.matchedEntries(in: page, using: Self.recipe)
        #expect(matches.map(\.version) == ["2.0", "1.0"])
        #expect(matches.map(\.hasItems) == [false, true])
        #expect(ChangelogExtractor.extract(from: page, using: Self.recipe)?.entries.map(\.version) == ["1.0"])
        #expect(ChangelogAutofix.emptyNotesRefusal(matches) != nil)
    }

    // MARK: - the proposal

    @Test func aProposalMayOnlyMoveTheSourceWithinItsHost() throws {
        typealias A = ChangelogAutofix
        func propose(_ source: String) throws {
            _ = try A.candidate(Self.recipe, applying: A.parse(Self.reply(source: source)))
        }
        try propose("https://notes.example.com/releases")
        #expect(throws: (any Error).self) { try propose("https://evil.example.net/changelog") }
        #expect(throws: (any Error).self) { try propose("https://example.com/changelog") }
        #expect(throws: (any Error).self) { try propose("http://notes.example.com/changelog") }
        #expect(throws: (any Error).self) {
            _ = try A.candidate(Self.recipe, applying: A.parse(Self.reply(entryPattern: "(unclosed")))
        }
        #expect(throws: (any Error).self) {
            _ = try A.candidate(Self.recipe, applying: A.parse(
                Self.reply(entryPattern: nil, itemPatterns: ["<li>(?<item>", "<p>(.+)</p>"])))
        }
        #expect(throws: (any Error).self) {
            _ = try A.candidate(Self.recipe, applying: A.parse(Self.reply(entryPattern: Self.oldPattern)))
        }
    }

    /// The candidate is built through the recipe's own strict decoder, so no
    /// field the proposal does not name can move — `acknowledgedStaleEntry` above
    /// all, the human judgement this whole feature must not make.
    @Test func theCandidateChangesOnlyTheProposedFields() throws {
        let recipe = ChangelogRecipe(
            bundleID: "com.example.autofix", source: Self.source,
            entryPattern: Self.oldPattern, itemPatterns: [Self.itemPattern], maxEntries: 7,
            newestLast: true, acknowledgedStaleEntry: "1.0")
        let (candidate, edit) = try ChangelogAutofix.candidate(
            recipe, applying: ChangelogAutofix.parse(Self.reply()))
        #expect(edit == .init(entryPattern: Self.newPattern))
        #expect(candidate.entryPattern == Self.newPattern)
        #expect(candidate.itemPatterns == recipe.itemPatterns)
        #expect(candidate.acknowledgedStaleEntry == "1.0")
        #expect(candidate.maxEntries == 7)
        #expect(candidate.newestLast)
        #expect(candidate.source == recipe.source)
    }

    // MARK: - gates as functions

    @Test func extractionGates() {
        typealias A = ChangelogAutofix
        func refusal(_ versions: [String], _ trigger: A.Trigger = .noEntries,
                     count: Int? = 3, last: String? = "2.0", lineage: Bool = false) -> String? {
            A.extractionRefusal(versions: versions, trigger: trigger, lastGoodCount: count,
                                lastGoodVersion: last, ordersByLineage: lineage)
        }
        #expect(refusal(["3.0", "2.0", "1.0"]) == nil)
        #expect(refusal([])?.hasPrefix("G1") == true)
        #expect(refusal(["3.0", "2.0"])?.hasPrefix("G2") == true)
        #expect(refusal(["3.0"], count: nil) == nil)
        // A collapse asks for more than one, whatever the last count was.
        #expect(refusal(["3.0"], .collapse, count: nil)?.hasPrefix("G2") == true)
        #expect(refusal(["3.0", "2.0"], .collapse, count: 9) == nil)
        #expect(refusal(["1.0", "0.9", "0.8"])?.hasPrefix("G3") == true)
        #expect(refusal(["2.0", "1.0", "0.9"]) == nil)
        // Unordered versions: the last good one must still be on the page.
        #expect(refusal(["New AI", "Old AI", "Older"], last: "Old AI") == nil)
        #expect(refusal(["New AI", "Other", "Older"], last: "Old AI")?.hasPrefix("G3") == true)
        #expect(refusal(["abc123", "def456", "0aa"], last: "fff", lineage: true)?.hasPrefix("G3") == true)
    }

    @Test func theGoldenMayChangeOnlyInTheProposedFieldsOfThisRecipe() {
        typealias A = ChangelogAutofix
        let edit = RecipeLiteralEditor.Edit(entryPattern: Self.newPattern)
        let faithful = Self.golden.replacingOccurrences(
            of: A.goldenQuote(Self.oldPattern), with: A.goldenQuote(Self.newPattern))
        #expect(A.goldenRefusal(old: Self.golden, new: faithful, index: 0, edit: edit) == nil)
        #expect(A.goldenRefusal(old: Self.golden, new: Self.golden, index: 0, edit: edit) != nil)
        #expect(A.goldenRefusal(
            old: Self.golden,
            new: faithful.replacingOccurrences(
                of: "acknowledgedStaleEntry = nil", with: "acknowledgedStaleEntry = \"1.0\""),
            index: 0, edit: edit) != nil)
        #expect(A.goldenRefusal(
            old: Self.golden,
            new: faithful.replacingOccurrences(of: "probes = Array(count: 0)", with: "probes = Array(count: 1)"),
            index: 0, edit: edit) != nil)
        // Another value than the proposal's, in the right field.
        #expect(A.goldenRefusal(
            old: Self.golden,
            new: Self.golden.replacingOccurrences(
                of: A.goldenQuote(Self.oldPattern), with: A.goldenQuote("something else")),
            index: 0, edit: edit) != nil)
        // The right field of another recipe.
        #expect(A.goldenRefusal(old: Self.golden, new: faithful, index: 1, edit: edit) != nil)
        // A field the edit does not name.
        let movedSource = faithful.replacingOccurrences(
            of: "URL(\"https://notes.example.com/changelog\")", with: "URL(\"https://notes.example.com/x\")")
        #expect(A.goldenRefusal(old: Self.golden, new: movedSource, index: 0, edit: edit) != nil)
    }

    @Test func goldenQuotingMatchesTheDump() {
        #expect(ChangelogAutofix.goldenQuote(#"a"b\c"#) == #""a\"b\\c""#)
        #expect(ChangelogAutofix.goldenQuote("é\t") == #""\u{E9}\t""#)
    }

    @Test func onlyTheFamilyItsGoldenAndTheFixtureMayChange() {
        typealias A = ChangelogAutofix
        let fixture = "\(A.fixtureDirectory)/stem"
        let ok = [Self.familyPath, Self.goldenPath, A.generationPath, A.generationPinPath,
                  fixture + ".txt", fixture + ".json"]
        #expect(A.pathRefusal(changed: ok, family: "test-family", fixtureStem: "stem") == nil)
        #expect(A.pathRefusal(changed: [Self.familyPath, Self.goldenPath, A.generationPath, A.generationPinPath],
                              family: "test-family", fixtureStem: "stem") == nil)
        // The bump is required, in both places, not just allowed.
        #expect(A.pathRefusal(changed: [Self.familyPath, Self.goldenPath],
                              family: "test-family", fixtureStem: "stem") != nil)
        #expect(A.pathRefusal(changed: [Self.familyPath, Self.goldenPath, A.generationPath],
                              family: "test-family", fixtureStem: "stem") != nil)
        #expect(A.pathRefusal(changed: [Self.familyPath, Self.goldenPath, A.generationPinPath],
                              family: "test-family", fixtureStem: "stem") != nil)
        for stray in [
            ".github/workflows/ci.yml", "scripts/ci_route.py", "Makefile",
            "DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/other-family.swift",
            "DuoUpdaterCore/Sources/DuoUpdaterCore/Install/BundleIDMigration.swift",
            "DuoUpdaterCore/Tests/RecipeGoldens/other-family.txt",
            "\(A.fixtureDirectory)/other.txt", ".opencode/agent/duo-changelog-fix.md",
            "verify/baseline.json",
        ] {
            #expect(A.pathRefusal(changed: ok + [stray], family: "test-family", fixtureStem: "stem") != nil,
                    "\(stray)")
        }
        #expect(A.pathRefusal(changed: [Self.goldenPath, A.generationPath, A.generationPinPath],
                              family: "test-family", fixtureStem: "stem") != nil)
    }

    static func report(_ status: FindingStatus, id: String = "changelog:com.example.autofix:-") -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let finding = Finding(
            recipeID: id, registry: .changelog, bundleID: "com.example.autofix", channel: "-",
            status: status, version: "3.0",
            warnings: status == .warn ? ["something degraded"] : [],
            endpointHost: "notes.example.com")
        return try! encoder.encode(Report.Document(generatedAt: Date(), findings: [finding]))
    }

    @Test func verifyMustBeCleanNotMerelyReadable() {
        typealias A = ChangelogAutofix
        let id = "changelog:com.example.autofix:-"
        #expect(A.verifyRefusal(report: Self.report(.ok), recipeID: id) == nil)
        #expect(A.verifyRefusal(report: Self.report(.warn), recipeID: id) != nil)
        #expect(A.verifyRefusal(report: Self.report(.broken), recipeID: id) != nil)
        #expect(A.verifyRefusal(report: Self.report(.ok, id: "changelog:other:-"), recipeID: id) != nil)
        #expect(A.verifyRefusal(report: Data("{".utf8), recipeID: id) != nil)
    }

    // MARK: - the fixture and the pull request

    @Test func theFixtureIsASliceThatReadsTheSameEntries() throws {
        let candidate = try Self.recipe.replacing(.init(entryPattern: Self.newPattern))
        let padding = String(repeating: "x", count: 200_000)
        // The footer heading is what ends the last entry, as the next one would.
        let page = padding + Self.restyled + "<h3>Footer</h3>" + padding
        let read: (String) -> [String]? = {
            ChangelogExtractor.extract(from: $0, using: candidate)?.entries.map(\.version)
        }
        let slice = try #require(ChangelogAutofix.fixture(
            body: page, recipe: candidate, versions: ["3.0", "2.0", "1.0"], read: read))
        #expect(slice.utf8.count < 20_000)
        #expect(read(slice) == ["3.0", "2.0", "1.0"])
        // Entries spread wider than the cap leave no slice that fits.
        let spread = "<h3 class=\"v\">2.0</h3><li>a</li>" + String(repeating: "y", count: 300_000)
            + "<h3 class=\"v\">1.0</h3><li>b</li>"
        #expect(ChangelogAutofix.fixture(
            body: spread, recipe: candidate, versions: ["2.0", "1.0"], read: read) == nil)
    }

    @Test func thePullRequestRefersAndNeverCloses() {
        let body = ChangelogAutofix.pullRequestBody(
            Self.finding(), trigger: .noEntries, recipe: Self.recipe, issue: 42,
            edit: .init(entryPattern: Self.newPattern),
            proposal: .init(diagnosis: "x ``` [link](https://evil) fixes #1", source: nil,
                            entryPattern: Self.newPattern, itemPatterns: nil, confidence: 0.5),
            versions: ["3.0"], entry: .init(), fixtureIncluded: true, model: "m")
        #expect(body.hasPrefix("Refs #42"))
        #expect(!body.contains("fixes #1"))
        // The diagnosis is model text from vendor input: fenced, and unable to close the fence.
        #expect(body.components(separatedBy: "```").count % 2 == 1)
        #expect(!ChangelogAutofix.containsClosingKeyword(body))
    }

    @Test func closingKeywordsAreRecognisedInEveryForm() {
        typealias A = ChangelogAutofix
        for text in ["Fixes #1", "closes: #22", "resolved jizhi0v0/duo-updater#3", "FIX #4", "close #5"] {
            #expect(A.containsClosingKeyword(text), "\(text)")
        }
        for text in ["Refs #821", "prefix #1", "fixes # 1", "closest #1"] {
            #expect(!A.containsClosingKeyword(text), "\(text)")
        }
    }

    @Test func aBodyThatWouldCloseAnIssueIsNotPublished() async throws {
        var world = World()
        // A pattern is shown verbatim; one that reads as a closing keyword stops it.
        let pattern = #"<h3 class="v">(?<version>[0-9.]+)</h3>(?<body>(?:(?!<h3).)*)(?:fixes #9)?"#
        world.reply = Self.reply(entryPattern: pattern)
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome) == "refused: the pull request body would close an issue",
                "\(Self.reason(outcome))")
        #expect(!log.all.contains { $0.hasPrefix("publish") })
    }

    // MARK: - the gates in place

    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        func add(_ call: String) { lock.withLock { calls.append(call) } }
        var all: [String] { lock.withLock { calls } }
        func did(_ call: String) -> Bool { all.contains(call) }
    }

    struct World {
        var page = ChangelogAutofixTests.restyled
        var movedPage: String?
        var reply = ChangelogAutofixTests.reply()
        /// Applied to the faithful golden.
        var goldenTamper: @Sendable (String) -> String = { $0 }
        var strayFile: String?
        /// Applied to Changelog.swift after the harness bumped it.
        var generationTamper: (@Sendable (String) -> String)?
        var pinTamper: (@Sendable (String) -> String)?
        var testStatus: Int32 = 0
        var verifyStatus: FindingStatus = .ok
        var treeChangesDuringGates = false
        var family = ChangelogAutofixTests.familyFile
    }

    static func steps(_ world: World, log: Log) throws -> ChangelogAutofix.Steps {
        let tree = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-autofix-test-\(UUID().uuidString)")
        let world = world
        @Sendable func write(_ text: String, _ path: String) throws {
            let url = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        @Sendable func files() -> [String] {
            let base = tree.standardizedFileURL.path + "/"
            let walker = FileManager.default.enumerator(at: tree, includingPropertiesForKeys: nil)
            return (walker?.allObjects as? [URL] ?? [])
                .filter { !$0.hasDirectoryPath }
                .map { $0.standardizedFileURL.path.replacingOccurrences(of: base, with: "") }
                .sorted()
        }
        return ChangelogAutofix.Steps(
            fetch: { recipe in
                log.add("fetch \(recipe.source.path)")
                let body = recipe.source == Self.source ? world.page : (world.movedPage ?? "")
                return .init(
                    changelog: ChangelogExtractor.extract(from: body, using: recipe),
                    resolvedURL: recipe.source, httpStatus: 200, fetchFailed: false,
                    bodySample: body)
            },
            ask: { _ in log.add("ask"); return world.reply },
            model: "test-model",
            tree: tree,
            prepareTree: {
                log.add("prepare")
                try write(world.family, Self.familyPath)
                try write(Self.changelogSwift, ChangelogAutofix.generationPath)
                try write(Self.pinTest, ChangelogAutofix.generationPinPath)
            },
            recordGoldens: {
                log.add("goldens")
                let family = try String(contentsOf: tree.appendingPathComponent(Self.familyPath), encoding: .utf8)
                // A stand-in for the dump: read back what the editor wrote.
                var golden = Self.golden
                if let range = family.range(of: #"source: URL\(string: "[^"]*"\)!"#, options: .regularExpression) {
                    let url = family[range].dropFirst(#"source: URL(string: ""#.count).dropLast(#"")!"#.count)
                    golden = golden.replacingOccurrences(
                        of: "URL(\"\(Self.source.absoluteString)\")", with: "URL(\"\(url)\")")
                }
                if !family.contains(Self.oldPattern),
                   let range = family.range(of: ##"entryPattern: #+"(.*)"#+,"##, options: .regularExpression) {
                    let literal = String(family[range]).dropFirst("entryPattern: ".count).dropLast()
                    let value = RecipeLiteralEditor.stringLiteralValue(
                        Array(String(literal).unicodeScalars), 0..<literal.unicodeScalars.count)
                    golden = golden.replacingOccurrences(
                        of: ChangelogAutofix.goldenQuote(Self.oldPattern),
                        with: ChangelogAutofix.goldenQuote(value ?? "?"))
                }
                try write(world.goldenTamper(golden), Self.goldenPath)
                if let stray = world.strayFile { try write("x", stray) }
                if let tamper = world.pinTamper {
                    let url = tree.appendingPathComponent(ChangelogAutofix.generationPinPath)
                    try write(tamper(try String(contentsOf: url, encoding: .utf8)), ChangelogAutofix.generationPinPath)
                }
                if let tamper = world.generationTamper {
                    let url = tree.appendingPathComponent(ChangelogAutofix.generationPath)
                    try write(tamper(try String(contentsOf: url, encoding: .utf8)), ChangelogAutofix.generationPath)
                }
            },
            committedFile: { path in
                switch path {
                case ChangelogAutofix.generationPath: return Self.changelogSwift
                case ChangelogAutofix.generationPinPath: return Self.pinTest
                default: return Self.golden
                }
            },
            changedPaths: { files() },
            makeTest: {
                log.add("make test")
                return .init(status: world.testStatus, timedOut: false,
                             output: "lots of output\nmake: *** [test-scripts] Error 1")
            },
            verify: { _ in
                log.add("verify")
                if world.treeChangesDuringGates { try write("late", "late.txt") }
                return Self.report(world.verifyStatus)
            },
            diffStat: { "stat" },
            publish: { branch, paths, _, body in
                log.add("publish \(branch)")
                log.add("paths \(paths.joined(separator: ","))")
                log.add("body \(body.prefix(9))")
                return "https://github.com/o/r/pull/1"
            })
    }

    static func attempt(
        _ world: World = World(), trigger: ChangelogAutofix.Trigger = .noEntries,
        entry: Baseline.Entry = { var e = Baseline.Entry(); e.lastGoodVersion = "2.0"; e.lastGoodEntryCount = 3; return e }(),
        dryRun: Bool = false
    ) async throws -> (ChangelogAutofix.Outcome, Log) {
        let log = Log()
        let steps = try Self.steps(world, log: log)
        defer { try? FileManager.default.removeItem(at: steps.tree) }
        let outcome = await ChangelogAutofix.attempt(
            Self.finding(), trigger: trigger, recipe: Self.recipe, issue: 42, entry: entry,
            location: ("test-family", 0, 1), dryRun: dryRun, steps: steps)
        return (outcome, log)
    }

    static func reason(_ outcome: ChangelogAutofix.Outcome) -> String {
        switch outcome {
        case .notAttempted(let r): return "notAttempted: \(r)"
        case .refused(let r): return "refused: \(r)"
        case .opened(let r): return "opened: \(r)"
        case .dryRun: return "dryRun"
        case .error(let r): return "error: \(r)"
        }
    }

    @Test func everyGatePassedOpensOneDraft() async throws {
        let (outcome, log) = try await Self.attempt()
        #expect(Self.reason(outcome) == "opened: https://github.com/o/r/pull/1", "\(log.all)")
        #expect(log.did("publish recipe-autofix/issue-42"))
        #expect(log.all.contains("body Refs #42\n"))
        let paths = try #require(log.all.first { $0.hasPrefix("paths ") })
        #expect(paths.contains(ChangelogAutofix.generationPath))
        #expect(paths.contains(ChangelogAutofix.generationPinPath))
        #expect(paths.contains(Self.familyPath) && paths.contains(Self.goldenPath)
                && paths.contains(".json") && paths.contains(".txt"))
        #expect(log.all.filter { $0 == "make test" || $0 == "verify" } == ["make test", "verify"])
    }

    @Test func aDryRunRunsEveryGateAndPublishesNothing() async throws {
        let (outcome, log) = try await Self.attempt(dryRun: true)
        #expect(Self.reason(outcome) == "dryRun", "\(log.all)")
        #expect(log.did("verify"))
        #expect(!log.all.contains { $0.hasPrefix("publish") })
    }

    @Test func g0APageThatHealedIsNotAttempted() async throws {
        var world = World()
        world.page = "<h2>3.0</h2><ul><li>Fine again</li></ul>"
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("notAttempted: no longer failing"), "\(Self.reason(outcome))")
        #expect(!log.did("ask"))
    }

    @Test func g0ACollapseThatHealedIsNotAttempted() async throws {
        var world = World()
        world.page = "<h2>3.0</h2><li>a</li><h2>2.0</h2><li>b</li>"
        let (outcome, log) = try await Self.attempt(world, trigger: .collapse)
        #expect(Self.reason(outcome).hasPrefix("notAttempted: no longer failing"))
        #expect(!log.did("ask"))
    }

    @Test func emptyVendorNotesNeverReachTheModel() async throws {
        var world = World()
        world.page = "<h2>3.0</h2><p>Nothing to see.</p>"
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).contains("has no notes"), "\(Self.reason(outcome))")
        #expect(!log.did("ask"))
    }

    @Test func anOffHostSourceIsRefusedBeforeItIsFetched() async throws {
        var world = World()
        world.reply = Self.reply(source: "https://attacker.example.net/notes", entryPattern: nil)
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused"))
        #expect(!log.all.contains { $0.hasPrefix("fetch /notes") })
        #expect(!log.did("prepare"))
    }

    @Test func aMovedSourceIsReadFromTheNewPage() async throws {
        var world = World()
        world.page = "<p>This page moved.</p>"
        world.movedPage = Self.restyled
        world.reply = Self.reply(source: "https://notes.example.com/releases")
        let (outcome, log) = try await Self.attempt(world, dryRun: true)
        #expect(Self.reason(outcome) == "dryRun", "\(Self.reason(outcome))")
        #expect(log.did("fetch /releases"))
    }

    @Test func g1APatternThatReadsNothingStopsBeforeTheWorktree() async throws {
        var world = World()
        world.reply = Self.reply(entryPattern: #"<h4>(?<version>[0-9.]+)</h4>(?<body>.*)"#)
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G1"), "\(Self.reason(outcome))")
        #expect(!log.did("prepare"))
    }

    @Test func g2FewerEntriesThanLastGoodStops() async throws {
        var entry = Baseline.Entry()
        entry.lastGoodEntryCount = 5
        let (outcome, log) = try await Self.attempt(entry: entry)
        #expect(Self.reason(outcome).hasPrefix("refused: G2"), "\(Self.reason(outcome))")
        #expect(!log.did("prepare"))
    }

    @Test func g3AnOlderNewestEntryStops() async throws {
        var entry = Baseline.Entry()
        entry.lastGoodVersion = "4.0"
        let (outcome, log) = try await Self.attempt(entry: entry)
        #expect(Self.reason(outcome).hasPrefix("refused: G3"), "\(Self.reason(outcome))")
        #expect(!log.did("prepare"))
    }

    @Test func g4AGoldenChangedElsewhereStopsBeforeTests() async throws {
        var world = World()
        world.goldenTamper = {
            $0.replacingOccurrences(of: "acknowledgedStaleEntry = nil", with: "acknowledgedStaleEntry = \"2.0\"")
        }
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G4"), "\(Self.reason(outcome))")
        #expect(!log.did("make test"))
    }

    @Test func theGenerationIsBumpedWithItsBulletAndNothingElse() throws {
        typealias A = ChangelogAutofix
        let note = A.generationNote(
            Self.recipe, trigger: .collapse, edit: .init(entryPattern: Self.newPattern), issue: 821)
        let bumped = try A.bumpingGeneration(in: Self.changelogSwift, note: note)
        #expect(bumped.contains("public static let parserGeneration = 19"))
        #expect(bumped.contains("/// - 19: com.example.autofix's changelog recipe has a new `entryPattern`"))
        #expect(bumped.components(separatedBy: "\n").allSatisfy { $0.count <= 100 })
        #expect(A.generationRefusal(old: Self.changelogSwift, new: bumped) == nil)
        // Not up by exactly one.
        #expect(A.generationRefusal(old: Self.changelogSwift, new: Self.changelogSwift) != nil)
        #expect(A.generationRefusal(
            old: Self.changelogSwift,
            new: bumped.replacingOccurrences(of: "= 19", with: "= 20")) != nil)
        // A consistent jump: bullet and constant agree, but not on the next number.
        #expect(A.generationRefusal(
            old: Self.changelogSwift,
            new: bumped.replacingOccurrences(of: "= 19", with: "= 25")
                .replacingOccurrences(of: "/// - 19:", with: "/// - 25:")) != nil)
        // A line of code slipped in under a well-formed bullet.
        #expect(A.generationRefusal(
            old: Self.changelogSwift,
            new: bumped.replacingOccurrences(
                of: "    public static let parserGeneration = 19",
                with: "    static var x = 1\n    public static let parserGeneration = 19")) != nil)
        // Anything else in the file.
        #expect(A.generationRefusal(
            old: Self.changelogSwift,
            new: bumped.replacingOccurrences(of: "public struct Changelog", with: "public struct Changelog2")) != nil)
        // Added lines that are not doc comment.
        #expect(A.generationRefusal(
            old: Self.changelogSwift,
            new: bumped.replacingOccurrences(of: "/// - 19:", with: "static var x = 1 // - 19:")) != nil)
        #expect(throws: (any Error).self) { try A.bumpingGeneration(in: "no constant here", note: note) }
    }

    @Test func thePinMovesWithTheGenerationAndAlone() throws {
        typealias A = ChangelogAutofix
        let pinned = try A.bumpingPin(in: Self.pinTest)
        #expect(pinned.contains("#expect(Changelog.parserGeneration == 19)"))
        #expect(A.pinRefusal(old: Self.pinTest, new: pinned, generation: 19) == nil)
        #expect(A.pinRefusal(old: Self.pinTest, new: Self.pinTest, generation: 19) != nil)
        #expect(A.pinRefusal(old: Self.pinTest, new: pinned, generation: 20) != nil)
        #expect(A.pinRefusal(
            old: Self.pinTest, new: pinned.replacingOccurrences(of: "pinnedGeneration", with: "other"),
            generation: 19) != nil)
        #expect(throws: (any Error).self) { try A.bumpingPin(in: "nothing pinned") }
    }

    /// Review round 2 on #1194: the harness bumped the constant and not its pin,
    /// so `make test` — stubbed everywhere above — failed every real attempt.
    /// This bumps the repository's own two files and holds them to each other and
    /// to the gates, so a change to either file's shape fails here first.
    @Test func theRealGenerationAndItsPinBumpTogether() throws {
        typealias A = ChangelogAutofix
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let changelog = try String(contentsOf: root.appendingPathComponent(A.generationPath), encoding: .utf8)
        let pin = try String(contentsOf: root.appendingPathComponent(A.generationPinPath), encoding: .utf8)
        let current = try #require(A.declaredGeneration(in: changelog))
        #expect(pin.contains("#expect(Changelog.parserGeneration == \(current))"),
                "the pin and the constant already disagree")
        let note = A.generationNote(Self.recipe, trigger: .noEntries, edit: .init(entryPattern: "x"), issue: 1)
        let newChangelog = try A.bumpingGeneration(in: changelog, note: note)
        let newPin = try A.bumpingPin(in: pin)
        #expect(A.declaredGeneration(in: newChangelog) == current + 1)
        #expect(A.generationRefusal(old: changelog, new: newChangelog) == nil)
        #expect(A.pinRefusal(old: pin, new: newPin, generation: current + 1) == nil)
    }

    @Test func g4APinOutOfStepStopsBeforeTests() async throws {
        var world = World()
        world.pinTamper = { $0.replacingOccurrences(of: "== 19", with: "== 18") }
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G4: the guard test"), "\(Self.reason(outcome))")
        #expect(!log.did("make test"))
    }

    @Test func g4AGenerationFileChangedElsewhereStopsBeforeTests() async throws {
        var world = World()
        world.generationTamper = { $0 + "\n// extra\n" }
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G4: Changelog.swift"), "\(Self.reason(outcome))")
        #expect(!log.did("make test"))
    }

    @Test func g5AStrayFileStopsBeforeTests() async throws {
        var world = World()
        world.strayFile = ".github/workflows/ci.yml"
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G5"), "\(Self.reason(outcome))")
        #expect(!log.did("make test"))
    }

    @Test func g6AFailingSuiteStopsBeforeVerify() async throws {
        var world = World()
        world.testStatus = 2
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G6"), "\(Self.reason(outcome))")
        // Why, without re-running it on the mini.
        #expect(Self.reason(outcome).contains("make: *** [test-scripts] Error 1"))
        #expect(!log.did("verify"))
        #expect(!log.all.contains { $0.hasPrefix("publish") })
    }

    @Test func g7ADegradedVerifyStopsThePullRequest() async throws {
        var world = World()
        world.verifyStatus = .warn
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G7"), "\(Self.reason(outcome))")
        #expect(!log.all.contains { $0.hasPrefix("publish") })
    }

    @Test func aTreeThatChangedDuringTheGatesIsNotPublished() async throws {
        var world = World()
        world.treeChangesDuringGates = true
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: G5"), "\(Self.reason(outcome))")
        #expect(!log.all.contains { $0.hasPrefix("publish") })
    }

    @Test func aSharedPatternIsRefusedAfterTheModelSoItIsNotAskedAgain() async throws {
        var world = World()
        world.family = Self.familyFile.replacingOccurrences(
            of: "entryPattern: #\"\(Self.oldPattern)\"#", with: "entryPattern: sharedPattern")
        let (outcome, log) = try await Self.attempt(world)
        #expect(Self.reason(outcome).hasPrefix("refused: the family file"), "\(Self.reason(outcome))")
        #expect(!log.did("goldens"))
    }
}
