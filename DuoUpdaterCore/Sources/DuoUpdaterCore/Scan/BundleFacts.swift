import CryptoKit
import Darwin
import Foundation

/// Everything `duo diff` compares, read from one unpacked release.
///
/// Collected once per side and then compared by `BundleDiff`, so the comparison is
/// a pure function of two values and can be tested without a bundle on disk.
/// Paths are relative to the root the release was unpacked to: the `.app` itself
/// for an app, zip or dmg, and the `pkgutil --expand-full` directory for a pkg.
struct BundleFacts: Sendable, Codable {
    var rootName = ""
    /// Read from a `.pkg`, whose paths start at the expanded package rather than at
    /// an app. `BundleDiff.aligned` rewrites them before anything is compared.
    var isPackage = false
    /// Paths a backup deliberately did not copy (`BackupStore.Backup.omittedFiles`).
    /// Set on the old side only, by the caller that knows it is a backup.
    var omittedByBackup: Set<String> = []
    /// `pkgutil --check-signature`, minus the lines that differ on every signing.
    /// Nil when the input was not a pkg.
    var packageSignature: [String]?
    /// Each component package's `PackageInfo` attributes, keyed by component.
    var packageComponents: [String: [String: String]] = [:]
    /// Installer scripts, by path. They run as root, so they are shown in full.
    var scripts: [String: String] = [:]
    var files: [String: FileFact] = [:]
    var bundles: [String: BundleFact] = [:]
    var machO: [String: MachOFact] = [:]
    /// `.strings` files under `en`, `Base` and `zh-Hans`, parsed.
    var strings: [String: [String: String]] = [:]
    /// launchd property lists, flattened to `key -> value`.
    var launchdPlists: [String: [String: String]] = [:]
    var asars: [String: AsarFact] = [:]
    /// Printable runs of every Mach-O file small enough to index, newline-joined.
    /// What a localization key is looked for in.
    var stringsBlob = Data()
    /// Mach-O files too large to index into `stringsBlob`.
    var unindexedMachO: [String] = []
    /// Whether `stringsBlob` was filled at all, i.e. whether the absence of a key
    /// from it means anything.
    ///
    /// Default false, set true by ``BundleFactsReader/scan(root:stop:)`` alone, so
    /// facts that came from anywhere else say so rather than presenting an empty
    /// index as a search that found nothing. ``BackupFactsLibrary`` does not keep
    /// the blob — it is 20–300× everything else in these facts put together — and a
    /// stored side therefore cannot answer "was this key already in the old
    /// binaries", only "is it in the new ones".
    var stringsIndexed = false
    var timings = PhaseTimings()
    var bytesHashed: Int64 = 0

    /// What ``BackupFactsLibrary`` keeps, which is everything the report compares
    /// except the three fields below.
    ///
    /// - `stringsBlob` is left out on size: 16.7–64.9 MB per app against 344 KB–19 MB
    ///   for all of the above, and 2.3–13.9 MiB against 53 KB–3.4 MB once both are
    ///   compressed (measured 2026-09-19 on Claude, ChatGPT, Excel and DuoUpdater).
    ///   `stringsIndexed` is left out with it so a decoded value is honest by
    ///   construction rather than by remembering to clear a flag.
    /// - `omittedByBackup` belongs to the caller, not to the bundle: the comparison
    ///   re-applies it from the backup's own sidecar every time.
    /// - `timings` describes the run that produced the value, and a stored one is
    ///   replaced by the time it took to read it back.
    enum CodingKeys: String, CodingKey {
        case rootName, isPackage, packageSignature, packageComponents, scripts
        case files, bundles, machO, strings, launchdPlists, asars
        case unindexedMachO, bytesHashed
    }
}

struct FileFact: Sendable, Equatable, Codable {
    var size: Int64
    /// SHA-256 of the contents, or `symlink:<destination>`.
    var digest: String
}

struct BundleFact: Sendable, Equatable, Codable {
    var identifier: String?
    var shortVersion: String?
    var buildVersion: String?
    var minimumSystemVersion: String?
    var feedURL: String?
    var publicEDKey: String?
    var usageDescriptions: [String: String] = [:]
    var urlSchemes: [String] = []
    var infoKeys: [String] = []
    /// Nil when the bundle is unsigned or the signature cannot be read.
    var signature: SignatureVerifier.SigningSummary?
}

struct MachOFact: Sendable, Equatable, Codable {
    var size: Int64
    var architectures: [String]
    /// Install name -> the `current_version` the linker recorded.
    var dylibs: [String: String]
    var buildSDK: String?
    var sourcePaths: [String]
}

struct AsarFact: Sendable, Equatable, Codable {
    /// Path inside the archive -> integrity hash, or `size:<n>` when there is none.
    var files: [String: String] = [:]
    /// `node_modules/<name>` -> version, from each package's own package.json.
    var packages: [String: String] = [:]
    var rootPackage: [String: String] = [:]
    /// Source map path -> its `sources`, for maps outside node_modules.
    var mapSources: [String: [String]] = [:]
}

/// Wall time per phase, in the order phases first ran. Printed at the end of the
/// report so a slow input says where the time went.
struct PhaseTimings: Sendable {
    private(set) var order: [String] = []
    private(set) var totals: [String: Duration] = [:]

    mutating func add(_ phase: String, _ elapsed: Duration) {
        if totals[phase] == nil { order.append(phase) }
        totals[phase, default: .zero] += elapsed
    }

    mutating func time<T>(_ phase: String, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        defer { add(phase, ContinuousClock.now - start) }
        return try body()
    }

    var entries: [(phase: String, elapsed: Duration)] { order.map { ($0, totals[$0]!) } }
}

enum BundleFactsReader {

    /// Mach-O files larger than this are still read for architectures, libraries
    /// and source paths, but their printable runs are not indexed. Electron
    /// Framework is ~180 MB and no localization key is ever looked up in it.
    static let stringsIndexLimit: Int64 = 64 * 1024 * 1024

    static let bundleExtensions: Set<String> = [
        "app", "xpc", "appex", "framework", "bundle", "plugin", "systemextension", "kext",
    ]

    /// Walks, hashes and parses everything under `root`, signatures included.
    /// Synchronous disk and Security work throughout: callers run it off the
    /// cooperative pool, in one hop.
    static func scan(root: URL, stop: BundleDiff.StopFlag = BundleDiff.StopFlag()) throws -> BundleFacts {
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        var facts = BundleFacts()
        facts.rootName = base.lastPathComponent
        var timings = PhaseTimings()
        var blob = Data()
        var bundleURLs: [String: URL] = [:]

        guard let walker = fm.enumerator(
            at: base, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
            options: [], errorHandler: { _, _ in true })
        else { throw CocoaError(.fileReadNoSuchFile) }

        // The enumerator yields what is inside the root, never the root itself.
        if bundleExtensions.contains(base.pathExtension), let bundle = readBundle(at: base) {
            facts.bundles["."] = bundle
            bundleURLs["."] = base
        }

        // The walk, then every digest, then the rest in walk order. Hashing is most
        // of a large bundle's time and each file's is independent, so it fans out;
        // the strings index is appended to in walk order, so what feeds it does not.
        // Measured with `duo diff` on DSH Desktop 2.0.17 (26,174 files, 1.3 GB),
        // walk + hash before this, the prefix cut and the hex below → with them:
        // 3.0 s → 1.0 s with the files in the cache, 6.1–6.3 s → 2.6–2.9 s after
        // `purge`.
        var walkStart = ContinuousClock.now
        // Each path the enumerator yields starts with `base`, or with its real path
        // where `base` is under a link — a scratch copy in `/var/folders` comes back
        // as `/private/var/folders/…`. Cutting either prefix off spares
        // re-standardizing every path, which was a fifth of the walk;
        // `relativePath` stays for anything else.
        let prefixes = Set([base.path, realPath(base.path)].compactMap { $0 }).map { $0 + "/" }
        var entries: [(rel: String, url: URL, values: URLResourceValues?)] = []
        for case let url as URL in walker {
            if stop.isSet { throw CancellationError() }
            let path = url.path
            let rel = prefixes.first(where: path.hasPrefix).map { String(path.dropFirst($0.count)) }
                ?? relativePath(of: url, under: base)
            entries.append(
                (rel, url, try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])))
        }
        let digests = hashes(
            of: entries.map { $0.values?.isSymbolicLink != true && $0.values?.isRegularFile == true ? $0.url : nil },
            stop: stop)
        if stop.isSet { throw CancellationError() }

        for (index, (rel, url, values)) in entries.enumerated() {
            if stop.isSet { throw CancellationError() }
            if values?.isSymbolicLink == true {
                // Recorded, never followed — the enumerator does not descend into a
                // link. No `skipDescendants()` here: called on a link it skips the
                // rest of the *enclosing* directory (measured 2026-09-17 on Mac Mouse
                // Fix 3.0.8: 102 files seen instead of 280).
                let destination = (try? fm.destinationOfSymbolicLink(atPath: url.path)) ?? "?"
                facts.files[rel] = FileFact(size: 0, digest: "symlink:" + destination)
                continue
            }
            if bundleExtensions.contains(url.pathExtension), let bundle = readBundle(at: url) {
                facts.bundles[rel] = bundle
                bundleURLs[rel] = url
            }
            guard values?.isRegularFile == true else { continue }
            let size = Int64(values?.fileSize ?? 0)
            // One read of the contents serves both the digest and the Mach-O test.
            let hashed = digests[index]
            facts.files[rel] = FileFact(size: size, digest: hashed?.digest ?? "unreadable")
            facts.bytesHashed += size
            timings.add("walk + hash", ContinuousClock.now - walkStart)

            let name = url.lastPathComponent
            timings.time("plists, .strings, scripts") {
                if name.hasSuffix(".strings"), isIndexedLocalization(rel), let dict = readStrings(at: url) {
                    facts.strings[rel] = dict
                }
                if name.hasSuffix(".plist"), rel.contains("LaunchDaemons/") || rel.contains("LaunchAgents/"),
                   let plist = NSDictionary(contentsOf: url) as? [String: Any] {
                    facts.launchdPlists[rel] = flatten(plist)
                }
                if name == "preinstall" || name == "postinstall", rel.hasSuffix("Scripts/" + name) {
                    facts.scripts[rel] = (try? String(contentsOf: url, encoding: .utf8)) ?? "<not UTF-8>"
                }
                if name == "PackageInfo", let attributes = readPackageInfo(at: url) {
                    facts.packageComponents[(rel as NSString).deletingLastPathComponent] = attributes
                }
            }
            if name.hasSuffix(".asar") {
                timings.time("asar") {
                    if let asar = try? readAsar(at: url) { facts.asars[rel] = asar }
                }
            }
            if let head = hashed?.head, looksLikeMachO(head) {
                let architectures = timings.time("Mach-O headers") { MachOImports.architectures(at: url) }
                let commands = timings.time("Mach-O headers") { MachOImports.loadCommands(at: url) }
                // Read, never mapped: a hardened process that maps an executable
                // whose signature no longer validates is killed when it touches a
                // bad page (`ExecutableBytes`), and any app on disk can be one.
                // What the copy costs is measured on `forEachChunk`: nothing that shows.
                let indexed = size <= stringsIndexLimit
                var paths = SourcePathScanner.Stream()
                var runs = PrintableRuns.Stream()
                let blobCount = blob.count
                var indexing = Duration.zero
                let readStart = ContinuousClock.now
                let read = ExecutableBytes.forEachChunk(
                    of: url, overlap: max(SourcePathScanner.Stream.overlap, PrintableRuns.Stream.overlap)
                ) { buffer, carried, isLast in
                    paths.feed(buffer, carried: carried, isLast: isLast)
                    if indexed {
                        let start = ContinuousClock.now
                        runs.feed(buffer, carried: carried, isLast: isLast, to: &blob)
                        indexing += ContinuousClock.now - start
                    }
                    return true
                }
                // The read itself counts as source paths, where the page-ins of
                // the mapped file it replaces were counted.
                timings.add("source paths", ContinuousClock.now - readStart - indexing)
                if indexed { timings.add("strings index", indexing) }
                if read {
                    if !indexed { facts.unindexedMachO.append(rel) }
                    facts.machO[rel] = MachOFact(
                        size: size, architectures: architectures ?? [],
                        dylibs: commands?.dylibs ?? [:],
                        buildSDK: commands?.buildSDK.map { "\($0.platform.displayName) \($0.version)" },
                        sourcePaths: paths.found.sorted())
                } else {
                    // Failed partway: nothing of this file, as when it could not be mapped.
                    blob.removeSubrange(blobCount..<blob.count)
                }
            }
            walkStart = ContinuousClock.now
        }
        timings.add("walk + hash", ContinuousClock.now - walkStart)

        timings.time("signatures") {
            for (rel, url) in bundleURLs {
                facts.bundles[rel]?.signature = SignatureVerifier.signingSummary(at: url)
            }
        }
        facts.stringsBlob = blob
        facts.stringsIndexed = true
        facts.timings = timings
        return facts
    }

    /// `root`-relative, whatever the enumerator made of `/tmp` → `/private/tmp`.
    static func relativePath(of url: URL, under base: URL) -> String {
        let path = url.standardizedFileURL.path
        for prefix in [base.path, base.resolvingSymlinksInPath().path] {
            if path == prefix { return "." }
            if path.hasPrefix(prefix + "/") { return String(path.dropFirst(prefix.count + 1)) }
        }
        let resolved = url.resolvingSymlinksInPath().path
        let resolvedBase = base.resolvingSymlinksInPath().path
        if resolved.hasPrefix(resolvedBase + "/") { return String(resolved.dropFirst(resolvedBase.count + 1)) }
        return path
    }

    /// `realpath(3)`: unlike `resolvingSymlinksInPath`, it keeps `/private`.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func isIndexedLocalization(_ rel: String) -> Bool {
        let path = "/" + rel
        return path.contains("/en.lproj/") || path.contains("/Base.lproj/") || path.contains("/zh-Hans.lproj/")
    }

    /// ``hash(_:)`` of each URL given, all at once; nil where none is given, where
    /// the file could not be read, and for any file not yet started when `stop` is set.
    static func hashes(of urls: [URL?], stop: BundleDiff.StopFlag) -> [(digest: String, head: Data)?] {
        let results = UnsafeMutableBufferPointer<(digest: String, head: Data)?>.allocate(capacity: urls.count)
        results.initialize(repeating: nil)
        defer { results.deinitialize(); results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            guard let url = urls[index], !stop.isSet else { return }
            results[index] = try? hash(url)
        }
        return Array(results)
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// SHA-256 of the file, and its first eight bytes.
    static func hash(_ url: URL) throws -> (digest: String, head: Data) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var head = Data()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            if head.isEmpty { head = chunk.prefix(8) }
            hasher.update(data: chunk)
        }
        // Not `String(format: "%02x")` per byte: 32 Foundation format calls a file
        // were a quarter of the walk.
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in hasher.finalize() {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0F)])
        }
        return (String(decoding: hex, as: UTF8.self), head)
    }

    /// Thin or fat Mach-O, by magic. `MachOImports` does the real parsing; this
    /// only decides whether to ask it.
    static func looksLikeMachO(_ head: Data) -> Bool {
        guard head.count >= 8 else { return false }
        let bytes = [UInt8](head.prefix(8))
        let magic = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        switch magic {
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            return true
        case 0xCAFE_BABE, 0xCAFE_BABF:
            // Java class files share this magic; their next word is a class file
            // version, 45 and up, never a plausible slice count.
            let count = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
            return count > 0 && count < 30
        default:
            return false
        }
    }

    static func readStrings(at url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist.mapValues { "\($0)" }
    }

    static func readBundle(at url: URL) -> BundleFact? {
        let candidates = [
            url.appendingPathComponent("Contents/Info.plist"),
            url.appendingPathComponent("Resources/Info.plist"),
        ]
        guard let info = candidates.lazy.compactMap({ NSDictionary(contentsOf: $0) as? [String: Any] }).first
        else { return nil }
        var bundle = BundleFact()
        bundle.identifier = info["CFBundleIdentifier"] as? String
        bundle.shortVersion = info["CFBundleShortVersionString"] as? String
        bundle.buildVersion = info["CFBundleVersion"] as? String
        bundle.minimumSystemVersion = info["LSMinimumSystemVersion"] as? String
        bundle.feedURL = info["SUFeedURL"] as? String
        bundle.publicEDKey = info["SUPublicEDKey"] as? String
        for (key, value) in info where key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            bundle.usageDescriptions[key] = "\(value)"
        }
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        bundle.urlSchemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.sorted()
        bundle.infoKeys = info.keys.sorted()
        return bundle
    }

    /// The `<pkg-info …>` element's attributes, minus the build tool's version.
    static func readPackageInfo(at url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let open = text.range(of: #"<pkg-info[^>]*>"#, options: .regularExpression)
        else { return nil }
        let element = String(text[open])
        var attributes: [String: String] = [:]
        for match in element.matches(of: /([\w-]+)="([^"]*)"/) {
            attributes[String(match.1)] = String(match.2)
        }
        attributes["generator-version"] = nil
        return attributes
    }

    static func flatten(_ value: Any, prefix: String = "") -> [String: String] {
        switch value {
        case let dict as [String: Any]:
            var out: [String: String] = [:]
            for (key, child) in dict {
                out.merge(flatten(child, prefix: prefix.isEmpty ? key : prefix + "." + key)) { first, _ in first }
            }
            return out
        case let array as [Any]:
            return [prefix: array.map { "\($0)" }.joined(separator: ", ")]
        default:
            return [prefix: "\(value)"]
        }
    }

    // MARK: - asar

    /// Reads an Electron `app.asar` without unpacking it.
    ///
    /// Layout: an 8-byte pickle `[4][header pickle size]`, then the header pickle
    /// `[payload size][JSON length][JSON]`. File offsets in the JSON count from the
    /// end of the header pickle; files marked `unpacked` live in `app.asar.unpacked`.
    static func readAsar(at url: URL) throws -> AsarFact {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: 16), head.count == 16 else { throw CocoaError(.fileReadCorruptFile) }
        let headerPickleSize = UInt64(head.littleEndianWord(at: 4))
        let jsonLength = UInt64(head.littleEndianWord(at: 12))
        guard jsonLength > 0, 16 + jsonLength <= fileSize, 8 + headerPickleSize <= fileSize
        else { throw CocoaError(.fileReadCorruptFile) }
        guard let json = try handle.read(upToCount: Int(jsonLength)),
              let header = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        let dataStart = 8 + headerPickleSize

        var entries: [String: [String: Any]] = [:]
        func walk(_ node: [String: Any], _ prefix: String) {
            for (name, child) in node["files"] as? [String: Any] ?? [:] {
                guard let child = child as? [String: Any] else { continue }
                let path = prefix.isEmpty ? name : prefix + "/" + name
                if child["files"] != nil {
                    walk(child, path)
                } else if child["offset"] != nil || child["unpacked"] as? Bool == true {
                    entries[path] = child
                }
            }
        }
        walk(header, "")

        func read(_ path: String) -> Data? {
            guard let entry = entries[path], let size = (entry["size"] as? NSNumber)?.uint64Value else { return nil }
            if entry["unpacked"] as? Bool == true {
                // Refuse anything that would climb out of the unpacked directory.
                guard !path.split(separator: "/").contains("..") else { return nil }
                return try? Data(contentsOf: URL(fileURLWithPath: url.path + ".unpacked").appendingPathComponent(path))
            }
            guard let offsetText = entry["offset"] as? String, let offset = UInt64(offsetText),
                  dataStart + offset + size <= fileSize,
                  (try? handle.seek(toOffset: dataStart + offset)) != nil
            else { return nil }
            return try? handle.read(upToCount: Int(size))
        }

        var fact = AsarFact()
        for (path, entry) in entries {
            let integrity = (entry["integrity"] as? [String: Any])?["hash"] as? String
            fact.files[path] = integrity ?? "size:\((entry["size"] as? NSNumber)?.int64Value ?? -1)"
        }
        for path in entries.keys {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.last == "package.json", let i = parts.lastIndex(of: "node_modules"), i + 2 < parts.count {
                let depth = parts[i + 1].hasPrefix("@") ? 2 : 1
                // The package's own manifest, not a fixture somewhere inside it.
                if parts.count == i + depth + 2, let data = read(path),
                   let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    fact.packages[parts[0...(i + depth)].joined(separator: "/")] = manifest["version"] as? String ?? "?"
                }
            }
            if path.hasSuffix(".map"), !parts.contains("node_modules"), let data = read(path),
               let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                fact.mapSources[path] = Array(Set(map["sources"] as? [String] ?? [])).sorted()
            }
        }
        if let data = read("package.json"),
           let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["name", "version", "main"] {
                if let value = manifest[key] as? String { fact.rootPackage[key] = value }
            }
            for key in ["dependencies", "overrides"] {
                if let deps = manifest[key] as? [String: Any] {
                    fact.rootPackage[key] = deps.map { "\($0.key)@\($0.value)" }.sorted().joined(separator: ", ")
                }
            }
        }
        return fact
    }

    // MARK: - Package signature

    /// The package signature without what changes on every signing: the
    /// `Package "name.pkg":` header, the timestamp, and each certificate's
    /// fingerprint and expiry below its name.
    static func packageSignatureLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                line.hasPrefix("Status:") || line.hasPrefix("Notarization:")
                    || line.firstMatch(of: #/^\d+\.\s/#) != nil
            }
    }
}

// MARK: - Source paths

/// Source file paths compiled into a binary as strings: `#file`, `#filePath` and
/// `__FILE__`, which logging macros and assertions embed.
///
/// Linear: it finds each `.swift`/`.m`/`.cc`… and walks back over path characters.
/// The obvious regex — path characters, then the extension — restarts at every
/// byte of a long printable run, which is quadratic on an Electron Framework-sized
/// binary (measured 2026-09-17 in the prototype: over ten minutes, then killed).
enum SourcePathScanner {

    private static let extensions: [[UInt8]] = ["swift", "cpp", "mm", "cc", "m", "c"].map { Array($0.utf8) }

    private static let pathCharacter: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for byte in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./+@ ".utf8 {
            table[Int(byte)] = true
        }
        return table
    }()

    private static let identifierCharacter: [Bool] = {
        var table = [Bool](repeating: false, count: 256)
        for byte in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".utf8 {
            table[Int(byte)] = true
        }
        return table
    }()

    /// How far back from an extension's dot the path is followed.
    private static let longestPath = 400

    /// What follows a dot that decides whether it starts an extension: the
    /// longest extension, and the byte after it.
    private static let lookAhead = extensions.map(\.count).max()! + 1

    static func paths(in bytes: UnsafeRawBufferPointer) -> Set<String> {
        var found = Set<String>()
        collect(in: bytes, dotsIn: 0..<bytes.count, into: &found)
        return found
    }

    /// ``paths(in:)`` over a file read with ``ExecutableBytes/forEachChunk(of:overlap:chunkSize:_:)``,
    /// with the same answer: a dot is judged only once everything the judgement
    /// reads is in the buffer — `longestPath` bytes before it, `lookAhead` after —
    /// or the file ends, and the dots too near a chunk's end wait for the next.
    struct Stream {
        /// What `forEachChunk` must carry over for this.
        static let overlap = longestPath + lookAhead
        private(set) var found = Set<String>()
        /// Trailing bytes of the last buffer whose dots have not been judged.
        private var undecided = 0

        mutating func feed(_ bytes: UnsafeRawBufferPointer, carried: Int, isLast: Bool) {
            let from = carried - undecided
            let to = isLast ? bytes.count : max(from, bytes.count - lookAhead)
            collect(in: bytes, dotsIn: from..<to, into: &found)
            undecided = bytes.count - to
        }
    }

    private static func collect(in bytes: UnsafeRawBufferPointer, dotsIn dots: Range<Int>, into found: inout Set<String>) {
        let dot = UInt8(ascii: ".")
        var i = dots.lowerBound
        while i < dots.upperBound {
            if bytes[i] != dot { i += 1; continue }
            if let length = matchedExtensionLength(bytes, dotAt: i) {
                var start = i
                while start > 0, i - start < longestPath, pathCharacter[Int(bytes[start - 1])] { start -= 1 }
                if i - start >= 3 {
                    let candidate = String(
                        decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<(i + 1 + length)]), as: UTF8.self)
                    if candidate.contains("/") { found.insert(trimLeadingWords(candidate)) }
                }
            }
            i += 1
        }
    }

    private static func matchedExtensionLength(_ bytes: UnsafeRawBufferPointer, dotAt dot: Int) -> Int? {
        let count = bytes.count
        for ext in extensions where dot + ext.count < count {
            var matches = true
            for k in 0..<ext.count where bytes[dot + 1 + k] != ext[k] {
                matches = false
                break
            }
            guard matches else { continue }
            let after = dot + 1 + ext.count
            if after < count, identifierCharacter[Int(bytes[after])] { continue }
            return ext.count
        }
        return nil
    }

    /// Spaces are path characters, so a preceding word is swallowed with the path:
    /// `window UURemote/Foo.swift`. Keep from the first word that contains a `/`.
    static func trimLeadingWords(_ candidate: String) -> String {
        let words = candidate.split(separator: " ", omittingEmptySubsequences: false)
        guard let first = words.firstIndex(where: { $0.contains("/") }) else { return candidate }
        return words[first...].joined(separator: " ")
    }
}

// MARK: - Printable runs

/// A binary's printable runs — ASCII, plus three-byte UTF-8 so a Chinese key can
/// be found — each at least four bytes, appended newline-separated.
enum PrintableRuns {

    static func append(from bytes: UnsafeRawBufferPointer, to blob: inout Data) {
        var stream = Stream()
        stream.feed(bytes, carried: 0, isLast: true, to: &blob)
    }

    /// ``append(from:to:)`` over a file read with ``ExecutableBytes/forEachChunk(of:overlap:chunkSize:_:)``,
    /// with the same bytes appended. A run is written as soon as it is known to be
    /// one — four bytes long — and terminated when it ends; what a chunk's end
    /// leaves undecided (a run of under four bytes, a lead byte whose continuation
    /// bytes are in the next chunk) is looked at again with the next chunk.
    struct Stream {
        /// What `forEachChunk` must carry over for this: a run of three bytes and
        /// two of a three-byte sequence.
        static let overlap = 5
        /// Trailing bytes of the last buffer not yet classified.
        private var undecided = 0
        /// `blob` ends in a run that has not ended yet.
        private var open = false

        mutating func feed(_ bytes: UnsafeRawBufferPointer, carried: Int, isLast: Bool, to blob: inout Data) {
            let count = bytes.count
            var i = carried - undecided
            var runStart = open ? i : -1
            while i < count {
                let byte = bytes[i]
                if byte >= 0x20 && byte <= 0x7E {
                    if runStart < 0 { runStart = i }
                    i += 1
                } else if byte >= 0xE0 && byte <= 0xEF, i + 2 >= count, !isLast {
                    break
                } else if byte >= 0xE0 && byte <= 0xEF, i + 2 < count,
                          bytes[i + 1] & 0xC0 == 0x80, bytes[i + 2] & 0xC0 == 0x80 {
                    if runStart < 0 { runStart = i }
                    i += 3
                } else {
                    if runStart >= 0, open || i - runStart >= 4 {
                        blob.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[runStart..<i]))
                        blob.append(0x0A)
                    }
                    open = false
                    runStart = -1
                    i += 1
                }
            }
            if isLast {
                if runStart >= 0, open || count - runStart >= 4 {
                    blob.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[runStart..<count]))
                    blob.append(0x0A)
                }
                open = false
                undecided = 0
            } else if runStart >= 0, open || i - runStart >= 4 {
                blob.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[runStart..<i]))
                open = true
                undecided = count - i
            } else {
                undecided = count - (runStart >= 0 ? runStart : i)
            }
        }
    }

    /// Which of `needles` are a run of `blob` on their own. Only a run as long as
    /// some needle is made into a string. Building every run of both indexes into
    /// sets was most of the 3.9 s the localization section still took on OneDrive
    /// 26.153 → 26.173 after ``delimitedMatches(_:_:)``; 0.2 s without.
    static func wholeRunMatches(_ blob: Data, _ needles: [String]) -> [Bool] {
        guard !needles.isEmpty else { return [] }
        let lengths = Set(needles.map(\.utf8.count))
        var runs = Set<String>()
        blob.withUnsafeBytes { bytes in
            var start = 0
            for i in 0..<bytes.count where bytes[i] == 0x0A {
                if i > start, lengths.contains(i - start) {
                    runs.insert(String(decoding: UnsafeRawBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self))
                }
                start = i + 1
            }
        }
        return needles.map(runs.contains)
    }

    /// Whether `needle` occurs in `blob` as a word of its own: not preceded or
    /// followed by a letter, digit or underscore. `Cancel` is not in `Cancellation`,
    /// `OK` is not in `SOK_STATE`.
    static func containsDelimited(_ blob: Data, _ needle: String) -> Bool {
        let bytes = Array(needle.utf8)
        guard !bytes.isEmpty, blob.count >= bytes.count else { return false }
        func isWordByte(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
        }
        return blob.withUnsafeBytes { hay in
            bytes.withUnsafeBytes { n in
                guard let base = hay.baseAddress else { return false }
                var offset = 0
                while offset + n.count <= hay.count,
                      let hit = memmem(base + offset, hay.count - offset, n.baseAddress, n.count) {
                    let start = base.distance(to: UnsafeRawPointer(hit))
                    let end = start + n.count
                    let clearBefore = start == 0 || !isWordByte(hay[start - 1])
                    let clearAfter = end == hay.count || !isWordByte(hay[end])
                    if clearBefore && clearAfter { return true }
                    offset = start + 1
                }
                return false
            }
        }
    }

    /// ``containsDelimited(_:_:)`` for many needles in one pass over `blob`, rather
    /// than one pass per needle. OneDrive 26.153 → 26.173 adds 2,294 keys, most of
    /// them not a whole run, and with one `memmem` over the whole index for each
    /// the localization section took 67 s of a 73 s comparison.
    ///
    /// A needle that starts with a word byte can only start where a word does, and
    /// that word is exactly the needle's leading word bytes: a longer word would
    /// fail the boundary after the needle, or its next byte. So needles are
    /// grouped by that leading word, each word of the blob is looked up once, and
    /// a hit is checked byte for byte. A needle that starts with any other byte
    /// is rare and searched on its own.
    static func delimitedMatches(_ blob: Data, _ needles: [String]) -> [Bool] {
        var found = [Bool](repeating: false, count: needles.count)
        let bytes = needles.map { Array($0.utf8) }
        var byLeadingWord: [UInt64: [Int]] = [:]
        var leadingLengths = Set<Int>()
        var alone: [Int] = []
        for (index, needle) in bytes.enumerated() where !needle.isEmpty && needle.count <= blob.count {
            let word = needle.prefix(while: isWordByte)
            guard !word.isEmpty else { alone.append(index); continue }
            byLeadingWord[fnv1a(word), default: []].append(index)
            leadingLengths.insert(word.count)
        }
        if !alone.isEmpty {
            let alone = alone
            let results = UnsafeMutableBufferPointer<Bool>.allocate(capacity: alone.count)
            defer { results.deallocate() }
            DispatchQueue.concurrentPerform(iterations: alone.count) { i in
                (results.baseAddress! + i).initialize(to: containsDelimited(blob, needles[alone[i]]))
            }
            for (i, index) in alone.enumerated() where results[i] { found[index] = true }
        }
        guard !byLeadingWord.isEmpty else { return found }
        let groups = byLeadingWord, lengths = leadingLengths

        let chunks = max(1, min(blob.count / 65_536, ProcessInfo.processInfo.activeProcessorCount * 4))
        let hits = UnsafeMutableBufferPointer<[Int]>.allocate(capacity: chunks)
        defer { hits.deinitialize(); hits.deallocate() }
        blob.withUnsafeBytes { hay in
            let count = hay.count
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                // Words that start in this chunk; one that starts before it is the
                // previous chunk's, however far it runs.
                let end = count * (chunk + 1) / chunks
                var i = count * chunk / chunks
                if i > 0 { while i < end, isWordByte(hay[i - 1]) && isWordByte(hay[i]) { i += 1 } }
                var local: [Int] = []
                while i < end {
                    guard isWordByte(hay[i]) else { i += 1; continue }
                    let start = i
                    while i < count, isWordByte(hay[i]) { i += 1 }
                    guard lengths.contains(i - start),
                          let candidates = groups[fnv1a(UnsafeRawBufferPointer(rebasing: hay[start..<i]))]
                    else { continue }
                    for index in candidates {
                        let needle = bytes[index]
                        let after = start + needle.count
                        guard after <= count, after == count || !isWordByte(hay[after]),
                              needle.withUnsafeBytes({ memcmp(hay.baseAddress! + start, $0.baseAddress!, needle.count) }) == 0
                        else { continue }
                        local.append(index)
                    }
                }
                (hits.baseAddress! + chunk).initialize(to: local)
            }
        }
        for chunk in hits { for index in chunk { found[index] = true } }
        return found
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
    }

    /// Only buckets candidates: every hit is compared byte for byte, so a
    /// collision costs a comparison and nothing else.
    private static func fnv1a<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash
    }
}

private extension Data {
    func littleEndianWord(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let b = startIndex + offset
        return UInt32(self[b]) | UInt32(self[b + 1]) << 8 | UInt32(self[b + 2]) << 16 | UInt32(self[b + 3]) << 24
    }
}
