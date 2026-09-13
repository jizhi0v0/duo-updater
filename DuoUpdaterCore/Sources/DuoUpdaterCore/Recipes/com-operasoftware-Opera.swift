import Foundation

enum com_operasoftware_Opera {
    static let set = AppRecipeSet(
        family: "com-operasoftware-Opera",
        probes: [
        // MARK: - 2026-08-16 group D (directory indexes)
        //
        // All three below are the same shape: a vendor's plain Apache/MirrorBrain
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
        // the one just reported as available. `VendorInstallSpec.URLSource` has no
        // "take the true max of every match" mode — only first (`bodyPattern`/
        // `bodyTemplate`) or last (`bodyPatternLast`) — so none of it can be made
        // to agree with `selectHighest`'s numeric max safely. All three are
        // therefore detection-only, even though every one of them mounts to a
        // genuine, notarized, Developer-ID-signed app (verified below) — the
        // blocker is this URL-construction gap, not the artifact.

        // Opera — `get.geo.opera.com` is Opera's own CDN mirror index, one folder
        // per released version (`134.0.5954.56/`), each holding a `mac/` dir with
        // `Opera_<version>_Setup.dmg`. The `href="…/"` anchor matches nothing but
        // version folders on this page (checked: every 4-dot-separated number in
        // the raw body is inside an `href`, none appear elsewhere — no stray dates
        // or sizes share that shape here).
        //
        // VERSION SCHEME TRAP: verified 2026-08-16 by mounting
        // `Opera_134.0.5954.56_Setup.dmg` — it holds `Opera.app`, notarized
        // Developer ID (Team A2P9LX4JPN, "Opera Software AS"), spctl accepted. But
        // `CFBundleShortVersionString` is only `"134.0"` while `CFBundleVersion` is
        // `"134.0.5954.56"` — exactly what the folder name carries. Comparing the
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
            // ONE-CLICK via `.versionTemplate` — see LibreOffice below for why the
            // template must fill the RESOLVED version and not a first-match regex
            // on this alphabetically-sorted index.
            //
            // Despite the "Setup" in the filename this dmg is NOT a stub
            // downloader (the 1Password trap): verified 2026-08-16 by mounting
            // `Opera_134.0.5954.56_Setup.dmg` (260,530,261 B) — it carries
            // `Opera.app` itself, 560 MB on disk, com.operasoftware.Opera,
            // universal (x86_64 + arm64), Team A2P9LX4JPN (Opera Software AS),
            // notarized Developer ID, spctl accepted. Its `CFBundleVersion` is
            // `134.0.5954.56`, i.e. exactly the folder name this recipe compares,
            // which is what makes the template safe as well as the comparison.
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
        // stop covering the installed build. `source` is the current page, used
        // only if no version is ever supplied.
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
