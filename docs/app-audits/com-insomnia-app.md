# Insomnia

## 基本信息
- Bundle ID: `com.insomnia.app`（stable / beta / alpha **共享同一 id**）
- Team ID: `FX44YY62GV` (Kong Inc.)
- 已安装版本: 12.6.0（stable）
- 自更新机制: Electron（应用自带）。无 Sparkle。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行/受阻  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | (cask `insomnia`) | — | ✓ 检测+一键安装 | — |
| **beta**     | —       | (cask —) | — | ✗ 受阻（检测层） | — |
| **alpha**    | —       | (cask `insomnia@alpha`) | — | ✗ 受阻（检测层） | — |

当前生效源: **GitHub Releases**（Kong/insomnia monorepo）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.insomnia.app` | 共享 | 非 prerelease `core@X.Y.Z` | `channel: .stable` + tag `$` 锚 | ✓ |
| beta   | `com.insomnia.app` | 共享 | 版本后缀 `-beta.N`（**detect() 不识别**） | — | ✗ 受阻 |
| alpha  | `com.insomnia.app` | 共享 | 版本后缀 `-alpha.N`（**detect() 不识别**） | — | ✗ 受阻 |

**用户的三个问题：**
1. **有独立渠道 app 吗？** 没有。beta/alpha 与 stable **共享** `com.insomnia.app`，
   渠道 = 你装了哪条 GitHub release 线（stable=非 prerelease；beta/alpha=prerelease tag）。
   `insomnia@alpha` cask 装的也是同一 bundle id（来自 prerelease dmg）。
2. **能在 app 内切换渠道吗？** 无 in-app channel toggle 证据；切换靠装不同构建/cask。
   Electron 在各自轨道内自更新。
3. **changelog 跟随渠道吗？** 跟随——GitHub release notes 按 tag 走，天然 per-release/
   per-channel。但目前**没有 ChangelogRecipe**；notes 来自 GitHub release body
   （`GitHubMarkdownParser`）。

## 已修复的 BUG（本次）
**stable 渠道跨渠道误推 + "Open" 假象。** Kong 会在 stable 之前发新线的 prerelease
（`core@13.0.0-beta.0`），它作为"最新"排在列表首位。旧 `versionPattern`
`core@([0-9]+\.[0-9]+\.[0-9]+)`（无锚）从 `core@13.0.0-beta.0` 里抠出 `13.0.0`，
把 beta 当 stable 推给 12.6.0 用户；而 `-beta.0` dmg 文件名又匹配不上
`installAssetPattern` → `vendorInstallerKind` 为空 → UI 显示 **"Open"** 而非 Update。
**修复**：pattern 加 `$` 锚 → `core@([0-9]+\.[0-9]+\.[0-9]+)$`，只匹配无后缀的 stable
tag。回归测试 `insomniaRuleMatchesCoreTagOnly` 已 pin 该 feed。

## 为什么 beta/alpha channel 受阻（检测层）
真机验证 2026-06-06（`Insomnia.Core-13.0.0-beta.0.dmg` 挂载只读）：
- beta 构建 `CFBundleShortVersionString = 13.0.0-beta.0` —— 后缀**保留**（不像 Mozilla 剥离）。
- 但 `ReleaseChannel.detect()` 对它返回 **`.stable`** —— **不解析版本后缀**。
- 因此任何 `channel: .beta` 的 GitHub rule 都过不了 channel gate（gate 要求
  检测渠道 == rule 渠道），永远不会被选中。
- **前置依赖**：先让 `detect()` 识别 `com.insomnia.app` 的 `-beta.N`/`-alpha.N` 后缀
  （或一般化版本后缀信号）。GitHub 侧的 tag + `Insomnia.Core-<ver>-beta.N.dmg` 资产已就绪。

## 更新检测（stable）
- 源: GitHubReleaseRule（owner `Kong`, repo `insomnia`, `usePrereleases: true` 扫列表跳过 lib@/inso@）
- versionPattern: `core@([0-9]+\.[0-9]+\.[0-9]+)$`
- installAssetPattern: `^Insomnia\.Core-[0-9.]+\.dmg$`（universal dmg，排除 `inso-macos-*` CLI）
- installerKind: dmg
- Team 门控: `FX44YY62GV`（2026-06-06 验证 `Insomnia.Core-12.6.0.dmg` 内 `Insomnia.app`）

## Changelog
- 来源: **ChangelogRecipe**（已接入 2026-06-06），抓 `insomnia.rest/changelog`。
  必须用 recipe 而非 GitHub release body：stable `core@X.Y.Z` 的 body 常常只有一句
  "Full Changelog: …compare…"（真实改动都在前置的 `core@X.Y.Z-beta.0` prerelease body），
  12.6.0 用户因此看不到有用 notes。recipe 在 UI 优先级最高（`changelogState` 先于
  source 的 structured/HTML），所以会盖过那条空 body；解析失败再回落到网页。
- 实现: 该页是 Next.js，全量历史烘焙在 `__NEXT_DATA__` JSON
  （`props.pageProps.changelogs[]`，含 `release_version`/`release_date`/`log[]`）。
  Recipe 用 `mode: .json` 解析嵌入 JSON（非 Tailwind-hashed 渲染 HTML），96 条真机验证。
- 跟随 channel: 页面是全渠道合并的版本流（per-version），stable 命中对应版本块。
- Recipe 状态: ✅ 已接入 + 离线 fixture 测试 `extractsInsomniaEntriesFromNextDataJSON`。

## 一键安装
- 状态: stable **支持**；beta/alpha 受检测层阻塞。
- 格式: dmg

## 真机验证（Phase 3¾）
见 `application-test/records/com-insomnia-app.md`。

## 建议下一步
1. ✅ stable ChangelogRecipe 已接（见上）。
2. beta/alpha channel：先扩 `ReleaseChannel.detect()` 识别 `-beta.N`/`-alpha.N` 版本后缀
   并真机验证，再加 `channel: .beta/.alpha` 的 GitHub rule。
