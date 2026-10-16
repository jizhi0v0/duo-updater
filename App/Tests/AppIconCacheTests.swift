import AppKit
import Testing

/// The icon cache re-reads a path once the bundle there has been replaced by
/// something other than the GUI's own install (the `duo` CLI, a vendor updater, a
/// drag in Finder). Identity of the returned `NSImage` is the probe:
/// `NSWorkspace.icon(forFile:)` hands back a new image on every read, so the same
/// instance means a cache hit and a different one a re-read.
@MainActor
struct AppIconCacheTests {

    /// A minimal `.app` at a fresh temp path; returns the bundle path.
    private static func makeBundle(in dir: URL, name: String = "Probe.app", version: String) throws -> String {
        let contents = dir.appendingPathComponent(name).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "app.duo.test.iconprobe",
                                    "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return dir.appendingPathComponent(name).path
    }

    private static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIconCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// An unchanged bundle stays a cache hit. Mutation: making `icon(for:)` never
    /// return the cached entry.
    @Test func anUnchangedBundleIsServedFromTheCache() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let first = AppIconCache.icon(for: path)
        #expect(AppIconCache.icon(for: path) === first)
    }

    /// The bundle at the path is swapped for another copy, the way `duo install`
    /// does it (a new bundle renamed over the old path). Mutation: comparing only
    /// the presence of an entry, not its stamp.
    @Test func aBundleReplacedInPlaceIsReRead() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let old = AppIconCache.icon(for: path)

        let staging = dir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let fresh = try Self.makeBundle(in: staging, version: "2.0")
        _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                 withItemAt: URL(fileURLWithPath: fresh))

        let reread = AppIconCache.icon(for: path)
        #expect(reread !== old)
        #expect(AppIconCache.icon(for: path) === reread)
    }

    /// Read while the bundle was absent (mid-swap), then the copy lands. Mutation:
    /// treating a missing stamp as matching any stamp.
    @Test func anIconReadWhileTheBundleWasMissingIsReReadOnceItLands() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Probe.app").path
        let missing = AppIconCache.icon(for: path)
        _ = try Self.makeBundle(in: dir, version: "1.0")
        #expect(AppIconCache.icon(for: path) !== missing)
    }

    /// The same file rewritten in place (new mtime, same inode) also counts.
    /// Mutation: dropping `mtime` from the stamp's equality.
    @Test func anInfoPlistRewrittenInPlaceIsReRead() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = try Self.makeBundle(in: dir, version: "1.0")
        let old = AppIconCache.icon(for: path)
        let plist = URL(fileURLWithPath: path + "/Contents/Info.plist")
        let later = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: plist.path)
        #expect(AppIconCache.icon(for: path) !== old)
    }
}
