import Foundation
import Testing

@testable import DuoUpdaterCore

/// Herdr (`Recipes/so-pen-herdr-gpui.swift`): date-versioned tags and a dmg
/// among a release listing full of signature siblings and updater payloads.
@Suite struct HerdrGitHubRuleTests {

    @Test func ruleReadsTheDateTagAndTheDmgOnly() throws {
        let rule = try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "so.pen.herdr-gpui" })
        #expect(rule.owner == "penso" && rule.repo == "herdr-gpui")
        #expect(rule.channel == .stable && !rule.usePrereleases)
        #expect(rule.installerKind == .dmg)
        let pattern = try #require(rule.installAssetPattern)
        func matches(_ name: String) -> Bool {
            name.range(of: pattern, options: .regularExpression) != nil
        }

        #expect(VendorProbeRecipe.extractVersion(from: "v20261007.2", pattern: rule.versionPattern) == "20261007.2")
        #expect(VendorProbeRecipe.extractVersion(from: "v20261007.2-rc.1", pattern: rule.versionPattern) == nil)

        #expect(matches("Herdr-20261007.2-universal-apple-darwin.dmg"))
        // The rest of the real v20261007.2 listing's macOS-looking names.
        #expect(!matches("Herdr-20261007.2-universal-apple-darwin.dmg.sha256"))
        #expect(!matches("Herdr-20261007.2-universal-apple-darwin.dmg.sig"))
        #expect(!matches("herdr-gpui-20261007.2-macos-universal.app.tar.gz"))
        #expect(!matches("update-manifest.json"))
        #expect(!matches("Herdr-20261007.2-x86_64-pc-windows-msvc.zip"))
    }

    /// The daily counter is compared as a number, so a tenth release in a day
    /// still reads as newer than the ninth.
    @Test func dateVersionsCompareNumerically() {
        #expect(VersionComparator.compare("20261007.2", "20261007.1") == .orderedDescending)
        #expect(VersionComparator.compare("20261007.10", "20261007.9") == .orderedDescending)
        #expect(VersionComparator.compare("20261008.1", "20261007.9") == .orderedDescending)
    }
}
