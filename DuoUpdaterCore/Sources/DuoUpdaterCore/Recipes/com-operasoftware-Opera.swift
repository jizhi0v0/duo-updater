import Foundation

enum com_operasoftware_Opera {
    static let set = AppRecipeSet(
        family: "com-operasoftware-Opera",
        probes: [
        // MARK: - 2026-08-16 group D (directory indexes)
        //
        // All three — Opera (this file), LibreOffice (`Recipes/org-libreoffice-script.swift`)
        // and pgAdmin (`Recipes/org-pgadmin-pgadmin4.swift`) — are the same shape: a
        // vendor's plain Apache/MirrorBrain
        // directory listing of version folders, sorted ALPHABETICALLY (not
        // numerically) by every one of these servers — confirmed for Opera by
        // diffing the default listing against an explicit `?C=N;O=A` (name,
        // ascending) request: identical. Alphabetical sort makes `selectHighest`
        // mandatory (`"100.0…" < "99.0…"` as strings, so first-in-document is
        // often not the newest), and — for exactly the same reason — makes it UNSAFE
        // to build the install/download URL from ANY single match (first OR last):
        // once a version component crosses a digit-width boundary (Opera's 3-digit
        // major overtaking 2-digit, pgAdmin's major eventually reaching v10 and
        // sorting ahead of v9.x, a LibreOffice patch someday reaching two digits)
        // the alphabetically-first-or-last entry silently stops being the numeric
        // maximum, and a template built from it would download an OLDER build than
        // the one just reported as available. So all three build the install URL
        // with `.versionTemplate`, which fills in the version the probe RESOLVED
        // rather than a match over the listing, and all three are one-click; each
        // mounts to a genuine, notarized, Developer-ID-signed app (verified in
        // each recipe's own comment, and for Opera in its audit History).

        // History: docs/app-audits/com-operasoftware-Opera.md#历史与实测
        // Opera — `get.geo.opera.com` is Opera's own CDN mirror index, one folder
        // per released version (e.g. `134.0.5954.56/`), each holding a `mac/` dir with
        // `Opera_<version>_Setup.dmg`. The `href="…/"` anchor matches nothing but
        // version folders on this page (checked: every 4-dot-separated number in
        // the raw body is inside an `href`, none appear elsewhere — no stray dates
        // or sizes share that shape here).
        //
        // VERSION SCHEME TRAP: `CFBundleShortVersionString` is only major.minor
        // (e.g. `"134.0"`) while `CFBundleVersion` is the four-part version (e.g.
        // `"134.0.5954.56"`) — exactly what the folder name carries (verified
        // 2026-08-16 on a mounted dmg; History has the details). Comparing the
        // 4-part folder version against the 2-part marketing string would read
        // every release as a phantom major upgrade forever, so this is a build
        // comparison (`versionIsBuild`), not a marketing one.
        VendorProbeRecipe(
            bundleID: "com.operasoftware.Opera",
            url: URL(string: "https://get.geo.opera.com/pub/opera/desktop/")!,
            mode: .responseBody,
            versionPattern: #"href="([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/""#,
            downloadURL: URL(string: "https://www.opera.com/download"),
            changelogURL: URL(string: "https://blogs.opera.com/desktop/"),
            selectHighest: true,
            versionIsBuild: true,
            // ONE-CLICK via `.versionTemplate` — see LibreOffice (`Recipes/org-libreoffice-script.swift`) for why the
            // template must fill the RESOLVED version and not a first-match regex
            // on this alphabetically-sorted index.
            //
            // Despite the "Setup" in the filename this dmg is NOT a stub
            // downloader (the 1Password trap): mounted on 2026-08-16 it carried
            // `Opera.app` itself (History has the details). Its `CFBundleVersion`
            // is exactly the folder name this recipe compares, which is what makes
            // the template safe as well as the comparison.
            install: VendorInstallSpec(
                urlSource: .versionTemplate(
                    "https://get.geo.opera.com/pub/opera/desktop/"
                    + "{version}/mac/Opera_{version}_Setup.dmg"),
                kind: .dmg)),
        ],
        changelogs: [
        // Opera — one page per MAJOR version, listing every build in it newest
        // first: `blogs.opera.com/desktop/changelog-for-134/`. Each entry is
        //   <h4><strong> 134.0.5954.56 &#8211; 2026-08-12 <a …>blog post</a></strong></h4>
        //   <ul><li>CHR-9416 Updating Chromium…</li>…</ul>
        // (captured verbatim 2026-08-16). The separator is an HTML-entity en dash,
        // not a hyphen, and the trailing "blog post" link sits INSIDE the
        // `<strong>` — both are why the pattern stops at the date instead of
        // matching to `</strong>`.
        //
        // `{major}`, not `{version}`: the page covers a whole major line, and
        // Opera ships a new major every few weeks, so a fixed URL would quietly
        // stop covering the installed build. `source` is one fixed major's page,
        // used only if no version is ever supplied.
        //
        // The page also carries developer/beta builds of the same major (the
        // `…5960.0` shapes). That is fine and deliberate: entries are listed
        // newest-first and the workbench shows the ones at the top; pinning to a
        // single build would need a per-build page, which Opera doesn't publish.
        ChangelogRecipe(
            bundleID: "com.operasoftware.Opera",
            source: URL(string: "https://blogs.opera.com/desktop/changelog-for-134/")!,
            entryPattern:
                #"<h4[^>]*>\s*<strong>\s*(?<version>[0-9]+(?:\.[0-9]+)+)\s*(?:&#8211;|–|-)\s*"#
                + #"(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})[^<]*(?:<a[^>]*>[^<]*</a>)?\s*</strong>\s*</h4>"#
                + #"\s*(?<body><ul>.*?</ul>)"#,
            itemPatterns: [#"<li>(?<item>.*?)</li>"#],
            channel: .stable,
            sourceTemplate: "https://blogs.opera.com/desktop/changelog-for-{major}/"),
        ])
}
