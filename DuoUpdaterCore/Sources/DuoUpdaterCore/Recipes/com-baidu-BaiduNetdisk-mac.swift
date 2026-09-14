import Foundation

enum com_baidu_BaiduNetdisk_mac {
    static let set = AppRecipeSet(
        family: "com-baidu-BaiduNetdisk-mac",
        probes: [
        // History: docs/app-audits/com-baidu-BaiduNetdisk-mac.md#历史与实测
        // 百度网盘 (Baidu Netdisk) — reads the endpoint the vendor's own download
        // page is built from: `pan.baidu.com/disk/cmsdata?do=client` answers a small
        // JSON with one object per product line (`android`, `guanjia` = the Windows
        // client, `linux`, `mac`, `tv`, `genflow-pro-pc-mac`, …), each carrying that
        // line's version, its architecture URLs and a publish stamp. It answers
        // anonymously — no cookie, no Referer, the browser-like default UA is fine.
        //
        // Nothing standard can cover this app. It ships `Squirrel.framework` and an
        // electron-updater `Contents/Resources/app-update.yml` naming
        // `https://netdisk-pc.cdn.bcebos.com/update/`, but that feed is DEAD:
        // `latest-mac.yml`, `latest-mac-arm64.yml` and the directory itself all 404.
        // The updater that actually runs is `libkernel.dylib`'s
        // `http://update.pan.baidu.com/autoupdate`, which answers 200 with a
        // ZERO-BYTE body to every request we can form — its parameters are not in
        // the clear, and it is plain HTTP besides. There is no Sparkle appcast, and
        // the Homebrew cask (`baidunetdisk`) cannot apply either: it is
        // `auto_updates true`, which `HomebrewCaskSource` declines by design, and
        // that source only adopts a copy brew itself installed.
        //
        // ANCHORING — the body carries several `…_arm64.dmg` URLs and only one is
        // this app. `MACguanjia` (the Netdisk Mac client) sits beside
        // `MACGenFlowPro` (库库GenFlow, a different Baidu product on the same CDN),
        // and the netdisk entry itself publishes x64 / arm64 / universal side by
        // side. So both patterns pin the product path AND the architecture: a bare
        // `_arm64\.dmg` can match another product's dmg (e.g. `KukuAI_…_arm64.dmg`)
        // first.
        //
        // The version pattern uses a BACKREFERENCE so the directory version and the
        // filename version have to agree — the version this reports is then, by
        // construction, the version of the file the install spec downloads. A
        // mismatch degrades to "unknown", which is the safe direction.
        //
        // One-click: the resolved `BaiduNetdisk_mac_<ver>_arm64.dmg` holds
        // `BaiduNetdisk_mac.app`, bundle id `com.baidu.BaiduNetdisk-mac`, Team
        // `738UU3Y57V`, notarized (History has the verification). The install
        // source must stay `.bodyPattern`: that CDN
        // answers **405 Method Not Allowed** to HEAD, so a `.redirect` source could
        // not resolve it at all.
        //
        // FROZEN-MARKETING GRANULARITY, stated rather than assumed: the feed
        // exposes only a marketing version (e.g. `8.7.9`) while the bundle also carries a
        // build (e.g. `CFBundleVersion` 473) the feed never mentions. `VersionComparator`
        // ties on marketing, finds no remote build, and answers "not newer" — so a
        // build-only respin is invisible here, never a phantom update. Baidu's mac
        // line does move its marketing version (History has the versions observed),
        // so this is a granularity limit, not a
        // dead discriminator.
        //
        // No `publishedAtPattern`: `publish` looks like `"2026-08-28 14:39:00"` —
        // space-separated and zone-less, a shape `ReleaseDate` does not parse, so
        // the pattern would silently yield nothing. It is Asia/Shanghai (that stamp
        // is two minutes before the artifact's own `Last-Modified: Fri, 28 Aug 2026
        // 06:41:09 GMT`), exactly the assumption `ReleaseDate`'s zone-less branch
        // warns about — reading it as UTC would place every Baidu release eight
        // hours early in the timeline.
        //
        // `changelogURL` is the vendor's own 版本更新 page, which has a Mac版 tab.
        // Note the page is a JS shell — its eight `<section>`s ship EMPTY and are
        // filled from `/disk/cmsdata?platform=mac&…`, so it is only good as the
        // human-facing fallback; the parsed notes come from a `ChangelogRecipe`
        // reading that same endpoint (the `ChangelogRecipe` below in this file). The
        // `feature_tips` field on THIS response is empty for `mac` and is not it.
        VendorProbeRecipe(
            bundleID: "com.baidu.BaiduNetdisk-mac",
            url: URL(string: "https://pan.baidu.com/disk/cmsdata?do=client")!,
            mode: .responseBody,
            versionPattern:
                #"/MACguanjia/([0-9]+(?:\.[0-9]+)+)/BaiduNetdisk_mac_\1_arm64\.dmg"#,
            // The probe URL is a JSON API, so it must not be what a "download page"
            // link opens; pan.baidu.com/download is the product's own page.
            downloadURL: URL(string: "https://pan.baidu.com/download"),
            changelogURL: URL(string: "https://pan.baidu.com/disk/version"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #"(https://pkg-ant\.baidu\.com/issue/netdisk/MACguanjia/[0-9][^"]*/BaiduNetdisk_mac_[0-9][^"]*_arm64\.dmg)"#),
                kind: .dmg)),
        ],
        changelogs: [
        // 百度网盘 — the notes ARE published, just not anywhere a person would
        // look: `pan.baidu.com/disk/version` ("版本更新") renders eight empty
        // `<section>`s and fills the Mac版 tab from JS, so the page's own markup
        // carries no release note at all. `changelog.js` shows what it asks for —
        // `/disk/cmsdata?platform=<tab>&page=<n>&num=<n>` — which is the same
        // `/disk/cmsdata` endpoint the version probe reads, on its other calling
        // convention. This recipe reads that endpoint directly; the human page is
        // what the `VendorProbeRecipe` above in this file points `changelogURL` at for
        // the fallback.
        //
        // `num=40` matches `maxEntries`, so the request carries 40 releases rather
        // than the whole list. Newest-first, so no `newestLast`.
        //
        // Entry shape, e.g. (verbatim, compact — the vendor emits no spaces):
        //   {"detail":[{"more":["【团队空间】…"],"stable":true,"title":"百度网盘全新升级"}],
        //    "publish":"2026-08-28 14:39:00","size":"444.2M","system":"Mac OS X 10.13+",
        //    "title":"百度网盘Mac电脑客户端V8.7.9","url":"…_x64.dmg","url_1":"…_arm64.dmg",
        //    "version":"百度网盘Mac电脑客户端V8.7.9"}
        //
        // Three shapes in the live data the patterns are built around, not guessed:
        //
        //  1. **`more` is empty for some releases, and
        //     the note moves into the detail object's `title`.** Those are not
        //     note-less releases — e.g. 4.54.9's title is
        //     "百度网盘优化了一些已知的体验问题，欢迎升级体验~", the whole note.
        //     So `body` captures the WHOLE detail object and the item patterns are
        //     ordered: bullets first, the title only when there are none.
        //     Capturing just the `more` array would not have shown those as blank
        //     entries — `ChangelogExtractor` drops an entry whose item patterns
        //     yield nothing (`guard !noteHits.isEmpty`), so those releases
        //     would be MISSING from the changelog entirely, with no blank row to
        //     notice. The fallback is what keeps them.
        //  2. **The key order inside `detail` is not fixed, and neither is the key
        //     set**: `more` and `title` are on every entry, `stable` and
        //     `feature_tips` only on some. So nothing may assume `more` comes first,
        //     and `feature_tips` is common rather than a curiosity.
        //     It is a plain STRING wherever it appears (`"mac版可以xxx啦"`, vendor filler,
        //     never a release note), which is the only reason the punctuation
        //     anchoring below declines it — a value preceded by `:`. Were the
        //     vendor to make it an array, its elements would start rendering as
        //     notes.
        //  3. **The version string gained a space at some point**: recent releases
        //     say e.g. `百度网盘Mac电脑客户端V8.7.9`, older ones `百度网盘Mac电脑客户端 V4.15.0`,
        //     and the oldest drop the prose entirely (`Mac版 V3.9.5`). Anchoring on
        //     `V` + digits rather than on the label survives all three.
        //
        // The first item pattern reads a JSON array element by its PUNCTUATION —
        // a string opened by `[` or `,` and closed by `,` or `]` — which is what
        // separates `more`'s elements from the keys and from `title`'s value in
        // the same object (a key is followed by `:`, a value preceded by one).
        //
        // Its body is `(?:[^"\\]|\\.)+` rather than `[^"]+` so a note containing an
        // escaped quote stays one element. `[^"]+` stops at the backslash's quote
        // and the element is then SILENTLY DROPPED, not reported: the array's other
        // elements still match, so `firstNonEmptyItemHits` is satisfied, never tries
        // the fallback, and the entry renders with fewer notes than the vendor
        // published. No live item carries a quote, which is
        // exactly why this would have gone unnoticed; the recipe is `.json` because
        // this feed's strings are escaped, so the item pattern has to agree.
        ChangelogRecipe(
            bundleID: "com.baidu.BaiduNetdisk-mac",
            source: URL(string: "https://pan.baidu.com/disk/cmsdata?platform=mac&page=1&num=40")!,
            entryPattern:
                #"\{"detail":\[\{(?<body>.*?)\}\],"publish":"(?<date>[^"]+)""#
                + #".*?"version":"[^"]*?V(?<version>[0-9]+(?:\.[0-9]+)*)""#,
            itemPatterns: [
                #"[\[,]"(?<item>(?:[^"\\]|\\.)+)"(?=[,\]])"#,
                #""title":"(?<item>[^"]+)""#,
            ],
            mode: .json,
            maxEntries: 40),
        ])
}
