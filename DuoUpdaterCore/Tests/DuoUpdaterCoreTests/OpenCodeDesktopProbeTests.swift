import Testing
import Foundation
@testable import DuoUpdaterCore

/// OpenCode Desktop's move to the vendor's own update channel with 2.0: a 1.x
/// bundle's `app-update.yml` still says `provider: github`, so only a probe of
/// `https://opencode.ai/update/api/latest/desktop/opencode/` can show a 1.x
/// install that 2.x exists. The feed is electron-updater's `latest-mac.yml`
/// (2.2.5, captured 2026-10-31, trimmed to the entries the recipe reads —
/// `<arch>.zip` and `.dmg` for both architectures, in the vendor's order).
private let feedFixture = #"""
files:
  - url: https://opencode.ai/files/bin/2.2.5/opencode-desktop-mac-arm64.zip
    sha512: GHcgqB/Wb5P2c71ZIMsVG3ZF79ZPvEfVOsbyHF+1h4Oh3+Hz5rHudLooTw/NW5V+ugBrHnXPINt1LBMy/5ifLQ==
    size: 298567019
  - url: https://opencode.ai/files/bin/2.2.5/opencode-desktop-mac-arm64.dmg
    sha512: yPqDeFY7BqcgmQz8LHrLdyq02qYo/FMAGHEHAxmpPUl00yE/C1awLKiL9lBAbvsQBEtMhArmXN7niVVGRXm0RQ==
    size: 329627154
  - url: https://opencode.ai/files/bin/2.2.5/opencode-desktop-mac-x64.dmg
    sha512: SmesA5wZ6eDM3YrfEozRLWugNLnrzYaOf7gM5H/bKSd6u8gyUjeAIcamzppngrdl746PbnNHwtEVtP8dQpiMxw==
    size: 344196662
releaseDate: 2026-10-30T23:06:23.000Z
version: 2.2.5
"""#

struct OpenCodeDesktopProbeTests {

    static let bundleID = "ai.opencode.desktop"

    /// The installed 1.x bundle this recipe has to move: read off
    /// `/Applications/OpenCode.app` on 2026-10-31.
    static let installedVersion = "1.19.4"

    static func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == bundleID },
                     "no OpenCode Desktop recipe in the registry")
    }

    // MARK: - registry shape

    /// One stable recipe, on the channel a 2.x bundle declares for itself, and no
    /// GitHub rule beside it: GitHub answers before a probe, so the rule this
    /// family used to carry is exactly what kept 2.x invisible.
    ///
    /// Mutation: put the `GitHubReleaseRule` back — the probe stops running and
    /// the app goes back to resolving 1.19.5.
    @Test func registersOneProbeAndNoGitHubRule() throws {
        let all = VendorProbeRegistry.recipes.filter { $0.bundleID == Self.bundleID }
        #expect(all.count == 1)
        #expect(GitHubReleaseRegistry.rules.contains { $0.bundleID == Self.bundleID } == false)

        let recipe = try Self.recipe()
        #expect(recipe.channel == .stable)
        #expect(recipe.variant == nil)
        #expect(recipe.url.absoluteString == "https://opencode.ai/update/api/latest/desktop/opencode/latest-mac.yml")
        #expect(recipe.url.scheme == "https")
        // The feed is a manifest, not something a person reads: the user's link is
        // the download page.
        #expect(recipe.downloadURL?.absoluteString == "https://opencode.ai/download")
        #expect(recipe.downloadURL != recipe.url)
        // Notes come from the family's `ChangelogRecipe` (the GitHub releases), so
        // the pane is not sent to an embedded page as well.
        #expect(recipe.changelogURL == nil)
        #expect(recipe.install?.kind == .dmg)
        // No `hostRequirement`: the dmg this resolves is arm64, and every host
        // DuoUpdater runs on is arm64 (`App/project.yml`), so a gate here would
        // only hide the recipe from `duo verify` on a runner that could still
        // check it.
        #expect(recipe.hostRequirement == nil)
    }

    // MARK: - the version

    @Test func readsTheManifestsOwnVersion() throws {
        let recipe = try Self.recipe()
        #expect(VendorProbeRecipe.extractVersion(from: feedFixture, pattern: recipe.versionPattern) == "2.2.5")
        // Above what the 1.x install reports: that comparison is the whole update.
        #expect(VersionComparator.compare(Self.installedVersion, "2.2.5") == .orderedAscending)
    }

    /// The artifact paths carry a version too; the pattern must read the
    /// document's own field, so a manifest whose files point at another release
    /// (the next one, still uploading) still answers with the one it declares.
    /// Mutation: loosen the pattern to `version` anywhere — it then reads the
    /// directory segment of the first artifact.
    @Test func theVersionIsTheDocumentsFieldNotAnArtifactPath() throws {
        let recipe = try Self.recipe()
        let body = feedFixture.replacingOccurrences(of: "version: 2.2.5", with: "version: 2.3.0")
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == "2.3.0")
        // A manifest with no top-level `version:` is not an answer.
        let without = feedFixture.replacingOccurrences(of: "version: 2.2.5", with: "")
        #expect(VendorProbeRecipe.extractVersion(from: without, pattern: recipe.versionPattern) == nil)
    }

    // MARK: - the install

    static func installPatterns() throws -> (url: String, checksum: String) {
        let spec = try #require(try recipe().install)
        guard case .bodyPattern(let url) = spec.urlSource else {
            Issue.record("OpenCode Desktop's install is no longer a body pattern")
            throw CancellationError()
        }
        return (url, try #require(spec.checksumPattern))
    }

    /// The arm64 dmg, not the arm64 zip listed above it and not either x64 file:
    /// the zip is what electron-updater consumes, and `kind: .dmg` would hand a
    /// zip to the mounter.
    @Test func resolvesTheArm64DMG() throws {
        let (pattern, _) = try Self.installPatterns()
        #expect(VendorProbeRecipe.extractVersion(from: feedFixture, pattern: pattern)
            == "https://opencode.ai/files/bin/2.2.5/opencode-desktop-mac-arm64.dmg")
        // Only zips (a release whose dmgs are still uploading): nothing to install.
        let zips = feedFixture.replacingOccurrences(of: "opencode-desktop-mac-arm64.dmg", with: "opencode-desktop-mac-arm64.zip")
            .replacingOccurrences(of: "opencode-desktop-mac-x64.dmg", with: "opencode-desktop-mac-x64.zip")
        #expect(VendorProbeRecipe.extractVersion(from: zips, pattern: pattern) == nil)
    }

    /// The digest beside the same entry, which is the vendor's own SHA-512 of the
    /// dmg: 2.2.5's file hashes to it (checked on the real download 2026-10-31).
    @Test func theChecksumIsThatEntrysOwnSHA512() throws {
        let (_, checksum) = try Self.installPatterns()
        #expect(VendorProbeRecipe.extractVersion(from: feedFixture, pattern: checksum)
            == "yPqDeFY7BqcgmQz8LHrLdyq02qYo/FMAGHEHAxmpPUl00yE/C1awLKiL9lBAbvsQBEtMhArmXN7niVVGRXm0RQ==")
        // Anchored to the dmg entry: the zip above it names a different digest, and
        // a body holding only zips has none to offer.
        #expect(VendorProbeRecipe.extractVersion(from: feedFixture, pattern: checksum) !=
                "GHcgqB/Wb5P2c71ZIMsVG3ZF79ZPvEfVOsbyHF+1h4Oh3+Hz5rHudLooTw/NW5V+ugBrHnXPINt1LBMy/5ifLQ==")
        let zips = feedFixture.replacingOccurrences(of: "opencode-desktop-mac-arm64.dmg", with: "opencode-desktop-mac-arm64.zip")
        #expect(VendorProbeRecipe.extractVersion(from: zips, pattern: checksum) == nil)
    }
}
