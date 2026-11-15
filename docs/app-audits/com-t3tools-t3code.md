# T3 Code

## 基本信息
- Bundle ID：`com.t3tools.t3code`，历史 alpha、当前 beta、nightly 共享。
- Team ID：`ARK85ZXQ4Z`（T3 Tools, Inc.）。
- 本次真包：已装 Beta `0.1.6`；公开 DMG Beta `0.1.9`，两者 short == build。
- 自更新：electron-updater，`app-update.yml` 指向 `pingdotgg/t3code`、
  `releaseType: release`，无 `SUFeedURL`。
- 分发：GitHub Releases、官网、Homebrew cask；本次补的是现有 GitHub 家族的 beta 规则。

## 覆盖矩阵

| 安装副本 | 检测源 | 安装资产 | 状态 |
|---|---|---|---|
| 历史 Alpha | GitHub 主发布序列 `vX.Y.Z` | `T3-Code-X.Y.Z-arm64.dmg` | 保留；当前主发布包已改称 Beta |
| Beta | GitHub 主发布序列 `vX.Y.Z` | `T3-Code-X.Y.Z-arm64.dmg` | 本次新增；VM 0.1.6→0.1.9 检测、原生一键与启动通过 |
| Nightly | GitHub `vX.Y.Z-nightly.date.seq` | 对应 nightly arm64 DMG | 已有支持，本次不改 |
| Preview / desktop-preview | 独立 preview / PR 发布序列 | 未选取 | 仍未接入；不冒充 beta 或 nightly |

## 渠道与检测

不是靠 tag 中的 beta 单词判断：上游主发布包的 `CFBundleName` /
`CFBundleDisplayName` 为 `T3 Code (Beta)`，但 tag 仍是 `v0.1.9`，不是 prerelease。
`ReleaseChannel.detect` 按 App 显示名识别为 `.beta`，因此原先只有 alpha/nightly
规则时没有匹配源，最终得到 unknown。本次新增 `.beta` 的独立规则，不修改
通用渠道识别，也不把所有共享 ID 的构建强行当作同一渠道。

Alpha 与 Beta 是同一主发布序列前后使用的显示名，两条兼容规则保留同样的纯数字
版本及安装包形状。Tag 锚拒绝 nightly / preview；安装资产锚拒绝这些轨道、x64、
zip、blockmap。Beta 的 `ChannelProofKey` 与 alpha 一样锚住安装资产的纯数字字段。
它可以发现 pattern 被放宽到能吞其他轨道的变化，不能预言未来厂商另发的同命名轨道。

## Changelog

使用 GitHub Release 正文，随所选 tag 返回。无需额外 ChangelogRecipe。

## 一键安装

完整 arm64 DMG，更新器按当前已装副本的路径替换 App。新旧 Beta 真包为同 bundle ID、
同 Team，未放宽签名、渠道或身份检查。VM 中不修改宿主机的 T3 Code。
此次使用完整包，未验证 electron-updater 的 blockmap 增量更新。

## 验证记录

2026-11-15 在 macOS VM 1 实测：旧 CLI 为 unknown；新增规则的 CLI 为
GitHub 0.1.6→0.1.9 / in-place；原生 GUI 实际下载、替换后显示最新版。
新副本 short/build 0.1.9 / 0.1.9、Team ARK85ZXQ4Z，严格签名通过，启动到
Welcome/setup 界面。此次是未运行状态更新，没有重跑运行中一轮。
完整证据见 [VM 验证](../../verify/t3-beta-20261115/README.md)。
历史 alpha 与 nightly 真包记录保留在下面；本次不把它们称为重新执行过的安装测试。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-t3tools-t3code.swift — 开头的说明（几条轨）

转引自 recipe 注释，未复测。整段原文。"two trains" 与 "the prerelease train" 迁移时已不完整：同一 repo 出现了 `-preview.` 发布系列，此前还有一个滚动的 `desktop-preview` PR 构建 release（见本节末尾的复测）。代码里改成了「两条已覆盖的轨」加上未覆盖的 preview 系列，"the prerelease train" 改成了 "the nightly prerelease train"，末句的 "Neither" 改成了点名 alpha 与 nightly 两个构建。

T3 Code — two trains, ONE bundle id (`com.t3tools.t3code`), one repo.
`ReleaseChannel.detect()` reads the display name: the primary build is
`T3 Code (Alpha).app` (→ .alpha) and the prerelease train is
`T3 Code (Nightly).app` (→ .nightly), verified on the mounted artifacts.
Neither carries SUFeedURL; the cask is auto_updates, so Homebrew defers.

更正 2026-09-14：这个 repo 此后出现了 `-preview.` 发布系列（此前已有一个滚动的 `desktop-preview` PR 构建 release），alpha 与 nightly 两条 rule 都不覆盖它；数据见本节末尾的复测。

### Recipes/com-t3tools-t3code.swift — nightly GitHubReleaseRule（`listPageSize`）

转引自 recipe 注释，未复测。整段原文（nightly 那条 rule 的注释是一整块）。代码里的 `listPageSize` 一句改成了说条件（别的轨的 release 会插在两个 nightly 之间），2026-09-04 的位置、间隔和页大小搬到这里，并按下面的复测注明间隔已经变宽；版本号标成了示例。

T3 Code nightly — prerelease tags `vX.Y.Z-nightly.<date>.<seq>`, several
per day, marked prerelease, so `usePrereleases` reads the list and the
pattern is anchored to the nightly shape end to end. The app reports the
whole string as BOTH marketing and build, so the extracted version must
keep it intact rather than truncate to `X.Y.Z` — a nightly install shows
`0.0.37-nightly.20260830.1227` on both sides, and `VersionComparator`
orders the date/seq runs numerically. One-click: same Team
ARK85ZXQ4Z, verified on the mounted nightly artifact. The asset name
carries `-nightly.` — which is also why the alpha pattern above cannot
drift onto this train: its `[0-9.]+` run refuses the dash.
listPageSize: measured 2026-09-04 against the newest 100 releases —
first-match index 0, worst run between two nightly tags is 2 (the
alpha train's occasional release lands a single non-nightly entry in
between, e.g. `v0.0.39-nightly.20260902.1252`→
`v0.0.38-nightly.20260901.1250`). 5 keeps 2.5x headroom; real page
measured at 11.9 KB gzipped for per_page=3 (12,157 bytes; an earlier
comment rounded the same measurement to 9 KB), vs 64 KB at per_page=20.

### Recipes/com-t3tools-t3code.swift — alpha channel proof

转引自 recipe 注释，未复测。整段原文。"which is the only other train this repo publishes" 迁移时已不成立，而且写下时就不完全成立：当时已有一个滚动的 `desktop-preview` PR 构建 release（见下面的复测），代码里改成了：此后出现了 `-preview.` 发布系列（tag 自 2026-09-12、release 自 2026-09-13），`[0-9.]+` 同样拒绝它的资产名。原句来自提交 `8e0cc26e`（2026-08-30）。

T3 Code alpha is the one channel with no token in the tag OR the asset
name: `v0.0.36` / `T3-Code-0.0.36-arm64.dmg` are byte-identical in
shape to what a hypothetical stable train would publish. What keeps
the alpha rule off the nightly train is the install pattern's PURE
DIGIT run — nightly assets (`T3-Code-0.0.37-nightly.20260830.1227-
arm64.dmg`) carry `-nightly.<date>.<seq>` between the version and
`-arm64`, which `[0-9.]+` refuses. So the proof is an anchor on that
field, not on the artifact: it fails the day someone loosens the
pattern enough to match nightly names (e.g. a `.*` run), which is the
only other train this repo publishes. What it cannot do is catch a
vendor-launched stable train with identical naming — nothing in the
URL would distinguish it, and `/releases/latest` would return it; the
anchor documents that exposure rather than pretending to close it.

复测 2026-09-14（约 07:31 UTC，只读 `gh api repos/pingdotgg/t3code/releases?per_page=100` 与 `releases/latest`）：最新 100 条里 nightly tag 的首次出现在第 1 位（第 0 位是 `v0.0.41-preview.20260914.1693`），相邻两个 nightly tag 的位置差最大是 4；100 条里有 4 个 `-preview.` tag，最早的是 `v0.0.41-preview.20260913.1634`（2026-09-13），都标了 prerelease；`releases/latest` 是 `v0.0.40`（2026-09-08）。`v0.0.41-preview.20260914.1693` 的 macOS 资产名是 `T3-Code-0.0.41-preview.20260914.1693-arm64.dmg` 与 `…-x64.dmg`。nightly rule 的 `listPageSize` 是 5。同日稍后（`gh api repos/pingdotgg/t3code/tags` 与 `releases`）：名字里带 `-preview.` 的 tag 最早是 `v0.0.41-preview.20260912.1595`，标成 release 的最早是 `v0.0.41-preview.20260913.1634`（2026-09-13T04:14:56Z）；另有一个滚动的 `desktop-preview` **release**（prerelease，名为 "Desktop preview builds"，发布于 2026-08-26T02:12:49Z，正文说是带 preview 标签的 PR 的未签名构建，资产形如 `T3-Code-0.0.40-pr.11709.12661-arm64.dmg`）——它早于提交 `8e0cc26e`（2026-08-30），两条 rule 的资产名模式都拒绝它的 `-pr.` 名字，`releases/latest` 也跳过 prerelease。

### Recipes/com-t3tools-t3code.swift — nightly `listPageSize` 5 → 15

复测 2026-10-09（约 02:29 UTC，只读 `gh api repos/pingdotgg/t3code/releases?per_page=100`）：Detection recipes 列表显示
`5 releases fetched, none matched the version pattern`。最新 100 条里前 5 条全是 `-preview.`（`v0.0.46-preview.20261009.2851`、
`…20261008.2848`、`…20261008.2844`、`…20261008.2802`、`…20261008.2800`），第一个 nightly（`v0.0.46-nightly.20261008.2849`）在第 5 位，
所以 5 条的页里一个 nightly 都没有。相邻两个 nightly 的位置差最大是 4（`v0.0.43-nightly.20260920.2005`→`…20260920.1990`、
`…20260926.2282`→`…20260925.2269`），100 条里有 22 个 `-preview.` tag，最早一条发布于 2026-09-17。preview 是成批发的，领头那一段才是
页大小的下限：`GitHubListPageSizeTests` 的下限改为 6，`listPageSize` 取 15（下限前那段的 3 倍）。

同时取回的页大小（gzip，带 token）：per_page=5 15,299 B，10 40,756 B，15 68,712 B，20 93,236 B。`probesNewestFirst` 先取 1 条，
最新一条不是 nightly 时才付整页的钱。

### Electron ZIP 迁移（2026-11-15）

本次保留 alpha 与 nightly 的 DMG 路线。两个 ZIP 都通过生产签名、身份与替换检查，且与对应 DMG 的 arm64 主程序 CDHash / app.asar 一致；但 VM 已运行的 T3 Code Beta 占用共享 t3code-v2 用户目录，测试副本在单实例闸处退出。没有停止既有实例，没有把退出记成启动成功。当前普通版本包已名为 T3 Code (Beta)，既有 alpha 渠道覆盖范围未在本次扩展。

本次包、逐项结果与限制见 [集中验证记录](../../verify/electron-blockmap-20261115/README.md)。这些是一次验证的结果，不代表应用所有版本或功能均已测试。
