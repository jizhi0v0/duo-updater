import Foundation
import Testing
@testable import DuoUpdaterCore

/// Kiln: the version comes from the product page's server-rendered download line.
struct KilnProbeRecipeTests {
    private static var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.superultra.kiln" }
    }

    /// The download line as superwhisper.com/kiln served it (2026-10-18), with
    /// React's text separators.
    private static let line =
        #"Press <strong>spacebar</strong> to download</p><p class="kiln-meta">v<!-- -->0.4.3<!-- --> · <!-- -->6.0 MB<!-- --> · Also for<!-- --> <span>"#

    @Test func readsTheDownloadLine() throws {
        let recipe = try #require(Self.recipe)
        #expect(VendorProbeRecipe.extractVersion(from: Self.line, pattern: recipe.versionPattern) == "0.4.3")
    }

    /// The next releases read; a prerelease the page might one day name does not.
    @Test func readsTheNextReleaseAndRefusesAPrerelease() throws {
        let recipe = try #require(Self.recipe)
        func read(_ version: String) -> String? {
            VendorProbeRecipe.extractVersion(
                from: Self.line.replacingOccurrences(of: "0.4.3", with: version),
                pattern: recipe.versionPattern)
        }
        #expect(read("0.4.10") == "0.4.10")
        #expect(read("1.0") == "1.0")
        #expect(read("2.0.0") == "2.0.0")
        #expect(read("0.5.0-beta.1") == nil)
    }

    @Test func installsTheLatestZip() throws {
        let install = try #require(Self.recipe?.install)
        #expect(install.kind == .zip)
        guard case .fixed(let url) = install.urlSource else {
            Issue.record("expected a fixed URL, got \(install.urlSource)"); return
        }
        #expect(url.absoluteString == "https://kiln-builds.superwhisper.com/latest/Kiln-mac.zip")
    }
}
