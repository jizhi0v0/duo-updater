import Testing
import Foundation
@testable import DuoUpdaterCore

/// The `Location` Dropbox's download link answers with when asked for the arm64
/// build. Captured 2026-09-14 with a no-follow HEAD on
/// `https://www.dropbox.com/download?plat=mac&full=1&arch=arm64` → `302`.
private let dropboxArm64RedirectFixture =
    "https://edge.dropboxstatic.com/dbx-releng/client/Dropbox%20268.4.4124.arm64.dmg"

/// The same link without `&arch=arm64`, captured the same way the same day. The
/// dmg behind it is x86_64-only: mounted 2026-09-14, `lipo -archs` on
/// `Dropbox.app/Contents/MacOS/Dropbox` read `x86_64`, and its sha256 is the one
/// the Homebrew cask labels `intel:`. This is the filename the recipe used to
/// read and install.
private let dropboxIntelRedirectFixture =
    "https://edge.dropboxstatic.com/dbx-releng/client/Dropbox%20268.4.4124.dmg"

@Suite struct DropboxProbeRecipeTests {
    private var recipe: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.getdropbox.dropbox" }
    }

    /// One-click must fetch the arm64 dmg, and the probe must read the same URL
    /// the installer fetches — so the version offered is the version downloaded.
    /// Dropping the query from the install URL alone, from the probe alone, or
    /// from both turns this red.
    @Test func probeAndInstallBothAskForTheArm64Build() throws {
        let recipe = try #require(recipe)
        guard case .redirectFilename = recipe.mode else {
            Issue.record("expected the redirect-filename mode"); return
        }
        let install = try #require(recipe.install)
        guard case .redirect(let installURL) = install.urlSource else {
            Issue.record("expected a .redirect install source"); return
        }
        #expect(install.kind == .dmg)
        #expect(installURL == recipe.url,
                "the probe must read the redirect the installer follows")

        let query = try #require(
            URLComponents(url: installURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.filter { $0.name == "arch" }.map(\.value) == ["arm64"])
        #expect(query.contains(URLQueryItem(name: "plat", value: "mac")))
        #expect(query.contains(URLQueryItem(name: "full", value: "1")))
    }

    /// The pattern reads the arm64 filename and refuses the Intel one, so a
    /// Dropbox that stops honouring `arch=arm64` shows up as a pattern miss in
    /// `duo verify` rather than as an update the architecture gate refuses after
    /// a full download. Relaxing `.arm64` to optional turns the second
    /// expectation red.
    @Test func versionPatternReadsOnlyTheArm64Filename() throws {
        let recipe = try #require(recipe)
        #expect(VendorProbeRecipe.extractVersion(
            from: dropboxArm64RedirectFixture, pattern: recipe.versionPattern) == "268.4.4124")
        #expect(VendorProbeRecipe.extractVersion(
            from: dropboxIntelRedirectFixture, pattern: recipe.versionPattern) == nil)
    }
}
