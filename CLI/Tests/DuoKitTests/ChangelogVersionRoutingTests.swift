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

    /// Regression for #874. Blender's stable probe and its alpha track answer from
    /// two hosts the sweep runs concurrently, so either can come first. The
    /// channel-less changelog recipe must get the Stable version both ways: the
    /// alpha's 5.3.0 templates an unreleased notes page that has no entries.
    @Test func bareVersionPrefersStableWhateverTheOrder() {
        let bundleID = "org.blenderfoundation.blender"
        func finding(_ channel: String, _ version: String?) -> Finding {
            Finding(
                recipeID: "vendor:\(bundleID):\(channel)", registry: .vendor,
                bundleID: bundleID, channel: channel,
                status: version == nil ? .skipped : .ok, version: version,
                endpointHost: "example.org")
        }
        let stable = finding("stable", "5.2.2")
        let alpha = finding("alpha", "5.3.0")
        let beta = finding("beta", nil)

        for order in [[alpha, beta, stable], [stable, alpha, beta], [beta, alpha, stable]] {
            let versions = Verify.knownVersions(from: order)
            #expect(versions[bundleID] == "5.2.2")
            #expect(versions["\(bundleID):alpha"] == "5.3.0")
            #expect(versions["\(bundleID):beta"] == nil)
        }
        let recipe = ChangelogRecipeRegistry.recipes.first { $0.bundleID == bundleID }
        #expect(recipe?.channel == nil)
        #expect(recipe.flatMap {
            Verify.changelogVersion(for: $0, versions: Verify.knownVersions(from: [alpha, stable]))
        } == "5.2.2")
    }

    /// With no Stable source at all, a channel track still fills the bare key.
    @Test func bareVersionFallsBackToAChannelWhenNoStableSourceExists() {
        let bundleID = "org.blenderfoundation.blender"
        let alpha = Finding(
            recipeID: "vendor:\(bundleID):alpha", registry: .vendor,
            bundleID: bundleID, channel: "alpha", status: .ok, version: "5.3.0",
            endpointHost: "builder.blender.org")
        #expect(Verify.knownVersions(from: [alpha])[bundleID] == "5.3.0")
    }

    /// A Stable source that ran and failed leaves the bare key empty, so the
    /// installed Stable copy fills it rather than the live alpha answer.
    @Test func failedStableSourceDoesNotHandTheBareKeyToAChannel() {
        let bundleID = "org.blenderfoundation.blender"
        let alpha = Finding(
            recipeID: "vendor:\(bundleID):alpha", registry: .vendor,
            bundleID: bundleID, channel: "alpha", status: .ok, version: "5.3.0",
            endpointHost: "builder.blender.org")
        let stable = Finding(
            recipeID: "vendor:\(bundleID):stable", registry: .vendor,
            bundleID: bundleID, channel: "stable", status: .infra,
            endpointHost: "www.blender.org")
        let known = Verify.knownVersions(from: [alpha, stable])
        #expect(known[bundleID] == nil)
        #expect(known["\(bundleID):alpha"] == "5.3.0")

        let versions = Verify.changelogVersions(
            known: known,
            installed: ["vendor:\(bundleID):stable": InstalledVersion(
                marketing: "5.2.2", build: nil, vendorBuild: nil)])
        #expect(versions[bundleID] == "5.2.2")
    }

    /// The installed fallback is a dictionary, so its order is arbitrary too.
    @Test func installedFallbackPrefersStableForTheBareKey() {
        let bundleID = "org.blenderfoundation.blender"
        let installed = [
            "vendor:\(bundleID):alpha": InstalledVersion(
                marketing: "5.3.0", build: nil, vendorBuild: nil),
            "vendor:\(bundleID):stable": InstalledVersion(
                marketing: "5.2.2", build: nil, vendorBuild: nil),
        ]
        let versions = Verify.changelogVersions(known: [:], installed: installed)
        #expect(versions[bundleID] == "5.2.2")
        #expect(versions["\(bundleID):alpha"] == "5.3.0")

        // A live answer still beats every installed copy.
        let live = Verify.changelogVersions(known: [bundleID: "5.2.3"], installed: installed)
        #expect(live[bundleID] == "5.2.3")
    }
}
