import Testing
import Foundation
@testable import DuoUpdaterCore

/// The JSON coding of every type an `AppRecipeSet` stores — the convention on
/// `RecipeCoding`. Nothing in production decodes recipes from JSON yet; these pin
/// the format and its strictness before anything does.
///
/// Values are compared by reflection (`RecipeMirror.dump`), not by encoding them
/// again: an encoder and a decoder that share a mistake agree with each other, and
/// none of these types is `Equatable`.
struct RecipeCodableTests {

    // MARK: - The population

    /// Every `DuoUpdaterCore` type reachable from the stored properties of the real
    /// registry, found by reflection — including through optionals that are nil
    /// and arrays that are empty, whose static types still name the element.
    ///
    /// Mutation: add a stored property of a new type to `VendorProbeRecipe` (even one
    /// that every recipe leaves nil). `everyReachableTypeHasACodingCase` goes red
    /// naming it.
    static let reachableTypes: Set<String> = {
        var names = Set<String>()
        let pattern = /DuoUpdaterCore\.[A-Za-z0-9_.]+/
        func collect(_ value: Any) {
            for match in String(reflecting: type(of: value)).matches(of: pattern) {
                names.insert(String(match.output))
            }
        }
        func visit(_ value: Any, depth: Int) {
            guard depth < 12, !(value is URL), !(value is Data), !(value is String) else { return }
            for child in Mirror(reflecting: value).children {
                collect(child.value)
                visit(child.value, depth: depth + 1)
            }
        }
        for set in AppRecipeIndex.all {
            for child in Mirror(reflecting: set).children where child.label != "family" {
                collect(child.value)
                visit(child.value, depth: 0)
            }
        }
        return names
    }()

    /// How each reachable type is exercised. Keyed by `String(reflecting:)`; the
    /// keys are held to `reachableTypes` in both directions, so this cannot silently
    /// fall behind the registry or keep a case for a type it no longer stores.
    static let codingCases: [String: CodingCase] = {
        let cases: [CodingCase] = [
            .structure(
                VendorProbeRecipe.self,
                keys: VendorProbeRecipe.CodingKeys.allCases.map(\.stringValue),
                required: #"{"bundleID":"zz.fixture","url":"https://example.invalid/v","mode":{"kind":"responseBody"},"versionPattern":"v([0-9.]+)"}"#,
                expected: VendorProbeRecipe(
                    bundleID: "zz.fixture", url: URL(string: "https://example.invalid/v")!,
                    mode: .responseBody, versionPattern: "v([0-9.]+)")),
            .structure(
                ChangelogRecipe.self,
                keys: ChangelogRecipe.CodingKeys.allCases.map(\.stringValue),
                required: #"{"bundleID":"zz.fixture","source":"https://example.invalid/notes"}"#,
                expected: ChangelogRecipe(
                    bundleID: "zz.fixture", source: URL(string: "https://example.invalid/notes")!)),
            .structure(
                GitHubReleaseRule.self,
                keys: GitHubReleaseRule.CodingKeys.allCases.map(\.stringValue),
                required: #"{"bundleID":"zz.fixture","owner":"zz","repo":"fixture"}"#,
                expected: GitHubReleaseRule(bundleID: "zz.fixture", owner: "zz", repo: "fixture")),
            .structure(
                MacAppStoreProbeCase.self,
                keys: MacAppStoreProbeCase.CodingKeys.allCases.map(\.stringValue),
                required: #"{"bundleID":"zz.fixture","trackId":1,"expectedKind":"mac-software","route":"nativeMac"}"#,
                expected: MacAppStoreProbeCase(
                    bundleID: "zz.fixture", trackId: 1, expectedKind: "mac-software", route: .nativeMac)),
            .structure(
                VendorInstallSpec.self,
                keys: VendorInstallSpec.CodingKeys.allCases.map(\.stringValue),
                required: #"{"urlSource":{"kind":"fixed","url":"https://example.invalid/a.zip"},"kind":"zip"}"#,
                expected: VendorInstallSpec(
                    urlSource: .fixed(URL(string: "https://example.invalid/a.zip")!), kind: .zip)),
            .structure(
                VendorHostRequirement.self,
                keys: VendorHostRequirement.CodingKeys.allCases.map(\.stringValue),
                required: "{}",
                expected: VendorHostRequirement()),
            .structure(
                VendorProbeRecipe.BuildLineageSpec.self,
                keys: VendorProbeRecipe.BuildLineageSpec.CodingKeys.allCases.map(\.stringValue),
                required: #"{"url":"https://example.invalid/list","entryPattern":"id=([0-9a-f]+)"}"#,
                expected: .init(url: URL(string: "https://example.invalid/list")!, entryPattern: "id=([0-9a-f]+)")),
            .structure(
                VendorProbeRecipe.RequestBody.self,
                keys: VendorProbeRecipe.RequestBody.CodingKeys.allCases.map(\.stringValue),
                required: #"{"json":"{}"}"#,
                expected: .init(json: "{}")),
            .structure(
                ProbeIdentity.self,
                keys: ProbeIdentity.CodingKeys.allCases.map(\.stringValue),
                required: #"{"location":{"kind":"home","path":".zz"},"encoding":{"kind":"plain"},"validationPattern":"[a-z]+"}"#,
                expected: ProbeIdentity(location: .home(".zz"), encoding: .plain, validationPattern: "[a-z]+")),
            .structure(
                RolloutTrack.self,
                keys: RolloutTrack.CodingKeys.allCases.map(\.stringValue),
                required: #"{"selector":{"location":{"kind":"home","path":".zz"},"encoding":{"kind":"plain"},"validationPattern":"[a-z]+"},"contrastValue":"free","contrastTrackName":"free"}"#,
                expected: RolloutTrack(
                    selector: ProbeIdentity(location: .home(".zz"), encoding: .plain, validationPattern: "[a-z]+"),
                    contrastValue: "free", contrastTrackName: "free")),
            .structure(
                ChannelProofKey.self,
                keys: ChannelProofKey.CodingKeys.allCases.map(\.stringValue),
                required: #"{"bundleID":"zz.fixture","channel":"beta"}"#,
                expected: ChannelProofKey("zz.fixture", .beta)),
            .structure(
                SparkleFeedCatalog.SupersededFeed.self,
                keys: SparkleFeedCatalog.SupersededFeed.CodingKeys.allCases.map(\.stringValue),
                required: #"{"declared":"https://example.invalid/old.xml","live":"https://example.invalid/new.xml"}"#,
                expected: .init(
                    declared: URL(string: "https://example.invalid/old.xml")!,
                    live: URL(string: "https://example.invalid/new.xml")!)),

            // Each sample beside the exact JSON it must encode to. These literals are
            // the format: change one only as a deliberate format change.
            .tagged(
                VendorProbeRecipe.Mode.self,
                tags: VendorProbeRecipe.Mode.CodingKind.allCases.map(\.rawValue),
                samples: [
                    (.redirectFilename, #"{"kind":"redirectFilename"}"#),
                    (.responseBody, #"{"kind":"responseBody"}"#),
                    (.zipEntryPlist(entry: "a/Info.plist", key: "K"),
                     #"{"kind":"zipEntryPlist","entry":"a/Info.plist","key":"K"}"#),
                    (.redirectArchiveInfoPlist(entry: "a/Info.plist"),
                     #"{"kind":"redirectArchiveInfoPlist","entry":"a/Info.plist"}"#),
                ]),
            .tagged(
                VendorInstallSpec.URLSource.self,
                tags: VendorInstallSpec.URLSource.CodingKind.allCases.map(\.rawValue),
                samples: [
                    (.bodyPattern("a(b)"), #"{"kind":"bodyPattern","pattern":"a(b)"}"#),
                    (.bodyPatternLast("c(d)"), #"{"kind":"bodyPatternLast","pattern":"c(d)"}"#),
                    (.bodyPatternHighestVersioned("(e)(f)"),
                     #"{"kind":"bodyPatternHighestVersioned","pattern":"(e)(f)"}"#),
                    (.bodyPatternRelative("(g)", base: URL(string: "https://example.invalid/")!),
                     #"{"kind":"bodyPatternRelative","pattern":"(g)","base":"https://example.invalid/"}"#),
                    (.bodyTemplate("https://example.invalid/{0}", fields: ["(h)"]),
                     #"{"kind":"bodyTemplate","template":"https://example.invalid/{0}","fields":["(h)"]}"#),
                    (.versionTemplate("https://example.invalid/{version}"),
                     #"{"kind":"versionTemplate","template":"https://example.invalid/{version}"}"#),
                    (.redirect(URL(string: "https://example.invalid/latest")!),
                     #"{"kind":"redirect","url":"https://example.invalid/latest"}"#),
                    (.fixed(URL(string: "https://example.invalid/a.dmg")!),
                     #"{"kind":"fixed","url":"https://example.invalid/a.dmg"}"#),
                ]),
            .tagged(
                ProbeIdentity.Encoding.self,
                tags: ProbeIdentity.Encoding.CodingKind.allCases.map(\.rawValue),
                samples: [
                    (.plain, #"{"kind":"plain"}"#),
                    (.base64, #"{"kind":"base64"}"#),
                    (.jsonKey("id"), #"{"kind":"jsonKey","key":"id"}"#),
                    (.jwtClaim(tokenPath: ["t"], claimPath: ["c", "d"]),
                     #"{"kind":"jwtClaim","tokenPath":["t"],"claimPath":["c","d"]}"#),
                ]),
            .tagged(
                ProbeIdentity.Location.self,
                tags: ProbeIdentity.Location.CodingKind.allCases.map(\.rawValue),
                samples: [
                    (.applicationSupport("A/id"), #"{"kind":"applicationSupport","path":"A/id"}"#),
                    (.home(".b/id"), #"{"kind":"home","path":".b/id"}"#),
                ]),
            .tagged(
                ChannelArtifactProof.self,
                tags: ChannelArtifactProof.CodingKind.allCases.map(\.rawValue),
                samples: [
                    (.artifact("/beta/"), #"{"kind":"artifact","pattern":"/beta/"}"#),
                    (.recipeAnchor("beta", in: ["url", "versionPattern"]),
                     #"{"kind":"recipeAnchor","pattern":"beta","fields":["url","versionPattern"]}"#),
                ],
                // `in` reads as a preposition in Swift (`recipeAnchor(p, in: fields)`)
                // and as nothing at all as a JSON key.
                keyForLabel: ["recipeAnchor.in": "fields"]),

            .caseName(VendorInstallerKind.self, all: VendorInstallerKind.allCases, name: { "\($0)" }),
            .caseName(HostArch.self, all: HostArch.allCases, name: { "\($0)" }),

            // Standard-library `RawRepresentable` coding, not code in this file:
            // listed so the population stays complete, checked for round trip only.
            .caseName(ReleaseChannel.self, all: ReleaseChannel.allCases, name: \.rawValue),
            .caseName(MacAppStoreProbeCase.Route.self, all: MacAppStoreProbeCase.Route.allCases, name: \.rawValue),
            .caseName(GitHubCandidateScope.self, all: [.newest, .installedMajorLineOrNewestStable], name: \.rawValue),
            .caseName(InstalledApp.BuildNamespace.self, all: [.bundle, .vendor], name: \.rawValue),
            .caseName(ChangelogRecipe.Mode.self, all: [.html, .json], name: \.rawValue),
            .caseName(ChangelogRecipe.HTTPMethod.self, all: [.get, .post], name: \.rawValue),
            .caseName(ChangelogRecipe.StructuredFormat.self, all: [.gitHubReleases, .warpChannelVersions], name: \.rawValue),
        ]
        return Dictionary(uniqueKeysWithValues: cases.map { ($0.typeName, $0) })
    }()

    @Test func everyReachableTypeHasACodingCase() {
        let missing = Self.reachableTypes.subtracting(Self.codingCases.keys).sorted()
        let stale = Set(Self.codingCases.keys).subtracting(Self.reachableTypes).sorted()
        #expect(missing.isEmpty, "types stored by AppRecipeSet with no coding case: \(missing)")
        #expect(stale.isEmpty, "coding cases for types AppRecipeSet no longer stores: \(stale)")
        // Floor: a reflection walk that found nothing would pass both lines above
        // with an empty table.
        #expect(Self.reachableTypes.count >= 20, "only \(Self.reachableTypes.sorted()) reachable")
    }

    /// Default parity, key sets, `null` handling and unknown keys, per type.
    ///
    /// Mutations: pass `false` instead of `d.followRedirects` in
    /// `VendorProbeRecipe.init(from:)` (parity); add a stored property to a struct
    /// without a coding key (key set); make `decode(_:forKey:default:)` return the
    /// default for `null` (null); make `rejectUnknownKeys` return early (unknown
    /// key); swap two raw values in `URLSource.CodingKind` (tag).
    @Test(arguments: RecipeCodableTests.codingCases.keys.sorted())
    func codingCaseHolds(_ typeName: String) throws {
        let failures = try #require(Self.codingCases[typeName]).check()
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    // MARK: - ChangelogRecipe.maxEntries

    /// Mutation: restore `decodeIfPresent(Int?.self, forKey: .maxEntries) ?? 40`, or
    /// let the encoder omit a nil.
    @Test func maxEntriesAbsentIsTheDefaultAndNullIsNil() throws {
        let absent = try decode(ChangelogRecipe.self, #"{"bundleID":"zz","source":"https://example.invalid/"}"#)
        #expect(absent.maxEntries == 40)
        let null = try decode(ChangelogRecipe.self, #"{"bundleID":"zz","source":"https://example.invalid/","maxEntries":null}"#)
        #expect(null.maxEntries == nil)

        let unbounded = ChangelogRecipe(bundleID: "zz", source: URL(string: "https://example.invalid/")!, maxEntries: nil)
        let object = try jsonObject(try JSONEncoder().encode(unbounded))
        #expect(object["maxEntries"] is NSNull, "a nil maxEntries must be written as null, not omitted")
        #expect(try JSONDecoder().decode(ChangelogRecipe.self, from: JSONEncoder().encode(unbounded)).maxEntries == nil)
    }

    // MARK: - Request body

    /// Mutation: encode `requestBody` as `Data` again (base64).
    @Test func aChangelogRequestBodyIsWrittenAsItsText() throws {
        let posting = ChangelogRecipeRegistry.recipes.filter { $0.requestBody != nil }
        #expect(!posting.isEmpty, "no recipe with a request body left to check")
        for recipe in posting {
            let object = try jsonObject(try JSONEncoder().encode(recipe))
            let body = try #require(recipe.requestBody)
            #expect(object["requestBody"] as? String == String(data: body, encoding: .utf8),
                    "\(recipe.bundleID): request body is not written as its UTF-8 text")
        }
        let binary = ChangelogRecipe(
            bundleID: "zz", source: URL(string: "https://example.invalid/")!,
            httpMethod: .post, requestBody: Data([0xFF, 0xFE]))
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(binary) }
    }

    // MARK: - Errors carry a path

    @Test func anUnknownKeyDeepInARecipeNamesItsPath() throws {
        let json = #"{"bundleID":"zz","url":"https://example.invalid/","mode":{"kind":"responseBody"},"versionPattern":"x","install":{"urlSource":{"kind":"fixed","url":"https://example.invalid/a.zip","pattern":"x"},"kind":"zip"}}"#
        do {
            _ = try decode(VendorProbeRecipe.self, json)
            Issue.record("an unknown payload key inside install.urlSource decoded")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.codingPath.map(\.stringValue) == ["install", "urlSource", "pattern"])
        }
    }

    @Test func aChannelProofTableRefusesAKeyListedTwice() throws {
        let json = #"[{"bundleID":"zz","channel":"beta","proof":{"kind":"artifact","pattern":"b"}},{"bundleID":"zz","channel":"beta","proof":{"kind":"artifact","pattern":"c"}}]"#
        #expect(throws: DecodingError.self) { try decode(ChannelProofTable.self, json) }
    }

    /// A table entry decodes its own flat `bundleID`/`channel`/`proof` object rather
    /// than going through `ChannelProofKey`'s conformance (whose strictness would
    /// refuse `proof`), so it is held to the same rules here, directly.
    ///
    /// Mutation: delete `rejectUnknownKeys` from `ChannelProofTable.Entry.init(from:)`.
    @Test func aChannelProofTableEntryIsStrict() throws {
        let proof = #""proof":{"kind":"artifact","pattern":"b"}"#
        let valid = #"[{"bundleID":"zz","channel":"beta","# + proof + "}]"
        let table = try decode(ChannelProofTable.self, valid)
        #expect(table.proofs[ChannelProofKey("zz", .beta)] == .artifact("b"))

        do {
            _ = try decode(ChannelProofTable.self, #"[{"bundleID":"zz","channel":"beta","zz":1,"# + proof + "}]")
            Issue.record("an unknown key in a channel-proof table entry decoded")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.codingPath.last?.stringValue == "zz")
        }
        #expect(throws: DecodingError.self) {
            try decode(ChannelProofTable.self, #"[{"bundleID":null,"channel":"beta","# + proof + "}]")
        }
        #expect(throws: DecodingError.self) {
            try decode(ChannelProofTable.self, #"[{"bundleID":"zz","channel":"beta"}]"#)
        }
    }

    /// A `Set` cannot hold a field twice, so a file that lists one twice was written
    /// by mistake — refused rather than quietly collapsed.
    ///
    /// Mutation: delete the duplicate guard in `ChannelArtifactProof.init(from:)`.
    @Test func aRecipeAnchorListingAFieldTwiceIsRefused() throws {
        #expect(throws: DecodingError.self) {
            try decode(ChannelArtifactProof.self, #"{"kind":"recipeAnchor","pattern":"b","fields":["url","url"]}"#)
        }
    }

    // MARK: - Deterministic output

    /// What the conformances sort, they sort — checked with collections big enough
    /// that hash order coming out sorted by chance is not a real possibility
    /// (24 elements: one ordering in 24!).
    ///
    /// Mutations: drop `.sorted()` from `recipeAnchor`'s `fields`; drop the sort in
    /// `ChannelProofTable.encode(to:)`.
    @Test func setsAndProofTablesAreWrittenSorted() throws {
        let names = (0..<24).map { String(format: "field%02d", $0) }
        let anchor = try jsonObject(JSONEncoder().encode(ChannelArtifactProof.recipeAnchor("p", in: Set(names))))
        #expect(anchor["fields"] as? [String] == names)

        var proofs: [ChannelProofKey: ChannelArtifactProof] = [:]
        for index in 0..<12 {
            for channel in [ReleaseChannel.beta, .nightly] {
                proofs[ChannelProofKey(String(format: "zz.app%02d", index), channel)] = .artifact("x")
            }
        }
        let rows = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ChannelProofTable(proofs))) as? [[String: Any]])
        let order = rows.map { "\($0["bundleID"] as? String ?? "") \($0["channel"] as? String ?? "")" }
        #expect(order == order.sorted())
        #expect(order.count == 24)
    }

    /// The whole registry encodes to the same bytes twice with `.sortedKeys` — the
    /// second time from a value rebuilt by decoding the first, so its sets and
    /// dictionaries are fresh instances rather than the same ones iterated again.
    @Test func theRegistryEncodesToStableBytes() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var failures: [String] = []
        var checked = 0
        func stable<T: Codable>(_ value: T, _ label: String) throws {
            let first = try encoder.encode(value)
            let second = try encoder.encode(try JSONDecoder().decode(T.self, from: first))
            checked += 1
            if first != second { failures.append("\(label): bytes differ after a rebuild") }
        }
        for set in AppRecipeIndex.all {
            let at = set.family
            try stable(set.probes, "\(at).probes")
            try stable(set.changelogs, "\(at).changelogs")
            try stable(set.githubRules, "\(at).githubRules")
            try stable(set.appStoreCases, "\(at).appStoreCases")
            try stable(ChannelProofTable(set.channelProofs), "\(at).channelProofs")
            try stable(ChannelProofTable(set.githubChannelProofs), "\(at).githubChannelProofs")
            try stable(ChannelProofTable(set.bindingProofs), "\(at).bindingProofs")
            try stable(set.sparkleFeeds, "\(at).sparkleFeeds")
            try stable(set.supersededFeeds, "\(at).supersededFeeds")
            try stable(set.changelogPages, "\(at).changelogPages")
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
        // The kinds above are listed by hand; a kind added to `AppRecipeSet` and
        // not here makes this count wrong.
        let kinds = Mirror(reflecting: try #require(AppRecipeIndex.all.first)).children
            .compactMap(\.label).filter { $0 != "family" }
        #expect(checked == AppRecipeIndex.all.count * kinds.count)
    }

    // MARK: - The whole registry (smoke test, not the equivalence gate)

    /// decode(encode(x)) reflects equal to x for every entry of every kind in every
    /// family. A smoke test: it proves the coding loses nothing the registry uses
    /// today, not that any JSON file matches the Swift registry — that is a later
    /// gate's job.
    ///
    /// Mutations: drop a case from `URLSource.init(from:)` (every case is in use);
    /// forget to encode a field some recipe sets (`selectHighest`, say).
    @Test func everyRegistryEntryRoundTrips() throws {
        var compared: [String: Int] = [:]
        var failures: [String] = []
        for set in AppRecipeIndex.all {
            for child in Mirror(reflecting: set).children {
                guard let label = child.label, label != "family" else { continue }
                do {
                    let (count, problem) = try roundTrip(child.value)
                    compared[label, default: 0] += count
                    if let problem { failures.append("\(set.family).\(label): \(problem)") }
                } catch {
                    // Collected rather than thrown, so one bad case reports every
                    // family it breaks instead of stopping at the first.
                    compared[label, default: 0] += 0
                    failures.append("\(set.family).\(label): \(error)")
                }
            }
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
        let kinds = Set(Mirror(reflecting: try #require(AppRecipeIndex.all.first)).children
            .compactMap(\.label)).subtracting(["family"])
        #expect(Set(compared.keys) == kinds)
        #expect(compared.values.reduce(0, +) > 300, "compared only \(compared)")
        // The comparison itself must be able to tell two recipes apart.
        let probes = VendorProbeRegistry.recipes
        #expect(RecipeMirror.dump(try #require(probes.first)) != RecipeMirror.dump(try #require(probes.last)))
    }

    private func roundTrip(_ value: Any) throws -> (Int, String?) {
        func check<T: Codable>(_ original: T, count: Int) throws -> (Int, String?) {
            let data = try JSONEncoder().encode(original)
            let back = try JSONDecoder().decode(T.self, from: data)
            let (a, b) = (RecipeMirror.dump(original), RecipeMirror.dump(back))
            return (count, a == b ? nil : "differs after a round trip\n  was: \(a)\n  now: \(b)")
        }
        switch value {
        case let v as [VendorProbeRecipe]: return try check(v, count: v.count)
        case let v as [ChangelogRecipe]: return try check(v, count: v.count)
        case let v as [GitHubReleaseRule]: return try check(v, count: v.count)
        case let v as [MacAppStoreProbeCase]: return try check(v, count: v.count)
        case let v as [ChannelProofKey: ChannelArtifactProof]:
            let data = try JSONEncoder().encode(ChannelProofTable(v))
            let back = try JSONDecoder().decode(ChannelProofTable.self, from: data).proofs
            let (a, b) = (RecipeMirror.dump(v), RecipeMirror.dump(back))
            return (v.count, a == b ? nil : "differs after a round trip\n  was: \(a)\n  now: \(b)")
        case let v as [String: URL]: return try check(v, count: v.count)
        case let v as [String: SparkleFeedCatalog.SupersededFeed]: return try check(v, count: v.count)
        default: return (0, "no round trip for \(type(of: value))")
        }
    }
}

// MARK: - Helpers

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any])
}

/// A value's stored contents as canonical JSON text, by reflection: arrays in
/// order, dictionaries and sets sorted, URLs as their string, `Data` as base64,
/// enums as their case and payload.
enum RecipeMirror {
    static func dump(_ value: Any) -> String {
        let tree = canonical(value)
        let data = (try? JSONSerialization.data(
            withJSONObject: ["v": tree], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func canonical(_ value: Any) -> Any {
        if let s = value as? String { return ["$string": s] }
        if let u = value as? URL { return ["$url": u.absoluteString] }
        if let d = value as? Data { return ["$data": d.base64EncodedString()] }
        if let b = value as? Bool { return ["$bool": b] }
        if let i = value as? Int { return ["$int": i] }
        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .optional:
            return mirror.children.first.map { canonical($0.value) } ?? NSNull()
        case .collection:
            return mirror.children.map { canonical($0.value) }
        case .set:
            return mirror.children.map { dump($0.value) }.sorted()
        case .dictionary:
            return mirror.children.map { pair -> [Any] in
                let parts = Mirror(reflecting: pair.value).children.map(\.value)
                return [canonical(parts[0]), canonical(parts[1])]
            }.sorted { dump($0[0]) < dump($1[0]) }
        case .enum:
            if let payload = mirror.children.first {
                return ["$case": payload.label ?? "?", "$payload": canonical(payload.value)]
            }
            return ["$case": String(describing: value)]
        default:
            var fields: [String: Any] = ["$type": String(reflecting: type(of: value))]
            for (index, child) in mirror.children.enumerated() {
                fields[child.label ?? "\(index)"] = canonical(child.value)
            }
            return fields
        }
    }

    /// The case name of an enum value.
    static func caseName(_ value: Any) -> String {
        Mirror(reflecting: value).children.first?.label ?? String(describing: value)
    }

    /// Whether the stored property `label` of `value` is an `Optional`.
    static func isOptional(_ label: String, of value: Any) -> Bool? {
        Mirror(reflecting: value).children.first { $0.label == label }
            .map { Mirror(reflecting: $0.value).displayStyle == .optional }
    }
}

/// One type's coding checks. See `RecipeCodableTests.codingCases`.
struct CodingCase: Sendable {
    let typeName: String
    let check: @Sendable () throws -> [String]

    /// A struct: `{required keys}` decodes to `init(required only)`; its
    /// `CodingKeys` are its stored properties; every coding key refuses `null`
    /// unless its property is optional (then `null` is nil); an unknown key is
    /// refused.
    static func structure<T: Codable>(
        _ type: T.Type, keys: [String], required: String, expected: T
    ) -> CodingCase {
        nonisolated(unsafe) let expected = expected
        return CodingCase(typeName: String(reflecting: T.self)) {
            var failures: [String] = []
            let name = String(describing: T.self)

            let labels = Set(Mirror(reflecting: expected).children.compactMap(\.label))
            if Set(keys) != labels {
                failures.append("\(name): CodingKeys \(Set(keys).subtracting(labels).sorted()) are not "
                    + "stored properties; stored properties \(labels.subtracting(keys).sorted()) have no key")
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: Data(required.utf8))
                if RecipeMirror.dump(decoded) != RecipeMirror.dump(expected) {
                    failures.append("\(name): decoding the required keys alone differs from the "
                        + "initializer's defaults\n  init:   \(RecipeMirror.dump(expected))\n  "
                        + "decoded: \(RecipeMirror.dump(decoded))")
                }
            } catch {
                failures.append("\(name): the required keys alone do not decode: \(error)")
            }

            let written = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(expected)) as? [String: Any] ?? [:]
            if written.isEmpty && !labels.isEmpty {
                failures.append("\(name): the encoder wrote no keys")
            }
            // Every coding key, not only the ones the encoder happened to write for
            // the defaults-only value: an optional left nil is never written, and
            // it is exactly those whose `null` handling would otherwise go
            // unexercised. Optional-ness comes from the stored property's type.
            for key in keys.sorted() {
                guard let optional = RecipeMirror.isOptional(key, of: expected) else { continue }
                var object = written
                object[key] = NSNull()
                let data = try JSONSerialization.data(withJSONObject: object)
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    if !optional {
                        failures.append("\(name): `\(key)`: null decoded instead of being refused")
                    } else if let child = Mirror(reflecting: decoded).children.first(where: { $0.label == key }),
                              Mirror(reflecting: child.value).children.count != 0 {
                        failures.append("\(name): `\(key)`: null decoded to a value, not nil")
                    }
                } catch {
                    if optional {
                        failures.append("\(name): `\(key)` is optional but null was refused: \(error)")
                    }
                }
            }

            var unknown = written
            unknown["zzNotAField"] = true
            if (try? JSONDecoder().decode(
                T.self, from: JSONSerialization.data(withJSONObject: unknown))) != nil {
                failures.append("\(name): an unknown key was accepted")
            }
            return failures
        }
    }

    /// An enum with associated values: every tag is the Swift case name; each
    /// sample encodes to exactly its checked-in JSON literal and that literal
    /// decodes back to it; a labelled payload value's key is its Swift label
    /// (unless listed in `keyForLabel`, and a listing that matches nothing fails);
    /// the samples cover every tag; an unknown key or tag is refused.
    ///
    /// The literal is what pins an unlabelled payload's key (`pattern`, `url`, …):
    /// a key renamed in the decoder, the encoder and the allowed list together
    /// still round-trips, but no longer matches the literal.
    static func tagged<T: Codable>(
        _ type: T.Type, tags: [String], samples: [(T, String)],
        keyForLabel: [String: String] = [:]
    ) -> CodingCase {
        nonisolated(unsafe) let samples = samples
        return CodingCase(typeName: String(reflecting: T.self)) {
            var failures: [String] = []
            let name = String(describing: T.self)
            var seen = Set<String>()
            var usedOverrides = Set<String>()
            for (sample, literal) in samples {
                let data = try JSONEncoder().encode(sample)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let tag = object["kind"] as? String ?? "<none>"
                seen.insert(tag)
                let caseName = RecipeMirror.caseName(sample)
                if tag != caseName {
                    failures.append("\(name).\(caseName) is tagged `\(tag)`")
                }

                let pinned = try JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [String: Any] ?? [:]
                if !(object as NSDictionary).isEqual(to: pinned) {
                    failures.append("\(name).\(caseName) encodes to \(String(decoding: data, as: UTF8.self)), "
                        + "not the checked-in \(literal)")
                }
                do {
                    let fromLiteral = try JSONDecoder().decode(T.self, from: Data(literal.utf8))
                    if RecipeMirror.dump(fromLiteral) != RecipeMirror.dump(sample) {
                        failures.append("\(name).\(caseName): the checked-in \(literal) decodes to something else")
                    }
                } catch {
                    failures.append("\(name).\(caseName): the checked-in \(literal) does not decode: \(error)")
                }

                // Labelled payload values: the JSON key is the label.
                if let payload = Mirror(reflecting: sample).children.first?.value {
                    let parts = Mirror(reflecting: payload)
                    if parts.displayStyle == .tuple {
                        for label in parts.children.compactMap(\.label) where !label.hasPrefix(".") {
                            let override = keyForLabel["\(caseName).\(label)"]
                            if override != nil { usedOverrides.insert("\(caseName).\(label)") }
                            let key = override ?? label
                            if pinned[key] == nil {
                                failures.append("\(name).\(caseName): payload label `\(label)` has no "
                                    + "`\(key)` key in \(literal)")
                            }
                        }
                    }
                }

                let back = try JSONDecoder().decode(T.self, from: data)
                if RecipeMirror.dump(back) != RecipeMirror.dump(sample) {
                    failures.append("\(name).\(tag) does not round-trip")
                }
                var unknown = object
                unknown["zzNotAField"] = true
                if (try? JSONDecoder().decode(
                    T.self, from: JSONSerialization.data(withJSONObject: unknown))) != nil {
                    failures.append("\(name).\(tag): an unknown key was accepted")
                }
            }
            if seen != Set(tags) {
                failures.append("\(name): samples cover \(seen.sorted()), tags are \(tags.sorted())")
            }
            let staleOverrides = Set(keyForLabel.keys).subtracting(usedOverrides)
            if !staleOverrides.isEmpty {
                failures.append("\(name): keyForLabel entries match no payload label: \(staleOverrides.sorted())")
            }
            if (try? JSONDecoder().decode(T.self, from: Data(#"{"kind":"zzNotACase"}"#.utf8))) != nil {
                failures.append("\(name): an unknown kind was accepted")
            }
            return failures
        }
    }

    /// An enum without associated values: written as `name`, round-trips, and an
    /// unknown string is refused.
    static func caseName<T: Codable>(_ type: T.Type, all: [T], name: @escaping (T) -> String) -> CodingCase {
        nonisolated(unsafe) let all = all
        nonisolated(unsafe) let name = name
        return CodingCase(typeName: String(reflecting: T.self)) {
            var failures: [String] = []
            for value in all {
                let data = try JSONEncoder().encode(value)
                let text = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
                if text != name(value) {
                    failures.append("\(T.self).\(value) is written as \(text ?? "<not a string>")")
                }
                let back = try JSONDecoder().decode(T.self, from: data)
                if RecipeMirror.dump(back) != RecipeMirror.dump(value) {
                    failures.append("\(T.self).\(value) does not round-trip")
                }
            }
            if (try? JSONDecoder().decode(T.self, from: Data(#""zzNotACase""#.utf8))) != nil {
                failures.append("\(T.self): an unknown value was accepted")
            }
            return failures
        }
    }
}
