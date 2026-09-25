import Foundation
import Testing
@testable import DuoUpdaterCore

/// Two slices of the real `https://www.blender.org/download/`, captured
/// 2026-09-25, each verbatim: the header's macOS download button, and the macOS
/// entry of the platform menu further down (which runs the
/// `plausible-event-build` attribute straight into `href`).
private let blenderDownloadFixture = #"""
<div id="macos" class="dl-header-cta dl-os-macos">
              <a
                href="https://www.blender.org/download/release/Blender5.2/blender-5.2.2-macos-arm64.dmg/"
                class="btn btn-accent dl-header-cta-button plausible-event-name=Downloads+Blender plausible-event-os=macOS plausible-event-build=macOS+Apple+Silicon"
                title="Download Blender for macOS Apple Silicon">
                <i class="i-download"></i>
                Download Blender
              </a>
              <ul class="dl-build-details mb-0">
                <li class="os macos js-toggle-menu" data-toggle-menu="menu-info-macos"><i class="i-macos"></i><strong> macOS</strong><li class="js-toggle-menu" data-toggle-menu="menu-info-macos"><strong class="text-decoration-underline">Apple Silicon</strong></li></li><li>5.2.2 LTS</li></ul>
              <ul class="dl-build-details mt-1 mb-0"><li title="Tiny isn't?"><small>330 MB</small></li><li title="Release date"><small>September 15, 2026</small></li></ul>
<li class="os macos"><a class="plausible-event-name=Downloads+Blender plausible-event-os=macOS plausible-event-build=macOS+Apple+Silicon"href="https://www.blender.org/download/release/Blender5.2/blender-5.2.2-macos-arm64.dmg/"title="Download Blender for macOS Apple Silicon"><span class="name">macOS</span><span class="build">Apple Silicon</span><span class="size">330 MB</span></a></li>
"""#

struct BlenderProbeRecipeTests {
    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.blenderfoundation.blender" }
    }

    @Test func readsTheMacOSDownloadVersion() throws {
        let recipe = try #require(recipe)
        #expect(recipe.channel == .stable)
        #expect(VendorProbeRecipe.extractVersion(
            from: blenderDownloadFixture, pattern: recipe.versionPattern) == "5.2.2")
    }

    /// Only the arm64 dmg counts: a page that linked some other Mac build (the
    /// 4.5 LTS line still ships `-macos-x64.dmg`) yields nothing, not its number.
    @Test func ignoresOtherMacBuilds() throws {
        let recipe = try #require(recipe)
        let windowsOnly = blenderDownloadFixture.replacingOccurrences(
            of: "-macos-arm64.dmg", with: "-macos-x64.dmg")
        #expect(VendorProbeRecipe.extractVersion(
            from: windowsOnly, pattern: recipe.versionPattern) == nil)
    }

    @Test func rebuildsTheDmgURLOnTheDownloadHost() throws {
        let recipe = try #require(recipe)
        let spec = try #require(recipe.install)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        let parts = fields.map { VendorProbeRecipe.extractVersion(from: blenderDownloadFixture, pattern: $0) }
        #expect(parts == ["5.2", "5.2.2"])
        var url = template
        for (index, part) in parts.enumerated() {
            url = url.replacingOccurrences(of: "{\(index)}", with: part ?? "")
        }
        #expect(url == "https://download.blender.org/release/Blender5.2/blender-5.2.2-macos-arm64.dmg")
        #expect(spec.kind == .dmg)
    }

    @Test func runsOnlyOnAppleSilicon() throws {
        let recipe = try #require(recipe)
        #expect(recipe.hostRequirement?.architectures == [.arm64])
    }
}
