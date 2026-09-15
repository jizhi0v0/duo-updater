import Foundation

/// One app family stored as data: `Resources/Recipes/<family>.json5`, read at first
/// access to `AppRecipeIndex.all` from the target's resource bundle.
///
/// ## The file
///
/// A JSON object whose keys are `AppRecipeSet`'s kinds (`probes`, `changelogs`,
/// `githubRules`, …), each written the way `RecipeCoding` describes. A kind the family
/// has none of is left out. There is no `family` key: the file name without `.json5`
/// is the slug, so there is no second copy of it to disagree with the first.
///
/// The dialect is a subset of JSON5: plain JSON plus whole-line `//` comments, nothing
/// else. `JSONDecoder.allowsJSON5` accepts more than that (trailing commas, `/* */`,
/// single quotes, unquoted keys) and, like every Foundation JSON reader, keeps the
/// FIRST value of a key written twice without a word. Neither is caught here;
/// `scripts/check_recipe_json5.py`, run by `make test`, refuses both.
///
/// ## Failure
///
/// A file that does not decode is not skipped. `AppRecipeIndex` traps on first
/// access with `problem(decoding:file:)`'s text, which names the file and the coding
/// path — a family that silently vanished would read, in the app and in `duo verify`,
/// exactly like an app nobody wrote a recipe for.
struct RecipeFamilyFile: Decodable {
    let probes: [VendorProbeRecipe]
    let changelogs: [ChangelogRecipe]
    let githubRules: [GitHubReleaseRule]
    let appStoreCases: [MacAppStoreProbeCase]
    let channelProofs: ChannelProofTable
    let githubChannelProofs: ChannelProofTable
    let bindingProofs: ChannelProofTable
    let sparkleFeeds: [String: URL]
    let supersededFeeds: [String: SparkleFeedCatalog.SupersededFeed]
    let changelogPages: [String: URL]

    /// The top-level keys. `AppRecipeIndexTests.everyStoredKindIsDeclared` holds them
    /// to `AppRecipeSet`'s stored properties, so a kind added there cannot be missing
    /// from the file format.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case probes, changelogs, githubRules, appStoreCases
        case channelProofs, githubChannelProofs, bindingProofs
        case sparkleFeeds, supersededFeeds, changelogPages
    }

    static let fileExtension = "json5"
    /// The resource directory, as `Package.swift` declares it with `.copy`.
    static let directoryName = "Recipes"

    init(from decoder: Decoder) throws {
        try RecipeCoding.rejectUnknownKeys(in: decoder, allowed: CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        probes = try c.decode([VendorProbeRecipe].self, forKey: .probes, default: [])
        changelogs = try c.decode([ChangelogRecipe].self, forKey: .changelogs, default: [])
        githubRules = try c.decode([GitHubReleaseRule].self, forKey: .githubRules, default: [])
        appStoreCases = try c.decode([MacAppStoreProbeCase].self, forKey: .appStoreCases, default: [])
        channelProofs = try c.decode(ChannelProofTable.self, forKey: .channelProofs, default: ChannelProofTable([:]))
        githubChannelProofs = try c.decode(
            ChannelProofTable.self, forKey: .githubChannelProofs, default: ChannelProofTable([:]))
        bindingProofs = try c.decode(ChannelProofTable.self, forKey: .bindingProofs, default: ChannelProofTable([:]))
        sparkleFeeds = try c.decode([String: URL].self, forKey: .sparkleFeeds, default: [:])
        supersededFeeds = try c.decode(
            [String: SparkleFeedCatalog.SupersededFeed].self, forKey: .supersededFeeds, default: [:])
        changelogPages = try c.decode([String: URL].self, forKey: .changelogPages, default: [:])
    }

    func recipeSet(family: String) -> AppRecipeSet {
        AppRecipeSet(
            family: family,
            probes: probes,
            changelogs: changelogs,
            githubRules: githubRules,
            appStoreCases: appStoreCases,
            channelProofs: channelProofs.proofs,
            githubChannelProofs: githubChannelProofs.proofs,
            bindingProofs: bindingProofs.proofs,
            sparkleFeeds: sparkleFeeds,
            supersededFeeds: supersededFeeds,
            changelogPages: changelogPages)
    }

    /// Decodes one family file's bytes. `family` is the file name without its extension.
    static func decode(_ data: Data, family: String) throws -> AppRecipeSet {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(RecipeFamilyFile.self, from: data).recipeSet(family: family)
    }

    /// Every family file in `directory`, decoded, in file-name order. Throws
    /// `LoadFailure` for the first problem, never skips a file.
    static func loadAll(from directory: URL) throws -> [AppRecipeSet] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw LoadFailure(text: "recipe directory \(directory.path) cannot be listed: \(error)")
        }
        let files = names.filter { ($0 as NSString).pathExtension == fileExtension }.sorted()
        // A bundle whose `Recipes` directory holds no family is a packaging failure
        // (a copy that brought the directory but not its files), never a valid state:
        // at least one family is data from step 3 on.
        guard !files.isEmpty else {
            throw LoadFailure(text: "recipe directory \(directory.path) holds no .\(fileExtension) family files")
        }
        return try files.map { name in
            let url = directory.appendingPathComponent(name)
            let family = String(name.dropLast(fileExtension.count + 1))
            do {
                return try decode(try Data(contentsOf: url), family: family)
            } catch {
                throw LoadFailure(text: problem(decoding: error, file: "\(directoryName)/\(name)"))
            }
        }
    }

    struct LoadFailure: Error, CustomStringConvertible {
        let text: String
        var description: String { text }
    }

    /// `Recipes/com-example-App.json5: probes[0].install.urlSource: unknown key …`.
    /// A `DecodingError`'s own description buries the path in a debug dump of its
    /// coding keys; this puts it where an author looks first.
    static func problem(decoding error: Error, file: String) -> String {
        func path(_ keys: [CodingKey]) -> String {
            var out = ""
            for key in keys {
                // An array position: JSONDecoder's own keys carry `intValue`;
                // `ChannelProofTable` names its positions with a digit string.
                if let index = key.intValue ?? Int(key.stringValue) {
                    out += "[\(index)]"
                } else {
                    out += out.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return out.isEmpty ? "<top level>" : out
        }
        func underlying(_ context: DecodingError.Context) -> String {
            guard let inner = context.underlyingError else { return "" }
            return " (\((inner as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? "\(inner)"))"
        }
        let detail: String
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            detail = "\(path(context.codingPath + [key])): required key is missing"
        case DecodingError.typeMismatch(let type, let context):
            detail = "\(path(context.codingPath)): expected \(type) — \(context.debugDescription)"
        case DecodingError.valueNotFound(let type, let context):
            detail = "\(path(context.codingPath)): expected \(type) — \(context.debugDescription)"
        case DecodingError.dataCorrupted(let context):
            detail = "\(path(context.codingPath)): \(context.debugDescription)\(underlying(context))"
        default:
            detail = "\(error)"
        }
        return "\(file): \(detail)"
    }
}
