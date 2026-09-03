import Testing
import Foundation
@testable import DuoUpdaterCore

/// Apple's release notes are the one changelog in this registry that a regex
/// cannot read: the visible text of a note is an array of runs, and on the live
/// Xcode 27 page 83 of 335 notes have more than one, so "capture the text" means
/// "capture the first quarter of a sentence". These tests pin the two things
/// that follow from that — runs are joined, and the section a note was filed
/// under travels with it — plus the URL mapping, which is the other half of the
/// recipe and the half that fails silently (a wrong page still parses).
///
/// Fixture: real blocks from
/// `developer.apple.com/tutorials/data/documentation/xcode-release-notes/xcode-27-release-notes.json`
/// (fetched 2026-09-03) — the Overview, one topic from the current beta, one
/// note carrying a link, and the head of the `Updates in Xcode 27 Beta 5`
/// section.
@Suite struct XcodeReleaseNotesChangelogTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.apple.dt.Xcode"))
        let format = try #require(recipe.structuredFormat)
        return try #require(StructuredChangelogDecoder.decode(
            xcodeReleaseNotesFixture, format: format, channel: nil,
            maxEntries: recipe.maxEntries))
    }

    /// One page carries the whole train: the blocks above the first
    /// `Updates in …` heading are the newest build, each heading below opens an
    /// earlier one.
    @Test func splitsTheTrainPageIntoOneEntryPerBuild() throws {
        let entries = try changelog().entries
        #expect(entries.map(\.version) == ["Xcode 27 Beta 6", "Xcode 27 Beta 5"])
        // No dates anywhere on these pages; better empty than invented.
        #expect(entries.allSatisfy { $0.date == nil })
    }

    /// The note reads "When streaming `stdout` and `stderr` from multiple
    /// processes…" — three text runs around two code runs. A first-fragment
    /// capture would have stopped at "When streaming ".
    @Test func joinsEveryRunOfANote() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains {
            $0.hasSuffix("When streaming stdout and stderr from multiple processes at the "
                + "same time (for example: in parallel testing scenarios), the results may "
                + "be significantly delayed.  (165098287)")
        })
    }

    /// A link contributes the words the document's reference table gives it, so
    /// the sentence closes instead of running into a hole.
    @Test func resolvesLinksToTheirTitle() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains {
            $0.contains("follow the How to reinstall macOS guide.")
        })
    }

    /// "Known Issues" versus "New Features" is the level-4 heading and nothing
    /// else. Flatten it away and every known issue reads as a shipped feature.
    @Test func everyNoteKeepsItsSection() throws {
        let newest = try #require(try changelog().entries.first)
        #expect(newest.items.contains { $0.hasPrefix("General · Known Issues: ") })
        #expect(newest.items.contains { $0.hasPrefix("Code Intelligence · New Features: ") })
        // The Overview paragraphs sit under no topic and are left unlabelled.
        #expect(newest.items.first?.hasPrefix("Xcode 27 beta 6 includes Swift 6.4") == true)
    }

    /// Inside an `Updates in Xcode 27 Beta 5` section every kind heading repeats
    /// the build ("New Features in Xcode 27 Beta 5"), which the entry already
    /// names — so the label drops it rather than saying it twice on every line.
    @Test func theKindHeadingDoesNotRepeatTheBuild() throws {
        let earlier = try #require(try changelog().entries.last)
        #expect(earlier.version == "Xcode 27 Beta 5")
        #expect(!earlier.items.isEmpty)
        #expect(earlier.items.allSatisfy {
            $0.hasPrefix("Coding Intelligence · New Features: ")
        })
    }

    /// The other half of the recipe. Apple's path spells a `.0` release by its
    /// major and everything else with underscores; a prerelease's display version
    /// carries its track, and every beta of a train shares that train's page.
    /// Expected values read off `links.notes.url` in `xcodereleases.com/data.json`.
    @Test func resolvesApplesOwnPathForEveryReleaseShape() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.apple.dt.Xcode"))
        let page = { (version: String) in
            recipe.resolvedSource(forVersion: version).lastPathComponent
        }
        #expect(page("27.0 beta 6") == "xcode-27-release-notes.json")
        #expect(page("27.0 Release Candidate") == "xcode-27-release-notes.json")
        #expect(page("27.0") == "xcode-27-release-notes.json")
        #expect(page("26.6") == "xcode-26_6-release-notes.json")
        #expect(page("26.1 beta 2") == "xcode-26_1-release-notes.json")
        // A trailing zero is only dropped from a two-part version: `xcode-26_0_1`
        // is a real page and `xcode-26` is a different one.
        #expect(page("26.0.1") == "xcode-26_0_1-release-notes.json")
        #expect(page("26.0") == "xcode-26-release-notes.json")
    }

    /// `{major}`, the closest existing token, maps every 26.x onto the Xcode 26.0
    /// page — and Apple ships betas for nearly every minor, so that is the common
    /// case rather than a corner. Pinned so nobody "simplifies" the token away.
    @Test func majorAloneWouldReadTheWrongPage() {
        #expect(ChangelogRecipe.appleDocVersionToken(for: "26.5 beta 3") == "26_5")
        #expect(ChangelogRecipe.appleDocVersionToken(for: "26.5 beta 3") != "26")
    }
}

private let xcodeReleaseNotesFixture = #"""
{"metadata":{"role":"article","roleHeading":"Article","title":"Xcode 27 Beta 6 Release Notes"},"primaryContentSections":[{"kind":"content","content":[{"anchor":"Overview","level":2,"text":"Overview","type":"heading"},{"inlineContent":[{"text":"Xcode 27 beta 6 includes Swift 6.4 and SDKs for iOS 27, iPadOS 27, tvOS 27, watchOS 27, macOS 27, and visionOS 27.","type":"text"},{"text":" ","type":"text"},{"text":"Xcode 27 beta 6 supports on-device debugging in iOS 17 and later, tvOS 17 and later, watchOS 10 and later, and visionOS.","type":"text"},{"text":" ","type":"text"},{"text":"Xcode 27 beta 6 requires a Mac running macOS Tahoe 26.4 or later.","type":"text"}],"type":"paragraph"},{"inlineContent":[{"text":"See ","type":"text"},{"identifier":"https://developer.apple.com/support/xcode/","isActive":true,"type":"reference"},{"text":" to learn more about compatible platforms and deployment targets.","type":"text"}],"type":"paragraph"},{"anchor":"General","level":3,"text":"General","type":"heading"},{"anchor":"Known-Issues","level":4,"text":"Known Issues","type":"heading"},{"items":[{"content":[{"inlineContent":[{"text":"When streaming ","type":"text"},{"code":"stdout","type":"codeVoice"},{"text":" and ","type":"text"},{"code":"stderr","type":"codeVoice"},{"text":" from multiple processes at the same time (for example: in parallel testing scenarios), the results may be significantly delayed.  (165098287)","type":"text"}],"type":"paragraph"}]},{"content":[{"inlineContent":[{"text":"The Coding Assistant artifact view shows preview snapshots from all turns even when the Scope filter is set to Last Turn.  (185119267)","type":"text"}],"type":"paragraph"}]}],"type":"unorderedList"},{"type":"heading","level":3,"text":"Code Intelligence","anchor":"Code-Intelligence"},{"type":"heading","level":4,"text":"New Features","anchor":"New-Features"},{"type":"unorderedList","items":[{"content":[{"inlineContent":[{"text":"Fixed: If you installed Xcode 27 beta on macOS Tahoe 26.5.1 and earlier, macOS virtual machine installation will fail due to a known bug. To restore virtual machine installation functionality, follow the ","type":"text"},{"identifier":"https://support.apple.com/en-us/102655","isActive":true,"type":"reference"},{"text":".  (179068335)","type":"text"}],"type":"paragraph"}]}]},{"anchor":"Updates-in-Xcode-27-Beta-5","level":2,"text":"Updates in Xcode 27 Beta 5","type":"heading"},{"anchor":"Coding-Intelligence","level":3,"text":"Coding Intelligence","type":"heading"},{"anchor":"New-Features-in-Xcode-27-Beta-5","level":4,"text":"New Features in Xcode 27 Beta 5","type":"heading"},{"items":[{"content":[{"inlineContent":[{"text":"Coding Intelligence agents can now verify watchOS apps, including rotating and pressing the Digital Crown, and pressing the side and Action buttons (Apple Watch Ultra).  (181147968)","type":"text"}],"type":"paragraph"}]},{"content":[{"inlineContent":[{"text":"Xcode 27 Beta 5 adds a preview of a new MCP server experience that runs without requiring an open Xcode workspace. This new experience also allows you to grant code-signed agents permission to use projects within a directory tree for extended periods of time without being asked for additional permissions.","type":"text"}],"type":"paragraph"},{"inlineContent":[{"text":"You can turn this experience on by using ","type":"text"},{"code":"sudo xcrun mcp-server enable","type":"codeVoice"},{"text":". Check its state afterward with ","type":"text"},{"code":"xcrun mcp-server status","type":"codeVoice"},{"text":".","type":"text"}],"type":"paragraph"},{"inlineContent":[{"text":"Developers running agents in unattended environments can approve all permissions upfront with ","type":"text"},{"code":"sudo xcrun mcp-server enable --unsafe-always-allow-all-agents","type":"codeVoice"},{"text":". This is not a recommended configuration for at-desk use.","type":"text"}],"type":"paragraph"},{"inlineContent":[{"text":"In this early preview, some aspects of the ","type":"text"},{"code":"xcrun mcp-server","type":"codeVoice"},{"text":" command line utility may not work in all configurations, and some settings or permissions may occasionally require relaunching Xcode or rebooting your machine to apply.  (181836944)","type":"text"}],"type":"paragraph"}]}],"type":"unorderedList"}]}],"references":{"https://support.apple.com/en-us/102655":{"title":"How to reinstall macOS guide","url":"https://support.apple.com/en-us/102655","type":"link"},"https://developer.apple.com/support/xcode/":{"title":"Xcode Support","url":"https://developer.apple.com/support/xcode/","type":"link"}}}
"""#
