import Testing
import Foundation
@testable import DuoUpdaterCore

struct PackageInstallerTests {
    @Test func parsesDeveloperIDInstallerTeamIdentifier() {
        let output = """
        Package "Example.pkg":
           Status: signed by a certificate trusted by Mac OS X
           Certificate Chain:
            1. Developer ID Installer: Example Corp (ABCDE12345)
            2. Developer ID Certification Authority
            3. Apple Root CA
        """

        #expect(PackageInstaller.packageTeamIdentifier(fromPkgutilOutput: output) == "ABCDE12345")
    }

    @Test func ignoresNonInstallerCertificates() {
        let output = """
        Package "Example.pkg":
           Status: signed by a certificate trusted by Mac OS X
           Certificate Chain:
            1. Developer ID Application: Example Corp (ABCDE12345)
            2. Developer ID Certification Authority
            3. Apple Root CA
        """

        #expect(PackageInstaller.packageTeamIdentifier(fromPkgutilOutput: output) == nil)
    }

    @Test func acceptsFlatAndBundlePackagesButRejectsSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pkg-entry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let flat = root.appendingPathComponent("Flat.pkg")
        try Data("flat".utf8).write(to: flat)

        let bundle = root.appendingPathComponent("Bundle.pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let symlink = root.appendingPathComponent("Link.pkg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: flat)

        let text = root.appendingPathComponent("Readme.txt")
        try Data("not a package".utf8).write(to: text)

        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        #expect(PackageInstaller.isPackageEntry(flat, insideResolvedPath: base))
        #expect(PackageInstaller.isPackageEntry(bundle, insideResolvedPath: base))
        #expect(!PackageInstaller.isPackageEntry(symlink, insideResolvedPath: base))
        #expect(!PackageInstaller.isPackageEntry(text, insideResolvedPath: base))
    }

    @Test func packageScratchDirectoriesAreUniquePerInstall() {
        let app = URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true)
        let first = PackageInstaller.workDirectory(forInstalledApp: app)
        let second = PackageInstaller.workDirectory(forInstalledApp: app)

        #expect(first != second)
        #expect(first.lastPathComponent.hasPrefix("DuoUpdater-pkg-Example-App-"))
        #expect(second.lastPathComponent.hasPrefix("DuoUpdater-pkg-Example-App-"))
    }

    @Test func multiPackageImagesRequireAUniqueProductMatch() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("pkg-choice-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func package(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: url)
            return url
        }

        let product = try package("Foo.pkg")
        _ = try package("FooHelper.pkg")
        _ = try package("Bar.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo")?.lastPathComponent
                    == product.lastPathComponent)

        try fm.removeItem(at: product)
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo") == nil,
                "a helper package must not win by substring")

        let versioned = try package("Foo-2.0.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo")?.lastPathComponent
                    == versioned.lastPathComponent)

        _ = try package("Foo-v3.pkg")
        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Foo") == nil,
                "two plausible product packages are ambiguous")
    }

    @Test func aSinglePackageNeedsNoFilenameConvention() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("pkg-single-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let only = root.appendingPathComponent("Installer.pkg")
        try Data("fixture".utf8).write(to: only)

        #expect(PackageInstaller.preferredPackage(in: root, preferring: "Different App")?.lastPathComponent
                    == only.lastPathComponent)
    }

    /// The hand-over retires the *previous* Installer window for this app, so a
    /// package that fails the Developer-ID/Team-ID gate must not cost the user the
    /// window they already have open — nothing is closed and nothing is opened.
    @Test func aPackageThatFailsTheGateNeitherOpensNorRetiresAnything() async throws {
        let fm = FileManager.default
        let dir = PackageInstaller.workDirectory(forInstalledApp:
            URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        // Unsigned, so `pkgutil --check-signature` rejects it whatever else is true.
        let pkg = dir.appendingPathComponent("Example.pkg")
        try Data("not really a package".utf8).write(to: pkg)

        let opened = Recorder()
        let installer = PackageInstaller(opener: { await opened.record($0) })
        await #expect(throws: (any Error).self) {
            try await installer.reopen(
                package: pkg,
                installedApp: URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true))
        }
        #expect(await opened.urls.isEmpty)
    }

    private actor Recorder {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    @Test func discardsOnlyOurOwnScratchDirectories() throws {
        let fm = FileManager.default
        let app = URL(fileURLWithPath: "/Applications/Example App.app", isDirectory: true)

        let ours = PackageInstaller.workDirectory(forInstalledApp: app)
        try fm.createDirectory(at: ours, withIntermediateDirectories: true)
        let pkg = ours.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: pkg)
        #expect(PackageInstaller.discardWorkDirectory(containing: pkg))
        #expect(!fm.fileExists(atPath: ours.path))

        // Wrong name: someone else's temp directory is never removed.
        let foreign = fm.temporaryDirectory
            .appendingPathComponent("Other-pkg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: foreign, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: foreign) }
        let foreignPkg = foreign.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: foreignPkg)
        #expect(!PackageInstaller.discardWorkDirectory(containing: foreignPkg))
        #expect(fm.fileExists(atPath: foreignPkg.path))

        // Right name, wrong place: a persisted path pointing outside the temp
        // directory must not turn into a recursive delete there.
        let outside = fm.temporaryDirectory
            .appendingPathComponent("elsewhere-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("DuoUpdater-pkg-Example-App-x", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside.deletingLastPathComponent()) }
        let outsidePkg = outside.appendingPathComponent("Example.pkg")
        try Data("pkg".utf8).write(to: outsidePkg)
        #expect(!PackageInstaller.discardWorkDirectory(containing: outsidePkg))
        #expect(fm.fileExists(atPath: outsidePkg.path))
    }
}
