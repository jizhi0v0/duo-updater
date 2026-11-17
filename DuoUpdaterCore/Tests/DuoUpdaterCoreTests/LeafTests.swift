import CryptoKit
import Foundation
import Testing
@testable import DuoUpdaterCore

@Suite struct LeafTests {
    final class Box: @unchecked Sendable {
        let root: URL
        let digests: LeafPublishedDigests
        let lock = NSLock()
        var builds: [String: Data] = [:]
        var extracts = 0
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var file: URL { bin.appendingPathComponent("leaf") }
        var ran: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("ran").path) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("leaf-tests-\(UUID().uuidString)")
            digests = LeafPublishedDigests(fileURL: root.appendingPathComponent("digests.json"))
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        var scanner: LeafScanner {
            LeafScanner(home: home, directories: [bin], quarantine: { _ in false }, target: { _ in "aarch64-apple-darwin" })
        }

        func install(update: Bool = true, publishOld: Bool = true, publishNew: Bool = true) throws {
            let next = Data("#!/bin/sh\n# leaf 0.16.1\nexit 0\n".utf8)
            let staged = root.appendingPathComponent("next")
            try next.write(to: staged)
            let body = """
            #!/bin/sh
            # leaf 0.16.0
            [ "$#" = 1 ] && [ "$1" = upgrade ] || exit 23
            /usr/bin/touch '\(root.path)/ran'
            /usr/bin/env > '\(root.path)/env'
            \(update ? "/bin/cp '\(staged.path)' '\(bin.path)/.next' && /bin/chmod 755 '\(bin.path)/.next' && /bin/mv '\(bin.path)/.next' '\(file.path)'" : "true")
            """
            let old = Data(body.utf8)
            try old.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            lock.withLock {
                if publishOld { builds["0.16.0"] = old }
                if publishNew { builds["0.16.1"] = next }
            }
        }

        func verifier(tamper: Bool = false) -> LeafVerifier {
            LeafVerifier(download: { url in
                let version = String(url.deletingLastPathComponent().lastPathComponent.dropFirst())
                guard self.lock.withLock({ self.builds[version] }) != nil else { throw LeafRelease.Failure.http(404) }
                let bytes = Data(version.utf8)
                if url.pathExtension == "sha256" {
                    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                    return Data("\(digest)  leaf-aarch64-apple-darwin.tar.gz\n".utf8)
                }
                return tamper ? Data("changed".utf8) : bytes
            }, extract: { archive, directory in
                let version = String(decoding: try Data(contentsOf: archive), as: UTF8.self)
                let bytes = self.lock.withLock { self.extracts += 1; return self.builds[version] }
                try #require(bytes).write(to: directory.appendingPathComponent("leaf"))
            }, digests: digests)
        }

        func check(latest: String = "0.16.1") -> LeafCheck {
            LeafCheck(release: LeafRelease(fetch: { _ in
                (200, URL(string: "https://github.com/DeepanshuMishraa/leaf/releases/tag/v\(latest)"))
            }), verifier: verifier())
        }

        func status() async throws -> CLIToolStatus {
            await check().status(of: try #require(scanner.scan().first), busy: false, published: .success("0.16.1"))
        }

        func updater(tamper: Bool = false, busy: Bool = false, latest: String = "0.16.1") -> LeafUpdater {
            LeafUpdater(scanner: scanner, check: check(latest: latest), verifier: verifier(tamper: tamper),
                        busy: { busy }, environment: { ["PATH": "/untrusted/bin"] })
        }
    }

    @Test func readsVersionWithoutExecutingAndLeavesManagersToTheirOwners() throws {
        let box = try Box()
        try box.install()
        #expect(box.scanner.scan().first?.version == "0.16.0")
        #expect(!box.ran)
        let cellar = box.root.appendingPathComponent("Cellar/leaf/0.16.0/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        let brewed = cellar.appendingPathComponent("leaf")
        try FileManager.default.moveItem(at: box.file, to: brewed)
        try FileManager.default.createSymbolicLink(at: box.file, withDestinationURL: brewed)
        #expect(box.scanner.scan().isEmpty)
        try FileManager.default.removeItem(at: box.file)
        let cargo = box.home.appendingPathComponent(".cargo/bin")
        try FileManager.default.createDirectory(at: cargo, withIntermediateDirectories: true)
        let managed = cargo.appendingPathComponent("leaf")
        try FileManager.default.moveItem(at: brewed, to: managed)
        try FileManager.default.createSymbolicLink(at: box.file, withDestinationURL: managed)
        #expect(box.scanner.scan().isEmpty)
    }

    @Test func versionBannerDoesNotAbsorbAdjacentCertificateBytes() throws {
        let box = try Box()
        // v0.17.0's User-Agent directly precedes DER certificate data. Its
        // opening SET tag (0x31) is also ASCII "1", not part of the version.
        var bytes = Data("leaf 0.17.0\nleaf/0.17.0".utf8)
        bytes.append(contentsOf: [0x31, 0x0B, 0x30, 0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53])
        try bytes.write(to: box.file)
        #expect(box.scanner.scan().first?.version == "0.17.0")
        #expect(!box.ran)
    }

    @Test func versionsRequireCompleteBannersAndKeepPrereleases() {
        func version(_ values: String...) -> String? {
            LeafScanner.compiledVersion(values.map { Data(("leaf " + $0).utf8) })
        }
        #expect(version("reader\n", "0.16.1\n") == "0.16.1")
        #expect(version("0.17.10\n") == "0.17.10")
        #expect(version("0.17.0-rc.1\n") == "0.17.0-rc.1")
        #expect(version("0.16.0\n", "0.16.1\n") == nil)
        #expect(version("0.16.1overflow\n") == nil)
        #expect(version("0.16.1.2\n") == nil)
        #expect(version("0.16.1+local\n") == nil)
        #expect(version("0.17.0\0") == nil)
        #expect(version("0.17.0") == nil)
        #expect(version("reader") == nil)
        #expect(!LeafRelease.isVersion("0.17.0-rc.1"))
        #expect(LeafRelease.isVersion("1.0.0"))
    }

    @Test func latestMustBeTheVendorsStableReleaseRedirect() async throws {
        let urls = ["https://github.com/DeepanshuMishraa/leaf/releases/tag/v0.16.1",
                    "https://github.com/DeepanshuMishraa/leaf/releases/tag/v1.0.0"]
        for url in urls {
            let release = LeafRelease(fetch: { requested in
                #expect(requested == LeafRelease.latestURL)
                return (200, URL(string: url))
            })
            #expect(try await release.latest() == URL(string: url)!.lastPathComponent.dropFirst())
        }
        for url in ["https://github.com/DeepanshuMishraa/leaf/releases/tag/v1.0.0-rc.1",
                    "https://github.com/another/leaf/releases/tag/v9.0.0",
                    "https://github.com/DeepanshuMishraa/leaf/releases"] {
            #expect(LeafRelease.version(from: URL(string: url)!) == nil)
        }
    }

    @Test func verdictPreservesUpdateButWithholdsUnsafeRuns() async throws {
        let box = try Box()
        try box.install()
        let original = try #require(box.scanner.scan().first)
        func status(version: String = "0.16.0", quarantine: Bool = false, writable: Bool = true,
                    busy: Bool = false) async -> CLIToolStatus {
            let copy = LeafInstall(path: original.path, binary: original.binary, version: version,
                                   target: original.target, quarantined: quarantine, writable: writable)
            return await box.check().status(of: copy, busy: busy, published: .success("0.16.1"))
        }
        #expect(await status().oneClick != nil)
        #expect(await status(quarantine: true).withheld == .unverified)
        #expect(await status(writable: false).withheld == .unsupportedInstaller)
        #expect(await status(busy: true).withheld == .busy)
        #expect(await status(version: "0.11.0").withheld == .unsupportedInstaller)
        #expect(await status(version: "0.11.0").commandToCopy == nil)
        #expect(await status(version: "0.17.0-rc.1").state == .unknown)
        #expect(await status(version: "0.16.1").state == .upToDate)
        #expect(await status(version: "1.0.0").state == .ahead)
    }

    @Test func tamperedArchiveIsRejectedBeforeExtractionOrExecution() async throws {
        let box = try Box()
        try box.install()
        let result = await box.updater(tamper: true).update(try await box.status())
        guard case .failed = result else { Issue.record("expected a checksum failure, got \(result)"); return }
        #expect(!box.ran)
        #expect(box.lock.withLock { box.extracts } == 0)
    }

    @Test func modifiedInstalledBinaryIsNotRun() async throws {
        let box = try Box()
        try box.install()
        let status = try await box.status()
        let handle = try FileHandle(forWritingTo: box.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n# modified\n".utf8))
        try handle.close()
        guard case .failed = await box.updater().update(status) else { Issue.record("modified binary ran"); return }
        #expect(!box.ran)
    }

    @Test func updateRunsOwnCommandAndVerifiesNewFile() async throws {
        let box = try Box()
        try box.install()
        let checked = try await box.status()
        // A status is data, not authority to run arbitrary arguments or a
        // different executable. The updater must rebuild the vendor command.
        let hostile = CLIToolStatus(
            kind: .leaf, path: checked.path, installedVersion: checked.installedVersion,
            latestVersion: checked.latestVersion, channel: nil, state: .updateAvailable,
            oneClick: CLIToolCommand(executable: "/usr/bin/false", arguments: ["agent", "setup"], pathPrefix: nil),
            withheld: nil, note: nil, detail: checked.detail)
        #expect(await box.updater().update(hostile) == .updated(version: "0.16.1"))
        #expect(box.ran)
        #expect(box.scanner.scan().first?.version == "0.16.1")
        let environment = try String(contentsOf: box.root.appendingPathComponent("env"), encoding: .utf8)
        #expect(environment.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(box.lock.withLock { box.extracts } == 2)
    }

    @Test func unchangedOrUnverifiableResultCannotCountAsUpdated() async throws {
        for changed in [false, true] {
            let box = try Box()
            try box.install(update: changed, publishNew: false)
            guard case .failed = await box.updater().update(try await box.status()) else {
                Issue.record("unchanged or unverifiable result passed"); continue
            }
            #expect(box.ran)
        }
    }

    @Test func busyOrMovedBackReleaseStartsNothing() async throws {
        let box = try Box()
        try box.install()
        let status = try await box.status()
        guard case .busy = await box.updater(busy: true).update(status) else { Issue.record("busy run started"); return }
        guard case .failed = await box.updater(latest: "0.16.0").update(status) else { Issue.record("stale release ran"); return }
        #expect(!box.ran)
    }

    @Test func bothVendorUpdateAliasesAreBusyButReadOnlyChecksAreNot() {
        for alias in ["upgrade", "update"] {
            let args = ["/tmp/bin/leaf", alias]
            #expect(LeafActivity.busy(processes: [.init(pid: 42, arguments: args)]))
            #expect(!LeafActivity.busy(processes: [.init(pid: 42, arguments: args + ["--check"])]))
        }
        #expect(!LeafActivity.busy(processes: [.init(pid: 42, arguments: ["/tmp/bin/leaf", "open", "update.md"])]))
    }

    @Test func notesAreStructuredAndUnreleasedCannotLeakIntoLastRelease() throws {
        let notes = try #require(LeafChangelog.parse("""
        # Changelog
        ## Unreleased
        - A future change
        ## 0.16.1
        - `leaf agent setup` installs skills and hooks together.
        ## 0.16.0
        - Review plans with `leaf plan`.
        ## Unreleased
        - Another future change
        """))
        #expect(notes.entries.map(\.version) == ["0.16.1", "0.16.0"])
        #expect(notes.entries.allSatisfy { !$0.items.isEmpty })
        #expect(!notes.entries.flatMap(\.items).joined().contains("future"))
    }
}
