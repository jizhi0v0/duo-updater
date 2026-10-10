import Foundation
import Testing

@testable import DuoUpdaterCore

/// `obdev.at/products/littlesnitch/releasenotes6.html`, fetched 2026-10-10: the
/// 6.5 block and the 6.4.1 hot fix under it, then the end of the section. 6.5's two
/// lists are cut to two items each; every byte kept is verbatim.
///
/// The two blocks are the two shapes on the page: 6.5 opens with a paragraph
/// before its `<h4>` sections and lists, 6.4.1 is paragraphs only.
private let littleSnitchReleaseNotesFixture = #"""
<section class="changelogs">
<div class="changelog-entry" id="version-7303">
<div class="date"><span>September 8, 2026</span></div>
<div class="details">
<h3 id="first-releasenotes-headline">Little Snitch 6.5 <span class="buildnumber">(7303)</span></h3>
<div class="changes">
<div class="update-recommended">
<p><strong>IMPORTANT</strong>: Upgrade to this version <em>before</em> you upgrade to macOS 27 Golden Gate! Previous versions of Little Snitch are not compatible with macOS 27 Golden Gate and would break your internet connection after the macOS upgrade.</p>
</div>
<h4>Improvements</h4>
<ul>
<li>Compatibility with macOS 27 Golden Gate.</li>
<li>Added an experimental implementation of NAT64 (<a href="https://datatracker.ietf.org/doc/html/rfc6052">RFC 6052</a>).</li>
</ul>
<h4>Bug Fixes</h4>
<ul>
<li>Fixed an issue that prevented expired temporary rules from appearing under Suggestions &gt; Expired.</li>
<li>Various other bug fixes and improvements under the hood.</li>
</ul>
</div></div></div>
<div class="changelog-entry" id="version-7212">
<div class="date"><span>June 22, 2026</span></div>
<div class="details">
<h3>Little Snitch 6.4.1 <span class="buildnumber">(7212)</span></h3>
<div class="changes">
<h4>Hot Fix</h4>
<p>Fixes an issue where some older licenses were not accepted, causing Little Snitch to fall back to demo mode.</p>
<p>If you are not affected by this issue, you may skip this update.</p>
</div></div></div>
</section>
"""#

@Test func littleSnitchReadsItsStableReleaseNotes() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "at.obdev.littlesnitch", channel: .stable))
    let log = try #require(ChangelogExtractor.extract(from: littleSnitchReleaseNotesFixture, using: recipe))

    // The marketing version, as the stable probe's display version reads it — not
    // the build in the span.
    #expect(log.entries.map(\.version) == ["6.5", "6.4.1"])
    try #require(log.entries.count == 2)
    #expect(log.entries.map(\.date) == ["September 8, 2026", "June 22, 2026"])
    // The paragraph ahead of the lists leads, then the items in document order.
    #expect(log.entries[0].items == [
        "IMPORTANT: Upgrade to this version before you upgrade to macOS 27 Golden Gate! Previous versions of Little Snitch are not compatible with macOS 27 Golden Gate and would break your internet connection after the macOS upgrade.",
        "Compatibility with macOS 27 Golden Gate.",
        "Added an experimental implementation of NAT64 (RFC 6052).",
        "Fixed an issue that prevented expired temporary rules from appearing under Suggestions > Expired.",
        "Various other bug fixes and improvements under the hood.",
    ])
    #expect(log.entries[0].content.contains(.heading("Bug Fixes")))
    // A release written as paragraphs only still has notes.
    #expect(log.entries[1].items == [
        "Fixes an issue where some older licenses were not accepted, causing Little Snitch to fall back to demo mode.",
        "If you are not affected by this issue, you may skip this update.",
    ])
}

@Test func aLittleSnitchNightlyCopyIsNotShownTheStablePage() {
    // The page lists final releases only, and the nightly probe links no page for
    // that reason; the lookup ladder's fallbacks would otherwise hand a nightly
    // copy the stable recipe.
    #expect(ChangelogRecipeRegistry.recipe(forBundleID: "at.obdev.littlesnitch", channel: .nightly) == nil)
}
