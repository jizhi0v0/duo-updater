import Testing
@testable import DuoUpdaterCore

struct BlockBlockProbeTests {
    private static let archive = "https://github.com/objective-see/BlockBlock/releases/download/v2.5.2/BlockBlock_2.5.2.zip"
    private static let digest = "7E5A332A4DA6A22E8B494418C3CAC241D24B43176C8BFC4BB2EF8BDC640BD4C7"

    // Trimmed from the actual vendor download panel.
    private static let page = #"""
    <div class="product-hero">
      <a href="javascript:void(0)" onclick="window.location.href='\#(archive)'; showPopup();" class="btn-download">
        Download
      </a>
      <span class="product-meta">
        v2.5.2 · macOS 10.15+
        · <span class="sha-wrapper" id="sha-wrapper">
          <span class="sha-popover">
            <span class="sha-popover-label">Zip SHA-256</span>
            <code class="sha-popover-hash">\#(digest)</code>
          </span>
        </span>
      </span>
    </div>
    """#

    @Test func downloadPanelResolvesTheSignedInstallerOffer() async throws {
        let server = try RecipeVerificationTests.StubServer(body: Self.page)
        defer { server.stop() }
        let recipe = try Self.recipe()
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "2.5.2")
        #expect(remote.downloadURL?.absoluteString == Self.archive)
        #expect(remote.expectedSHA256?.lowercased() == Self.digest.lowercased())
        #expect(remote.vendorInstallerApp?.bundleIdentifier == "com.objective-see.blockblock.installer")
        #expect(remote.requiresManualInstaller)
        #expect(outcome.warnings.isEmpty)
    }

    @Test(arguments: [
        ("7E5A332A4DA6A22E8B494418C3CAC241D24B43176C8BFC4BB2EF8BDC640BD4C7", ""),
        ("BlockBlock_2.5.2.zip", "BlockBlock_beta_2.5.2.zip"),
        ("<div class=\"product-hero\">", "<div>"),
    ])
    func unprovenDownloadKeepsDetectionOnly(original: String, replacement: String) async throws {
        let body = Self.page.replacingOccurrences(of: original, with: replacement)
        let server = try RecipeVerificationTests.StubServer(body: body)
        defer { server.stop() }
        let recipe = try Self.recipe()
        let outcome = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url))
        let remote = try #require(outcome.remote)
        #expect(remote.shortVersion == "2.5.2")
        #expect(remote.vendorInstallerApp == nil)
    }

    private static func recipe() throws -> VendorProbeRecipe {
        try #require(VendorProbeRegistry.recipes.first { $0.bundleID == "com.objective-see.blockblock.helper" })
    }
}
