import Foundation
import Testing
@testable import DuoUpdaterCore

struct FixStorageProviderTests {
    @Test func scansOnlyTheOfficialLinkChainWithoutRunningTheCLI() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let modules = home.appendingPathComponent(".fix-storage/node_modules")
        let package = modules.appendingPathComponent("fix-storage")
        let bin = package.appendingPathComponent("bin", isDirectory: true)
        let npmBin = modules.appendingPathComponent(".bin")
        let localBin = home.appendingPathComponent(".local/bin")
        defer { try? fm.removeItem(at: home) }
        for directory in [bin, npmBin, localBin] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let binary = bin.appendingPathComponent("fix-storage.cjs")
        // It only needs to exist and be executable. Running it could never
        // yield the version asserted below.
        try Data("#!/bin/sh\nexit 91\n".utf8).write(to: binary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let manifest = package.appendingPathComponent("package.json")
        try Data(#"{"name":"fix-storage","version":"0.1.0","bin":{"fix-storage":"bin/fix-storage.cjs"}}"#.utf8)
            .write(to: manifest)
        let npmLink = npmBin.appendingPathComponent("fix-storage")
        let launcher = localBin.appendingPathComponent("fix-storage")
        try fm.createSymbolicLink(atPath: npmLink.path, withDestinationPath: "../fix-storage/bin/fix-storage.cjs")
        try fm.createSymbolicLink(atPath: launcher.path, withDestinationPath: npmLink.path)
        let provider = FixStorageProvider(home: home)

        let sightings = await provider.scan()
        #expect(sightings.map(\.version) == ["0.1.0"])
        #expect(sightings.map(\.path) == [launcher.path])

        try fm.removeItem(at: launcher)
        try fm.createSymbolicLink(atPath: launcher.path, withDestinationPath: binary.path)
        #expect(await provider.scan().isEmpty)
    }

    @Test func offersOnlyTheManualCommandForANewerStableVersion() async throws {
        let install = FixStorageInstall(path: "/fixture/.local/bin/fix-storage", version: "0.1.0")
        let latest = try #require(NpmVersion("0.2.0"))
        let status = FixStorageProvider.status(install, latest: latest)
        #expect(status.state == .updateAvailable)
        #expect(status.oneClick == nil)
        #expect(status.commandToCopy?.arguments.suffix(2) == ["--version", "0.2.0"])
        #expect(await FixStorageProvider().update(status, progress: { _ in }) == .notOffered)
        #expect(FixStorageProvider.status(install, latest: NpmVersion("0.1.0")).state == .upToDate)
        #expect(FixStorageProvider.status(install, latest: NpmVersion("0.0.9")).state == .ahead)
        #expect(FixStorageProvider.status(install, latest: nil).state == .unknown)
    }

    @Test func acceptsOnlyTheStableVendorReleasePath() {
        let release = "https://github.com/govijr/fix-storage/releases/tag/"
        #expect(FixStorageProvider.releaseVersion(URL(string: release + "v0.1.0")!) == NpmVersion("0.1.0"))
        for ignored in [release + "v0.2.0-rc.1", release + "v0.1.0%0A",
                        "https://github.com/other/fix-storage/releases/tag/v0.1.0"] {
            #expect(FixStorageProvider.releaseVersion(URL(string: ignored)!) == nil)
        }
    }

    @Test func readsReleasedNotesAndCategoriesWithoutTheCompareLinks() throws {
        let markdown = """
        # Changelog

        ## [Unreleased]

        - Still in progress.

        ## [0.1.0] - 2026-11-14
        ### Added

        - Disk overview.
        - Folder browser.

        [Unreleased]: https://example.com/compare/v0.1.0...HEAD
        """
        let notes = try #require(FixStorageProvider.parseNotes(
            Data(markdown.utf8), source: URL(string: "https://example.com/CHANGELOG.md")!))
        #expect(notes.entries.map(\.version) == ["0.1.0"])
        let entry = try #require(notes.entries.first)
        #expect(entry.date == "2026-11-14")
        #expect(entry.items == ["Disk overview.", "Folder browser."])
        #expect(entry.content.first == .heading("Added"))
    }
}
