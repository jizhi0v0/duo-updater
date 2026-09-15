import CryptoKit
import Foundation
import MachO

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
/// ## The directory
///
/// It holds family files and nothing else: every entry must be a regular file (not
/// a symlink) named `<slug>.json5`, exactly. `.copy` ships whatever is there, so a
/// `Foo.JSON5`, a `foo.json`, a `.DS_Store` or a `sub/foo.json5` would be shipped
/// and never loaded — and the next golden re-record would delete that family's
/// golden. `loadAll` refuses the directory instead; `check_recipe_json5.py` refuses
/// the same in `make test`, which is where a stray `.DS_Store` should be found.
///
/// ## The recipe digest
///
/// A command-line `duo` finds this data in a resource bundle beside it, outside its
/// code signature and writable by the user it runs as, while the binary holds an
/// App Management grant. So `scripts/build-cli.sh` computes `digest(of:)` over the
/// checkout's `Resources/Recipes` before building and passes it as a build setting
/// that lands in the binary's embedded Info.plist (`App/duo-cli-Info.plist`), which
/// the signature covers. When the running executable carries that key, `loadAll`
/// hashes the bytes it is about to decode — read once, so they cannot change between
/// the check and the decode — and refuses a mismatch. An executable without the key
/// (the app, whose resources are sealed by its own signature; `swift test`; a
/// `swift build` binary) skips the check. Debug builds also honour
/// `PACKAGE_RESOURCE_BUNDLE_PATH` for where the bundle is, which is why the check is
/// on content, not location.
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

    /// The Info.plist key a `duo` built by `scripts/build-cli.sh` carries the digest in.
    static let digestInfoKey = "DuoRecipeDigest"

    /// The recipe digest the running executable was built with, or nil to skip the
    /// check — read from the main executable's own `__TEXT,__info_plist` section, so
    /// an `Info.plist` file an attacker drops beside the binary cannot supply it (see
    /// "The recipe digest"). nil when there is no such section, or one without the
    /// key. An empty string (the key present but unexpanded) is returned as `""`, and
    /// `loadAll` traps on it — a `duo` built without `DUO_RECIPE_DIGEST`.
    static func embeddedDigest() -> String? {
        guard let mh = mainExecutableHeader() else { return nil }
        var size: UInt = 0
        // getsectiondata takes the SLID header, which is what dlsym hands back.
        guard let bytes = getsectiondata(mh, "__TEXT", "__info_plist", &size), size > 0
        else { return nil }
        return digest(fromInfoPlistSection: Data(bytes: bytes, count: Int(size)))
    }

    /// The header of the process's main executable image, or nil.
    ///
    /// `dlsym(RTLD_MAIN_ONLY, …)` "searches only the main executable" (dlsym(3)), and
    /// `_mh_execute_header` / `MH_EXECUTE_SYM` is the mach-header symbol that, per
    /// `<mach-o/ldsyms.h>`, "does not appear in any file type other than a MH_EXECUTE
    /// file type" — so this resolves the one image that is the executable, not any
    /// linked dylib, and not by trusting `_dyld_get_image_header(0)` (which dyld does
    /// not document as the main executable).
    static func mainExecutableHeader() -> UnsafePointer<mach_header_64>? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -5) /* RTLD_MAIN_ONLY */,
                                 MH_EXECUTE_SYM) else { return nil }
        return UnsafeRawPointer(symbol).assumingMemoryBound(to: mach_header_64.self)
    }

    /// The digest key out of a `__TEXT,__info_plist` section's bytes, or nil when the
    /// bytes are not a plist dictionary or hold no such key. The injectable seam:
    /// a test drives this with fixture bytes, since a test process has no section of
    /// its own to plant one in.
    static func digest(fromInfoPlistSection data: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary[digestInfoKey] as? String
    }

    /// Whether `name` is a family file name: the slug
    /// `AppRecipeIndexTests.familySlugsAreUniqueAndWellFormed` requires, then
    /// `.json5`, case included. `recipe_families.py`'s `DATA_FILE` is the same rule.
    static func isFamilyFileName(_ name: String) -> Bool {
        name.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9.-]*\.json5/) != nil
    }

    /// Every entry of `directory`, read: the family files' names and bytes in name
    /// order. Throws for an entry that is not a regular `<slug>.json5` file, naming
    /// all of them, and for a directory with no family in it.
    static func readFamilyFiles(in directory: URL) throws -> [(name: String, bytes: Data)] {
        let entries: [URL]
        do {
            // No options: hidden files are listed too.
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw LoadFailure(text: "recipe directory \(directory.path) cannot be listed: \(error)")
        }
        var files: [(name: String, bytes: Data)] = []
        var refused: [String] = []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                refused.append("\(name) (a symbolic link)")
            } else if values?.isRegularFile != true {
                refused.append("\(name) (not a regular file)")
            } else if !isFamilyFileName(name) {
                refused.append("\(name) (not named <slug>.\(fileExtension))")
            } else {
                do {
                    files.append((name, try Data(contentsOf: url)))
                } catch {
                    throw LoadFailure(text: "recipe file \(directoryName)/\(name) cannot be read: \(error)")
                }
            }
        }
        guard refused.isEmpty else {
            throw LoadFailure(text: """
                recipe directory \(directory.path) holds entries that are not family files, \
                which would be shipped and never loaded: \(refused.joined(separator: ", "))
                """)
        }
        // A bundle whose `Recipes` directory holds no family is a packaging failure
        // (a copy that brought the directory but not its files), never a valid state:
        // at least one family is data from step 3 on.
        guard !files.isEmpty else {
            throw LoadFailure(text: "recipe directory \(directory.path) holds no .\(fileExtension) family files")
        }
        return files
    }

    /// SHA-256, lowercase hex, over each file in name order: `"<name>\n<byte count>\n"`
    /// then its bytes. The name, so a rename moves it; the count, so bytes cannot be
    /// re-split between neighbours for the same digest (the same framing as
    /// `SourceStamp`). `scripts/recipe_digest.py` computes the same; both are held to
    /// one known answer in their tests.
    static func digest(of files: [(name: String, bytes: Data)]) -> String {
        var hasher = SHA256()
        for (name, bytes) in files.sorted(by: { $0.name < $1.name }) {
            hasher.update(data: Data("\(name)\n\(bytes.count)\n".utf8))
            hasher.update(data: bytes)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Every family file in `directory`, decoded, in file-name order. Throws
    /// `LoadFailure` for the first problem, never skips a file. With an
    /// `expectedDigest`, the bytes read must digest to it before anything is decoded.
    static func loadAll(from directory: URL, expectedDigest: String? = nil) throws -> [AppRecipeSet] {
        let files = try readFamilyFiles(in: directory)
        if let expectedDigest {
            let found = digest(of: files)
            guard found == expectedDigest else {
                throw LoadFailure(text: expectedDigest.isEmpty
                    ? """
                      this executable carries an empty \(digestInfoKey), so it was built without \
                      DUO_RECIPE_DIGEST; build it with scripts/build-cli.sh (make cli)
                      """
                    : """
                      the recipe files in \(directory.path) are not the ones this executable was \
                      built with (built with \(expectedDigest), found \(found)). Reinstall with \
                      `make cli`; if nobody here edited them, something else did
                      """)
            }
        }
        return try files.map { name, bytes in
            let family = String(name.dropLast(fileExtension.count + 1))
            do {
                return try decode(bytes, family: family)
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
