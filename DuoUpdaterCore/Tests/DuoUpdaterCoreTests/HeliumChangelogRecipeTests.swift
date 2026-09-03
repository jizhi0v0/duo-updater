import Testing
import Foundation
@testable import DuoUpdaterCore

/// Helium's release bodies are a hash dump followed by two fenced commit logs,
/// and the commit logs are the only change data the vendor publishes anywhere —
/// its Sparkle feed carries no notes and helium.computer has no changelog page.
/// So the recipe has to reach INTO the fences and leave the hashes alone, and it
/// must not show a build the app is not being offered: the vendor tags a release
/// as prerelease for a day or two before the appcast picks it up.
///
/// Fixture: three release objects from
/// `api.github.com/repos/imputnet/helium-macos/releases` (fetched 2026-09-03) —
/// 0.16.4.1, still flagged prerelease; 0.16.3.1, the version the appcast was
/// serving; and 0.15.3.1, whose commit log carries a quoted phrase. Their bodies
/// carry the two line endings this vendor really uses: `\n` on the prerelease,
/// `\r\n` on the stable releases.
@Suite struct HeliumChangelogRecipeTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.imput.helium"))
        return try #require(
            ChangelogExtractor.extract(from: heliumReleasesFixture, using: recipe))
    }

    @Test func readsTheCommitSubjectsFromBothRepos() throws {
        let newest = try #require(try changelog().entries.first)
        #expect(newest.version == "0.16.3.1")
        #expect(newest.date == "2026-09-02")
        #expect(newest.items.count == 9)
        // The hash is consumed, not shown: it is a link the pane cannot follow.
        #expect(newest.items.first
            == "sparkle: update to 2.9.6, build and use BinaryDelta directly (#340)")
        #expect(newest.items.last
            == "helium/core/sync/provider: add provider manifest declaration (#2384)")
    }

    /// The capture runs before the JSON unescape, so a subject containing `\"`
    /// gets cut at the backslash unless the pattern spans escapes. Five commit
    /// subjects in the current 40-release window do; this is one of them.
    @Test func aQuotedCommitSubjectIsNotTruncated() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains(
            "helium/settings: add GPC toggle, \"Security\" -> \"Network and security\""))
    }

    /// The `md5:`/`sha1:`/`sha256:` block sits in a fence of its own, immediately
    /// above the commit log. Nothing in it is a change.
    @Test func theChecksumBlockIsNotReadAsChanges() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(!items.contains { $0.hasPrefix("md5") || $0.hasPrefix("sha") })
        #expect(!items.contains { $0.contains("Cryptographic_hash_function") })
    }

    /// …and skipped for being a prerelease, not for being unreadable. Relaxing
    /// exactly that one gate — on the REGISTERED pattern, so this cannot drift
    /// from it — must surface the entry, or the test above is measuring the
    /// fixture rather than the recipe.
    ///
    /// That relaxed parse is also the only place an LF-only body is exercised:
    /// this vendor writes its prerelease bodies with bare `\n` and its stable
    /// ones with `\r\n`, and an item pattern that handles only the second reads
    /// an LF-only release as a release with no changes at all. Nothing else would
    /// notice — it is not a parse failure, just an entry that quietly vanishes.
    @Test func theStillUnreleasedPrereleaseIsSkippedForBeingUnreleased() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.imput.helium"))
        #expect(!(try changelog().entries.contains { $0.version == "0.16.4.1" }))

        let anyTrack = ChangelogRecipe(
            bundleID: recipe.bundleID,
            source: recipe.source,
            entryPattern: recipe.entryPattern.replacingOccurrences(
                of: #""prerelease"\s*:\s*false\s*,"#, with: #""prerelease"\s*:\s*\w+\s*,"#),
            itemPatterns: recipe.itemPatterns,
            mode: recipe.mode,
            maxEntries: recipe.maxEntries)
        #expect(anyTrack.entryPattern != recipe.entryPattern, "the gate moved; re-derive this")
        let relaxed = try #require(
            ChangelogExtractor.extract(from: heliumReleasesFixture, using: anyTrack))
        let prerelease = try #require(relaxed.entries.first { $0.version == "0.16.4.1" })
        #expect(prerelease.items.contains("update: helium 0.16.4.1 (#341)"))
    }

    /// Same as Headlamp's: this endpoint's whitespace is not ours to assume. See
    /// `HeadlampChangelogRecipeTests.bothJSONFormattingsParseTheSame`.
    @Test func bothJSONFormattingsParseTheSame() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.imput.helium"))
        #expect(ChangelogExtractor.extract(from: heliumReleasesPrettyFixture, using: recipe)
            == ChangelogExtractor.extract(from: heliumReleasesFixture, using: recipe))
    }
}

private let heliumReleasesFixture = #"""
[{"tag_name":"0.16.4.1","name":"0.16.4.1","draft":false,"prerelease":true,"created_at":"2026-09-02T19:13:35Z","published_at":"2026-09-03T04:25:37Z","assets":[{"name":"0.15.6.1-arm64.delta"}],"body":"## Helium macOS 0.16.4.1\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.4.1_arm64-macos.dmg`: \n\n```\nmd5: f49648c16ef12df18f20cce465a39440\nsha1: 2284397781c04d34b5a736f6f080c4b3b197a1d7\nsha256: 7c945dcbaca8151d2b2c287d438a7b46bcbe69a3d9d921db87d60cc35b4b8f6c\n```\n\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.4.1_x86_64-macos.dmg`: \n\n```\nmd5: 8cf8660f335c16f93459543e570d214b\nsha1: b9e9fb97312f959e585d4330a7f23a298d8b4eb4\nsha256: 170b4acf31b023f6ac9a7dbc3a52c0a66228f2860fa0da75bdd91ea35ba8fadf\n```\nChanges since last build:\n### helium-macos\n```\n9a4f092 update: helium 0.16.4.1 (#341)\n```\n\n### helium-chromium\n```\n00bb44b0 revision: bump to 4 (#2429)\nc4045414 merge: update to chromium 152.0.7977.75"},{"tag_name":"0.16.3.1","name":"0.16.3.1","draft":false,"prerelease":false,"created_at":"2026-09-01T21:15:44Z","published_at":"2026-09-02T01:20:49Z","assets":[{"name":"0.15.5.1-arm64.delta"}],"body":"## Helium macOS 0.16.3.1\r\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.3.1_arm64-macos.dmg`: \r\n\r\n```\r\nmd5: 641bb3626f2a245cafd4b132a5c94645\r\nsha1: 3ef700bc4448b338bbb15353cc1b3ab59ac9758a\r\nsha256: 4cc271d1305f08934d9500b672525ae5f9f5aa2ed49986d8bbc625a99bd83220\r\n```\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n3b00351 sparkle: update to 2.9.6, build and use BinaryDelta directly (#340)\r\n396158f update: helium 0.16.3.1 (#338)\r\n```\r\n\r\n### helium-chromium\r\n```\r\n6fb6afe4 revision: bump to 3 (#2420)\r\n867f7714 helium/core/sync/provider: make profile prefs provider-neutral (#2414)\r\n957eafc0 helium/core/sync/vault: use provider-neutral engine names (#2413)\r\n2337809a helium/ui: compact debugger warning, fix icon bubble margin (#2412)\r\n58927d6c helium/ui: compact extension debugger warning\r\n4ffbeff3 helium/ui/location-bar: fix trailing spacing in icon label bubble\r\ne0580f59 helium/core/sync/provider: add provider manifest declaration (#2384)\r\n```\r\n\r\n---\r\n\r\nSee [this GitHub Actions Run]() for the [Workflow file](/workflow) used as well as the build logs and artifacts\r\n"},{"tag_name":"0.15.3.1","name":"0.15.3.1","draft":false,"prerelease":false,"created_at":"2026-08-07T22:35:58Z","published_at":"2026-08-08T15:55:58Z","assets":[{"name":"0.14.7.1-arm64.delta"}],"body":"## Helium macOS 0.15.3.1\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n41a561f update: helium 0.15.3.1 (#318)\r\n```\r\n\r\n### helium-chromium\r\n```\r\n6212115c revision: bump to 3 (#2290)\r\n39d1887c helium/settings: remove new autofill pages (#2286)\r\nb51e059b helium/core: add global privacy control and network settings UI (#2284)\r\ndf7a0420 helium/settings: add GPC toggle, \"Security\" -> \"Network and security\"\r\n```\r\n"}]
"""#

/// The same three releases as above, as this endpoint also serves them.
private let heliumReleasesPrettyFixture = #"""
[
  {
    "tag_name": "0.16.4.1",
    "name": "0.16.4.1",
    "draft": false,
    "prerelease": true,
    "created_at": "2026-09-02T19:13:35Z",
    "published_at": "2026-09-03T04:25:37Z",
    "assets": [
      {
        "name": "0.15.6.1-arm64.delta"
      }
    ],
    "body": "## Helium macOS 0.16.4.1\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.4.1_arm64-macos.dmg`: \n\n```\nmd5: f49648c16ef12df18f20cce465a39440\nsha1: 2284397781c04d34b5a736f6f080c4b3b197a1d7\nsha256: 7c945dcbaca8151d2b2c287d438a7b46bcbe69a3d9d921db87d60cc35b4b8f6c\n```\n\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.4.1_x86_64-macos.dmg`: \n\n```\nmd5: 8cf8660f335c16f93459543e570d214b\nsha1: b9e9fb97312f959e585d4330a7f23a298d8b4eb4\nsha256: 170b4acf31b023f6ac9a7dbc3a52c0a66228f2860fa0da75bdd91ea35ba8fadf\n```\nChanges since last build:\n### helium-macos\n```\n9a4f092 update: helium 0.16.4.1 (#341)\n```\n\n### helium-chromium\n```\n00bb44b0 revision: bump to 4 (#2429)\nc4045414 merge: update to chromium 152.0.7977.75"
  },
  {
    "tag_name": "0.16.3.1",
    "name": "0.16.3.1",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-09-01T21:15:44Z",
    "published_at": "2026-09-02T01:20:49Z",
    "assets": [
      {
        "name": "0.15.5.1-arm64.delta"
      }
    ],
    "body": "## Helium macOS 0.16.3.1\r\n[Hashes](https://en.wikipedia.org/wiki/Cryptographic_hash_function) for the disk image `helium_0.16.3.1_arm64-macos.dmg`: \r\n\r\n```\r\nmd5: 641bb3626f2a245cafd4b132a5c94645\r\nsha1: 3ef700bc4448b338bbb15353cc1b3ab59ac9758a\r\nsha256: 4cc271d1305f08934d9500b672525ae5f9f5aa2ed49986d8bbc625a99bd83220\r\n```\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n3b00351 sparkle: update to 2.9.6, build and use BinaryDelta directly (#340)\r\n396158f update: helium 0.16.3.1 (#338)\r\n```\r\n\r\n### helium-chromium\r\n```\r\n6fb6afe4 revision: bump to 3 (#2420)\r\n867f7714 helium/core/sync/provider: make profile prefs provider-neutral (#2414)\r\n957eafc0 helium/core/sync/vault: use provider-neutral engine names (#2413)\r\n2337809a helium/ui: compact debugger warning, fix icon bubble margin (#2412)\r\n58927d6c helium/ui: compact extension debugger warning\r\n4ffbeff3 helium/ui/location-bar: fix trailing spacing in icon label bubble\r\ne0580f59 helium/core/sync/provider: add provider manifest declaration (#2384)\r\n```\r\n\r\n---\r\n\r\nSee [this GitHub Actions Run]() for the [Workflow file](/workflow) used as well as the build logs and artifacts\r\n"
  },
  {
    "tag_name": "0.15.3.1",
    "name": "0.15.3.1",
    "draft": false,
    "prerelease": false,
    "created_at": "2026-08-07T22:35:58Z",
    "published_at": "2026-08-08T15:55:58Z",
    "assets": [
      {
        "name": "0.14.7.1-arm64.delta"
      }
    ],
    "body": "## Helium macOS 0.15.3.1\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n41a561f update: helium 0.15.3.1 (#318)\r\n```\r\n\r\n### helium-chromium\r\n```\r\n6212115c revision: bump to 3 (#2290)\r\n39d1887c helium/settings: remove new autofill pages (#2286)\r\nb51e059b helium/core: add global privacy control and network settings UI (#2284)\r\ndf7a0420 helium/settings: add GPC toggle, \"Security\" -> \"Network and security\"\r\n```\r\n"
  }
]
"""#
