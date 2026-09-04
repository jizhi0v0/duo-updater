import Foundation
import Testing

@testable import DuoUpdaterCore

/// Two verbatim windows of `pdfexpert.com/pem3/changelog`, fetched 2026-09-04.
/// The page's own `</body>` is moved up to close each window — every other byte,
/// including the ragged indentation and the trailing spaces before `<br />`, is
/// the vendor's.
///
/// The newest five releases. Covers the shapes the top of the page has: a heading
/// with a trailing space inside `<strong>` (3.13.2) and one without (3.13.1), a
/// one-paragraph entry, an entry whose notes are `<br />`-separated lines (3.13),
/// and a `<br /><br />` pair separating two paragraphs (3.11.4).
private let pdfExpertChangelogHeadFixture = #"""
<body>
    
    <p>
        <strong>Version 3.13.2 </strong>
    </p>

    A fresh update for a fresher experience! We’ve ironed out a few technical wrinkles to keep your workflow uninterrupted. Let us know how we’re doing at rdsupport@readdle.com.
    <br />
    <p>
        <strong>Version 3.13.1</strong>
    </p>

    A fresh update for a fresher experience! We’ve ironed out a few technical wrinkles to keep your workflow uninterrupted. Let us know how we’re doing at rdsupport@readdle.com.
    <br />
    <p>
        <strong>Version 3.13</strong>
    </p>

    PDF Expert for Business is now easier to access and use.<br />Explore the new “For Business” menu to learn more about PDF Expert Business Manager, subscribe, or book a call with our sales team.<br />PDF Expert Premium is activated automatically with your business license, no personal purchase needed.<br />Plus, each license works on up to three devices, so you can stay productive across your Mac, iPhone, and iPad. Update PDF Expert today and let us know what you think!
    <br />
    <p>
        <strong>Version 3.12</strong>
    </p>

    Introducing the New Home Tab in PDF Expert!<br />Now you can quickly access your Recent Files, Favorites, and Essential Tools.<br />Customize your Home Tab and reorder sections to suit your unique workflows.<br />Give it a try and share your feedback with us at rdsupport@readdle.com
    <br />
    <p>
        <strong>Version 3.11.4</strong>
    </p>

    Hi, folks!<br />This time bugs were squished, performance was improved, work was done, and the result was good. Please enjoy PDF Expert!<br /><br />Questions, issues or bugs? Contact rdsupport@readdle.com, as ever, and we’ll be happy to help.
    <br />
</body>
"""#

/// Five releases from the bottom of the same page, where the vendor wrote notes
/// as dash-prefixed bullets — the shape the item pattern's `-\s+` prefix exists
/// for. 3.0.27 mixes bulleted and unbulleted lines in one entry, and 3.0.24 pads
/// its paragraphs with `<br /><br />`.
private let pdfExpertChangelogTailFixture = #"""
    <p>
        <strong>Version 3.0.28</strong>
    </p>

    - Big Sur fixes 
<br />- Stability and performance improvements
    <br />
    <p>
        <strong>Version 3.0.27</strong>
    </p>

    - Improvements in move and resize of annotations 
<br />Fixes: 
<br />- Notes tool: Notes text in Annotation Summary in Dark mode 
<br />- Cursor in form fields in Dark mode
    <br />
    <p>
        <strong>Version 3.0.26</strong>
    </p>

    - Stability and performance improvements 
<br />- Small fixes
    <br />
    <p>
        <strong>Version 3.0.25</strong>
    </p>

    Greetings from Ukraine!
<br />In this update:
<br />Just some fresh paint and tune-ups. No bigs.
<br />We’ve tinkered with the internal workings and polished some rough edges.
<br />Enjoy your PDF Expert!
<br />We’re always here for you at rdsupport@readdle.com
    <br />
    <p>
        <strong>Version 3.0.24</strong>
    </p>

    Hi, folks! 
<br />
<br />With today’s update PDF Expert is ready to go globally as the go-to PDF editor for your iPhone, iPad and Mac. 
<br />PDF Expert introduces a single Premium subscription, so when you create an account you get PDF editing experience across all your Apple devices. Even better together! 
<br />
<br />We hope you enjoy this release. 
<br />
<br />As always, you can reach out to us at rdsupport@readdle.com 
<br />Keep the feedback coming!
    <br />
</body>
"""#

/// PDF Expert's appcast links `pem3/changelog.html`, which holds ONLY the newest
/// release; the full history is on the `sparkle:fullReleaseNotesLink` page, an
/// element the appcast parser does not read. So without this recipe the pane
/// shows one paragraph and no history at all.
@Test func pdfExpertReadsEveryReleaseOnTheVendorsFullNotesPage() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.readdle.pdfexpert-mac"),
        "PDF Expert changelog recipe must exist")
    let log = try #require(
        ChangelogExtractor.extract(from: pdfExpertChangelogHeadFixture, using: recipe))

    // Both heading spellings parse, and neither leaks its whitespace into the
    // version string the entry is keyed by.
    #expect(log.entries.map(\.version) == ["3.13.2", "3.13.1", "3.13", "3.12", "3.11.4"])
    // The page carries no dates anywhere — there is no `date` group to capture,
    // and the entries must not invent one.
    #expect(log.entries.allSatisfy { $0.date == nil })

    #expect(log.entries[0].items == [
        "A fresh update for a fresher experience! We\u{2019}ve ironed out a few technical "
            + "wrinkles to keep your workflow uninterrupted. Let us know how we\u{2019}re "
            + "doing at rdsupport@readdle.com.",
    ])
    // `<br />`-separated lines become one item each — the split is the markup's.
    #expect(log.entries[2].items.count == 4)
    #expect(log.entries[2].items[0] == "PDF Expert for Business is now easier to access and use.")
    #expect(log.entries[2].items[3].hasPrefix("Plus, each license works on up to three devices"))
    // The `<br /><br />` between 3.11.4's two paragraphs is an empty run, and an
    // empty run must not become an empty bullet.
    #expect(log.entries[4].items == [
        "Hi, folks!",
        "This time bugs were squished, performance was improved, work was done, and the "
            + "result was good. Please enjoy PDF Expert!",
        "Questions, issues or bugs? Contact rdsupport@readdle.com, as ever, and we\u{2019}ll "
            + "be happy to help.",
    ])
}

/// The dash the older entries prefix their bullets with is markup, not text: it
/// is stripped, and stripping it does not eat an unbulleted line beside it.
@Test func pdfExpertStripsTheVendorsBulletDashWithoutEatingPlainLines() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.readdle.pdfexpert-mac"))
    let log = try #require(
        ChangelogExtractor.extract(from: pdfExpertChangelogTailFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["3.0.28", "3.0.27", "3.0.26", "3.0.25", "3.0.24"])
    #expect(log.entries[0].items == ["Big Sur fixes", "Stability and performance improvements"])
    // Mixed: three dashed lines and one plain "Fixes:" label between them.
    #expect(log.entries[1].items == [
        "Improvements in move and resize of annotations",
        "Fixes:",
        "Notes tool: Notes text in Annotation Summary in Dark mode",
        "Cursor in form fields in Dark mode",
    ])
    // The last entry on the page is closed by `</body>` and nothing else — it is
    // the only entry whose body has no following heading to stop at.
    #expect(log.entries[4].items.count == 6)
    #expect(log.entries[4].items.first == "Hi, folks!")
    #expect(log.entries[4].items.last == "Keep the feedback coming!")
}

/// Why the heading is matched as `<p[^>]*>` rather than the bare `<p>` the page
/// happens to use today. This recipe cannot fail the way most do. If the
/// terminator stops matching, the first block runs to `</body>` and the result is
/// ONE entry — correctly versioned, carrying the whole page as its notes — and
/// `duo verify` records only the newest version, so that failure sweeps green.
/// One added class attribute would have been enough.
@Test func pdfExpertSurvivesAnAttributeAppearingOnTheVendorsParagraphTag() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.readdle.pdfexpert-mac"))
    let restyled = pdfExpertChangelogHeadFixture
        .replacingOccurrences(of: "<p>", with: #"<p class="release">"#)
    let log = try #require(ChangelogExtractor.extract(from: restyled, using: recipe))

    #expect(log.entries.map(\.version) == ["3.13.2", "3.13.1", "3.13", "3.12", "3.11.4"])
    // The shape the tolerance prevents, stated so a reverted pattern fails on
    // the symptom and not only on the count.
    #expect(log.entries[0].items.count == 1,
            "one entry swallowing the whole page is what a lost terminator looks like")
}
