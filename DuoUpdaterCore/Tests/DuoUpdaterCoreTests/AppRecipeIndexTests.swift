import Testing
import Foundation
@testable import DuoUpdaterCore

/// The shape `Recipes/` has to keep: one file per app family, one line per
/// family in `AppRecipeIndex.all`, and the registries derived from nothing else.
///
/// Derived from the index and the directory listing, never from a written-down
/// roster — a roster is the thing that would drift.
struct AppRecipeIndexTests {

    private static let recipesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DuoUpdaterCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // DuoUpdaterCore
        .appendingPathComponent("Sources/DuoUpdaterCore/Recipes")

    /// The two files in `Recipes/` that are not a family.
    private static let infrastructure: Set<String> = ["AppRecipeSet.swift", "AppRecipeIndex.swift"]

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
    /// cannot hold two files that differ only in case.
    @Test func familySlugsAreUniqueAndWellFormed() {
        let slugs = AppRecipeIndex.all.map(\.family)
        let malformed = slugs.filter { $0.wholeMatch(of: /[A-Za-z0-9.-]+/) == nil }
        #expect(malformed.isEmpty, Comment(rawValue: "malformed family slugs: \(malformed)"))
        let repeated = Dictionary(grouping: slugs, by: { $0.lowercased() })
            .filter { $0.value.count > 1 }.keys.sorted()
        #expect(repeated.isEmpty, Comment(rawValue: "family slugs listed more than once: \(repeated)"))
    }

    /// Mutation: add a family file without listing it in `AppRecipeIndex.all`, or
    /// change a family's `family:` string so it no longer names its file.
    @Test func familySlugsAreTheFileNames() throws {
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: Self.recipesDirectory.path)
            .filter { $0.hasSuffix(".swift") })
            .subtracting(Self.infrastructure)
        let slugs = Set(AppRecipeIndex.all.map { $0.family + ".swift" })
        #expect(!files.isEmpty, "no family files found under \(Self.recipesDirectory.path)")
        #expect(files.subtracting(slugs).isEmpty,
                "files with no family in AppRecipeIndex.all: \(files.subtracting(slugs).sorted())")
        #expect(slugs.subtracting(files).isEmpty,
                "families whose slug names no file: \(slugs.subtracting(files).sorted())")
    }

    /// Mutation: swap two adjacent lines of `AppRecipeIndex.all`, or append a new
    /// family at the end instead of at its sorted place.
    @Test func theIndexIsSortedBySlug() {
        let slugs = AppRecipeIndex.all.map { $0.family.lowercased() }
        let outOfOrder = zip(slugs, slugs.dropFirst()).filter { !($0 < $1) }
        #expect(outOfOrder.isEmpty,
                Comment(rawValue: "not strictly ascending: \(outOfOrder.map { "\($0) ≥ \($1)" })"))
    }

    /// Mutation: derive a registry from anything but the whole index — e.g.
    /// `AppRecipeIndex.all.dropFirst().flatMap(\.probes)`, or a literal appended
    /// to a derivation.
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
