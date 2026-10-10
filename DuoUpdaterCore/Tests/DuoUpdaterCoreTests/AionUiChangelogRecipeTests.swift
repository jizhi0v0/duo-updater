import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two releases from `api.github.com/repos/iOfficeAI/AionUi/releases` (fetched
/// 2026-10-10), bodies trimmed by whole lines from the top: v2.2.2 keeps its
/// first two items, v2.1.47-final its first three.
///
/// - v2.2.2: the current shape, `### <topic>` over a Markdown list.
/// - v2.1.47-final: the one stable tag with a suffix, which `tagPattern` drops
///   so the entry reads `2.1.47`, the version the install reported.
private let aionUiReleasesFixture = #"""
[
 {
  "tag_name": "v2.2.2",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-09-09T11:29:49Z",
  "body": "## Highlights\n\n### Explorer: tab-scoped refresh and Collapse All\n- The Files and Changes panel now has a single top-bar Refresh button that does the right thing per tab: on Files it re-mounts every root and revalidates project detail; on Changes it re-discovers repositories and re-pulls their status.\n- A git worktree created inside an already-open project now shows up on the Changes tab after a single refresh — no more switching projects away and back to make it appear."
 },
 {
  "tag_name": "v2.1.47-final",
  "prerelease": false,
  "draft": false,
  "published_at": "2026-08-05T07:52:23Z",
  "body": "> **This is the final AionUi build distributed through GitHub Releases.** From here on, installers and updates come from the official website. See [A note on distribution](#a-note-on-distribution) at the bottom for what this means for you, your data, and the open-source repo.\r\n\r\n## Highlights\r\n\r\n### In-App Browser, Controllable by the Agent\r\n\r\n- Web pages now open as tabs in the preview panel, and you share one persistent session with the agent — sign in by hand once, and the agent carries that session into whatever it does next.\r\n- The agent reaches the browser through a new built-in MCP server (`aionui-browser`), so it can navigate, click, and pull data on its own.\r\n- On safety: the obvious way to let an agent drive Chromium is `--remote-debugging-port`, but that switch is application-wide with no per-target ACL — it would expose *every* WebContents, including the main window and its preload bridge, to any local process with no authentication. Instead this ships a single-target CDP bridge that exposes only the browser view. Nothing is written to config or the database; the bridge's port and access token travel down the process-inheritance chain, so multiple app instances never cross wires."
 }
]
"""#

@Suite struct AionUiChangelogRecipeTests {

    private func parsed() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.aionui.app"))
        return try #require(ChangelogService.parse(recipe, body: aionUiReleasesFixture))
    }

    @Test func readsTheNewestReleaseAsTheManifestNamesIt() throws {
        let entries = try parsed().entries
        #expect(entries.count == 2)
        let newest = try #require(entries.first)
        #expect(newest.version == "2.2.2")
        #expect(newest.date == "2026-09-09")
        #expect(newest.items.count == 2)
        #expect(newest.items.first == "The Files and Changes panel now has a single top-bar Refresh button that does the right thing per tab: on Files it re-mounts every root and revalidates project detail; on Changes it re-discovers repositories and re-pulls their status.")
    }

    @Test func theFinalSuffixIsNotPartOfTheVersion() throws {
        let entries = try parsed().entries
        #expect(entries.map(\.version) == ["2.2.2", "2.1.47"])
        #expect(entries.last?.items.count == 3)
    }
}
