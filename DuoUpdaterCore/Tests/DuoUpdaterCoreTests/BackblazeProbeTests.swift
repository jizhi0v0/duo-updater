import Testing
@testable import DuoUpdaterCore

struct BackblazeProbeTests {
    private static let archive = "https://secure.backblaze.com/api/install_backblaze?file=bzinstall-mac-10.0.4.1082.dmg"
    private static let digest = "49f22e2ec057ba011dab1e53d4fc70f0c6ecc8b9275436b22590ccb165be0d85"
    private static let record = #"""
    {"token":"backblaze","full_token":"backblaze","url":"\#(archive)","version":"10.0.4.1082","sha256":"\#(digest)","auto_updates":true}
    """#

    @Test func thePublishedCaskPinsTheOfficialSignedInstaller() async throws {
        let outcome = try await Self.probe(Self.record)
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "10.0.4.1082")
        #expect(remote.downloadURL?.absoluteString == Self.archive)
        #expect(remote.expectedSHA256 == Self.digest)
        #expect(remote.vendorInstallerApp?.bundleIdentifier == "com.backblaze.bzdoinstall")
        #expect(remote.requiresManualInstaller)
        #expect(outcome.warnings.isEmpty)
    }

    @Test func aMissingDigestKeepsTheOfficialPageWithoutTheHandoff() async throws {
        let outcome = try await Self.probe(Self.record.replacingOccurrences(of: Self.digest, with: "no_check"))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "10.0.4.1082")
        #expect(remote.vendorInstallerApp == nil)
        #expect(remote.downloadURL?.absoluteString == "https://www.backblaze.com/status/update")
    }

    @Test(arguments: [
        ("secure.backblaze.com", "downloads.example.com"),
        ("bzinstall-mac-10.0.4.1082.dmg", "bzinstall-mac-10.0.3.1076.dmg"),
        (#""token":"backblaze""#, #""token":"different-cask""#),
    ])
    func unrelatedDownloadRecordsAreRefused(original: String, replacement: String) async throws {
        let outcome = try await Self.probe(Self.record.replacingOccurrences(of: original, with: replacement))
        #expect(outcome.remote == nil)
    }

    private static func probe(_ body: String) async throws -> ProbeOutcome {
        let fixture = try RecipeVerificationTests.StubServer(body: body)
        defer { fixture.stop() }
        let recipe = try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.backblaze.Backblaze" })
        return await VendorProbeSource().probeDiagnostic(recipe.with(url: fixture.url))
    }
}
