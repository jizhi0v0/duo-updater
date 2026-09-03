import Testing
import DuoUpdaterCore

@testable import DuoKit

@Suite struct ChangelogVersionRoutingTests {

    /// Regression for the issue #191 reproduction command. A changelog-only sweep
    /// has no freshly probed versions, so its installed fallback must retain the
    /// release channel instead of trying every templated recipe with one bare version.
    @Test func installedFallbackKeepsTheReleaseChannel() {
        let bundleID = "com.tencent.wechatdevtools"
        let installed = [
            "vendor:\(bundleID):stable": InstalledVersion(
                marketing: "2.02.2608060", build: nil, vendorBuild: nil),
            "vendor:\(bundleID):nightly": InstalledVersion(
                marketing: "2.02.2609022", build: nil, vendorBuild: nil),
        ]

        let versions = Verify.changelogVersions(known: [:], installed: installed)

        #expect(versions["\(bundleID):stable"] == "2.02.2608060")
        #expect(versions["\(bundleID):nightly"] == "2.02.2609022")
        #expect(Set(versions.values).contains("2.02.2608060"))
        #expect(Set(versions.values).contains("2.02.2609022"))
    }

    /// A bare Stable fallback must not be reused for sibling channel recipes.
    /// This is what made the issue's `--changelog` reproduction command fabricate
    /// 404s for the RC and Nightly URL templates on a machine with Stable installed.
    @Test func channelRecipeNeverFallsBackToABareSiblingVersion() throws {
        let bundleID = "com.tencent.wechatdevtools"
        let recipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == bundleID }
        let versions = [
            bundleID: "2.02.2608060",
            "\(bundleID):stable": "2.02.2608060",
        ]

        for recipe in recipes {
            let version = Verify.changelogVersion(for: recipe, versions: versions)
            if recipe.channel == .stable {
                #expect(version == "2.02.2608060")
            } else {
                #expect(version == nil)
            }
        }
    }

    /// Live probe answers are newer evidence than the local scan and must not be
    /// overwritten when a full sweep has both.
    @Test func knownChannelVersionWinsOverInstalledFallback() {
        let bundleID = "com.tencent.wechatdevtools"
        let key = "\(bundleID):nightly"
        let versions = Verify.changelogVersions(
            known: [key: "2.02.2609032"],
            installed: [
                "vendor:\(key)": InstalledVersion(
                    marketing: "2.02.2609022", build: nil, vendorBuild: nil),
            ])

        #expect(versions[key] == "2.02.2609032")
    }
}
