import Foundation
import Testing

@testable import DuoUpdaterCore

/// Six releases from `api.github.com/repos/MonitorControl/MonitorControl/releases`
/// (fetched 2026-10-08), each picked for a decision the recipe makes. Bodies are
/// verbatim; the longer ones are trimmed by whole lines only: v4.2.0 keeps two
/// items per section, one New Contributors row and the Full Changelog line;
/// v4.0.0-rc1 and v4.0.0-beta2 keep their first two items.
///
/// - v4.4.0: the current shape, one `## What's Changed` over a flat list.
/// - v4.2.0: GitHub's generated notes, with the two noise sections every app drops.
/// - v4.0.2: hand-written categories plus a `### Notes` sign-off.
/// - v4.0.0-rc1: a release candidate published with `prerelease: false`.
/// - v4.0.0-beta2: a real prerelease.
/// - v1.1: nothing but `### Installation`.
private let monitorControlReleasesFixture = #"""
[
 {
  "tag_name": "v4.4.0",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-09-15T09:41:29Z",
  "body": "This is a maintenance update addressing compatibility issues with macOS 27 Golden Gate and macOS 26 Tahoe, helping keep our beloved MonitorControl going in its original glory.\r\n\r\nIt is for those who have grown attached to MonitorControl just the way it is, and still prefer its simple, familiar way of doing things over some of the fancier alternatives out there.\r\n\r\n## What's Changed\r\n\r\n- Restored the traditional OSD for macOS 26 and macOS 27.\r\n- Fixed app Settings appearing on every interaction with the macOS 27 Siri app.\r\n- Fixed custom keyboard shortcut recording issues on macOS 27.\r\n- Various minor bug fixes.\r\n\r\nIf you need more features please consider switching to **[BetterDisplay](https://betterdisplay.pro)**."
 },
 {
  "tag_name": "v4.2.0",
  "prerelease": false,
  "draft": false,
  "published_at": "2023-09-09T14:06:10Z",
  "body": "> [!WARNING]\r\n> Please be aware that **this version crashes on macOS Sequoia** when attempting to change the brightness of an Apple first party, built-in display, or any third party display in HDR mode! Please upgrade to v4.3.2 for Sequoia compatibility (note: manual upgrade needed, the v4.2.0 version does not update automatically to future new releases due to a signing issue)!\r\n\r\n## What's Changed\r\n\r\n### Improvements\r\n* DDC support for high-end M2 (Pro/Max/Ultra) systems by @waydabber, maker of **[BetterDisplay](https://betterdisplay.pro/)** in https://github.com/MonitorControl/MonitorControl/pull/1404\r\n* Fixed \"Possible memory leak in Arm64ddc? #1087\" by @waydabber, maker of **[BetterDisplay](https://betterdisplay.pro/)** in https://github.com/MonitorControl/MonitorControl/pull/1181\r\n\r\n### Translations & other\r\n* cs_CZ: update Main.strings for 4.1.0 by @isametry in https://github.com/MonitorControl/MonitorControl/pull/1085\r\n* Fixed Readme typo by @prabch in https://github.com/MonitorControl/MonitorControl/pull/1156\r\n\r\n## New Contributors\r\n* @sertrsv made their first contribution in https://github.com/MonitorControl/MonitorControl/pull/1075\r\n\r\n**Full Changelog**: https://github.com/MonitorControl/MonitorControl/compare/v4.1.0...v4.2.0"
 },
 {
  "tag_name": "v4.0.2",
  "prerelease": false,
  "draft": false,
  "published_at": "2021-11-18T19:12:19Z",
  "body": "This is a service release with some minor changes.\r\n\r\n### Improvements\r\n\r\n- Settings are now saved for virtual displays (Sidecar, DisplayLink etc.) as well.\r\n- Shorter wake wait times, removed \"locked control\" OSD sign.\r\n- Spanish translation - thanks to @OliverCG\r\n\r\n### Fixes\r\n\r\n- Menuless operation's Quit button location now matches the corresponding info text.\r\n\r\n### Notes\r\n\r\n- If you discover any problem, feel free to open an issue!\r\n- If you want to help translating, see #637\r\n- Thanks to everyone who helps make MonitorControl better!"
 },
 {
  "tag_name": "v4.0.0-rc1",
  "prerelease": false,
  "draft": false,
  "published_at": "2021-10-12T17:24:06Z",
  "body": "## Full v4.0.0 Release Candidate release notes\r\n\r\n### Enhancements\r\n\r\n- Automatic & manual updates through the app, no more manual downloads 🎉 \r\n- Added proper support for controlling Apple displays."
 },
 {
  "tag_name": "v4.0.0-beta2",
  "prerelease": true,
  "draft": false,
  "published_at": "2021-10-07T18:45:52Z",
  "body": "## Changes compared to  [v4.0.0-beta1](https://github.com/MonitorControl/MonitorControl/releases/tag/v4.0.0-beta1):\r\n\r\n### Enhancements\r\n\r\n- Added Internet Access Policy\r\n- Don't relinquish control over brightness keys with no external display connected if fine brightness OSD scale is active"
 },
 {
  "tag_name": "v1.1",
  "prerelease": false,
  "draft": false,
  "published_at": "2018-01-06T15:31:35Z",
  "body": "### Installation\r\nOpen the `.dmg` file and drop `MonitorControl` into your Applications folder. Launch by double clicking on the app."
 }
]
"""#

@Suite struct MonitorControlChangelogRecipeTests {

    private let bundleID = "app.monitorcontrol.MonitorControl"

    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipe(forBundleID: bundleID, channel: .stable))
    }

    /// Through `ChangelogService.parse`, the one route the app and `duo verify`
    /// both take, so the recipe's `skipSections` and `tagPattern` are applied.
    private func parsed() throws -> Changelog {
        try #require(ChangelogService.parse(try recipe(), body: monitorControlReleasesFixture))
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { block -> String? in
            if case .heading(let h) = block { return h }
            return nil
        }
    }

    @Test func readsTheReleasesListOfTheAppsOwnRepo() throws {
        let r = try recipe()
        #expect(r.structuredFormat == .gitHubReleases)
        #expect(r.mode == .json)
        #expect(r.channel == nil)
        #expect(r.source.host == "api.github.com")
        #expect(r.source.path == "/repos/MonitorControl/MonitorControl/releases")
    }

    /// Stable only, and the tag minus its `v` is the version, which is what
    /// `CFBundleShortVersionString` says (4.4.0). The release candidate, the beta
    /// and the installation-only body produce no entry.
    @Test func entriesAreTheStableReleasesUnderTheirBundleVersion() throws {
        let cl = try parsed()
        #expect(cl.entries.map(\.version) == ["4.4.0", "4.2.0", "4.0.2"])
        #expect(cl.entries.map(\.date) == ["2026-09-15", "2023-09-09", "2021-11-18"])
        #expect(cl.itemSyntax == .markdown)
    }

    /// One `## What's Changed` is below `GitHubMarkdownParser`'s two-heading
    /// threshold, so it is not styled: the entry is the flat list, and the intro
    /// and BetterDisplay prose around it are not items.
    @Test func theCurrentShapeIsAFlatListWithNoHeading() throws {
        let entry = try #require(try parsed().entries.first)
        #expect(entry.items == [
            "Restored the traditional OSD for macOS 26 and macOS 27.",
            "Fixed app Settings appearing on every interaction with the macOS 27 Siri app.",
            "Fixed custom keyboard shortcut recording issues on macOS 27.",
            "Various minor bug fixes.",
        ])
        #expect(entry.content.isEmpty)
    }

    /// GitHub's generated notes: the two category headings render, New
    /// Contributors and Full Changelog do not.
    @Test func generatedNotesKeepCategoriesAndDropTheContributorList() throws {
        let entry = try #require(try parsed().entries.first { $0.version == "4.2.0" })
        #expect(headings(entry) == ["Improvements", "Translations & other"])
        #expect(entry.items.count == 4)
        #expect(entry.items[2] == "cs_CZ: update Main.strings for 4.1.0")
        #expect(entry.items[3] == "Fixed Readme typo")
        #expect(!entry.items.contains { $0.contains("first contribution") })
        #expect(!entry.items.contains { $0.contains("Full Changelog") })
    }

    /// `skipSections` drops the `### Notes` sign-off, and its heading with it.
    @Test func theNotesSignOffIsNotAChange() throws {
        let entry = try #require(try parsed().entries.first { $0.version == "4.0.2" })
        #expect(entry.items == [
            "Settings are now saved for virtual displays (Sidecar, DisplayLink etc.) as well.",
            "Shorter wake wait times, removed \"locked control\" OSD sign.",
            "Spanish translation - thanks to @OliverCG",
            "Menuless operation's Quit button location now matches the corresponding info text.",
        ])
        #expect(headings(entry) == ["Improvements", "Fixes"])
    }

    /// Both filters are load-bearing on this fixture: without `tagPattern` the
    /// release candidate (GitHub calls it stable) is an entry, and without
    /// `skipSections` the install instructions are one.
    @Test func theTagFilterAndTheSkippedSectionsEachRemoveAnEntry() throws {
        let r = try recipe()
        let unfiltered = try #require(StructuredChangelogDecoder.decode(
            monitorControlReleasesFixture, format: .gitHubReleases, channel: r.channel,
            maxEntries: r.maxEntries, skipSections: r.skipSections))
        #expect(unfiltered.entries.map(\.version) == ["4.4.0", "4.2.0", "4.0.2", "4.0.0-rc1"])

        let unskipped = try #require(StructuredChangelogDecoder.decode(
            monitorControlReleasesFixture, format: .gitHubReleases, channel: r.channel,
            maxEntries: r.maxEntries, tagPattern: r.tagPattern))
        #expect(unskipped.entries.map(\.version) == ["4.4.0", "4.2.0", "4.0.2", "1.1"])
    }

    /// The beta never reaches a stable install, with or without the recipe's filters.
    @Test func thePrereleaseIsNeverAnEntry() throws {
        let bare = try #require(StructuredChangelogDecoder.decodeGitHubReleases(
            monitorControlReleasesFixture, channel: nil, maxEntries: nil))
        #expect(!bare.entries.contains { $0.version.contains("beta") })
        #expect(bare.entries.contains { $0.version == "4.0.0-rc1" })
    }
}
