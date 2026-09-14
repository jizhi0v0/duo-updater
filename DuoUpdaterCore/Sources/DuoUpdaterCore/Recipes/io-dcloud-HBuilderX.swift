import Foundation

enum io_dcloud_HBuilderX {
    static let set = AppRecipeSet(
        family: "io-dcloud-HBuilderX",
        probes: [
        // History: docs/app-audits/io-dcloud-HBuilderX.md#历史与实测
        // HBuilderX (DCloud) — the vendor's own download-site config,
        // `release.json`. It carries BOTH the version and the installer `files[]`,
        // so one source drives detection and one-click alike — the same shape as
        // the alpha recipe below. (The changelog recipe no longer reads this file;
        // see ChangelogRecipe.)
        //
        // One-click: `files[]` lists the platforms in win/x64/arm64 order, so the
        // plain `mac_simple` x64 `.dmg` appears BEFORE `mac_simple_arm64`; the
        // `\.arm64\.dmg` anchor pins the Apple-silicon build regardless of order
        // (same guard as the alpha recipe). The dmg is notarized under Team
        // YQM5H857L5 (Digital Heaven / DCloud), same as the alpha, so it clears
        // VendorInstaller's signature gate. Apple-silicon only.
        //
        // The trailing `"` in versionPattern is load-bearing: it requires the
        // captured X.Y.Z to be immediately closed by a quote, so the config's own
        // 2-component `displayVersion` (e.g. "5.14") and any hypothetical suffixed
        // string can't be mis-captured. Don't drop it.
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderX",
            url: URL(string: "https://download1.dcloud.net.cn/hbuilderx/release.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+(?:\.[0-9]+){1,3})""#,
            changelogURL: URL(string: "https://hx.dcloud.net.cn/Tutorial/HistoryVersion"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download1\.dcloud\.net\.cn/download/HBuilderX\.[0-9.]+\.arm64\.dmg)"#),
                kind: .dmg)),

        // HBuilderX Alpha (DCloud) — the alpha track is a SEPARATE app: bundle id
        // io.dcloud.HBuilderXAlpha, installed as HBuilderX-Alpha.app, notarized
        // under the SAME Team ID (YQM5H857L5) as the stable build. Its detected
        // channel is .alpha (the "HBuilderX-Alpha" bundle name carries a standalone
        // "alpha" token), so this recipe MUST declare channel: .alpha — otherwise
        // VendorProbeSource's channel gate refuses it and the app stays "unknown".
        // Version comes from the download page's alpha config JSON, whose `version`
        // is the full pre-release string (e.g. "5.11.2026052520-alpha") and matches
        // the installed CFBundleShortVersionString exactly (VersionComparator tokenizes
        // the "-alpha" as a trailing text run, so equal strings compare equal and a
        // newer numeric build still wins). The trailing `"` after the capture keeps
        // it off the shorter `displayVersion` (e.g. "5.11") field.
        //
        // One-click: the SAME alpha.json that yields the version also lists the
        // installer under `files[]`. We grab the arm64 dmg explicitly — its
        // `mac_simple_arm64` entry appears AFTER the x64 `mac_simple` `.dmg`, so a
        // naive `\.dmg` `.bodyPattern` (first match) would pull the Intel build;
        // the `\.arm64\.dmg` anchor pins the right one regardless of order. The dmg
        // is notarized under the same Team ID YQM5H857L5 as the installed alpha, so
        // it clears VendorInstaller's signature gate. (Apple-silicon only, which is
        // every host DuoUpdater runs on: `App/project.yml`, `ARCHS: arm64`.)
        VendorProbeRecipe(
            bundleID: "io.dcloud.HBuilderXAlpha",
            url: URL(string: "https://download1.dcloud.net.cn/hbuilderx/alpha.json")!,
            mode: .responseBody,
            versionPattern: #""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+-alpha)""#,
            changelogURL: URL(string: "https://hx.dcloud.net.cn/Tutorial/HistoryVersion"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://download1\.dcloud\.net\.cn/download/HBuilderX\.[0-9.]+-alpha\.arm64\.dmg)"#),
                kind: .dmg),
            channel: .alpha),
        ],
        changelogs: [
        // HBuilderX (DCloud) — SINGLE-hop now, not two-stage: hx.dcloud.net.cn
        // serves a plain markdown changelog directly (200, no redirect, no
        // per-request tokenized CDN hop), so there is no index page to follow
        // and no `indexLinkPattern` here anymore (that's how the old
        // download1.dcloud.net.cn/release.json + HTML-detail-page two-stage
        // fetch worked; this recipe replaces it wholesale, not on top of it).
        // NOT `structuredFormat`: that decoder path (`StructuredChangelogDecoder`)
        // is for feeds too irregular for the regex extractor; this one is a
        // clean, uniform `## <version>` / `* <item>` document that the regex
        // path handles directly — and `structuredFormat` would also disable
        // `indexLinkPattern` handling in `ChangelogService`, which is irrelevant
        // here anyway since there's no second hop to disable.
        //
        // Format: e.g. `## 5.24.2026081301` heading (the build IS the version, no
        // separate date — same as the old HTML: there was never a `date` group
        // there either, so this is not a regression), then `* ` bullet lines,
        // e.g. `* 修复 ... [详情](https://issues.dcloud.net.cn/...)`. The
        // trailing `[详情](url)` / `[文档](url)` markdown link (occasionally two
        // in a row, occasionally followed by a bare `<url>` autolink) is stripped
        // by the item pattern rather than kept literal — flattening it to just
        // the link text (as `StructuredChangelogDecoder.bulletItems` does for
        // the structured path) isn't reachable from here without a much bigger
        // change to the regex extractor, so instead the pattern simply excludes
        // any *trailing* link syntax from the captured item. This covers the
        // overwhelming majority of lines (History has the counts); the rare line
        // where the link sits mid-sentence rather than at the end is left with its
        // `[text](url)` literal intact.
        //
        // Content scope: this md endpoint covers only the HBuilder IDE itself —
        // the old HTML detail page's other module sections (uni-app x, uni-app,
        // uts插件, uniCloud, App插件) aren't in it. That's an intentional
        // narrowing (confirmed against the HTML: every md item matches an
        // HBuilder-section item in the HTML verbatim, including issue ids — it's
        // a subset, not a rewrite/summary), so fewer items per entry here vs.
        // before is expected, not a parsing regression.
        //
        // Version group has no `-alpha` suffix, matching only bare `X.Y.Z`
        // headings (the alpha recipe below requires the suffix) — moot in
        // practice since the two channels are served from separate documents,
        // but kept for the same belt-and-suspenders reason the old HTML regexes
        // did.
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderX",
            source: URL(
                string: "https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_release.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+)\n"#
                + #"(?<body>.*?)"#
                + #"(?=\n## |$)"#,
            itemPatterns: [
                #"(?:^|\n)[ \t]*\*[ \t]+(?<item>[^\n]+?)(?:\s*\[[^\]\n]*\]\([^)\n]*\))*(?:\s*<[^>\n]*>)?(?=\n|$)"#
            ],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            // The doc is a years-long cumulative list (History has its length);
            // cap to the recent handful, same as before.
            maxEntries: 10,
            minItemLength: 4),

        // HBuilderX Alpha (DCloud) — the alpha is a SEPARATE app (bundle id
        // io.dcloud.HBuilderXAlpha, ships as HBuilderX-Alpha.app), so it needs its
        // own recipe; the stable io.dcloud.HBuilderX one never matches it. Same
        // single-hop markdown shape as stable, reading the alpha document
        // instead, whose version headings all carry an "-alpha" suffix
        // (e.g. 5.23.2026080313-alpha) — the version group requires it, so a stray
        // stable heading could never be mis-captured here. See the stable
        // recipe above for the full rationale (single-hop rewrite, why not
        // `structuredFormat`, link-stripping, and the HBuilder-IDE-only scope).
        ChangelogRecipe(
            bundleID: "io.dcloud.HBuilderXAlpha",
            source: URL(
                string: "https://hx.dcloud.net.cn/zh-cn/Tutorial/changelog/ReleaseNote_alpha.md")!,
            entryPattern:
                #"## (?<version>[0-9]+\.[0-9]+\.[0-9]+-alpha)\n"#
                + #"(?<body>.*?)"#
                + #"(?=\n## |$)"#,
            itemPatterns: [
                #"(?:^|\n)[ \t]*\*[ \t]+(?<item>[^\n]+?)(?:\s*\[[^\]\n]*\]\([^)\n]*\))*(?:\s*<[^>\n]*>)?(?=\n|$)"#
            ],
            stripTags: false,
            decodeEntities: false,
            markdownSource: true,
            // Same cap as stable (History has the alpha document's length).
            maxEntries: 10,
            minItemLength: 4),
        ],
        channelProofs: [
        ChannelProofKey("io.dcloud.HBuilderXAlpha", .alpha): .artifact(#"-alpha\."#),
        ])
}
