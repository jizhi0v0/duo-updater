import Testing
import Foundation
@testable import DuoUpdaterCore

/// `HomebrewInstaller.upgrade` after brew exits 0: an app brew left as it was is
/// a failure (`BrewError.unchanged`), an app brew replaced is not. Each case runs
/// the real `upgrade` against a stand-in `brew` script and a fixture bundle.
///
/// The no-op case is the Hoppscotch run of 2026-10-22: Caskroom at
/// `hoppscotch-selfhost` 26.9.0-0, the vendor's 26.8.2 on disk, and brew
/// printing its "already installed" warning and exiting 0.
@Suite struct HomebrewUnchangedBundleTests {

    private struct Fixture {
        let root: URL
        let app: URL
        let brew: URL

        init(brewScript: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("brew-unchanged-\(UUID().uuidString)")
            app = root.appendingPathComponent("Zzfixture.app")
            brew = root.appendingPathComponent("brew")
            let macOS = app.appendingPathComponent("Contents/MacOS")
            try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
            try Self.writeInfo(version: "26.8.2", build: "26.8.2", to: app)
            try Data("old binary".utf8).write(to: macOS.appendingPathComponent("Zzfixture"))
            try Data(("#!/bin/sh\n" + brewScript).utf8).write(to: brew)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        }

        static func writeInfo(version: String, build: String, to app: URL) throws {
            let info: [String: Any] = [
                "CFBundleExecutable": "Zzfixture",
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        }

        func upgrade() async throws {
            try await HomebrewInstaller.$brewPathOverride.withValue(brew.path) {
                try await HomebrewInstaller().upgrade(caskToken: "zzfixture-cask", app: app) { _ in }
            }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func exitZeroWithTheBundleUntouchedThrowsUnchanged() async throws {
        let fixture = try Fixture(brewScript: """
            echo "Warning: Not upgrading zzfixture-cask, the latest version is already installed" >&2
            exit 0
            """)
        defer { fixture.remove() }
        await #expect {
            try await fixture.upgrade()
        } throws: { error in
            guard case HomebrewInstaller.BrewError.unchanged(let token, let onDisk, let caskroom) = error
            else { return false }
            // No Caskroom entry for a fixture token, on any machine.
            return token == "zzfixture-cask"
                && onDisk == VersionSide(marketing: "26.8.2", build: "26.8.2")
                && caskroom == nil
        }
    }

    @Test func aNewVersionOnDiskIsNotUnchanged() async throws {
        let fixture = try Fixture(brewScript: "")
        defer { fixture.remove() }
        // The script is written after the fixture exists, so it can name it.
        let script = """
            #!/bin/sh
            /usr/bin/plutil -replace CFBundleShortVersionString -string 26.9.0 '\(fixture.app.path)/Contents/Info.plist'
            /usr/bin/plutil -replace CFBundleVersion -string 26.9.0 '\(fixture.app.path)/Contents/Info.plist'
            exit 0
            """
        try Data(script.utf8).write(to: fixture.brew)
        try await fixture.upgrade()
    }

    /// A cask revision the bundle never carries (#1562): brew replaces the app,
    /// and the version pair reads exactly as before.
    @Test func aReplacedExecutableUnderTheSameVersionIsNotUnchanged() async throws {
        let fixture = try Fixture(brewScript: "")
        defer { fixture.remove() }
        let script = """
            #!/bin/sh
            printf 'rebuilt binary, longer' > '\(fixture.app.path)/Contents/MacOS/Zzfixture'
            exit 0
            """
        try Data(script.utf8).write(to: fixture.brew)
        try await fixture.upgrade()
    }

    /// A cask renamed in its new version leaves nothing at the old path; that
    /// is brew moving the app, not leaving it.
    @Test func aBundleGoneFromTheOldPathIsNotUnchanged() async throws {
        let fixture = try Fixture(brewScript: "")
        defer { fixture.remove() }
        try Data("#!/bin/sh\n/bin/rm -rf '\(fixture.app.path)'\nexit 0\n".utf8).write(to: fixture.brew)
        try await fixture.upgrade()
    }

    @Test func theReasonNamesBothVersions() {
        let error = HomebrewInstaller.BrewError.unchanged(
            caskToken: "hoppscotch-selfhost",
            onDisk: VersionSide(marketing: "26.8.2", build: "26.8.2"),
            caskroomVersion: "26.9.0-0")
        #expect(error.errorDescription
            == "brew considers hoppscotch-selfhost current (Caskroom records 26.9.0-0)"
            + " while the app on disk is 26.8.2 — brew did not replace it")
    }
}
