# T3 Code

## 基本信息
- Bundle ID: `com.t3tools.t3code`（alpha 与 nightly 共享）
- Team ID: `ARK85ZXQ4Z` (T3 Tools, Inc.)
- 观测版本: alpha `0.0.36`；nightly `0.0.37-nightly.20260830.1227`
- 自更新机制: electron-builder 类自研（发布在 GitHub Releases）；**无 `SUFeedURL`**
- 分发: GitHub Releases / 官网 / Homebrew cask `t3-code`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **alpha**   | —       | — (`auto_updates`) | — | ✓      | —           |
| **nightly** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel  | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|----------|-----------|----------|---------|---------|------|
| alpha    | `com.t3tools.t3code` | 共享 | app 名 `T3 Code (Alpha)`（display-name 词边界） | tag 锚 `^vX.Y.Z$`；`/releases/latest` | ✓ |
| nightly  | `com.t3tools.t3code` | 共享 | app 名 `T3 Code (Nightly)` | `usePrereleases` + tag 锚 nightly 形状 | ✓ |

Pattern A 的变体：同一 bundle id，两条轨靠 **app 名里的渠道词**区分（`ReleaseChannel.detect()`
第 3 步），各自的 GitHub rule 以 `channel:` 门控互斥。nightly 轨的版本串整串
`0.0.37-nightly.20260830.1227` 同时是 marketing 和 build，`VersionComparator` 按数字段
比较，`20260830.1227` 与 `20260830.1226` 正确排序。

## 更新检测
- 源: `pingdotgg/t3code` GitHub Releases
- alpha: `/releases/latest`（nightly 都带 prerelease 标记，被 GitHub 计算排除；
  tag 锚 `^v([0-9]+(?:\.[0-9]+)+)$` 再拒一遍，防 list fallback 时截断 nightly tag）
- nightly: `usePrereleases: true`，pattern
  `^v([0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]+\.[0-9]+)$`——**必须保留整串**，
  截成 `X.Y.Z` 会让每个新 nightly 都读作已装
- 版本方案: 两轨 short==build，比较即同构；无 phantom 面

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 dmg/zip/blockmap，无 `.delta`（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是（各轨读各自的 release）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**，两轨各自
- 格式: dmg — alpha `T3-Code-<X.Y.Z>-arm64.dmg`；nightly `T3-Code-<ver>-nightly.<date>.<seq>-arm64.dmg`
- **读的是**: 人人可手动下载的 GA（GitHub Releases 公开资产）
- 包验（2026-08-30，两条轨的真包挂载）:
  - alpha v0.0.36: `com.t3tools.t3code` / `0.0.36`，arm64-only dmg，
    `Developer ID Application: T3 Tools, Inc. (ARK85ZXQ4Z)`，`spctl accepted /
    Notarized Developer ID`
  - nightly `…1227`: 同 bundle / 同 Team / 公证通过
- **channel proof**（`ChannelProofRegistry.githubProofs`，两条轨都注册）:
  - nightly: `.artifact(#"/download/v[0-9.]+-nightly\."#)` —— tag 在资产 URL 路径里
  - alpha: `.recipeAnchor(#"\[0-9\.\]\+-arm64"#, in: ["installAssetPattern"])` ——
    alpha 的 tag 和资产名**都不带**渠道 token；挡住它的唯一判别子是资产 pattern 的
    纯数字段（nightly 名在版本和 `-arm64` 之间有 `-nightly.<date>.<seq>`，`[0-9.]+`
    拒绝）。锚在 pattern 文本上，pattern 一旦被放宽到能吃 nightly 名，proof 即失败。
    它不承诺能识别厂商未来另发的同命名 stable 轨——那在 URL 上无迹可寻，注释里
    写明了这个敞口。

## 已知问题
- 同一 repo 里 nightly 每天多条；alpha 安装永远看不到它们（prerelease 被
  `/releases/latest` 排除 + tag 锚拒绝），nightly 安装只看到 nightly 轨。
- `LSMinimumSystemVersion = 12.0`，低版本宿主由下载后检查兜住。

## 如何复验
```
# GET https://api.github.com/repos/pingdotgg/t3code/releases/latest → v0.0.36
# 挂载 T3-Code-0.0.36-arm64.dmg → com.t3tools.t3code / 0.0.36，Team ARK85ZXQ4Z
# 装 alpha 构建 → channel-verify --check com.t3tools.t3code --expect alpha
#   winning=GitHub, 0.0.36 up to date
# 换 nightly 构建 → --expect nightly：winning=GitHub,
#   0.0.37-nightly.20260830.1227 up to date
```

## 建议下一步
无。检测 + 一键 + changelog 两轨均已覆盖。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

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

转引自 recipe 注释，未复测。整段原文。"which is the only other train this repo publishes" 迁移时已不成立（见下面的复测），代码里改成了「写这句时 nightly 是唯一的另一条轨，此后多了 `-preview.` 轨，`[0-9.]+` 同样拒绝它的资产名」。原句来自提交 `8e0cc26e`（2026-08-30）。

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

复测 2026-09-14（约 07:31 UTC，只读 `gh api repos/pingdotgg/t3code/releases?per_page=100` 与 `releases/latest`）：最新 100 条里 nightly tag 的首次出现在第 1 位（第 0 位是 `v0.0.41-preview.20260914.1693`），相邻两个 nightly tag 的位置差最大是 4；100 条里有 4 个 `-preview.` tag，最早的是 `v0.0.41-preview.20260913.1634`（2026-09-13），都标了 prerelease；`releases/latest` 是 `v0.0.40`（2026-09-08）。`v0.0.41-preview.20260914.1693` 的 macOS 资产名是 `T3-Code-0.0.41-preview.20260914.1693-arm64.dmg` 与 `…-x64.dmg`。
