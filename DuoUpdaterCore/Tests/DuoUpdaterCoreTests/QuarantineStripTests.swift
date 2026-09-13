import Foundation
import Testing
@testable import DuoUpdaterCore

/// `InPlaceSwap.stripQuarantine` against a real, invented bundle. The first
/// version ran `xattr -dr` with stderr to /dev/null and ignored the exit status,
/// so a strip that left the attribute on read-only and `uchg` files looked
/// exactly like one that cleared it — and on macOS 27 a quarantined launchd plist
/// is one launchd will not load.
@Suite struct QuarantineStripTests {

    private static let name = "com.apple.quarantine"
    private static let value = "0083;66e00000;ZZFixture;"

    /// Mutation: treat every `xattr` exit as success (skip the walk when the
    /// status is non-zero) — `exitStatus`/`remaining` come back as a clean strip
    /// and this goes red. Reverting to the original fire-and-forget version does
    /// the same.
    @Test func aPartialStripReportsWhatIsStillQuarantined() async throws {
        let scratch = try scratch()
        defer { cleanUp(scratch) }
        let app = try fixtureBundle(in: scratch)

        let plist = "Contents/Library/LaunchAgents/com.zzfixture.agent.plist"
        let locked = "Contents/Resources/locked"
        let sealed = "Contents/Resources/sealed"
        #expect(chmod(app.appendingPathComponent(plist).path, 0o444) == 0)
        #expect(chflags(app.appendingPathComponent(locked).path, UInt32(UF_IMMUTABLE)) == 0)
        #expect(chmod(app.appendingPathComponent(sealed).path, 0o555) == 0)

        let result = await InPlaceSwap.stripQuarantine(app)

        #expect(result.exitStatus != 0)
        #expect(result.exitStatus != nil)
        #expect(result.remaining == [plist, locked, sealed])
        // What the disk says, independently of the walk the result came from.
        #expect(isQuarantined(app.appendingPathComponent(plist)))
        #expect(isQuarantined(app.appendingPathComponent(locked)))
        #expect(isQuarantined(app.appendingPathComponent(sealed)))
        // Inside a read-only directory is not the same as read-only: this one clears.
        #expect(!isQuarantined(app.appendingPathComponent(sealed + "/inner")))
        #expect(!isQuarantined(app))
        #expect(!isQuarantined(app.appendingPathComponent("Contents/MacOS/ZZFixture")))

        let line = try #require(
            InPlaceSwap.quarantineStripLogLine(result, app: app.lastPathComponent))
        #expect(line.contains(plist))
        #expect(line.contains(locked))
        #expect(line.contains(sealed))
    }

    /// The negative control: a writable tree is fully cleared, reported as such,
    /// and logs nothing. Mutation: drop `-r` from the `xattr` arguments — the
    /// nested files stay quarantined and this goes red.
    @Test func aCompleteStripReportsNothing() async throws {
        let scratch = try scratch()
        defer { cleanUp(scratch) }
        let app = try fixtureBundle(in: scratch)

        let result = await InPlaceSwap.stripQuarantine(app)

        #expect(result == .init(exitStatus: 0, remaining: []))
        #expect(InPlaceSwap.quarantineScan(in: app) == ([], []))
        #expect(InPlaceSwap.quarantineStripLogLine(result, app: app.lastPathComponent) == nil)
    }

    /// Symlinks, in both directions. A link carrying its own xattr (what
    /// `ditto -x -k` of a quarantined zip leaves) must be cleared, not survive an
    /// exit 0; a dangling link must not fail the strip and log an error over a
    /// bundle with nothing left in it. Mutation: drop `-s` from the `xattr`
    /// arguments — the link keeps its xattr under exit 0 and the dangling link
    /// exits 1, and this goes red.
    @Test func symlinksAreStrippedNotFollowed() async throws {
        let scratch = try scratch()
        defer { cleanUp(scratch) }
        let app = try fixtureBundle(in: scratch)
        let fm = FileManager.default
        let link = "Contents/Library/LaunchAgents/current.plist"
        let dangling = "Contents/Resources/dangling"
        try fm.createSymbolicLink(
            atPath: app.appendingPathComponent(link).path,
            withDestinationPath: "com.zzfixture.agent.plist")
        let missing = scratch.appendingPathComponent("ZZFixture-missing-target").path
        #expect(!fm.fileExists(atPath: missing))
        try fm.createSymbolicLink(
            atPath: app.appendingPathComponent(dangling).path, withDestinationPath: missing)
        for path in [link, dangling] {
            let full = app.appendingPathComponent(path).path
            let rc = Self.value.withCString {
                setxattr(full, Self.name, $0, strlen($0), 0, XATTR_NOFOLLOW)
            }
            try #require(rc == 0, "could not quarantine \(path)")
        }

        let result = await InPlaceSwap.stripQuarantine(app)

        #expect(result == .init(exitStatus: 0, remaining: []))
        #expect(!isQuarantined(app.appendingPathComponent(link)))
        #expect(!isQuarantined(app.appendingPathComponent(dangling)))
        #expect(InPlaceSwap.quarantineScan(in: app) == ([], []))
    }

    /// An entry the walk cannot read is reported as unknown, never as cleared.
    /// Mutation: count every `getxattr` failure as "not quarantined" (drop the
    /// `errno != ENOATTR` branch) — `unreadable` comes back empty, the line says
    /// "nothing in it is still quarantined", and this goes red.
    @Test func unreadableEntriesAreReportedAsUnknown() async throws {
        let scratch = try scratch()
        defer { cleanUp(scratch) }
        let app = try fixtureBundle(in: scratch)
        let file = "Contents/Library/LaunchAgents/com.zzfixture.agent.plist"
        let dir = "Contents/Resources/sealed"
        #expect(chmod(app.appendingPathComponent(file).path, 0o000) == 0)
        #expect(chmod(app.appendingPathComponent(dir).path, 0o000) == 0)

        let result = await InPlaceSwap.stripQuarantine(app)

        #expect(result.exitStatus == 1)
        #expect(result.remaining == [])
        #expect(result.unreadable == [file, dir])
        let line = try #require(
            InPlaceSwap.quarantineStripLogLine(result, app: app.lastPathComponent))
        #expect(!line.contains("nothing in it is still quarantined"))
        #expect(line.contains("2 path(s) could not be read"))
        #expect(line.contains(file))
        #expect(line.contains(dir))
        // Restore modes to confirm what the log could not see: both were still
        // quarantined, and so was the file inside the directory.
        #expect(chmod(app.appendingPathComponent(dir).path, 0o755) == 0)
        #expect(chmod(app.appendingPathComponent(file).path, 0o644) == 0)
        #expect(isQuarantined(app.appendingPathComponent(file)))
        #expect(isQuarantined(app.appendingPathComponent(dir)))
        #expect(isQuarantined(app.appendingPathComponent(dir + "/inner")))
    }

    /// The line names the bundle root legibly and caps a long list rather than
    /// logging tens of thousands of paths.
    @Test func theLogLineCapsALongList() throws {
        let remaining = [""] + (1...30).map { "Contents/Resources/f\($0)" }
        let line = try #require(InPlaceSwap.quarantineStripLogLine(
            .init(exitStatus: 1, remaining: remaining), app: "ZZFixture.app"))
        #expect(line.contains("31 path(s)"))
        #expect(line.contains(": ., Contents/Resources/f1,"))
        #expect(line.contains("(+11 more)"))
        #expect(line.contains("f19"))
        #expect(!line.contains("f20"))

        let notLaunched = try #require(InPlaceSwap.quarantineStripLogLine(
            .init(exitStatus: nil, remaining: ["Contents"]), app: "ZZFixture.app"))
        #expect(notLaunched.contains("could not be launched"))
    }

    // MARK: - Helpers

    /// A quarantined `ZZFixture-Quarantine.app` with a nested executable, an
    /// embedded LaunchAgent plist and a few resources — every entry quarantined, the
    /// way extracting a quarantined archive leaves it.
    private func fixtureBundle(in scratch: URL) throws -> URL {
        let fm = FileManager.default
        let app = scratch.appendingPathComponent("ZZFixture-Quarantine.app")
        #expect(!fm.fileExists(atPath: app.path))
        for dir in [
            "Contents/MacOS", "Contents/Library/LaunchAgents", "Contents/Resources/sealed",
        ] {
            try fm.createDirectory(
                at: app.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for file in [
            "Contents/MacOS/ZZFixture",
            "Contents/Library/LaunchAgents/com.zzfixture.agent.plist",
            "Contents/Resources/locked",
            "Contents/Resources/sealed/inner",
        ] {
            try Data(file.utf8).write(to: app.appendingPathComponent(file))
        }
        var paths = [app.path]
        let walker = fm.enumerator(atPath: app.path)
        while let rel = walker?.nextObject() as? String { paths.append(app.path + "/" + rel) }
        for path in paths {
            let rc = Self.value.withCString {
                setxattr(path, Self.name, $0, strlen($0), 0, XATTR_NOFOLLOW)
            }
            try #require(rc == 0, "could not quarantine \(path)")
        }
        try #require(InPlaceSwap.quarantineScan(in: app).quarantined.count == paths.count)
        return app
    }

    private func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, Self.name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoQuarantineStripTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `uchg`, 0444 and 0555 would otherwise make the scratch directory undeletable.
    private func cleanUp(_ scratch: URL) {
        let walker = FileManager.default.enumerator(atPath: scratch.path)
        while let rel = walker?.nextObject() as? String {
            let path = scratch.path + "/" + rel
            _ = chflags(path, 0)
            _ = chmod(path, 0o755)
        }
        try? FileManager.default.removeItem(at: scratch)
    }
}
