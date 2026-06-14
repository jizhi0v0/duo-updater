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
}
