import Testing
import Foundation
@testable import DuoUpdaterCore

/// fx's `CHANGELOG.md` into one entry per version. The fixture copies the shape
/// fetched on 2026-10-01: a `# fx` title, release markers around the newest
/// section only, a bold summary, `###` categories, and older sections without a
/// summary whose bullets lead with a bold label.
@Suite struct FxChangelogTests {

    static let fixture = """
        # fx

        ## 0.0.12

        <!-- release:start -->

        **Session listing is up to 560× faster, and Markdown renders better.**

        ### Breaking Changes

        - libfx now uses `LIBFX_MODEL_UNSUPPORTED_EFFORT` for unsupported model settings.

        ### New Features

        - Detached processes such as `tmux` now stay alive between shell calls.
        - `/mcp list` now opens the interactive Servers menu.

        ### Bug Fixes

        - Prompt-too-long errors now trigger compaction and one retry.

        <!-- release:end -->

        - A stray line after the release markers, not part of the release.

        ## 0.0.11

        **fx now supports custom model connections and themes.**

        ### New Features

        - Custom model connections.

        ### Security

        - Slack MCP sign-in now requests only approved fx scopes.

        ## Unreleased notes

        - Something that belongs to no version.

        ## v0.0.3

        ### Improvements

        - **JSON recovery progress:** Report retry status on stderr.

        ### Bug Fixes

        - **Memory clearing:** Succeed when memory is already absent.
        """

    @Test func oneEntryPerVersionNewestFirst() throws {
        let changelog = try #require(FxChangelog.parse(Self.fixture))
        #expect(changelog.entries.map(\.version) == ["0.0.12", "0.0.11", "0.0.3"])
        #expect(changelog.itemSyntax == .markdown)
    }

    /// The summary leads the entry, in front of the first category, and keeps
    /// its bold; the categories stay headings.
    @Test func summaryLeadsAndCategoriesStayHeadings() throws {
        let entry = try #require(FxChangelog.parse(Self.fixture)?.entries.first)
        let summary = "**Session listing is up to 560× faster, and Markdown renders better.**"
        #expect(entry.items.first == summary)
        #expect(entry.content == [
            .note(summary),
            .heading("Breaking Changes"),
            .note("libfx now uses `LIBFX_MODEL_UNSUPPORTED_EFFORT` for unsupported model settings."),
            .heading("New Features"),
            .note("Detached processes such as `tmux` now stay alive between shell calls."),
            .note("`/mcp list` now opens the interactive Servers menu."),
            .heading("Bug Fixes"),
            .note("Prompt-too-long errors now trigger compaction and one retry."),
        ])
    }

    /// Only what the markers enclose is the release.
    @Test func linesOutsideTheReleaseMarkersAreDropped() throws {
        let entry = try #require(FxChangelog.parse(Self.fixture)?.entries.first)
        #expect(!entry.items.contains { $0.contains("stray line") })
    }

    /// A heading that is not a version closes the section before it.
    @Test func nonVersionHeadingEndsTheSection() throws {
        let changelog = try #require(FxChangelog.parse(Self.fixture))
        let older = try #require(changelog.entries.first { $0.version == "0.0.11" })
        #expect(older.items == [
            "**fx now supports custom model connections and themes.**",
            "Custom model connections.",
            "Slack MCP sign-in now requests only approved fx scopes.",
        ])
        #expect(!changelog.entries.flatMap(\.items).contains { $0.contains("belongs to no version") })
    }

    @Test func sectionWithoutSummaryKeepsItsLabelledBullets() throws {
        let entry = try #require(FxChangelog.parse(Self.fixture)?.entries.last)
        #expect(entry.version == "0.0.3")
        #expect(entry.items == [
            "**JSON recovery progress:** Report retry status on stderr.",
            "**Memory clearing:** Succeed when memory is already absent.",
        ])
        #expect(entry.content.first == .heading("Improvements"))
    }

    @Test func somethingElseIsNotReleaseNotes() {
        #expect(FxChangelog.parse("404: Not Found") == nil)
        #expect(FxChangelog.parse("# fx\n\n## 0.0.1\n\n") == nil)
        #expect(FxChangelog.parse("<html><body>## 0.0.1</body></html>") == nil)
    }
}
