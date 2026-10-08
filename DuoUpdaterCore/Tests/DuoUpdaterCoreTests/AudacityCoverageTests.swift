import Foundation
import Testing
@testable import DuoUpdaterCore

/// Audacity 3, Audacity 4 and the 4.0 alpha/beta id
/// (`Recipes/org-audacityteam-audacity.swift`).
///
/// Three bundle ids read one Releases list, so every test here is about a train
/// reading only its own rows of it, and about the prerelease id — the 3.x id in
/// another case — never being handed Audacity 3's notes.
@Suite struct AudacityCoverageTests {

    static let threeID = "org.audacityteam.audacity"
    static let fourID = "org.audacityteam.audacity4"
    static let prereleaseID = "org.audacityteam.Audacity"

    /// `api.github.com/repos/audacity/audacity/releases`, fetched 2026-10-08:
    /// eight of the real rows in their real order, flags, dates, macOS asset
    /// names, sizes and digests. Bodies are trimmed to real lines of each.
    static let releasesJSON = ##"""
    [
    {"tag_name":"Audacity-4.0.1","name":"Audacity-4.0.1","draft":false,"prerelease":false,"published_at":"2026-09-30T11:59:48Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-4.0.1","body":"# Audacity 4.0.1 release notes\n\nMany of these fixes come from community contributors. Thank you all!\n\n## Features\n\n- Export multiple: export each track, or each labelled region, to its own file (#11136)\n- Liquid Glass app icon on macOS (#11923, by @JoshBashed)\n\n## Bug fixes\n\n- Fixed project corruption after a failed save (#12296)\n- Fixed opening files dropped on the macOS Dock icon (#11961)\n","assets":[{"name":"audacity-macOS-4.0.1-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.1/audacity-macOS-4.0.1-arm64.dmg","size":50034126,"digest":"sha256:278c8647b78c77af7f07dbd5e7d9bfc950bc14168047b65738716b61d12055ec"},{"name":"audacity-macOS-4.0.1-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.1/audacity-macOS-4.0.1-universal.dmg","size":92003045,"digest":"sha256:473db7ce0d846d2d45df97e8e83ff4c70fc835eff6bcc9e119d8eac34f979794"},{"name":"audacity-macOS-4.0.1-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.1/audacity-macOS-4.0.1-x86_64.dmg","size":54321871,"digest":"sha256:9794b0b3a3a795bdc097b411a5776ba59dc451cb1524f58c9714c30cca2564be"}]},
    {"tag_name":"Audacity-4.0.0","name":"","draft":false,"prerelease":false,"published_at":"2026-09-03T10:19:48Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-4.0.0","body":"## Audacity 4.0\n\nAudacity 4 rebuilds the application interface on Qt and introduces many new quality-of-life improvements, including a new clip-editing model.\n\n## Editing clips\n\n- **Clips can be grouped.** Groups remain together when moved, copied, pasted or duplicated.\n\n## Projects, import and export\n\n- Audacity 4 uses the new **`.aup4` project format**.\n","assets":[{"name":"audacity-macOS-4.0.0-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0/audacity-macOS-4.0.0-arm64.dmg","size":46806707,"digest":"sha256:266201f3151b09e46a5ab8e0ce1a16cefdd53a66fc7c979e943b2c88d6500c51"},{"name":"audacity-macOS-4.0.0-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0/audacity-macOS-4.0.0-universal.dmg","size":89186652,"digest":"sha256:03bdb378bc333695af8cba1ff0b91775cf17961a6f23a34edc6a94e3ca7c85ab"},{"name":"audacity-macOS-4.0.0-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0/audacity-macOS-4.0.0-x86_64.dmg","size":51096331,"digest":"sha256:4a5edd087bd5078aa2cd4e93c085a1172c9d791533c96b416a36bd82838a868b"}]},
    {"tag_name":"Audacity-3.7.9","name":"Audacity 3.7.9","draft":false,"prerelease":false,"published_at":"2026-09-01T15:05:46Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-3.7.9","body":"This is a patch release. It contains the following changes:\r\n\r\n   * #11690 Enabled ASIO support for the Windows builds, playback and recording device selection is remembered per-host now\r\n   * #11679 Added FFmpeg 9 support\r\n   * #11711 Fixed a crash after a failed recording attempt\r\n\r\n**Full Changelog**: https://github.com/audacity/audacity/compare/Audacity-3.7.8...Audacity-3.7.9","assets":[{"name":"audacity-macOS-3.7.9-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.9/audacity-macOS-3.7.9-arm64.dmg","size":31370830,"digest":"sha256:fafeb7fa963d3e2ba05ee7aba5290c966362ac5f5feca86eb8b1f61c7819d499"},{"name":"audacity-macOS-3.7.9-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.9/audacity-macOS-3.7.9-universal.dmg","size":69550559,"digest":"sha256:5d4fe9125fc79aec3d6d67677407afda42229ae86a37c2a65d99b0df1cd95a24"},{"name":"audacity-macOS-3.7.9-universal.pkg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.9/audacity-macOS-3.7.9-universal.pkg","size":69576947,"digest":"sha256:ea15b556a08b8af51344fe872aa2c396aa6f6491e447b4c8f7edc12d7b986cfd"},{"name":"audacity-macOS-3.7.9-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.9/audacity-macOS-3.7.9-x86_64.dmg","size":33643297,"digest":"sha256:142f3900bea5d49a73e66cce06e156b8e5387643e1b718806e85286753d6294f"}]},
    {"tag_name":"Audacity-4.0.0-beta-4","name":"Audacity 4.0.0 Beta 4","draft":false,"prerelease":true,"published_at":"2026-08-28T15:25:10Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-4.0.0-beta-4","body":"### Hello everyone, beta 4 is here!\r\n\r\n### Highlights:\r\n\r\n* #11330 ASIO support on Windows, finally!\r\n* #11581 FFmpeg 9 support","assets":[{"name":"Audacity-4.0.0-beta4-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0-beta-4/Audacity-4.0.0-beta4-universal.dmg","size":87696857,"digest":"sha256:6bdb79070c8ca81e61e27324242445b50b72097e988df17d84e748471eadec1b"},{"name":"Audacity-4.0.0-beta4-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0-beta-4/Audacity-4.0.0-beta4-x86_64.dmg","size":50159427,"digest":"sha256:3fd193d63bdbcf80b64d8d6c0716b5414481ee718b1af7952ee4cf090c81ff1c"},{"name":"Audacity-4.0.0-beta4-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0-beta-4/Audacity-4.0.0-beta4-arm64.dmg","size":45833321,"digest":"sha256:3fba43f3a92ad2155bbfdbf2693af93b52875b476a74e84314d1c6fcfc643c2b"}]},
    {"tag_name":"Audacity-3.7.8","name":"Audacity 3.7.8","draft":false,"prerelease":false,"published_at":"2026-06-11T14:32:48Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-3.7.8","body":"This is a patch release. It contains the following changes:\r\n\r\n   * #10681 Fixed multichannel FLAC import\r\n   * #10999 Fixed envelope being broken after joining clips","assets":[{"name":"audacity-macOS-3.7.8-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.8/audacity-macOS-3.7.8-arm64.dmg","size":31818104,"digest":"sha256:2888d2bef5321990d3a11507f9b5cf9461831725a50f391fffd558f7404ffcf8"},{"name":"audacity-macOS-3.7.8-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.8/audacity-macOS-3.7.8-universal.dmg","size":70435312,"digest":"sha256:09099365c3d5a8b83b055ec04ed3468ccfd6a53d162bf0b32130ff3620cbfac6"},{"name":"audacity-macOS-3.7.8-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.8/audacity-macOS-3.7.8-x86_64.dmg","size":34101912,"digest":"sha256:6d79d5ec2c1bbb69421b3c2c8ff5f34b34be96997e4cdb6e0fde12948b9fc173"}]},
    {"tag_name":"Audacity-4.0.0-beta-2","name":"Audacity 4.0.0 Beta 2","draft":false,"prerelease":true,"published_at":"2026-06-11T14:33:00Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-4.0.0-beta-2","body":"### ⚠️ This is a beta\r\n\r\n- Found a bug? [Open an issue](https://github.com/audacity/audacity/issues)\r\n- Want to chat? [Join the discussion](https://github.com/audacity/audacity/discussions)","assets":[{"name":"Audacity-4.0.0-beta2-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-4.0.0-beta-2/Audacity-4.0.0-beta2-universal.dmg","size":127104762,"digest":"sha256:db670f12c3f859057fa51a520c6d2fec89d8c5222f456e19e184902637df4f28"}]},
    {"tag_name":"Audacity-3.7.7","name":"Audacity 3.7.7","draft":false,"prerelease":false,"published_at":"2025-12-11T19:48:17Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-3.7.7","body":"This is a hotfix release. It fixes broken waveform scrolling and selection for some users introduced in 3.7.6. \r\nThe fix was provided by @iv-m and @DavidBailes, thank you!\r\n\r\nOther changes:\r\n   * #9940 Added checksum to WavPack export (thanks @ajsand)\r\n\r\n## New Contributors\r\n* @iv-m made their first contribution in https://github.com/audacity/audacity/pull/10011\r\n* @ajsand made their first contribution in https://github.com/audacity/audacity/pull/9940\r\n\r\n**Full Changelog**: https://github.com/audacity/audacity/compare/Audacity-3.7.6...Audacity-3.7.7","assets":[{"name":"audacity-macOS-3.7.7-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.7/audacity-macOS-3.7.7-arm64.dmg","size":30014299,"digest":"sha256:8b3c43a06eef2977bd81fd14f349d93c6295f1760a93fc5bd4dba86c0ec104eb"},{"name":"audacity-macOS-3.7.7-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.7/audacity-macOS-3.7.7-universal.dmg","size":66894576,"digest":"sha256:7a188eec047e32c25c95eb301854e98cdc2bdb2facb169d5022d967c2ba94d35"},{"name":"audacity-macOS-3.7.7-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.7.7/audacity-macOS-3.7.7-x86_64.dmg","size":32274723,"digest":"sha256:8c9bf8bdca75ffb1d6cfe5c28b04869ec1150c65f246983e70d901847e94d4b9"}]},
    {"tag_name":"Audacity-3.5.0-beta-3","name":"Audacity 3.5.0 Beta 3","draft":false,"prerelease":true,"published_at":"2024-03-29T10:30:15Z","html_url":"https://github.com/audacity/audacity/releases/tag/Audacity-3.5.0-beta-3","body":"compared to Beta 2:\r\n\r\n* Audio previews for the projects are generated only on demand\r\n* Bug fixes","assets":[{"name":"audacity-macOS-3.5.0-beta-3-arm64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.5.0-beta-3/audacity-macOS-3.5.0-beta-3-arm64.dmg","size":24824394},{"name":"audacity-macOS-3.5.0-beta-3-universal.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.5.0-beta-3/audacity-macOS-3.5.0-beta-3-universal.dmg","size":53062499},{"name":"audacity-macOS-3.5.0-beta-3-x86_64.dmg","browser_download_url":"https://github.com/audacity/audacity/releases/download/Audacity-3.5.0-beta-3/audacity-macOS-3.5.0-beta-3-x86_64.dmg","size":26631390}]}
    ]
    """##

    // MARK: - Changelog

    private static func notes(_ bundleID: String, version: String) throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: bundleID, channel: .stable, version: version))
        return try #require(ChangelogService.parse(recipe, body: releasesJSON))
    }

    /// The 3.x pane lists only stable `Audacity-3.*` releases: the 4.x rows
    /// above and between them, and the 3.x and 4.x betas, are all left out.
    @Test func threeXNotesReadOnlyTheThreeTrain() throws {
        let cl = try Self.notes(Self.threeID, version: "3.7.8")
        #expect(cl.entries.map(\.version) == ["3.7.9", "3.7.8", "3.7.7"])
        #expect(cl.entries[0].date == "2026-09-01")
        #expect(cl.entries[0].items == [
            "#11690 Enabled ASIO support for the Windows builds, playback and recording device selection is remembered per-host now",
            "#11679 Added FFmpeg 9 support",
            "#11711 Fixed a crash after a failed recording attempt",
        ])
        // `## New Contributors` and the Full Changelog line are not changes.
        #expect(cl.entries[2].items == ["#9940 Added checksum to WavPack export (thanks @ajsand)"])
    }

    /// The 4.x pane lists only stable `Audacity-4.*` releases, with the
    /// release's own section headings.
    @Test func fourXNotesReadOnlyTheStableFourTrain() throws {
        let cl = try Self.notes(Self.fourID, version: "4.0.0")
        #expect(cl.entries.map(\.version) == ["4.0.1", "4.0.0"])
        #expect(cl.entries[0].date == "2026-09-30")
        #expect(cl.entries[0].items == [
            "Export multiple: export each track, or each labelled region, to its own file",
            "Liquid Glass app icon on macOS (#11923, by @JoshBashed)",
            "Fixed project corruption after a failed save",
            "Fixed opening files dropped on the macOS Dock icon",
        ])
        #expect(cl.entries[0].content.contains(.heading("Features")))
        #expect(cl.entries[0].content.contains(.heading("Bug fixes")))
    }

    /// The registry groups bundle ids case-insensitively, so the prerelease id
    /// and the 3.x id are one group: whichever spelling is asked, a 4.x version
    /// gets the 4.x notes and a 3.x version the 3.x notes. 4.0.1 is the version
    /// the pane is resolved for when Homebrew offers a prerelease copy 4.0.1.
    ///
    /// Mutation (run): with both version windows removed, the 4.0.0 prerelease
    /// gets the 3.x recipe again (the group's first) → red.
    @Test(arguments: [prereleaseID, threeID])
    func theGroupSplitsAtFour(_ bundleID: String) throws {
        for version in ["4.0.0", "4.0.1"] {
            let cl = try Self.notes(bundleID, version: version)
            #expect(cl.entries.map(\.version) == ["4.0.1", "4.0.0"], "\(bundleID) \(version)")
        }
        for version in ["3.7.8", "3.7.9"] {
            let cl = try Self.notes(bundleID, version: version)
            #expect(cl.entries.first?.version == "3.7.9", "\(bundleID) \(version)")
        }
    }
}
