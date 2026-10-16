import Foundation
import Testing

@testable import DuoUpdaterCore

/// The download table of `dev.mysql.com/downloads/workbench/?os=33` (the macOS
/// tab), fetched 2026-10-16, verbatim: one dmg row and one zip row.
private let workbenchMacDownloadsFixture = #"""
<table border="0" cellpadding="2" cellspacing="0" class="table04">
                            <tr class="alt">
                        <td class="col1"><b>macOS (ARM, 64-bit), DMG Archive</b></td>
                    <td class="col3">26.7.0</td>
        <td class="col4">301.0M</td>
        <td class="col5">
                            <div class="button03"><a href="/downloads/file/?id=559071">Download</a></div>
                        </td>
    </tr>
    <tr class="alt">
        <td class="sub-text">(mysql-workbench-26.7.0-macos-arm64.dmg)</td>
        <td class="sub-text" style="text-align:right;" colspan="4">
            MD5: <code class="md5">bb0f5e5bcba12d4add0a35957ce47355</code> |
            <a class="signature" href="/downloads/gpg/?file=mysql-workbench-26.7.0-macos-arm64.dmg&p=8"
                target="_blank">Signature</a>            </td>
    </tr>
                                <tr >
                        <td class="col1"><b>macOS (ARM, 64-bit), ZIP Archive</b></td>
                    <td class="col3">26.7.0</td>
        <td class="col4">293.8M</td>
        <td class="col5">
                            <div class="button03"><a href="/downloads/file/?id=559072">Download</a></div>
                        </td>
    </tr>
    <tr >
        <td class="sub-text">(mysql-workbench-26.7.0-macos-arm64.zip)</td>
        <td class="sub-text" style="text-align:right;" colspan="4">
            MD5: <code class="md5">5b6fc29f8673f27d73e16933eecefbca</code> |
            <a class="signature" href="/downloads/gpg/?file=mysql-workbench-26.7.0-macos-arm64.zip&p=8"
                target="_blank">Signature</a>            </td>
    </tr>
            </table>
"""#

/// The page navigation of `news-8-0.html`, the 8.0 release-notes index, fetched
/// 2026-10-16, verbatim, with the `<link rel="next">` from its `<head>` (whose
/// `?ff=nopfpls` query the pattern must not take).
private let workbench80IndexFixture = #"""
<link rel="next" href="news-8-0-47.html?ff=nopfpls" title=" Changes in MySQL Workbench 8.0.47 (2026-04-23)" />
    <a href="preface.html"
        aria-label="Previous" title="Previous: Preface and Legal Notices"><span
        class="icon-chevron-left"></span></a>
<a href="index.html" aria-label="Start" title="Start"><span class="icon-book-open"></span></a>
    <a href="index.html" aria-label="Up" title="Up"><span class="icon-chevron-up"></span></a>
    <a href="news-8-0-47.html" aria-label="Next"
        title="Next: Changes in MySQL Workbench 8.0.47 (2026-04-23)"><span
        class="icon-chevron-right"></span></a>
"""#

/// The section of `news-8-0-47.html`, fetched 2026-10-16, verbatim up to the
/// page navigation that ends the entry.
private let workbench8047Fixture = #"""
<div class="section">
<div class="titlepage"><div><div><h3 class="title">
<a name="news-8-0-47"></a>Changes in MySQL Workbench 8.0.47 (2026-04-23)</h3></div></div></div>
<div class="simplesect">
<div class="titlepage"><div><div><h4 class="title">
<a name="workbench-8-0-47-feature"></a>Functionality Added or Changed</h4></div></div></div>
<div class="itemizedlist"><ul class="itemizedlist" type="disc">
<li class="listitem"><p>
        The bundled LIBPNG library has been updated to 1.6.56.
       (Bug #38965332)</p></li>
<li class="listitem"><p>
        The bundled OpenSSL library has been updated to 3.5.5.
       (Bug #38906653)</p></li>
<li class="listitem">
<p>
        MySQL HeatWave Migration Assistant now supports partial migrations, allowing users to
        choose what schemas and objects to migrate, including individual DB
        objects such as schemas, tables, views, routines, events, triggers,
        libraries, and user accounts.
      </p>
<p>
        For more information, see
        <a class="ulink" href="/doc/workbench/en/heatwave-migration-assistant.html" target="_top">MySQL HeatWave Migration Assistant</a>.
       (WL #17258)</p>
</li>
</ul></div>
</div>
</div><br />
        </div>

                <div id="docs-in-page-nav-container">
"""#

/// The section of `news-8-0-46.html`, fetched 2026-10-16, verbatim: a release
/// with no list, only a sentence.
private let workbench8046Fixture = #"""
<div class="section">
<div class="titlepage"><div><div><h3 class="title">
<a name="news-8-0-46"></a>Changes in MySQL Workbench 8.0.46 (2026-01-21)</h3></div></div></div>
<p>
        This release contains no functional changes.
      </p>
</div><br />
        </div>

                <div id="docs-in-page-nav-container">
"""#

@Test func mysqlWorkbenchReadsTheMacDmgRowOnly() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.oracle.mysqlworkbench" })
    #expect(VendorProbeRecipe.extractVersion(
        from: workbenchMacDownloadsFixture, pattern: recipe.versionPattern) == "26.7.0")
    // 8.0's files are `mysql-workbench-community-…`: the other app, never read here.
    #expect(VendorProbeRecipe.extractVersion(
        from: "(mysql-workbench-community-8.0.47-macos-arm64.dmg)",
        pattern: recipe.versionPattern) == nil)
    // A suffixed filename is not a GA version.
    #expect(VendorProbeRecipe.extractVersion(
        from: "(mysql-workbench-26.8.0-rc-macos-arm64.dmg)",
        pattern: recipe.versionPattern) == nil)
    let install = try #require(recipe.install)
    #expect(install.kind == .dmg)
    guard case .versionTemplate(let template) = install.urlSource else {
        Issue.record("expected a version template")
        return
    }
    #expect(template.replacingOccurrences(of: "{version}", with: "26.7.0")
        == "https://cdn.mysql.com/Downloads/MySQLGUITools/mysql-workbench-26.7.0-macos-arm64.dmg")
}

@Test func mysqlWorkbench80HasNotesButNoProbe() throws {
    // See the recipe comment: `8.0.47.CE` against `8.0.47` would read as an update.
    #expect(!VendorProbeRegistry.recipes.contains {
        $0.bundleID == "com.oracle.workbench.MySQLWorkbench" })
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.oracle.workbench.MySQLWorkbench"))
    let pattern = try #require(recipe.indexLinkPattern)
    #expect(ChangelogService.firstLink(
        in: workbench80IndexFixture, pattern: pattern, base: recipe.source)?.absoluteString
        == "https://dev.mysql.com/doc/relnotes/workbench/en/news-8-0-47.html")
}

@Test func mysqlWorkbench80NotesKeepSectionsAndParagraphs() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "com.oracle.workbench.MySQLWorkbench"))
    let log = try #require(ChangelogExtractor.extract(from: workbench8047Fixture, using: recipe))
    let entry = try #require(log.entries.first)
    #expect(log.entries.count == 1)
    #expect(entry.version == "8.0.47")
    #expect(entry.date == "2026-04-23")
    #expect(entry.items.count == 3)
    #expect(entry.items.first == "The bundled LIBPNG library has been updated to 1.6.56. (Bug #38965332)")
    let headings = entry.content.compactMap { block -> String? in
        if case .heading(let text) = block { return text }
        return nil
    }
    #expect(headings == ["Functionality Added or Changed"])

    let quiet = try #require(ChangelogExtractor.extract(from: workbench8046Fixture, using: recipe))
    #expect(quiet.entries.first?.items == ["This release contains no functional changes."])
}
