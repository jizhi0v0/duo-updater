import Foundation

enum com_tencent_wechatdevtools {
    static let set = AppRecipeSet(
        family: "com-tencent-wechatdevtools",
        probes: [
        // History: docs/app-audits/com-tencent-wechatdevtools.md#历史与实测
        // 微信开发者工具 (WeChat DevTools) — Tencent's mini-program IDE, three
        // parallel channels: 稳定版 Stable, 预发布版 RC, 开发版 Nightly. All three are
        // the SAME install (one bundle, one app name), and since the 2.02 Electron
        // rewrite they all report `com.github.Electron` / `36.6.0` in Info.plist —
        // the channel AND the real version come from the app's own `package.json`
        // instead, and `AppScanner` re-files the install under the canonical
        // `com.tencent.wechatdevtools` these recipes key on. See
        // `AppScanner.weChatDevToolsIdentity`.
        //
        // ONE endpoint serves all three channels: `config.json` is what the official
        // docs site's own changelog page (`devtools/log.html`, a Vue SPA) reads to
        // render its download buttons — `channels[]` with `id` / `version` / macOS
        // `downloads[]`. Each recipe anchors on its own `"id": "<channel>"` and takes
        // the nearest following `version` and arm64 pkg URL, so a channel can never
        // read a sibling's build. Nightly's anchor is exact-quoted for a second
        // reason: the document also carries a `"nightly-old"` entry (the retired
        // NW.js 2.01 train), and an unanchored `nightly` prefix would match it.
        //
        // NOT the old `servicewechat.com/wxa-dev-logic/download_redirect?…&
        // version_type=N` endpoint: when checked (2026-08-18) it ignored
        // `version_type` entirely and 302'd all three values to the same Stable
        // dmg.
        //
        // One-click: the arm64 `.pkg`, `Developer ID Installer: Tencent Technology
        // (Shanghai) Co., Ltd (FN2V63AD2J)`, notarized on all three channels
        // (checked with `pkgutil --check-signature` on 2.02.2608031 / 2608040 /
        // 2608182) — same Team as the installed app, so the signature gate holds.
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"stable"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#stable"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"stable"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .stable),
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"rc"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#rc"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"rc"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .rc),
        VendorProbeRecipe(
            bundleID: "com.tencent.wechatdevtools",
            url: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .responseBody,
            versionPattern: #""id":\s*"nightly"[\s\S]*?"version":\s*"([0-9]+(?:\.[0-9]+)+)""#,
            downloadURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/download.html"),
            changelogURL: URL(string: "https://developers.weixin.qq.com/miniprogram/dev/devtools/log.html#nightly"),
            install: VendorInstallSpec(
                urlSource: .bodyPattern(
                    #""id":\s*"nightly"[\s\S]*?"url":\s*"(https://[^"]+_darwin_arm64\.pkg)""#),
                kind: .pkg),
            channel: .nightly),
        ],
        changelogs: [
        // 微信开发者工具 (WeChat DevTools) — three channels under one (synthesized)
        // bundle id, each with its own notes train, so one recipe per channel keyed
        // by `channel`; `AppScanner` reads the install's channel out of the app's own
        // `package.json` (see `weChatDevToolsIdentity`) and
        // `recipe(forBundleID:channel:)` routes to the matching train.
        //
        // Version-templated, like Thunderbird: the vendor publishes ONE document per
        // release (`logs/<channel>_v<version>.json`) and no "latest" alias, so the
        // target version is substituted at load time and the notes on screen are
        // always the build being offered. The docs page (`log.html#stable-<version>`)
        // renders these very files — it's a Vue SPA reading them over fetch, so the
        // JSON is the source and the page is the rendering, not the other way round.
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .stable,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/stable_v{version}.json",
            structuredFormat: .weChatDevToolsLog),
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .rc,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/rc_v{version}.json",
            structuredFormat: .weChatDevToolsLog),
        ChangelogRecipe(
            bundleID: "com.tencent.wechatdevtools",
            source: URL(string: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/config.json")!,
            mode: .json,
            channel: .nightly,
            sourceTemplate: "https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/logs/nightly_v{version}.json",
            structuredFormat: .weChatDevToolsLog),
        ],
        channelProofs: [
        // MARK: WeChat DevTools (微信开发者工具)
        // Nightly builds live under their own CDN prefix (`/WechatWebDev/nightly/…`)
        // while Stable and RC are both served from `/WechatWebDev/release/<hash>/`,
        // so only Nightly can be proven from the URL. RC's artifact is byte-for-byte
        // shaped like Stable's — same host, same directory, same filename template,
        // differing only in the version — so its proof is the anchor instead: the
        // recipe reads the `"id": "rc"` block of the vendor's own `config.json`, and
        // if that anchor ever stops being there the recipe would start reading
        // whichever channel `config.json` lists first (Stable).
        ChannelProofKey("com.tencent.wechatdevtools", .nightly): .artifact(#"/WechatWebDev/nightly/"#),
        // Named on BOTH halves, which is what issue #110 was about. The token sits
        // in `versionPattern` and in the install `bodyPattern`, and matching the
        // joined surface passed on either — so if the install regex alone were
        // rewritten (the vendor renames the block, someone retypes it), the version
        // pattern would keep this green while the install fell back to whichever
        // channel `config.json` lists first. Which is Stable, into an RC install,
        // through every gate we have. Requiring both means the half that picks the
        // artifact is checked as the half that picks the artifact.
        ChannelProofKey("com.tencent.wechatdevtools", .rc):
            .recipeAnchor(#""id":.*"rc""#, in: ["versionPattern", "install"]),
        ])
}
