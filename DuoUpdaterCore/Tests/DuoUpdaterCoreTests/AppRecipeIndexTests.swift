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

    /// Mutations (the data half): put a `Foo.JSON5`, a `sub/` or a symlink beside the
    /// families. Mutations: add a Swift family file without listing it in
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

        // Every entry, hidden ones included: a `Foo.JSON5` or `sub/` next to the
        // families is shipped by `.copy` and never loaded, so it is a failure here,
        // not a file to filter out.
        let entries = try fileManager.contentsOfDirectory(atPath: Self.dataDirectory.path)
        let strays = entries.filter { name in
            var isDirectory: ObjCBool = false
            let path = Self.dataDirectory.appendingPathComponent(name).path
            let link = (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
            return !RecipeFamilyFile.isFamilyFileName(name) || link
                || !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) || isDirectory.boolValue
        }
        #expect(strays.isEmpty, "entries in \(Self.dataDirectory.path) that are not family files: \(strays.sorted())")
        let dataFiles = Set(entries)
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

    /// A scratch recipe directory, removed when the returned value's `remove` runs.
    /// Made in THIS process and handed to the exit tests by path, so the child never
    /// creates a directory it cannot clean up (it dies on purpose).
    private struct Scratch {
        let url: URL
        var path: String { url.path }
        init(_ files: [String: String] = [:]) throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("duo-recipe-fixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, text) in files {
                try Data(text.utf8).write(to: url.appendingPathComponent(name))
            }
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }

    private static func stderr(_ result: ExitTest.Result?) -> String {
        String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    }

    /// The trap is real, and its message is the file and the path. Run in a child
    /// process, since the point is that the process dies.
    /// Mutations: make `AppRecipeIndex.dataFamilies(in:bundle:expectedDigest:)` return
    /// `[]` on a load error; drop the empty-directory guard in
    /// `RecipeFamilyFile.readFamilyFiles`; drop the `guard let directory` trap (a
    /// bundle with no `Recipes` directory would then crash on force-unwrap or load
    /// nothing).
    @Test func aDataFamilyProblemTraps() async throws {
        let broken = try Scratch(["zz-broken.json5": #"{"probes": [{"bundleID": "zz"}]}"#])
        let empty = try Scratch()
        defer { broken.remove(); empty.remove() }

        let decode = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) { [path = broken.path as String] in
            _ = AppRecipeIndex.dataFamilies(in: URL(fileURLWithPath: path), bundle: "fixture", expectedDigest: nil)
        }
        #expect(Self.stderr(decode).contains("recipe data: Recipes/zz-broken.json5: probes[0].url: required key is missing"),
                "\(Self.stderr(decode))")

        let none = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) { [path = empty.path as String] in
            _ = AppRecipeIndex.dataFamilies(in: URL(fileURLWithPath: path), bundle: "fixture", expectedDigest: nil)
        }
        #expect(Self.stderr(none).contains("holds no .json5 family files"), "\(Self.stderr(none))")

        let noDirectory = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            _ = AppRecipeIndex.dataFamilies(in: nil, bundle: "/fixture/X.bundle", expectedDigest: nil)
        }
        #expect(Self.stderr(noDirectory).contains("recipe data: no `Recipes` directory in /fixture/X.bundle"),
                "\(Self.stderr(noDirectory))")
    }

    /// Anything in the directory but regular `<slug>.json5` files is refused, by name,
    /// before anything is decoded.
    /// Mutations: filter by extension instead of refusing; compare the extension
    /// case-insensitively; let the slug start with `.` (the `.zz.json5` case, which a
    /// dotfile with a bad extension would not catch — `.DS_Store` fails on its
    /// extension); drop the symlink branch (measured: `URLResourceValues` on a symlink
    /// reports `isSymbolicLink` true and `isRegularFile` false — it does NOT follow the
    /// link — so the regular-file branch refuses it too; this pins that the reason
    /// given is "a symbolic link", not "not a regular file").
    @Test(arguments: ["other extension", "upper-case extension", "dotfile", "hidden json5",
                      "subdirectory", "symlink", "leading dash"])
    func aStrayEntryIsRefused(_ kind: String) throws {
        let valid = #"{"changelogPages": {"zz.fixture": "https://example.invalid/"}}"#
        let scratch = try Scratch(["zz-fixture.json5": valid])
        defer { scratch.remove() }
        let fileManager = FileManager.default
        let expected: String
        switch kind {
        case "other extension":
            try Data(valid.utf8).write(to: scratch.url.appendingPathComponent("zz-other.json"))
            expected = "zz-other.json (not named <slug>.json5)"
        case "upper-case extension":
            try Data(valid.utf8).write(to: scratch.url.appendingPathComponent("zz-other.JSON5"))
            expected = "zz-other.JSON5 (not named <slug>.json5)"
        case "dotfile":
            try Data([0]).write(to: scratch.url.appendingPathComponent(".DS_Store"))
            expected = ".DS_Store (not named <slug>.json5)"
        case "hidden json5":
            // A leading dot with the right extension: the slug rule (first char a
            // letter or digit) is what refuses this, not the extension check.
            try Data(valid.utf8).write(to: scratch.url.appendingPathComponent(".zz.json5"))
            expected = ".zz.json5 (not named <slug>.json5)"
        case "subdirectory":
            let sub = scratch.url.appendingPathComponent("sub")
            try fileManager.createDirectory(at: sub, withIntermediateDirectories: false)
            try Data(valid.utf8).write(to: sub.appendingPathComponent("zz-deep.json5"))
            expected = "sub (not a regular file)"
        case "symlink":
            try fileManager.createSymbolicLink(
                at: scratch.url.appendingPathComponent("zz-link.json5"),
                withDestinationURL: scratch.url.appendingPathComponent("zz-fixture.json5"))
            expected = "zz-link.json5 (a symbolic link)"
        default:
            try Data(valid.utf8).write(to: scratch.url.appendingPathComponent("-zz.json5"))
            expected = "-zz.json5 (not named <slug>.json5)"
        }
        do {
            _ = try RecipeFamilyFile.loadAll(from: scratch.url)
            Issue.record("loaded a directory holding a \(kind)")
        } catch {
            #expect("\(error)".contains("holds entries that are not family files"), "\(error)")
            #expect("\(error)".contains(expected), "\(error)")
        }
    }

    /// The same two-file fixture and hex as `scripts/test_recipe_digest.py`, whose
    /// answer was also computed by piping the framed bytes to `shasum -a 256`.
    /// `scripts/build-cli.sh` embeds the Python digest; the loader computes this one.
    /// Mutations: drop the name, the byte count or the sort from
    /// `RecipeFamilyFile.digest`.
    @Test func theRecipeDigestHasOneKnownAnswer() throws {
        let scratch = try Scratch(["b-app.json5": "// c\n{\"probes\": []}\n", "a-app.json5": "{}\n"])
        defer { scratch.remove() }
        let files = try RecipeFamilyFile.readFamilyFiles(in: scratch.url)
        #expect(RecipeFamilyFile.digest(of: files) == "8fdc639d4711a2edc32eb757828c6e2b89c5c98a7c10051cd1242814a11a8692")
        #expect(RecipeFamilyFile.digest(of: files.reversed()) == RecipeFamilyFile.digest(of: files))
    }

    /// With a digest to hold them to, recipe files that differ by one byte do not
    /// load, and the trap names both digests; the right digest loads.
    /// Mutations: skip the comparison in `loadAll`; let an empty digest pass. (The
    /// read-once property — that `loadAll` hashes the same bytes it decodes — is not
    /// asserted here; catching it would need a writer racing between the hash and the
    /// decode, which this single-threaded test has no way to stage. The single read
    /// in `loadAll` is what it rests on.)
    @Test func recipeFilesThatDoNotMatchTheBuiltDigestAreRefused() async throws {
        let text = #"{"changelogPages": {"zz.fixture": "https://example.invalid/"}}"#
        let scratch = try Scratch(["zz-fixture.json5": text])
        defer { scratch.remove() }
        let built = RecipeFamilyFile.digest(of: try RecipeFamilyFile.readFamilyFiles(in: scratch.url))
        #expect(try RecipeFamilyFile.loadAll(from: scratch.url, expectedDigest: built).count == 1)

        try Data((text + "\n").utf8).write(to: scratch.url.appendingPathComponent("zz-fixture.json5"))
        let found = RecipeFamilyFile.digest(of: try RecipeFamilyFile.readFamilyFiles(in: scratch.url))
        #expect(found != built)
        #expect(throws: RecipeFamilyFile.LoadFailure.self) {
            try RecipeFamilyFile.loadAll(from: scratch.url, expectedDigest: "")
        }

        let trap = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            [path = scratch.path as String, built = built as String] in
            _ = AppRecipeIndex.dataFamilies(in: URL(fileURLWithPath: path), bundle: "fixture", expectedDigest: built)
        }
        let message = Self.stderr(trap)
        #expect(message.contains("are not the ones this executable was built with"), "\(message)")
        #expect(message.contains("built with \(built), found \(found)"), "\(message)")
    }

    /// The digest is read from the executable's own `__TEXT,__info_plist` section,
    /// not through `Bundle.main`, so an `Info.plist` file beside a bare `duo` cannot
    /// supply or override it (the reproduced bypass). This drives the section parser
    /// with fixture bytes — a test process has no section of its own to plant a real
    /// one in, so this proves the parser, not the section lookup; the section lookup
    /// is proven end to end by `build-cli.sh`'s self-test against the real binary.
    /// Mutations: read `Bundle.main` again; return the whole dict; ignore the key.
    @Test func theDigestIsParsedFromAnInfoPlistSection() throws {
        func plist(_ dictionary: [String: Any]) -> Data {
            try! PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        }
        #expect(RecipeFamilyFile.digest(
            fromInfoPlistSection: plist(["CFBundleIdentifier": "zz", "DuoRecipeDigest": "abc"])) == "abc")
        // Present but unexpanded (built without DUO_RECIPE_DIGEST): "" so loadAll traps.
        #expect(RecipeFamilyFile.digest(fromInfoPlistSection: plist(["DuoRecipeDigest": ""])) == "")
        // No key, wrong type, and non-plist bytes all read as "skip".
        #expect(RecipeFamilyFile.digest(fromInfoPlistSection: plist(["CFBundleIdentifier": "zz"])) == nil)
        #expect(RecipeFamilyFile.digest(fromInfoPlistSection: plist(["DuoRecipeDigest": 7])) == nil)
        #expect(RecipeFamilyFile.digest(fromInfoPlistSection: Data("not a plist".utf8)) == nil)
    }

    /// What `embeddedDigest` returns in THIS process. The test bundle is loaded by a
    /// test runner whose main executable carries no `DuoRecipeDigest` (it is not built
    /// by `build-cli.sh`), so the answer is nil and the check is skipped — which is
    /// exactly why a test process could never have caught the S7 bypass, and why the
    /// gate for it lives in `build-cli.sh`. This cannot prove the positive case (a
    /// section whose key is read): only a binary built with the section can, which
    /// `build-cli.sh`'s real-mode self-test does.
    @Test func embeddedDigestIsNilInTheTestProcess() {
        #expect(RecipeFamilyFile.embeddedDigest() == nil)
        // The lookup at least resolves the main image (a non-nil header), so a nil
        // digest means "no key", not "no header".
        #expect(RecipeFamilyFile.mainExecutableHeader() != nil)
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
