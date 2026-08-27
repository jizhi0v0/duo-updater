import Testing
import Foundation
@testable import DuoUpdaterCore

/// Two consecutive entries from `blogs.opera.com/desktop/changelog-for-134/`,
/// captured verbatim 2026-08-16 and trimmed to the first few `<li>`s of each.
/// Kept as two so "newest first" is actually exercised, and kept with the
/// `&#8211;` en dash and the trailing "blog post" link inside the `<strong>` —
/// both are the shape the pattern has to survive.
private let operaChangelogFixture = #"""
            <div class="content">
                <h4><strong> 134.0.5954.56 &#8211; 2026-08-12 <a href="https://blogs.opera.com/desktop/2026/08/opera-134-0-5954-56-stable-update/">blog post</a></strong></h4>
<ul>
<li>CHR-9416 Updating Chromium on desktop-stable-* branches  </li>
<li>DNA-125460 Crash at opera::SnapViewWidgetDelegate::~SnapViewWidgetDelegate  </li>
<li>RNA-3745 Remind me tomorrow option doesn&#8217;t work  </li>
</ul>
<h4><strong> 134.0.5954.46 &#8211; 2026-08-06 <a href="https://blogs.opera.com/desktop/2026/08/opera-134-0-5954-46-stable-update/">blog post</a></strong></h4>
<ul>
<li>CHR-10415 Update Chromium on desktop-stable-150-5954 to 150.0.7871.212  </li>
<li>RNA-4229 Crash when using split screen in vertical tabs  </li>
</ul>
            </div>
"""#

@Suite struct OperaChangelogRecipeTests {
    private func recipe() throws -> ChangelogRecipe {
        try #require(ChangelogRecipeRegistry.recipes
            .first { $0.bundleID == "com.operasoftware.Opera" })
    }

    @Test func readsEveryEntryNewestFirst() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: operaChangelogFixture, using: try recipe()))
        #expect(log.entries.count == 2)
        #expect(log.entries.first?.version == "134.0.5954.56")
        #expect(log.entries.first?.date == "2026-08-12")
        #expect(log.entries.first?.items.count == 3)
        #expect(log.entries.first?.items.first
            == "CHR-9416 Updating Chromium on desktop-stable-* branches")
        // Entities inside items are decoded, not left as `&#8217;`.
        #expect(log.entries.first?.items.contains { $0.contains("doesn’t work") } == true)
    }

    /// The "blog post" link is inside the `<strong>`, i.e. INSIDE the header the
    /// entry pattern matches. It must not become the first change line.
    @Test func theBlogPostLinkIsNotAChangeLine() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: operaChangelogFixture, using: try recipe()))
        #expect(!log.entries.flatMap(\.items).contains { $0.contains("blog post") })
    }

    /// An entry's items must not bleed into the next entry's list — the second
    /// `<h4>` is what has to stop it.
    @Test func entriesDoNotSwallowTheNextRelease() throws {
        let log = try #require(
            ChangelogExtractor.extract(from: operaChangelogFixture, using: try recipe()))
        #expect(log.entries.first?.items.contains { $0.contains("CHR-10415") } == false)
        #expect(log.entries.last?.version == "134.0.5954.46")
        #expect(log.entries.last?.items.count == 2)
    }

    /// Opera publishes ONE page per major, so the URL is templated on `{major}`,
    /// not `{version}` — a page pinned to today's major stops covering the
    /// installed build within a few weeks.
    @Test func theSourceIsTemplatedOnTheMajor() throws {
        let recipe = try self.recipe()
        #expect(recipe.sourceTemplate?.contains("{major}") == true)
        #expect(recipe.resolvedSource(forVersion: "134.0.5954.56").absoluteString
            == "https://blogs.opera.com/desktop/changelog-for-134/")
        #expect(recipe.resolvedSource(forVersion: "135.0.6000.1").absoluteString
            == "https://blogs.opera.com/desktop/changelog-for-135/")
        // No version to work from (the fallback path) must still be a real page.
        #expect(recipe.resolvedSource(forVersion: nil) == recipe.source)
    }
}
