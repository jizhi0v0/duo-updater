import CryptoKit
import Darwin
import Foundation
import Testing

@testable import DuoUpdaterCore

/// Whether an app bundle survives a trip through an Apple Archive intact.
///
/// This is the load-bearing property of storing backups off the boot volume: the
/// archive is what lets a destination filesystem that cannot represent a `.app`
/// (exFAT, an SMB share) hold one anyway. If a round trip is lossy, storing
/// backups as archives is not viable and the whole approach has to change, so
/// these tests assert the property directly rather than trusting the tool's
/// documentation.
///
/// Two separate assertions, because one does not imply the other:
///
/// - the `BackupManifest` matches, which is what the rollback gate checks; and
/// - the vendor code signature still validates, which the manifest **cannot**
///   tell us because it does not hash extended attributes.
///
/// A tree can come back byte-identical by the manifest's reckoning and still be a
/// broken app.
@Suite struct BundleArchiveTests {

    // MARK: - Fixtures

    private func scratch() -> URL {
        // UUID-suffixed: several worktrees of this repo run `swift test`
        // concurrently against the same $TMPDIR, and a shared fixture name means
        // one run deletes another's directory mid-test.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DuoBundleArchiveTest-\(UUID().uuidString)")
    }

    private func setXattr(_ name: String, _ value: String, on url: URL) throws {
        let data = Data(value.utf8)
        let rc = data.withUnsafeBytes { buf in
            setxattr(url.path, name, buf.baseAddress, buf.count, 0, 0)
        }
        try #require(rc == 0, "setxattr(\(name)) failed: \(errno)")
    }

    private func xattrNames(of url: URL) -> [String] {
        let size = listxattr(url.path, nil, 0, 0)
        guard size > 0 else { return [] }
        var buf = [CChar](repeating: 0, count: size)
        guard listxattr(url.path, &buf, size, 0) == size else { return [] }
        return buf.split(separator: 0)
            .map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
            .sorted()
    }

    /// A bundle carrying every shape that a non-native filesystem is known to
    /// mangle: symlinks (relative and absolute), extended attributes, non-default
    /// permission bits, a hard-link pair, an empty directory, and a decomposed
    /// (NFD) filename.
    @discardableResult
    private func makeNastyBundle(in dir: URL) throws -> URL {
        let fm = FileManager.default
        let app = dir.appendingPathComponent("Fixture.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        let versions = contents.appendingPathComponent("Frameworks/F.framework/Versions")

        for path in [macOS, resources, versions.appendingPathComponent("A"),
                     contents.appendingPathComponent("EmptyDir")] {
            try fm.createDirectory(at: path, withIntermediateDirectories: true)
        }

        let exec = macOS.appendingPathComponent("App")
        try Data("hello executable\n".utf8).write(to: exec)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
        try setXattr("com.apple.quarantine", "0081;00000000;Safari;", on: exec)

        let plain = resources.appendingPathComponent("plain.txt")
        try Data("plain\n".utf8).write(to: plain)
        try setXattr("com.example.custom", "some-custom-value", on: plain)

        let secret = resources.appendingPathComponent("private.txt")
        try Data("secret\n".utf8).write(to: secret)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secret.path)

        // `Versions/Current -> A` is the shape every framework inside a real
        // bundle uses; an absolute link is the one that breaks differently.
        try fm.createSymbolicLink(
            atPath: versions.appendingPathComponent("Current").path,
            withDestinationPath: "A")
        try fm.createSymbolicLink(
            atPath: resources.appendingPathComponent("abs-link").path,
            withDestinationPath: "/usr/bin/true")
        try fm.createSymbolicLink(
            atPath: resources.appendingPathComponent("rel-link").path,
            withDestinationPath: "../MacOS/App")

        let hardA = resources.appendingPathComponent("hard-a")
        try Data("linked content\n".utf8).write(to: hardA)
        try fm.linkItem(at: hardA, to: resources.appendingPathComponent("hard-b"))

        // Decomposed "Café.txt" — normalization differences move a manifest that
        // sorts by path string.
        try Data("accented\n".utf8)
            .write(to: resources.appendingPathComponent("Cafe\u{0301}.txt"))

        return app
    }

    /// A small, really-signed app to prove the signature survives. Scanned rather
    /// than hard-coded: no single app is guaranteed present on a dev machine.
    private static let signedApp: URL? = {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return nil }
        let candidates = entries.filter { $0.pathExtension == "app" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        for app in candidates {
            // Cheap size guard first: a 900 MB Electron app makes this test slow
            // for no extra signal.
            let size = (try? fm.subpathsOfDirectory(atPath: app.path).count) ?? .max
            guard size < 4000 else { continue }
            guard (try? SignatureVerifier.verifyCodeSignature(appAt: app)) != nil else { continue }
            return app
        }
        return nil
    }()

    // MARK: - The two load-bearing assertions

    @Test(arguments: [BundleArchive.Compression.fast, .smallest])
    func roundTripPreservesTheManifest(_ compression: BundleArchive.Compression) throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let app = try makeNastyBundle(in: root)
        let before = try #require(BackupManifest.compute(for: app))

        let archive = root.appendingPathComponent("fixture.aar")
        try BundleArchive.archive(bundle: app, to: archive, compression: compression)

        let restored = root.appendingPathComponent("Restored.app")
        try BundleArchive.extract(archive: archive, into: restored)

        let after = try #require(BackupManifest.compute(for: restored))
        #expect(after == before, "\(compression) round trip changed the manifest")
    }

    /// The things `BackupManifest` does **not** hash, checked directly. Without
    /// this, a round trip that dropped every extended attribute would still pass
    /// the test above.
    @Test func roundTripPreservesMetadataTheManifestIgnores() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let app = try makeNastyBundle(in: root)
        let archive = root.appendingPathComponent("fixture.aar")
        try BundleArchive.archive(bundle: app, to: archive)
        let restored = root.appendingPathComponent("Restored.app")
        try BundleArchive.extract(archive: archive, into: restored)

        let fm = FileManager.default
        let exec = "Contents/MacOS/App"
        let plain = "Contents/Resources/plain.txt"
        let secret = "Contents/Resources/private.txt"

        // Extended attributes: the ones whose loss silently breaks a signature.
        #expect(xattrNames(of: restored.appendingPathComponent(exec))
            == xattrNames(of: app.appendingPathComponent(exec)))
        #expect(xattrNames(of: restored.appendingPathComponent(plain))
            .contains("com.example.custom"))

        // Permission bits.
        for relative in [exec, secret] {
            let source = try fm.attributesOfItem(atPath: app.appendingPathComponent(relative).path)
            let copy = try fm.attributesOfItem(
                atPath: restored.appendingPathComponent(relative).path)
            #expect(copy[.posixPermissions] as? Int == source[.posixPermissions] as? Int,
                    "mode changed for \(relative)")
        }

        // Symlinks stay symlinks, pointing where they pointed.
        for (relative, target) in [
            ("Contents/Frameworks/F.framework/Versions/Current", "A"),
            ("Contents/Resources/abs-link", "/usr/bin/true"),
            ("Contents/Resources/rel-link", "../MacOS/App"),
        ] {
            let path = restored.appendingPathComponent(relative).path
            #expect(try fm.destinationOfSymbolicLink(atPath: path) == target)
        }

        // Hard links stay linked rather than becoming two independent copies —
        // `ditto`, which the local backup path uses, does not manage this.
        let linkCount = try fm.attributesOfItem(
            atPath: restored.appendingPathComponent("Contents/Resources/hard-a").path)
        #expect(linkCount[.referenceCount] as? Int == 2)

        #expect(fm.fileExists(atPath: restored.appendingPathComponent("Contents/EmptyDir").path))
    }

    /// Manifest equality does not imply a valid seal, so this asks the question
    /// the manifest cannot.
    @Test(.enabled(if: BundleArchiveTests.signedApp != nil))
    func roundTripPreservesTheCodeSignature() throws {
        let app = try #require(Self.signedApp)
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let archive = root.appendingPathComponent("signed.aar")
        try BundleArchive.archive(bundle: app, to: archive)
        let restored = root.appendingPathComponent(app.lastPathComponent)
        try BundleArchive.extract(archive: archive, into: restored)

        // Throws on failure; reaching the next line is the assertion.
        try SignatureVerifier.verifyCodeSignature(appAt: restored)
    }

    // MARK: - Failure modes

    @Test func archivingAMissingBundleFails() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let archive = root.appendingPathComponent("out.aar")
        #expect(throws: BundleArchive.ArchiveError.self) {
            try BundleArchive.archive(
                bundle: root.appendingPathComponent("NoSuch.app"), to: archive)
        }
        #expect(!FileManager.default.fileExists(atPath: archive.path),
                "a failed archive must not leave a file under the real name")
    }

    @Test func extractingAMissingArchiveFails() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        #expect(throws: BundleArchive.ArchiveError.self) {
            try BundleArchive.extract(
                archive: root.appendingPathComponent("nope.aar"),
                into: root.appendingPathComponent("out"))
        }
    }

    /// A truncated or altered archive must be detectable without unpacking it —
    /// this digest is the integrity gate for the copy that lives on the
    /// destination, where a tree-walking comparison is exactly what we cannot do.
    @Test func digestChangesWhenTheArchiveIsTampered() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let app = try makeNastyBundle(in: root)
        let archive = root.appendingPathComponent("fixture.aar")
        try BundleArchive.archive(bundle: app, to: archive)

        let original = try BundleArchive.sha256(of: archive)
        #expect(original.count == 64)
        #expect(try BundleArchive.sha256(of: archive) == original, "digest is not stable")

        var bytes = try Data(contentsOf: archive)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: archive)

        #expect(try BundleArchive.sha256(of: archive) != original)
    }

    /// A successful archive leaves the destination directory clean — no `.partial`
    /// beside it, which the destination sweeper would otherwise have to guess about.
    @Test func aSuccessfulArchiveLeavesNoPartialBehind() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let app = try makeNastyBundle(in: root)
        let out = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try BundleArchive.archive(bundle: app, to: out.appendingPathComponent("fixture.aar"))

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(leftovers == ["fixture.aar"], "unexpected leftovers: \(leftovers)")
    }

    @Test func archivingReplacesAnExistingArchiveAtTheSamePath() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let app = try makeNastyBundle(in: root)
        let archive = root.appendingPathComponent("fixture.aar")
        try Data("stale".utf8).write(to: archive)

        try BundleArchive.archive(bundle: app, to: archive)
        let restored = root.appendingPathComponent("Restored.app")
        try BundleArchive.extract(archive: archive, into: restored)
        #expect(FileManager.default.fileExists(
            atPath: restored.appendingPathComponent("Contents/MacOS/App").path))
    }
}
