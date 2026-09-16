# Tinycast

## 基本信息
- Bundle ID: `com.tinycast.app`（stable）/ `com.tinycast.app.beta`（beta）
- Team ID: **无** —— 两轨都用自签名证书 `Tinycast Self-Signed`，`TeamIdentifier=not set`
- 观测版本: stable `0.10.23`（build `93`）、beta `0.11.1-beta.96`（build `96`），2026-09-17
- 自更新机制: **自研**，读 `abue-ammar/tinycast` 的 GitHub Releases 列表，下载 zip、
  `ditto` 解包、校验后 `replaceItemAt`。无 Sparkle、无 appcast（包里没有 `SUFeedURL`）
- 分发: GitHub Releases（dmg + zip）；Homebrew 自有 tap `abue-ammar/homebrew-tinycast`
  （`tinycast` / `tinycast@beta` / `tinycast-universal` / `tinycast-sequoia`，均 `auto_updates true`）；
  主 homebrew-cask 无收录；Mac App Store 无上架
- 开源: 是。以下渠道与版本结论**取自源码**（1a-00），不是推断:
  `docs/features/updates.md`、`docs/release.md`、`.github/workflows/release.yml`、
  `Tinycast/Features/Updates/Model/{ReleaseChannel,ReleaseFeed}.swift`，均在 `main`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（第三方 tap，且 `auto_updates`） | — | ✓（仅检测） | — |
| **beta**   | —       | —（同上） | — | ✓（仅检测） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.tinycast.app` | 独立 | — | `/releases/latest` + tag 锚 `^vX.Y.Z$` | ✓ |
| beta    | `com.tinycast.app.beta` | 独立 | bundle id 后缀 `.beta`，版本串带 `-beta.N` | 列表 + tag 锚 `^vX.Y.Z-beta.N$` | ✓ |

**Pattern A（独立安装）**，settled from source: `ReleaseChannel.swift` on `main` —— 厂商
只按 bundle id 分渠道，stable 只收非 prerelease、beta 只收 prerelease，互不越轨；
`Tinycast.app` 与 `Tinycast Beta.app` 可以并装。本地开发构建是第三个 id
`com.tinycast.app.dev`，不自更新，也不在发布里出现。

beta 的 `-beta.N` 里 `N` 是 Actions 的 run number，跨 base 版本持续递增，与 base 版本同时
前进（`0.10.23-beta.94` → `0.11.0-beta.95` → `0.11.1-beta.96`）。

**beta rule 不收 stable tag**（与 WhatCable 相反、与 Yaak 相同）：stable 发布是另一个 app
（`Tinycast.app`），不是 beta 副本"毕业"去的版本；厂商自己的更新器也从不把 stable 给 beta。

`ReleaseChannel.detect` 对真实身份的结果由 `TinycastGitHubRuleTests` 钉住：
`Tinycast Beta` / `com.tinycast.app.beta` / `0.11.1-beta.96` → `.beta`；
`Tinycast` / `com.tinycast.app` / `0.10.23` → `.stable`。

## 更新检测
- 源: `abue-ammar/tinycast` GitHub Releases
- 版本方案: tag `v0.10.23` → `0.10.23` == 包的 `CFBundleShortVersionString`；
  tag `v0.11.1-beta.96` → `0.11.1-beta.96` == beta 包的 `CFBundleShortVersionString`
  （后缀原样保留，所以抽取时必须连后缀一起抽）。build 号不参与。
- 仓库里还有三类非本轨 tag，全部 `prerelease: true`，两条 pattern 都不收:
  - `v0.9.7-sequoia` / `v0.9.4-sequoia` / `v0.7.5-sequoia`：macOS 15 构建，**同 bundle id**
    `com.tinycast.app`，只有 dmg
  - `v0.1.0-alpha.4` … `v0.5.7-alpha.22`：早期 alpha 轨，已停
- 2026-09-17 全部 94 个 release：tag 形状与 `prerelease` 标志**零不一致**
  （`-beta.N` 全为 true、纯 `vX.Y.Z` 全为 false）。两条 rule 都没有 `installAssetPattern`，
  所以资产有没有都不参与解析（缺资产的列表回退只对设了 install pattern 的 rule 生效）。
  ⚠️ 将来加一键时要知道：57 个早期 release 只发 dmg、没有 zip，一条 zip 的 install pattern
  会把它们当成「缺 macOS 资产」。
- beta 的 `listPageSize`: 56 个 beta tag，最大间隔 5（`v0.9.6-beta.53` → `v0.9.2-beta.49`），
  下限 6，取 10。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 源码 `docs/features/updates.md`：只下整包 zip | release 资产只有 dmg/zip（stable 另有 Universal 一对） | — |

- 按架构分轨: stable 发 arm64 thin zip + `Tinycast-Universal-<v>` 一对；beta 只发 arm64 thin。
  我们仅检测，不选资产，不受影响。
- 按 OS 分轨: stable/beta 包 `LSMinimumSystemVersion=26.0`；`-sequoia` 构建 `15.0`。
  见「已知问题」。
- 自更新器会不会和我们抢: 不会，我们不安装。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回，无需 recipe）
- 正文由 GitHub 的 generate-notes 生成（`## What's Changed` + PR bullet 列表），跟随各自的 release，
  所以天然跟随 channel。
- 正文里 `<!-- tinycast:install -->` 标记之下是 Homebrew / `xattr` 安装说明，厂商自己的更新窗口
  会在标记处截断。**我们没有截断，面板里这段会不会被渲染出来：未验证。**

## 一键安装
- 状态: **不支持，且不是待办**
- 格式: zip（`ditto -c -k --keepParent --sequesterRsrc`）
- **读的是**: 轨道最新。仅检测、不安装，而且与厂商更新器读的是同一个列表、同一条规则，没有灰度。
- 包验（2026-09-17，`gh release download` 下 `Tinycast-0.10.23.zip`、`Tinycast-Universal-0.10.23.zip`、
  `Tinycast-0.11.1-beta.96.zip`，`ditto -x -k` 解包）:
  - `codesign -dvv`: `Authority=Tinycast Self-Signed`、`TeamIdentifier=not set`
  - `codesign --verify --deep --strict`: 三个都通过（签名本身完整）
  - `spctl -a -vv`: 三个都 `rejected`
- 对应到闸：`SignatureVerifier` 要求被替换的拷贝和下载包都有 Team ID，二者都没有，必拒。
  挂 `installAssetPattern` 只能造出一个必定失败的 Update 按钮，所以留 nil。
- 重开条件: 厂商源码 `BundleSignature` 已经钉了一个 Developer ID 要求（Team `SPBUD83MLU`），
  注释写着"Developer ID switch"，但截至 2026-09-17 发布的包仍是自签名。发布包换成 Developer ID
  签名之后可以重新评估（届时仍要处理「从自签名副本换到 Developer ID 包」这一次 Team ID 不一致）。

## 已知问题
- **macOS 15 的 `-sequoia` 构建会被报"有更新"。** 它与 stable 同 bundle id、版本串是
  `0.9.7-sequoia`（`LSMinimumSystemVersion=15.0`，2026-09-17 挂载 dmg 读到），`detect` 按 stable
  处理，stable rule 会给出 `0.10.23`，而那个版本要求 macOS 26。仅检测，不会装错；但在 macOS 15
  上这行会一直显示一个装不上的更新。`GitHubReleaseRule` 没有 OS 下限字段，没修。

## 建议下一步
1. 无。stable/beta 检测已接入。
2. 厂商发布包换成 Developer ID 签名后，重新评估一键安装。
