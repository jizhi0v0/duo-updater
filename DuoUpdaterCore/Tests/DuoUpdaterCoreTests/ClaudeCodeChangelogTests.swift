import Testing
import Foundation
@testable import DuoUpdaterCore

/// Claude Code's `CHANGELOG.md`, parsed, and the slice of it one install's reader
/// is shown. Fixture text only — nothing here reaches the network.
@Suite struct ClaudeCodeChangelogTests {

    /// The shape of the vendor's file on 2026-09-30, cut down: a title, then
    /// `## <version>` sections of `- ` bullets, newest first, with a version gap
    /// (no 2.1.279) exactly as the real file has one.
    static let fixture = """
    # Changelog

    ## 2.1.285

    - Added `CLAUDE_CODE_DISABLE_WEB_FETCH` environment variable to turn off the WebFetch tool
    - Fixed plugin installs over SSH ignoring `GIT_SSH`

    ## 2.1.284

    - Fixed one thing

    ## 2.1.280

    - Stable-channel release
      wrapped onto a second line

    ## 2.1.278

    - Older

    ## 2.1.100

    - Much older

    ## 2.1.99

    - Oldest
    """

    static func versions(_ changelog: Changelog?) -> [String] { changelog?.entries.map(\.version) ?? [] }

    static var parsed: Changelog { ClaudeCodeChangelog.parse(fixture)! }

    // MARK: - Parsing

    /// Mutation: dropping the `hasPrefix("- ")` strip keeps the dash in each item.
    @Test func sectionsAndBulletsComeOutInFileOrder() throws {
        let log = try #require(ClaudeCodeChangelog.parse(Self.fixture))
        #expect(Self.versions(log) == ["2.1.285", "2.1.284", "2.1.280", "2.1.278", "2.1.100", "2.1.99"])
        #expect(log.entries[0].items == [
            "Added `CLAUDE_CODE_DISABLE_WEB_FETCH` environment variable to turn off the WebFetch tool",
            "Fixed plugin installs over SSH ignoring `GIT_SSH`",
        ])
        // Backticks are the vendor's Markdown: the renderer has to be told.
        #expect(log.itemSyntax == .markdown)
    }

    /// Mutation: appending a continuation line as its own item fails this.
    @Test func aWrappedBulletIsOneItem() {
        let entry = Self.parsed.entries.first { $0.version == "2.1.280" }
        #expect(entry?.items == ["Stable-channel release wrapped onto a second line"])
    }

    /// A heading that is not a version ends the section above it, so what follows
    /// is not filed under the wrong release. Mutation: keeping `version` across a
    /// non-version heading puts "Not a release" under 1.0.1.
    @Test func aNonVersionHeadingClosesTheSection() {
        let log = ClaudeCodeChangelog.parse("""
        ## 1.0.1
        - Real
        ## Unreleased
        - Not a release
        ### Notes
        - Also not
        ## 1.0.0
        - Earlier
        """)
        #expect(Self.versions(log) == ["1.0.1", "1.0.0"])
        #expect(log?.entries.first?.items == ["Real"])
    }

    /// What GitHub serves for a missing file, and a section with nothing in it.
    /// Mutation: returning an empty `Changelog` instead of nil fails the first.
    @Test func noSectionIsNil() {
        #expect(ClaudeCodeChangelog.parse("404: Not Found") == nil)
        #expect(ClaudeCodeChangelog.parse("# Changelog\n\n## 2.0.0\n\n") == nil)
    }

    // MARK: - Which sections a reader sees

    /// Behind: every release not taken, up to the channel's latest — then the
    /// installed one and older, to make up the minimum.
    @Test func behindShowsWhatIsNewThenFillsWithWhatTheyHave() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.278", latest: "2.1.285", minimum: 5)
        #expect(Self.versions(log) == ["2.1.285", "2.1.284", "2.1.280", "2.1.278", "2.1.100"])
    }

    /// More unseen releases than the minimum: all of them, and nothing older.
    /// Mutation: `prefix(minimum)` over everything cuts 2.1.278 and 2.1.100 short.
    @Test func everyUnseenReleaseIsShownEvenPastTheMinimum() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.99", latest: "2.1.285", minimum: 2)
        #expect(Self.versions(log) == ["2.1.285", "2.1.284", "2.1.280", "2.1.278", "2.1.100"])
    }

    /// A `stable` reader is not shown what only `latest` has. Mutation: dropping the
    /// ceiling filter lets 2.1.285 and 2.1.284 in.
    @Test func nothingPastTheChannelsLatest() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.278", latest: "2.1.280", minimum: 1)
        #expect(Self.versions(log) == ["2.1.280"])
    }

    /// Up to date: the latest few, starting at their own version.
    @Test func upToDateShowsTheLatestFew() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.280", latest: "2.1.280", minimum: 3)
        #expect(Self.versions(log) == ["2.1.280", "2.1.278", "2.1.100"])
    }

    /// Versions compare as versions: 2.1.100 is newer than 2.1.99 although it sorts
    /// before it as text. Mutation: comparing with `<` on the strings shows 2.1.99's
    /// notes as unseen to a reader on 2.1.100.
    @Test func versionsCompareNumerically() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.100", latest: "2.1.100", minimum: 1)
        #expect(Self.versions(log) == ["2.1.100"])
    }

    /// Ahead of the channel (a `latest` build on a Mac now set to `stable`): the
    /// ceiling is their own version, so the notes for what they run are there.
    /// Mutation: always using `latest` as the ceiling drops 2.1.284.
    @Test func aheadReadsUpToTheirOwnVersion() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.284", latest: "2.1.280", minimum: 2)
        #expect(Self.versions(log) == ["2.1.284", "2.1.280"])
    }

    /// Channel unreadable: nothing past what they run, since nothing says the newer
    /// sections are on their channel.
    @Test func withoutLatestTheCeilingIsTheInstalledVersion() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: "2.1.280", latest: nil, minimum: 2)
        #expect(Self.versions(log) == ["2.1.280", "2.1.278"])
    }

    /// Version unreadable: nothing counts as unseen, so it is just the latest few.
    @Test func withoutInstalledNothingIsUnseen() {
        let log = ClaudeCodeChangelog.relevant(Self.parsed, installed: nil, latest: "2.1.284", minimum: 2)
        #expect(Self.versions(log) == ["2.1.284", "2.1.280"])
    }

    /// A section filed out of order still lands in its place. Mutation: dropping the
    /// sort shows 2.1.278 (already installed) as the first "new" release and
    /// leaves 2.1.285 behind the unseen/taken split.
    @Test func aSectionFiledOutOfOrderIsSortedIn() throws {
        let log = try #require(ClaudeCodeChangelog.parse("""
        ## 2.1.278
        - Older
        ## 2.1.285
        - Newest
        ## 2.1.280
        - Middle
        """))
        let picked = ClaudeCodeChangelog.relevant(log, installed: "2.1.280", latest: "2.1.285", minimum: 2)
        #expect(Self.versions(picked) == ["2.1.285", "2.1.280"])
    }

    @Test func nothingAtOrBelowTheCeilingIsNil() {
        #expect(ClaudeCodeChangelog.relevant(Self.parsed, installed: "1.0.0", latest: "1.0.0") == nil)
    }
}
