# Insomnia

## 基本信息
- Bundle ID: `com.insomnia.app`（stable / beta / alpha **共享同一 id**）
- Team ID: `FX44YY62GV` (Kong Inc.)
- 观测版本: 12.6.0（stable）
- 自更新机制: Electron（应用自带）。无 Sparkle。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行/受阻  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | (cask `insomnia`) | — | ✓ 检测+一键安装 | — |
| **beta**     | —       | (cask —) | — | ○ 检测层已就绪，rule 未接 | — |
| **alpha**    | —       | (cask `insomnia@alpha`) | — | ✗ 受阻（检测层） | — |

当前生效源: **GitHub Releases**（Kong/insomnia monorepo）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.insomnia.app` | 共享 | 非 prerelease `core@X.Y.Z` | `channel: .stable` + tag `$` 锚 | ✓ |
| beta   | `com.insomnia.app` | 共享 | 版本后缀 `-beta.N` | 可用 `.beta` gate | ○ 未接 rule |
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

## beta/alpha channel 当前状态
真机验证 2026-06-06（`Insomnia.Core-13.0.0-beta.0.dmg` 挂载只读）：
- beta 构建 `CFBundleShortVersionString = 13.0.0-beta.0` —— 后缀**保留**（不像 Mozilla 剥离）。
- 当时 `ReleaseChannel.detect()` 对它返回 `.stable`，任何 `.beta` rule 都过不了
  channel gate。这个历史阻塞已于 2026-08-30 随 Vorssaint 接入解除：通用检测现在
  严格识别整串以 `-beta.<数字>` 结尾的版本，同时继续排除带 `+sha` 的构建元数据。
- Insomnia beta 因此已具备接 rule 的检测前提，但本次没有把另一个 app 混进
  Vorssaint PR；它仍是待接入状态。
- alpha 的 `-alpha.N` 尚未加入通用检测，仍受检测层阻塞。

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
- 状态: stable **支持**；beta 检测前提已就绪但 rule 未接；alpha 仍受检测层阻塞。
- 格式: dmg

## 真机验证（Phase 3¾）
结论见上文「Key findings」；原始 channel-verify 输出未保留。

## 建议下一步
1. ✅ stable ChangelogRecipe 已接（见上）。
2. beta channel：检测前提已完成；另开 app PR 真机复验并加 `.beta` GitHub rule。
3. alpha channel：先扩 `ReleaseChannel.detect()` 识别 `-alpha.N`，再加 `.alpha` rule。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-insomnia-app.swift — stable GitHubReleaseRule（`core@X.Y.Z`，一键 `Insomnia.Core-<ver>.dmg`）

转引自 recipe 注释，未复测。第一、二段原句没写日期；日期取自引入这句话的提交：`f7686b3d`（2026-06-07）。第三段唯一的改写：一处本机状态措辞（这个 app 装没装），按本目录的机器状态规则改成了针对那台被验证的机器的说法。

An unanchored
`core@(X.Y.Z)` captured `13.0.0` out of `core@13.0.0-beta.0` and pushed a
beta onto stable users as "13.0.0" (and the `-beta.0` dmg name then failed
`installAssetPattern`, so the row showed "Open", not even "Update").

(The earlier comment's
"betas sort after the stable of the same line" assumption was simply wrong
when a brand-new line debuts as a prerelease.)

Best-effort one-click: the `Insomnia.Core-<ver>.dmg` (universal) wraps
`Insomnia.app` — verified 2026-06-06 a notarized Developer ID build (Team
FX44YY62GV, Kong Inc.) reporting version 12.6.0 == tag, bundle id
com.insomnia.app. The sibling `inso-macos-*` assets are the CLI, not the
desktop app — the `Insomnia.Core-` anchor excludes them. Electron app with
its own updater, so a fallback; not installed on the machine this was verified on, so the Team-gate
enforces the match at install time.

listPageSize: not installed on the measuring machine, so measured
directly against the live endpoint (2026-09-04, newest 100 releases):
first-match index 0, worst run of non-`core@` tags between two
`core@` releases is 9 (`core@11.0.0`→`core@10.3.1`, the Design/CLI
trains publish in between). 15 keeps ~67% headroom over that.

复测 2026-09-14（03:15 UTC，只读 GET `repos/Kong/insomnia/releases?per_page=100`）：首个 `core@X.Y.Z` 在第 0 位（`core@13.2.0`），相邻两个之间最多隔 8 个 release，100 条里 30 个 stable `core@` tag。
