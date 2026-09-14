import Foundation

enum org_zotero_zotero {
    static let set = AppRecipeSet(
        family: "org-zotero-zotero",
        probes: [
        // History: docs/app-audits/org-zotero-zotero.md#历史与实测
        // Zotero — no version API at all: `update.xml` and every `manifests/*.json`
        // path 404, and `dl.php` merely echoes back whatever version is passed to
        // it (not a source of truth). The one stable anchor is an inline JS literal
        // on the download page, `www.zotero.org/download/`:
        // `"standaloneVersions":{"mac":"10.0","win32":"10.0",...}`. The pattern
        // is scoped to the `standaloneVersions` object and its `"mac"` key
        // specifically, so it can't drift onto a Windows/Linux number in the same
        // literal, and to the closing quote so it can't capture a truncated value.
        //
        // The version component count is NOT fixed at three: Zotero 10.0 shipped
        // as a two-segment string (2026-08-17), which is what broke the original
        // `[0-9]+\.[0-9]+\.[0-9]+` pattern — the literal is still on the page,
        // unchanged in shape. On the mounted `Zotero-10.0.dmg`,
        // CFBundleShortVersionString and CFBundleVersion are both exactly `10.0`
        // (checked 2026-08-19), so the page string still matches what the installed
        // bundle self-reports and no phantom update is possible; still
        // org.zotero.zotero, Team 8LAYR367YV, notarized Developer ID
        // (`spctl -t install`: accepted). The vendor's own
        // `download/client/dl?channel=release&platform=mac` redirect resolves to
        // exactly the templated URL below, so the template shape is unchanged.
        //
        // One-click: the dmg at
        // `download.zotero.org/client/release/<ver>/Zotero-<ver>.dmg` holds
        // org.zotero.zotero, Team 8LAYR367YV (Corporation for Digital Scholarship),
        // notarized Developer ID, universal binary, with a
        // CFBundleShortVersionString that matches the page verbatim, no scheme
        // mismatch (first checked 2026-08-16; History has the version). Zotero
        // publishes every release at that exact path/filename shape, so the
        // install URL is templated from the matched version rather than scraped
        // (there is no link to scrape — the download button is client-rendered).
        VendorProbeRecipe(
            bundleID: "org.zotero.zotero",
            url: URL(string: "https://www.zotero.org/download/")!,
            mode: .responseBody,
            versionPattern: #""standaloneVersions"\s*:\s*\{\s*"mac"\s*:\s*"([0-9]+(?:\.[0-9]+){1,2})""#,
            downloadURL: URL(string: "https://www.zotero.org/download/"),
            changelogURL: URL(string: "https://www.zotero.org/support/changelog"),
            install: VendorInstallSpec(
                urlSource: .bodyTemplate(
                    "https://download.zotero.org/client/release/{0}/Zotero-{0}.dmg",
                    fields: [#""standaloneVersions"\s*:\s*\{\s*"mac"\s*:\s*"([0-9]+(?:\.[0-9]+){1,2})""#]),
                kind: .dmg)),
        ])
}
