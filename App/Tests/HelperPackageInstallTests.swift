import CryptoKit
import Darwin
import Foundation
import Testing

@Suite struct HelperPackageInstallTests {
    @Test func replacingTheInstalledAppWithAnAttackerSignedCopyCannotChangeVendorTrust() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let app = fixture.root.appendingPathComponent("Spoof.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let identifier = "io.tailscale.ipn.macsys"
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier],
            format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        // Both attacker-controlled objects may have a valid Developer ID from
        // the same attacker. Equality with the mutable app's Team is no authority
        // to execute that developer's PKG as root. Signature attestation is the
        // seam here; the real validation and compiled binding below are unchanged.
        do {
            try HelperPackageInstall.validateInstalledIdentity(at: app, bundleIdentifier: identifier,
                verifiedTeam: { _ in "ATTACKER01" })
            Issue.record("The substituted developer became the root install authority")
        } catch HelperPackageInstall.Failure.untrustedInstalledDeveloper {}
        try HelperPackageInstall.validateInstalledIdentity(at: app, bundleIdentifier: identifier,
            verifiedTeam: { _ in "W5364U7YZB" })
    }

    @Test func anUnprivilegedHelperDeclinesBeforeStaging() async throws {
        guard geteuid() != 0 else { return }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = try FileHandle(forReadingFrom: fixture.source)
        let progress = try FileHandle(forWritingTo: fixture.source)
        defer { try? source.close(); try? progress.close() }
        let result = await HelperPackageInstall.shared.install(
            package: source, fingerprint: fixture.fingerprint,
            installedAppPath: "/Applications/UnprivilegedFixture.app",
            bundleIdentifier: "test.fixture", automatic: false,
            progress: progress, caller: getuid())
        #expect(result.0 == 77)
        #expect(try Data(contentsOf: fixture.source) == fixture.bytes)
    }

    @Test func protectedCopyUsesTheDescriptorAndSurvivesPathReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = try FileHandle(forReadingFrom: fixture.source)
        defer { try? source.close() }
        try source.seek(toOffset: UInt64(fixture.bytes.count))
        try FileManager.default.moveItem(at: fixture.source, to: fixture.root.appendingPathComponent("original.pkg"))
        try Data("substituted path".utf8).write(to: fixture.source)
        let staged = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
            under: fixture.storage, owner: getuid())
        defer { staged.remove() }
        #expect(try Data(contentsOf: staged.package) == fixture.bytes)
        #expect(try source.offset() == UInt64(fixture.bytes.count))
        let mode = try FileManager.default.attributesOfItem(atPath: staged.package.path)[.posixPermissions] as? Int
        #expect(mode == 0o400)
    }

    @Test func changedBytesAreRefusedAndNoCopyIsLeft() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try Data("changed package".utf8).write(to: fixture.source)
        let source = try FileHandle(forReadingFrom: fixture.source)
        defer { try? source.close() }
        #expect(throws: HelperPackageInstall.Failure.self) {
            _ = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
                                               under: fixture.storage, owner: getuid())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.storage.path).isEmpty)
    }

    @Test func directoryPipeAndWriteOnlyDescriptorsNeverGetRead() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let pipe = Pipe()
        let directory = FileHandle(fileDescriptor: open(fixture.root.path, O_RDONLY), closeOnDealloc: true)
        let writeOnly = try FileHandle(forWritingTo: fixture.source)
        defer { try? directory.close(); try? writeOnly.close() }
        for source in [directory, pipe.fileHandleForReading, writeOnly] {
            #expect(throws: HelperPackageInstall.Failure.self) {
                _ = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
                                                   under: fixture.storage, owner: getuid())
            }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
    }

    @Test func nonPrivateAndSymlinkedStorageAreRefused() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = try FileHandle(forReadingFrom: fixture.source)
        defer { try? source.close() }
        try FileManager.default.createDirectory(at: fixture.storage, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        #expect(throws: HelperPackageInstall.Failure.self) {
            _ = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
                                               under: fixture.storage, owner: getuid())
        }
        try FileManager.default.removeItem(at: fixture.storage)
        let actual = fixture.root.appendingPathComponent("actual")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: fixture.storage, withDestinationURL: actual)
        #expect(throws: HelperPackageInstall.Failure.self) {
            _ = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
                                               under: fixture.storage, owner: getuid())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: actual.path).isEmpty)
    }

    @Test func progressMustBeWritableOwnedByTheCallerAndSingleLinked() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let writer = try FileHandle(forWritingTo: fixture.source)
        let reader = try FileHandle(forReadingFrom: fixture.source)
        defer { try? writer.close(); try? reader.close() }
        try HelperPackageInstall.validateProgress(writer, caller: getuid())
        #expect(throws: HelperPackageInstall.Failure.self) {
            try HelperPackageInstall.validateProgress(reader, caller: getuid())
        }
        #expect(throws: HelperPackageInstall.Failure.self) {
            try HelperPackageInstall.validateProgress(writer, caller: getuid() + 1)
        }
        try FileManager.default.linkItem(at: fixture.source, to: fixture.root.appendingPathComponent("hardlink"))
        #expect(throws: HelperPackageInstall.Failure.self) {
            try HelperPackageInstall.validateProgress(writer, caller: getuid())
        }
        #expect(throws: HelperPackageInstall.Failure.self) {
            try HelperPackageInstall.validateProgress(Pipe().fileHandleForWriting, caller: getuid())
        }
    }

    @Test func malformedFingerprintsAndWrongStorageOwnerFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let source = try FileHandle(forReadingFrom: fixture.source)
        defer { try? source.close() }
        #expect(throws: HelperPackageInstall.Failure.self) {
            _ = try HelperPackageInstall.stage(source, fingerprint: Data(count: 31),
                                               under: fixture.storage, owner: getuid())
        }
        #expect(throws: HelperPackageInstall.Failure.self) {
            _ = try HelperPackageInstall.stage(source, fingerprint: fixture.fingerprint,
                                               under: fixture.storage, owner: getuid() + 1)
        }
    }

    @Test func packageProtocolIsSeparateFromMASApprovalAndOldHelpers() {
        for version in ["149", "149 protocol/3", "149 protocol/4", "149 protocol/5", "149 protocol/", "149 protocol/no"] {
            #expect(!HelperProtocolRevision.supportsPackageInstall(versionReply: version))
        }
        #expect(HelperProtocolRevision.supportsVerifiedMASInstall(versionReply: "149 protocol/4"))
        #expect(HelperProtocolRevision.supportsPackageInstall(
            versionReply: HelperProtocolRevision.versionReply(bundleVersion: "149")))
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let storage: URL
        let bytes = Data("verified package fixture".utf8)
        var fingerprint: Data { Data(SHA256.hash(data: bytes)) }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("helper-pkg-\(UUID().uuidString)")
            source = root.appendingPathComponent("source.pkg")
            storage = root.appendingPathComponent("private")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try bytes.write(to: source)
        }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
