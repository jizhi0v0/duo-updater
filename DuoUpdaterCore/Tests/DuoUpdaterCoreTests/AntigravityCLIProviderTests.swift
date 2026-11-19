import Foundation
import Testing
@testable import DuoUpdaterCore

struct AntigravityCLIProviderTests {
    @Test func onlyTheFlatSignedInstallIsRunForItsVersion() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = home.resolvingSymlinksInPath().appendingPathComponent(".local/bin/agy")
        let files = FileManager.default
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: home) }

        let unsigned = AntigravityCLIProvider(home: home, signature: { _ in .adHoc }, readVersion: { _, _ in
            Issue.record("Ran an untrusted executable")
            return "1.5.11"
        })
        try files.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
        #expect(await unsigned.installed() == nil)
        try files.removeItem(at: file)
        try Data("#!/bin/sh\necho 1.5.11\n".utf8).write(to: file)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        #expect(await unsigned.installed()?.signature == .adHoc)
        #expect(await unsigned.installed()?.version == nil)

        let signed = AntigravityCLIProvider(home: home, signature: { _ in .vendor })
        #expect(await signed.installed()?.version == "1.5.11")
    }

    @Test func comparesAgainstTheStableManifestAndHonorsOptOut() async throws {
        let provider = AntigravityCLIProvider()
        let path = "/Users/ann/.local/bin/agy"
        let install = AntigravityCLIInstall(path: path, version: "1.5.11", signature: .vendor)
        let manifest = Data(#"{"version":"1.5.12"}"#.utf8)
        let latest = try JSONDecoder().decode(AntigravityCLIProvider.Manifest.self, from: manifest).version
        let update = await provider.status(of: install, autoUpdateOff: false) { latest }
        #expect(update.state == .updateAvailable)
        #expect(update.oneClick?.executable == path)
        #expect(update.oneClick?.arguments == ["update"])

        let disabled = await provider.status(of: install, autoUpdateOff: true) { latest }
        #expect(disabled.state == .updateAvailable)
        #expect(disabled.oneClick == nil)
        #expect(disabled.commandToCopy == install.command)

        let ahead = await provider.status(of: install, autoUpdateOff: false) { NpmVersion(major: 1, minor: 5, patch: 10) }
        #expect(ahead.state == .ahead)
        #expect(ahead.oneClick == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AntigravityCLIProvider.Manifest.self, from: Data(#"{"version":"1.6.0-beta.1"}"#.utf8))
        }
    }

    @Test func completionRequiresAVerifiedNewerVersion() throws {
        let before = try #require(NpmVersion("1.5.11"))
        #expect(AntigravityCLIProvider.updated(before: before, after: "1.5.12", output: "") == .updated(version: "1.5.12"))
        for after in [nil, "1.5.11", "1.5.10"] {
            guard case .failed = AntigravityCLIProvider.updated(before: before, after: after, output: "") else {
                Issue.record("Accepted \(after ?? "an unreadable version") as a newer installation")
                continue
            }
        }
    }
}
