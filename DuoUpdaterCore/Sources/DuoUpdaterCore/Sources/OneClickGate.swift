import Foundation
import Synchronization

/// Which installed copies of an app may take a one-click update, declared in the
/// app's recipe family (`AppRecipeSet.oneClickGates`) and enforced in one place
/// for every source: `UpdatePolicy.canAutoInstall` (the offer) and
/// `InstallCoordinator.perform` (the gate). A copy a gate does not admit keeps
/// its detection — the row still says what is newer — and gets no one-click.
///
/// For one bundle id that names more than one thing the vendor ships, where the
/// update a source resolves is right for one of them and would replace the
/// other:
///  - MuseScore 3 and 4 share `org.musescore.MuseScore` and install side by
///    side; the 4.x build would take `MuseScore 3.app`'s place.
///  - GitKraken's On-Premise Serverless edition shares the normal edition's id,
///    Team and Info.plist; the normal build would swap its edition.
///
/// A gate is a requirement on the copy on disk, never on the machine. Several
/// gates for one id must all admit.
///
/// A gate may also be scoped to the package on offer (`offering`), for an id
/// whose editions each have their own package: Hoppscotch's Cloud and Self-Host
/// share id, Team and Info.plist, and each edition's gate asks for its own
/// marker only when its own package is offered. Once an id has a scoped gate,
/// an offer none of its scoped gates names is withheld (`unnamedOffer`): a
/// package nobody has tied to an edition is never swapped in.
public struct OneClickGate: Sendable {
    /// Matched against `InstalledApp.recipeBundleID`, case-insensitively.
    public let bundleID: String
    public let requirement: Requirement
    /// Why a copy that fails the requirement is kept off the one-click and what
    /// to do instead, for the log, the CLI and the refusal the installer reports.
    public let reason: String
    /// Nil: the gate applies to every offer. Otherwise a pattern (searched;
    /// write your own anchors) on the offer's identity, `"<source>:<package>"`
    /// (`OneClickGateRegistry.offerIdentity`): the gate applies only to the
    /// offers it matches, e.g. `GitHub:Hoppscotch_SelfHost_mac_aarch64.dmg` or
    /// `Homebrew:hoppscotch`.
    public let offering: String?

    public enum Requirement: Sendable {
        /// `CFBundleShortVersionString` matches this pattern (searched; write
        /// your own anchors). A copy without one is not admitted.
        case installedVersion(pattern: String)
        /// The file at `path` inside `Contents/Resources/app.asar` (a packed
        /// entry, read without unpacking) matches this pattern. A missing asar,
        /// entry or match is not admitted: failing closed costs one manual
        /// update, failing open could cost the user the app they chose.
        case asarEntry(path: String, pattern: String)
        /// The bundle's main executable (`Contents/MacOS/<CFBundleExecutable>`)
        /// contains `marker`'s UTF-8 bytes, read in chunks and never mapped
        /// (`ExecutableBytes`). For editions whose Info.plist is identical and
        /// only the binary tells them apart. A plist without
        /// `CFBundleExecutable`, a missing, unreadable, non-regular or
        /// oversized executable, or no match is not admitted, for the same
        /// reason as `asarEntry`. The verdict is cached per Info.plist and
        /// executable identity (`ExecutableMarker`).
        case executableContains(marker: String)
        /// The bundle's main executable was read whole and does not contain
        /// `marker`: for an edition whose sibling's marker must be absent, since
        /// `executableContains` alone admits a copy that holds both. Fails
        /// closed the same way: an empty marker, or anything that keeps the
        /// whole executable from being read, is not admitted.
        case executableLacks(marker: String)
    }

    public init(bundleID: String, requirement: Requirement, reason: String, offering: String? = nil) {
        self.bundleID = bundleID
        self.requirement = requirement
        self.reason = reason
        self.offering = offering
    }

    /// Whether this gate speaks for the offer whose identity is `identity`.
    func applies(toOffer identity: String?) -> Bool {
        guard let offering else { return true }
        guard let identity else { return false }
        return identity.range(of: offering, options: .regularExpression) != nil
    }

    /// What withholds an offer none of an id's scoped gates names. Its
    /// requirement never admits.
    static func unnamedOffer(bundleID: String) -> OneClickGate {
        OneClickGate(
            bundleID: bundleID, requirement: .installedVersion(pattern: "(?!)"),
            reason: unnamedOfferReason)
    }

    static let unnamedOfferReason =
        "the update on offer is not a package DuoUpdater has tied to this copy's edition; update it from its own updater"

    /// Whether `app` meets the requirement. `fresh` reads the executable for
    /// `.executableContains` again instead of trusting the cached verdict —
    /// for the install-time gate, which runs once, off the main actor.
    public func admits(_ app: InstalledApp, fresh: Bool = false) -> Bool {
        switch requirement {
        case .installedVersion(let pattern):
            guard let version = app.shortVersion else { return false }
            return version.range(of: pattern, options: .regularExpression) != nil
        case .asarEntry(let path, let pattern):
            let asar = app.path.appendingPathComponent("Contents/Resources/app.asar")
            guard let data = AsarEntryReader.packedEntry(path, inAsarAt: asar) else { return false }
            return String(decoding: data, as: UTF8.self)
                .range(of: pattern, options: .regularExpression) != nil
        case .executableContains(let marker):
            return ExecutableMarker.presence(marker, inMainExecutableOf: app.path, fresh: fresh) == .present
        case .executableLacks(let marker):
            return ExecutableMarker.presence(marker, inMainExecutableOf: app.path, fresh: fresh) == .absent
        }
    }
}

/// `OneClickGate.Requirement.executableContains`: whether the bundle's main
/// executable holds a literal.
///
/// Cached, for the reason `AsarEntryReader` is: `UpdatePolicy.canAutoInstall`
/// is asked per row on the main actor, and the popover header's `canUpdateAll`
/// asks it on every redraw, unmemoised. A read is the whole file up to the
/// first hit — 67 MB for a Hoppscotch Self-Host copy, which has none. A
/// verdict is kept per bundle and marker with the identity (device, inode,
/// size, mtime) of the Info.plist it was read from and of the executable that
/// plist named, so a repeated ask is two `stat`s and never re-parses the plist;
/// a change to either file reads again. `fresh` skips the cache (and refreshes
/// it) for the install-time gate.
enum ExecutableMarker {
    /// Executables larger than this are not read, and not admitted. The
    /// largest seen is 70.9 MB (Hoppscotch 26.9.0 x64); four times that leaves
    /// room for growth while bounding one cold read to a few hundred ms.
    static let byteLimit: Int64 = 256 << 20

    /// What a read of the executable proved about the marker. `unknown` is
    /// everything that is neither a hit nor a whole read without one (no plist,
    /// no executable, unreadable, non-regular, oversized, an empty marker), so
    /// neither `executableContains` nor `executableLacks` admits it.
    enum Presence: Sendable, Equatable { case present, absent, unknown }

    static func found(_ marker: String, inMainExecutableOf bundle: URL, fresh: Bool = false) -> Bool {
        presence(marker, inMainExecutableOf: bundle, fresh: fresh) == .present
    }

    static func presence(_ marker: String, inMainExecutableOf bundle: URL, fresh: Bool = false) -> Presence {
        guard !marker.isEmpty else { return .unknown }
        let plistPath = bundle.appendingPathComponent("Contents/Info.plist").path
        guard let plistIdentity = FileIdentity(atPath: plistPath) else { return .unknown }
        let key = Key(bundle: bundle.path, marker: marker)
        if !fresh, let kept = cache.withLock({ $0[key] }), kept.plist == plistIdentity,
           kept.executablePath.flatMap({ FileIdentity(atPath: $0) }) == kept.executable {
            return kept.presence
        }
        let entry = read(marker, bundle: bundle, plistIdentity: plistIdentity)
        cache.withLock { $0[key] = entry }
        return entry.presence
    }

    /// `presence` without the cache, neither read nor written: for a bundle that
    /// is about to move or be deleted (a downloaded package before the swap).
    static func presenceUncached(_ marker: String, inMainExecutableOf bundle: URL) -> Presence {
        guard !marker.isEmpty,
              let plistIdentity = FileIdentity(
                atPath: bundle.appendingPathComponent("Contents/Info.plist").path)
        else { return .unknown }
        return read(marker, bundle: bundle, plistIdentity: plistIdentity).presence
    }

    private static func read(_ marker: String, bundle: URL, plistIdentity: FileIdentity) -> Entry {
        guard let info = NSDictionary(
                contentsOf: bundle.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let name = info["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/")
        else { return Entry(plist: plistIdentity, executablePath: nil, executable: nil, presence: .unknown) }
        let path = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(name).path
        // Non-blocking, so a FIFO there cannot hold the open; a regular file
        // reads the same either way. `fstat` on what was opened decides the rest.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return Entry(plist: plistIdentity, executablePath: path, executable: nil, presence: .unknown)
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            return Entry(plist: plistIdentity, executablePath: path, executable: nil, presence: .unknown)
        }
        let identity = FileIdentity(status)
        guard status.st_mode & S_IFMT == S_IFREG, Int64(status.st_size) <= byteLimit else {
            return Entry(plist: plistIdentity, executablePath: path, executable: identity, presence: .unknown)
        }
        var search = ExecutableBytes.MarkerSearch(marker: Data(marker.utf8), before: 0)
        var hit = false
        var total: Int64 = 0
        let readable = ExecutableBytes.forEachChunk(ofDescriptor: descriptor, overlap: search.overlap) {
            buffer, carried, _ in
            total += Int64(buffer.count - carried)
            // Grown past the limit while being read: stop, not admitted.
            guard total <= byteLimit else { return false }
            search.feed(buffer, carried: carried) { _ in
                hit = true
                return false
            }
            return !hit
        }
        // A hit stops the read early; no hit is `absent` only after the whole
        // file was read within the limit.
        let presence: Presence = !readable || total > byteLimit ? .unknown : hit ? .present : .absent
        return Entry(plist: plistIdentity, executablePath: path, executable: identity, presence: presence)
    }

    struct FileIdentity: Hashable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            size = Int64(status.st_size)
            modifiedSeconds = status.st_mtimespec.tv_sec
            modifiedNanoseconds = status.st_mtimespec.tv_nsec
        }

        init?(atPath path: String) {
            var status = stat()
            guard stat(path, &status) == 0 else { return nil }
            self.init(status)
        }
    }

    private struct Key: Hashable { let bundle: String; let marker: String }
    private struct Entry {
        let plist: FileIdentity
        let executablePath: String?
        let executable: FileIdentity?
        let presence: Presence
    }
    private static let cache = Mutex<[Key: Entry]>([:])
}

public enum OneClickGateRegistry {
    public static let gates: [OneClickGate] = AppRecipeIndex.all.flatMap(\.oneClickGates)

    private static let byBundleID: [String: [OneClickGate]] =
        Dictionary(grouping: gates, by: { $0.bundleID.lowercased() })

    /// The first gate for `app` and the offer `remote` that does not admit it,
    /// or nil when every gate does (or the app has none — every app but a few).
    /// Gates scoped to other offers (`OneClickGate.offering`) are skipped; when
    /// the id has scoped gates and none names this offer, `unnamedOffer`.
    /// `fresh` bypasses the `.executableContains` verdict cache only
    /// (`OneClickGate.admits(_:fresh:)`); other requirements answer as usual.
    public static func withholding(
        _ app: InstalledApp, offering remote: RemoteVersion?, fresh: Bool = false
    ) -> OneClickGate? {
        guard let id = app.recipeBundleID?.lowercased(), let candidates = byBundleID[id] else { return nil }
        let identity = offerIdentity(remote)
        let scoped = candidates.filter { $0.offering != nil }
        if !scoped.isEmpty, !scoped.contains(where: { $0.applies(toOffer: identity) }) {
            return .unnamedOffer(bundleID: candidates[0].bundleID)
        }
        return candidates.first { $0.applies(toOffer: identity) && !$0.admits(app, fresh: fresh) }
    }

    /// `"<source>:<package>"` for an offer: the Homebrew cask token, else the
    /// last path component of the download URL (a GitHub asset's name). Nil
    /// without an offer or a package name.
    public static func offerIdentity(_ remote: RemoteVersion?) -> String? {
        guard let remote else { return nil }
        let package = remote.sourceName == "Homebrew"
            ? remote.sourceIdentifier : remote.downloadURL?.lastPathComponent
        guard let package, !package.isEmpty else { return nil }
        return "\(remote.sourceName):\(package)"
    }

    /// A marker the downloaded package's main executable must contain
    /// (`present`) or must have been read whole without (`!present`).
    struct PackageMarker: Equatable, Sendable {
        let marker: String
        let present: Bool
    }

    /// The `.executableContains` and `.executableLacks` markers of the scoped
    /// gates that name this offer: what the downloaded package itself must and
    /// must not contain before it is swapped in, so a package that is not the
    /// edition its name says, or holds both editions' markers, cannot replace
    /// a copy. Empty for every offer of every app without scoped gates.
    ///
    /// Checked on the `.vendor` route only (`VendorInstaller`, step 3c), where
    /// we unpack the package ourselves before the swap. The Sparkle,
    /// `.installer` (pkg), Xcode, App Store and Homebrew routes never consult
    /// it: a scoped gate's `offering` must not name an offer that takes one of
    /// those routes, except the Homebrew casks listed in
    /// `OneClickGateTests.offeringsWithoutAPackageCheck` (brew fetches and
    /// swaps the package itself; the gate still checks the copy).
    static func packageMarkers(for bundleID: String?, offering remote: RemoteVersion?) -> [PackageMarker] {
        guard let id = bundleID?.lowercased(), let candidates = byBundleID[id] else { return [] }
        let identity = offerIdentity(remote)
        return candidates.compactMap { gate in
            guard gate.offering != nil, gate.applies(toOffer: identity) else { return nil }
            switch gate.requirement {
            case .executableContains(let marker): return PackageMarker(marker: marker, present: true)
            case .executableLacks(let marker): return PackageMarker(marker: marker, present: false)
            case .installedVersion, .asarEntry: return nil
            }
        }
    }

    /// Thrown by `InstallCoordinator.perform` for a copy a gate does not admit.
    public struct Withheld: LocalizedError, Sendable {
        public let appName: String
        public let reason: String
        public var errorDescription: String? {
            "\(appName): one-click update is not offered for this copy — \(reason). Nothing was changed."
        }
    }
}

/// Reads one packed entry of an Electron `app.asar` without unpacking it, cached
/// per asar path, size and modification date: `UpdatePolicy.canAutoInstall` asks
/// per row per redraw, and only a changed file is read again (a stat per call
/// otherwise). Same layout as `BundleFacts.readAsar`: an 8-byte pickle
/// `[4][header pickle size]`, then `[payload size][JSON length][JSON]`; offsets
/// count from the end of the header pickle.
///
/// Measured on GitKraken 12.6.0's real 299 MB asar (2026-10-16, debug build):
/// about 60 ms to parse the header and read the entry, about 0.25 ms cached.
enum AsarEntryReader {
    /// Entries larger than this are not read: the gates look at small markers.
    static let entryByteLimit: UInt64 = 64 * 1024

    static func packedEntry(_ path: String, inAsarAt url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let key = Key(asar: url.path, entry: path, size: size, modified: modified)
        if let hit = cache.withLock({ $0[key] }) { return hit.data }
        let data = try? read(path.split(separator: "/").map(String.init), inAsarAt: url)
        cache.withLock { $0[key] = Cached(data: data ?? nil) }
        return data ?? nil
    }

    static func read(_ components: [String], inAsarAt url: URL) throws -> Data? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let head = try handle.read(upToCount: 16), head.count == 16 else { return nil }
        let headerPickleSize = UInt64(word(head, at: 4))
        let jsonLength = UInt64(word(head, at: 12))
        guard jsonLength > 0, 16 + jsonLength <= fileSize, 8 + headerPickleSize <= fileSize,
              let json = try handle.read(upToCount: Int(jsonLength)),
              var node = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { return nil }
        for name in components {
            guard let child = (node["files"] as? [String: Any])?[name] as? [String: Any] else { return nil }
            node = child
        }
        guard node["unpacked"] as? Bool != true,
              let size = (node["size"] as? NSNumber)?.uint64Value, size <= entryByteLimit,
              let offsetText = node["offset"] as? String, let offset = UInt64(offsetText)
        else { return nil }
        let start = 8 + headerPickleSize + offset
        guard start + size <= fileSize else { return nil }
        try handle.seek(toOffset: start)
        return try handle.read(upToCount: Int(size))
    }

    private static func word(_ data: Data, at offset: Int) -> UInt32 {
        let b = data.startIndex + offset
        return UInt32(data[b]) | UInt32(data[b + 1]) << 8 | UInt32(data[b + 2]) << 16 | UInt32(data[b + 3]) << 24
    }

    private struct Key: Hashable { let asar: String; let entry: String; let size: Int64; let modified: Date }
    private struct Cached { let data: Data? }
    private static let cache = Mutex<[Key: Cached]>([:])
}
