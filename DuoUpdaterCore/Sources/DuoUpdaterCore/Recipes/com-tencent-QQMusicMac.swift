import Foundation

enum com_tencent_QQMusicMac {
    static let set = AppRecipeSet(
        family: "com-tencent-QQMusicMac",
        probes: [
        // QQ音乐 (QQMusic Mac) — Tencent ships no Sparkle appcast and no public
        // version API; the client updates itself in-app. The one machine-readable
        // surface is the download page's own data file,
        // `y.qq.com/download/download.js`, a JSONP document
        // (`MusicJsonCallback({"data":[…]})`) with ONE OBJECT PER PLATFORM —
        // Windows, Mac, iPhone, Android, TV, 车载, HarmonyOS, and two sibling
        // Tencent products (腾讯视频 / QQ影音 / 电脑管家). The Homebrew cask is
        // `auto_updates`, so it is not a source here.
        //
        // The `y.qq.com/download/index.html` page carries NO notes of its own: it
        // is a JS shell that fetches this same file client-side (measured
        // 2026-08-29 — the served HTML does not contain any release-note string).
        // So the notes come from a `ChangelogRecipe` over this same URL, and
        // `changelogURL` points at that page only as the human-facing fallback.
        //
        // URL: every query parameter the site sends
        // (`cv`/`ct`/`format`/`platform`/`g_tk`/`jsonpCallback`/…) is INERT —
        // measured 2026-08-29, the bare path, the site's full query, and a minimal
        // query all return byte-identical bodies with identical `Last-Modified`
        // and `Cache-Control: max-age=600`, and the callback name is always
        // `MusicJsonCallback` regardless of `jsonpCallback`. So the bare path is
        // registered: fewer tokens to go stale, same answer.
        //
        // ANCHORING — the body holds TWO `"Ftype":2,"Ftitle":"Mac"` objects. `ID:2`
        // is the live client (11.8.1, 2026-08-03); `ID:15` is a 2020-era legacy
        // record still parked in the table (7.0.0, "QQ音乐Mac7.0全新改版", link
        // `QQMusicMac_Mgr.dmg`). Both patterns therefore key on the VERSIONED Mac
        // dmg filename `QQMusicMac<ver>Build<nn>.dmg` rather than on `Ftitle`, an
        // `ID`, or a `Fversion` label: the legacy entry's link has no version in it
        // (`QQMusicMac_Mgr`), so `QQMusicMac[0-9]` excludes it structurally, and
        // the Windows/Android/iOS links carry different filename stems. One match
        // each in the live body.
        //
        // FROZEN-MARKETING GRANULARITY, stated rather than assumed: the `Build01`
        // in the filename is the vendor's respin ordinal for that marketing
        // version, NOT the app's `CFBundleVersion` (the installed 11.8.1 reports
        // build `73276`). Comparing it as a build would be a cross-namespace
        // comparison, so this stays a marketing-only recipe (`versionIsBuild`
        // false): a same-marketing respin (11.8.1 Build01 → Build02) is invisible
        // here, never a phantom update. Tencent does move the marketing version
        // (the same body has Windows at 22.5.2 and iPhone at 20.7.5), so this is a
        // granularity limit, not a dead discriminator.
        //
        // No `publishedAtPattern`: the date lives inside `Fdesc` as
        // `发布时间：2026-08-03` — a bare calendar day with no time and no zone,
        // which `ReleaseDate` does not parse, so a pattern here would be a silent
        // no-op. (It is also the FIRST-match trap: the Windows object precedes Mac
        // in the body, so an unanchored date pattern would stamp the Mac release
        // with Windows' date.) The ChangelogRecipe shows the day verbatim, which
        // is display-only and where a zone-less day belongs.
        //
        // One-click verified 2026-08-29 by resolving and opening the artifact this
        // recipe builds: `Flink1` 302s to
        // `dldir.y.qq.com/…/QQMusicMac11.8.1Build01.dmg?sign=…` (the `sign` is
        // minted per request by the redirect; the one in the body is the redirect's
        // own token, read fresh from the live body at apply time). The 97 MB image
        // holds `QQMusic.app` AND NOTHING ELSE — no pkg, no daemon, no
        // LaunchAgents/LaunchDaemons/PrivilegedHelperTools sibling on this machine
        // — which is what makes `.dmg` (bundle swap only) the correct kind rather
        // than `.pkg`. Bundle id `com.tencent.QQMusicMac`, `CFBundleShortVersionString`
        // 11.8.1 / `CFBundleVersion` 73276 (identical to the installed copy), Team
        // `FN2V63AD2J` (Tencent Technology (Shanghai) Company Limited — the
        // installed copy's team, which the VendorInstaller signature gate enforces),
        // `spctl -a -t install` "Notarized Developer ID", `lipo -archs` x86_64 arm64.
        VendorProbeRecipe(
            bundleID: "com.tencent.QQMusicMac",
            url: URL(string: "https://y.qq.com/download/download.js")!,
            mode: .responseBody,
            versionPattern: #"QQMusicMac([0-9]+(?:\.[0-9]+)+)Build[0-9]+\.dmg"#,
            // The probe URL is a JSONP data file, so it must not be what a
            // "download page" link opens; y.qq.com/download is the product's page.
            downloadURL: URL(string: "https://y.qq.com/download/index.html"),
            changelogURL: URL(string: "https://y.qq.com/download/index.html"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://c\.y\.qq\.com/cgi-bin/file_redirect\.fcg\?[^"]*QQMusicMac[0-9][^"]*Build[0-9]+\.dmg[^"]*)"#),
                kind: .dmg)),
        ],
        changelogs: [
        // QQ音乐 (QQMusic Mac) — the vendor publishes release notes NOWHERE a
        // reader can reach: `y.qq.com/download/index.html` is a JS shell whose
        // served HTML contains no note text at all (measured 2026-08-29), and
        // there is no blog, no appcast and no per-version page. The notes exist
        // only as the `Fdesc` string of the Mac object inside the page's own JSONP
        // data file, which is also this app's `VendorProbeRecipe` endpoint.
        //
        // One entry, by construction: the file states only the CURRENT release per
        // platform, so there is no history to page through.
        //
        // The Mac object (verbatim, 2026-08-29):
        //   "ID":2,"Ftype":2,"Ftitle":"Mac","Fversion":"最新版:11.8.1",…,
        //   "Fdesc":"「AI声景疗愈」…开启\n|「AI伴听」…开启\n|「其他」其他体验优化\n|\n\n|发布时间：2026-08-03",
        //   "Flink1":"https://c.y.qq.com/…QQMusicMac11.8.1Build01.dmg&sign=…"
        // Note the separator is a JSON-escaped `\n` followed by a `|`, so on the
        // regex path every newline is the two characters `\` `n` — the item
        // pattern has to spell it `\\n`, and the trailing `\n|\n\n|` run before
        // 发布时间 has to be eaten by the entry pattern or it becomes a bullet.
        //
        // ANCHORING — the file holds TWO `"Ftitle":"Mac"` objects: the live client
        // (ID 2) and a 2020-era legacy record (ID 15, 7.0.0, "QQ音乐Mac7.0全新改版").
        // Without a discriminator the pane would list a six-year-old release under
        // its own version header. The entry pattern requires the object's own
        // `Flink1` to be a VERSIONED Mac dmg (`QQMusicMac<digit>`); the legacy
        // record links `QQMusicMac_Mgr.dmg`, so it is excluded structurally rather
        // than by an `ID` literal that a table edit could renumber. `[^{}]` between
        // fields is what keeps a lazy gap from wandering into the next platform's
        // object.
        //
        // The date is captured out of `Fdesc`'s own 发布时间 tail so it can only be
        // this entry's — it is display-only here, and `ReleaseDate` cannot parse a
        // bare zone-less day anyway (see the probe recipe's comment).
        //
        // ONE item pattern, not the usual redundant list: it already degenerates
        // correctly. `(?:^|\\n)` matches the start of the body, so a future `Fdesc`
        // with no separators at all yields the whole string as a single note rather
        // than nothing. A second pattern here could never fire.
        //
        // The item body is `(?:[^\\]|\\(?!n))+?`, not `[^\\]+?`: a note has to run
        // THROUGH an escaped quote (`\\"`) while still stopping at the `\\n`
        // separator. The plain negated class cannot tell the two apart — it stops
        // at every backslash, which drops the note carrying the quote instead of
        // splitting it (the extractor is satisfied by the OTHER notes matching, so
        // nothing reports the loss). No live note carries a quote today; the
        // regression test does.
        ChangelogRecipe(
            bundleID: "com.tencent.qqmusicmac",
            source: URL(string: "https://y.qq.com/download/download.js")!,
            entryPattern:
                #""Ftitle":"Mac"[^{}]*?"Fversion":"[^"]*?(?<version>[0-9]+(?:\.[0-9]+)+)""#
                + #"[^{}]*?"Fdesc":"(?<body>(?:[^"\\]|\\.)*?)(?:\\n\|?)*"#
                + #"发布时间[:：]\s*(?<date>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})"#
                + #"(?:[^"\\]|\\.)*"[^{}]*?"Flink1":"[^"]*QQMusicMac[0-9]"#,
            itemPatterns: [#"(?:^|\\n)\|?(?<item>(?:[^\\]|\\(?!n))+?)(?=\\n|$)"#],
            mode: .json,
            maxEntries: 1,
            minItemLength: 2),
        ])
}
