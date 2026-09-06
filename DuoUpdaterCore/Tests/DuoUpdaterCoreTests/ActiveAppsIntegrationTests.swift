import Foundation
import Testing
@testable import DuoUpdaterCore

/// Trimmed official API/appcast responses fetched 2026-09-06. Iterate the
/// registered channels so adding one cannot silently escape fixture coverage.
struct ActiveAppsIntegrationTests {
    @Test func releaseHistoriesRespectEveryRegisteredChannel() throws {
        for recipe in ChangelogRecipeRegistry.recipes where
            recipe.source.path == "/repos/mountain-loop/yaak/releases"
            || recipe.source.path == "/repos/coteditor/CotEditor/releases" {
            let isYaak = recipe.bundleID == "app.yaak.desktop"
            let fixture = isYaak ? yaakReleases : coteditorReleases
            let parsed = try #require(ChangelogService.parse(recipe, body: fixture))
            let stable = isYaak ? "2026.7.1" : "7.0.9"
            let beta = isYaak ? "2026.8.0-beta.1" : "7.1.0-beta.6"
            #expect(parsed.entries.first?.version == (recipe.channel == .stable ? stable : beta))
            #expect(parsed.entries.allSatisfy { !$0.items.isEmpty && $0.date != nil })
            if recipe.channel == .stable {
                #expect(!parsed.entries.contains { $0.version == beta })
                #expect(parsed.entries.first?.items.contains {
                    $0.contains(isYaak ? "Fix param edits" : "Avoid unnecessary scroll")
                } == true)
            } else {
                #expect(parsed.entries.contains { $0.version == stable } == recipe.includesPromotedStable)
            }
            // Unpublished notes must never appear, on either channel.
            let objects = try #require(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [[String: Any]])
            let drafts = objects.map { $0.merging(["draft": true]) { _, new in new } }
            let draftBody = String(decoding: try JSONSerialization.data(withJSONObject: drafts), as: UTF8.self)
            #expect(ChangelogService.parse(recipe, body: draftBody) == nil)
        }
    }

    @Test func yaakRulesSelectOnlyTheirOwnSignedMacArtifact() throws {
        let releases = try #require(JSONSerialization.jsonObject(with: Data(yaakReleases.utf8)) as? [[String: Any]])
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
            }
            #expect(VendorProbeRecipe.extractVersion(from: "v2026.8.0-beta.1-junk", pattern: rule.versionPattern) == nil)
        }
    }

    @Test func coteditorCatalogPreservesStableBetaAndOSGates() throws {
        let feed = try #require(SparkleFeedCatalog.feed(forBundleID: "com.coteditor.CotEditor"))
        #expect(feed.absoluteString == "https://coteditor.com/appcast.xml")
        let items = SparkleAppcastParser.parse(Data(coteditorAppcast.utf8), relativeTo: feed)
        for (version, build, expected) in [("7.0.8", "830", "7.0.9"), ("7.1.0-beta.6", "845", "7.1.0-beta.6")] {
            let channel = ReleaseChannel.detect(name: "CotEditor", bundleID: "com.coteditor.CotEditor", keystoneChannel: nil, version: version)
            let app = InstalledApp(name: "CotEditor", bundleID: "com.coteditor.CotEditor",
                shortVersion: version, buildVersion: build, path: URL(fileURLWithPath: "/fixture/CotEditor.app"),
                isMASApp: false, sparkleFeedURL: feed, releaseChannel: channel)
            let best = try #require(SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "27.0"))
            #expect(best.shortVersionString == expected)
            #expect(best.edSignature != nil)
            #expect(SparkleAppcastSource.bestItem(for: app, from: items, osVersion: "14.0")?.shortVersionString == "5.2.3")
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

private let coteditorReleases = #"""
[
  {
    "tag_name": "7.1.0-beta.6",
    "body": "system requirements: __macOS 26__ and later\r\n\r\n\r\n### Improvements\r\n\r\n- Apply the current theme’s text color to the text restored by undo even when the theme has changed since the deletion.\r\n- Remove the Bulgarian localization.\r\n- [beta] Reflect all changes in CotEditor 7.0.9.\r\n\r\n\r\n### Known Issues\r\n\r\n- In some cases, a sandboxed URL is passed when folder search results are dropped onto another app (FB23578716).\r\n- In full-screen mode, an unnecessary separator appears above the pane switcher in the Inspector (FB24552348).\r\n\r\n**Full Changelog**: https://github.com/coteditor/CotEditor/compare/7.1.0-beta.5...7.1.0-beta.6",
    "published_at": "2026-09-05T01:33:07Z",
    "prerelease": true,
    "draft": false,
    "assets": [
      {
        "name": "CotEditor_7.1.0-beta.6.dmg"
      }
    ]
  },
  {
    "tag_name": "7.0.9",
    "body": "system requirements: __macOS 15__ and later\r\n\r\n### Improvements\r\n\r\n- Avoid unnecessary scroll after inserting a snippet when the range is already visible.\r\n- Update the Markdown syntax to improve headings highlight.\r\n- Update tree-sitter-scala to 0.26.2.\r\n- [non-AppStore ver.] Update Sparkle from 2.9.5 to 2.9.6.\r\n\r\n\r\n### Fixes\r\n\r\n- Fix an issue in the regular expression replacement with the “Unescape replacement text” option where escaped backslashes in the replacement string were unexpectedly removed instead of being unescaped to literal backslashes.\r\n- Fix an issue in the LaTeX syntax where custom environment definitions were incorrectly extracted as outline items.\r\n- Fix an issue in the LaTeX syntax where the opening braces of arguments of some commands, such as `\\cite`, were highlighted in the wrong color.\r\n- Fix an issue in the Scala syntax where string interpolators, such as `s` in `s\"…\"`, were highlighted in the same color as the string body.\r\n- Fix typos in Dutch and French localizations.\r\n\r\n**Full Changelog**: https://github.com/coteditor/CotEditor/compare/7.0.8...7.0.9",
    "published_at": "2026-09-05T01:32:59Z",
    "prerelease": false,
    "draft": false,
    "assets": [
      {
        "name": "CotEditor_7.0.9.dmg"
      }
    ]
  }
]
"""#

private let coteditorAppcast = #"""
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
<item>
            <title>CotEditor 7.1.0-beta.6</title>
            <pubDate>Sat, 05 Sep 2026 10:26:56 +0900</pubDate>
            <sparkle:channel>prerelease</sparkle:channel>
            <sparkle:version>845</sparkle:version>
            <sparkle:shortVersionString>7.1.0-beta.6</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink xml:lang="en">https://coteditor.com/releasenotes/7.1.0-beta.en.html</sparkle:releaseNotesLink>
            <sparkle:releaseNotesLink xml:lang="ja">https://coteditor.com/releasenotes/7.1.0-beta.ja.html</sparkle:releaseNotesLink>
            <enclosure url="https://github.com/coteditor/CotEditor/releases/download/7.1.0-beta.6/CotEditor_7.1.0-beta.6.dmg" length="26458624" type="application/octet-stream" sparkle:edSignature="RbaJg/M9shdtcYkT0Z5gsd5OkZTTa1M8lVq2OAHoJuIHTWoKkxE8zcu0Qw10eRiuQ6Pq2SQdkpnnxvs9tlVuBA=="></enclosure>
        </item>
<item>
            <title>CotEditor 7.0.9</title>
            <pubDate>Sat, 05 Sep 2026 09:59:15 +0900</pubDate>
            <sparkle:version>843</sparkle:version>
            <sparkle:shortVersionString>7.0.9</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink xml:lang="en">https://coteditor.com/releasenotes/7.0.9.en.html</sparkle:releaseNotesLink>
            <sparkle:releaseNotesLink xml:lang="ja">https://coteditor.com/releasenotes/7.0.9.ja.html</sparkle:releaseNotesLink>
            <enclosure url="https://github.com/coteditor/CotEditor/releases/download/7.0.9/CotEditor_7.0.9.dmg" length="25609728" type="application/octet-stream" sparkle:edSignature="ck7WNGbpjxXaDls7GSePbZEFw6FIyPcHxk10HKKzU2a5OeUPVyJbO4v0tBd/Xv7ZnleRjd06wzVbYZAjN2sDAg=="/>
        </item>
<item>
            <title>CotEditor 5.2.3</title>
            <pubDate>Sat, 23 Aug 2025 17:28:00 +0900</pubDate>
            
            <sparkle:version>730</sparkle:version>
            <sparkle:shortVersionString>5.2.3</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink xml:lang="en">https://coteditor.com/releasenotes/5.2.3.en.html</sparkle:releaseNotesLink>
            <sparkle:releaseNotesLink xml:lang="ja">https://coteditor.com/releasenotes/5.2.3.ja.html</sparkle:releaseNotesLink>
            <enclosure url="https://github.com/coteditor/CotEditor/releases/download/5.2.3/CotEditor_5.2.3.dmg"
                       length="17555057"
                       type="application/octet-stream"
                        sparkle:edSignature="VceO3Okj5sPcnnIgk+EfB1w4/UU/g7LANyC360GPGTTtCdtnKfHrsjcjf2tE2xO8uaZl/6/EdMObEbqO5+GOAg=="/>
        </item>
</channel></rss>
"""#
