import Foundation
import Testing

@testable import DuoUpdaterCore

struct SigilRecipeTests {
    private static let downloads = #"""
        <p><a href="https://github.com/Sigil-Ebook/Sigil/releases/download/2.8.6/Sigil-2.8.6-Windows-x64-Setup.exe" class="btn btn--success">Latest Windows x64 download</a><br /><a href="https://github.com/Sigil-Ebook/Sigil/releases/download/2.8.6/Sigil.app-2.8.6-Mac-x86_64.txz" class="btn btn--success">Latest MacOS (Intel) download</a><br /><a href="https://github.com/Sigil-Ebook/Sigil/releases/download/2.8.6/Sigil.app-2.8.6-Mac-arm64.txz" class="btn btn--success">Latest MacOS (Arm64) download</a></p>
        """#

    @Test func latestOfficialArmLinkSetsBothVersionAndArchive() async throws {
        let recipe = try #require(com_sigil_ebook_Sigil_app.set.probes.first)
        let server = try RecipeVerificationTests.StubServer(body: Self.downloads, contentType: "text/html")
        defer { server.stop() }
        let remote = await VendorProbeSource().probeDiagnostic(recipe.with(url: server.url)).remote

        #expect(remote?.shortVersion == "2.8.6")
        #expect(remote?.downloadURL?.absoluteString
            == "https://github.com/Sigil-Ebook/Sigil/releases/download/2.8.6/Sigil.app-2.8.6-Mac-arm64.txz")
        #expect(remote?.vendorInstallerKind == .tarGz)
    }

    @Test func otherAssetsAndAnArchiveFromAnotherVersionDoNotResolve() throws {
        let recipe = try #require(com_sigil_ebook_Sigil_app.set.probes.first)
        for body in [
            Self.downloads.replacingOccurrences(of: "-Mac-arm64.txz", with: "-Mac-x86_64.txz"),
            Self.downloads.replacingOccurrences(of: "Sigil.app-2.8.6-Mac-arm64", with: "Sigil.app-2.8.1-Mac-arm64"),
            Self.downloads.replacingOccurrences(of: "/download/2.8.6/", with: "/download/2.8.6-beta/"),
            Self.downloads.replacingOccurrences(of: "github.com/", with: "github.com.example/"),
        ] {
            #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern) == nil)
        }
    }

    @Test func keepsSectionAndWrappedBulletWithTheirPublishedVersion() throws {
        let body = """
            pre-2.8.7
               New Features
                 - Unreleased.

            Sigil-2.8.6
               Bug Fixes

                 - fix bug in epub3 when updating or changing the cover image that can cause OPF manifest entry damage
                      (Thankyou ABeater)

            Sigil 2.8.1
               Bug Fixes
                 - add workarounds to macOS Tahoe bugs that prevent modal native dialogs from working
            """
        let recipe = try #require(com_sigil_ebook_Sigil_app.set.changelogs.first)
        let entries = try #require(ChangelogExtractor.extract(from: body, using: recipe)).entries

        #expect(entries.map(\.version) == ["2.8.6", "2.8.1"])
        #expect(entries.first?.content == [
            .heading("Bug Fixes"),
            .note("fix bug in epub3 when updating or changing the cover image that can cause OPF manifest entry damage (Thankyou ABeater)"),
        ])
        #expect(entries.last?.content == [
            .heading("Bug Fixes"),
            .note("add workarounds to macOS Tahoe bugs that prevent modal native dialogs from working"),
        ])
    }
}
