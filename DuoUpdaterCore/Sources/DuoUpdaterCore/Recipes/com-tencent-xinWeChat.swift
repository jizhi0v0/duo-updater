import Foundation

enum com_tencent_xinWeChat {
    static let set = AppRecipeSet(
        family: "com-tencent-xinWeChat",
        probes: [
        // History: docs/app-audits/com-tencent-xinWeChat.md#历史与实测
        // WeChat (微信, 官网版) — Tencent's flagship messenger, installed from the
        // official site (Developer ID, no MAS receipt, no SUFeedURL in Info.plist).
        // No standard source resolves it: the Homebrew cask is `auto_updates: true`
        // (fall-through), MAS is a separate copy, and WeChat's bundled Sparkle sets
        // its feed URL at runtime. But the appcast IS public — the same XML the cask's
        // livecheck reads. We probe it directly.
        //
        // VERSION SCHEME: compare the MARKETING version, the way users (and the
        // official site) track WeChat — e.g. "4.1.10". The feed's
        // `sparkle:shortVersionString` is a 4-segment `4.1.10.53`, but the
        // installed bundle STRIPS the 4th segment and reports
        // `CFBundleShortVersionString = 4.1.10`; the official changelog and
        // download both say "4.1.10". So the pattern captures only the first THREE
        // segments → "4.1.10", which equals the installed marketing version (up to
        // date) and bumps cleanly to "4.1.11" when that ships. We deliberately do
        // NOT compare the `sparkle:version` build (e.g. 268853 vs 268851): WeChat
        // re-spins builds inside one marketing version, and surfacing "→ 268853" is
        // both a meaningless number and a non-update in the user's eyes. The
        // pattern matches both the element and the enclosure-attribute form of
        // `shortVersionString`; selectHighest takes the newest across all items (it
        // matches nothing but app versions).
        //
        // One-click dmg: the enclosure is on Tencent's own CDN, same channel, signed
        // by the same Team `5A4RE8SF68` (Tencent Mobile International) as the installed
        // app — the VendorInstaller signature gate enforces it. `.bodyPattern` takes
        // the FIRST `<enclosure>` in whatever text it is handed; its `?t=<token>`
        // query is read fresh from each probe's feed.
        //
        // `entryStartPattern` is what makes that safe. Without it the two readers
        // select INDEPENDENTLY over the whole body — the version is the highest
        // found anywhere (`selectHighest`), the download URL is the first enclosure
        // found anywhere — and this feed carries items spanning several generations
        // (History has the count and range read live 2026-08-30). They coincide
        // only because Tencent happens to list newest first; a reordering that put
        // the legacy `WeChatMac_10_15.dmg` item first would report the newest
        // version while installing a 3.8 build, silently. That is the #76 shape
        // exactly, and an ordering argument is not a guard. `<item>` is never
        // nested in the body, so it slices between releases and not inside one.
        //
        // Tencent also buckets ONE version by OS across three of those items
        // (`min12.0` with no max, `min12.0/max14.3`, and `min14.3/max15.0` which
        // carries NO enclosure at all and tells the user to visit the website).
        // Nothing here reads those bounds — `VendorProbeSource` honours a bound
        // only where the recipe declares `minimum`/`maximumSystemVersionPattern`
        // (#634), and this recipe deliberately does not: the window is applied
        // to the entry already picked, and picking the first-listed capped
        // bucket would refuse the whole probe. What keeps this correct is the tie-break in
        // `highestVersionEntry`: `best` is replaced only on a STRICTLY newer
        // version, so among the three items that all read the same version the
        // FIRST wins — the no-max bucket carrying the universal dmg. If Tencent
        // ever reorders those three, the enclosure-less bucket could win and
        // one-click would go quiet: visible in the nightly sweep, and strictly
        // better than the silent wrong-artifact install the un-sliced version risks.
        //
        // The pattern is `<item[\s>]`, not the literal `<item>` the feed uses
        // today, because the literal form fails OPEN in the worst way: an
        // attribute on the tag (`<item id="269579">`) would match zero times,
        // `highestVersionEntry` would return nil for having fewer than two
        // entries, and every reader would revert to whole-body first-match —
        // this bug, back, behind nothing but a `entryPatternNoMatch` warning
        // nobody reads until the nightly sweep. The character class costs
        // nothing and cannot match `<items>`.
        //
        // One property worth knowing before reading a sweep report: slicing
        // needs at least TWO matches to mean anything, so if Tencent ever trims
        // the feed to a single item this recipe still answers correctly (the
        // whole body IS that item) while reporting `entryPatternNoMatch`. That
        // warning would be a false alarm, not a regression. Structured notes come from a
        // ChangelogRecipe over the official per-version updates page; changelogURL is
        // the webview fallback.
        VendorProbeRecipe(
            bundleID: "com.tencent.xinWeChat",
            url: URL(string: "https://dldir1.qq.com/weixin/mac/mac-release.xml")!,
            mode: .responseBody,
            versionPattern: #"sparkle:shortVersionString[>="]+\s*(\d+\.\d+\.\d+)"#,
            downloadURL: URL(string: "https://mac.weixin.qq.com/"),
            changelogURL: URL(string: "https://weixin.qq.com/updates?platform=mac"),
            selectHighest: true,
            entryStartPattern: #"<item[\s>]"#,
            install: VendorInstallSpec(
                urlSource: .bodyPattern(#"<enclosure url="(https://[^"]+\.dmg[^"]*)""#),
                kind: .dmg)),
        ],
        changelogs: [
        // WeChat (微信, 官网版) — the official updates site publishes ONE page per
        // Mac version at `weixin.qq.com/updates?platform=mac&version=<X.Y.Z>`, with the
        // exact labels/dates the user sees in-app (4.1.10, 4.1.9, …). The Sparkle feed
        // the VendorProbe reads is NOT a usable changelog source: it carries 4-segment
        // labels (4.1.10.53) and a sparse, gap-ridden history. So this is a templated
        // recipe (like Thunderbird): `{version}` is the marketing version the probe
        // offers (or the installed one), substituted to fetch exactly that release's
        // page. It's a Nuxt SSR page but the notes are server-rendered: a `faq_title`
        // "微信 <ver> for Mac …", a `发布日期：<date>`, then the change lines as `<h4>`
        // inside `#page_center`. We bound `body` to that container so unrelated `<h4>`
        // (footer/marketing) can't leak in. A parse miss falls back to the webview
        // (the VendorProbe's changelogURL).
        ChangelogRecipe(
            bundleID: "com.tencent.xinWeChat",
            source: URL(string: "https://weixin.qq.com/updates?platform=mac")!,
            entryPattern:
                #"微信 (?<version>[0-9]+(?:\.[0-9]+)+) for Mac.*?"#
                + #"发布日期[：: ]*(?<date>[0-9-]+).*?"#
                + #"<div id="page_center"[^>]*>(?<body>.*?)</div>"#,
            itemPatterns: [
                // Notes carry a literal "- " bullet; drop it so the UI's own bullet
                // doesn't render as "• - …".
                #"<h4[^>]*>\s*-?\s*(?<item>.*?)</h4>"#,
            ],
            sourceTemplate: "https://weixin.qq.com/updates?platform=mac&version={version}",
            // Each release embeds one or more feature screenshots between the change
            // lines (res.wxqcloud.qq.com.cn / res.wx.qq.com); surface them inline.
            imagePattern: #"<img[^>]+src="(?<image>https?://[^"]+)""#),
        ])
}
