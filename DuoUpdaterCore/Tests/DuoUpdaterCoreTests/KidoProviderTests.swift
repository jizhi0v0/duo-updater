import Foundation
import Testing
@testable import DuoUpdaterCore

struct KidoProviderTests {
    @Test func scansTheScriptLayoutAndOnlyReadsItsBinary() async throws {
        let fm = FileManager.default
        let temporary = try #require(CLIToolProcesses.realpath(fm.temporaryDirectory.path))
        let home = URL(fileURLWithPath: temporary, isDirectory: true).appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let prefix = home.appendingPathComponent(".local")
        let binary = prefix.appendingPathComponent("bin/kido")
        let helpers = prefix.appendingPathComponent("libexec/kido")
        let agent = helpers.appendingPathComponent("kido-agent")
        let vmm = helpers.appendingPathComponent("kido-vmm")
        for executable in [binary, agent, vmm] {
            try fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 91\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        let provider = KidoProvider(home: home, customPrefix: prefix.path) { url in
            #expect(url.path == binary.path)
            return .known("0.3.0")
        }
        #expect(await provider.scan().map(\.path) == [binary.path])

        try fm.removeItem(at: vmm)
        #expect(await provider.scan().isEmpty)

        try fm.copyItem(at: agent, to: vmm)
        let keg = home.appendingPathComponent("Cellar/kido/0.3.0")
        try fm.createDirectory(at: keg.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: prefix, to: keg)
        try fm.createSymbolicLink(at: prefix, withDestinationURL: keg)
        #expect(await provider.scan().isEmpty)
    }

    @Test func readsGoReleaseVersionsButOnlyRecognizesTheFirstPseudoVersionByDigest() {
        let module = KidoScanner.module
        func info(_ version: String, path: String = KidoScanner.module + "/cmd/kido") -> GoBuildInfo {
            GoBuildInfo.parse(goVersion: "go1.27.4", modinfo: "path\t\(path)\nmod\t\(module)\t\(version)\t\n")
        }

        #expect(KidoScanner.version(info("v0.3.0"), digest: { nil }) == .known("0.3.0"))
        #expect(KidoScanner.version(info("v0.3.0", path: module + "/cmd/other"), digest: { nil }) == .foreign)
        #expect(KidoScanner.version(info("v0.3.0-dev.1"), digest: { nil }) == .unreadable)
        #expect(KidoScanner.version(info("v" + KidoScanner.firstModuleVersion),
                                    digest: { KidoScanner.firstExecutableDigest }) == .known("0.1.0"))
        #expect(KidoScanner.version(info("v" + KidoScanner.firstModuleVersion),
                                    digest: { "other" }) == .unreadable)
    }

    @Test func detectsTheStableMacReleaseAndPresentsOnlyTheVendorCommand() async throws {
        let stable = """
            {"tag_name":"v0.4.0","draft":false,"prerelease":false,
             "assets":[{"name":"kido-0.4.0-darwin-arm64.tar.gz"},{"name":"kido-0.4.0-linux-arm64.tar.gz"},
                       {"name":"SHA256SUMS"},{"name":"SHA256SUMS.sig"}]}
            """
        let release = KidoRelease { url, purpose, force, _ in
            #expect(url == KidoRelease.latestURL)
            #expect(purpose == .versionCheck)
            #expect(!force)
            return Data(stable.utf8)
        }
        let latest = try await release.latest()
        let install = KidoInstall(path: "/fixture/it's a prefix/bin/kido", version: "0.3.0")
        let status = KidoProvider.status(install, latest: .success(latest))
        #expect(status.state == .updateAvailable)
        #expect(status.latestVersion == "0.4.0")
        #expect(status.oneClick == nil)
        #expect(status.withheld == .ownUpgrade)
        #expect(status.commandToCopy?.display == "'/fixture/it'\\''s a prefix/bin/kido' upgrade")
        #expect(await KidoProvider().update(status, progress: { _ in }) == .notOffered)

        #expect(KidoProvider.status(install, latest: .success(NpmVersion("0.3.0")!)).state == .upToDate)
        #expect(KidoProvider.status(install, latest: .success(NpmVersion("0.2.0")!)).state == .ahead)
        #expect(KidoProvider.status(install, latest: .failure(CLIToolReleaseNotesError.rateLimited)).withheld == .rateLimited)

        for invalid in [stable.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true"),
                        stable.replacingOccurrences(of: "-darwin-arm64.tar.gz", with: "-darwin-x64.tar.gz"),
                        stable.replacingOccurrences(of: "\"SHA256SUMS.sig\"", with: "\"notes.txt\"")] {
            let other = KidoRelease { _, _, _, _ in Data(invalid.utf8) }
            await #expect(throws: KidoRelease.Failure.invalidRelease) { try await other.latest() }
        }
    }

    @Test func keepsStableReleaseNotesAndTheirSections() async throws {
        // Trimmed real v0.4.0 release content, followed by a distinct prerelease.
        let data = Data(#"""
            [{"tag_name":"v0.4.0","published_at":"2026-11-28T05:08:08Z","draft":false,"prerelease":false,
              "body":"- **Metal GPU compute passthrough (\u0060--gpu\u0060)**:\n  - **macOS 27+ hosts**: zero-copy \u0060virtio-metal\u0060 passthrough to host \u0060Metal.framework\u0060 over a shared PCIe BAR4 memory window."},
             {"tag_name":"v0.5.0-rc.1","published_at":"2026-11-29T00:00:00Z","draft":false,"prerelease":true,
              "body":"## Added\n- Preview feature"}]
            """#.utf8)
        let release = KidoRelease { url, purpose, force, _ in
            #expect(url == KidoRelease.notesURL)
            #expect(purpose == .changelog)
            #expect(force)
            return data
        }
        let changelog = try await release.notes(force: true)
        #expect(changelog.entries.map(\.version) == ["0.4.0"])
        let notes = try #require(changelog.entries.first)
        #expect(notes.date == "2026-11-28")
        #expect(notes.items.joined(separator: " ").contains("Metal GPU compute passthrough"))
    }
}
