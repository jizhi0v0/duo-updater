import Foundation
import Synchronization

/// Which GitKraken Desktop edition a bundle is, read from the one place the two
/// public editions differ in what the vendor itself checks.
///
/// The normal edition and the On-Premise Serverless ("Standalone") edition ship
/// the same bundle id, app name, Info.plist (byte-identical `plutil` output at
/// 12.6.0) and Team `T7QVVUTZQ8`. The app's own code tells them apart with
/// `src/main/static/clientType.js` inside `Contents/Resources/app.asar`:
/// `module.exports = 'NORMAL';` vs `'STANDALONE'` (both 12.6.0 packages read
/// 2026-10-16). Our GitKraken recipe downloads the NORMAL build, so a copy that
/// is not NORMAL is not offered one-click: detection still answers (the two
/// lines share version numbers), the swap would change the edition.
///
/// Read without unpacking: the asar header is parsed for that one entry and its
/// bytes read, nothing else. Cached per asar path, size and modification date,
/// because `UpdatePolicy.canAutoInstall` asks per row per redraw.
public enum GitKrakenEdition {
    public static let bundleID = "com.axosoft.gitkraken"
    static let clientTypePath = ["src", "main", "static", "clientType.js"]

    /// True when `bundleURL` is GitKraken and not provably the NORMAL edition.
    /// An asar that cannot be read, or a `clientType.js` that is gone or names no
    /// edition, withholds one-click too: the failure costs one manual update, a
    /// wrong guess costs the user their edition.
    public static func withholdsOneClick(bundleID: String?, bundleURL: URL) -> Bool {
        guard bundleID?.lowercased() == Self.bundleID else { return false }
        return clientType(bundleAt: bundleURL) != "NORMAL"
    }

    /// The edition string `clientType.js` exports, or nil.
    public static func clientType(bundleAt bundleURL: URL) -> String? {
        let asar = bundleURL.appendingPathComponent("Contents/Resources/app.asar")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: asar.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let key = CacheKey(path: asar.path, size: size, modified: modified)
        if let hit = cache.withLock({ $0[key] }) { return hit.value }
        let value = (try? readEntry(Self.clientTypePath, inAsarAt: asar)).flatMap(parseExport)
        cache.withLock { $0[key] = Cached(value: value) }
        return value
    }

    /// `module.exports = 'X';` → `X`. The file also carries a comment line.
    static func parseExport(_ data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"module\.exports\s*=\s*['"]([A-Z_]+)['"]"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    /// One packed (not `unpacked`) file's bytes from an asar. Same layout as
    /// `BundleFacts.readAsar`: an 8-byte pickle `[4][header pickle size]`, then
    /// `[payload size][JSON length][JSON]`; offsets count from the end of the
    /// header pickle.
    static func readEntry(_ components: [String], inAsarAt url: URL) throws -> Data? {
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
              let size = (node["size"] as? NSNumber)?.uint64Value, size <= 64 * 1024,
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

    private struct CacheKey: Hashable { let path: String; let size: Int64; let modified: Date }
    private struct Cached { let value: String? }
    private static let cache = Mutex<[CacheKey: Cached]>([:])
}
