import Testing
import Foundation
@testable import DuoUpdaterCore

/// Section labels in a Sparkle `<description>` become `.heading` blocks once a
/// body has at least two of them, the way `GitHubMarkdownParser` treats
/// `### Added` / `### Fixed`; below that, nothing changes.
///
/// Fixtures are the CDATA bodies of real items, verbatim, fetched 2026-10-08:
/// - OpenClaw 2026.9.9 (`raw.githubusercontent.com/openclaw/openclaw/main/appcast.xml`):
///   a version-restating `<h2>`, then `<h3>` Highlights / Changes / Fixes /
///   Complete contribution record and an `<h4>` Pull requests.
/// - Superwhisper 2.19.0 and 2.19.2 (`superwhisper.com/appcast.xml`): sections
///   marked by a bold line (`<b>Fixes</b>`) directly above each `<ul>`; 2.19.2
///   has only one.
struct AppcastHTMLSectionLabelTests {

    private static func headings(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .heading(let text) = $0 { return text }; return nil }
    }

    private static func notes(_ entry: Changelog.Entry) -> [String] {
        entry.content.compactMap { if case .note(let text) = $0 { return text }; return nil }
    }

    // MARK: - Real feeds

    @Test func openClawSectionHeadingsAreHeadingsNotItems() throws {
        let entry = try #require(AppcastHTMLChangelogParser.entry(
            html: Self.openClaw2026_9_9, version: "2026.9.9", date: nil))
        #expect(Self.headings(entry) == [
            "Highlights", "Changes", "Fixes", "Complete contribution record", "Pull requests",
        ])
        // The version-restating `<h2>` has a digit, so it is no label; with no
        // line under it, it is dropped exactly as before.
        #expect(!entry.items.contains { $0.contains("OpenClaw 2026.9.9") })
        #expect(!entry.items.contains("Highlights"))
        #expect(Self.notes(entry) == entry.items)
        #expect(entry.items.count == 26)
        // Each heading sits directly above its own first line.
        #expect(entry.content[0] == .heading("Highlights"))
        #expect(entry.content[1] == .note(
            "GPT-6.1 Sol support: update the managed Codex app-server and its embedded model catalog so native Codex sessions can discover and run GPT-6.1 Sol. (#161446, #163560) Thanks @IstiqlalBhat, @fuller-stack-dev, @vincentkoc, and @RomneyDa."))
        #expect(entry.content[6] == .heading("Changes"))
        #expect(entry.content[7] == .note(
            "No intentional capability changes beyond enabling the already-advertised GPT-6.1 Sol model on the managed Codex runtime."))
        #expect(entry.content[8] == .heading("Fixes"))
        #expect(entry.items.last == "PR #162033 Related #161953. Thanks @cestercian and @RomneyDa and @zhyx1996.")
    }

    @Test func superwhisperBoldLinesAboveListsAreHeadings() throws {
        let entry = try #require(AppcastHTMLChangelogParser.entry(
            html: Self.superwhisper2_19_0, version: "2.19.0", date: nil))
        #expect(entry.content == [
            .heading("Features & Improvements"),
            .note("Faster microphone start when beginning recording across all input devices."),
            .note("New Muffle sound option applies a low-pass filter to other apps' audio while you record."),
            .note("Lower playback now drops audio to 30% of your current volume instead of a fixed level, so it scales with how loud you're listening."),
            .heading("Fixes"),
            .note("Fixed issue with \"Always Close\" option when paste detection fails."),
            .note("Fixed license details not updating in the UI after unlinking a personal license."),
            .note("Fixed trial progress bars and trial cards not displaying correctly in the sidebar and License view."),
            .note("Fixed text flicker while typing in the agent composer and when sending messages in agent chat."),
            .note("Fixed clipboard restore issues when using \"Keep what I have copied.\""),
            .note("Fixed the reprocess button unintentionally selecting a mode on a plain click."),
        ])
        #expect(entry.items == Self.notes(entry))
    }

    /// One label is below the floor: the entry reads exactly as it did before.
    @Test func superwhisperLoneBoldLineStaysALine() throws {
        let entry = try #require(AppcastHTMLChangelogParser.entry(
            html: Self.superwhisper2_19_2, version: "2.19.2", date: nil))
        #expect(entry.items == [
            "Fixes",
            "Fixed an issue where app updates could get stuck during installation.",
        ])
        #expect(entry.content.isEmpty)
    }

    // MARK: - Shapes that must not become headings

    @Test func loneHeadingStaysFoldedIntoItems() throws {
        let html = """
        <h3>Fixed</h3>
        <ul>
        <li>Crash when opening the settings window.</li>
        </ul>
        """
        let entry = try #require(AppcastHTMLChangelogParser.entry(html: html, version: "1.0", date: nil))
        #expect(entry.items == ["Fixed", "Crash when opening the settings window."])
        #expect(entry.content.isEmpty)
    }

    /// Bold inside a sentence, and a bold paragraph that does not open a list,
    /// stay lines even in a body that has two real labels.
    @Test func boldThatIsNotALabelStaysALine() throws {
        let html = """
        <p>This release makes <b>sync</b> faster:</p>
        <ul><li>Sync resumes after sleep.</li></ul>
        <p><strong>Please restart after updating.</strong></p>
        <p>Thanks for the reports.</p>
        <b>Features</b>
        <ul><li>Faster sync across devices.</li></ul>
        <p><b>Fixes</b></p>
        <ul><li>Fixed a crash on launch.</li></ul>
        """
        let entry = try #require(AppcastHTMLChangelogParser.entry(html: html, version: "1.0", date: nil))
        #expect(entry.content == [
            .note("This release makes sync faster:"),
            .note("Sync resumes after sleep."),
            .note("Please restart after updating."),
            .note("Thanks for the reports."),
            .heading("Features"),
            .note("Faster sync across devices."),
            .heading("Fixes"),
            .note("Fixed a crash on launch."),
        ])
        #expect(entry.items == Self.notes(entry))
    }

    /// A label with a digit restates a version or names a release; it is no
    /// section label, and two of them do not reach the floor.
    @Test func labelsWithDigitsDoNotCount() throws {
        let html = """
        <h2>Version 3.1</h2>
        <ul><li>Faster sync across devices.</li></ul>
        <b>Claude Sonnet 4.5 support</b>
        <ul><li>Pick the new model in settings.</li></ul>
        """
        let entry = try #require(AppcastHTMLChangelogParser.entry(html: html, version: "3.1", date: nil))
        #expect(entry.items == [
            "Version 3.1",
            "Faster sync across devices.",
            "Claude Sonnet 4.5 support",
            "Pick the new model in settings.",
        ])
        #expect(entry.content.isEmpty)
    }

    /// In a body with enough labels, a heading that is not one (it has a digit)
    /// is folded in as a line, as it always was, and stays in `items`.
    @Test func nonLabelHeadingInALabelledBodyStaysALine() throws {
        let html = """
        <h3>Added</h3>
        <ul><li>Dark mode for the editor.</li></ul>
        <h3>Changes in 2.0 beta</h3>
        <ul><li>New icon set.</li></ul>
        <h3>Fixed</h3>
        <ul><li>Crash on quit.</li></ul>
        """
        let entry = try #require(AppcastHTMLChangelogParser.entry(html: html, version: "2.0", date: nil))
        #expect(entry.content == [
            .heading("Added"),
            .note("Dark mode for the editor."),
            .note("Changes in 2.0 beta"),
            .note("New icon set."),
            .heading("Fixed"),
            .note("Crash on quit."),
        ])
        #expect(entry.items == ["Dark mode for the editor.", "Changes in 2.0 beta", "New icon set.", "Crash on quit."])
    }

    // MARK: - Fixtures

    static let openClaw2026_9_9 = #"""
<h2>OpenClaw 2026.9.9</h2>
<h3>Highlights</h3>
<ul>
<li><strong>GPT-6.1 Sol support:</strong> update the managed Codex app-server and its embedded model catalog so native Codex sessions can discover and run GPT-6.1 Sol. (#161446, #163560) Thanks @IstiqlalBhat, @fuller-stack-dev, @vincentkoc, and @RomneyDa.</li>
<li><strong>Safer updates:</strong> inspect live WAL ownership without unstable full-database copies and retain published 2026.9.8 updater compatibility. (#162268, #163998) Thanks @RomneyDa.</li>
<li><strong>Responsive background work:</strong> reuse the prepared runtime for Skill Workshop reviews and rooted cron jobs so they no longer stall the Gateway. (#164049) Thanks @RomneyDa.</li>
<li><strong>Windows session recovery:</strong> bind session creation to the physical SQLite store identity so junction-backed stores publish correctly. (#162033) Thanks @cestercian, @RomneyDa, and @zhyx1996.</li>
<li><strong>Cross-platform reliability:</strong> prevent Node process-exit hangs, preserve node work during metadata updates, and restore native Windows workspace and sandbox startup. (#163788, #164087, #164202, #158303) Thanks @paulcam206 and @RomneyDa.</li>
</ul>
<h3>Changes</h3>
<ul>
<li>No intentional capability changes beyond enabling the already-advertised GPT-6.1 Sol model on the managed Codex runtime.</li>
</ul>
<h3>Fixes</h3>
<ul>
<li><strong>Codex:</strong> ship the 0.160.0 managed app-server, synchronized protocol/catalog metadata, and a package-level regression that requires GPT-6.1 Sol in the bundled native catalog. (#161446, #163560) Thanks @IstiqlalBhat, @fuller-stack-dev, @vincentkoc, and @RomneyDa.</li>
<li><strong>Update and Gateway availability:</strong> avoid unstable live-database copies during ownership admission, reuse prepared plugin/runtime facts for rooted work, preserve node work through metadata refreshes, and retain 2026.9.8 first-hop compatibility. (#162268, #164049, #164087, #163998) Thanks @RomneyDa.</li>
<li><strong>Windows:</strong> restore junction-backed session creation, native empty-workspace initialization, and MXC sandbox readiness and wire compatibility. (#162033, #164202, #158303) Thanks @cestercian, @RomneyDa, @zhyx1996, and @paulcam206.</li>
<li><strong>Delivery and scheduling:</strong> restore ordinary iMessage finals, credit Discord thread deliveries, keep Telegram dashboard/control access separate, prevent stale cron cleanup from aborting a later run, and keep queued cancellation from stalling active turns. (#163742, #163756, #161369, #163704, #164230) Thanks @VACInc, @Kimiyu-186, @MertBasar0, @stuart-minion-ai, @mmaps, @joshavant, @jayzhou2309, @AXEG0, @vincentkoc, and @RomneyDa.</li>
<li><strong>CLI lifecycle:</strong> prevent Node 24 and 26 CLI, hook-relay, and Gateway processes from hanging after output. (#163788) Thanks @RomneyDa.</li>
</ul>
<h3>Complete contribution record</h3>
This audited record covers the complete v2026.9.8..bec0cfd9a21a1e6d5900fd0ac859c23f56b45d87 history: 14 in-range PRs + 0 retained seed-only PRs = 14 unique PRs. The generation manifest also supplies direct commits as editorial input; the grouped notes above prioritize user impact.
Shipped baseline exclusions: v2026.9.8 (0 PRs).
<h4>Pull requests</h4>
<ul>
<li><strong>PR #161446</strong> Thanks @IstiqlalBhat and @fuller-stack-dev and @RomneyDa.</li>
<li><strong>PR #163560</strong> Thanks @vincentkoc and @RomneyDa.</li>
<li><strong>PR #163742</strong> Thanks @VACInc and @Kimiyu-186 and @RomneyDa.</li>
<li><strong>PR #163788</strong> Thanks @RomneyDa.</li>
<li><strong>PR #163704</strong> Related #163568. Thanks @jayzhou2309 and @RomneyDa and @AXEG0.</li>
<li><strong>PR #158303</strong> Thanks @paulcam206 and @RomneyDa.</li>
<li><strong>PR #161369</strong> Thanks @mmaps and @joshavant and @RomneyDa.</li>
<li><strong>PR #163756</strong> Related #163724. Thanks @MertBasar0 and @RomneyDa and @stuart-minion-ai.</li>
<li><strong>PR #164087</strong> Thanks @RomneyDa.</li>
<li><strong>PR #164202</strong> Thanks @RomneyDa.</li>
<li><strong>PR #164230</strong> Thanks @vincentkoc and @RomneyDa.</li>
<li><strong>PR #162268</strong> Thanks @RomneyDa.</li>
<li><strong>PR #164049</strong> Thanks @RomneyDa.</li>
<li><strong>PR #162033</strong> Related #161953. Thanks @cestercian and @RomneyDa and @zhyx1996.</li>
</ul>
<p><a href="https://github.com/openclaw/openclaw/blob/main/CHANGELOG.md">View full changelog</a></p>

"""#

    static let superwhisper2_19_0 = #"""

                <b>Features & Improvements</b>
        <ul>
            <li>Faster microphone start when beginning recording across all input devices.</li>
            <li>New Muffle sound option applies a low-pass filter to other apps' audio while you record.</li>
            <li>Lower playback now drops audio to 30% of your current volume instead of a fixed level, so it scales with how loud you're listening.</li>
        </ul>
        
        <b>Fixes</b>
        <ul>
            <li>Fixed issue with "Always Close" option when paste detection fails.</li> 
            <li>Fixed license details not updating in the UI after unlinking a personal license.</li>
            <li>Fixed trial progress bars and trial cards not displaying correctly in the sidebar and License view.</li>
            <li>Fixed text flicker while typing in the agent composer and when sending messages in agent chat.</li>
            <li>Fixed clipboard restore issues when using "Keep what I have copied."</li>
            <li>Fixed the reprocess button unintentionally selecting a mode on a plain click.</li>
        </ul>
                
"""#

    static let superwhisper2_19_2 = #"""

                <b>Fixes</b>
        <ul>
            <li>Fixed an issue where app updates could get stuck during installation.</li>
        </ul>
                
"""#
}
