import Testing
import Foundation
@testable import DuoUpdaterCore

/// The EasyFind slice of DEVONtechnologies' shared freeware page, captured
/// verbatim 2026-08-16, with a neighbouring app's block kept in front of it.
/// That neighbour is the point: the page lists several unrelated apps, each with
/// its own version, so anything anchored on "Version X" text rather than on
/// EasyFind's own download path reads the wrong number.
private let devonFreewareFixture = #"""
<div class="fragment"><a name="xmenu"></a>
<p class='download button'><a class="button" href='https://download.devontechnologies.com/download/freeware/xmenu/1.9.11/XMenu.app.zip'>Download</a></p><p class="versioninfo mac">Version 1.9.11. Requires OS X El Capitan or later.</p>
</div>
<div class="fragment"><a name="easyfind"></a>
<p>Of course EasyFind doesn&#8217;t just give you the files.</p>
<p class='download button'><a class="button" href='https://download.devontechnologies.com/download/freeware/easyfind/5.0.2/EasyFind.app.zip'>Download</a></p><p class="versioninfo mac">Version 5.0.2. Requires OS X El Capitan or later.</p>
</div>
"""#

@Suite struct EasyFindProbeRecipeTests {
    private func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes
            .first { $0.bundleID == "org.grunenberg.EasyFind" })
    }

    @Test func readsEasyFindsOwnVersionNotANeighboursOnTheSamePage() throws {
        let recipe = try self.recipe()
        #expect(VendorProbeRecipe.extractVersion(
            from: devonFreewareFixture, pattern: recipe.versionPattern) == "5.0.2")
        // XMenu's 1.9.11 sits EARLIER in the document, so a loose "Version X"
        // pattern would win with it — that is the failure this anchor prevents.
        #expect(devonFreewareFixture.contains("Version 1.9.11"))
    }

    @Test func installURLIsReadFromThePageNotTemplated() throws {
        let spec = try #require(try recipe().install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: devonFreewareFixture, pattern: pattern)
            == "https://download.devontechnologies.com/download/freeware/easyfind/5.0.2/EasyFind.app.zip")
        #expect(spec.kind == .zip)
    }
}
