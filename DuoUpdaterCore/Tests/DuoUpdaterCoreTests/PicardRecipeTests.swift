import Foundation
import Testing

@testable import DuoUpdaterCore

/// The top of `picard.musicbrainz.org/changelog/`, fetched 2026-10-16: the
/// 3.0.2 entry verbatim, the 3.0 entry with its Bugfixes list cut to one item,
/// and the 3.0.0rc4 entry cut to one item, closed by the end of `#log`.
private let picardChangelogFixture = #"""
    <div class="container">
      <div id="log">
        <h3 id="release-3.0.2">Version <strong>3.0.2</strong> <span>2026-10-11</span></h3><h4>Bugfixes</h4>
<ul>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3484">PICARD-3484</a> - Hardcoded link styling in Audio Player options</li>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3485">PICARD-3485</a> - Sticky grey background in metadata pane</li>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3490">PICARD-3490</a> - Program crash after wizard if build with <code>--disable-autoupdate</code></li>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3491">PICARD-3491</a> - Text color issues in dark mode in metadata pane and placeholder texts</li>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3494">PICARD-3494</a> - Plugin manager &quot;View Repository&quot; fails silently when remote is a local path</li>
</ul>
<h3 id="release-3.0">Version <strong>3.0</strong> <span>2026-10-04</span></h3><h4>Bugfixes</h4>
<ul>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-2172">PICARD-2172</a> - Using &quot;Use original values&quot; on a large number of recordings will skyrocket memory usage</li>
</ul>
<h4>Improvements</h4>
<ul>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3472">PICARD-3472</a> - Cluster matching picks the wrong release when the correct one has a placeholder catalog number, or when a wrong-artist release shares the album title</li>
</ul>
<h3 id="release-3.0.0rc4">Version <strong>3.0.0rc4</strong> <span>2026-09-22</span></h3><h4>Bugfixes</h4>
<ul>
<li><a href="https://tickets.metabrainz.org/browse/PICARD-3439">PICARD-3439</a> - Unexpected font change in script editors after pasting</li>
</ul>
      </div>
    </div><!-- /.container -->
"""#

struct PicardRecipeTests {
    static func rule() throws -> GitHubReleaseRule {
        try #require(GitHubReleaseRegistry.rules.first { $0.bundleID == "org.musicbrainz.Picard" })
    }

    /// Every final tag shape the repo has used reads whole, two-part .0 releases
    /// included; pre-release tags read nothing — `release-2.6.0b3` among them,
    /// which GitHub does not flag as a prerelease.
    @Test func versionPatternReadsFinalTagsOnly() throws {
        let rule = try Self.rule()
        #expect(rule.usePrereleases == false)
        #expect(rule.channel == .stable)
        for (tag, version) in [
            ("release-3.0.2", "3.0.2"), ("release-3.0", "3.0"), ("release-2.13.3", "2.13.3"),
            ("release-2.0.0", "2.0.0"), ("release-4.0", "4.0"), ("release-10.1.2", "10.1.2"),
        ] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern) == version)
        }
        for tag in [
            "release-3.0.0rc4", "release-3.0.0b9", "release-3.0.0a1", "release-2.6.0b3",
            "release-2.1.0dev3", "2.0.0dev6", "2.0.0.dev4", "release-1.4.2-1",
        ] {
            #expect(VendorProbeRecipe.extractVersion(from: tag, pattern: rule.versionPattern) == nil,
                    "\(tag)")
        }
    }

    /// One-click picks the arm64 dmg out of release-3.0.2's assets (verbatim
    /// names, in GitHub's order), and still does after a floor change.
    @Test func installsTheArm64Dmg() throws {
        let rule = try Self.rule()
        #expect(rule.installerKind == .dmg)
        let pattern = try #require(rule.installAssetPattern)
        let names = [
            "MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg", "MusicBrainz-Picard-3.0.2-macOS-13.0-x86_64.dmg",
            "MusicBrainz-Picard-3.0.2.exe", "MusicBrainz-Picard-3.0.2.msix", "picard-3.0.2.tar.gz",
            "picard-3.0.2.tar.gz.asc", "picard-setup-3.0.2.exe", "SHA256SUMS",
        ]
        let matched = names.filter { $0.range(of: pattern, options: .regularExpression) != nil }
        #expect(matched == ["MusicBrainz-Picard-3.0.2-macOS-13.0-arm64.dmg"])
        #expect("MusicBrainz-Picard-3.1-macOS-14.0-arm64.dmg"
            .range(of: pattern, options: .regularExpression) != nil)
    }

    /// A 2.0.x copy, still `org.musicbrainz.picard`, is filed under the current
    /// id; a lower-case copy at or past 2.3.1 is not that rename. Mutation: drop
    /// the Picard entry from `BundleIDMigration.all` → the first expectation fails.
    @Test func aLowerCaseIdCopyIsFiledUnderTheCurrentId() {
        #expect(BundleIDMigration.recipeBundleID(
            for: "org.musicbrainz.picard", installedVersion: "2.0.4") == "org.musicbrainz.Picard")
        #expect(BundleIDMigration.recipeBundleID(
            for: "org.musicbrainz.picard", installedVersion: "2.3.1") == "org.musicbrainz.picard")
    }

    @Test func changelogKeepsSectionsAndPreReleaseEntries() throws {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "org.musicbrainz.Picard"))
        let log = try #require(ChangelogExtractor.extract(from: picardChangelogFixture, using: recipe))

        #expect(log.entries.map(\.version) == ["3.0.2", "3.0", "3.0.0rc4"])
        #expect(log.entries.map(\.date) == ["2026-10-11", "2026-10-04", "2026-09-22"])
        #expect(log.entries[0].items == [
            "PICARD-3484 - Hardcoded link styling in Audio Player options",
            "PICARD-3485 - Sticky grey background in metadata pane",
            "PICARD-3490 - Program crash after wizard if build with --disable-autoupdate",
            "PICARD-3491 - Text color issues in dark mode in metadata pane and placeholder texts",
            "PICARD-3494 - Plugin manager \"View Repository\" fails silently when remote is a local path",
        ])
        let three = log.entries[1]
        #expect(three.content == [
            .heading("Bugfixes"),
            .note(three.items[0]),
            .heading("Improvements"),
            .note(three.items[1]),
        ])
        #expect(log.entries[2].items == [
            "PICARD-3439 - Unexpected font change in script editors after pasting",
        ])
    }
}
