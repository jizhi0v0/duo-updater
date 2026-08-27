# 微信开发者工具 (WeChat DevTools)

> 审计 2026-08-18 · 状态：**已接入**（三渠道检测 + 一键 pkg + changelog）
> 真实包验证记录见 [`application-test/records/com-tencent-wechatdevtools.md`](../../application-test/records/com-tencent-wechatdevtools.md)
>
> duo-updater 内部按 **`com.tencent.wechatdevtools`**（pkg 声明的 id）登记这个 app，
> 不是 Info.plist 里那个 `com.github.Electron`——见下面「2.02 换成 Electron」。

## 基本信息

- 已安装：`/Applications/wechatwebdevtools.app` — **2.01.2510290**（nw.js 版）
  - Bundle ID: `com.tencent.webplusdevtools`
  - Team ID: `FN2V63AD2J`（Developer ID Application: Tencent Technology (Shanghai)）
- 自更新机制：应用内提示 + 官网下载安装包（无 Sparkle，无 `SUFeedURL`）
- 分发形态：官网 pkg / dmg（macOS arm64 + x64），无 Homebrew cask、无 MAS、无 GitHub

## ⚠️ 2.02 换成 Electron，本地身份全变（实测 3 个真包）

2.02 是 nw.js → Electron 的重写，**厂商没有改 Electron 的默认 Info.plist**：

| 字段 | 2.01（已装） | 2.02（三个渠道的 pkg payload 都一样） |
|------|--------------|-----------------------------------|
| `CFBundleIdentifier` | `com.tencent.webplusdevtools` | **`com.github.Electron`** |
| `CFBundleShortVersionString` | `2.01.2510290` | **`36.6.0`**（Electron 版本，不是工具版本） |
| `CFBundleVersion` | `4240.111` | `36.6.0` |
| `CFBundleName` | `wechatwebdevtools` | `wechatwebdevtools` |
| 主二进制 codesign Identifier | `com.tencent.webplusdevtools` | `com.github.Electron`（Team 仍是 FN2V63AD2J） |

pkg 的 `PackageInfo` 三个渠道同为 `identifier="com.tencent.wechatdevtools"`；`postinstall`
只建 `/usr/local/bin/wechatide` 软链，**不改写 Info.plist** —— 所以装完磁盘上就是这个样子。

后果：装了 2.02 之后 `AppScanner` 看到的是 `com.github.Electron` + `36.6.0`，
既没法按 bundle id 命中 recipe（这 id 是所有没改 plist 的 Electron app 的公共默认值），
也没法拿 `36.6.0` 跟 `2.02.x` 比版本。**必须在 scanner 层读别的文件才能得到真身份。**

## 真版本 / 真渠道在哪（实测 4 个 bundle）

| 版本 | 文件 | `version` | `versionType` | `window.title` |
|------|------|-----------|---------------|----------------|
| 2.01 已装 | `Contents/Resources/package.nw/package.json` | 2.01.2510290 | `0` | 微信开发者工具 Stable v2.01.2510290 |
| 2.02 RC | `Contents/Resources/app.asar.unpacked/package.json` | 2.02.2608031 | `1` | 微信开发者工具 **RC** v2.02.2608031 |
| 2.02 Stable | 同上 | 2.02.2608040 | `0` | 微信开发者工具 **Stable** v2.02.2608040 |
| 2.02 Nightly | 同上 | 2.02.2608182 | `2` | 微信开发者工具 **Nightly** v2.02.2608182 |

→ `versionType`: **0=stable / 1=rc(预发布) / 2=nightly(开发版)**，
`window.title` 里的 Stable/RC/Nightly 是同一信息的冗余备份。
这是 Mozilla `RemotingName` 的同构做法：渠道烤进 bundle 内一个不用启动就能读的文件。

## 版本端点（官方文档站自己在用，无鉴权，JSON）

文档站 `devtools/log.html` 是 Vue SPA，`DevToolsLog` 组件从这个 base 拉数据：

```
https://devtools.wxqcloud.qq.com.cn/WechatWebDev/nightly/versions/
├── config.json                      # 每渠道最新版本 + 三平台下载直链
├── history_{stable,rc,nightly}.json # 该渠道全部历史版本（新→旧），带 log_file
└── logs/{stable,rc,nightly}_v<版本>.json  # 单版本 changelog（结构化 categories）
```

实测 `config.json` 的 `channels[]`（2026-08-18）：

| id | version | macOS ARM64 下载 |
|----|---------|-----------------|
| `stable` | 2.02.2608040 | `.../release/be1ec64.../wechat_devtools_2.02.2608040_darwin_arm64.pkg` |
| `rc` | 2.02.2608031 | `.../release/be1ec64.../wechat_devtools_2.02.2608031_darwin_arm64.pkg` |
| `nightly` | 2.02.2608182 | `.../nightly/electron-36.6.0/wechat_devtools_2.02.2608182_darwin_arm64.pkg` |
| `nightly-old` | 2.01.2602282 | 旧 nw.js 轨，dldir1.qq.com，已停更 |

版本串与 app 内 `package.json` 的 `version` **同构**（`2.02.2608040` ↔ `2.02.2608040`），
不存在 Office/OneDrive 那种 build-vs-marketing 错位。

> 官网那个老的 `servicewechat.com/wxa-dev-logic/download_redirect?...&version_type=N`
> 端点**实测忽略 `version_type`**：0/1/2 一律 302 到 stable 的 dmg。不能用来分渠道。

## Changelog

- 来源：`logs/<channel>_v<version>.json` — 结构化 JSON（`categories[].items[]`，带 Fix/Feature tag）
- 跟随 channel：**是**，三个渠道各有独立日志
- 页面锚点：`log.html#stable-2.02.2608040` / `#rc-…` / `#nightly-…`（前端 hash 路由，非 HTML 锚点）
- 适配：走 `structuredFormat` 路径（Warp 的 `channel_versions.json` 是既有范式）

## 一键安装可行性

- 格式：**pkg**（arm64 / x64 各一份），三渠道同构
- 签名：`Developer ID Installer: Tencent Technology (Shanghai) Co., Ltd (FN2V63AD2J)`，
  三个包**全部通过公证**（`pkgutil --check-signature` 实测）
- Team ID 与已装 2.01 的 App 签名一致（FN2V63AD2J）→ 过 Team 闸
- 无 WAF / 无 Referer 门（直链 302 可下）

## 覆盖矩阵

> ✓ 已接入 ○ 可接入(未实现) ✗ 不可行 — 不适用

|          | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|----------|---------|----------|-----|--------|-------------|
| stable   | —       | —        | —   | —      | ✓ (一键 pkg) |
| rc       | —       | —        | —   | —      | ✓ (一键 pkg) |
| nightly  | —       | —        | —   | —      | ✓ (一键 pkg) |

当前生效源：**VendorProbe**（`config.json`，三渠道共用一个端点）

## Channel 详情

| Channel | 磁盘 bundle ID | 登记 ID | 检测信号 | 门控方式 | 状态 |
|---------|---------------|---------|---------|---------|------|
| stable | 2.01 `com.tencent.webplusdevtools` / 2.02 `com.github.Electron` | `com.tencent.wechatdevtools` | `package.json` → `versionType=0` | `"id": "stable"` 锚点 | ✓ |
| rc | 同上 | 同上 | `versionType=1` | `"id": "rc"` 锚点（+ recipeAnchor 证明） | ✓ |
| nightly | 同上 | 同上 | `versionType=2` | `"id": "nightly"` 锚点（+ artifact 证明 `/WechatWebDev/nightly/`） | ✓ |

`ReleaseChannel` 为此新增了 `.rc`（预发布版有自己的独立发布轨，不是 beta 上的一个 tag）。

## 实现落点

| 文件 | 改了什么 |
|------|---------|
| `Models/ReleaseChannel.swift` | 新增 `.rc`；刻意不进 `nonStable`/`channelWord`（"rc" 太短，泛匹配会误伤） |
| `Scan/AppScanner.swift` | `weChatDevToolsIdentity` 读 `package.json` → 真版本 + 渠道；bundle id 改写为 `com.tencent.wechatdevtools` |
| `Sources/VendorProbeRecipe.swift` | 三条 recipe，同一个 `config.json`，各自锚 `"id"`，一键 arm64 pkg |
| `Sources/ChannelArtifactProof.swift` | nightly = artifact 证明；rc = recipeAnchor（rc 的包和 stable 同目录同命名，URL 证不了） |
| `Sources/ChangelogRecipe.swift` + `StructuredChangelogDecoder.swift` | 新增 `.weChatDevToolsLog`，version-templated 到 `logs/<channel>_v<version>.json` |
| `CLI/Sources/DuoKit/Verify.swift` | changelog sweep 的版本按 (bundleID, channel) 取，不再按 bundleID 一把抓 |
| `application-test/.../channel-verify` | 支持 `.pkg` 输入；镜像 scanner 的身份改写 |

## 已知问题 / 风险

1. **锚点易碎**：三条 recipe 都锚在 `config.json` 的 `"id": "<channel>"` 上。厂商改这个
   文档结构 → 三条一起坏（`duo verify` 会抓到）。
2. **`com.github.Electron` 是公共默认 id**：改写的判据是 `package.json` 里的
   `appname == wechatwebdevtools`，别的 Electron app 落不进来（有回归测试钉住）。
3. **未知 `versionType` 一律不认**：不猜 stable，宁可显示 unknown——猜错就是跨渠道覆盖。
4. **nightly 一天一版**（history 里 507 条），开着会比较吵。
5. 2.02 仍未在本机安装，一键安装的**下载→签名闸→装机**全链路没跑过真机；检测/渠道/下载
   URL 已按真实包验证。

## 后续可做（未做）

- changelog 目前一次只渲染目标版本那一篇（厂商的 `history_<channel>.json` 只有指针没有
  正文，多版本要两跳，现有结构不支持）。
- x64 未覆盖：三条 recipe 都锚 `_darwin_arm64.pkg`（与仓库其余 recipe 的口径一致）。
