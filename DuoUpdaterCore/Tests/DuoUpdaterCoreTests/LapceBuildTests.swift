import Foundation
import Testing
@testable import DuoUpdaterCore

/// The bytes `LapceBuild` reads, as they sit in the real executables
/// (2026-10-20): the `NAME` constant runs straight into `VERSION`, with no NUL
/// between Rust string literals. Only the surrounding megabytes are left out.
private enum Layout {
    /// 2026-10-09 nightly (`nightly` tag, commit f66ffaa).
    static let nightly = "failed to allocate default calleeLapce-Nightly0.4.6+Nightly.f66ffaaurnuri not supporte"
    /// v0.4.6: the stable name, and the updater's `+Nightly.` format pieces that
    /// every build carries.
    static let stable = "initialization_options Lapce-Stable0.4.6capabilities\0no directoryLapce-macos.dmg"
        + "can't download releasehttps://api.github.com/repos/lapce/lapce/releases/latest0.4.6+Nightly.no parent"
}

struct LapceBuildTests {

    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapceBuildTests-\(UUID().uuidString)")
        try Data(("\u{1}\u{2}junk\0" + text + "\0tail").utf8).write(to: url)
        return url
    }

    @Test func readsTheNightly() throws {
        let url = try file(Layout.nightly)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LapceBuild.isNightly(contentsOf: url) == true)
    }

    @Test func stableIsNotNightlyDespiteTheFormatString() throws {
        let url = try file(Layout.stable)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(LapceBuild.isNightly(contentsOf: url) == false)
    }

    /// The marker split across two chunks is still found whole.
    @Test func findsTheMarkerAcrossAChunkBoundary() throws {
        let url = try file(Layout.nightly)
        defer { try? FileManager.default.removeItem(at: url) }
        for chunkSize in 1...16 {
            #expect(LapceBuild.isNightly(contentsOf: url, chunkSize: chunkSize) == true)
        }
    }

    @Test func unreadableFileClaimsNothing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
        #expect(LapceBuild.isNightly(contentsOf: missing) == nil)
        #expect(LapceBuild.channel(bundleAt: missing) == nil)
    }

    /// The remembered answer belongs to the executable, not to its path: a
    /// stable build copied over a nightly at the same path is read again and
    /// called stable (the cache key carries size and mtime).
    @Test func aReplacedExecutableIsReadAgain() throws {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapceBuildTests-\(UUID().uuidString)/Lapce.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "io.lapce", "CFBundleExecutable": "lapce"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let executable = contents.appendingPathComponent("MacOS/lapce")

        try Data(("\u{1}junk\0" + Layout.nightly).utf8).write(to: executable)
        #expect(LapceBuild.channel(bundleAt: app) == .nightly)

        try Data(("\u{1}junk\0" + Layout.stable).utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: executable.path)
        #expect(LapceBuild.channel(bundleAt: app) == nil)
    }

    /// The wiring, through `AppScanner.readApp(at:)` on bundles on disk: the
    /// nightly marker makes a Lapce copy `.nightly` (so the stable GitHub rule
    /// steps aside), a stable copy stays `.stable`, and the marker means nothing
    /// under any other bundle id.
    @Test func theScannerCallsTheNightlyNightly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LapceBuildTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ dir: String, id: String, executable text: String) throws -> URL {
            let app = root.appendingPathComponent("\(dir)/Lapce.app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(
                at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "CFBundleIdentifier": id, "CFBundleName": "Lapce", "CFBundlePackageType": "APPL",
                "CFBundleExecutable": "lapce", "CFBundleShortVersionString": "0.4.6", "CFBundleVersion": "1",
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            try Data(("\u{1}junk\0" + text).utf8).write(to: contents.appendingPathComponent("MacOS/lapce"))
            return app
        }
        let scanner = AppScanner(locations: [], testflight: TestFlightInventory(macRows: []))

        let nightly = try #require(scanner.readApp(
            at: try bundle("nightly", id: "io.lapce", executable: Layout.nightly)))
        #expect(nightly.releaseChannel == .nightly)
        #expect(nightly.channelIsAuthoritative)

        let stable = try #require(scanner.readApp(
            at: try bundle("stable", id: "io.lapce", executable: Layout.stable)))
        #expect(stable.releaseChannel == .stable)

        let other = try #require(scanner.readApp(
            at: try bundle("other", id: "com.example.other", executable: Layout.nightly)))
        #expect(other.releaseChannel == .stable)
    }
}
