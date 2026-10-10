import Darwin
import Foundation

/// The root helper's one read: the three version strings of the app bundle a
/// Sparkle installer running as root has staged for one bundle identifier.
///
/// ## Where Sparkle puts it (read from Sparkle's source, 2026-10-11)
///
/// `Autoupdate/AppInstaller.m` stages into
/// `[SPULocalCacheDirectory cachePathForBundleIdentifier:bundleIdentifier]` +
/// `Installation` at every 2.x tag read (2.0.0 through 2.10.0), where
/// `bundleIdentifier` is the host bundle's own (`hostBundle.bundleIdentifier`,
/// checked equal to the one it was launched for). `cachePathForBundleIdentifier:`
/// is `NSCachesDirectory` in the user domain of the process doing it
/// (`Sparkle/SPULocalCacheDirectory.m`), so an `Autoupdate` that runs as root
/// stages under `/var/root/Library/Caches/` — observed on Tailscale's Sparkle
/// 2.8.0 (mac mini, 2026-09-13), inferred for the other versions from the
/// identical code path.
///
/// Below `Installation/` the layout changed once:
///   - 2.0.0 – 2.6.0: `<rand>/<Name>.app` — the unarchivers extract beside the
///     archive (`SUPipedUnarchiver.m`: `[_archivePath stringByDeletingLastPathComponent]`).
///   - 2.6.1 on: `<rand>/<rand>/<Name>.app` — a separate extraction directory
///     inside the per-install one (`AppInstaller.m`, `extractionDirectory`).
/// Both fixed depths are read, nothing deeper.
///
/// The cache folder is not always the bundle identifier verbatim:
///   - ≤ 2.9.2: always verbatim.
///   - 2.9.3 – 2.9.6: `.sparkle` appended when the identifier ends in `.app` or
///     `.APP` (exactly those two spellings).
///   - 2.10.0-beta.1 on: appended when the lowercased identifier ends in any of
///     `.app .service .xpc .appex .bundle .plugin .saver .kext`.
/// The helper cannot know which Sparkle an app embeds, so for an identifier
/// either rule could apply to it tries both spellings
/// (`cacheFolderNames(for:)`).
///
/// ## Why it is shaped like this
///
/// This runs as root on a request from another process, so everything a request
/// can influence is bounded:
///   - the only input is a bundle identifier, allow-listed (`isAllowedBundleID`);
///     the path is built here from a fixed prefix;
///   - every component below the prefix is opened with `O_NOFOLLOW`, directories
///     with `O_DIRECTORY` too, each relative to its parent's descriptor, so no
///     symlink anywhere below the prefix is followed and nothing is resolved by
///     path twice;
///   - only the two fixed depths above are visited, with a cap on entries per
///     directory and on `.app` candidates;
///   - `Info.plist` must be a regular file under a size cap, checked on the open
///     descriptor before reading;
///   - the answer is three length-capped strings, never a path or file contents.
enum StagedSparkleVersions {

    struct Fields: Equatable, Sendable {
        let identifier: String
        let shortVersion: String
        let buildVersion: String?
    }

    /// Root's caches — where an installer running as root stages. Fixed: no part
    /// of it comes from the client.
    static let rootCachesDirectory = "/var/root/Library/Caches"

    static let maxBundleIDLength = 255
    static let maxVersionLength = 128
    /// Larger than any real `Info.plist` (a few KB, a few hundred with long
    /// document-type lists), small enough that a hostile one costs nothing.
    static let maxInfoPlistBytes = 1 << 20
    /// Entries looked at per directory. `Installation/` holds one directory per
    /// install attempt, and Sparkle only sweeps those older than ten days
    /// (`OLD_ITEM_DELETION_INTERVAL`), so a handful is normal; more than this is
    /// not a layout Sparkle produces and is answered with nil.
    static let maxEntriesPerDirectory = 32
    /// `.app` bundles opened per request, over every folder and depth.
    static let maxAppCandidates = 8

    /// Suffixes Sparkle 2.10 appends `.sparkle` after (`SPULocalCacheDirectory.m`,
    /// `problematicBundleIdentifierExtensions`), compared lowercased. A superset
    /// of 2.9.3–2.9.6's `.app`/`.APP`.
    static let sparkleSuffixedExtensions = [
        ".app", ".service", ".xpc", ".appex", ".bundle", ".plugin", ".saver", ".kext",
    ]

    /// `[A-Za-z0-9.-]`, non-empty, at most `maxBundleIDLength` bytes, no leading
    /// `.`, no `..`. With `/` outside the alphabet, the identifier is one path
    /// component that cannot name a parent or a hidden entry.
    static func isAllowedBundleID(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty, bundleID.utf8.count <= maxBundleIDLength,
              !bundleID.hasPrefix("."), !bundleID.contains("..")
        else { return false }
        return bundleID.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-": return true
            default: return false
            }
        }
    }

    /// The cache folder names Sparkle may have used for `bundleID`, verbatim
    /// first. Two when the identifier ends in a suffix some Sparkle release
    /// renames: which release the app embeds is not knowable from here, and an
    /// `.App` ending is verbatim under 2.9.3–2.9.6 but renamed from 2.10.
    static func cacheFolderNames(for bundleID: String) -> [String] {
        let lowered = bundleID.lowercased()
        guard sparkleSuffixedExtensions.contains(where: { lowered.hasSuffix($0) }) else {
            return [bundleID]
        }
        return [bundleID, bundleID + ".sparkle"]
    }

    /// The staged build's fields, or nil.
    ///
    /// Nil also when two staged copies of this app disagree: an extraction
    /// abandoned by a killed installer stays on disk for up to ten days, and
    /// nothing here can tell which copy the parked installer will apply. The
    /// caller then shows the version as unknown, which is what it showed before
    /// this read existed.
    ///
    /// - Parameter cachesDirectory: tests only. The XPC entry point passes
    ///   nothing and gets `rootCachesDirectory`.
    static func read(
        bundleID: String, cachesDirectory: String = rootCachesDirectory
    ) -> Fields? {
        guard isAllowedBundleID(bundleID) else { return nil }
        // The prefix is fixed and root-owned all the way down, so it is opened by
        // path; `O_NOFOLLOW` still refuses a link as its last component.
        let caches = open(cachesDirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard caches >= 0 else { return nil }
        defer { close(caches) }

        var budget = maxAppCandidates
        var found: [Fields] = []
        for folder in cacheFolderNames(for: bundleID) {
            guard let installation = openDirectory(
                under: caches, components: [folder, "org.sparkle-project.Sparkle", "Installation"])
            else { continue }
            defer { close(installation) }
            guard let names = entries(of: installation) else { return nil }
            for name in names {
                // `Installation/<Name>.app` is no layout Sparkle produces.
                if name.hasSuffix(".app") { continue }
                guard let attempt = openDirectory(under: installation, components: [name])
                else { continue }  // the archive, or anything not a real directory
                defer { close(attempt) }
                guard let inner = entries(of: attempt) else { return nil }
                for innerName in inner {
                    if innerName.hasSuffix(".app") {
                        // ≤ 2.6.0: Installation/<rand>/<Name>.app
                        guard budget > 0 else { return nil }
                        budget -= 1
                        if let fields = appFields(under: attempt, name: innerName, bundleID: bundleID) {
                            found.append(fields)
                        }
                        continue
                    }
                    guard let extraction = openDirectory(under: attempt, components: [innerName])
                    else { continue }
                    defer { close(extraction) }
                    guard let apps = entries(of: extraction) else { return nil }
                    // ≥ 2.6.1: Installation/<rand>/<rand>/<Name>.app. Not deeper.
                    for appName in apps where appName.hasSuffix(".app") {
                        guard budget > 0 else { return nil }
                        budget -= 1
                        if let fields = appFields(under: extraction, name: appName, bundleID: bundleID) {
                            found.append(fields)
                        }
                    }
                }
            }
        }
        guard let first = found.first, found.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: - Descriptor-relative walking

    /// Open `components` one at a time below `parent`, each with `O_NOFOLLOW` and
    /// `O_DIRECTORY`: a symlink at any level fails the open (`ELOOP`/`ENOTDIR`)
    /// rather than being followed. The caller closes the result.
    private static func openDirectory(under parent: Int32, components: [String]) -> Int32? {
        var current = parent
        for component in components {
            // Each component is a single name: the allow-list keeps `/` out of the
            // identifier, and directory entries can't contain one.
            guard !component.isEmpty, component != ".", component != "..",
                  !component.contains("/")
            else {
                if current != parent { close(current) }
                return nil
            }
            let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if current != parent { close(current) }
            guard next >= 0 else { return nil }
            current = next
        }
        return current == parent ? nil : current
    }

    /// Names in the directory open at `fd`, hidden ones skipped. Nil when there
    /// are more than `maxEntriesPerDirectory` or the listing fails.
    private static func entries(of fd: Int32) -> [String]? {
        // `fdopendir` takes ownership of the descriptor it is given; hand it a
        // duplicate so the caller's stays open and is closed exactly once.
        let copy = dup(fd)
        guard copy >= 0 else { return nil }
        guard let dir = fdopendir(copy) else { close(copy); return nil }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name.hasPrefix(".") { continue }
            names.append(name)
            if names.count > maxEntriesPerDirectory { return nil }
        }
        return names.sorted()
    }

    /// The three fields of `<name>/Contents/Info.plist` below `parent`, when it is
    /// a staged copy of `bundleID`.
    private static func appFields(under parent: Int32, name: String, bundleID: String) -> Fields? {
        guard let contents = openDirectory(under: parent, components: [name, "Contents"])
        else { return nil }
        defer { close(contents) }
        // `O_NONBLOCK`: opening a FIFO for reading otherwise waits for a writer.
        let plist = openat(contents, "Info.plist", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard plist >= 0 else { return nil }
        defer { close(plist) }
        guard let data = readRegularFile(plist, limit: maxInfoPlistBytes) else { return nil }
        return fields(fromInfoPlist: data, bundleID: bundleID)
    }

    /// The file open at `fd`, when it is a regular file of at most `limit` bytes.
    /// Size is checked on the descriptor before reading, and the read stops at
    /// `limit + 1` regardless, in case the file grows in between.
    private static func readRegularFile(_ fd: Int32, limit: Int) -> Data? {
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              st.st_size >= 0, st.st_size <= off_t(limit)
        else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= limit {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 { return nil }
            if n == 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        return data.count <= limit ? data : nil
    }

    /// The three fields from an `Info.plist`'s bytes: nil unless it is a
    /// dictionary whose `CFBundleIdentifier` is exactly `bundleID` and whose
    /// `CFBundleShortVersionString` is a usable string. A present but unusable
    /// `CFBundleVersion` rejects the whole bundle rather than being dropped, so
    /// what goes back is either what the file says or nothing.
    static func fields(fromInfoPlist data: Data, bundleID: String) -> Fields? {
        guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil),
              let dict = plist as? [String: Any],
              let identifier = dict["CFBundleIdentifier"] as? String,
              identifier == bundleID,
              let short = cleanField(dict["CFBundleShortVersionString"])
        else { return nil }
        let build: String?
        if let raw = dict["CFBundleVersion"] {
            guard let value = cleanField(raw) else { return nil }
            build = value
        } else {
            build = nil
        }
        return Fields(identifier: identifier, shortVersion: short, buildVersion: build)
    }

    /// A plist value as a version string: a string, trimmed, non-empty, at most
    /// `maxVersionLength` bytes, without control characters. Over-long is
    /// refused, not truncated — a cut version is a different version.
    private static func cleanField(_ raw: Any?) -> String? {
        guard let trimmed = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.utf8.count <= maxVersionLength,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }
}
