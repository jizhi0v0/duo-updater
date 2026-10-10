import Foundation
import Testing

@testable import DuoUpdaterCore

/// The first two releases of `www.mongodb.com/docs/compass/release-notes/`
/// (fetched 2026-10-10): the page from the 1.52.0 `<section><h2>` up to the
/// 1.50.0 `<h2>`, with a closing `</section>` appended. Trimmed for size: the
/// inline `<svg>` icons (permalink and external-link glyphs, no text) are cut;
/// every other byte is the page's.
private let compassReleaseNotesFixture = #"""
<section><h2 class="Text-module__2xN8W_text Text-module__2xN8W_heading3 colorScheme-module_uDd7va_light contains-headerlink heading_sectionMargin__Hk8j_" data-color-scheme="light" data-display="h3">MongoDB Compass<!-- --> 1.52.0<a class="headerlink permalink_heading__JA_UW" href="#mongodb-compass-1520" title="Permalink to this heading"><div class="permalink_headerBuffer__YJ3GH" id="mongodb-compass-1520"></div></a></h2><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p"><em>Released October 2, 2026</em></p><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">New Features</p><ul class="list_list__BM_Mz">
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Add a warning banner for trusted connections (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-10671" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-10671)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Improve the error message for bulk update actions (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-8866" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-8866)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Update the <code class="Text-module__2xN8W_text Text-module__2xN8W_inlineCode Text-module__2xN8W_large colorScheme-module_uDd7va_light literal_literal__uSQAf" data-color-scheme="light" data-display="code">electron-wix-msi</code> version (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-10984" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-10984)</span></a></p>
</div></li>
</ul><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Bug Fixes</p><ul class="list_list__BM_Mz">
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Return only <code class="Text-module__2xN8W_text Text-module__2xN8W_inlineCode Text-module__2xN8W_large colorScheme-module_uDd7va_light literal_literal__uSQAf" data-color-scheme="light" data-display="code">ANSWER</code> results from DNS lookups (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-11158" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-11158)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Update the Java export in the export-to-language feature (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-11156" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-11156)</span></a></p>
</div></li>
</ul><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p"><a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://github.com/mongodb-js/compass/compare/v1.51.0...v1.52.0" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">Full Changelog available on GitHub</span></a></p></section><section><h2 class="Text-module__2xN8W_text Text-module__2xN8W_heading3 colorScheme-module_uDd7va_light contains-headerlink heading_sectionMargin__Hk8j_" data-color-scheme="light" data-display="h3">MongoDB Compass<!-- --> 1.51.0<a class="headerlink permalink_heading__JA_UW" href="#mongodb-compass-1510" title="Permalink to this heading"><div class="permalink_headerBuffer__YJ3GH" id="mongodb-compass-1510"></div></a></h2><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p"><em>Released September 25, 2026</em></p><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">New Features</p><ul class="list_list__BM_Mz">
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Add the Atlas user ID to telemetry when a user is logged in (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-10933" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-10933)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Use shell syntax when creating an index (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-9352" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-9352)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Improve the document layout to make copying and pasting a selection easier (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-10908" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-10908)</span></a></p>
</div></li>
</ul><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Bug Fixes</p><ul class="list_list__BM_Mz">
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Prevent action buttons from rendering when the approval ID is missing (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-10973" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-10973)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Parse AWS IAM credential configuration files when you do not use environment variables (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-11097" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-11097)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Use shell syntax when parsing validation rules (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-4989" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-4989)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Improve tool retrying behavior in the assistant</p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Display collection and index names that contain spaces correctly (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-11108" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-11108)</span></a></p>
</div></li>
<li class="list-item_listItem__58gGN"><div class="list-item_listItemContent__1wkOE">
<p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p">Display a chip for failed connection information (<a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://jira.mongodb.org/browse/COMPASS-11077" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">COMPASS-11077)</span></a></p>
</div></li>
</ul><p class="Text-module__2xN8W_text Text-module__2xN8W_body Text-module__2xN8W_large colorScheme-module_uDd7va_light paragraph_paragraph__fpJ3R" data-color-scheme="light" data-display="p"><a data-color-scheme="light" data-viaid="via-link" class="Link-module_IFszra_link Link-module_IFszra_inline colorScheme-module_uDd7va_light link_viaLink__QWBMd" data-rac="" href="https://github.com/mongodb-js/compass/compare/v1.50.0...v1.51.0" target="_blank" rel="noopener noreferrer" tabindex="0" data-react-aria-pressable="true"><span class="Link-module_IFszra_text">Full Changelog available on GitHub</span></a></p></section><section></section>
"""#

@Suite struct CompassChangelogRecipeTests {

    private func parsed() throws -> Changelog {
        let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "com.mongodb.compass"))
        return try #require(ChangelogService.parse(recipe, body: compassReleaseNotesFixture))
    }

    @Test func readsEachReleaseSection() throws {
        let entries = try parsed().entries
        #expect(entries.map(\.version) == ["1.52.0", "1.51.0"])
        let newest = try #require(entries.first)
        #expect(newest.date == "October 2, 2026")
        #expect(newest.items.count == 5)
        #expect(newest.items.first == "Add a warning banner for trusted connections (COMPASS-10671)")
        #expect(entries[1].items.count == 9)
    }

    /// The list stops at the next release's heading: 1.52.0's last item is its
    /// own, not 1.51.0's first.
    @Test func anEntryDoesNotRunIntoTheNext() throws {
        let entries = try parsed().entries
        #expect(!entries[0].items.contains("Add the Atlas user ID to telemetry when a user is logged in (COMPASS-10933)"))
        #expect(entries[1].items.first == "Add the Atlas user ID to telemetry when a user is logged in (COMPASS-10933)")
    }
}
