import Foundation
import Testing
@testable import DuoUpdaterCore

/// 搜狗输入法 — a version read off a changelog page that carries TWO product
/// families, decoded from GBK bytes we never decode as GBK, compared against an
/// installed version that has one segment more than the vendor ever publishes.
/// Each of those is a way to be quietly wrong, so each gets a test.
///
/// The fixture is verbatim from `pinyin.sogou.com/mac/update_log.php` (2026-08-28),
/// trimmed to four entries: the newest 拼音 release, the one before it, an old
/// four-segment 拼音 entry, and a 五笔 entry. The Chinese is written as the
/// replacement characters the real bytes decode to — the page declares
/// `charset=gbk` and the probe reads bodies as UTF-8, so this is what the pattern
/// actually sees, not a prettified version of it.
private let sogouUpdateLogFixture = #"""
<div class="lognavRight fl"><ul class="navRight"><li>
<p class="post_message">
<span class="post_type">\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD} for Mac 6.24.1</span>
<span class="post_time">2026-07-17</span>
</p>
<p class="type_mes"><span>\#u{FFFD}\#u{FFFD}</span><br>
1\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD} emoji<br>
</p></li><li>
<p class="post_message">
<span class="post_type">\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD} for Mac 6.24.0</span>
<span class="post_time">2026-07-08</span>
</p></li><li>
<p class="post_message">
<span class="post_type">\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD} for Mac 2.0.0.26481</span>
<span class="post_time">2018-05-31</span>
</p></li><li>
<p class="post_message">
<span class="post_type">\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}\#u{FFFD}for Mac 1.4.0</span>
<span class="post_time">2023-01-05</span>
</p></li></ul></div>
"""#

private func sogouRecipe() throws -> VendorProbeRecipe {
    try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.sogou.inputmethod.sogou" })
}

@Suite struct SogouInputTests {

    /// The version comes from the entry the slicer picks, and the date comes from
    /// that SAME entry. Both patterns are first-match within one entry, which is
    /// the whole reason `entryStartPattern` is set rather than trusting the page
    /// to stay newest-first.
    @Test func theVersionAndItsDateComeFromOneEntry() throws {
        let recipe = try sogouRecipe()
        let start = try #require(recipe.entryStartPattern)
        let entry = try #require(VendorProbeRecipe.highestVersionEntry(
            in: sogouUpdateLogFixture,
            entryStartPattern: start,
            versionPattern: recipe.versionPattern))

        #expect(VendorProbeRecipe.extractVersion(
            from: entry, pattern: recipe.versionPattern) == "6.24.1")
        let published = try #require(recipe.publishedAtPattern)
        #expect(VendorProbeRecipe.extractVersion(from: entry, pattern: published) == "2026-07-17")
    }

    /// The page publishes 搜狗**五笔**输入法 on the same document. Its titles run the
    /// product name straight into `for Mac` with no space, while every 拼音 entry
    /// has one — measured across all 96 versioned entries on the live page. That
    /// space is the discriminator, and it is the only one available: the character
    /// that would actually distinguish them is Chinese, and the page is GBK while
    /// the probe decodes UTF-8, so 五笔 itself is unmatchable by the time we see it.
    ///
    /// 五笔 being at 1.x is the backstop, not the argument. A magnitude that happens
    /// to lose today is not a rule, and this pins the rule.
    @Test func theWuBiFamilyOnTheSamePageIsNeverSelected() throws {
        let recipe = try sogouRecipe()
        let regex = try NSRegularExpression(pattern: recipe.versionPattern)
        let ns = sogouUpdateLogFixture as NSString
        let matches = regex.matches(
            in: sogouUpdateLogFixture, range: NSRange(location: 0, length: ns.length))
        let found = matches.map { ns.substring(with: $0.range(at: 1)) }

        // Two 拼音 releases, and neither the 五笔 1.4.0 nor the old four-segment
        // entry: `{1,2}` caps the pattern at three segments on purpose.
        #expect(found == ["6.24.1", "6.24.0"], "matched \(found)")
    }

    /// A four-segment entry must not match, and the reason is the failure mode it
    /// buys. If the vendor returns to publishing four segments (they did until
    /// 2018), the newest entries stop matching and selection falls back to an older
    /// three-segment one — so the next release makes the probe report a version
    /// BELOW the installed copy, which the nightly sweep flags as
    /// `remote is BEHIND the installed copy`. Loud, on the next release, rather
    /// than a silently stale answer forever.
    @Test func aFourSegmentEntryIsDeliberatelyNotMatched() throws {
        let recipe = try sogouRecipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: #"<span class="post_type">x for Mac 2.0.0.26481</span>"#,
            pattern: recipe.versionPattern) == nil)
    }

    /// The comparison pair. The bundle says `6.24.1.11676`; the vendor has never
    /// published that fourth segment anywhere. Trimming the installed side is what
    /// makes both sides speak the form the vendor actually uses — without it the
    /// comparator treats the missing segment as `0`, the installed copy out-ranks
    /// every announced release, and the row reads "remote is behind" forever.
    @Test func theInstalledVersionIsTrimmedToWhatTheVendorPublishes() {
        #expect(AppScanner.firstThreeSegments("6.24.1.11676") == "6.24.1")
        // Without the trim, the installed copy wins against the newest release.
        #expect(VersionComparator.isNewer("6.24.1.11676", than: "6.24.1"))
        // With it, they are equal — which is "up to date", the correct answer.
        #expect(VersionComparator.compare(
            AppScanner.firstThreeSegments("6.24.1.11676"), "6.24.1") == .orderedSame)
        // And a real release is still caught.
        #expect(VersionComparator.isNewer("6.25.0", than: AppScanner.firstThreeSegments("6.24.1.11676")))
    }

    /// The trim only fires on the shape it is for. Anything else — a version with
    /// three segments or fewer, a build id with letters, a date-like string — comes
    /// back untouched, so no other app can be mangled by a rule written for this one.
    @Test func theTrimTouchesNothingItWasNotWrittenFor() {
        for untouched in ["6.24.1", "6.24", "6", "2026.1.2.3-beta", "27A5194q", "1.2.3.4a", ""] {
            #expect(AppScanner.firstThreeSegments(untouched) == untouched, "\(untouched)")
        }
        // Only an all-numeric, more-than-three-segment version is trimmed.
        #expect(AppScanner.firstThreeSegments("1.2.3.4.5") == "1.2.3")
    }

    /// Detection only. The full installer owns LaunchAgents, a QuickLook generator,
    /// and user-data migration. The narrower self-update payload is a nested
    /// Contents archive plus migration scripts, and its Info.plist omits the
    /// installed copy's SGQuDao channel with reinjection behavior still unverified.
    /// It needs a dedicated dynamic installer, not the generic bundle/Contents
    /// installer.
    @Test func sogouStaysDetectionOnly() throws {
        let recipe = try sogouRecipe()
        #expect(recipe.install == nil)
        #expect(UpdatePolicy.isInputMethod(
            URL(fileURLWithPath: "/Library/Input Methods/SogouInput.app")))
    }
}
