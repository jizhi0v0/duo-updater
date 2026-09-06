import Foundation
import Testing
@testable import DuoUpdaterCore

/// Trimmed official GitHub API responses for Yaak, fetched 2026-09-06. Every
/// case is driven off the registry rather than a hand-written list, so adding a
/// channel cannot silently escape fixture coverage — and each loop asserts how
/// many rows it saw, because a `for … where` over a registry is green when the
/// registry entry it is meant to protect has been deleted.
struct ActiveAppsIntegrationTests {
    /// Both halves of what makes the beta rule a beta rule, asserted against the
    /// registry rather than restated. Deleting either Yaak rule fails here, which
    /// nothing else in the suite does: measured 2026-09-06 by removing the stable
    /// rule and running the whole Core package — 2335 tests, all green.
    @Test func bothYaakRulesAreRegisteredAndSplitTheTrains() throws {
        let rules = GitHubReleaseRegistry.rules.filter { $0.bundleID == "app.yaak.desktop" }
        #expect(rules.count == 2)
        let stable = try #require(rules.first { $0.channel == .stable })
        let beta = try #require(rules.first { $0.channel == .beta })
        #expect(stable.usePrereleases == false)
        #expect(beta.usePrereleases)
        for rule in rules { #expect(rule.owner == "mountain-loop" && rule.repo == "yaak") }
    }

    /// The premise the whole beta track rests on: a Yaak beta bundle keeps the
    /// `-beta.N` suffix in `CFBundleShortVersionString`, and `detect` has to read
    /// that as `.beta` or the channel gate in `GitHubReleasesSource` hands a beta
    /// copy the stable rule's DMG. Asserted directly, because reaching it through
    /// an `InstalledApp` does not: `channelIsAuthoritative` defaults to false, so
    /// the Sparkle path never reads `releaseChannel` and a test that builds one
    /// passes just as well with `.stable` written in by hand (measured).
    @Test func aBetaVersionStringResolvesToTheBetaChannel() {
        func detect(_ version: String) -> ReleaseChannel {
            ReleaseChannel.detect(name: "Yaak", bundleID: "app.yaak.desktop",
                keystoneChannel: nil, version: version)
        }
        #expect(detect("2026.8.0-beta.1") == .beta)
        #expect(detect("2026.7.1") == .stable)
    }

    @Test func releaseHistoriesRespectEveryRegisteredChannel() throws {
        let recipes = ChangelogRecipeRegistry.recipes.filter { $0.bundleID == "app.yaak.desktop" }
        #expect(recipes.count == 2, "one rail per channel; a deleted recipe must not read as coverage")
        var seen: Set<ReleaseChannel> = []
        for recipe in recipes {
            seen.insert(recipe.channel ?? .stable)
            #expect(recipe.source.path == "/repos/mountain-loop/yaak/releases")
            let parsed = try #require(ChangelogService.parse(recipe, body: yaakReleases))
            let stable = "2026.7.1"
            let beta = "2026.8.0-beta.1"
            #expect(parsed.entries.first?.version == (recipe.channel == .stable ? stable : beta))
            #expect(parsed.entries.allSatisfy { !$0.items.isEmpty && $0.date != nil })
            if recipe.channel == .stable {
                #expect(!parsed.entries.contains { $0.version == beta })
                #expect(parsed.entries.first?.items.contains { $0.contains("Fix param edits") } == true)
            } else {
                // See the recipe's comment: the beta rule can only ever resolve a
                // `-beta.N` artifact, so its notes must not advertise the stable
                // release it graduates into. Asserted as a literal — reading the
                // flag off the recipe under test would self-adjust to whatever
                // value someone wrote there.
                #expect(recipe.includesPromotedStable == false)
                #expect(!parsed.entries.contains { $0.version == stable })
            }
            // Unpublished notes must never appear, on either channel.
            let objects = try #require(JSONSerialization.jsonObject(with: Data(yaakReleases.utf8)) as? [[String: Any]])
            let drafts = objects.map { $0.merging(["draft": true]) { _, new in new } }
            let draftBody = String(decoding: try JSONSerialization.data(withJSONObject: drafts), as: UTF8.self)
            #expect(ChangelogService.parse(recipe, body: draftBody) == nil)
        }
        #expect(seen == [.stable, .beta])
    }

    @Test func yaakRulesSelectOnlyTheirOwnSignedMacArtifact() throws {
        let releases = try #require(JSONSerialization.jsonObject(with: Data(yaakReleases.utf8)) as? [[String: Any]])
        #expect(releases.count == 2, "one release per train, or the loop below proves nothing")
        var checked = 0
        for rule in GitHubReleaseRegistry.rules where rule.bundleID == "app.yaak.desktop" {
            let pattern = try #require(rule.installAssetPattern)
            #expect(rule.installerKind == .dmg)
            for release in releases {
                let tag = try #require(release["tag_name"] as? String)
                let beta = try #require(release["prerelease"] as? Bool)
                let version = VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern)
                #expect((version != nil) == (beta == (rule.channel == .beta)))
                let assets = try #require(release["assets"] as? [[String: Any]])
                let matching = assets.compactMap { $0["name"] as? String }.filter {
                    $0.range(of: pattern, options: .regularExpression) != nil
                }
                #expect(matching.count == (version == nil ? 0 : 1))
                if let name = matching.first {
                    #expect(name.hasSuffix("_aarch64.dmg"))
                }
                checked += 1
            }
            #expect(VendorProbeRecipe.extractVersion(from: "v2026.8.0-beta.1-junk", pattern: rule.versionPattern) == nil)
        }
        #expect(checked == 4, "two rules x two releases")
    }

    /// The vendor renamed its macOS artifact, and the patterns are pinned to the
    /// name in use now. Measured over the newest 100 releases on 2026-09-06: the
    /// 92 at or newer than `v2025.9.0-beta.5` (2025-11-11) publish
    /// `Yaak_<version>_aarch64.dmg`; the 8 before it published
    /// `Yaak_<version>_aarch64_darwin.dmg`, which neither pattern accepts. That
    /// is inert — both rules resolve newest-first and the beta rule reads a
    /// 20-row page — but it is the boundary, and a vendor who reverted the name
    /// would take both trains out at once rather than one.
    @Test func theSupersededDarwinSuffixIsNotAccepted() throws {
        for rule in GitHubReleaseRegistry.rules where rule.bundleID == "app.yaak.desktop" {
            let pattern = try #require(rule.installAssetPattern)
            let old = rule.channel == .beta
                ? "Yaak_2025.9.0-beta.4_aarch64_darwin.dmg"
                : "Yaak_2025.8.2_aarch64_darwin.dmg"
            #expect(old.range(of: pattern, options: .regularExpression) == nil)
        }
    }
}

private let yaakReleases = #"""
[
  {
    "tag_name": "v2026.8.0-beta.1",
    "body": "\n### 🎁 New\n\n- 🔄 Import into Existing Workspaces ([#618](https://github.com/mountain-loop/yaak/pull/618), [feedback](https://yaak.app/feedback/posts/update-current-workspace-during-import))\n- Preview imports and choose their destination before anything is applied ([#571](https://github.com/mountain-loop/yaak/pull/571))\n- Generate an example gRPC message from the method schema ([#613](https://github.com/mountain-loop/yaak/pull/613), [feedback](https://yaak.app/feedback/posts/grpc-message-example-from-proto))\n\n### 💄 Improved\n\n- Faster search match counting in large responses ([#612](https://github.com/mountain-loop/yaak/pull/612), [feedback](https://yaak.app/feedback/posts/improve-search-performance-for-large-responses))\n- Windows open faster by not waiting for the plugin runtime to boot ([#616](https://github.com/mountain-loop/yaak/pull/616))\n\n### 🛠️ Fixed\n\n- Disable macOS Writing Tools suggestions inside editors\n- Remove the broken Refresh item from the gRPC method picker\n\n<!-- generated-by-yaak-releases -->\n",
    "published_at": "2026-09-01T19:14:18Z",
    "prerelease": true,
    "draft": false,
    "assets": [
      {
        "name": "latest.json"
      },
      {
        "name": "yaak-2026.8.0-beta.1-1.aarch64.rpm"
      },
      {
        "name": "yaak-2026.8.0-beta.1-1.aarch64.rpm.sig"
      },
      {
        "name": "yaak-2026.8.0-beta.1-1.x86_64.rpm"
      },
      {
        "name": "yaak-2026.8.0-beta.1-1.x86_64.rpm.sig"
      },
      {
        "name": "yaak-cef_2026.8.0-beta.1_amd64.deb"
      },
      {
        "name": "yaak-cef_2026.8.0-beta.1_arm64.deb"
      },
      {
        "name": "yaak-cef_2026.8.0-beta.1_linux_arm64.tar.gz"
      },
      {
        "name": "yaak-cef_2026.8.0-beta.1_linux_x64.tar.gz"
      },
      {
        "name": "yaak_2026.8.0-beta.1_aarch64.AppImage"
      },
      {
        "name": "yaak_2026.8.0-beta.1_aarch64.AppImage.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_aarch64.dmg"
      },
      {
        "name": "yaak_2026.8.0-beta.1_amd64.AppImage"
      },
      {
        "name": "yaak_2026.8.0-beta.1_amd64.AppImage.sig"
      },
      {
        "name": "yaak_2026.8.0-beta.1_amd64.deb"
      },
      {
        "name": "yaak_2026.8.0-beta.1_amd64.deb.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_arm64-setup-machine.exe"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_arm64-setup-machine.exe.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_arm64-setup.exe"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_arm64-setup.exe.sig"
      },
      {
        "name": "yaak_2026.8.0-beta.1_arm64.deb"
      },
      {
        "name": "yaak_2026.8.0-beta.1_arm64.deb.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_x64-setup-machine.exe"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_x64-setup-machine.exe.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_x64-setup.exe"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_x64-setup.exe.sig"
      },
      {
        "name": "Yaak_2026.8.0-beta.1_x64.dmg"
      },
      {
        "name": "Yaak_aarch64.app.tar.gz"
      },
      {
        "name": "Yaak_aarch64.app.tar.gz.sig"
      },
      {
        "name": "Yaak_x64.app.tar.gz"
      },
      {
        "name": "Yaak_x64.app.tar.gz.sig"
      }
    ]
  },
  {
    "tag_name": "v2026.7.1",
    "body": "Full changelog: https://yaak.app/changelog/2026.7.1\n\n### 🛠️ Fixed\n\n- Fix param edits from one request appearing on its duplicate when switching between them ([#617](https://github.com/mountain-loop/yaak/pull/617), [feedback](https://yaak.app/feedback/posts/if-i-duplicate-request-and-modify-one-the-other-one-gets-modified-as-well))\n\n<!-- generated-by-yaak-releases -->\n",
    "published_at": "2026-09-01T17:00:59Z",
    "prerelease": false,
    "draft": false,
    "assets": [
      {
        "name": "latest.json"
      },
      {
        "name": "yaak-2026.7.1-1.aarch64.rpm"
      },
      {
        "name": "yaak-2026.7.1-1.aarch64.rpm.sig"
      },
      {
        "name": "yaak-2026.7.1-1.x86_64.rpm"
      },
      {
        "name": "yaak-2026.7.1-1.x86_64.rpm.sig"
      },
      {
        "name": "yaak-cef_2026.7.1_amd64.deb"
      },
      {
        "name": "yaak-cef_2026.7.1_arm64.deb"
      },
      {
        "name": "yaak-cef_2026.7.1_linux_arm64.tar.gz"
      },
      {
        "name": "yaak-cef_2026.7.1_linux_x64.tar.gz"
      },
      {
        "name": "yaak_2026.7.1_aarch64.AppImage"
      },
      {
        "name": "yaak_2026.7.1_aarch64.AppImage.sig"
      },
      {
        "name": "Yaak_2026.7.1_aarch64.dmg"
      },
      {
        "name": "yaak_2026.7.1_amd64.AppImage"
      },
      {
        "name": "yaak_2026.7.1_amd64.AppImage.sig"
      },
      {
        "name": "yaak_2026.7.1_amd64.deb"
      },
      {
        "name": "yaak_2026.7.1_amd64.deb.sig"
      },
      {
        "name": "Yaak_2026.7.1_arm64-setup-machine.exe"
      },
      {
        "name": "Yaak_2026.7.1_arm64-setup-machine.exe.sig"
      },
      {
        "name": "Yaak_2026.7.1_arm64-setup.exe"
      },
      {
        "name": "Yaak_2026.7.1_arm64-setup.exe.sig"
      },
      {
        "name": "yaak_2026.7.1_arm64.deb"
      },
      {
        "name": "yaak_2026.7.1_arm64.deb.sig"
      },
      {
        "name": "Yaak_2026.7.1_x64-setup-machine.exe"
      },
      {
        "name": "Yaak_2026.7.1_x64-setup-machine.exe.sig"
      },
      {
        "name": "Yaak_2026.7.1_x64-setup.exe"
      },
      {
        "name": "Yaak_2026.7.1_x64-setup.exe.sig"
      },
      {
        "name": "Yaak_2026.7.1_x64.dmg"
      },
      {
        "name": "Yaak_aarch64.app.tar.gz"
      },
      {
        "name": "Yaak_aarch64.app.tar.gz.sig"
      },
      {
        "name": "Yaak_x64.app.tar.gz"
      },
      {
        "name": "Yaak_x64.app.tar.gz.sig"
      }
    ]
  }
]
"""#

