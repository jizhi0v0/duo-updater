# Longbridge Desktop（长桥桌面版）

## 基本信息
- Bundle ID: `com.longbridge.app.desktop`
- Team ID: `45NG8MW7WK`（LONG BRIDGE TECHNOLOGY HK LIMITED）
- 已验证版本: `0.19.1`（build `20260820.080114`）
- 自更新机制: 自研；无 `SUFeedURL`

## 覆盖矩阵

> ✓ = 已接入　○ = 可接入（未实现）　✗ = 已调查不可行　— = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | —      | ✓           |
| **preview**  | —       | —        | —   | —      | ✓（2026-08-26 接入，见下） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

Homebrew 的 `longbridge-pro` 是另一款应用 Longbridge Pro，不是本接入对象；Mac App
Store 搜索没有 Longbridge Desktop。公开 stable 分发由厂商自己的 release manifest 提供。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|-----------|----------|------|
| stable | `com.longbridge.app.desktop` | 独立 | 默认 stable | ✓ |
| preview | `com.longbridge.app.desktop.preview` | 独立 | bundle id / 显示名 / 版本后缀 | ✓ VendorProbe + changelog + 一键（`55721c0e`） |

旧 preview 实包 `0.15.0-preview.0` 已验证为独立 Bundle ID，生产
`ReleaseChannel.detect()` 正确识别为 `.preview`；stable 配方不会跨渠道命中它。

**更正（2026-09-14）**：本文原先把 preview 记为「已停更，不接」。那是 2026-08-25 从一个旧包倒推的，
2026-08-26 的 `55721c0e` 已按活轨接入（`Recipes/com-longbridge-app-desktop.swift`，`channel: .preview`）。
2026-09-14 只读 GET 复测：preview 索引 `/desktop/release-notes/preview/` 列出 `v1.0.0-preview.1` 与
`v1.0.0-preview.0`，`preview/latest.json` 是 `1.0.0-preview.1`（2026-09-08 发布），资产带 `sha256`。

## 更新检测
- 源: VendorProbe。
- 端点: `https://assets.lbkrs.com/github/release/longbridge-desktop/stable/latest.json`。
- 版本字段: 顶层 `version`，与实包 `CFBundleShortVersionString` 完全一致；不使用时间戳式
  `CFBundleVersion`。
- 发布时间: 顶层 `published_at`，写入 Release Log。
- 生产验证: mounted stable DMG `0.19.1 → 0.19.1`，stable / up-to-date。
- preview（`55721c0e`，2026-08-26 接入）: 独立 recipe，端点 `…/longbridge-desktop/preview/latest.json`，版本 pattern 要求 `-preview.N` 后缀；两条轨的 pattern 互不匹配，跨轨解析 fail-closed。

## Changelog
- 来源（stable）: 英文版本页 `longbridge.com/en/changelog/longbridge-pro/v{major.minor}`。官网一页对应一条小版本线（如 `…/v0.19` 同页含 0.19.1 与 0.19.0），每版是一个 `release-section`。不带 `v` 的 `…/0.19` 是 meta-refresh 跳转壳（见「历史与实测」2026-10-19）。
- 来源（preview）: 官网已没有 preview 版本页（见「历史与实测」2026-10-14）。唯一仍发布 preview 说明的是 `…/longbridge-desktop/preview/latest.json` 的 `release_notes.en`。
- 状态（stable）: `ChangelogRecipe`，正则取该页第一个 `release-section`（`data-rail-version` / `data-rail-date`），条目取 `div.prose` 里的 `<li>`/`<p>`；`<video>` 截断条目，`imagePattern` 收图。
- 状态（preview）: `StructuredFormat.longbridgeDesktopManifest`，读 JSON 字符串 `release_notes.en`，每个 `- ` 行一条，去掉 `**` 与 `###` 标题。清单只含最新一版，所以无论请求哪个版本，条目都是这一版（条目上标的是它自己的版本号）。
- 网页兜底（stable）: `https://longbridge.com/desktop/release-notes/`（仍 200，跳到 Pro 产品列表）。preview 没有专属兜底页，`changelogURL` 同样跳到 Pro 产品列表。
- 限制: stable 的 `maxEntries: 1`，按装机版本的那条小版本线取最新一版；preview 只有最新一版的说明，没有历史。

## 一键安装
- 状态: ✓（Apple Silicon）。
- 格式: 自包含 DMG；manifest 精确选择 `macos-aarch64.dmg`。
- 安全: 官方 JSON 的 SHA-256 与下载字节一致；应用代码签名有效，Team
  `45NG8MW7WK`，Gatekeeper 判定 `Notarized Developer ID`。
- 校验: 2026-10-07 起 stable 与 preview 都接上 manifest 里同一资产的 `sha256`（`checksumFormat: .sha256Hex`，#1016），
  在 Team ID 闸之上先核下载字节；该资产没有 `sha256` 时什么都不读（只剩 Team ID 闸），不会借用 x86_64 / linux 资产的摘要。
- 架构: manifest 也提供 `macos-x86_64.dmg`，但 DuoUpdater 只跑在 Apple silicon 上（`App/project.yml`
  `ARCHS: arm64`），所以 pattern 锚 `macos-aarch64.dmg` 就是完整覆盖，没有 Intel 一键要补。
  （更正 2026-09-14：原先写「本次不宣称 Intel 一键安装覆盖」，暗示将来会补。）
- preview: 同样一键 `…-preview.N-macos-aarch64.dmg`，Team 与 stable 相同（`45NG8MW7WK`），见 `55721c0e`。

## 运行时（GPUI，不是 Tauri）

Longbridge 桌面端用 **GPUI** 画界面 —— 和 Zed 同一套渲染框架，直接从 Zed 仓库拉：

```
~/.cargo/git/checkouts/zed-a70e2ad075855582/6ae5231
~/.cargo/git/checkouts/gpui-component-95ce574d8a0da8b8/20a1bb4   # github.com/longbridge/gpui-component
```

`gpui-component`（那套 UI 组件库）是长桥自己维护的开源项目。

**它同时内嵌了一个改名的 wry 分叉**，只用于承载局部网页内容，不是主界面：

```
~/.cargo/registry/src/rsproxy.cn-…/lb-wry-0.53.3/src/wkwebview/…
```

`0.19.1` 实包里 `strings` 计数：`gpui` 2140 处、`zed` 1238 处、**`tauri` 0 处**。

这正是 issue #206 的根因。旧的 Tauri 判据是「cargo-bundle 的 plist 指纹 +
链了 WebKit」，Longbridge 三条全中却不是 Tauri —— Zed 和 Warp 只是碰巧没内嵌
WebView 才逃过。判据现在改成正面证据（二进制里必须有 `tauri-<semver>` crate 路径），
Longbridge 归到 `native`。见 `AppRuntimeDetector`。

## 已知问题
- （已更正）原先这里写 preview「已经停止更新、不添加 recipe」；preview 实际在更新且已接入，见「Channel 详情」的更正。
- （已解决 2026-10-07）原先这里写「官方 manifest 发布十六进制 SHA-256，而 VendorInstallSpec 的内联 checksum 闸只支持
  base64 SHA-512」；#1016 加了 `.sha256Hex`，两个渠道都已接上，见「一键安装」。

## 建议下一步
1. 监控 stable manifest 的 `version`、`published_at`、`assets[].url` 字段形状。
（原第 2 条「若 VendorInstallSpec 将来支持按 host architecture 选 URL，再补 Intel 一键安装」已删：没有 Intel 宿主，见「一键安装」。）


## 历史与实测

### Recipes/com-longbridge-app-desktop.swift — changelog 版本页加 `v` 前缀（2026-10-19 实测，#1273）

夜扫 2026-10-18 报 `noEntriesExtracted`（上次正常 2026-10-15，last good `1.0.0`），抓到的响应是 455 B 的跳转壳。只读 GET，浏览器样式 User-Agent：

- `/en/changelog/longbridge-pro/1.0`、`…/0.19`、`…/0.20` 都是 HTTP 200、约 455–460 B 的页面，只有 `<meta http-equiv="refresh">` + `location.replace` 指向 `…/v1.0`、`…/v0.19`、`…/v0.20`，没有 `release-section`。`ChangelogService` 不跟 meta-refresh，所以抽出 0 条。
- 带 `v` 的页 200（36–50 KB）。Python 按 recipe 同一正则复算：`v1.0` → 1.0.0、2026-10-13、11 项；`v0.19` → 0.19.1、2026-08-20、2 项（共 2 节）；`v0.18` → 0.18.4、2026-08-04、2 项（共 4 节）。与 10-14 用生产解析器测到的条目数一致。
- 旧 URL `/desktop/release-notes/v1.0.0` 仍 301 到不带 `v` 的 `…/1.0#v1.0.0`（再经跳转壳到 `v1.0`）。
- 修法：`sourceTemplate` 改成 `…/longbridge-pro/v{majorMinor}`。

### Recipes/com-longbridge-app-desktop.swift — changelog（官网改版，2026-10-14 实测）

只读 GET，浏览器样式 User-Agent，原始字节存在 scratch 里。以下为本次复测结果：

- 官网改为 Astro 页面（`data-astro-cid-*`，`All release notes`，RSS 在 `/en/changelog/rss.xml`）。旧的 `div.vp-doc`、`Release Date:` 块、`id="downloads"` 都已不存在。
- 旧版本页 URL 仍可用，但会跳转：`/desktop/release-notes/v0.19.1`、`…/v0.19.0`、`…/v1.0.0` 都跳到 `/en/changelog/longbridge-pro/<minor>#v<version>`（落地页 200，含 `release-section`）。`/desktop/release-notes/` 跳到 `/changelog/longbridge-pro`（产品列表，无 `release-section`）。
- preview 页已经没有：`/desktop/release-notes/preview/` 与 `/desktop/release-notes/preview/v1.0.0-preview.3` 都跳到 `/changelog/longbridge-pro`（产品列表，无 preview 条目）。猜测过的 `/en/changelog/longbridge-preview`、`…/longbridge-pro-preview`、`…/longbridge-pro/preview`、`…/longbridge-pro/1.0-preview`、`…/longbridge-pro/1.0.0-preview.3` 都是 404。产品列表 `/en/changelog` 只列 Longbridge Pro（版本线 0.1–1.0）与 LongbridgeAI，没有 preview。
- RSS `/en/changelog/rss.xml`（全站，约 20.7 KB）没有 preview 条目；`description` 被截成一行（例：「Fixed an issue where an order price tracking Mid / Bid1 / As」），不是正文。所以没有选 RSS 作为正文来源。
- 清单：`stable/latest.json` 版本 `1.0.0`（`published_at` 2026-10-12），`preview/latest.json` 版本 `1.0.0-preview.3`（`published_at` 2026-10-09）。两份的 `release_notes.en` 都在。
- 版本页结构：`pro-0.19` 页 2 个 release-section（0.19.1、0.19.0），`pro-0.20` 页 2 个（0.20.1、0.20.0），`pro-1.0` 页 1 个（1.0.0）。`<section>` 上的 `data-rail-version` 与 `data-rail-date` 是 ISO 日期，`<time datetime>` 与之一致。
- 生产解析器（`ChangelogService.parse`）在实时字节上的结果（maxEntries 1）：stable `1.0.0` 页 → 1 条 `1.0.0`，2026-10-13，11 条；`0.20` 页 → 1 条 `0.20.1`，2026-09-24，4 条；`0.19` 页 → 1 条 `0.19.1`，2026-08-20，2 条。preview 清单 → 1 条 `1.0.0-preview.3`，2026-10-09，11 条。新的 stable 正则读 preview 清单、preview 解码器读 stable 页面，都得到 nil。
- 结构：stable 条目保持扁平，`<h2>` 分类标题（如「New Features」）不作为条目输出，只保留 `<li>` 文本，与旧版本一致。preview 同样扁平，`###` 标题被丢弃。

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-longbridge-app-desktop.swift — preview VendorProbe（`com.longbridge.app.desktop.preview`）

转引自 recipe 注释，未复测。前两段原句没写日期；日期取自引入这些句子的提交：`55721c0e`（2026-08-26）。

The channel has been DE-LISTED from the vendor's site but not retired:
`/desktop/release-notes/preview/` still returns 200 while rendering an
EMPTY version list (stable's index server-renders 48 links), and
`/desktop/preview/` is 404 — there is no download landing page. The
per-version notes pages, this manifest, and the artifacts are all still
published, so a user who already runs Preview can be updated in place;
they just cannot discover a new one through the website. That is why
`changelogURL` points at the (currently empty) preview index rather than
a version-specific page: it is the right place conceptually and will
repopulate on its own if the vendor restores the listing.

Two structural differences from the stable manifest, both deliberate
here: the version carries a `-preview.N` suffix (so the pattern requires
it — the stable pattern's trailing quote cannot match this shape, and
this one cannot match stable's, verified both directions against the
live bodies), and preview assets ship WITHOUT the `sha256` field stable
includes. No checksum is asserted either way (`checksumPattern` wants a
base64 SHA-512), so this costs nothing today, but it is a sign the
preview manifest is maintained at a lower standard than stable's.

Verified 2026-08-26 against the downloaded 0.19.0-preview.1 artifact
(75,399,519 B): com.longbridge.app.desktop.preview, arm64,
Team 45NG8MW7WK — the SAME team as stable, which is what
`VendorInstaller`'s signature gate requires — spctl accepted as
Notarized Developer ID.

复测 2026-09-14（03:15 UTC，只读 GET）：`/desktop/release-notes/preview/` 回 200，列出 2 个版本（`./v1.0.0-preview.0`、`./v1.0.0-preview.1`），不再是空列表；stable 索引列出 49 个版本；`/desktop/preview/` 仍是 404；preview `latest.json` 是 `1.0.0-preview.1`（`published_at` 2026-09-08），它的资产**带** `sha256`（与 stable 的 `latest.json` 一样，各 6 处）。代码里 "DE-LISTED / currently empty" 与 "ship WITHOUT the `sha256`" 两处已按这次复测改写。

### Recipes/com-longbridge-app-desktop.swift — preview ChangelogRecipe

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`55721c0e`（2026-08-26）。

`source` is the preview index. The vendor currently renders it EMPTY
(see the VendorProbeRecipe comment), which makes it a correct no-version
fallback for the same reason stable's index is: it yields nothing and
the UI embeds the page instead of inventing an entry.

复测 2026-09-14：preview 与 stable 两个索引页里 `Release Date` 都出现 0 次。

### Recipes/com-longbridge-app-desktop.swift — 一键接上 sha256（2026-10-07）

stable 与 preview 的 `checksumPattern` 都取「第一个本渠道 aarch64 dmg 文件名所在的那个资产对象」里的 `sha256`，即 URL pattern 读的那一项，与键序无关。

实测（2026-10-07，只读 GET + 下载）：stable `latest.json` 是 0.20.1，preview 是 1.0.0-preview.1，两份的 6 个资产都带 `sha256`。
`longbridge-v0.20.1-macos-aarch64.dmg`（80,201,274 B）的 SHA-256 是 `4e47fba4…b915`，`longbridge-v1.0.0-preview.1-macos-aarch64.dmg`（80,106,741 B）是 `4c9aa999…bd02`，
都与 manifest 值一致。用生产路径（`VendorProbeSource.probeDiagnostic`）对线上端点跑：两个渠道的 `RemoteVersion.expectedSHA256` 分别是这两个值、`expectedSHA512` 为 nil、无 warning；
`VendorInstaller.verifySHA256` 对下载文件通过，翻转一个字节的副本抛 `checksumMismatch`（临时测试，跑完已删）。没有跑 `duo install`。
