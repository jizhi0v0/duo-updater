import Testing
import Foundation
@testable import DuoUpdaterCore

/// `CLIToolChangelog.breakingVersions`: which versions an update brings the
/// vendor's notes mark breaking. The lines are the vendors' own, as their
/// parsers produced them on 2026-10-12.
@Suite struct CLIToolBreakingTests {

    static func entry(
        _ version: String, items: [String] = ["Fix a thing"], headings: [String] = [], markdown: String? = nil
    ) -> Changelog.Entry {
        Changelog.Entry(version: version, date: nil, items: items,
                        content: headings.map { .heading($0) } + items.map { .note($0) }, markdown: markdown)
    }

    static func marked(_ entry: Changelog.Entry) -> Bool { CLIToolChangelog.isMarkedBreaking(entry) }

    // MARK: - Markers

    @Test func categoryHeadingsMark() {
        #expect(Self.marked(Self.entry("0.0.13", headings: ["Breaking Changes", "New Features"])))  // fx, mise
        #expect(Self.marked(Self.entry("0.13.0", headings: ["Breaking changes", "Enhancements"])))  // uv, GHCup
        #expect(Self.marked(Self.entry("0.5.1", headings: ["🚨 Breaking Changes", "🚀 Features"])))  // bub
    }

    @Test func markdownHeadingsMark() {
        #expect(Self.marked(Self.entry("0.2.1.0", markdown: "### New features\n- a\n\n### Breaking changes\n- b")))
    }

    @Test func linesThatOpenWithTheWordMark() {
        for line in [
            "Breaking change: --print JSON output now returns nested message objects",  // Claude Code
            "**BREAKING**: remove total_history from api index response ([#3094](…))",  // Atuin
            "**Breaking:** Default prefix key changed from `ctrl+s` to `ctrl+b`",  // Herdr
            "**Breaking — Node runtime:** require Node 24.16.0 or newer on 24.x",  // openclaw
            "**`vp test` now runs upstream Vitest directly (breaking)**: Vite+ used to ship",  // Vite+
        ] {
            #expect(Self.marked(Self.entry("1.0.0", items: [line])), "\(line)")
        }
    }

    @Test func theWordElsewhereDoesNotMark() {
        for line in [
            "Fixed tab bars in dialogs such as `/config` and `/plugin` breaking the title",  // Claude Code
            "No breaking changes, maintaining backward compatibility",  // bub
            "Ignore malformed model pricing instead of breaking usage cost calculation.",  // OpenCode
            "Fix installed-package checks incorrectly reporting post-releases as incompatible",  // uv
        ] {
            #expect(!Self.marked(Self.entry("1.0.0", items: [line])), "\(line)")
        }
    }

    @Test func otherNoticeHeadingsDoNotMark() {
        #expect(!Self.marked(Self.entry("1.99.0", headings: ["Compatibility Notes", "Libraries"])))  // Rust
        #expect(!Self.marked(Self.entry("0.9.0", headings: ["Removed", "Changed"])))  // zoxide
        #expect(!Self.marked(Self.entry("2026.10.7", headings: ["Deprecated", "Fixed"])))  // mise
    }

    // MARK: - Range

    static let notes = Changelog(entries: [
        entry("0.14.0", headings: ["Breaking changes"]),
        entry("0.13.1"),
        entry("0.13.0", headings: ["Breaking changes"]),
        entry("0.12.5", items: ["Breaking change: something"]),
        entry("0.12.4"),
        entry("0.12.0", headings: ["Breaking changes"]),
    ])

    @Test func readsOnlyAboveInstalledUpToLatest() {
        // 0.14.0 is past the channel's latest; 0.12.0 is the install's own.
        #expect(CLIToolChangelog.breakingVersions(in: Self.notes, installed: "0.12.0", latest: "0.13.1")
                == ["0.12.5", "0.13.0"])
    }

    @Test func latestItselfCounts() {
        #expect(CLIToolChangelog.breakingVersions(in: Self.notes, installed: "0.13.1", latest: "0.14.0")
                == ["0.14.0"])
    }

    @Test func nothingMarkedInRangeIsEmpty() {
        #expect(CLIToolChangelog.breakingVersions(in: Self.notes, installed: "0.13.0", latest: "0.13.1").isEmpty)
    }

    @Test func eitherEndUnknownIsEmpty() {
        #expect(CLIToolChangelog.breakingVersions(in: Self.notes, installed: nil, latest: "0.14.0").isEmpty)
        #expect(CLIToolChangelog.breakingVersions(in: Self.notes, installed: "0.12.0", latest: nil).isEmpty)
    }

    @Test func wording() {
        #expect(CLIToolWording.breaking(["0.12.5", "0.13.0"])
                == "The release notes mark breaking changes in 0.12.5, 0.13.0")
    }
}
