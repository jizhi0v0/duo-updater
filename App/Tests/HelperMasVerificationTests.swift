import Foundation
import Security
import Testing

/// `HelperService.stageVerifiedMAS`: the root helper copies the bundled `mas` into
/// a private directory, checks the COPY against a code requirement, and runs only
/// that copy. Security review 2026-10-25, item 2.
///
/// The real requirement names our own team, which a hostless, unsigned test
/// bundle cannot produce a binary for. So the positive control is a copy of
/// `/usr/bin/true` against `anchor apple` (it is Apple-signed), and the negative
/// cases use the production requirement shape with a team that is not Apple's.
@Suite struct HelperMasVerificationTests {

    @Test func aMASFromAnotherTeamIsRefusedAndNothingIsLeftStaged() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = try fx.copyOfTrue()
        let requirement = try #require(OwnTeamIdentifier.requirement(
            bundleIdentifier: HelperService.masSigningIdentifier, team: "ZZ00000000"))

        #expect(throws: HelperService.MASStagingError.self) {
            _ = try HelperService.stageVerifiedMAS(at: source, requirement: requirement, under: fx.stagingParent)
        }
        #expect(try fx.stagingEntries().isEmpty)
    }

    @Test func anUnsignedMASIsRefused() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = fx.sourceDir + "/mas"
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: source))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source)

        #expect(throws: HelperService.MASStagingError.self) {
            _ = try HelperService.stageVerifiedMAS(at: source, requirement: "anchor apple", under: fx.stagingParent)
        }
        #expect(try fx.stagingEntries().isEmpty)
    }

    /// Team alone is not enough: another binary of the same signer must not pass
    /// as `mas`. Shown with Apple as the signer, since that is the one we have.
    @Test func aBinaryWithAnotherIdentifierIsRefused() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = try fx.copyOfTrue()

        #expect(throws: HelperService.MASStagingError.self) {
            _ = try HelperService.stageVerifiedMAS(
                at: source,
                requirement: "anchor apple and identifier \"\(HelperService.masSigningIdentifier)\"",
                under: fx.stagingParent)
        }
        #expect(try fx.stagingEntries().isEmpty)
    }

    /// An unsigned or ad-hoc helper has no team, so the production requirement is
    /// nil — and that must refuse, not skip the check.
    @Test func aMissingRequirementFailsClosed() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = try fx.copyOfTrue()

        #expect(throws: HelperService.MASStagingError.self) {
            _ = try HelperService.stageVerifiedMAS(at: source, requirement: nil, under: fx.stagingParent)
        }
        #expect(try fx.stagingEntries().isEmpty)
    }

    @Test func aSymlinkedMASIsRefused() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = fx.sourceDir + "/mas"
        try FileManager.default.createSymbolicLink(atPath: source, withDestinationPath: "/usr/bin/true")

        #expect(throws: HelperService.MASStagingError.self) {
            _ = try HelperService.stageVerifiedMAS(at: source, requirement: "anchor apple", under: fx.stagingParent)
        }
        #expect(try fx.stagingEntries().isEmpty)
    }

    /// The copy is what runs: it lives in a fresh 0711 directory of ours, is
    /// 0555, matches the source byte for byte at staging time — and replacing the
    /// source afterwards changes nothing about it.
    @Test func onlyTheVerifiedPrivateCopyIsRun() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = try fx.copyOfTrue()
        let original = try Data(contentsOf: URL(fileURLWithPath: source))

        let staged = try HelperService.stageVerifiedMAS(at: source, requirement: "anchor apple", under: fx.stagingParent)

        #expect(staged.path != source)
        #expect((staged.directory as NSString).deletingLastPathComponent == fx.stagingParent)
        #expect((staged.path as NSString).deletingLastPathComponent == staged.directory)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: staged.directory)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o711)
        #expect((dirAttrs[.ownerAccountID] as? Int) == Int(geteuid()))
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: staged.path)
        #expect((fileAttrs[.posixPermissions] as? Int) == 0o555)
        #expect((fileAttrs[.ownerAccountID] as? Int) == Int(geteuid()))
        #expect(try Data(contentsOf: URL(fileURLWithPath: staged.path)) == original)

        // Swap the source after staging: the copy must be unaffected.
        try FileManager.default.removeItem(atPath: source)
        try Data("#!/bin/sh\nexit 7\n".utf8).write(to: URL(fileURLWithPath: source))
        #expect(try Data(contentsOf: URL(fileURLWithPath: staged.path)) == original)
        #expect(Self.satisfies(staged.path, "anchor apple"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: staged.path)
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        staged.remove()
        #expect(!FileManager.default.fileExists(atPath: staged.directory))
        #expect(try fx.stagingEntries().isEmpty)
    }

    /// `mas` drops to the requesting user (`SUDO_UID`) and then opens its own
    /// path; under a 0700 root directory that is EACCES and it dies (exit 11,
    /// seen on a real Mac 2026-10-25). So with the production parent, every
    /// ancestor of the copy must be searchable by others and the copy readable.
    @Test func theStagedCopyIsReachableAfterMasDropsPrivileges() throws {
        let fx = try Fixture()
        defer { fx.cleanUp() }
        let source = try fx.copyOfTrue()

        let staged = try HelperService.stageVerifiedMAS(
            at: source, requirement: "anchor apple", under: HelperService.masStagingParent)
        defer { staged.remove() }

        var ancestor = (staged.path as NSString).deletingLastPathComponent
        while true {
            var st = stat()
            #expect(stat(ancestor, &st) == 0)
            #expect(st.st_mode & S_IXOTH != 0, "\(ancestor) is not searchable by others: \(String(st.st_mode & 0o7777, radix: 8))")
            if ancestor == "/" { break }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        var st = stat()
        #expect(stat(staged.path, &st) == 0)
        #expect(st.st_mode & S_IROTH != 0, "copy is not readable by others: \(String(st.st_mode & 0o7777, radix: 8))")
    }

    // MARK: fixtures

    static func satisfies(_ path: String, _ requirementText: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    struct Fixture {
        let root: String
        let sourceDir: String
        let stagingParent: String

        init() throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("zz-mas-verify-\(UUID().uuidString)")
            root = base.path
            sourceDir = base.appendingPathComponent("Resources").path
            stagingParent = base.appendingPathComponent("staging").path
            try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: stagingParent, withIntermediateDirectories: true)
        }

        func copyOfTrue() throws -> String {
            let path = sourceDir + "/mas"
            try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: path)
            return path
        }

        func stagingEntries() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: stagingParent)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(atPath: root)
        }
    }
}
