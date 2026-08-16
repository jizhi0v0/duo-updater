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

struct GroupBProbeRecipeTests {

    private func recipe(_ bundleID: String) -> VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == bundleID }
    }

    // MARK: Emacs

    @Test func emacsVersionPatternDropsTheRepackSuffix() throws {
        let recipe = try #require(recipe("org.gnu.Emacs"))
        // The installed bundle reports plain `30.2` (verified by mounting the
        // 30.2-2 dmg) — the `-2` repack suffix must NOT survive extraction, or
        // the probe would claim a permanent phantom update.
        #expect(VendorProbeRecipe.extractVersion(
            from: emacsFeedFixture, pattern: recipe.versionPattern) == "30.2")
    }

    @Test func emacsInstallURLKeepsTheRealSuffixedFilename() throws {
        let recipe = try #require(recipe("org.gnu.Emacs"))
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
        let recipe = try #require(recipe("org.gnu.Emacs"))
        // A plain (non-repack) entry, e.g. "Emacs Version 30.1", must also match —
        // the `-N` group is optional, not required.
        let plain = "<title>Emacs Version 30.1</title>"
        #expect(VendorProbeRecipe.extractVersion(
            from: plain, pattern: recipe.versionPattern) == "30.1")
    }

    // MARK: Tor Browser

    @Test func torBrowserReadsTheVersionFieldVerbatim() throws {
        let recipe = try #require(recipe("org.torproject.torbrowser"))
        // Verified against the real install: CFBundleShortVersionString is
        // exactly "15.0.19" — same three-segment scheme as the feed, no
        // build/marketing split to work around.
        #expect(VendorProbeRecipe.extractVersion(
            from: torUpdateJSONFixture, pattern: recipe.versionPattern) == "15.0.19")
        #expect(recipe.versionIsBuild == false)
    }

    @Test func torBrowserInstallsTheBinaryFieldDirectly() throws {
        let recipe = try #require(recipe("org.torproject.torbrowser"))
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
        let recipe = try #require(recipe("org.zotero.zotero"))
        // Verified against the real install: CFBundleShortVersionString is
        // exactly "9.0.6", matching the page's literal verbatim.
        #expect(VendorProbeRecipe.extractVersion(
            from: zoteroDownloadPageFixture, pattern: recipe.versionPattern) == "9.0.6")
    }

    @Test func zoteroInstallURLIsTemplatedFromTheMatchedVersion() throws {
        let recipe = try #require(recipe("org.zotero.zotero"))
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
            let recipe = try #require(recipe(id))
            #expect(recipe.channel == .stable)
            #expect(recipe.install != nil)
        }
    }
}
