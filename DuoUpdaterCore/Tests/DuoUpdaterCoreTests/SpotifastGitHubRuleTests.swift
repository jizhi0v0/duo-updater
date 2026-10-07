import Foundation
import Testing

@testable import DuoUpdaterCore

/// Spotifast (`Recipes/rocks-spotifast-Spotifast.swift`), formerly Fastpotify.
///
/// v0.8.0–v0.9.1 shipped a `fastpotify-…` dmg beside the `spotifast-…` one, and
/// every app in them is still `me.paolino.fastpotify`; the new id's rule must
/// only ever take the `spotifast-` dmg. The old id's rule is detection-only.
@Suite struct SpotifastGitHubRuleTests {

    private static func rule(_ bundleID: String) -> GitHubReleaseRule? {
        GitHubReleaseRegistry.rules.first { $0.bundleID == bundleID }
    }

    @Test func ruleReadsTheBareTagAndTheSpotifastDmgOnly() throws {
        let rule = try #require(Self.rule("rocks.spotifast.Spotifast"))
        #expect(rule.owner == "crmne" && rule.repo == "spotifast")
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .dmg)
        let pattern = try #require(rule.installAssetPattern)
        func extract(_ tag: String) -> String? {
            VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
        }
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }

        #expect(extract("v0.12.0") == "0.12.0")
        #expect(extract("v0.5.0-rc2") == nil)

        #expect(matches("spotifast-v0.12.0-macos-universal.dmg"))
        // The rest of real release listings, the rename years included.
        #expect(!matches("fastpotify-v0.9.1-macos-universal.dmg"))
        #expect(!matches("spotifast-v0.12.0-x86_64-pc-windows-msvc-setup.exe"))
        #expect(!matches("spotifast-v0.12.0-x86_64-unknown-linux-gnu.tar.gz"))
        #expect(!matches("spotifast-v0.12.0-x86_64.flatpak"))
        #expect(!matches("spotifast-0.12.0-aarch64.AppImage"))
        #expect(!matches("spotifast-0.12.0-packaging.tar.xz"))
        #expect(!matches("spotifast-v0.12.0-source.tar.gz"))
    }

    /// The pre-rename id reads the same repo and never installs: the download is
    /// a different bundle id.
    @Test func thePreRenameIdIsDetectionOnly() throws {
        let rule = try #require(Self.rule("me.paolino.fastpotify"))
        #expect(rule.owner == "crmne" && rule.repo == "spotifast")
        #expect(rule.installAssetPattern == nil && rule.installerKind == nil)
        #expect(VendorProbeRecipe.extractVersion(from: "v0.12.0", pattern: rule.versionPattern) == "0.12.0")
        #expect(VendorProbeRecipe.extractVersion(from: "v0.5.0-rc2", pattern: rule.versionPattern) == nil)
    }
}
