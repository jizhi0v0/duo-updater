import Foundation

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
///
/// In Core so the workbench and `duo diff` print the same report from the same code.
public enum BundleDiff {

    /// Compare two releases and return the full report, timings included.
    ///
    /// Each side is a path to an `.app`, `.zip`, `.dmg` or `.pkg`; a label for it
    /// goes in the report header, which is where a caller's own wording (a
    /// command-line argument, "backup") belongs. Cancelling the task stops the
    /// walk between files: the workbench starts one per selected app, and a
    /// selection that moves on must not leave two multi-gigabyte bundles hashing.
    ///
    /// `omittedFromOld` names files the old side lacks on purpose — a backup's
    /// skipped runtime state — so they are not reported as added by the update.
    ///
    /// `recordedOld` names a backup whose facts may already be in
    /// ``BackupFactsLibrary``, in which case the old side is read from there
    /// instead of off disk. An entry that is absent or does not match changes
    /// nothing: the old path is read exactly as it would have been.
    public static func report(
        old oldPath: String, new newPath: String, oldLabel: String? = nil, newLabel: String? = nil,
        omittedFromOld: [String] = [], recordedOld: BackupFactsLibrary.Reference? = nil
    ) async -> Result<String, Failure> {
        let stop = StopFlag()
        return await withTaskCancellationHandler {
            await compare(old: oldPath, new: newPath, oldLabel: oldLabel ?? oldPath,
                          newLabel: newLabel ?? newPath, omittedFromOld: omittedFromOld,
                          recordedOld: recordedOld, stop: stop)
        } onCancel: {
            stop.set()
        }
    }

    private static func compare(
        old oldPath: String, new newPath: String, oldLabel: String, newLabel: String,
        omittedFromOld: [String], recordedOld: BackupFactsLibrary.Reference?, stop: StopFlag
    ) async -> Result<String, Failure> {
        let totalStart = ContinuousClock.now
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-diff-\(UUID().uuidString)", isDirectory: true)
        // Covers the failure returns; on success it finds the directory already gone.
        defer { await offCooperativePool { try? FileManager.default.removeItem(at: scratch) } }

        // Both sides at once: unpacking and hashing are independent, and on a pair
        // of large releases each side is most of the run.
        async let oldSide = read(
            oldPath, scratch: scratch.appendingPathComponent("old"), stop: stop, recorded: recordedOld)
        async let newSide = read(newPath, scratch: scratch.appendingPathComponent("new"), stop: stop)
        let sides = await (oldSide, newSide)

        let old: BundleFacts, new: BundleFacts
        switch sides {
        case (.success(var a), .success(let b)):
            a.omittedByBackup = Set(omittedFromOld)
            old = aligned(a)
            new = aligned(b)
        case (.failure(let error), _), (_, .failure(let error)):
            return .failure(error)
        }
        if stop.isSet { return .failure(.cancelled) }

        // CPU work that fans out over `concurrentPerform`, so not on the pool.
        let (reported, compareTimings) = await offCooperativePool {
            var timings = PhaseTimings()
            let lines = report(old: old, new: new, oldInput: oldLabel, newInput: newLabel, timings: &timings)
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
        return .success(lines.joined(separator: "\n"))
    }

    public struct Failure: Error, CustomStringConvertible, Sendable, Equatable {
        public let description: String
        public static let cancelled = Failure(description: "cancelled")
    }

    /// Set from a cancellation handler, read between files inside an
    /// `offCooperativePool` hop, where the task's own cancellation is not visible.
    final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    // MARK: - Reading one side

    static func read(
        _ input: String, scratch: URL, stop: StopFlag = StopFlag(),
        recorded: BackupFactsLibrary.Reference? = nil
    ) async -> Result<BundleFacts, Failure> {
        // Before anything is unpacked or walked: a backup is bytes that cannot
        // change, so if what it holds was recorded when it was written, that is
        // the same answer this function would spend the rest of its time
        // producing. On a backup that lives on a disk it is also the difference
        // between reading one file and unpacking a whole app bundle over a cable.
        if let recorded {
            let start = ContinuousClock.now
            // Resolved here, not inside the hop — see `BackupFactsLibrary.entry(for:)`.
            let entry = BackupFactsLibrary.entry(for: recorded)
            if var facts = await offCooperativePool({ BackupFactsLibrary.facts(at: entry) }) {
                var timings = PhaseTimings()
                // Kept under the 28 characters `timingSection` pads a phase name to,
                // which truncates rather than wraps.
                timings.add("read the recorded facts", ContinuousClock.now - start)
                facts.timings = timings
                return .success(facts)
            }
        }
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
        case "aar":
            // A backup kept on another disk. It is stored as one Apple Archive
            // — that is what lets a disk formatted for Windows, or a share,
            // hold an app bundle at all — and comparing an app against its
            // backup is precisely what this is asked to do, so refusing the
            // format the backup is in meant the comparison worked only while
            // the backups happened to be on this Mac.
            //
            // Named after the archive, so the report says "ChatGPT.app" rather
            // than the name of a scratch directory. `extract` writes the
            // bundle's *contents* into the directory it is given, so this
            // directory is the bundle.
            let unpacked = scratch.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent + ".app", isDirectory: true)
            do {
                try await BundleArchive.extract(archive: url, into: unpacked)
            } catch {
                return .failure(Failure(description: "\(input): \(error.localizedDescription)"))
            }
            root = unpacked
        case "zip", "dmg", "tar", "gz", "tgz", "bz2", "tbz", "xz":
            do {
                root = try await ArchiveExtractor.extractApp(from: url, workDir: scratch)
            } catch {
                return .failure(Failure(description: "\(input): \(error.localizedDescription)"))
            }
        default:
            return .failure(Failure(
                description: "\(input): expected an .app, .zip, .dmg, .pkg or .aar"))
        }
        let unpackElapsed = ContinuousClock.now - unpackStart

        var facts: BundleFacts
        do {
            facts = try await offCooperativePool { try BundleFactsReader.scan(root: root, stop: stop) }
        } catch is CancellationError {
            return .failure(.cancelled)
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
        facts.isPackage = package != nil
        return .success(facts)
    }

    // MARK: - Aligning a package with everything else

    static let packagePrefix = "<package>/"
    static let componentPlaceholder = "<component>"

    /// A pkg's paths rewritten to line up with any other input.
    ///
    /// An `.app`, zip or dmg is read from the bundle itself, so its paths are
    /// `Contents/…`; a pkg is read from its expanded tree, so the same file is
    /// `UURemote.pkg/Payload/Applications/UURemote.app/Contents/…`. Left alone,
    /// comparing an installed app with the next pkg shares no path at all, and the
    /// report said every bundle was removed and re-added while its trust line read
    /// "unchanged in all 0 common bundles". So: everything inside the package's
    /// main app becomes app-relative; everything else — scripts, launchd plists,
    /// receipts — goes under `<package>/`; and a lone component package's name,
    /// which some vendors version, becomes `<component>`.
    static func aligned(_ facts: BundleFacts) -> BundleFacts {
        guard facts.isPackage else { return facts }
        var out = facts
        let components = Array(facts.packageComponents.keys)
        func component(_ key: String) -> String {
            guard components.count == 1, let only = components.first else { return key }
            if key == only { return componentPlaceholder }
            return key.hasPrefix(only + "/") ? componentPlaceholder + key.dropFirst(only.count) : key
        }
        var probe = BundleFacts()
        probe.bundles = Dictionary(
            facts.bundles.map { (component($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        let app = mainBundleKey(probe)
        func key(_ raw: String) -> String {
            let path = component(raw)
            if let app {
                if path == app { return "." }
                if path.hasPrefix(app + "/") { return String(path.dropFirst(app.count + 1)) }
            }
            return packagePrefix + path
        }
        func rekey<V>(_ map: [String: V]) -> [String: V] {
            Dictionary(map.map { (key($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        out.files = rekey(facts.files)
        out.bundles = rekey(facts.bundles)
        out.machO = rekey(facts.machO)
        out.strings = rekey(facts.strings)
        out.launchdPlists = rekey(facts.launchdPlists)
        out.asars = rekey(facts.asars)
        out.scripts = rekey(facts.scripts)
        out.unindexedMachO = facts.unindexedMachO.map(key)
        out.omittedByBackup = Set(facts.omittedByBackup.map(key))
        out.packageComponents = Dictionary(
            facts.packageComponents.map { (component($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        if let app { out.rootName = (component(app) as NSString).lastPathComponent }
        return out
    }

    // MARK: - Report

    static func report(
        old: BundleFacts, new: BundleFacts, oldInput: String, newInput: String, timings: inout PhaseTimings
    ) -> [String] {
        var out: [String] = []
        out.append("duo diff")
        out.append("  old: \(oldInput)  \(label(old))")
        out.append("  new: \(newInput)  \(label(new))")
        if old.isPackage != new.isPackage {
            out.append("  note: only one side is a package. The app inside it is compared with the other side;")
            out.append("  installer items (scripts, launchd plists, receipts) have no counterpart and show under <package>/.")
        }
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

        if old.isPackage != new.isPackage {
            // One side is an app: there is no second package to compare the
            // signature or the scripts with, so say which side has them.
            let side = old.isPackage ? "old" : "new"
            let package = old.isPackage ? old : new
            out.append("  package signature (\(side) only): " + (package.packageSignature ?? []).joined(separator: " | "))
            for component in package.packageComponents.keys.sorted() {
                out.append("  package component \(component) (\(side) only): \(describe(package.packageComponents[component]!))")
            }
            for name in package.scripts.keys.sorted() {
                out.append("  script \(name) (\(side) only): \(lineCount(package.scripts[name]!)) lines")
            }
        } else if old.packageSignature != nil || new.packageSignature != nil {
            if old.packageSignature == new.packageSignature {
                out.append("  package signature: unchanged (\(new.packageSignature?.first ?? "?"))")
            } else {
                out.append("  package signature: CHANGED")
                out.append("    old: " + (old.packageSignature ?? []).joined(separator: " | "))
                out.append("    new: " + (new.packageSignature ?? []).joined(separator: " | "))
            }
        }
        for component in Set(old.packageComponents.keys).union(new.packageComponents.keys).sorted()
        where old.isPackage == new.isPackage {
            switch (old.packageComponents[component], new.packageComponents[component]) {
            case (nil, let b?): out.append("  package component ADDED \(component): \(describe(b))")
            case (let a?, nil): out.append("  package component REMOVED \(component): \(describe(a))")
            case (let a?, let b?):
                out += dictionaryChanges(a, b).map { "  package component \(component) \($0)" }
            default: break
            }
        }
        for name in Set(old.scripts.keys).union(new.scripts.keys).sorted() where old.isPackage == new.isPackage {
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
            + (common.isEmpty ? "NOT COMPARED — no bundle is at the same path on both sides"
                : unchangedTrust == common.count ? "unchanged in all \(common.count) common bundles"
                : "changed in \(common.count - unchangedTrust) of \(common.count) bundles (above)"))
        if !trackingVersions.isEmpty {
            out.append("  embedded components with their own version:")
            out += trackingVersions.map { "      " + $0 }
        }

        let (addedPrivileged, removedPrivileged) = privilegedComponents(old: old, new: new)
        out += addedPrivileged.map { "  background/privileged component ADDED   \($0)" }
        out += removedPrivileged.map { "  background/privileged component REMOVED \($0)" }

        let (addedExecutables, removedExecutables) = keyChanges(old.machO, new.machO)
        // Capped like every other list: Baidu Netdisk 8.8.3 vendored 45 dylibs at once.
        out += capped(addedExecutables.map { "  executable ADDED   \($0)" }, 40)
        out += capped(removedExecutables.map { "  executable REMOVED \($0)" }, 40)
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
                rows.append("signed identifier: \(shown(a.identifier)) -> \(shown(b.identifier))")
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
        let (everyAdded, removed) = keyChanges(old.files, new.files)
        // Not in the backup because the backup skipped them, not because the update
        // brought them: unreadable runtime state an app keeps inside its own bundle.
        let skippedByBackup = everyAdded.filter { old.omittedByBackup.contains($0) }
        let added = everyAdded.filter { !old.omittedByBackup.contains($0) }
        let common = Set(old.files.keys).intersection(new.files.keys)
        let changed = common.filter { old.files[$0]!.digest != new.files[$0]!.digest }
        let signature = changed.filter { $0.contains("_CodeSignature/") || $0.hasSuffix("CodeResources") }
        let machO = changed.filter { new.machO[$0] != nil }
        out.append("  \(old.files.count) -> \(new.files.count) files; \(added.count) added, \(removed.count) removed, "
            + "\(changed.count) changed (\(machO.count) Mach-O, \(signature.count) code signature, "
            + "\(changed.count - machO.count - signature.count) other)")
        out.append("  note: every Mach-O and signature file changes on any rebuild; sizes below are the signal")
        if !skippedByBackup.isEmpty {
            out.append("  \(skippedByBackup.count) more only on the new side because the backup skipped them "
                + "(unreadable runtime state, not part of the update):")
            out += capped(skippedByBackup.map { "      \($0)" }, 20)
        }
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
            out += groupedByDirectory(change.added, prefix: "      + ", directoryLimit: 40)
            out += groupedByDirectory(change.removed, prefix: "      - ", directoryLimit: 40)
        }
        if !any {
            let count = new.machO.values.filter { !$0.sourcePaths.isEmpty }.count
            out.append("  no change (\(count) binaries carry source paths)")
        }
        return out
    }

    static let namesPerLine = 8

    /// Paths grouped by directory, a few names per line, cut after `directoryLimit`
    /// directories.
    ///
    /// A few names per line: joined into one, Baidu Netdisk 8.8.3's bundled GLib put
    /// 2,563 characters on a single line, and the workbench drew the whole report
    /// blank. The limit counts directories, not lines — cutting by lines let one
    /// large directory use up the whole allowance and hide every other directory.
    static func groupedByDirectory(_ paths: [String], prefix: String = "", directoryLimit: Int = .max) -> [String] {
        var groups: [String: [String]] = [:]
        for path in paths {
            let url = path as NSString
            groups[url.deletingLastPathComponent, default: []].append(url.lastPathComponent)
        }
        let directories = groups.keys.sorted()
        var lines = directories.prefix(directoryLimit).flatMap { directory in
            let names = groups[directory]!.sorted()
            return stride(from: 0, to: names.count, by: namesPerLine).map { start in
                let chunk = names[start..<min(start + namesPerLine, names.count)]
                return "\(prefix)\(directory)/{\(chunk.joined(separator: ", "))}"
            }
        }
        if directories.count > directoryLimit {
            lines.append("\(prefix)… \(directories.count - directoryLimit) more directories")
        }
        return lines
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

    /// A removed key and an added key with the same value are paired as a rename —
    /// Mac Mouse Fix 3.1.0 moved `button-modifier.1` to
    /// `trigger.substring.button-modifier.1`, which otherwise reads as a feature
    /// removed and another added.
    ///
    /// Only when the pairing is unambiguous: the value is not blank, and exactly one
    /// removed key and exactly one added key carry it. A nib's strings file is full
    /// of empty titles and repeated `OK`s, and pairing those would hide a real
    /// removal behind an invented rename.
    static func localizationChange(_ old: [String: String], _ new: [String: String]) -> LocalizationChange {
        var added = Set(new.keys).subtracting(old.keys).sorted()
        var removed = Set(old.keys).subtracting(new.keys).sorted()
        let changed = Set(old.keys).intersection(new.keys).filter { old[$0] != new[$0] }.sorted()
        let removedByValue = Dictionary(grouping: removed, by: { old[$0]! })
        let addedByValue = Dictionary(grouping: added, by: { new[$0]! })
        var renamed: [(String, String)] = []
        for oldKey in removed {
            let value = old[oldKey]!
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  removedByValue[value]?.count == 1,
                  let candidates = addedByValue[value], candidates.count == 1,
                  let index = added.firstIndex(of: candidates[0])
            else { continue }
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
        /// The key is in the new binaries, and whether the old ones carried it
        /// is unknown: that side's facts came from ``BackupFactsLibrary``, which
        /// does not keep the strings index.
        ///
        /// Its own case rather than `referencedByNewBinaries`, which is a claim
        /// *about the old binaries* — "only" — that an unindexed side cannot
        /// support. Folding the two would leave the report saying a key is new
        /// for every key it finds, in exactly the reading a reader would act on.
        case oldNotIndexed = "in new binaries; old side not indexed"
        /// Neither side can be searched, because the new side was not indexed
        /// either. Unreachable while the new side is always a live scan; here so
        /// that an unindexed value is never read as a search that came up empty.
        case notIndexed = "binaries not indexed"
    }

    /// Where each key occurs, answered for every key at once.
    ///
    /// A key is usually a whole string of its own in the binary, so an exact lookup
    /// settles most of them; only a key that is not a whole run anywhere falls back
    /// to a substring search of the index, and those run in parallel. Keys are
    /// deduplicated first — `en` and `zh-Hans` carry the same ones. Measured on UU
    /// Remote 4.35 → 4.39 (207 new keys per file): 5.6 s searching every key in
    /// every file serially.
    ///
    /// The substring fallback only counts a key that stands as a word inside the
    /// longer string, and only for keys of `minimumSubstringKeyBytes` or more: an
    /// app that uses English text as keys adds `OK` and `Cancel`, which occur inside
    /// any number of unrelated strings (`SOK_STATE`, `Cancellation`). A length floor
    /// alone did not do it — `Cancel` is six bytes.
    static let minimumSubstringKeyBytes = 6

    static func evidence(for keys: Set<String>, old: BundleFacts, new: BundleFacts) -> [String: KeyEvidence] {
        let ordered = Array(keys)
        guard !ordered.isEmpty else { return [:] }
        guard new.stringsIndexed else {
            return Dictionary(uniqueKeysWithValues: ordered.map { ($0, KeyEvidence.notIndexed) })
        }
        // An empty index and no index are the same bytes and opposite meanings, so
        // the old side is searched only when it has one. Without this the searches
        // below both fail — `wholeRuns` is empty and `containsDelimited` cannot fit
        // the key into a shorter blob — and every key found in the new binaries
        // would be reported as being in the new binaries *only*.
        let searchOld = old.stringsIndexed
        let oldRuns = searchOld ? PrintableRuns.wholeRuns(old.stringsBlob) : []
        let newRuns = PrintableRuns.wholeRuns(new.stringsBlob)
        let results = UnsafeMutableBufferPointer<KeyEvidence>.allocate(capacity: ordered.count)
        defer { results.deallocate() }
        DispatchQueue.concurrentPerform(iterations: ordered.count) { index in
            let key = ordered[index]
            let searchable = key.utf8.count >= minimumSubstringKeyBytes
            let inNew = newRuns.contains(key) || (searchable && PrintableRuns.containsDelimited(new.stringsBlob, key))
            let inOld = searchOld && inNew
                && (oldRuns.contains(key) || (searchable && PrintableRuns.containsDelimited(old.stringsBlob, key)))
            (results.baseAddress! + index).initialize(
                to: !inNew ? .notFound
                    : inOld ? .referencedByBoth
                    : searchOld ? .referencedByNewBinaries : .oldNotIndexed)
        }
        return Dictionary(uniqueKeysWithValues: zip(ordered, results))
    }

    static func localizationSection(old: BundleFacts, new: BundleFacts) -> [String] {
        var out = ["", "LOCALIZATION (en, Base, zh-Hans)"]
        out.append("  note: a key is looked for in the binaries' strings. \"not found\" proves nothing: Swift")
        out.append("  inlines literals of up to 15 UTF-8 bytes, and keys built at runtime never appear whole.")
        if !new.stringsIndexed {
            out.append("  note: neither side's binaries were indexed, so no key below was looked for at all.")
        } else if !old.stringsIndexed {
            out.append("  note: the old side was read from what was recorded when the backup was made, which")
            out.append("  does not keep the strings index. A key can be found in the new binaries; whether the")
            out.append("  old ones carried it is not known here.")
        }
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
        if changes.isEmpty {
            out.append("  NOT COMPARED — no en, Base or zh-Hans .strings file on either side")
        } else if !any {
            out.append("  no change in \(changes.count) strings files")
        }
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

    /// Lines as `wc -l` counts them — newline bytes, so a CRLF script is not one
    /// line per grapheme `\r\n` — plus a last line that has no newline.
    static func lineCount(_ text: String) -> Int {
        text.utf8.filter { $0 == 0x0A }.count + (text.isEmpty || text.utf8.last == 0x0A ? 0 : 1)
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

    /// An absent or empty value spelled out, so `x ->  -> y` never reads as a gap.
    static func shown(_ value: String?) -> String {
        guard let value else { return "none" }
        return value.isEmpty ? "(empty)" : value
    }

    static func chain(_ authorities: [String]) -> String {
        authorities.isEmpty ? "none" : authorities.joined(separator: " < ")
    }

    static func seconds(_ duration: Duration) -> String {
        let (s, attoseconds) = duration.components
        return String(format: "%.2fs", Double(s) + Double(attoseconds) / 1e18)
    }
}
