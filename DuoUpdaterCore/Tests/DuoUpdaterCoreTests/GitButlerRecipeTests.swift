import Foundation
import Testing
@testable import DuoUpdaterCore

struct GitButlerRecipeTests {
    private static let archive = "https://releases.gitbutler.com/releases/release/0.23.5-3373/macos/aarch64/GitButler.app.tar.gz"

    // Trimmed from the official stable Tauri response and stable download page.
    private static let manifest = """
        {"url":"\(archive)","version":"0.23.5","notes":"## Changes\\n\\n- Linux: GitButler is now on Flathub","pub_date":"2026-11-20T13:42:54+00:00"}
        """

    private static let html = """
        <section class="latest-release svelte-19lfojq"><div class="latest-release__header-subtitle svelte-19lfojq"><span class="svelte-19lfojq">0.23.5 Latest release</span> <span class="svelte-19lfojq">•</span> <span class="svelte-19lfojq">20 November 2026</span></div>
        <div class="download-links__wrapper svelte-19lfojq"><ul><li>Apple Silicon</li></ul></div>
        <div class="release-notes-content svelte-19lfojq"><h2><!--[-->Changes<!--]--></h2><ul><li><!--[-->Linux: GitButler is now on <a href="https://flathub.org/apps/com.gitbutler.gitbutler">Flathub</a><!--]--></li></ul>
        <h2><!--[-->Native app<!--]--></h2><p><!--[-->Highlights from the native app.<!--]--></p><ul><li><!--[-->You can now pick separate themes for light and dark mode<!--]--></li></ul></div></section>
        <section class="releases svelte-19lfojq"><div class="release svelte-w1upf4"><h3 class="release-version svelte-w1upf4">0.23.4</h3> <span class="release-date svelte-w1upf4">11 Nov 2026</span>
        <div class="stack-v gap-16"><div class="release-notes-content svelte-w1upf4"><h2><!--[-->Changes<!--]--></h2><ul><li><!--[-->Repositories using Git LFS or git-crypt no longer get a warning to avoid GitButler<!--]--></li></ul></div></div></div></section>
        """

    private var probe: VendorProbeRecipe { com_gitbutler_app.set.probes[0] }

    @Test func resolvesTheStableArm64ArchiveAndItsVersion() async throws {
        let reordered = """
            {"notes":"Never read a string containing \\"version\\":\\"3.0.0\\" as a manifest field","version":"0.23.5","url":"\(Self.archive)"}
            """
        for body in [Self.manifest, reordered] {
            let server = try RecipeVerificationTests.StubServer(body: body, contentType: "application/json")
            defer { server.stop() }
            let remote = await VendorProbeSource().probeDiagnostic(probe.with(url: server.url)).remote
            #expect(remote?.shortVersion == "0.23.5")
            #expect(remote?.downloadURL?.absoluteString == Self.archive)
            #expect(remote?.vendorInstallerKind == .tarGz)
        }
        #expect(probe.bundleID == "com.gitbutler.app")
        #expect(probe.channel == .stable)
        #expect(probe.hostRequirement?.architectures == [.arm64])
    }

    @Test func rejectsMismatchedVersionsAndOtherDistributionPaths() async throws {
        let invalid = [
            Self.manifest.replacingOccurrences(of: "\"version\":\"0.23.5\"", with: "\"version\":\"0.23.6\""),
            Self.manifest.replacingOccurrences(of: "/release/", with: "/nightly/"),
            Self.manifest.replacingOccurrences(of: "/aarch64/", with: "/x86_64/"),
            Self.manifest.replacingOccurrences(of: "releases.gitbutler.com", with: "other.example"),
            "{\"response\":\(Self.manifest)}",
            "",
        ]
        #expect(Set(invalid).count == invalid.count)
        for body in invalid {
            let server = try RecipeVerificationTests.StubServer(body: body, contentType: "application/json")
            defer { server.stop() }
            let remote = await VendorProbeSource().probeDiagnostic(probe.with(url: server.url)).remote
            #expect(remote == nil)
        }
    }

    @Test func preservesHeadingsAndDoesNotBorrowNotesFromTheNextRelease() throws {
        let recipe = try #require(com_gitbutler_app.set.changelogs.first)
        let missingNotes = """
            <h3 class="release-version svelte-w1upf4">0.23.6</h3> <span class="release-date svelte-w1upf4">20 Nov 2026</span>
            """
        let htmlWithMissingNotes = Self.html.replacingOccurrences(
            of: "<section class=\"releases svelte-19lfojq\">",
            with: "<section class=\"releases svelte-19lfojq\">\(missingNotes)")
        let entries = try #require(ChangelogExtractor.extract(from: htmlWithMissingNotes, using: recipe)).entries
        #expect(entries.map(\.version) == ["0.23.5", "0.23.4"])
        #expect(entries.map(\.date) == ["20 November 2026", "11 Nov 2026"])
        #expect(entries.first?.content == [
            .heading("Changes"),
            .note("Linux: GitButler is now on Flathub"),
            .heading("Native app"),
            .note("Highlights from the native app."),
            .note("You can now pick separate themes for light and dark mode"),
        ])
        #expect(entries.last?.items == [
            "Repositories using Git LFS or git-crypt no longer get a warning to avoid GitButler",
        ])
    }
}
