import Foundation
import DuoUpdaterCore

/// `duo diff <old> <new>`: what changed between two releases of an app, below the
/// version number.
///
/// An investigation tool, not a verdict. Every line is a real difference in the
/// bytes; what it *means* is left to the reader, with the ways it is known to
/// mislead printed beside it. Built from the prototype that compared UU Remote
/// 4.35 → 4.41, Mac Mouse Fix 3.0.8 → 3.1.0 and Chatbox 1.23.1 → 1.23.3 on
/// 2026-09-17, and every noise class below is one that prototype hit:
///
/// - **Source paths are logging, not code.** Mac Mouse Fix 3.1.0 "removed" 77
///   files — it had dropped CocoaLumberjack, whose macros carried `__FILE__`; the
///   classes were all still there. Paths are compared by file name because the
///   same file is embedded as `#filePath` in one build and `#fileID` in the next,
///   and CI job directories differ per build.
/// - **A missing localization key proves nothing.** Swift inlines string literals
///   of up to 15 UTF-8 bytes, so `strings` cannot see them.
/// - **Bundler hashes are not changes.** Every Vite chunk is renamed per build;
///   with the hash removed Chatbox's 777 renames were zero.
public enum BundleDiff {

    public struct Options: Sendable {
        public var old: String
        public var new: String
        public init(old: String, new: String) {
            self.old = old
            self.new = new
        }
    }

    public static func run(_ options: Options) async -> Int32 {
        let totalStart = ContinuousClock.now
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-diff-\(UUID().uuidString)", isDirectory: true)
        // Covers the failure returns; on success it finds the directory already gone.
        defer { await offCooperativePool { try? FileManager.default.removeItem(at: scratch) } }

        // Both sides at once: unpacking and hashing are independent, and on a pair
        // of large releases each side is most of the run.
        async let oldSide = read(options.old, scratch: scratch.appendingPathComponent("old"))
        async let newSide = read(options.new, scratch: scratch.appendingPathComponent("new"))
        let sides = await (oldSide, newSide)

        let old: BundleFacts, new: BundleFacts
        switch sides {
        case (.success(let a), .success(let b)):
            old = a
            new = b
        case (.failure(let error), _), (_, .failure(let error)):
            FileHandle.standardError.write(Data("duo diff: \(error.description)\n".utf8))
            return 1
        }

        // CPU work that fans out over `concurrentPerform`, so not on the pool.
        let (reported, compareTimings) = await offCooperativePool {
            var timings = PhaseTimings()
            let lines = report(old: old, new: new, oldInput: options.old, newInput: options.new, timings: &timings)
            return (lines, timings)
        }
        var lines = reported

        // Removing the scratch copy of two app bundles is disk work of its own.
        let cleanupStart = ContinuousClock.now
        await offCooperativePool { try? FileManager.default.removeItem(at: scratch) }
        let cleanupElapsed = ContinuousClock.now - cleanupStart

        lines += timingSection(
            old: old, new: new, compare: compareTimings, cleanup: cleanupElapsed,
            total: ContinuousClock.now - totalStart)
        print(lines.joined(separator: "\n"))
        return 0
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: - Reading one side

    static func read(_ input: String, scratch: URL) async -> Result<BundleFacts, Failure> {
        let url = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(Failure(description: "\(input): no such file"))
        }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch {
            return .failure(Failure(description: "cannot create \(scratch.path): \(error.localizedDescription)"))
        }

        let unpackStart = ContinuousClock.now
        let root: URL
        var package: URL?
        switch url.pathExtension.lowercased() {
        case "app" where isDirectory.boolValue:
            root = url
        case "pkg" where !isDirectory.boolValue:
            let expanded = scratch.appendingPathComponent("expanded")
            let outcome: ChildProcess.Outcome
            do {
                // Writes a tree, so it is never torn down halfway.
                outcome = try await ChildProcess.run(
                    "/usr/sbin/pkgutil", ["--expand-full", url.path, expanded.path], onCancel: .runToCompletion)
            } catch {
                return .failure(Failure(description: "\(input): pkgutil could not run: \(error.localizedDescription)"))
            }
            guard outcome.succeeded else {
                let message = String(decoding: outcome.standardError, as: UTF8.self)
                return .failure(Failure(description: "\(input): pkgutil --expand-full failed: \(message)"))
            }
            root = expanded
            package = url
        case "zip", "dmg", "tar", "gz", "tgz", "bz2", "tbz", "xz":
            do {
                root = try await ArchiveExtractor.extractApp(from: url, workDir: scratch)
            } catch {
                return .failure(Failure(description: "\(input): \(error.localizedDescription)"))
            }
        default:
            return .failure(Failure(description: "\(input): expected an .app, .zip, .dmg or .pkg"))
        }
        let unpackElapsed = ContinuousClock.now - unpackStart

        var facts: BundleFacts
        do {
            facts = try await offCooperativePool { try BundleFactsReader.scan(root: root) }
        } catch {
            return .failure(Failure(description: "\(input): cannot read \(root.path): \(error.localizedDescription)"))
        }
        var timings = PhaseTimings()
        timings.add("unpack", unpackElapsed)
        if let package {
            let start = ContinuousClock.now
            let outcome = try? await ChildProcess.run(
                "/usr/sbin/pkgutil", ["--check-signature", package.path],
                standardError: .mergeIntoOutput, onCancel: .terminateChild)
            facts.packageSignature = BundleFactsReader.packageSignatureLines(
                outcome.map { String(decoding: $0.standardOutput, as: UTF8.self) } ?? "")
            timings.add("package signature", ContinuousClock.now - start)
        }
        for entry in facts.timings.entries { timings.add(entry.phase, entry.elapsed) }
        facts.timings = timings
        return .success(facts)
    }

    // MARK: - Report

    static func report(
        old: BundleFacts, new: BundleFacts, oldInput: String, newInput: String, timings: inout PhaseTimings
    ) -> [String] {
        var out: [String] = []
        out.append("duo diff")
        out.append("  old: \(oldInput)  \(label(old))")
        out.append("  new: \(newInput)  \(label(new))")
        out += timings.time("compare: trust surface") { trustSection(old: old, new: new) }
        out += timings.time("compare: files") { filesSection(old: old, new: new) }
        out += timings.time("compare: source paths") { sourcePathSection(old: old, new: new) }
        out += timings.time("compare: localization") { localizationSection(old: old, new: new) }
        out += timings.time("compare: electron") { asarSection(old: old, new: new) }
        return out
    }

    /// The outermost bundle's name and version.
    static func label(_ facts: BundleFacts) -> String {
        guard let key = mainBundleKey(facts), let bundle = facts.bundles[key] else { return "" }
        let name = key == "." ? facts.rootName : (key as NSString).lastPathComponent
        return "\(name) \(bundle.shortVersion ?? "?") (\(bundle.buildVersion ?? "?"))"
    }

    static func mainBundleKey(_ facts: BundleFacts) -> String? {
        facts.bundles.keys
            .filter { $0 == "." || $0.hasSuffix(".app") }
            .min { depth($0) < depth($1) || (depth($0) == depth($1) && $0 < $1) }
    }

    private static func depth(_ key: String) -> Int {
        key == "." ? 0 : key.split(separator: "/").count
    }

    static func display(_ key: String, in facts: BundleFacts) -> String {
        key == "." ? facts.rootName : key
    }

    // MARK: Trust surface

    static func trustSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out = ["", "TRUST SURFACE"]

        if old.packageSignature != nil || new.packageSignature != nil {
            if old.packageSignature == new.packageSignature {
                out.append("  package signature: unchanged (\(new.packageSignature?.first ?? "?"))")
            } else {
                out.append("  package signature: CHANGED")
                out.append("    old: " + (old.packageSignature ?? []).joined(separator: " | "))
                out.append("    new: " + (new.packageSignature ?? []).joined(separator: " | "))
            }
        }
        for component in Set(old.packageComponents.keys).union(new.packageComponents.keys).sorted() {
            switch (old.packageComponents[component], new.packageComponents[component]) {
            case (nil, let b?): out.append("  package component ADDED \(component): \(describe(b))")
            case (let a?, nil): out.append("  package component REMOVED \(component): \(describe(a))")
            case (let a?, let b?):
                out += dictionaryChanges(a, b).map { "  package component \(component) \($0)" }
            default: break
            }
        }
        for name in Set(old.scripts.keys).union(new.scripts.keys).sorted() {
            let a = old.scripts[name], b = new.scripts[name]
            if a == b {
                out.append("  script \(name): unchanged")
                continue
            }
            let changes = lineChanges(a ?? "", b ?? "")
            let what = a == nil ? "ADDED" : b == nil ? "REMOVED" : "CHANGED"
            out.append("  script \(name): \(what), \(changes.count) lines differ")
            out += changes.prefix(60).map { "      " + $0 }
            if changes.count > 60 { out.append("      … \(changes.count - 60) more") }
        }
        for path in Set(old.launchdPlists.keys).union(new.launchdPlists.keys).sorted() {
            let a = old.launchdPlists[path], b = new.launchdPlists[path]
            guard a != b else { continue }
            if a == nil { out.append("  launchd plist ADDED \(path)") }
            if b == nil { out.append("  launchd plist REMOVED \(path)") }
            if let a, let b {
                out.append("  launchd plist changed \(path)")
                out += dictionaryChanges(a, b).map { "      " + $0 }
            }
        }

        let (addedBundles, removedBundles) = keyChanges(old.bundles, new.bundles)
        out += addedBundles.map { "  bundle ADDED   \(display($0, in: new))" }
        out += removedBundles.map { "  bundle REMOVED \(display($0, in: old))" }

        let common = Set(old.bundles.keys).intersection(new.bundles.keys).sorted()
        var unchangedTrust = 0
        var trackingVersions: [String] = []
        let mainOld = mainBundleKey(old).flatMap { old.bundles[$0] }
        let mainNew = mainBundleKey(new).flatMap { new.bundles[$0] }
        for key in common {
            let a = old.bundles[key]!, b = new.bundles[key]!
            var rows: [String] = []
            rows += signatureChanges(a.signature, b.signature)
            if a.minimumSystemVersion != b.minimumSystemVersion {
                rows.append("minimum macOS: \(a.minimumSystemVersion ?? "none") -> \(b.minimumSystemVersion ?? "none")")
            }
            if a.feedURL != b.feedURL {
                rows.append("SUFeedURL: \(a.feedURL ?? "none") -> \(b.feedURL ?? "none")")
            }
            if a.publicEDKey != b.publicEDKey {
                rows.append("SUPublicEDKey: \(a.publicEDKey ?? "none") -> \(b.publicEDKey ?? "none")")
            }
            rows += dictionaryChanges(a.usageDescriptions, b.usageDescriptions).map { "usage description " + $0 }
            let (addedSchemes, removedSchemes) = setChanges(a.urlSchemes, b.urlSchemes)
            rows += addedSchemes.map { "URL scheme + \($0)" } + removedSchemes.map { "URL scheme - \($0)" }
            let trustRows = rows.count
            let (addedKeys, removedKeys) = setChanges(a.infoKeys, b.infoKeys)
            if !addedKeys.isEmpty { rows.append("Info.plist keys + " + addedKeys.joined(separator: ", ")) }
            if !removedKeys.isEmpty { rows.append("Info.plist keys - " + removedKeys.joined(separator: ", ")) }
            if trustRows == 0 { unchangedTrust += 1 }
            if !rows.isEmpty {
                out.append("  \(display(key, in: new)):")
                out += rows.map { "      " + $0 }
            }
            // A nested bundle whose version did not move with the app is an
            // embedded component with a release line of its own — Sparkle, an
            // Electron Framework, a vendored SDK.
            let tracks = (a.shortVersion == mainOld?.shortVersion && b.shortVersion == mainNew?.shortVersion)
                || (a.buildVersion == mainOld?.buildVersion && b.buildVersion == mainNew?.buildVersion)
            if key != mainBundleKey(new), !tracks,
               a.shortVersion != b.shortVersion || a.buildVersion != b.buildVersion {
                trackingVersions.append(
                    "\(display(key, in: new)): \(a.shortVersion ?? "-") (\(a.buildVersion ?? "-")) -> \(b.shortVersion ?? "-") (\(b.buildVersion ?? "-"))")
            }
        }
        out.append("  signing identity, entitlements, minimum macOS, update feed: "
            + (unchangedTrust == common.count ? "unchanged in all \(common.count) common bundles"
                : "changed in \(common.count - unchangedTrust) of \(common.count) bundles (above)"))
        if !trackingVersions.isEmpty {
            out.append("  embedded components with their own version:")
            out += trackingVersions.map { "      " + $0 }
        }

        let (addedPrivileged, removedPrivileged) = privilegedComponents(old: old, new: new)
        out += addedPrivileged.map { "  background/privileged component ADDED   \($0)" }
        out += removedPrivileged.map { "  background/privileged component REMOVED \($0)" }

        let (addedExecutables, removedExecutables) = keyChanges(old.machO, new.machO)
        out += addedExecutables.map { "  executable ADDED   \($0)" }
        out += removedExecutables.map { "  executable REMOVED \($0)" }
        for key in Set(old.machO.keys).intersection(new.machO.keys).sorted() {
            let a = old.machO[key]!, b = new.machO[key]!
            var rows: [String] = []
            if a.architectures != b.architectures {
                rows.append("architectures: \(a.architectures.joined(separator: " ")) -> \(b.architectures.joined(separator: " "))")
            }
            if a.buildSDK != b.buildSDK {
                rows.append("built with: \(a.buildSDK ?? "?") -> \(b.buildSDK ?? "?")")
            }
            let (linked, unlinked) = keyChanges(a.dylibs, b.dylibs)
            rows += linked.map { "links + \($0)" } + unlinked.map { "links - \($0)" }
            for library in Set(a.dylibs.keys).intersection(b.dylibs.keys).sorted()
            where a.dylibs[library] != b.dylibs[library] && !library.hasPrefix("/usr/lib/") && !library.hasPrefix("/System/") {
                rows.append("links \(library): \(a.dylibs[library]!) -> \(b.dylibs[library]!)")
            }
            if !rows.isEmpty {
                out.append("  \(key):")
                out += rows.map { "      " + $0 }
            }
        }
        return out
    }

    static func signatureChanges(
        _ a: SignatureVerifier.SigningSummary?, _ b: SignatureVerifier.SigningSummary?
    ) -> [String] {
        switch (a, b) {
        case (nil, nil):
            return []
        case (nil, _?):
            return ["signature: unsigned -> signed"]
        case (_?, nil):
            return ["signature: signed -> UNSIGNED or unreadable"]
        case (let a?, let b?):
            var rows: [String] = []
            if a.identifier != b.identifier {
                rows.append("signed identifier: \(a.identifier ?? "none") -> \(b.identifier ?? "none")")
            }
            if a.teamIdentifier != b.teamIdentifier {
                rows.append("TEAM ID: \(a.teamIdentifier ?? "none") -> \(b.teamIdentifier ?? "none")")
            }
            if a.authorities != b.authorities {
                rows.append("certificate chain: \(chain(a.authorities)) -> \(chain(b.authorities))")
            }
            if a.flags != b.flags {
                rows.append("code signing flags: \(a.flags.joined(separator: ",")) -> \(b.flags.joined(separator: ","))")
            }
            if a.runtimeVersion != b.runtimeVersion {
                rows.append("hardened runtime version: \(a.runtimeVersion ?? "none") -> \(b.runtimeVersion ?? "none")")
            }
            rows += dictionaryChanges(a.entitlements, b.entitlements).map { "entitlement " + $0 }
            return rows
        }
    }

    /// Anything installed where it runs without being opened: launchd jobs, login
    /// items, privileged helpers, system extensions, XPC services. Reported by the
    /// item itself (the `.app`, the `.plist`), not by every file inside it.
    static func privilegedComponents(old: BundleFacts, new: BundleFacts) -> ([String], [String]) {
        let markers = [
            "Library/LaunchDaemons/", "Library/LaunchAgents/", "Contents/Library/LaunchServices/",
            "Contents/Library/LoginItems/", "Contents/Library/SystemExtensions/", "Contents/XPCServices/",
        ]
        func items(_ facts: BundleFacts) -> Set<String> {
            var found = Set<String>()
            for path in facts.files.keys {
                for marker in markers {
                    guard let range = path.range(of: marker) else { continue }
                    let rest = path[range.upperBound...]
                    guard let first = rest.split(separator: "/").first else { continue }
                    found.insert(String(path[..<range.upperBound]) + first)
                }
            }
            return found
        }
        return setChanges(Array(items(old)), Array(items(new)))
    }

    // MARK: Files

    static func filesSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out = ["", "FILES"]
        let (added, removed) = keyChanges(old.files, new.files)
        let common = Set(old.files.keys).intersection(new.files.keys)
        let changed = common.filter { old.files[$0]!.digest != new.files[$0]!.digest }
        let signature = changed.filter { $0.contains("_CodeSignature/") || $0.hasSuffix("CodeResources") }
        let machO = changed.filter { new.machO[$0] != nil }
        out.append("  \(old.files.count) -> \(new.files.count) files; \(added.count) added, \(removed.count) removed, "
            + "\(changed.count) changed (\(machO.count) Mach-O, \(signature.count) code signature, "
            + "\(changed.count - machO.count - signature.count) other)")
        out.append("  note: every Mach-O and signature file changes on any rebuild; sizes below are the signal")
        out += capped(added.map { "  + \($0) (\(bytes(new.files[$0]!.size)))" }, 40)
        out += capped(removed.map { "  - \($0) (\(bytes(old.files[$0]!.size)))" }, 40)
        let deltas = changed
            .map { (path: $0, delta: new.files[$0]!.size - old.files[$0]!.size) }
            .filter { abs($0.delta) >= 100_000 }
            .sorted { (a: (path: String, delta: Int64), b: (path: String, delta: Int64)) -> Bool in
                let sizeA = abs(a.delta), sizeB = abs(b.delta)
                return sizeA != sizeB ? sizeA > sizeB : a.path < b.path
            }
        if !deltas.isEmpty {
            out.append("  size changes of 100 KB or more:")
            out += capped(deltas.map { "      \(signedBytes($0.delta))  \($0.path)" }, 20)
        }
        let oldTotal = old.files.values.reduce(0) { $0 + $1.size }
        let newTotal = new.files.values.reduce(0) { $0 + $1.size }
        out.append("  total: \(bytes(oldTotal)) -> \(bytes(newTotal)) (\(signedBytes(newTotal - oldTotal)))")
        return out
    }

    // MARK: Source paths

    struct SourcePathChange: Equatable {
        var added: [String]
        var removed: [String]
        /// Same file name on both sides, spelled differently: `#filePath` in one
        /// build and `#fileID` in the other, or a different CI job directory.
        var respelled: Int
    }

    /// Compared by file name, showing the longest spelling seen for it.
    static func sourcePathChange(_ old: [String], _ new: [String]) -> SourcePathChange {
        func byName(_ paths: [String]) -> [String: String] {
            var names: [String: String] = [:]
            for path in paths {
                let name = (path as NSString).lastPathComponent
                if path.count > (names[name]?.count ?? -1) { names[name] = path }
            }
            return names
        }
        let a = byName(old), b = byName(new)
        return SourcePathChange(
            added: Set(b.keys).subtracting(a.keys).map { b[$0]! }.sorted(),
            removed: Set(a.keys).subtracting(b.keys).map { a[$0]! }.sorted(),
            respelled: Set(a.keys).intersection(b.keys).filter { a[$0] != b[$0] }.count)
    }

    static func sourcePathSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out = ["", "SOURCE PATHS (compiled in by #file / __FILE__)"]
        out.append("  note: these exist where code logs or asserts. A path that disappears usually means the")
        out.append("  logging changed, not that the code was removed; a new one is a lead, not a feature.")
        var any = false
        for key in Set(old.machO.keys).union(new.machO.keys).sorted() {
            let change = sourcePathChange(old.machO[key]?.sourcePaths ?? [], new.machO[key]?.sourcePaths ?? [])
            guard !change.added.isEmpty || !change.removed.isEmpty || change.respelled > 0 else { continue }
            any = true
            let total = Set((new.machO[key]?.sourcePaths ?? []).map { ($0 as NSString).lastPathComponent }).count
            out.append("  \(key): +\(change.added.count) -\(change.removed.count) of \(total) file names"
                + (change.respelled > 0 ? ", \(change.respelled) only respelled (noise)" : ""))
            out += capped(groupedByDirectory(change.added).map { "      + " + $0 }, 40)
            out += capped(groupedByDirectory(change.removed).map { "      - " + $0 }, 40)
        }
        if !any {
            let count = new.machO.values.filter { !$0.sourcePaths.isEmpty }.count
            out.append("  no change (\(count) binaries carry source paths)")
        }
        return out
    }

    static func groupedByDirectory(_ paths: [String]) -> [String] {
        var groups: [String: [String]] = [:]
        for path in paths {
            let url = path as NSString
            groups[url.deletingLastPathComponent, default: []].append(url.lastPathComponent)
        }
        return groups.keys.sorted().map { "\($0)/{\(groups[$0]!.sorted().joined(separator: ", "))}" }
    }

    // MARK: Localization

    struct LocalizationChange: Equatable {
        var added: [String]
        var removed: [String]
        var changed: [String]
        /// Removed key -> added key carrying the identical value.
        var renamed: [(old: String, new: String)]

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.added == rhs.added && lhs.removed == rhs.removed && lhs.changed == rhs.changed
                && lhs.renamed.map(\.old) == rhs.renamed.map(\.old) && lhs.renamed.map(\.new) == rhs.renamed.map(\.new)
        }
    }

    /// A removed key and an added key with the same value are paired as a rename,
    /// one to one, in key order — Mac Mouse Fix 3.1.0 moved `button-modifier.1` to
    /// `trigger.substring.button-modifier.1`, which otherwise reads as a feature
    /// removed and another added.
    static func localizationChange(_ old: [String: String], _ new: [String: String]) -> LocalizationChange {
        var added = Set(new.keys).subtracting(old.keys).sorted()
        var removed = Set(old.keys).subtracting(new.keys).sorted()
        let changed = Set(old.keys).intersection(new.keys).filter { old[$0] != new[$0] }.sorted()
        var renamed: [(String, String)] = []
        for oldKey in removed {
            guard let index = added.firstIndex(where: { new[$0] == old[oldKey] }) else { continue }
            renamed.append((oldKey, added.remove(at: index)))
        }
        let renamedOld = Set(renamed.map(\.0))
        removed.removeAll { renamedOld.contains($0) }
        return LocalizationChange(added: added, removed: removed, changed: changed, renamed: renamed)
    }

    enum KeyEvidence: String, Sendable {
        case referencedByNewBinaries = "in new binaries only"
        case referencedByBoth = "in old and new binaries"
        case notFound = "not found (proves nothing)"
    }

    /// Where each key occurs, answered for every key at once.
    ///
    /// A key is usually a whole string of its own in the binary, so an exact lookup
    /// settles most of them; only a key that is not a whole run anywhere falls back
    /// to a substring search of the index, and those run in parallel. Keys are
    /// deduplicated first — `en` and `zh-Hans` carry the same ones. Measured on UU
    /// Remote 4.35 → 4.39 (207 new keys per file): 5.6 s searching every key in
    /// every file serially.
    static func evidence(for keys: Set<String>, old: BundleFacts, new: BundleFacts) -> [String: KeyEvidence] {
        let ordered = Array(keys)
        guard !ordered.isEmpty else { return [:] }
        let oldRuns = PrintableRuns.wholeRuns(old.stringsBlob)
        let newRuns = PrintableRuns.wholeRuns(new.stringsBlob)
        let results = UnsafeMutableBufferPointer<KeyEvidence>.allocate(capacity: ordered.count)
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: ordered.count) { index in
            let key = ordered[index]
            let inNew = newRuns.contains(key) || PrintableRuns.contains(new.stringsBlob, key)
            let inOld = inNew && (oldRuns.contains(key) || PrintableRuns.contains(old.stringsBlob, key))
            (results.baseAddress! + index).initialize(
                to: !inNew ? .notFound : inOld ? .referencedByBoth : .referencedByNewBinaries)
        }
        return Dictionary(uniqueKeysWithValues: zip(ordered, results))
    }

    static func localizationSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out = ["", "LOCALIZATION (en, Base, zh-Hans)"]
        out.append("  note: a key is looked for in the binaries' strings. \"not found\" proves nothing: Swift")
        out.append("  inlines literals of up to 15 UTF-8 bytes, and keys built at runtime never appear whole.")
        var changes: [(path: String, change: LocalizationChange)] = []
        for path in Set(old.strings.keys).union(new.strings.keys).sorted() {
            changes.append((path, localizationChange(old.strings[path] ?? [:], new.strings[path] ?? [:])))
        }
        let lookedUp = Set(changes.filter { $0.path.hasSuffix("/Localizable.strings") }.flatMap { $0.change.added })
        let found = evidence(for: lookedUp, old: old, new: new)
        var any = false
        for (path, change) in changes {
            guard !change.added.isEmpty || !change.removed.isEmpty || !change.changed.isEmpty || !change.renamed.isEmpty
            else { continue }
            any = true
            let values = new.strings[path] ?? [:], oldValues = old.strings[path] ?? [:]
            let checksBinaries = path.hasSuffix("/Localizable.strings")
            out.append("  \(path): +\(change.added.count) -\(change.removed.count) ~\(change.changed.count)"
                + (change.renamed.isEmpty ? "" : " renamed \(change.renamed.count)"))
            out += capped(change.added.map { key in
                let tag = checksBinaries ? "[\(found[key]?.rawValue ?? "?")] " : ""
                return "      + \(tag)\(key) = \(clip(values[key] ?? ""))"
            }, 60)
            out += capped(change.removed.map { "      - \($0) = \(clip(oldValues[$0] ?? ""))" }, 30)
            out += capped(change.changed.map { "      ~ \($0): \(clip(oldValues[$0] ?? "")) -> \(clip(values[$0] ?? ""))" }, 30)
            out += capped(change.renamed.map { "      renamed \($0.old) -> \($0.new)" }, 30)
        }
        if !any { out.append("  no change") }
        return out
    }

    // MARK: Electron

    // A compiled regex is never mutated after this; Regex just isn't marked Sendable.
    nonisolated(unsafe) static let bundlerHash = /[-.]([A-Za-z0-9_-]{8})(?=\.[A-Za-z0-9]+(?:\.map)?$)/

    /// The path with a bundler's content hash removed. Under `dist/` any
    /// eight-character segment before the extension goes — Vite's hashes can be
    /// all letters (`powerquery.Bpmcvcod.js`), and a guess that disagrees between
    /// two builds invents renames. Elsewhere only a segment that looks like a hash.
    static func withoutBundlerHash(_ path: String) -> String {
        if path.hasPrefix("dist/") { return path.replacing(bundlerHash, with: "") }
        return path.replacing(bundlerHash) { match in
            let segment = match.output.1
            let looksHashed = segment.contains(where: { $0.isNumber || $0 == "_" || $0 == "-" })
                || segment.filter(\.isUppercase).count >= 2
            return looksHashed ? "" : String(match.output.0)
        }
    }

    static func asarSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out: [String] = []
        for path in Set(old.asars.keys).union(new.asars.keys).sorted() {
            out += ["", "ELECTRON \(path)"]
            guard let a = old.asars[path], let b = new.asars[path] else {
                out.append("  \(old.asars[path] == nil ? "ADDED" : "REMOVED")")
                continue
            }
            out += dictionaryChanges(a.rootPackage, b.rootPackage).map { "  package.json " + $0 }

            func grouped(_ files: [String: String]) -> [String: [String]] {
                var groups: [String: [String]] = [:]
                for (file, digest) in files { groups[withoutBundlerHash(file), default: []].append(digest) }
                return groups.mapValues { $0.sorted() }
            }
            let ga = grouped(a.files), gb = grouped(b.files)
            let (rawAdded, rawRemoved) = keyChanges(a.files, b.files)
            let (added, removed) = keyChanges(ga, gb)
            let changed = Set(ga.keys).intersection(gb.keys).filter { ga[$0] != gb[$0] }
            out.append("  \(a.files.count) -> \(b.files.count) files; paths +\(rawAdded.count) -\(rawRemoved.count), "
                + "without bundler hashes +\(added.count) -\(removed.count); \(changed.count) changed content")
            out += capped(added.filter { !$0.hasPrefix("node_modules/") }.map { "  + \($0)" }, 40)
            out += capped(removed.filter { !$0.hasPrefix("node_modules/") }.map { "  - \($0)" }, 40)

            let (newPackages, gonePackages) = keyChanges(a.packages, b.packages)
            let bumped = Set(a.packages.keys).intersection(b.packages.keys).filter { a.packages[$0] != b.packages[$0] }.sorted()
            out.append("  node_modules: \(a.packages.count) -> \(b.packages.count) packages; "
                + "\(newPackages.count) added, \(gonePackages.count) removed, \(bumped.count) version changes")
            out += newPackages.map { "      + \($0)@\(b.packages[$0]!)" }
            out += gonePackages.map { "      - \($0)@\(a.packages[$0]!)" }
            out += bumped.map { "      ~ \($0): \(a.packages[$0]!) -> \(b.packages[$0]!)" }

            func sources(_ maps: [String: [String]]) -> [String: Set<String>] {
                var merged: [String: Set<String>] = [:]
                for (map, list) in maps { merged[withoutBundlerHash(map), default: []].formUnion(list) }
                return merged
            }
            let sa = sources(a.mapSources), sb = sources(b.mapSources)
            for map in Set(sa.keys).union(sb.keys).sorted() {
                let own = { (set: Set<String>) in Set(set.filter { !$0.contains("node_modules/") }.map(tidySource)) }
                let (plus, minus) = setChanges(Array(own(sa[map] ?? [])), Array(own(sb[map] ?? [])))
                guard !plus.isEmpty || !minus.isEmpty else { continue }
                out.append("  source map \(map): own sources +\(plus.count) -\(minus.count)")
                out += capped(plus.map { "      + \($0)" }, 80)
                out += capped(minus.map { "      - \($0)" }, 80)
            }
        }
        return out
    }

    private static func tidySource(_ source: String) -> String {
        var trimmed = Substring(source)
        while trimmed.hasPrefix("../") { trimmed = trimmed.dropFirst(3) }
        return String(trimmed)
    }

    // MARK: Timings

    static func timingSection(
        old: BundleFacts, new: BundleFacts, compare: PhaseTimings, cleanup: Duration, total: Duration
    ) -> [String] {
        var out = ["", "TIMINGS (old and new are read concurrently)"]
        for (name, facts) in [("old", old), ("new", new)] {
            let sum = facts.timings.entries.reduce(Duration.zero) { $0 + $1.elapsed }
            out.append("  \(name): \(seconds(sum)) — \(facts.files.count) files, \(bytes(facts.bytesHashed)) hashed, "
                + "\(facts.machO.count) Mach-O, \(facts.bundles.count) bundles")
            for entry in facts.timings.entries {
                out.append("      \(entry.phase.padding(toLength: 28, withPad: " ", startingAt: 0))\(seconds(entry.elapsed))")
            }
        }
        for entry in compare.entries {
            out.append("  \(entry.phase.padding(toLength: 30, withPad: " ", startingAt: 0))\(seconds(entry.elapsed))")
        }
        out.append("  \("remove scratch copies".padding(toLength: 30, withPad: " ", startingAt: 0))\(seconds(cleanup))")
        out.append("  \("total".padding(toLength: 30, withPad: " ", startingAt: 0))\(seconds(total))")
        return out
    }

    // MARK: - Helpers

    static func keyChanges<V>(_ old: [String: V], _ new: [String: V]) -> (added: [String], removed: [String]) {
        (Set(new.keys).subtracting(old.keys).sorted(), Set(old.keys).subtracting(new.keys).sorted())
    }

    static func setChanges(_ old: [String], _ new: [String]) -> (added: [String], removed: [String]) {
        (Set(new).subtracting(old).sorted(), Set(old).subtracting(new).sorted())
    }

    static func dictionaryChanges(_ old: [String: String], _ new: [String: String]) -> [String] {
        Set(old.keys).union(new.keys).sorted().compactMap { key in
            switch (old[key], new[key]) {
            case (nil, let b?): return "+ \(key) = \(clip(b))"
            case (let a?, nil): return "- \(key) = \(clip(a))"
            case (let a?, let b?) where a != b: return "~ \(key): \(clip(a)) -> \(clip(b))"
            default: return nil
            }
        }
    }

    static func describe(_ attributes: [String: String]) -> String {
        attributes.keys.sorted().map { "\($0)=\(attributes[$0]!)" }.joined(separator: " ")
    }

    /// Changed lines between two texts, `-` then `+`, by a longest-common-
    /// subsequence walk. Installer scripts are a few hundred lines at most.
    static func lineChanges(_ old: String, _ new: String) -> [String] {
        let a = old.components(separatedBy: "\n"), b = new.components(separatedBy: "\n")
        guard a.count * b.count <= 4_000_000 else {
            return ["(too long to compare line by line: \(a.count) and \(b.count) lines)"]
        }
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                i += 1
                j += 1
            } else if i < a.count, j == b.count || lcs[i + 1][j] >= lcs[i][j + 1] {
                out.append("- " + a[i])
                i += 1
            } else {
                out.append("+ " + b[j])
                j += 1
            }
        }
        return out
    }

    static func capped(_ lines: [String], _ limit: Int) -> [String] {
        lines.count <= limit ? lines : Array(lines.prefix(limit)) + ["      … \(lines.count - limit) more"]
    }

    static func clip(_ text: String, _ limit: Int = 120) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "\\n")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func signedBytes(_ count: Int64) -> String {
        count == 0 ? "no change" : (count > 0 ? "+" : "-") + bytes(abs(count))
    }

    static func chain(_ authorities: [String]) -> String {
        authorities.isEmpty ? "none" : authorities.joined(separator: " < ")
    }

    static func seconds(_ duration: Duration) -> String {
        let (s, attoseconds) = duration.components
        return String(format: "%.2fs", Double(s) + Double(attoseconds) / 1e18)
    }
}
