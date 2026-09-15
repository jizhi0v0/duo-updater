import Testing
import Foundation
@testable import DuoUpdaterCore

/// The shape the recipe families have to keep: one file per app family — a
/// `.swift` file under `Recipes/` with one line in `AppRecipeIndex.swiftFamilies`,
/// or a `.json5` file under `Resources/Recipes/` — and the registries derived from
/// `AppRecipeIndex.all` and nothing else.
///
/// Derived from the index and the directory listings, never from a written-down
/// roster — a roster is the thing that would drift.
struct AppRecipeIndexTests {

    private static let targetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .appendingPathComponent("Sources/DuoUpdaterCore")
    private static let recipesDirectory = targetDirectory.appendingPathComponent("Recipes")
    /// Where the `.copy` resource in `Package.swift` comes from.
    private static let dataDirectory = targetDirectory.appendingPathComponent("Resources/Recipes")

    /// The two files in `Recipes/` that are not a family.
    private static let infrastructure: Set<String> = ["AppRecipeSet.swift", "AppRecipeIndex.swift"]

    /// Every kind of data an `AppRecipeSet` carries, declared once. (A list of
    /// kinds, not of apps — it changes only when `AppRecipeSet` does.)
    ///
    /// Adding a label here means also adding the kind to `AppRecipeSet.bundleIDs`
    /// and to `theRegistriesAreExactlyTheSumOfTheFamilies`: both enumerate the
    /// kinds by hand, and a kind missing from either passes every other test here.
    private static let recipeKinds: Set<String> = [
        "probes", "changelogs", "githubRules", "appStoreCases",
        "channelProofs", "githubChannelProofs", "bindingProofs",
        "sparkleFeeds", "supersededFeeds", "changelogPages",
    ]

    /// Mutation: give one family an entry for another family's bundle id (for
    /// example a `changelogPages` key naming an app that has its own file).
    /// Lowercased because that is how `ChangelogRecipeRegistry`, `ChangelogCatalog`
    /// and `SparkleFeedCatalog` look ids up — two spellings of one id are one app.
    @Test func noBundleIDBelongsToTwoFamilies() {
        var owner: [String: String] = [:]
        var clashes: [String] = []
        for set in AppRecipeIndex.all {
            for id in Set(set.bundleIDs.map { $0.lowercased() }) {
                if let first = owner[id], first != set.family {
                    clashes.append("\(id): \(first) and \(set.family)")
                }
                owner[id] = owner[id] ?? set.family
            }
        }
        #expect(clashes.isEmpty, Comment(rawValue: clashes.sorted().joined(separator: "\n")))
    }

    /// Mutation: add a family whose `AppRecipeSet` declares nothing of any kind.
    @Test func everyFamilyDeclaresSomething() {
        let empty = AppRecipeIndex.all.filter(\.bundleIDs.isEmpty).map(\.family)
        #expect(empty.isEmpty, Comment(rawValue: "families with no entries: \(empty)"))
    }

    /// Mutation: rename a family (file and slug together) to a slug with `_` in it.
    /// Uniqueness is checked case-insensitively too: the default macOS volume
    /// cannot hold two files that differ only in case. A slug starts with a letter or
    /// digit: a leading `.` names a hidden file, which `RecipeGoldenTests` skips when
    /// listing goldens, so that family's golden would read as missing forever.
    @Test func familySlugsAreUniqueAndWellFormed() {
        let slugs = AppRecipeIndex.all.map(\.family)
        let malformed = slugs.filter { $0.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9.-]*/) == nil }
        #expect(malformed.isEmpty, Comment(rawValue: "malformed family slugs: \(malformed)"))
        let repeated = Dictionary(grouping: slugs, by: { $0.lowercased() })
            .filter { $0.value.count > 1 }.keys.sorted()
        #expect(repeated.isEmpty, Comment(rawValue: "family slugs listed more than once: \(repeated)"))
    }

    /// Mutations: add a Swift family file without listing it in
    /// `AppRecipeIndex.swiftFamilies`, or change a family's `family:` string so it
    /// no longer names its file; convert a family to `.json5` and leave its `.swift`
    /// file (or its `swiftFamilies` line) behind; delete a `.json5` family file.
    /// The data half reads the source directory, and the index read the bundle
    /// built from it, so it also goes red if the bundle stops carrying a file.
    @Test func familySlugsAreTheFileNames() throws {
        let fileManager = FileManager.default
        let swiftFiles = Set(try fileManager.contentsOfDirectory(atPath: Self.recipesDirectory.path)
            .filter { $0.hasSuffix(".swift") })
            .subtracting(Self.infrastructure)
        let swiftSlugs = Set(AppRecipeIndex.swiftFamilies.map { $0.family + ".swift" })
        #expect(!swiftFiles.isEmpty, "no family files found under \(Self.recipesDirectory.path)")
        #expect(swiftFiles.subtracting(swiftSlugs).isEmpty,
                "files with no family in AppRecipeIndex.swiftFamilies: \(swiftFiles.subtracting(swiftSlugs).sorted())")
        #expect(swiftSlugs.subtracting(swiftFiles).isEmpty,
                "Swift families whose slug names no file: \(swiftSlugs.subtracting(swiftFiles).sorted())")

        let dataFiles = Set(try fileManager.contentsOfDirectory(atPath: Self.dataDirectory.path)
            .filter { $0.hasSuffix("." + RecipeFamilyFile.fileExtension) })
        let dataSlugs = Set(AppRecipeIndex.dataFamilies.map { $0.family + "." + RecipeFamilyFile.fileExtension })
        // Floor: every other expectation on the data half passes on two empty sets.
        #expect(!dataFiles.isEmpty, "no .json5 family files found under \(Self.dataDirectory.path)")
        #expect(dataFiles == dataSlugs,
                "source \(Self.dataDirectory.path) holds \(dataFiles.sorted()); the bundle loaded \(dataSlugs.sorted())")

        let stems = { (names: Set<String>) in Set(names.map { ($0 as NSString).deletingPathExtension.lowercased() }) }
        let both = stems(swiftFiles).intersection(stems(dataFiles))
        #expect(both.isEmpty, "families written both as Swift and as data: \(both.sorted())")
        #expect(AppRecipeIndex.all.count == AppRecipeIndex.swiftFamilies.count + AppRecipeIndex.dataFamilies.count)
    }

    /// Mutations: swap two adjacent lines of `AppRecipeIndex.swiftFamilies`, or
    /// append a new family at the end instead of at its sorted place (the literal);
    /// drop the `sorted` from `AppRecipeIndex.all` (the merge).
    @Test func theIndexIsSortedBySlug() {
        for (name, families) in [("all", AppRecipeIndex.all), ("swiftFamilies", AppRecipeIndex.swiftFamilies)] {
            let slugs = families.map { $0.family.lowercased() }
            let outOfOrder = zip(slugs, slugs.dropFirst()).filter { !($0 < $1) }
            #expect(outOfOrder.isEmpty,
                    Comment(rawValue: "\(name) not strictly ascending: \(outOfOrder.map { "\($0) ≥ \($1)" })"))
        }
    }

    /// Adding a kind to `AppRecipeSet` must be a decision, not an omission (same
    /// idea as `channelAnchorSurfaceCoversEveryRecipeField`): `bundleIDs` and the
    /// sum test below list the kinds by hand, so a new stored property would slip
    /// past both. Mutation: add a stored property to `AppRecipeSet`, e.g.
    /// `let extra: [String: URL] = [:]`. The family file format lists the kinds a
    /// third time; mutation: drop a case from `RecipeFamilyFile.CodingKeys`.
    @Test func everyStoredKindIsDeclared() throws {
        let set = try #require(AppRecipeIndex.all.first)
        let labels = Set(Mirror(reflecting: set).children.compactMap(\.label)).subtracting(["family"])
        #expect(labels == Self.recipeKinds,
                Comment(rawValue: "AppRecipeSet stored properties \(labels.sorted()) differ from recipeKinds \(Self.recipeKinds.sorted()): add the kind to recipeKinds, bundleIDs and the sum test"))
        let fileKeys = Set(RecipeFamilyFile.CodingKeys.allCases.map(\.stringValue))
        #expect(fileKeys == Self.recipeKinds,
                Comment(rawValue: "RecipeFamilyFile keys \(fileKeys.sorted()) differ from recipeKinds \(Self.recipeKinds.sorted())"))
    }

    // MARK: - Data families

    /// What an author sees: the file and the coding path, not a debug dump.
    /// Mutation: have `RecipeFamilyFile.problem` return `"\(error)"`.
    @Test func aDecodeProblemNamesTheFileAndThePath() throws {
        let cases: [(json: String, expected: String)] = [
            (#"{"probes":[{"bundleID":"zz","url":"https://example.invalid/","mode":{"kind":"responseBody"},"versionPattern":"x","selectHighst":true}]}"#,
             "Recipes/zz.json5: probes[0].selectHighst: unknown key `selectHighst`"),
            (#"{"probes":[{"bundleID":"zz","url":"https://example.invalid/","mode":{"kind":"responseBody"},"versionPattern":"x","selectHighest":"yes"}]}"#,
             "Recipes/zz.json5: probes[0].selectHighest: expected Bool"),
            (#"{"channelProofs":[{"bundleID":"zz","channel":"beta","proof":{"kind":"artefact","pattern":"b"}}]}"#,
             "Recipes/zz.json5: channelProofs[0].proof.kind: unknown kind `artefact`"),
            (#"{"probs":[]}"#, "Recipes/zz.json5: probs: unknown key `probs`"),
        ]
        for (json, expected) in cases {
            do {
                _ = try RecipeFamilyFile.decode(Data(json.utf8), family: "zz")
                Issue.record("decoded: \(json)")
            } catch {
                let text = RecipeFamilyFile.problem(decoding: error, file: "Recipes/zz.json5")
                #expect(text.hasPrefix(expected), "\(text)")
            }
        }
    }

    /// Absent kinds are empty, and a file holds nothing but what it says.
    /// Mutation: default `probes` to anything but `[]`; stop refusing `null`.
    @Test func anAbsentKindIsEmptyAndNullIsRefused() throws {
        let set = try RecipeFamilyFile.decode(Data("// only a comment\n{}".utf8), family: "zz")
        #expect(set.family == "zz")
        #expect(set.bundleIDs.isEmpty)
        #expect(throws: DecodingError.self) {
            try RecipeFamilyFile.decode(Data(#"{"probes": null}"#.utf8), family: "zz")
        }
    }

    /// The trap is real, and its message is the file and the path. Run in a child
    /// process, since the point is that the process dies.
    /// Mutations: make `AppRecipeIndex.dataFamilies(in:bundle:)` return `[]` on a
    /// decode error; drop the empty-directory guard in `RecipeFamilyFile.loadAll`.
    @Test func aFamilyFileThatDoesNotDecodeTraps() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-recipe-trap-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(#"{"probes": [{"bundleID": "zz"}]}"#.utf8)
                .write(to: directory.appendingPathComponent("zz-broken.json5"))
            _ = AppRecipeIndex.dataFamilies(in: directory, bundle: "fixture")
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("recipe data: Recipes/zz-broken.json5: probes[0].url: required key is missing"), "\(stderr)")

        let empty = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-recipe-empty-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = AppRecipeIndex.dataFamilies(in: directory, bundle: "fixture")
        }
        let emptyStderr = String(decoding: empty?.standardErrorContent ?? [], as: UTF8.self)
        #expect(emptyStderr.contains("holds no .json5 family files"), "\(emptyStderr)")
    }

    /// Mutation: derive a registry from anything but the whole index — e.g.
    /// `AppRecipeIndex.all.dropLast().flatMap(\.probes)`, or a literal appended
    /// to a derivation. (A dropped family only turns this red if it has entries
    /// of that kind: the last family by slug has a probe, the first has none, so
    /// `dropFirst()` on `probes` stays green.)
    @Test func theRegistriesAreExactlyTheSumOfTheFamilies() {
        let all = AppRecipeIndex.all
        func sum(_ count: (AppRecipeSet) -> Int) -> Int { all.reduce(0) { $0 + count($1) } }
        #expect(VendorProbeRegistry.recipes.count == sum { $0.probes.count })
        #expect(ChangelogRecipeRegistry.recipes.count == sum { $0.changelogs.count })
        #expect(GitHubReleaseRegistry.rules.count == sum { $0.githubRules.count })
        #expect(MacAppStoreProbeRegistry.cases.count == sum { $0.appStoreCases.count })
        #expect(ChannelProofRegistry.proofs.count == sum { $0.channelProofs.count })
        #expect(ChannelProofRegistry.githubProofs.count == sum { $0.githubChannelProofs.count })
        #expect(ChannelProofRegistry.bindingProofs.count == sum { $0.bindingProofs.count })
        #expect(SparkleFeedCatalog.feeds.count == sum { $0.sparkleFeeds.count })
        #expect(SparkleFeedCatalog.supersededFeeds.count == sum { $0.supersededFeeds.count })
        #expect(ChangelogCatalog.pages.count == sum { $0.changelogPages.count })
    }
}
