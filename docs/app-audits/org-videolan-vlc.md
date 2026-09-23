# VLC

## 基本信息
- Bundle ID: `org.videolan.vlc`（stable / nightly **共享同一 id**）
- 已验证版本: stable 由 VendorProbe 覆盖；nightly `4.0.0-dev`（build `20260827-0413`，arm64）
- 自更新机制: 内嵌 Sparkle（`SUFeedURL`），但更新决策走本仓库的 VendorProbe recipe，不吃 vendor 自己的 appcast 选型逻辑

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查、**永久**不可行  — = 不适用

|             | Homebrew | VendorProbe |
|-------------|----------|-------------|
| **stable**  | (cask `vlc`) | ✓ 检测 + 一键（`org.videolan.vlc`，Team `75GAHG3SZQ`）|
| **nightly** | (cask `vlc@nightly`，Homebrew 已标记 deprecated，计划 2026-09-01 停用) | ○ 检测已可行（#93 已解决），尚未接 recipe；✗ 一键**永久**不可（未签名）|

当前生效源（stable）: **VendorProbe**，`update.videolan.org/vlc/sparkle/vlc-arm64.xml`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 本地渠道标记 | 签名 | 判定 |
|---------|-----------|----------|-------------|------|------|
| stable  | `org.videolan.vlc` | 共享 | — | Team `75GAHG3SZQ`，公证 | ✓ 已接入 |
| nightly | `org.videolan.vlc` | 共享 | 版本串带 `-dev`（`ReleaseChannel.detect()` 已识别，#93 已解决） | **未签名** | 检测已可行，尚未接 recipe；**一键永久不可**（见下）|

## 为什么 nightly 只能是 detection-only（issue #95）

来源：#95（2026-08-27 channel sweep §2c 之后单独立项），本次 PR 重新下载真机验证。

### 重新验证：签名（本次实测，非转抄 issue）

下载当日（2026-08-27）arm64 nightly `vlc-4.0.0-dev-arm64-54a50fd7.dmg`
（`https://artifacts.videolan.org/vlc/nightly-macos-arm64/20260827-0413/`），
SHA-512 与官方 `SHA512SUM` 逐字节核对一致，挂载后对 `VLC.app` 跑：

```
$ codesign -dv --verbose=4 VLC.app
Executable=…/VLC.app/Contents/MacOS/VLC
Identifier=VLC
Format=app bundle with Mach-O thin (arm64)
CodeDirectory v=20400 size=540 flags=0x20002(adhoc,linker-signed) hashes=14+0 location=embedded
…
Signature=adhoc
Info.plist=not bound
TeamIdentifier=not set
Sealed Resources=none
Internal requirements=none

$ spctl -a -vv VLC.app
VLC.app: code has no resources but signature indicates they must be present
```

`Signature=adhoc` / `TeamIdentifier=not set`：ad-hoc 签名，没有 Developer ID Team。
`VendorInstaller.applyVerified` 的 gate 2/3
（`SignatureVerifier.verifyCodeSignature` + `verifyTeamIdentifierMatch`，
`DuoUpdaterCore/Sources/DuoUpdaterCore/Install/VendorInstaller.swift`）要求下载物的
Team ID 与已装 app **完全一致**——nightly 的 "not set" 不可能等于 stable 的
`75GAHG3SZQ`，一键会在 gate 2/3 被拒。这一步与 stable 的一键路径无关，也不因
#93 已解决而改变：`detect()` 现在能认出 `-dev` 后缀，但**这条 gate 依然会拒**，
拒的位置停在「检测到了但装不上」——本 issue 存在的意义就是把这条提前写下来，
不要等到真的接了 install spec 才在运行时发现。

Homebrew 自己也独立标记了同一结论：`vlc@nightly` cask 被标 `Deprecated because it
does not pass the macOS Gatekeeper check!`，计划 2026-09-01 停用（本次核查
2026-08-27 的 cask 源码，供佐证，非本仓库验证的替代）。

### 松散尾 1 —— arm64 nightly 的 `SUFeedURL` 指向 `vlc-intel64.xml`：核实为真错

`VLC.app/Contents/Info.plist` 里：

```
$ /usr/libexec/PlistBuddy -c "Print :SUFeedURL" VLC.app/Contents/Info.plist
https://update.videolan.org/vlc/sparkle/vlc-intel64.xml
```

`lipo -info` 确认这不是 universal 构建，是**纯 arm64** 单架构二进制：

```
$ lipo -info VLC.app/Contents/MacOS/VLC
Non-fat file: …/VLC is architecture: arm64
```

排除了"vendor 就一份 feed 打进所有架构，反正是同一份 Info.plist 模板"的可能——因为
两份 feed 本身内容并不相同，实测两条 feed 各自 enclosure 都是按架构分列的：

```
$ curl -sL https://update.videolan.org/vlc/sparkle/vlc-arm64.xml   | grep -oE 'url="[^"]+"' | tail -3
url="http://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-arm64.dmg"
$ curl -sL https://update.videolan.org/vlc/sparkle/vlc-intel64.xml | grep -oE 'url="[^"]+"' | tail -3
url="http://get.videolan.org/vlc/3.0.23/macosx/vlc-3.0.23-intel64.dmg"
```

本仓库 stable 的 VendorProbe recipe 本身就是靠这个区分选的 `vlc-arm64.xml`
（`VendorProbeRecipe.swift`）。结论：**这是 vendor 的 nightly 打包脚本把错误的 feed
URL 烤进了 arm64 build 的 Info.plist，不是"一份 feed 服务所有架构"的正常做法**——
真错，不是设计。因为 nightly 本来就不可能一键，这个错本身对本仓库没有后果，只是把
issue 提的疑点坐实。

### 松散尾 2（不适用于 VLC，见 KeePassXC 那份文档）

VLC 没有这条——nightly 的 arm64/x86_64 dmg 是分开发布的两个文件
（`vlc-4.0.0-dev-arm64-*.dmg` / `vlc-4.0.0-dev-x86_64-*.dmg`，见
`artifacts.videolan.org/vlc/nightly-macos-{arm64,x86_64}/`），跟 KeePassXC snapshot
的单一 x86_64-only dmg是两码事。

## 结论

- **检测**：已解决（#93）。`detect()` 现在能从版本串里的 `-dev` 后缀识别 nightly，
  但仓库尚未为它接一条 VendorProbeRecipe。
- **一键**：**永远不做**。未签名，`VendorInstaller` 的 Team 闸必拒。如果有人
  想给 nightly 接 channel-gated recipe，**不要带 `install:`**——保持 detection-only，
  跟 LibreWolf（`net-librewolf-librewolf.md`）、Wispr Flow 同一模式。
- 详见 issue #95、`CHANNEL_COVERAGE_TODO.md` §2c。

## 建议下一步
1. 若决定接 nightly 检测（`detect()` 已支持 `-dev` 后缀，#93 已解决）：只加
   `channel: .dev`（或对应枚举）的 VendorProbeRecipe，**省略 `install:`**，
   `downloadURL` 指到 nightly 目录页而不是 dmg（对照
   `PageURLTests.detectionOnlyRecipesCarryAPage` 的约束）。
2. 不必现在做——这不是本 issue 的范围，本 issue 只是把"一键必拒"这条写下来存档。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-videolan-vlc.swift — ChangelogRecipe（两段式）

转引自 recipe 注释，未复测。整段原文；代码里 "(currently /vlc/releases/3.0.23.html)" 改成示例 "(e.g. …)"，原句没写日期，引入它的提交是 `2af36691`（2026-06-02）；其余原样。

VLC — two-stage. `source` is the newest-first releases index; the
`indexLinkPattern` follows its first per-version link (currently
/vlc/releases/3.0.23.html) to the detail page, which avoids version-pinning
*and* the merge trap: VLC folds 3.0.19/3.0.20 — and 3.0.22/3.0.23 — onto a
single page, so the page is not always named after the latest version;
following the real href is correct where templating a version would 404.
(The companion NEWS file at code.videolan.org is behind an Anubis
proof-of-work wall, so it can't be fetched — hence the marketing page.)
The detail page is mostly marketing, but the "X Fixes" section carries the
real changelog. Its heading reads "3.0.22/3.0.23 Fixes" (the slash form
lists the superseded build), so `(?:[\d.]+/)*` skips the leading versions
and captures the final one. The Fixes block shares a single <section> with
the "3.0 Highlights" / "3.0 Features" marketing lists, so the body lookahead
must stop at the next <h1> — bounding to </section> would swallow those
feature bullets. No per-entry date is printed.

复测 2026-09-14（13:59 UTC，只读 GET `www.videolan.org/vlc/releases/`）：第一个 per-version 链接仍是 `/vlc/releases/3.0.23.html`，其后是 `3.0.21.html`、`3.0.20.html`。

复测 2026-09-23（#812，只读 GET）：index 第一个链接变为 `/vlc/releases/3.0.24.html`；该页的发布块标题改成 `3.0.24 Highlights`（不再是 `X Fixes`），旧 pattern 因此 `noEntriesExtracted`。`3.0.23.html`（`3.0.22/3.0.23 Fixes`）、`3.0.21.html`/`3.0.20.html`（`3.0.19/3.0.20 Fixes`）、`3.0.18.html`（`3.0.18 Fixes`）仍是旧式标题。每页其后都跟着通用的 `3.0 Highlights` 营销标题，所以新 pattern 同时接受 `Fixes|Highlights`，并要求版本至少三段，避免把 `3.0` 当成一个发布。新 pattern（Python re.S 复算）在其中三页上各抽出 1 条：3.0.24（12 项）、3.0.23（10 项）、3.0.18（10 项）。
