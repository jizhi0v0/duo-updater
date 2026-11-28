import Testing
@testable import DuoUpdaterCore

@Suite struct ONLYOFFICEChangelogRecipeTests {
    @Test func keepsMigrationNoticeAndEditorSectionsWithTheirRelease() throws {
        let recipe = try #require(asc_onlyoffice_ONLYOFFICE.set.changelogs.first)
        let changelog = try #require(ChangelogExtractor.extract(from: Self.html, using: recipe))
        #expect(changelog.entries.map(\.version) == ["10.0.0", "9.4.0"])
        #expect(changelog.entries.map(\.date) == ["10/13/2026", "05/19/2026"])
        #expect(changelog.entries[0].content == [
            .note("Important: Version 10.0 is a fully rebuilt app, so some settings can’t be transferred from previous versions."),
            .heading("New features"),
            .heading("Document Editor"),
            .note("Added the horizontal line settings window"),
            .heading("Spreadsheet Editor"),
            .note("Added range highlighting in the formula bar"),
        ])
        #expect(changelog.entries[1].content == [
            .heading("Document Editor"),
            .note("Implemented the ability to add a horizontal line"),
        ])
    }

    // Trimmed from the English Help Center. Docusaurus adds an anchor link to
    // each heading and renders the migration note outside both release lists.
    private static let html = """
        <article>
        <h2 class="anchor anchorTargetStickyNavbar_Vzrq" id=version-10-0-0>Version 10.0.0<a href=#version-10-0-0 class=hash-link translate=no>​</a></h2>
        <p>Release date: 10/13/2026</p>
        <div class="theme-admonition theme-admonition-note"><div class=admonitionContent_BuS1><p>Important: Version 10.0 is a fully rebuilt app, so some settings can’t be transferred from previous versions.</div></div>
        <h3 class="anchor anchorTargetStickyNavbar_Vzrq" id=new-features>New features<a href=#new-features class=hash-link>​</a></h3>
        <h4 class="anchor anchorTargetStickyNavbar_Vzrq" id=document-editor>Document Editor<a href=#document-editor class=hash-link>​</a></h4>
        <ul><li class="">Added the horizontal line settings window</li></ul>
        <h4 class="anchor anchorTargetStickyNavbar_Vzrq" id=spreadsheet-editor>Spreadsheet Editor<a href=#spreadsheet-editor class=hash-link>​</a></h4>
        <ul><li class="">Added range highlighting in the formula bar</li></ul>
        <h2 class="anchor anchorTargetStickyNavbar_Vzrq" id=version-9-4-0>Version 9.4.0<a href=#version-9-4-0 class=hash-link translate=no>​</a></h2>
        <p>Release date: 05/19/2026</p>
        <h4 class="anchor anchorTargetStickyNavbar_Vzrq" id=document-editor-1>Document Editor<a href=#document-editor-1 class=hash-link>​</a></h4>
        <ul><li class="">Implemented the ability to add a horizontal line</li></ul>
        </article>
        <ul><li>Sidebar navigation</li></ul>
        """
}
