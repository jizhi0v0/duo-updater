import Foundation
import Testing

@testable import DuoUpdaterCore

/// Three releases from `api.github.com/repos/HandBrake/HandBrake/releases`
/// (fetched 2026-10-08), only the fields the decoder reads. 1.11.2 and 1.11.1 are
/// whole bodies, verbatim, CRLF line ends included: the upgrade notice with its
/// Windows .NET links, the `### All platforms` / `#### …` nesting, the
/// `Updated libraries` bullet with its indented library list, and the Linux and
/// Windows sections. 1.4.0-beta.1, the repository's only `prerelease` release, is
/// trimmed to its first three paragraphs, verbatim.
private let handBrakeReleasesFixture = ###"""
[
 {
  "tag_name": "1.11.2",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-06-07T19:08:25Z",
  "body": "## Upgrade Notice\r\n\r\nBefore updating HandBrake, please make sure there are no pending encodes in the queue, and be sure to make a backup of any custom presets and app preferences you have, as they may not be compatible with newer versions.\r\n\r\nWindows users, please make sure to install [Microsoft .NET Desktop Runtime version 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0/runtime)\r\nDownload available from Microsoft:\r\n- [For x64 (AMD or Intel CPUs)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe)\r\n- [For Arm64 (Qualcomm or other)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-arm64.exe)\r\n\r\n\r\n## HandBrake 1.11.2\r\n\r\n### All platforms\r\n\r\n#### Video\r\n\r\n- Fixed a crash that happened when doing a 2-pass lossless x265 encode\r\n- Fixed a memory leak that happened when doing a 2-pass MPEG-4/MPEG-2/VP9/FFV1 encode\r\n\r\n#### Audio\r\n\r\n- Updated the list of supported dithers and encoders combinations\r\n- Fixed the Core Audio AAC encoder 7.1 channel layout\r\n\r\n#### Subtitles\r\n\r\n- Fixed the VobSub palette creation in the MP4 container\r\n\r\n#### Build system\r\n\r\n- Improved build system compatibility with older build tools\r\n\r\n#### Third-party libraries\r\n\r\n- Updated libraries\r\n  - FFmpeg 8.0.2 (decoding and filters)\r\n  - SVT-AV1 4.1.0 (AV1 video encoding)\r\n\r\n### Linux\r\n\r\n- Added WebM MIME type to the list of the supported formats\r\n\r\n### Mac\r\n\r\n- Improved handling of unsupported presets\r\n- Updated Sparkle automatic update library\r\n\r\n### Windows\r\n\r\n- Improved handling of unsupported presets\r\n- Improved queue low space pause behaviour\r\n- Fixed the automatic audio track name generation\r\n- Fixed the summary description of HDR video"
 },
 {
  "tag_name": "1.11.1",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-03-22T19:34:20Z",
  "body": "## Upgrade Notice\r\n\r\nBefore updating HandBrake, please make sure there are no pending encodes in the queue, and be sure to make a backup of any custom presets and app preferences you have, as they may not be compatible with newer versions.\r\n\r\nWindows users, please make sure to install [Microsoft .NET Desktop Runtime version 10.0](https://dotnet.microsoft.com/en-us/download/dotnet/10.0/runtime)\r\nDownload available from Microsoft:\r\n- [For x64 (AMD or Intel CPUs)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe)\r\n- [For Arm64 (Qualcomm or other)](https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-arm64.exe)\r\n\r\n\r\n## HandBrake 1.11.1\r\n\r\n### All platforms\r\n\r\n#### Audio\r\n\r\n- Fixed a crash that could happen when scanning a PCM track in a DVD-Video or Blu-ray \r\n\r\n#### Third-party libraries\r\n\r\n- Updated libraries\r\n  - Jansson 2.15.0 (JSON architecture)\r\n  - zlib 1.3.2 (general)\r\n\r\n### Windows\r\n\r\n- Removed dependency on having Microsoft .NET 8 Desktop Runtime installed\r\n- Fixed the file type selection in the save panel\r\n- Fixed a number of issues that impacted screen reader tools ability to read combo box controls"
 },
 {
  "tag_name": "1.4.0-beta.1",
  "prerelease": true,
  "draft": false,
  "published_at": "2020-11-11T19:06:00Z",
  "body": "We are pleased to announce Universal Binaries for macOS supporting both Apple's Intel Macs and the all-new Apple Silicon Macs.\r\n\r\nOur [development snapshot builds](https://handbrake.fr/nightly.php) have now also been updated to be Universal Binaries.\r\n\r\n### Notices\r\n\r\nPlease note that this is a BETA release and as such, there may be issues. If you do find issues with this builds please post a thorough bug report on our [Issue Tracker](https://github.com/HandBrake/HandBrake/issues)."
 }
]
"""###

@Suite struct HandBrakeChangelogRecipeTests {

    private static let bundleID = "fr.handbrake.HandBrake"

    /// Decode the way the app does, through `ChangelogService.parse` and the
    /// registered recipe, so its `skipSections` are the ones that ship.
    private func decode(_ feed: String) throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID))
        return try #require(ChangelogService.parse(recipe, body: feed))
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { block in
            if case .heading(let h) = block { return h } else { return nil }
        }
    }

    @Test func theRecipeReadsHandBrakesOwnReleasesAPI() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: Self.bundleID))
        #expect(recipe.structuredFormat == .gitHubReleases)
        #expect(recipe.mode == .json)
        #expect(recipe.channel == nil)
        #expect(recipe.source.host == "api.github.com")
        #expect(recipe.source.path == "/repos/HandBrake/HandBrake/releases")
        #expect(recipe.source.query == "per_page=10")
        #expect(recipe.skipSections == ["Upgrade Notice", "Linux", "Windows"])
    }

    /// The tag is the bare marketing version, so the entry's version is the string
    /// the app's `CFBundleShortVersionString` carries. The beta is `prerelease`,
    /// and a channel-less recipe never shows it.
    @Test func entriesAreTheStableReleasesKeyedByTheirTag() throws {
        let log = try decode(handBrakeReleasesFixture)
        #expect(log.entries.map(\.version) == ["1.11.2", "1.11.1"])
        #expect(log.entries.map(\.date) == ["2026-06-07", "2026-03-22"])
        #expect(!log.entries.contains { $0.version.contains("beta") })
    }

    /// The category headings survive as headings; the version-restating
    /// `HandBrake 1.11.2` and the item-less `All platforms` do not, and neither do
    /// the three skipped sections.
    @Test func theNewestReleaseKeepsItsCategoriesAndOnlyTheMacSection() throws {
        let entry = try #require(try decode(handBrakeReleasesFixture).entries.first)
        #expect(entry.version == "1.11.2")
        #expect(entry.items.count == 11)  // 9 changes, plus the two libraries under `Updated libraries`
        #expect(headings(entry) ==
            ["Video", "Audio", "Subtitles", "Build system", "Third-party libraries", "Mac"])
        #expect(entry.items.first
            == "Fixed a crash that happened when doing a 2-pass lossless x265 encode")
        #expect(entry.items.last == "Updated Sparkle automatic update library")
    }

    @Test func skippedSectionsLeaveNothingBehind() throws {
        let log = try decode(handBrakeReleasesFixture)
        let items = log.entries.flatMap(\.items)
        let allHeadings = log.entries.flatMap { headings($0) }
        for skipped in ["Upgrade Notice", "Linux", "Windows"] {
            #expect(!allHeadings.contains(skipped))
        }
        // Upgrade Notice: the .NET runtime download links.
        #expect(!items.contains { $0.contains("aka.ms/dotnet") || $0.contains("For x64") })
        // Linux only.
        #expect(!items.contains { $0.contains("WebM MIME type") })
        // Windows only, one from each release.
        #expect(!items.contains { $0.contains("queue low space pause") })
        #expect(!items.contains { $0.contains(".NET 8 Desktop Runtime") })
    }

    /// 1.11.1 has no Mac section, so its entry is the shared changes: one fix,
    /// and `Updated libraries` followed by the two libraries nested under it.
    @Test func aReleaseWithNoMacSectionStillHasAnEntry() throws {
        let entry = try #require(try decode(handBrakeReleasesFixture).entries.last)
        #expect(entry.version == "1.11.1")
        #expect(entry.items == [
            "Fixed a crash that could happen when scanning a PCM track in a DVD-Video or Blu-ray",
            "Updated libraries",
            "Jansson 2.15.0 (JSON architecture)",
            "zlib 1.3.2 (general)",
        ])
        #expect(headings(entry) == ["Audio", "Third-party libraries"])
    }

    /// The library list nested under `Updated libraries` is kept: each library
    /// is an item of its own, right after that line.
    @Test func theLibraryListUnderUpdatedLibrariesIsKept() throws {
        let entry = try #require(try decode(handBrakeReleasesFixture).entries.first)
        let at = try #require(entry.items.firstIndex(of: "Updated libraries"))
        #expect(Array(entry.items[(at + 1)...].prefix(2)) == [
            "FFmpeg 8.0.2 (decoding and filters)",
            "SVT-AV1 4.1.0 (AV1 video encoding)",
        ])
    }
}
