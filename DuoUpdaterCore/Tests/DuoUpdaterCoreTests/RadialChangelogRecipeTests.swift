import Foundation
import Testing

@testable import DuoUpdaterCore

/// Radial's appcast carries no notes, so the recipe reads the vendor's own
/// changelog page. This fixture is the page's first release, trimmed to two
/// sections and three bullets; the page's sidebar (which also lists versions in
/// `<a data-version=…>` and `<li>`) is deliberately kept out of the fixture's
/// article so a regression that starts reading the sidebar shows up as extra
/// entries.
private let radialChangelogFixture = #"""
<main class="max-w-6xl mx-auto px-6 sm:px-10 pt-32 sm:pt-40 pb-32"><div class="grid lg:grid-cols-[200px_1fr] gap-16"><nav class="hidden lg:block"><ul><li class="border-b"><a href="#v5-3-0" data-version="5.3.0"><span>5.3.0</span></a></li></ul></nav><div class="space-y-28 min-w-0"><article id="v5-3-0" class="scroll-mt-28"><p class="font-mono text-xs uppercase tracking-widest text-neutral-500 dark:text-neutral-400 mb-2">October 30, 2026</p><h2 class="text-6xl sm:text-7xl font-extrabold tracking-tighter leading-none text-foreground">5.3.0</h2><p class="mt-5 text-2xl sm:text-3xl font-semibold tracking-tight leading-snug text-foreground max-w-2xl">A smarter AI Pro, more room in every menu, and a fresh new look.</p><div class="mt-10 space-y-10"><section class="grid gap-3 sm:grid-cols-[120px_1fr] sm:gap-6"><p class="self-start sm:sticky sm:top-28 flex items-center gap-2 font-mono text-[11px] font-semibold uppercase tracking-widest text-neutral-700 dark:text-neutral-300 sm:pt-4"><span class="h-2 w-2 rounded-full bg-emerald-500"></span>New</p><ul class="border-t border-neutral-400/70 dark:border-neutral-600"><li class="py-4 border-b text-[15px] leading-relaxed text-neutral-500"><span class="font-semibold text-foreground">Ask Radial<!-- -->.</span> <!-- -->A new command bar, opened with ⌥Space from any app, that carries out what you describe in plain words.</li><li class="py-4 border-b text-[15px] leading-relaxed text-neutral-500"><span class="font-semibold text-foreground">Made for You<!-- -->.</span> <!-- -->Radial can now learn how you use your Mac over a few days and suggest shortcuts.</li></ul></section><section class="grid gap-3 sm:grid-cols-[120px_1fr] sm:gap-6"><p class="self-start sm:sticky sm:top-28 flex items-center gap-2 font-mono text-[11px] font-semibold uppercase tracking-widest text-neutral-700 dark:text-neutral-300 sm:pt-4"><span class="h-2 w-2 rounded-full bg-sky-500"></span>Improved</p><ul class="border-t border-neutral-400/70 dark:border-neutral-600"><li class="py-4 border-b text-[15px] leading-relaxed text-neutral-500">Faster menu rendering on large displays.</li></ul></section></div></article></div></div></main>
"""#

@Suite struct RadialChangelogRecipeTests {

    private func changelog() throws -> Changelog {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "dk.FirstForm.Radial"))
        return try #require(
            ChangelogExtractor.extract(from: radialChangelogFixture, using: recipe))
    }

    @Test func readsTheVendorChangelogPage() throws {
        let recipe = try #require(
            ChangelogRecipeRegistry.recipe(forBundleID: "dk.FirstForm.Radial"))
        #expect(recipe.source.absoluteString == "https://radial.appverge.net/changelog")
    }

    /// One `<article>` = one entry, with the date printed verbatim.
    @Test func articleBecomesAnEntry() throws {
        let entries = try changelog().entries
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.version == "5.3.0")
        #expect(entry.date == "October 30, 2026")
        #expect(entry.items.count == 3)
    }

    /// The sidebar's `5.3.0` link is not a second entry.
    @Test func theSidebarIsNotAnEntry() throws {
        #expect(try changelog().entries.allSatisfy { $0.version == "5.3.0" })
    }

    /// Inline markup inside a bullet is stripped: the reader gets the sentence,
    /// not `<span class="font-semibold …">`.
    @Test func inlineMarkupIsStripped() throws {
        let items = try changelog().entries.flatMap(\.items)
        #expect(items.contains { $0.hasPrefix("Ask Radial. A new command bar") })
        #expect(!items.contains { $0.contains("<span") || $0.contains("<!--") })
    }
}
