import CryptoKit
import Foundation
import Synchronization
import Testing
@testable import DuoUpdaterCore

struct MulticaTests {
    private static let before = "0.1.8"
    private static let after = "0.11.1"
    private static let module = "github.com/multica-ai/multica/server"
    private var before: String { Self.before }
    private var after: String { Self.after }

    /// Synthetic Go metadata in a thin Mach-O, read by the production scanner.
    /// No test executes it.
    private static func binary(_ version: String, cpu: UInt32 = 0x0100_000c, main: String = module + "/cmd/multica") -> Data {
        var image = Data()
        func le<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { image.append(contentsOf: $0) }
        }
        func name(_ string: String) {
            image.append(contentsOf: string.utf8)
            image.append(Data(count: 16 - string.utf8.count))
        }

        let settings = """
            path\t\(main)
            mod\t\(module)\t(devel)\t
            build\t-ldflags="-s -w -X main.version=\(version) -X main.commit=xyz"

            """
        var build = Data([0xff]) + Data(" Go buildinf:".utf8) + Data([8, 2]) + Data(count: 16)
        for string in ["go1.26.9", settings] {
            var length = string.utf8.count
            while length >= 0x80 {
                build.append(UInt8(length & 0x7f) | 0x80)
                length >>= 7
            }
            build.append(UInt8(length))
            build.append(contentsOf: string.utf8)
        }

        let commandBytes: UInt32 = 72 + 80
        let offset: UInt32 = 32 + commandBytes
        for value in [0xfeed_facf, cpu, 0, 2, 1, commandBytes, 0, 0, 0x19, commandBytes] as [UInt32] { le(value) }
        name("__DATA")
        for value in [0, 0, UInt64(offset), UInt64(build.count)] as [UInt64] { le(value) }
        for value in [3, 3, 1, 0] as [UInt32] { le(value) }
        name("__go_buildinfo")
        name("__DATA")
        le(UInt64(0))
        le(UInt64(build.count))
        for value in [offset, 3, 0, 0, 0, 0, 0, 0] as [UInt32] { le(value) }
        return image + build
    }

    private struct Fixture {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }
        var bin: URL { home.appendingPathComponent(".local/bin") }
        var system: URL { root.appendingPathComponent("usr/local/bin") }
        var executable: URL { bin.appendingPathComponent("multica") }
        var scanner: MulticaScanner { MulticaScanner(home: home, systemDirectory: system, customDirectory: nil) }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZZFixture-multica-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        }

        func clean() { try? FileManager.default.removeItem(at: root) }

        func write(_ bytes: Data, to file: URL) throws {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: file.path)
        }

        func archive(_ bytes: Data, shape: Shape = .regular) async throws -> Data {
            let bundle = root.appendingPathComponent(UUID().uuidString)
            let file = bundle.appendingPathComponent("multica")
            switch shape {
            case .regular, .duplicate:
                try write(bytes, to: file)
            case .link:
                let target = bundle.appendingPathComponent("some tool")
                try write(bytes, to: target)
                try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: target.lastPathComponent)
            case .nested:
                try write(bytes, to: bundle.appendingPathComponent("nested/multica"))
            }
            let archive = root.appendingPathComponent(UUID().uuidString + ".tar.gz")
            let members = switch shape {
            case .duplicate: ["multica", "multica"]
            case .nested: ["nested/multica"]
            default: ["multica"]
            }
            let result = try await ChildProcess.run(
                "/usr/bin/tar", ["-czf", archive.path, "-C", bundle.path] + members, onCancel: .terminateChild)
            try #require(result.succeeded)
            return try Data(contentsOf: archive)
        }

        func provider(
            old: Data, new: Data, failsDigest: Bool = false, staleMetadata: Bool = false,
            afterDownload: @escaping @Sendable () throws -> Void = {},
            usage: @escaping MulticaProvider.Usage = { _ in [:] }
        ) throws -> MulticaProvider {
            let before = MulticaTests.before
            let after = MulticaTests.after
            let oldAsset = "multica_darwin_arm64.tar.gz"
            let newAsset = "multica-cli-\(after)-darwin-arm64.tar.gz"
            let oldManifest = Data("\(digest(old))  \(oldAsset)\n".utf8)
            let newDigest = failsDigest ? String(repeating: "0", count: 64) : digest(new)
            let newManifest = Data("\(newDigest)  \(newAsset)\n".utf8)
            let oldRelease = try release(before, assets: [["name": oldAsset], ["name": "checksums.txt"]])
            let newRelease = try release(after, assets: [
                ["name": oldAsset, "digest": "sha256:\(digest(old))"],
                ["name": newAsset, "digest": "sha256:\(staleMetadata ? digest(old) : newDigest)"],
                ["name": "checksums.txt", "digest": "sha256:\(digest(newManifest))"],
            ])
            let release = MulticaRelease { url, _, _, _ in
                if url == MulticaRelease.notesURL { return Data("[".utf8) + newRelease + Data("]".utf8) }
                let path = url.path
                if path.hasSuffix("/latest") || path.hasSuffix("/tags/v\(after)") { return newRelease }
                if path.hasSuffix("/tags/v\(before)") { return oldRelease }
                if path.hasSuffix("/v\(before)/checksums.txt") { return oldManifest }
                if path.hasSuffix("/v\(after)/checksums.txt") { return newManifest }
                if path.hasSuffix("/v\(before)/\(oldAsset)") { return old }
                if path.hasSuffix("/v\(after)/\(newAsset)") {
                    try afterDownload()
                    return new
                }
                Issue.record("Unexpected Multica request: \(url)")
                throw CLIToolReleaseNotesError.http(404)
            }
            return MulticaProvider(scanner: scanner, release: release, usage: usage)
        }

        func release(_ version: String, assets: [[String: String]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "tag_name": "v\(version)", "name": "Multica \(version)", "assets": assets, "draft": false,
                "prerelease": false, "published_at": "2026-11-23T10:00:00Z",
                "html_url": "https://github.com/multica-ai/multica/releases/tag/v\(version)", "body": "- New CLI behavior",
            ])
        }

        private func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    private enum Shape { case regular, duplicate, link, nested }

    @Test func scannerSeparatesStandaloneLinksManagedCopiesAndSourceBuilds() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let source = fixture.executable
        let managerFile = fixture.root.appendingPathComponent("Cellar/multica/0.1.8/bin/multica")
        let desktop = fixture.root.appendingPathComponent("Multica.app/Contents/Resources/bin/multica")
        let system = fixture.system.appendingPathComponent("multica")
        try fixture.write(Self.binary("v0.1.8-123-gabcd"), to: source)
        try fixture.write(Self.binary(before), to: managerFile)
        try fixture.write(Self.binary(before), to: desktop)
        try FileManager.default.createSymbolicLink(at: system, withDestinationURL: managerFile)
        let scanner = MulticaScanner(home: fixture.home, systemDirectory: fixture.system,
                                     customDirectory: desktop.deletingLastPathComponent().path)
        let provider = MulticaProvider(scanner: scanner, release: MulticaRelease { _, _, _, _ in
            Issue.record("A source build does not read the release channel.")
            throw CLIToolReleaseNotesError.http(404)
        }, usage: { _ in [:] })
        let sightings = await provider.scan()
        #expect(sightings.map(\.path) == [source.path])
        #expect(sightings.first?.version == "0.1.8-123-gabcd")
        #expect(await provider.check().statuses.map(\.withheld) == [.versionUnreadable])

        try FileManager.default.removeItem(at: system)
        try FileManager.default.removeItem(at: source)
        let outside = fixture.root.appendingPathComponent("standalone/multica")
        try fixture.write(Self.binary(before), to: outside)
        try fixture.write(Self.binary(before, main: Self.module + "/cmd/server"), to: system)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        let published = try fixture.release(after, assets: [
            ["name": "multica-cli-\(after)-darwin-arm64.tar.gz"], ["name": "checksums.txt"],
        ])
        let report = await MulticaProvider(scanner: scanner, release: MulticaRelease { _, _, _, _ in published },
                                          usage: { _ in [:] }).check()
        let linked = try #require(report.statuses.first)
        #expect(report.statuses.map(\.path) == [source.path])
        #expect(linked.oneClick == nil)
        #expect(linked.manualCommand == nil)
        #expect(linked.withheld == .unsupportedInstaller)

        let custom = MulticaScanner(home: fixture.home, systemDirectory: fixture.system,
                                    customDirectory: outside.deletingLastPathComponent().path)
        #expect(custom.scan().map(\.path) == [outside.path])
    }

    @Test func verifiedLegacyCopyUpdatesThroughProviderAndReadsNotes() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        let new = Self.binary(after)
        try fixture.write(old, to: fixture.executable)
        let provider = try await fixture.provider(old: fixture.archive(old), new: fixture.archive(new))
        let status = try #require(await provider.check().statuses.first)
        #expect(status.oneClick?.executable == "duo")
        #expect(status.oneClick?.arguments == ["install", fixture.executable.path])
        #expect(status.latestVersion == after)
        let notes = try await provider.releaseNotes(for: status, force: true)
        #expect(notes.entries.map(\.version) == [after])
        #expect(await provider.update(status, progress: { _ in }) == .updated(version: after))
        #expect(try Data(contentsOf: fixture.executable) == new)
        let mode = try FileManager.default.attributesOfItem(atPath: fixture.executable.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o751)
        #expect(await provider.check().statuses.first?.state == .upToDate)
    }

    @Test func sameVersionSourceBuildCannotBeReplaced() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        let local = old + Data([1])
        try fixture.write(local, to: fixture.executable)
        let provider = try await fixture.provider(
            old: fixture.archive(old), new: fixture.archive(Self.binary(after)),
            afterDownload: { Issue.record("A local build should fail before the new archive is requested.") })
        let status = try #require(await provider.check().statuses.first)
        let result = await provider.update(status, progress: { _ in })
        guard case .failed(let message, _) = result else { Issue.record("Unexpected outcome \(result)"); return }
        #expect(message.contains("differs from the official release"))
        #expect(try Data(contentsOf: fixture.executable) == local)
    }

    @Test func manualUpdateRequiresAUsableVendorRelease() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let archive = ["name": "multica-cli-\(after)-darwin-arm64.tar.gz"]
        let available = try fixture.release(after, assets: [archive, ["name": "checksums.txt"]])
        let legacy = try fixture.release(after, assets: [
            archive, ["name": "multica_darwin_arm64.tar.gz"], ["name": "checksums.txt"],
        ])
        let provider = MulticaProvider(scanner: fixture.scanner, release: .init { _, _, _, _ in available },
                                       usage: { _ in [:] })
        let legacyProvider = MulticaProvider(scanner: fixture.scanner, release: .init { _, _, _, _ in legacy },
                                             usage: { _ in [:] })

        for (version, canUseVersioned, canUseLegacy) in [
            (before, false, false), ("0.1.14", false, true), ("0.2.10", true, true),
        ] {
            try fixture.write(Self.binary(version), to: fixture.executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.executable.path)
            for (source, offersManual) in [(provider, canUseVersioned), (legacyProvider, canUseLegacy)] {
                let readonly = try #require(await source.check().statuses.first)
                #expect(readonly.oneClick == nil)
                #expect(readonly.commandToCopy?.executable == (offersManual ? fixture.executable.path : nil))
                #expect(readonly.commandToCopy?.arguments == (offersManual ? ["update"] : nil))
            }
        }

        let incomplete = try fixture.release(after, assets: [archive])
        let badRelease = MulticaProvider(scanner: fixture.scanner, release: .init { _, _, _, _ in incomplete },
                                         usage: { _ in [:] })
        let missingManifest = try #require(await badRelease.check().statuses.first)
        #expect(missingManifest.withheld == .unverified)
        #expect(missingManifest.oneClick == nil)
        #expect(missingManifest.commandToCopy == nil)
    }

    enum Rejection: CaseIterable { case checksum, mismatchedMetadata, wrongVersion, wrongArchitecture, duplicate, link, nested }

    @Test(arguments: Rejection.allCases) func refusesInvalidPublishedArchive(_ rejection: Rejection) async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        try fixture.write(old, to: fixture.executable)
        let body = Self.binary(rejection == .wrongVersion ? before : after,
                               cpu: rejection == .wrongArchitecture ? 0x0100_0007 : 0x0100_000c)
        let shape: Shape = switch rejection {
        case .duplicate: .duplicate
        case .link: .link
        case .nested: .nested
        default: .regular
        }
        let provider = try await fixture.provider(old: fixture.archive(old), new: fixture.archive(body, shape: shape),
                                                  failsDigest: rejection == .checksum,
                                                  staleMetadata: rejection == .mismatchedMetadata)
        let status = try #require(await provider.check().statuses.first)
        #expect(status.oneClick != nil)
        let result = await provider.update(status, progress: { _ in })
        guard case .failed(let message, _) = result else { Issue.record("Unexpected outcome \(result)"); return }
        switch rejection {
        case .checksum: #expect(message.contains("did not match its published checksum"))
        case .mismatchedMetadata: #expect(message.contains("disagrees with GitHub"))
        case .wrongVersion, .wrongArchitecture: #expect(message.contains("version and architecture"))
        case .duplicate, .link, .nested: #expect(message.contains("single regular multica executable"))
        }
        #expect(try Data(contentsOf: fixture.executable) == old)
    }

    @Test func rechecksInUseImmediatelyBeforeReplacing() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        try fixture.write(old, to: fixture.executable)
        let running = Mutex(false)
        let provider = try await fixture.provider(
            old: fixture.archive(old), new: fixture.archive(Self.binary(after)),
            afterDownload: { running.withLock { $0 = true } },
            usage: { targets in
                guard running.withLock({ $0 }) else { return [:] }
                return Dictionary(uniqueKeysWithValues: targets.map { ($0, .init(current: [123], stale: [])) })
            })
        let status = try #require(await provider.check().statuses.first)
        #expect(status.oneClick != nil)
        #expect(await provider.update(status, progress: { _ in }) == .busy(MulticaProvider.busyMessage))
        #expect(await provider.check().statuses.first?.withheld == .busy)
        #expect(try Data(contentsOf: fixture.executable) == old)
    }

    @Test func rechecksReplacedFileEvenIfVersionIsUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        try fixture.write(old, to: fixture.executable)
        let replacement = old + Data([1])
        let provider = try await fixture.provider(
            old: fixture.archive(old), new: fixture.archive(Self.binary(after)),
            afterDownload: { try fixture.write(replacement, to: fixture.executable) })
        let status = try #require(await provider.check().statuses.first)
        let result = await provider.update(status, progress: { _ in })
        guard case .failed(let message, _) = result else { Issue.record("Unexpected outcome \(result)"); return }
        #expect(message.contains("changed after checking"))
        #expect(try Data(contentsOf: fixture.executable) == replacement)
    }

    @Test func symlinkInsertedDuringUpdateDoesNotRedirectReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        try fixture.write(old, to: fixture.executable)
        let external = fixture.root.appendingPathComponent("external/multica")
        try fixture.write(old, to: external)
        let provider = try await fixture.provider(
            old: fixture.archive(old), new: fixture.archive(Self.binary(after)),
            afterDownload: {
                try FileManager.default.removeItem(at: fixture.executable)
                try FileManager.default.createSymbolicLink(at: fixture.executable, withDestinationURL: external)
            })
        let status = try #require(await provider.check().statuses.first)
        let result = await provider.update(status, progress: { _ in })
        guard case .failed(let message, _) = result else { Issue.record("Unexpected outcome \(result)"); return }
        #expect(message.contains("changed after checking"))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.executable.path) == external.path)
        #expect(try Data(contentsOf: external) == old)
    }

    @Test func replacingTheStageDirectoryEntryCannotChangeWhatIsInstalled() throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        let updated = Self.binary(after)
        try fixture.write(old, to: fixture.executable)
        let installed = try #require(fixture.scanner.scan().first)
        let source = fixture.root.appendingPathComponent("verified")
        try fixture.write(updated, to: source)

        let fm = FileManager.default
        let moved = fixture.root.appendingPathComponent("moved-stage")
        var foreignFile: URL?
        try MulticaReplacement.replace(installed, with: source) {
            let entries = try fm.contentsOfDirectory(at: fixture.bin, includingPropertiesForKeys: nil)
            let stage = try #require(entries.first { $0.lastPathComponent.hasPrefix(".duo-multica-") })
            #expect(try fm.attributesOfItem(atPath: stage.path)[.posixPermissions] as? Int == 0o700)
            try fm.moveItem(at: stage, to: moved)
            let foreign = stage.appendingPathComponent("multica")
            try fixture.write(old, to: foreign)
            foreignFile = foreign
        }
        #expect(try Data(contentsOf: fixture.executable) == updated)
        #expect(try Data(contentsOf: #require(foreignFile)) == old)
        #expect(try fm.contentsOfDirectory(atPath: moved.path).isEmpty)
    }

    @Test func inheritedStagingACLFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let old = Self.binary(before)
        try fixture.write(old, to: fixture.executable)
        let installed = try #require(fixture.scanner.scan().first)
        let source = fixture.root.appendingPathComponent("verified")
        try fixture.write(Self.binary(after), to: source)
        let changed = try await ChildProcess.run(
            "/bin/chmod", ["+a", "everyone allow search,add_file,delete_child,directory_inherit", fixture.bin.path],
            onCancel: .terminateChild)
        try #require(changed.succeeded)
        #expect {
            try MulticaReplacement.replace(installed, with: source) {
                Issue.record("The staging directory should have been rejected before commit.")
            }
        } throws: { error in
            guard case MulticaReplacement.Failure.unsafeStaging = error else { return false }
            return true
        }
        #expect(try Data(contentsOf: fixture.executable) == old)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.bin.path) == ["multica"])
    }
}
