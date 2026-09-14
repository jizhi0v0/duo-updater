import Testing
import DuoUpdaterCore

@testable import DuoKit

/// `www.raycast.com/changelog/macos` as served 2026-09-14 — by then the v2 page,
/// the same list `/changelog` serves — trimmed to its newest entry and its 0.71
/// beta entry, one heading and one bullet each. Markup verbatim otherwise.
private let raycastV2PageFixture = #"""
<article><span id="2.3"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill Pill-module__gZwUCW__button" style="background-color:var(--color-red-transparent);color:var(--color-red)" href="/changelog/macos/2-3">v<!-- -->2.3</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">September 11, 2026</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><h2>✨ New</h2>
<ul>
<li><strong>AI</strong>: Added support for rendering Mermaid diagrams</li>
</ul></div></article><article><span id="0.71"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill Pill-module__gZwUCW__button" style="background-color:var(--color-red-transparent);color:var(--color-red)" href="/changelog/macos/0-71">v<!-- -->0.71</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">August 19, 2026</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><h2>✨ New</h2>
<ul>
<li><strong>AI</strong>: Send Focused Window to AI command includes richer app and window context</li>
</ul></div></article>
"""#

/// `www.raycast.com/changelog/macos-v1` as served 2026-09-14, trimmed to its
/// newest and oldest entries, one heading and one bullet each.
private let raycastV1ArchiveFixture = #"""
<article><span id="1.104.0"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill Pill-module__gZwUCW__button" style="background-color:var(--color-red-transparent);color:var(--color-red)" href="/changelog/macos-v1/1-104-0">v<!-- -->1.104.0</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">December 16, 2025</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><h2>🎁 Raycast Wrapped 2025</h2>
<ul>
<li><strong>File Search</strong>: Update File Search Beta to be on parity with Windows File Search.</li>
</ul></div></article><article><span id="1.95.0"></span><div class="ChangelogEntry-module__p4g-ca__changelogMeta"><a class="Pill-module__gZwUCW__pill Pill-module__gZwUCW__button" style="background-color:var(--color-red-transparent);color:var(--color-red)" href="/changelog/macos-v1/1-95-0">v<!-- -->1.95.0</a><span class="ChangelogEntry-module__p4g-ca__changelogDate">April 9, 2025</span></div><div class="markdown ChangelogEntry-module__p4g-ca__changelogBody"><h2>✨ Improvements and bug fixes</h2>
<ul>
<li><strong>Reasoning Effort:</strong> You can now set the reasoning level for OpenAI’s o3-mini and Claude 3.7 Sonnet (Reasoning).</li>
</ul></div></article>
"""#

@Suite struct ChangelogVersionWindowTests {

    private func raycastArchive() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes.first {
            $0.bundleID == "com.raycast.macos" && $0.declaresVersionWindow
        })
    }

    private func entryVersions(_ page: String, _ recipe: ChangelogRecipe) throws -> [String] {
        try #require(ChangelogExtractor.extract(from: page, using: recipe)).entries.map(\.version)
    }

    /// The failure as it shipped: Raycast moved its v1 archive to `/changelog/macos-v1`
    /// and turned `/changelog/macos` into a second copy of the v2 page. The `[1, 2)`
    /// recipe kept parsing it cleanly and handed 1.104.x installs the 2.x notes,
    /// and the sweep recorded 2.3 as the archive's healthy newest version.
    @Test func theArchiveRecipeReadingTheV2PageIsFlagged() throws {
        let recipe = try raycastArchive()
        let versions = try entryVersions(raycastV2PageFixture, recipe)
        #expect(versions == ["2.3", "0.71"])
        let complaint = try #require(Verify.changelogWindowComplaint(recipe, entryVersions: versions))
        // Both sides of the window: a lower bound that only swallowed `< 2` would
        // pass the 0.71 beta entry, whose notes are not v1's either.
        #expect(complaint.contains("2 of 2 entries"))
        #expect(complaint.contains("[1, 2)"))
        #expect(complaint.contains("2.3") && complaint.contains("0.71"))
    }

    @Test func theArchiveRecipeReadingTheV1PageIsClean() throws {
        let recipe = try raycastArchive()
        let versions = try entryVersions(raycastV1ArchiveFixture, recipe)
        #expect(versions == ["1.104.0", "1.95.0"])
        #expect(Verify.changelogWindowComplaint(recipe, entryVersions: versions) == nil)
    }

    /// The recipe must point at the page the fixture above says is the archive.
    @Test func theArchiveRecipeReadsMacOSV1() throws {
        #expect(try raycastArchive().source.absoluteString
            == "https://www.raycast.com/changelog/macos-v1")
    }

    // MARK: Derived from the registry

    /// Every windowed recipe is judged at both of its own bounds: the exclusive
    /// ceiling and anything under the floor are outside, the floor itself is in.
    @Test func everyWindowedRecipeIsJudgedAtItsOwnBounds() {
        let windowed = ChangelogRecipeRegistry.recipes.filter(\.declaresVersionWindow)
        #expect(!windowed.isEmpty)
        for recipe in windowed {
            if let floor = recipe.minimumAppVersion {
                #expect(Verify.changelogWindowComplaint(recipe, entryVersions: [floor]) == nil,
                        "\(recipe.recipeID): its floor \(floor) is inside")
                if floor != "0" {
                    #expect(Verify.changelogWindowComplaint(recipe, entryVersions: ["0"]) != nil,
                            "\(recipe.recipeID): 0 is under its floor \(floor)")
                }
            }
            if let ceiling = recipe.belowAppVersion {
                #expect(Verify.changelogWindowComplaint(recipe, entryVersions: [ceiling]) != nil,
                        "\(recipe.recipeID): its exclusive ceiling \(ceiling) is outside")
            }
        }
    }

    /// Scoped to windowed recipes: the other ~100 declare no train, so no entry of
    /// theirs can be on the wrong one.
    @Test func aRecipeWithoutAWindowNeverComplains() {
        for recipe in ChangelogRecipeRegistry.recipes where !recipe.declaresVersionWindow {
            #expect(Verify.changelogWindowComplaint(recipe, entryVersions: ["0", "999999.0"]) == nil,
                    "\(recipe.recipeID)")
        }
    }

    /// A headline captured into `version` has no place in a window, so it is not
    /// counted against one.
    @Test func headlineEntriesAreNotJudged() throws {
        let recipe = try raycastArchive()
        #expect(Verify.changelogWindowComplaint(
            recipe, entryVersions: ["Raycast Wrapped 2025", "1.104.0"]) == nil)
    }
}
