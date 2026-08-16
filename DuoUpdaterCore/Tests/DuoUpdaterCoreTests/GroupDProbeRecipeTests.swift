import Testing
import Foundation
@testable import DuoUpdaterCore

/// Group D — the three "directory index, take the highest version" recipes added
/// 2026-08-16 (Opera, LibreOffice, pgAdmin4). All three share one shape: a plain
/// Apache/MirrorBrain listing of version folders, sorted ALPHABETICALLY by the
/// server — never numerically — which is why every one of them requires
/// `selectHighest` and why none of them carries an install spec (see the
/// `// MARK: - 2026-08-16 group D` comment in `VendorProbeRecipe.swift` for the
/// full reasoning). Fixtures below are trimmed excerpts of the real page bodies,
/// captured 2026-08-16, keeping every line that matters to the assertions.
struct GroupDProbeRecipeTests {

    // MARK: - Opera

    /// Excerpt of `https://get.geo.opera.com/pub/opera/desktop/`: the true first
    /// entries (100.x, alphabetically first because "1" < "9"), the run that
    /// contains the actual highest release (133.x/134.x, plus a decoy "15.0.…"
    /// legacy entry that sorts even later than 134.x alphabetically), and the
    /// tail (99.x — numerically almost the lowest major, but alphabetically LAST
    /// on the whole page). This is the exact shape that makes first-match,
    /// last-match, and "assume the page is sorted" all wrong at once.
    private let operaIndexFixture = """
    <html>
    <head><title>Index of /pub/opera/desktop/</title></head>
    <body>
    <h1>Index of /pub/opera/desktop/</h1><hr><pre><a href="../">../</a>
    <a href="100.0.4815.20/">100.0.4815.20/</a>                                     20-Jun-2023 06:35                   -
    <a href="100.0.4815.21/">100.0.4815.21/</a>                                     20-Jun-2023 12:05                   -
    <a href="133.0.5932.10/">133.0.5932.10/</a>                                     29-Jun-2026 09:55                   -
    <a href="133.0.5932.85/">133.0.5932.85/</a>                                     23-Jul-2026 11:37                   -
    <a href="134.0.5954.46/">134.0.5954.46/</a>                                     06-Aug-2026 11:52                   -
    <a href="134.0.5954.56/">134.0.5954.56/</a>                                     12-Aug-2026 12:02                   -
    <a href="15.0.1147.130/">15.0.1147.130/</a>                                     01-Jul-2013 15:18                   -
    <a href="99.0.4788.88/">99.0.4788.88/</a>                                      27-Jun-2023 13:52                   -
    <a href="99.0.4788.9/">99.0.4788.9/</a>                                       18-Sep-2023 11:38                   -
    </pre><hr></body>
    </html>
    """

    private var opera: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "com.operasoftware.Opera" }
    }

    @Test func operaSelectsTheTrueNumericMaximum() throws {
        let recipe = try #require(opera)
        #expect(recipe.selectHighest)
        #expect(VendorProbeRecipe.highestVersion(
            from: operaIndexFixture, pattern: recipe.versionPattern) == "134.0.5954.56")
    }

    /// The trap, pinned explicitly: without `selectHighest`, "first match" grabs
    /// the alphabetically-earliest folder (100.x — a 2023 release, and neither the
    /// newest nor the oldest on the page), and "last match" grabs 99.x — an even
    /// older one that merely happens to sort last as a string. Neither is close to
    /// the real newest release, 134.0.5954.56.
    @Test func neitherFirstNorLastMatchWouldFindTheRealNewest() throws {
        let recipe = try #require(opera)
        #expect(VendorProbeRecipe.extractVersion(
            from: operaIndexFixture, pattern: recipe.versionPattern) == "100.0.4815.20")
        #expect(VendorProbeRecipe.lastMatch(
            from: operaIndexFixture, pattern: recipe.versionPattern) == "99.0.4788.9")
    }

    /// `href="…/"` is the anchor that keeps the pattern from wandering off into
    /// dates or file sizes — neither of which contains a dot in this listing, but
    /// the anchor is what makes that a guarantee rather than a coincidence.
    @Test func patternIsAnchoredToTheHrefAttribute() throws {
        let recipe = try #require(opera)
        #expect(recipe.versionPattern.contains(#"href=""#))
        #expect(recipe.versionPattern.hasSuffix(#"/""#))
    }

    /// Verified 2026-08-16 by mounting `Opera_134.0.5954.56_Setup.dmg`: the bundle
    /// reports `CFBundleShortVersionString = "134.0"` but `CFBundleVersion =
    /// "134.0.5954.56"` — exactly the folder name. Comparing the folder version
    /// against the 2-part marketing string would read every release as a phantom
    /// major upgrade, so this must be a build comparison.
    @Test func operaComparesOnTheBuildNotTheMarketingString() throws {
        let recipe = try #require(opera)
        #expect(recipe.versionIsBuild)
    }

    /// Detection-only: no safe way to build an install URL from a page whose
    /// ordering can't be trusted (see the type-level doc comment above).
    @Test func operaIsDetectionOnly() throws {
        let recipe = try #require(opera)
        #expect(recipe.install == nil)
    }

    // MARK: - LibreOffice

    /// Real body of `https://download.documentfoundation.org/libreoffice/stable/`,
    /// captured 2026-08-16 in full (it's short).
    private let libreOfficeIndexFixture = """
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
     <head>
      <title>Index of /libreoffice/stable</title>
      <link rel="stylesheet" href="/mirrorbrain.css" type="text/css" />
     </head>
     <body>
    <h1>Index of /libreoffice/stable</h1>
    <table><tr><th>&nbsp;</th><th><a href="?C=N;O=D">Name</a></th><th><a href="?C=M;O=A">Last modified</a></th><th><a href="?C=S;O=A">Size</a></th><th>Metadata</th></tr><tr><th colspan="5"><hr /></th></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="/libreoffice/">Parent Directory</a></td><td>&nbsp;</td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="25.8.6/">25.8.6/</a></td><td align="right">23-Mar-2026 10:43  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="25.8.7/">25.8.7/</a></td><td align="right">11-May-2026 10:21  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="26.2.2/">26.2.2/</a></td><td align="right">23-Mar-2026 10:44  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="26.2.3/">26.2.3/</a></td><td align="right">30-Apr-2026 08:55  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="26.2.4/">26.2.4/</a></td><td align="right">04-Jun-2026 09:54  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><td valign="top">&nbsp;</td><td><a href="26.2.5/">26.2.5/</a></td><td align="right">24-Jul-2026 07:14  </td><td align="right">  - </td><td>&nbsp;</td></tr>
    <tr><th colspan="5"><hr /></th></tr>
    </table>
    <address>Apache Server at <a href="mailto:hostmaster@documentfoundation.org">download.documentfoundation.org</a> Port 80</address>
    <br/><address><a href="http://mirrorbrain.org/">MirrorBrain</a> powered by <a href="http://httpd.apache.org/">Apache</a></address>
    </body></html>
    """

    private var libreOffice: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.libreoffice.script" }
    }

    @Test func libreOfficeReadsTheNewestFolder() throws {
        let recipe = try #require(libreOffice)
        #expect(recipe.selectHighest)
        #expect(VendorProbeRecipe.highestVersion(
            from: libreOfficeIndexFixture, pattern: recipe.versionPattern) == "26.2.5")
    }

    /// The MirrorBrain sort-toggle links (`?C=N;O=D` etc.) carry no dotted digits,
    /// so they can never match this pattern — but the fixture pins that they don't,
    /// rather than assuming it.
    @Test func sortToggleLinksNeverMatch() throws {
        let recipe = try #require(libreOffice)
        let regex = try NSRegularExpression(pattern: recipe.versionPattern)
        let range = NSRange(libreOfficeIndexFixture.startIndex..., in: libreOfficeIndexFixture)
        let matches = regex.matches(in: libreOfficeIndexFixture, options: [], range: range)
        #expect(matches.count == 6) // exactly the six version folders, nothing else
    }

    /// A loose, unanchored pattern (bare `\\d+\\.\\d+\\.\\d+`, no `href="…/"`
    /// wrapper) matches TWICE per folder here — once inside the `href` attribute,
    /// once in the visible link text MirrorBrain repeats right after it
    /// (`<a href="26.2.5/">26.2.5/</a>`) — twelve matches for six real releases.
    /// Both copies happen to carry the same value on this particular page, so
    /// `highestVersion` still lands on the right answer today, but it's the
    /// `href="…/"` anchor — matching the link target exactly once — that makes
    /// that a guarantee rather than a coincidence a future markup tweak could
    /// break.
    @Test func unanchoredPatternDoubleCountsEveryFolder() throws {
        let loose = try NSRegularExpression(pattern: #"[0-9]+\.[0-9]+\.[0-9]+"#)
        let range = NSRange(libreOfficeIndexFixture.startIndex..., in: libreOfficeIndexFixture)
        #expect(loose.matches(in: libreOfficeIndexFixture, options: [], range: range).count == 12)
    }

    /// Verified 2026-08-16 by mounting `LibreOffice_26.2.5_MacOS_aarch64.dmg`: the
    /// bundle's `CFBundleShortVersionString` is the 4-segment `"26.2.5.2"`, not the
    /// bare `"26.2.5"` this index publishes — the trap the task brief called out.
    /// `VersionComparator` treats a missing trailing component as `0`, so comparing
    /// `"26.2.5"` against the installed `"26.2.5.2"` reads as "not newer" (safe
    /// direction: never a phantom update), which is why this recipe does NOT need
    /// `versionIsBuild` despite the segment-count mismatch — it isn't a build vs.
    /// marketing mismatch, both installed fields already agree on `26.2.5.2`.
    @Test func libreOfficeVersionIsCoarserThanTheInstalledFourSegmentString() {
        #expect(VersionComparator.compare("26.2.5", "26.2.5.2") == .orderedAscending)
        #expect(!VersionComparator.isNewer("26.2.5", than: "26.2.5.2"))
    }

    /// A 3-segment feed version against a 4-segment installed one is safe to
    /// COMPARE (above) but must not be pasted into a download URL blindly: the
    /// artifact is published under the 3-segment folder, which is exactly what the
    /// version template uses. Pinned so a later "let's make the pattern capture
    /// all four segments" change fails here instead of 404-ing at install time.
    @Test func libreOfficeInstallURLUsesTheThreeSegmentFolder() throws {
        let recipe = try #require(libreOffice)
        let spec = try #require(recipe.install)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("expected a version template"); return
        }
        #expect(!template.contains("26.2.5.2"))
        #expect(template.replacingOccurrences(of: "{version}", with: "26.2.5")
            .hasSuffix("/26.2.5/mac/aarch64/LibreOffice_26.2.5_MacOS_aarch64.dmg"))
    }

    // MARK: - pgAdmin4

    /// Real body of `https://ftp.postgresql.org/pub/pgadmin/pgadmin4/`, captured
    /// 2026-08-16 in full.
    private let pgAdminIndexFixture = """
    <html>
    <head><title>Index of /pub/pgadmin/pgadmin4/</title></head>
    <body>
    <h1>Index of /pub/pgadmin/pgadmin4/</h1><hr><pre><a href="../">../</a>
    <a href="apt/">apt/</a>                                               11-May-2026 13:33                   -
    <a href="autoupdate/">autoupdate/</a>                                        12-Aug-2025 06:56                   -
    <a href="snapshots/">snapshots/</a>                                         16-Aug-2026 02:02                   -
    <a href="v1.6/">v1.6/</a>                                              13-Jul-2017 14:32                   -
    <a href="v2.1/">v2.1/</a>                                              11-Jan-2018 13:33                   -
    <a href="v3.6/">v3.6/</a>                                              29-Nov-2018 12:14                   -
    <a href="v4.30/">v4.30/</a>                                             28-Jan-2021 11:38                   -
    <a href="v5.7/">v5.7/</a>                                              09-Sep-2021 09:08                   -
    <a href="v6.21/">v6.21/</a>                                             09-Mar-2023 11:17                   -
    <a href="v7.8/">v7.8/</a>                                              19-Oct-2023 10:04                   -
    <a href="v8.14/">v8.14/</a>                                             12-Dec-2024 06:27                   -
    <a href="v9.11/">v9.11/</a>                                             11-Dec-2025 06:03                   -
    <a href="v9.12/">v9.12/</a>                                             05-Feb-2026 09:53                   -
    <a href="v9.13/">v9.13/</a>                                             05-Mar-2026 06:46                   -
    <a href="v9.14/">v9.14/</a>                                             02-Apr-2026 06:37                   -
    <a href="v9.15/">v9.15/</a>                                             11-May-2026 13:02                   -
    <a href="v9.16/">v9.16/</a>                                             18-Jun-2026 14:22                   -
    <a href="v9.17/">v9.17/</a>                                             31-Jul-2026 09:09                   -
    <a href="yum/">yum/</a>                                               04-Apr-2024 14:32                   -
    <a href="README">README</a>                                             04-Feb-2021 14:58                  94
    </pre><hr></body>
    </html>
    """

    private var pgAdmin: VendorProbeRecipe? {
        VendorProbeRegistry.recipes.first { $0.bundleID == "org.pgadmin.pgadmin4" }
    }

    @Test func pgAdminReadsTheNewestRelease() throws {
        let recipe = try #require(pgAdmin)
        #expect(recipe.selectHighest)
        #expect(VendorProbeRecipe.highestVersion(
            from: pgAdminIndexFixture, pattern: recipe.versionPattern) == "9.17")
    }

    /// The trap for THIS page: without the `v` anchor, `extractVersion`'s "first
    /// match" over the loose `[0-9]+\\.[0-9]+` shape would grab whatever number-like
    /// text comes first in document order — including things that are not
    /// releases at all. Pin it against the real siblings: `apt/`, `autoupdate/`,
    /// `snapshots/`, `yum/` and `README` carry no digit right after a `v`, so the
    /// anchored pattern matches none of them — only the eighteen `vX.Y/` releases
    /// do, of which `v9.17` is the numeric maximum.
    @Test func nonReleaseSiblingsNeverMatchTheAnchoredPattern() throws {
        let recipe = try #require(pgAdmin)
        let regex = try NSRegularExpression(pattern: recipe.versionPattern)
        let range = NSRange(pgAdminIndexFixture.startIndex..., in: pgAdminIndexFixture)
        let matches = regex.matches(in: pgAdminIndexFixture, options: [], range: range)
        #expect(matches.count == 15) // v1.6, v2.1, v3.6, v4.30, v5.7, v6.21, v7.8, v8.14, v9.11–v9.17
    }

    /// The loose pattern the brief warns about: drop the `v` anchor and require
    /// only digits-dot-digits anywhere in the body, and `snapshots/`'s neighbor
    /// `README`'s size column (`94`) still can't match (no dot) — but `apt/`,
    /// `autoupdate/` etc. genuinely carry no version-shaped text either, so the
    /// real trap on THIS page is not noise, it's alphabetical order once pgAdmin
    /// eventually reaches v10.x (`"v10.0"` < `"v9.17"` as a string) — the same
    /// order hazard `selectHighest` exists to neutralize, pinned generically by
    /// the Opera test above.
    @Test func firstMatchAloneWouldGrabTheOldestRelease() throws {
        let recipe = try #require(pgAdmin)
        #expect(VendorProbeRecipe.extractVersion(
            from: pgAdminIndexFixture, pattern: recipe.versionPattern) == "1.6")
    }

    @Test func pgAdminIsDetectionOnly() throws {
        let recipe = try #require(pgAdmin)
        #expect(recipe.install == nil)
    }

    // MARK: - Cross-cutting

    /// Opera and pgAdmin stay detection-only: their artifacts are not at a path
    /// the matched version alone determines. LibreOffice's are (see below), so it
    /// is deliberately excluded here.
    @Test func operaAndPgAdminAreStableChannelDetectionOnly() {
        let bundleIDs = ["com.operasoftware.Opera", "org.pgadmin.pgadmin4"]
        for id in bundleIDs {
            guard let recipe = VendorProbeRegistry.recipes.first(where: { $0.bundleID == id })
            else {
                Issue.record("missing recipe for \(id)")
                continue
            }
            #expect(recipe.channel == .stable)
            #expect(recipe.install == nil)
            #expect(recipe.selectHighest)
        }
    }

    /// LibreOffice's dmg lives at a path fully determined by the version, so it
    /// installs — but ONLY through `.versionTemplate`. On this alphabetically
    /// sorted index the first `href="X.Y.Z/"` in the document is NOT the release
    /// `selectHighest` picks, so a `.bodyTemplate` (first-match regexes) would
    /// build a URL for an older version than the one being reported. This test
    /// pins both halves: the source case, and the fact that they really do differ
    /// on the real page.
    @Test func libreOfficeInstallsFromTheResolvedVersionNotTheFirstMatch() throws {
        let recipe = try #require(libreOffice)
        let spec = try #require(recipe.install)
        #expect(spec.kind == .dmg)
        guard case .versionTemplate(let template) = spec.urlSource else {
            Issue.record("LibreOffice must not template off first-match body regexes")
            return
        }
        #expect(template.contains("{version}"))
        #expect(recipe.selectHighest)

        // The trap, on the captured index: first match ≠ highest.
        let first = VendorProbeRecipe.extractVersion(
            from: libreOfficeIndexFixture, pattern: recipe.versionPattern)
        #expect(first != nil)
        #expect(first != "26.2.5", "fixture no longer exercises the ordering trap")

        // What the resolved version actually builds. Verified live 2026-08-16:
        // this URL 302s to a MirrorBrain mirror carrying the real dmg.
        let url = template.replacingOccurrences(of: "{version}", with: "26.2.5")
        #expect(url == "https://download.documentfoundation.org/libreoffice/stable/"
            + "26.2.5/mac/aarch64/LibreOffice_26.2.5_MacOS_aarch64.dmg")
    }
}
