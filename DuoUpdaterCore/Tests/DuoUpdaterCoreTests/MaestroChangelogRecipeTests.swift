import Testing
import Foundation
@testable import DuoUpdaterCore

/// Five releases from `api.github.com/repos/RunMaestro/Maestro/releases`
/// (2026-11-11), bodies cut: 1.0.2's highlight paragraphs and list, an RC
/// GitHub does not flag as a prerelease, a flagged RC, 0.13.1 repeating
/// 0.13.0 under `### v0.13.0 Changes`, and 0.12.3's `Changes Specific to
/// v0.12.3:`.
private let maestroReleasesFixture = #"""
[
 {"tag_name": "v1.0.2", "prerelease": false, "draft": false,
  "published_at": "2026-10-21T19:02:11Z",
  "body": "# 1.0.2 Highlights\r\n\r\n▶️ **Shell blocks in an agent's reply have a Run button.** When an agent answers with a `bash` block, click Run beside the copy button.\r\n\r\n📊 **Re-reading your usage history no longer freezes the app.** A progress window shows transcripts done.\r\n\r\n## Also in 1.0.2\r\n\r\n- 🗑️ **Close a whole tab group** from its chip menu.\r\n- 🗄️ **`maestro-cli group-chat archive`** archives a group chat.\r\n\r\n**Full Changelog**: https://github.com/RunMaestro/Maestro/compare/v1.0.1...v1.0.2"},
 {"tag_name": "v1.1.0-RC", "prerelease": true, "draft": false,
  "published_at": "2026-10-19T10:00:00Z",
  "body": "# 1.1.0 Highlights\n\n🧪 **An RC change.**"},
 {"tag_name": "v0.15.4-RC", "prerelease": false, "draft": false,
  "published_at": "2026-04-28T10:00:00Z",
  "body": "## Changes\n\n- An RC change GitHub lists as stable."},
 {"tag_name": "v0.13.1", "prerelease": false, "draft": false,
  "published_at": "2025-12-29T10:00:00Z",
  "body": "Fixed Linux ARM64 build architecture contamination issues 🏗️\n\n### v0.13.0 Changes\n- Added a global usage dashboard 🎛️\n- Bundled OpenSpec commands 📝"},
 {"tag_name": "v0.12.3", "prerelease": false, "draft": false,
  "published_at": "2025-12-28T10:00:00Z",
  "body": "The big changes in the v0.12.x line are the following three:\n\n## Show Thinking\n🤔 There is now a toggle to show thinking for the agent.\n\n## Changes Specific to v0.12.3:\n- We now have hosted documentation through Mintlify 📚\n\n**Full Changelog**: https://github.com/pedramamini/Maestro/compare/v0.12.1...v0.12.3"}
]
"""#

@Suite struct MaestroChangelogRecipeTests {
    private func parsed() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.maestro.app", channel: .stable))
        #expect(recipe.structuredFormat == .maestroReleases)
        return try #require(ChangelogService.parse(recipe, body: maestroReleasesFixture))
    }

    private func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .heading(let h) = $0 { return h } else { return nil } }
    }

    /// The paragraphs under `# 1.0.2 Highlights` were dropped before: 2 of 4 here.
    @Test func keepsTheHighlightParagraphsUnderTheirHeadings() throws {
        let newest = try #require(try parsed().entries.first)
        #expect(newest.version == "1.0.2")
        #expect(newest.date == "2026-10-21")
        #expect(newest.items.count == 4)
        #expect(newest.items.first?.hasPrefix("▶️ **Shell blocks in an agent's reply have a Run button.**") == true)
        #expect(newest.items.last == "🗄️ **`maestro-cli group-chat archive`** archives a group chat.")
        #expect(headings(newest) == ["Highlights", "Also in this release"])
    }

    /// Both RCs stay out, the unflagged one by the tag pattern.
    @Test func readsOnlyStableTags() throws {
        #expect(try parsed().entries.map(\.version) == ["1.0.2", "0.13.1", "0.12.3"])
    }

    @Test func cutsARepeatedEarlierRelease() throws {
        let entry = try #require(try parsed().entries.first { $0.version == "0.13.1" })
        #expect(entry.items == ["Fixed Linux ARM64 build architecture contamination issues 🏗️"])
    }

    @Test func dropsLeadInsAndTheCompareLink() throws {
        let entry = try #require(try parsed().entries.first { $0.version == "0.12.3" })
        #expect(entry.items == [
            "🤔 There is now a toggle to show thinking for the agent.",
            "We now have hosted documentation through Mintlify 📚",
        ])
        #expect(headings(entry) == ["Show Thinking", "Changes Specific to this release"])
    }

    @Test func headingsLoseTheirVersion() {
        #expect(MaestroReleaseNotes.withoutVersion("1.0.2 Highlights") == "Highlights")
        #expect(MaestroReleaseNotes.withoutVersion("Also in 1.0.2") == "Also in this release")
        #expect(MaestroReleaseNotes.withoutVersion("Major 0.17.x Additions") == "Major Additions")
        #expect(MaestroReleaseNotes.withoutVersion("Changes in v0.14.5") == "Changes in this release")
        #expect(MaestroReleaseNotes.withoutVersion("Smaller Changes in 014.x") == "Smaller Changes in this release")
        #expect(MaestroReleaseNotes.withoutVersion("Show Thinking") == "Show Thinking")
    }

    /// CRLF bodies (1.0.2's is one) read as LF: a wrap is not a paragraph break.
    @Test func crlfBodiesWrapLikeLFOnes() {
        let body = "- An item\r\n  that wraps\r\n\r\n🎯 **A paragraph** that\r\nwraps too."
        #expect(MaestroReleaseNotes.normalized(body, version: "1.0.0")
            == "- An item\n  that wraps\n\n- 🎯 **A paragraph** that wraps too.")
    }

    /// 0.17.0 opens with a blockquoted notice; the item is its text.
    @Test func aBlockquotedNoticeLosesItsMarker() {
        let body = "> ⚠️ **Please update before June 15.** Older builds\n> stop syncing.\n"
        #expect(MaestroReleaseNotes.normalized(body, version: "0.17.0")
            == "- ⚠️ **Please update before June 15.** Older builds stop syncing.\n")
    }

    /// The RC track's notes carry the RCs it is offered and the stable releases
    /// beside them; the stable track's never carry an RC.
    @Test func theRCTrackListsRCsAndStableReleases() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(
            forBundleID: "com.maestro.app", channel: .beta))
        #expect(recipe.channel == .beta)
        let entries = try #require(ChangelogService.parse(recipe, body: maestroReleasesFixture)).entries
        #expect(entries.map(\.version) == ["1.0.2", "1.1.0-RC", "0.15.4-RC", "0.13.1", "0.12.3"])
    }

    /// A line right under a list item continues it; a paragraph's hard wraps join.
    @Test func continuationsAndWrapsStayOneItem() {
        let body = "- An item\n  that wraps\n\n🎯 **A paragraph** that\nwraps too.\n"
        #expect(MaestroReleaseNotes.normalized(body, version: "1.0.0")
            == "- An item\n  that wraps\n\n- 🎯 **A paragraph** that wraps too.\n")
    }
}
