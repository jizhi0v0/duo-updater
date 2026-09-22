import Testing
import Foundation
@testable import DuoUpdaterCore

/// Settings → Xcode's Install: a new copy beside the others, never over one.
///
/// Nothing here expands a real xip or touches `/Applications`: the destination
/// is a scratch folder, and the archive is a text file `pkgutil` refuses. The
/// bundle gates run against apps every Mac that builds this project has — a
/// system app, and an app nested inside the active Xcode.
@Suite struct XcodeSideBySideInstallerTests {

    @Test(arguments: [
        ("26.6", "Xcode-26.6.app"),
        ("27.1 beta 1", "Xcode-27.1-beta-1.app"),
        ("27.0 RC 1", "Xcode-27.0-RC-1.app"),
        ("27.1 beta", "Xcode-27.1-beta.app"),
        // The list shows the build; the name leaves it out (seen live as
        // "Xcode-26.6-_17F113_.app", 2026-09-23).
        ("26.6 (17F113)", "Xcode-26.6.app"),
        ("27.1 beta 1 (27A9269)", "Xcode-27.1-beta-1.app"),
        // Whatever the list says, the name stays one path component.
        ("27/../x", "Xcode-27_.._x.app"),
    ])
    func theBundleNameCarriesTheVersion(version: String, name: String) {
        #expect(XcodeSideBySideInstaller.bundleName(forVersion: version) == name)
    }

    /// A taken name stops the install before the archive is even looked at: the
    /// archive here does not exist, so any later step would fail differently.
    @Test func aTakenNameIsRefusedFirst() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let taken = root.appendingPathComponent("Xcode-26.6.app")
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        let moved = Flag()
        do {
            _ = try await XcodeSideBySideInstaller.install(
                archive: root.appendingPathComponent("missing.xip"), workDir: root,
                into: root, name: "Xcode-26.6.app",
                willMove: { _ in moved.set() }, onStage: { _ in })
            Issue.record("expected a refusal")
        } catch let error as XcodeSideBySideInstaller.InstallError {
            #expect(error == .destinationExists(name: "Xcode-26.6.app"))
        }
        #expect(!moved.isSet)
    }

    /// A dangling symlink at the name counts as taken — `fileExists` would say
    /// it is free, and the move would then fail or follow it.
    @Test func aDanglingSymlinkIsATakenName() throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("Xcode-26.6.app")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: root.appendingPathComponent("nowhere"))
        #expect(throws: XcodeSideBySideInstaller.InstallError.destinationExists(name: "Xcode-26.6.app")) {
            try XcodeSideBySideInstaller.checkFree(link)
        }
        #expect(throws: Never.self) {
            try XcodeSideBySideInstaller.checkFree(root.appendingPathComponent("Xcode-27.app"))
        }
    }

    /// End to end up to the first archive gate: an archive that is not
    /// Apple-signed is refused, nothing is expanded, and `willMove` — where the
    /// app records the Ignore — never runs.
    @Test func anArchiveThatIsNotAppleSignedMovesNothing() async throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let work = root.appendingPathComponent("work")
        let apps = root.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let archive = work.appendingPathComponent("Xcode.xip")
        try Data("not a xip".utf8).write(to: archive)
        let moved = Flag()
        do {
            _ = try await XcodeSideBySideInstaller.install(
                archive: archive, workDir: work, into: apps, name: "Xcode-26.6.app",
                willMove: { _ in moved.set() }, onStage: { _ in })
            Issue.record("expected a refusal")
        } catch XcodeInstaller.InstallError.packageSignatureRejected {
        }
        #expect(!moved.isSet)
        #expect(!FileManager.default.fileExists(atPath: work.appendingPathComponent("expanded").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: apps.path).isEmpty)
    }

    /// Apple's own system app has a valid signature but no Team ID.
    @Test func anAppWithoutApplesTeamIsNotXcode() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        #expect(throws: XcodeSideBySideInstaller.InstallError.self) {
            try XcodeSideBySideInstaller.verifyIsXcode(calculator, host: .current, osVersion: HostOS.numericVersion())
        }
        do {
            try XcodeSideBySideInstaller.verifyIsXcode(calculator, host: .current, osVersion: HostOS.numericVersion())
        } catch let XcodeSideBySideInstaller.InstallError.notXcode(why) {
            #expect(why.contains("team"))
        } catch {
            Issue.record("expected notXcode, got \(error)")
        }
    }

    /// Apple's Team ID alone is not enough: FileMerge, inside every Xcode, is
    /// signed by the same team under its own identifier.
    @Test func applesTeamWithAnotherIdentifierIsNotXcode() async throws {
        let select = try await ChildProcess.run("/usr/bin/xcode-select", ["-p"], onCancel: .terminateChild)
        let developer = String(decoding: select.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileMerge = URL(fileURLWithPath: developer)
            .deletingLastPathComponent()   // Contents
            .appendingPathComponent("Applications/FileMerge.app")
        try #require(FileManager.default.fileExists(atPath: fileMerge.path),
                     "needs the active developer directory to be an Xcode, not the Command Line Tools")
        #expect(try SignatureVerifier.teamIdentifier(at: fileMerge) == XcodeSideBySideInstaller.appleTeamID)
        do {
            try XcodeSideBySideInstaller.verifyIsXcode(fileMerge, host: .current, osVersion: HostOS.numericVersion())
            Issue.record("expected a refusal")
        } catch let XcodeSideBySideInstaller.InstallError.notXcode(why) {
            #expect(why.contains("com.apple.FileMerge"))
        }
    }

    /// macOS 27's own entry, as read from its Exceptions.plist on 2026-09-23.
    static var macOS27Exceptions: [String: Any] { [
        "LaunchOverrides": [
            "com.apple.dt.Xcode": [
                ["HardDisabled": true, "HighVersion": "9999.99.98", "LowVersion": "2"],
                ["HardDisabled": true, "HighVersion": "24999", "LowVersion": "9999.99.100"],
            ],
            "com.apple.DVDPlayer": [["HardDisabled": true, "HighVersion": "5.5"]],
        ],
    ] }

    @Test(arguments: [
        ("24959", true),          // Xcode 26.6 — would not open on macOS 27
        ("24999", true),          // the bound itself
        ("25183.107.5", false),   // Xcode 27.0
        ("25400.27.8", false),    // Xcode 27.2 beta
        ("9999.99.99", false),    // the gap between the two entries
        ("1", false),             // below the first entry's LowVersion
    ])
    func macOSBlocksTheXcodeVersionsItsListNames(version: String, blocked: Bool) {
        #expect(XcodeSideBySideInstaller.isHardDisabled(
            bundleID: "com.apple.dt.Xcode", bundleVersion: version, exceptions: Self.macOS27Exceptions) == blocked)
    }

    @Test func onlyHardDisabledEntriesForThisIdentifierCount() {
        let soft: [String: Any] = ["LaunchOverrides": ["com.apple.dt.Xcode": [["HighVersion": "24999"]]]]
        #expect(!XcodeSideBySideInstaller.isHardDisabled(
            bundleID: "com.apple.dt.Xcode", bundleVersion: "24959", exceptions: soft))
        // A missing LowVersion is open at the bottom.
        #expect(XcodeSideBySideInstaller.isHardDisabled(
            bundleID: "com.apple.DVDPlayer", bundleVersion: "5.0", exceptions: Self.macOS27Exceptions))
        #expect(!XcodeSideBySideInstaller.isHardDisabled(
            bundleID: "com.apple.dt.Instruments", bundleVersion: "24959", exceptions: Self.macOS27Exceptions))
    }

    /// Read from the bundle and the list on disk, as the install does.
    @Test func aBlockedXcodeIsRefusedFromItsInfoPlist() throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let list = root.appendingPathComponent("Exceptions.plist")
        try PropertyListSerialization.data(fromPropertyList: Self.macOS27Exceptions, format: .xml, options: 0)
            .write(to: list)
        func app(_ version: String) throws -> URL {
            let app = root.appendingPathComponent("\(version).app")
            try FileManager.default.createDirectory(
                at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleVersion": version, "CFBundleShortVersionString": "v\(version)"],
                format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            return app
        }
        #expect(throws: XcodeSideBySideInstaller.InstallError.blockedByMacOS(version: "v24959")) {
            try XcodeSideBySideInstaller.verifyNotBlockedByMacOS(try app("24959"), exceptions: list)
        }
        #expect(throws: Never.self) {
            try XcodeSideBySideInstaller.verifyNotBlockedByMacOS(try app("25183.107.5"), exceptions: list)
        }
    }

    /// What the list checks to offer Download Only instead of Install.
    @Test func installedXcodesAreFoundByPublishedBuild() throws {
        let root = try Self.scratchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let apps = root.appendingPathComponent("Applications")
        let home = root.appendingPathComponent("HomeApplications")
        func bundle(_ dir: URL, _ name: String, id: String, build: String?) throws {
            let contents = dir.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(
                fromPropertyList: ["CFBundleIdentifier": id, "CFBundleVersion": "25183.107.5"],
                format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            if let build {
                try PropertyListSerialization.data(
                    fromPropertyList: ["ProductBuildVersion": build], format: .xml, options: 0)
                    .write(to: contents.appendingPathComponent("version.plist"))
            }
        }
        try bundle(apps, "Xcode", id: "com.apple.dt.Xcode", build: "27A266a")
        try bundle(apps, "Xcode-beta", id: "com.apple.dt.Xcode", build: "27B5019j")
        try bundle(apps, "ZZ-copy", id: "com.apple.dt.Xcode", build: "27A266a")
        try bundle(apps, "FileMerge", id: "com.apple.FileMerge", build: "999A1")
        try bundle(apps, "Xcode-nobuild", id: "com.apple.dt.Xcode", build: nil)
        try bundle(home, "Xcode-26.6", id: "com.apple.dt.Xcode", build: "17F113")

        let found = XcodeSideBySideInstaller.installedBuilds(in: [apps, home, root.appendingPathComponent("missing")])
        #expect(found.mapValues(\.lastPathComponent) == [
            "27A266a": "Xcode.app",
            "27B5019j": "Xcode-beta.app",
            "17F113": "Xcode-26.6.app",
        ])
    }

    static func scratchRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-xcode-side-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
