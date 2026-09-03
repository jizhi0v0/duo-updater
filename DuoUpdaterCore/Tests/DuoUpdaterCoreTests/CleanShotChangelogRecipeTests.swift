import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two blocks of `cleanshot.com/changelog`, fetched 2026-09-01 — the 5.0 release
/// and the 4.8.10 one under it. The `<svg>` icons are elided and 5.0's list is cut
/// to three of its twenty items; every byte kept is verbatim, including the Vue
/// scope attributes and the `<!--[-->` fragment markers, because those are what the
/// pattern has to tolerate.
///
/// The two blocks are not interchangeable. 4.8.10 is the ordinary shape: date,
/// number, list. 5.0 is a feature release, so it also carries a badge, an
/// introduction and two video links between the number and the list — the gap the
/// pattern has to cross.
private let cleanShotChangelogFixture = #"""
<section class="versions" data-v-0266dac0><div class="version" data-v-0266dac0 data-v-55b70507><div class="date" data-v-55b70507>1 September, 2026</div><div class="content" data-v-55b70507><div class="topbar" data-v-55b70507><div class="number" data-v-55b70507>5.0</div><div class="text-badge" data-v-55b70507 data-v-ab785faa> Major Update</div></div><!--[--><p class="change-intro" data-v-0266dac0 data-v-55b70507-s> We&#39;re excited to announce our biggest update yet! The new Studio Mode is all you need to turn a simple screen recording into a polished, professional video - all with the quality you expect from CleanShot. </p><a class="video-link" href="https://www.youtube.com/watch?v=PzlKjndagGU&amp;utm_source=changelog" target="_blank" rel="noopener" data-v-0266dac0 data-v-55b70507-s><button class="action-button -small -primary" data-v-0266dac0 data-v-55b70507-s data-v-360e2e8b><span class="label" data-v-360e2e8b><!--[-->Watch teaser<!--]--></span><!----><!----></button></a><a class="video-link" href="https://www.youtube.com/watch?v=fUB1s3RaD7c&amp;utm_source=changelog" target="_blank" rel="noopener" data-v-0266dac0 data-v-55b70507-s><span class="text-button -primary" data-v-0266dac0 data-v-55b70507-s data-v-dee04dfb><span data-v-dee04dfb><!--[-->Full walkthrough (7:00)<!--]--></span><!----></span></a><!--]--><!--[--><ul class="changes" data-v-0266dac0 data-v-55b70507-s><li class="change" data-v-0266dac0 data-v-55b70507-s>🎬 <span class="bold" data-v-0266dac0 data-v-55b70507-s>Introducing Studio Mode and a brand-new Video Editor</span></li><li class="change" data-v-0266dac0 data-v-55b70507-s> ✨ <span class="bold" data-v-0266dac0 data-v-55b70507-s>Smart Zooms</span> - Add smooth zooms that follow your cursor and draw attention to what matters most </li><li class="change" data-v-0266dac0 data-v-55b70507-s> ✂️ <span class="bold" data-v-0266dac0 data-v-55b70507-s>Advanced video editing</span> - Trim mistakes and fine-tune details so every recording looks polished </li></ul><!--]--></div></div><div class="version" data-v-0266dac0 data-v-55b70507><div class="date" data-v-55b70507>21 July, 2026</div><div class="content" data-v-55b70507><div class="topbar" data-v-55b70507><div class="number" data-v-55b70507>4.8.10</div><!----></div><!--[--><!--]--><!--[--><ul class="changes" data-v-0266dac0 data-v-55b70507-s><li class="change" data-v-0266dac0 data-v-55b70507-s><strong data-v-0266dac0 data-v-55b70507-s>Important security update recommended for all users</strong></li><li class="change" data-v-0266dac0 data-v-55b70507-s>Improved capture history performance</li><li class="change" data-v-0266dac0 data-v-55b70507-s> Fixed bug with the &quot;Ask for Name after every capture&quot; dialog not receiving focus on macOS Tahoe </li></ul><!--]--></div></div></section>
"""#

/// The same 5.0 block with its `<ul class="changes">` taken out — a shape the live
/// page does not currently contain (all 102 blocks on it have a list) and the one
/// that decides whether a lazy gap or a tempered one is correct.
private let cleanShotBlockWithoutAListFixture = #"""
<section class="versions" data-v-0266dac0><div class="version" data-v-0266dac0 data-v-55b70507><div class="date" data-v-55b70507>1 September, 2026</div><div class="content" data-v-55b70507><div class="topbar" data-v-55b70507><div class="number" data-v-55b70507>5.0</div><div class="text-badge" data-v-55b70507 data-v-ab785faa> Major Update</div></div><!--[--><p class="change-intro" data-v-0266dac0 data-v-55b70507-s> We&#39;re excited to announce our biggest update yet! The new Studio Mode is all you need to turn a simple screen recording into a polished, professional video - all with the quality you expect from CleanShot. </p><a class="video-link" href="https://www.youtube.com/watch?v=PzlKjndagGU&amp;utm_source=changelog" target="_blank" rel="noopener" data-v-0266dac0 data-v-55b70507-s><button class="action-button -small -primary" data-v-0266dac0 data-v-55b70507-s data-v-360e2e8b><span class="label" data-v-360e2e8b><!--[-->Watch teaser<!--]--></span><!----><!----></button></a><a class="video-link" href="https://www.youtube.com/watch?v=fUB1s3RaD7c&amp;utm_source=changelog" target="_blank" rel="noopener" data-v-0266dac0 data-v-55b70507-s><span class="text-button -primary" data-v-0266dac0 data-v-55b70507-s data-v-dee04dfb><span data-v-dee04dfb><!--[-->Full walkthrough (7:00)<!--]--></span><!----></span></a><!--]--><!--[--><!--]--></div></div><div class="version" data-v-0266dac0 data-v-55b70507><div class="date" data-v-55b70507>21 July, 2026</div><div class="content" data-v-55b70507><div class="topbar" data-v-55b70507><div class="number" data-v-55b70507>4.8.10</div><!----></div><!--[--><!--]--><!--[--><ul class="changes" data-v-0266dac0 data-v-55b70507-s><li class="change" data-v-0266dac0 data-v-55b70507-s><strong data-v-0266dac0 data-v-55b70507-s>Important security update recommended for all users</strong></li><li class="change" data-v-0266dac0 data-v-55b70507-s>Improved capture history performance</li><li class="change" data-v-0266dac0 data-v-55b70507-s> Fixed bug with the &quot;Ask for Name after every capture&quot; dialog not receiving focus on macOS Tahoe </li></ul><!--]--></div></div></section>
"""#

@Test func cleanShotReadsThePageAsItWasRebuiltForFivePointOh() throws {
    // CleanShot published 5.0 on 2026-09-01 and rebuilt the changelog page with it:
    // the date moved ahead of the version number, two wrappers appeared between the
    // block and the number, and the release's introduction and video links landed
    // between the number and the list of changes. The pattern that had been reading
    // this page matched nothing afterwards — `duo verify` said `noEntriesExtracted`
    // — so the app went on showing the 4.8.10 notes it had cached under the 5.0 key,
    // with no sign anything was wrong.
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "pl.maketheweb.cleanshotx"),
        "CleanShot X changelog recipe must exist")
    let log = try #require(ChangelogExtractor.extract(from: cleanShotChangelogFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["5.0", "4.8.10"])
    #expect(log.entries.map(\.date) == ["1 September, 2026", "21 July, 2026"])
    // The gap is crossed, not swallowed: 5.0 keeps its own list rather than the
    // next block's, and the bold spans inside the items are flattened to text.
    #expect(log.entries[0].items.first == "🎬 Introducing Studio Mode and a brand-new Video Editor")
    #expect(log.entries[1].items == [
        "Important security update recommended for all users",
        "Improved capture history performance",
        "Fixed bug with the \"Ask for Name after every capture\" dialog not receiving focus on macOS Tahoe",
    ])
}

@Test func aCleanShotBlockWithNoListDoesNotBorrowTheNextOnes() throws {
    // Why the number-to-list gap is tempered rather than a plain `.*?`. Lazy, it
    // leaves the block it started in the moment a block has no list of its own and
    // pairs that version with the following version's notes — a wrong answer that
    // looks exactly like a right one. Tempered, the block simply does not match and
    // the next one is read normally.
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "pl.maketheweb.cleanshotx"))
    let log = try #require(
        ChangelogExtractor.extract(from: cleanShotBlockWithoutAListFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["4.8.10"], "5.0 has no notes here — it must not take 4.8.10's")
    #expect(log.entries[0].items.first == "Important security update recommended for all users")
}
