import Foundation
import Testing

@testable import DuoUpdaterCore

/// The release service's answer to the request Kitten Preview's own updater sends,
/// fetched 2026-10-12, verbatim.
private let kittenPreviewAssetBody = #"""
{"version":"0.1.0","url":"https://api.kittenapi.com/releases/preview/0.1.0/download?asset=kitten-macos-aarch64.dmg&source=updater"}
"""#

/// The one release block of `www.kittenapi.com/releases/preview`, fetched
/// 2026-10-12. The download-arrow `<svg>`s are elided and the Windows and Linux
/// boxes cut; everything else is verbatim, including Svelte's scope classes and
/// `<!--[-->` markers. The asset links stay because they sit between the header
/// and the notes, and must not become items.
private let kittenPreviewReleasesFixture = #"""
<article class="release svelte-1cuzsfv" id="kitten-0.1.0"><header class="svelte-1cuzsfv"><span class="ver svelte-1cuzsfv">0.1.0</span> <span>Oct 10, 2026</span></header> <div class="assets svelte-1cuzsfv"><!--[--><div class="box svelte-1cuzsfv"><div class="box-title svelte-1cuzsfv">macOS</div> <!--[--><a href="https://api.kittenapi.com/releases/preview/0.1.0/download?asset=kitten-macos-aarch64.dmg&amp;source=website" class="svelte-1cuzsfv"> Apple Silicon</a> <!--[-1--><!--]--><a href="https://api.kittenapi.com/releases/preview/0.1.0/download?asset=kitten-macos-x86_64.dmg&amp;source=website" class="svelte-1cuzsfv"> Intel Chip</a> <!--[-1--><!--]--><!--]--></div><!--]--></div> <div class="notes svelte-1cuzsfv"><!--[0--><p class="svelte-1cuzsfv">First cross-platform build: Linux, macOS and Windows on both x86_64 and aarch64.</p><!--]--> <!--[--><h2 class="svelte-1cuzsfv">Notices</h2> <ul class="svelte-1cuzsfv"><!--[--><li class="svelte-1cuzsfv">macOS builds are unsigned. On first launch, right-click the app and choose Open.</li><li class="svelte-1cuzsfv">The Windows installer is unsigned; SmartScreen may warn on first run.</li><li class="svelte-1cuzsfv">The Linux archive includes a .desktop entry under share/applications/.</li><li class="svelte-1cuzsfv">Linux builds are made on Ubuntu 22.04 and need glibc 2.35 or newer.</li><!--]--></ul><!--]--></div></article>
"""#

@Test func kittenPreviewReadsTheReleaseServiceVersion() throws {
    let recipe = try #require(
        VendorProbeRegistry.recipes.first { $0.bundleID == "dev.kitten.Kitten-Preview" })
    #expect(recipe.channel == .preview)
    // Detection only: the macOS builds are ad-hoc signed, so no install route exists.
    #expect(recipe.install == nil)
    #expect(VendorProbeRecipe.extractVersion(
        from: kittenPreviewAssetBody, pattern: recipe.versionPattern) == "0.1.0")
    // The error envelope the service sends for a track that does not exist.
    #expect(VendorProbeRecipe.extractVersion(
        from: #"{"error":"release channel \"stable\" is not available"}"#,
        pattern: recipe.versionPattern) == nil)
}

@Test func kittenPreviewChangelogKeepsNotesAndSkipsAssetLinks() throws {
    let recipe = try #require(
        ChangelogRecipeRegistry.recipe(forBundleID: "dev.kitten.Kitten-Preview", channel: .preview))
    let log = try #require(ChangelogExtractor.extract(from: kittenPreviewReleasesFixture, using: recipe))

    #expect(log.entries.map(\.version) == ["0.1.0"])
    #expect(log.entries.map(\.date) == ["Oct 10, 2026"])
    #expect(log.entries[0].items == [
        "First cross-platform build: Linux, macOS and Windows on both x86_64 and aarch64.",
        "macOS builds are unsigned. On first launch, right-click the app and choose Open.",
        "The Windows installer is unsigned; SmartScreen may warn on first run.",
        "The Linux archive includes a .desktop entry under share/applications/.",
        "Linux builds are made on Ubuntu 22.04 and need glibc 2.35 or newer.",
    ])
}
