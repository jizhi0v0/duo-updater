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
/// A gate is a requirement on the copy on disk, never on the machine or the
/// download. Several gates for one id must all admit.
public struct OneClickGate: Sendable {
    /// Matched against `InstalledApp.recipeBundleID`, case-insensitively.
    public let bundleID: String
    public let requirement: Requirement
    /// Why a copy that fails the requirement is kept off the one-click and what
    /// to do instead, for the log, the CLI and the refusal the installer reports.
    public let reason: String

    public enum Requirement: Sendable {
        /// `CFBundleShortVersionString` matches this pattern (searched; write
        /// your own anchors). A copy without one is not admitted.
        case installedVersion(pattern: String)
        /// The file at `path` inside `Contents/Resources/app.asar` (a packed
        /// entry, read without unpacking) matches this pattern. A missing asar,
        /// entry or match is not admitted: failing closed costs one manual
        /// update, failing open could cost the user the app they chose.
        case asarEntry(path: String, pattern: String)
    }

    public init(bundleID: String, requirement: Requirement, reason: String) {
        self.bundleID = bundleID
        self.requirement = requirement
        self.reason = reason
    }

    /// Whether `app` meets the requirement.
    public func admits(_ app: InstalledApp) -> Bool {
        switch requirement {
        case .installedVersion(let pattern):
            guard let version = app.shortVersion else { return false }
            return version.range(of: pattern, options: .regularExpression) != nil
        case .asarEntry(let path, let pattern):
            let asar = app.path.appendingPathComponent("Contents/Resources/app.asar")
            guard let data = AsarEntryReader.packedEntry(path, inAsarAt: asar) else { return false }
            return String(decoding: data, as: UTF8.self)
                .range(of: pattern, options: .regularExpression) != nil
        }
    }
}

public enum OneClickGateRegistry {
    public static let gates: [OneClickGate] = AppRecipeIndex.all.flatMap(\.oneClickGates)

    private static let byBundleID: [String: [OneClickGate]] =
        Dictionary(grouping: gates, by: { $0.bundleID.lowercased() })

    /// The first gate for `app` that does not admit it, or nil when every gate
    /// does (or the app has none — every app but a few).
    public static func withholding(_ app: InstalledApp) -> OneClickGate? {
        guard let id = app.recipeBundleID?.lowercased(), let candidates = byBundleID[id] else { return nil }
        return candidates.first { !$0.admits(app) }
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
