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
