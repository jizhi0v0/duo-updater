import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two releases from `api.github.com/repos/wavetermdev/waveterm/releases`
/// (fetched 2026-10-10), bodies trimmed by whole lines from the top: v0.14.5
/// keeps its intro and first two items, v0.14.5-beta.2 its first two.
private let waveReleasesFixture = #"""
[
 {
  "tag_name": "v0.14.5",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-04-16T16:01:54Z",
  "body": "Wave v0.14.5 introduces a new Process Viewer widget, Quake Mode for global hotkey, and several quality-of-life improvements.\r\n\r\n- **Process Viewer** - New widget that displays running processes on local and remote machines, with CPU and memory usage, sortable columns, and the ability to send signals to processes\r\n- **Quake Mode** - The global hotkey (`app:globalhotkey`) now toggles a Wave window visible and invisible"
 },
 {
  "tag_name": "v0.14.5-beta.2",
  "prerelease": true,
  "draft": false,
  "published_at": "2026-04-16T06:42:58Z",
  "body": "## What's Changed\r\n* Bump @xmldom/xmldom from 0.8.11 to 0.8.12 by @dependabot[bot] in https://github.com/wavetermdev/waveterm/pull/3161\r\n* add docs for new term:showsplitbuttons config key by @sawka in https://github.com/wavetermdev/waveterm/pull/3160"
 }
]
"""#

@Suite struct WaveChangelogRecipeTests {

    private func parsed() throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "dev.commandline.waveterm"))
        return try #require(ChangelogService.parse(recipe, body: waveReleasesFixture))
    }

    /// The beta published the same day is a prerelease, and the probe reads the
    /// stable feed, so it is not on the rail.
    @Test func readsTheStableReleaseOnly() throws {
        let entries = try parsed().entries
        #expect(entries.map(\.version) == ["0.14.5"])
        let newest = try #require(entries.first)
        #expect(newest.date == "2026-04-16")
        #expect(newest.items == [
            "**Process Viewer** - New widget that displays running processes on local and remote machines, with CPU and memory usage, sortable columns, and the ability to send signals to processes",
            "**Quake Mode** - The global hotkey (`app:globalhotkey`) now toggles a Wave window visible and invisible",
        ])
    }
}
