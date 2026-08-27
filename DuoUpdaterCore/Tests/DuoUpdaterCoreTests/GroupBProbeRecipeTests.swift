import Testing
import Foundation
@testable import DuoUpdaterCore

/// Emacs's release Atom feed, trimmed to the two newest entries — captured
/// verbatim from `https://emacsformacosx.com/atom/release` on 2026-08-16. Kept
/// as two entries so "first match wins" (newest-first) is actually exercised,
/// and the second entry (no `-N` suffix) proves the suffix is optional, not
/// required, in the pattern.
private let emacsFeedFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Emacs For Mac OS X: Releases</title>
  <entry>
    <title>Emacs Version 30.2-2</title>
    <id>tag:emacsformacosx.com,2010:emacs-builds/Emacs-30.2-2-universal.dmg</id>
    <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml"><p><a href="https://emacsformacosx.com/emacs-builds/Emacs-30.2-2-universal.dmg">Emacs Version 30.2-2</a> - Universal Binary built on Mac OS X (169.13 MB).</p><a href="https://emacsformacosx.com/emacs-builds/Emacs-30.2-2.changes">See the differences from the last build</a>.</div>
    </content>
    <link type="binary/octet-stream" href="https://emacsformacosx.com/emacs-builds/Emacs-30.2-2-universal.dmg"/>
  </entry>
  <entry>
    <title>Emacs Version 30.2-1</title>
    <id>tag:emacsformacosx.com,2010:emacs-builds/Emacs-30.2-1-universal.dmg</id>
    <content type="xhtml">
      <div xmlns="http://www.w3.org/1999/xhtml"><p><a href="https://emacsformacosx.com/emacs-builds/Emacs-30.2-1-universal.dmg">Emacs Version 30.2-1</a> - Universal Binary built on Mac OS X (99.89 MB).</p></div>
    </content>
    <link type="binary/octet-stream" href="https://emacsformacosx.com/emacs-builds/Emacs-30.2-1-universal.dmg"/>
  </entry>
</feed>
"""#

/// Tor Browser's update-check JSON, captured verbatim from
/// `https://aus1.torproject.org/torbrowser/update_3/release/download-macos.json`
/// on 2026-08-16 (the whole body is 255 bytes).
private let torUpdateJSONFixture = #"""
{
   "binary" : "https://dist.torproject.org/torbrowser/15.0.19/tor-browser-macos-15.0.19.dmg",
   "git_tag" : "tbb-15.0.19-build1",
   "sig" : "https://dist.torproject.org/torbrowser/15.0.19/tor-browser-macos-15.0.19.dmg.asc",
   "version" : "15.0.19"
}
"""#

/// The `standaloneVersions` literal from `https://www.zotero.org/download/`,
/// captured verbatim on 2026-08-16 — the page's only machine-readable version
/// surface (there is no `update.xml` / `manifests/*.json`; both 404).
private let zoteroDownloadPageFixture = #"""
<script>window.__DATA__={"standaloneVersions":{"mac":"9.0.6","win32":"9.0.6","win-arm64":"9.0.6","win-x64":"9.0.6","linux-i686":"9.0.6","linux-x86_64":"9.0.6","win32-zip":"9.0.6"},"other":"noise 1.2.3"};</script>
"""#

/// The same literal re-captured verbatim on 2026-08-19, after Zotero 10.0 shipped
/// a TWO-segment version string. This is the body that broke the original
/// three-segment pattern in the wild (issue #8): the anchor never moved, only the
/// component count changed. Note `oldVersions` carries a three-segment 7.0.32 —
/// the pattern must not drift onto it.
private let zoteroDownloadPageFixtureV10 = #"""
<script>window.__DATA__={"standaloneVersions":{"mac":"10.0","win32":"10.0","win-arm64":"10.0","win-x64":"10.0","linux-i686":"10.0","linux-x86_64":"10.0","win32-zip":"10.0"},"oldVersions":{"macOS":{"platform":"mac","version":"7.0.32"}}};</script>
"""#

struct GroupBProbeRecipeTests {

    private func recipe(_ bundleID: String) -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
    }

    // MARK: Emacs

    @Test func emacsVersionPatternDropsTheRepackSuffix() throws {
        let recipe = try #require(self.recipe("org.gnu.Emacs"))
        // The installed bundle reports plain `30.2` (verified by mounting the
        // 30.2-2 dmg) — the `-2` repack suffix must NOT survive extraction, or
        // the probe would claim a permanent phantom update.
        #expect(VendorProbeRecipe.extractVersion(
            from: emacsFeedFixture, pattern: recipe.versionPattern) == "30.2")
    }

    @Test func emacsInstallURLKeepsTheRealSuffixedFilename() throws {
        let recipe = try #require(self.recipe("org.gnu.Emacs"))
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        // The download link legitimately DOES carry the `-2` suffix (it's the
        // real filename on disk) — only the compared version must drop it.
        #expect(VendorProbeRecipe.extractVersion(from: emacsFeedFixture, pattern: pattern)
            == "https://emacsformacosx.com/emacs-builds/Emacs-30.2-2-universal.dmg")
        #expect(spec.kind == .dmg)
    }

    @Test func emacsPatternIsUnsuffixedWhenTheEntryIsNotARepack() throws {
        let recipe = try #require(self.recipe("org.gnu.Emacs"))
        // A plain (non-repack) entry, e.g. "Emacs Version 30.1", must also match —
        // the `-N` group is optional, not required.
        let plain = "<title>Emacs Version 30.1</title>"
        #expect(VendorProbeRecipe.extractVersion(
            from: plain, pattern: recipe.versionPattern) == "30.1")
    }

    // MARK: Tor Browser

    @Test func torBrowserReadsTheVersionFieldVerbatim() throws {
        let recipe = try #require(self.recipe("org.torproject.torbrowser"))
        // Verified against the real install: CFBundleShortVersionString is
        // exactly "15.0.19" — same three-segment scheme as the feed, no
        // build/marketing split to work around.
        #expect(VendorProbeRecipe.extractVersion(
            from: torUpdateJSONFixture, pattern: recipe.versionPattern) == "15.0.19")
        #expect(recipe.versionIsBuild == false)
    }

    @Test func torBrowserInstallsTheBinaryFieldDirectly() throws {
        let recipe = try #require(self.recipe("org.torproject.torbrowser"))
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        #expect(VendorProbeRecipe.extractVersion(from: torUpdateJSONFixture, pattern: pattern)
            == "https://dist.torproject.org/torbrowser/15.0.19/tor-browser-macos-15.0.19.dmg")
        #expect(spec.kind == .dmg)
    }

    // MARK: Zotero

    @Test func zoteroReadsTheMacEntryOfStandaloneVersions() throws {
        let recipe = try #require(self.recipe("org.zotero.zotero"))
        // Verified against the real install: CFBundleShortVersionString is
        // exactly "9.0.6", matching the page's literal verbatim.
        #expect(VendorProbeRecipe.extractVersion(
            from: zoteroDownloadPageFixture, pattern: recipe.versionPattern) == "9.0.6")
    }

    @Test func zoteroReadsATwoSegmentVersion() throws {
        let recipe = try #require(self.recipe("org.zotero.zotero"))
        // Zotero 10.0 self-reports exactly "10.0" (verified by mounting
        // Zotero-10.0.dmg: CFBundleShortVersionString == CFBundleVersion == "10.0"),
        // so the two-segment page string is the correct thing to compare against —
        // it must not be padded, and must not fall through to `oldVersions`.
        #expect(VendorProbeRecipe.extractVersion(
            from: zoteroDownloadPageFixtureV10, pattern: recipe.versionPattern) == "10.0")
    }

    @Test func zoteroTwoSegmentVersionTemplatesTheInstallURL() throws {
        let recipe = try #require(self.recipe("org.zotero.zotero"))
        let spec = try #require(recipe.install)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: zoteroDownloadPageFixtureV10, pattern: fields[0]))
        // Confirmed live: the vendor's own download redirect resolves to exactly
        // this URL, and it serves a 192 MB application/x-apple-diskimage.
        #expect(template.replacingOccurrences(of: "{0}", with: version)
            == "https://download.zotero.org/client/release/10.0/Zotero-10.0.dmg")
    }

    @Test func zoteroInstallURLIsTemplatedFromTheMatchedVersion() throws {
        let recipe = try #require(self.recipe("org.zotero.zotero"))
        let spec = try #require(recipe.install)
        guard case .bodyTemplate(let template, let fields) = spec.urlSource else {
            Issue.record("expected a body template"); return
        }
        #expect(fields.count == 1)
        let version = try #require(VendorProbeRecipe.extractVersion(
            from: zoteroDownloadPageFixture, pattern: fields[0]))
        let resolved = template.replacingOccurrences(of: "{0}", with: version)
        #expect(resolved == "https://download.zotero.org/client/release/9.0.6/Zotero-9.0.6.dmg")
        #expect(spec.kind == .dmg)
    }

    // MARK: registry shape

    @Test func allThreeRecipesAreStableChannelAndOneClick() throws {
        for id in ["org.gnu.Emacs", "org.torproject.torbrowser", "org.zotero.zotero"] {
            let recipe = try #require(self.recipe(id))
            #expect(recipe.channel == .stable)
            #expect(recipe.install != nil)
        }
    }

    // MARK: OneNote — suite installer vs standalone

    /// The `FullUpdaterLocation` entry from the real OneNote MAU manifest
    /// (`0409ONMC2019.xml`), captured 2026-08-19, trimmed to the keys the recipe
    /// reads. The delta entries around it are kept because picking one of those
    /// instead is the mistake this pattern has to avoid.
    @Test func oneNoteInstallsTheStandalonePackageNotADelta() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.onenote.mac" })
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        let body = """
        <key>Payload</key>
        <string>OneNote_16.109.26041922_to_16.109.26053122_Delta.pkg</string>
        <key>Location</key>
        <string>https://res.public.onecdn.static.microsoft/x/OneNote_16.109.26041922_to_16.109.26053122_Delta.pkg</string>
        <key>FullUpdaterLocation</key>
        <string>https://res.public.onecdn.static.microsoft/x/Microsoft_OneNote_16.109.26053122_Updater.pkg</string>
        """
        // A delta applied without its baseline installs a broken app, so the
        // standalone updater is the only acceptable match.
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: pattern)
            == "https://res.public.onecdn.static.microsoft/x/Microsoft_OneNote_16.109.26053122_Updater.pkg")
    }

    /// The suite installer must not be reachable from this recipe any more. It
    /// declares eight destinations — Word, Excel, PowerPoint, Outlook, OneNote,
    /// OneDrive, AutoUpdate and a Defender shim — so installing it to update
    /// OneNote put the whole of Office on the machine.
    @Test func oneNoteDoesNotResolveTheWholeOfficeSuite() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.onenote.mac" })
        let spec = try #require(recipe.install)
        guard case .bodyPattern(let pattern) = spec.urlSource else {
            Issue.record("expected a body pattern"); return
        }
        let suite = """
        <key>FullUpdaterLocation</key>
        <string>https://res.public.onecdn.static.microsoft/x/Microsoft_365_and_Office_16.112.26081720_Installer.pkg</string>
        """
        #expect(VendorProbeRecipe.extractVersion(from: suite, pattern: pattern) == nil)
    }

    /// Detection reads the manifest's own version rather than a filename, and the
    /// build is what the bundle reports (`versionIsBuild`).
    @Test func oneNoteReadsTheManifestUpdateVersion() throws {
        let recipe = try #require(
            VendorProbeRegistry.recipes.first { $0.bundleID == "com.microsoft.onenote.mac" })
        let body = "<key>Update Version</key><string>16.109.26053122</string>"
        #expect(VendorProbeRecipe.extractVersion(from: body, pattern: recipe.versionPattern)
            == "16.109.26053122")
        #expect(recipe.versionIsBuild)
    }
}
