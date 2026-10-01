import Foundation
import Testing
@testable import DuoUpdaterCore

/// `CLIToolTrust`'s digest rule: a published hash vouches for a file only when it
/// is exactly the file's sha256, whatever shape the vendor writes it in.
struct CLIToolTrustTests {

    static let digest = "ec1b9233e7f72990" + String(repeating: "0", count: 47) + "a"

    /// The shapes vendors publish: rustup's `<hex> *./rustup-init`, coreutils'
    /// `<hex>  <name>`, GitHub's asset `sha256:<hex>`, bare hex, upper case.
    @Test(arguments: [
        "\(digest) *./rustup-init",
        "\(digest)  uv-aarch64-apple-darwin.tar.gz\n",
        "sha256:\(digest)",
        digest,
        digest.uppercased(),
    ])
    func aPublishedDigestInAnyShapeMatches(_ published: String) {
        #expect(CLIToolTrust.matches(Self.digest, published: published))
    }

    /// One hex digit off is a different file.
    ///
    /// Mutation: compare only a prefix (`actual.prefix(20) == published.prefix(20)`).
    @Test func aDigestOneDigitOffDoesNotMatch() {
        let other = String(Self.digest.dropLast()) + "b"
        #expect(!CLIToolTrust.matches(Self.digest, published: other))
    }

    /// Nothing published, nothing readable, or a run of hex that is not a whole
    /// sha256 — never a match. rustup's update-hashes hold 20 hex digits, which
    /// must not pass for a digest.
    ///
    /// Mutation: drop `actual.count == 64` from `matches` — two 20-digit
    /// update-hashes then vouch for each other. (Loosening `firstDigest`'s own
    /// length checks alone survives: a run of another length never equals a
    /// 64-digit `actual`.)
    @Test func aMissingOrPartialDigestNeverMatches() {
        #expect(!CLIToolTrust.matches(nil, published: Self.digest))
        #expect(!CLIToolTrust.matches(Self.digest, published: nil))
        #expect(!CLIToolTrust.matches(Self.digest, published: String(Self.digest.prefix(20))))
        #expect(!CLIToolTrust.matches(Self.digest, published: Self.digest + "0"))
        #expect(!CLIToolTrust.matches(String(Self.digest.prefix(20)), published: String(Self.digest.prefix(20))))
    }

    /// Developer ID and the Team ID — and no identifier, which for uv changes with
    /// every release.
    @Test func theRequirementNamesTheTeamAndNoIdentifier() {
        let requirement = CLIToolTrust.developerIDRequirement(teamIdentifier: "2DC432GLL2")
        #expect(requirement.contains("certificate leaf[subject.OU] = \"2DC432GLL2\""))
        #expect(requirement.contains("anchor apple generic"))
        #expect(!requirement.contains("identifier "))
    }

    /// A file that is not code at all has no signature to trust.
    @Test func aFileThatIsNotCodeIsNotTrusted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZZFixture-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tool")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: file)

        let signature = CLIToolTrust.signature(of: file, teamIdentifier: "2DC432GLL2")
        #expect(signature != .vendor)
        #expect(CLIToolTrust.matches(CLIToolTrust.sha256(of: file), published: CLIToolTrust.sha256(of: file)))
    }
}
