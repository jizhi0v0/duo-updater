import Testing
import Foundation
@testable import DuoUpdaterCore

/// Homebrew's own release notes for the self-update row (`HomebrewReleaseNotes`).
///
/// Bodies are invented in the shape `Homebrew/brew`'s generated notes had on
/// 2026-10-09 (`## What's Changed`, `* <title> by @user in <pull URL>`,
/// `## New Contributors`, `**Full Changelog**`), not fetched: the latest release
/// must not change a test's answer.
@Suite struct HomebrewReleaseNotesTests {

    private static func body(_ titles: [String], newContributor: Bool = false) -> String {
        var lines = [
            "<!-- Release notes generated using configuration in .github/release.yml at main -->",
            "",
            "## What's Changed",
        ]
        for (index, title) in titles.enumerated() {
            lines.append("* \(title) by @zzfixture-dev in https://github.com/Homebrew/brew/pull/\(90000 + index)")
        }
        if newContributor {
            lines += [
                "",
                "## New Contributors",
                "* @zzfixture-new made their first contribution in https://github.com/Homebrew/brew/pull/90999",
            ]
        }
        lines += ["", "", "**Full Changelog**: https://github.com/Homebrew/brew/compare/9.0.0...9.0.1"]
        return lines.joined(separator: "\n")
    }

    private static func release(_ tag: String, _ titles: [String], prerelease: Bool = false,
                                newContributor: Bool = false) -> [String: Any] {
        ["tag_name": tag, "prerelease": prerelease, "draft": false,
         "published_at": "2026-10-01T10:00:00Z", "body": body(titles, newContributor: newContributor)]
    }

    private static func json(_ releases: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: releases), as: UTF8.self)
    }

    private static func feed() throws -> Changelog {
        try #require(HomebrewReleaseNotes.parse(try json([
            release("9.1.0", ["ZZ eleven"]),
            release("9.0.10", ["ZZ ten a", "ZZ ten b"], newContributor: true),
            release("9.0.9", ["ZZ nine"]),
            release("9.0.8", ["ZZ eight"]),
            release("9.0.7", ["ZZ seven"]),
            release("9.0.6", ["ZZ six"]),
        ])))
    }

    // MARK: - parse

    /// The pull request bullets only: the generator comment, the new-contributor
    /// section, the full-changelog link and each bullet's `by @user in <URL>` tail
    /// stay out.
    @Test func keepsTheChangesAndDropsTheGeneratedNoise() throws {
        let log = try #require(HomebrewReleaseNotes.parse(try Self.json([
            Self.release("9.0.10", ["formula: ZZ fix one", "ZZ fix two"], newContributor: true),
        ])))
        let entry = try #require(log.entries.first)
        #expect(entry.version == "9.0.10")
        #expect(entry.date == "2026-10-01")
        #expect(entry.items == ["formula: ZZ fix one", "ZZ fix two"])
        #expect(log.itemSyntax == .markdown)
    }

    /// Mutation: drop the `tagPattern` → a tag that is not a bare release
    /// (`nightly`) becomes an entry of its own.
    @Test func readsOnlyBareReleaseTags() throws {
        let log = try #require(HomebrewReleaseNotes.parse(try Self.json([
            Self.release("nightly", ["ZZ nightly"]),
            Self.release("9.0.1", ["ZZ one"]),
            Self.release("9.0.2-rc1", ["ZZ candidate"], prerelease: true),
        ])))
        #expect(log.entries.map(\.version) == ["9.0.1"])
    }

    @Test func nothingReadableIsNil() throws {
        #expect(HomebrewReleaseNotes.parse("[]") == nil)
        #expect(HomebrewReleaseNotes.parse(#"{"message":"API rate limit exceeded"}"#) == nil)
    }

    // MARK: - relevant

    /// Mutation: a `minimum` above 0 → the installed release and older ones are
    /// listed too; a ceiling other than `latest` → 9.1.0, not on offer, appears.
    @Test func listsWhatTheUpdateBringsAndNothingElse() throws {
        let update = HomebrewSelfUpdate(installed: "9.0.7", latest: "9.0.10")
        let cut = try #require(HomebrewReleaseNotes.relevant(try Self.feed(), for: update))
        #expect(cut.entries.map(\.version) == ["9.0.10", "9.0.9", "9.0.8"])
    }

    /// A developer-mode checkout (`9.0.7-8-g…`) is past 9.0.7 and before 9.0.8.
    /// No guard of this file's own: this pins `VersionComparator`'s reading of
    /// the `git describe` suffix, which the cut relies on.
    @Test func developerModeIsReadByItsReleasePart() throws {
        for installed in ["9.0.7-8-gabc1234", "9.0.7-312-g0123456-dirty"] {
            let update = HomebrewSelfUpdate(installed: installed, latest: "9.0.10")
            let cut = try #require(HomebrewReleaseNotes.relevant(try Self.feed(), for: update))
            #expect(cut.entries.map(\.version) == ["9.0.10", "9.0.9", "9.0.8"])
        }
    }

    /// Notes not published yet for anything newer than the installed release.
    @Test func noNewReleaseNotesIsNil() throws {
        let update = HomebrewSelfUpdate(installed: "9.1.0", latest: "9.1.1")
        #expect(HomebrewReleaseNotes.relevant(try Self.feed(), for: update) == nil)
    }
}
