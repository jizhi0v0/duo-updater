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

    /// Issue #1123: the newest stable, 0.19.2.1, publishes two EMPTY commit
    /// fences — its tag points at the same commit as the 0.19.1.2 prerelease cut
    /// just before it, and the vendor's log is "since last build". So the page
    /// tops out at 0.18.3.1 while the appcast serves 0.19.2.1, and the
    /// acknowledgement has to name exactly what the extractor reads off it:
    /// `duo verify` compares the two by exact string.
    @Test func theAcknowledgedStaleEntryIsWhatTheEmptyStableLeavesOnTop() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.imput.helium"))
        let log = try #require(
            ChangelogExtractor.extract(from: heliumEmptyStableFixture, using: recipe))
        #expect(log.entries.map(\.version) == ["0.18.3.1"])
        let newest = try #require(log.entries.first)
        #expect(newest.date == "2026-10-03")
        #expect(newest.items.count == 14)
        #expect(newest.items.first == "update: helium 0.18.3.1 (#389)")
        #expect(newest.items.last
            == "helium/core/sync/provider: require saved vault checkpoints (#2603)")
        #expect(recipe.acknowledgedStaleEntry == newest.version)
    }

    /// …and 0.19.2.1 drops out for having no commits, not for being unmatched (the
    /// `"immutable": true` key these releases now carry sits inside the span the
    /// entry pattern crosses). Give the registered pattern one more item pattern
    /// that reads the body's title line, and the release surfaces — with nothing
    /// borrowed from the prerelease below it.
    @Test func theEmptyStableIsMatchedAndHasNothingToShow() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "net.imput.helium"))
        let titled = ChangelogRecipe(
            bundleID: recipe.bundleID,
            source: recipe.source,
            entryPattern: recipe.entryPattern,
            itemPatterns: recipe.itemPatterns + [#"## Helium macOS (?<item>[0-9.]+)\\r\\n"#],
            mode: recipe.mode,
            maxEntries: recipe.maxEntries)
        let log = try #require(
            ChangelogExtractor.extract(from: heliumEmptyStableFixture, using: titled))
        #expect(log.entries.map(\.version) == ["0.19.2.1", "0.18.3.1"])
        #expect(log.entries.first?.items == ["0.19.2.1"])
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

/// Three release objects from the same endpoint, fetched 2026-10-11 and trimmed to
/// the keys the pattern crosses (assets to one name; bodies verbatim): 0.19.2.1,
/// stable with both commit fences empty; 0.19.1.2, the prerelease cut from the
/// same commit, which carries the 0.19 commits; 0.18.3.1, the stable before them.
private let heliumEmptyStableFixture = #"""
[{"tag_name":"0.19.2.1","name":"0.19.2.1","draft":false,"immutable":true,"prerelease":false,"created_at":"2026-10-08T19:06:38Z","published_at":"2026-10-09T00:03:02Z","assets":[{"name":"0.17.2.1-arm64.delta"}],"body":"## Helium macOS 0.19.2.1\r\nHashes for the disk image `helium_0.19.2.1_arm64-macos.dmg`: \r\n\r\n```\r\nmd5: 460841425dfc93767107277db6a96ac4\r\nsha1: 87d3cd348b58ca3064222709ee1549e758ce11e3\r\nsha256: c07dab9c1571cf68cf856b35c6d0bf21c2cf53f77c43245163018e788094ebf1\r\n```\r\n\r\nHashes for the disk image `helium_0.19.2.1_x86_64-macos.dmg`: \r\n\r\n```\r\nmd5: 6b25c1e7b0c63caeea0fb5190709d4bc\r\nsha1: 67e3cca98daeaccb28d6436472b0b27ed802e981\r\nsha256: a032da1664b0b5aad30b3d02ce31e194ef5333d3b148f33a8182404c70a7e109\r\n```\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n```\r\n\r\n### helium-chromium\r\n```\r\n```\r\n\r\n---\r\n\r\nSee [this GitHub Actions Run]() for the [Workflow file](/workflow) used as well as the build logs and artifacts\r\n"},{"tag_name":"0.19.1.2","name":"0.19.1.2","draft":false,"immutable":true,"prerelease":true,"created_at":"2026-10-08T19:06:38Z","published_at":"2026-10-08T23:16:48Z","assets":[{"name":"0.17.2.1-arm64.delta"}],"body":"## Helium macOS 0.19.1.2\nHashes for the disk image `helium_0.19.1.2_arm64-macos.dmg`: \n\n```\nmd5: e80266f6a5d9716f9f03528251249a3f\nsha1: cdf298c59273c1405e93155921db0394095e55a4\nsha256: 6c16d9f9df6bcab9867b1cd19807892714a84a7e68b0a495ca83d1c993835d4b\n```\n\nHashes for the disk image `helium_0.19.1.2_x86_64-macos.dmg`: \n\n```\nmd5: e2481cddd5cf9c0df0c45d5520a56c40\nsha1: 398724feba289271257c1f617f6a341c6a5c0918\nsha256: 203f1e3ba888c53da5cbb1e12c10d7e3a58b740b3a90ae60b9b3651b30add338\n```\nChanges since last build:\n### helium-macos\n```\n031c50a update: helium 0.19.1.2 (#394)\n17f9fcd update: helium 0.19.1.1 (#393)\n```\n\n### helium-chromium\n```\n8309d0e9 devutils/lists: exclude gsutil, fix deps download post-sub (#2660)\n11610d0e utils/deps: add depot_tools to PATH (#2657)\ne6893b9f merge: update to chromium 155.0.8059.39 (#2654)\nfa960220 revision: reset to 1\n5c590e4c helium/core/exclude-flags: update for chromium 155\na49467f6 utils/cipd: install llvm-libclang\n6cbf0650 patches: refresh for chromium 155.0.8059.39\nd0dccfe6 merge: update ungoogled-chromium to 155.0.8059.39\nffeb45a2 Update to Chromium 155.0.8059.39\n860a42de helium/core: disable foreground launch infobar on windows (#2634)\n3e46b138 CI: Prevent duplicate job runs on tag\nd5de20c8 CI: Better handling of clone tarballs\na15893df CI: Remove/rename old Cirrus files\n```\n\n---\n\nSee [this GitHub Actions Run]() for the [Workflow file](/workflow) used as well as the build logs and artifacts\n"},{"tag_name":"0.18.3.1","name":"0.18.3.1","draft":false,"immutable":true,"prerelease":false,"created_at":"2026-10-02T23:07:12Z","published_at":"2026-10-03T19:52:40Z","assets":[{"name":"0.17.1.1-arm64.delta"}],"body":"## Helium macOS 0.18.3.1\r\nHashes for the disk image `helium_0.18.3.1_arm64-macos.dmg`: \r\n\r\n```\r\nmd5: 14ace4c250a1f080c8f5f8ce2f2c1d26\r\nsha1: e95f51cabaafd087ae7aa0f0932cbe9a1187447f\r\nsha256: 49dca5ee476df8528d88c7d111c822f0eb4a1c0e487502eacd486477ea77aa05\r\n```\r\n\r\nHashes for the disk image `helium_0.18.3.1_x86_64-macos.dmg`: \r\n\r\n```\r\nmd5: ea6901fad160c13cce76ea2461b4977f\r\nsha1: a36256718e9bc6004be908fb47d5dcdc4d75b7bd\r\nsha256: d8861597e6901519d68a971c75878248f0dc73bfef912f4d4668872d5d0d7c9d\r\n```\r\nChanges since last build:\r\n### helium-macos\r\n```\r\n95911fb update: helium 0.18.3.1 (#389)\r\n```\r\n\r\n### helium-chromium\r\n```\r\n57a40ad8 revision: bump to 3 (#2632)\r\nb0e3abba helium/core: add tab context menu option to mute tab(s) (#2631)\r\n35b41387 helium/ui/layout: fix bugs introduced by overflow optimization (#2628)\r\n2f3f1262 helium/ui/vertical: fix toolbar re-layout after button visibility change\r\ncbd01b17 helium/ui/compact: drop tab strip layer on layout change\r\n8bd1a6b3 helium/core/sync: add private sync profile repository (#2604)\r\n70a38ebf merge: update to chromium 154.0.8037.97 (#2623)\r\n2aebde9c patches: refresh for chromium 154.0.8037.97\r\n7853f57c merge: update ungoogled-chromium to 154.0.8037.97\r\n37085e47 Update to Chromium 154.0.8037.97\r\ndfd7c502 Update to Chromium 154.0.8037.92\r\n790ea617 helium/core/sync: distinguish local, custom, and disabled backends (#2600)\r\n07a82e8b helium/core/sync/provider: require saved vault checkpoints (#2603)\r\n```\r\n\r\n---\r\n\r\nSee [this GitHub Actions Run]() for the [Workflow file](/workflow) used as well as the build logs and artifacts\r\n"}]
"""#
