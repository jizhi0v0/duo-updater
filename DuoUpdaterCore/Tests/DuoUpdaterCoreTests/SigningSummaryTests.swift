import Testing
import Foundation
@testable import DuoUpdaterCore

/// `SignatureVerifier.signingSummary(at:)` feeds `duo diff`'s trust section, so what
/// it reads has to be what `codesign -dvv` would print for the same bundle.
@Suite struct SigningSummaryTests {

    /// A bundle whose executable is a shell script: signable ad hoc without any
    /// binary from the machine running the test.
    private func fixtureBundle(in directory: URL) throws -> URL {
        let app = directory.appendingPathComponent("ZZFixture-signing.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("zzfixture")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try PropertyListSerialization
            .data(fromPropertyList: ["CFBundleExecutable": "zzfixture", "CFBundleIdentifier": "test.zzfixture.signing"],
                  format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-signing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `SecCodeCopySigningInformation` succeeds on unsigned code, so without the
    /// identifier check this reads as a signature with every field empty.
    @Test func anUnsignedBundleHasNoSummary() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureBundle(in: directory)
        #expect(SignatureVerifier.signingSummary(at: app) == nil)
    }

    /// Ad hoc with the hardened runtime: flag bits 0x2 and 0x10000, which codesign
    /// prints as `flags=0x10002(adhoc,runtime)`.
    @Test func anAdHocSignatureReadsLikeCodesign() async throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try fixtureBundle(in: directory)
        let signed = try await ChildProcess.run(
            "/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", app.path],
            onCancel: .runToCompletion)
        try #require(signed.succeeded, "\(String(decoding: signed.standardError, as: UTF8.self))")

        let summary = try #require(SignatureVerifier.signingSummary(at: app))
        #expect(summary.identifier == "test.zzfixture.signing")
        #expect(summary.teamIdentifier == nil)
        #expect(summary.authorities.isEmpty)
        #expect(summary.flags == ["adhoc", "runtime"])
    }

    /// Nested dictionaries join their keys with `.` and arrays their values with
    /// `, `, so one changed entitlement reads as one changed line. Booleans arrive
    /// from Security as `NSNumber`, which print as `1`.
    @Test func entitlementsFlattenToOneLinePerValue() {
        let flattened = SignatureVerifier.flattened([
            "com.apple.security.device.camera": NSNumber(value: true),
            "zz.fixture.groups": ["one", "two"],
            "zz.fixture.nested": ["inner": "value"],
        ])
        #expect(flattened == [
            "com.apple.security.device.camera": "1",
            "zz.fixture.groups": "one, two",
            "zz.fixture.nested.inner": "value",
        ])
    }
}
