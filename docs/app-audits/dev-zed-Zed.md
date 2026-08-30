# Zed

> 审计日期 2026-06-04 · 模式 REPORT · 结论：**Stable + Preview 两 channel 均经 GitHub 检测 ✓**
> （2026-06-04 收尾补全：为 stable 加 GitHubReleaseRule 填上版本缺口，并修掉一个 Preview
> 的 channel-gate 回归——见「channel-verify 状态」）

## 基本信息
- Bundle ID (stable): `dev.zed.Zed`（Preview 独立：`dev.zed.Zed-Preview`）
- Homebrew cask: `zed`（`auto_updates: true`）→ HomebrewCaskSource 落穿
- 自更新机制: Zed 内置更新器（自研）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | ✓      | —           |
| **preview**  | —       | —        | —   | ✓      | —           |

当前生效源:
- stable: **GitHub** (`dev.zed.Zed`，`usePrereleases: false` → `/releases/latest` 排除 prerelease，默认 pattern 剥 `v`；live 确认 latest=`v1.5.3`)
- preview: **GitHub** (`dev.zed.Zed-Preview`，`usePrereleases: true`，pattern `v([0-9]+\.[0-9]+\.[0-9]+)-pre`，`channel: .preview`)

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `dev.zed.Zed`         | 独立 | — (stable 默认) | ✓ |
| preview | `dev.zed.Zed-Preview` | 独立 | bundle id `-Preview` 后缀 → `.preview` | ✓ |

## 更新检测
- stable: **GitHub** `zed-industries/zed`，`/releases/latest`（自动排除 prerelease），默认 pattern
  `v?([0-9]+(?:\.[0-9]+)+)` 剥 `v` → `1.5.3`，与安装版 `CFBundleShortVersionString` 同构。channel
  gate 默认 `.stable`，不会串到 Preview（后者独立 bundle id 且 `.preview`）。detection-only：
  `Zed-aarch64.dmg` 资产 Team ID 未对照安装版核实、且 Zed 自带更新器，不设 `installAssetPattern`。
- preview: GitHub `zed-industries/zed`，扫 prereleases，取第一个匹配 `v.*-pre` 的 tag；
  rule 显式 `channel: .preview`（否则被 channel gate 拒）。

## Changelog
- stable: ChangelogRecipe ✓（`zed.dev/releases/stable`，id-锚点结构）
- preview: ChangelogRecipe ✓（`zed.dev/releases/preview`，相同结构）

## 一键安装
- 仅检测（两 channel 均无 installAssetPattern / install 字段）

## 建议下一步
- （已无未决项）stable 改用 GitHub `/releases/latest` 后无需另装 Zed.app 验 `SUFeedURL`；
  若日后 Zed 给 stable 提供官方版本 JSON/Sparkle，可平替但非必需。

## channel-verify 状态
- ✓ **stable 已补源并验证 2026-06-04（收尾）**：加 `GitHubReleaseRule(dev.zed.Zed, zed-industries/zed)`。
  live API 确认 `/releases/latest`=`v1.5.3`（=审计时挂载的 stable dmg 版本），默认 pattern → `1.5.3`。
  离线断言 `GitHubReleaseRuleTests.zedStableRuleExtractsVPrefixedTag` 锁住。**填上了原 stable 缺口。**
- ✓ **preview 已验证（并修复 channel-gate 回归）2026-06-04**：`--check dev.zed.Zed-Preview`
  全生产链确认 winning source=**GitHub**、latest=`1.6.0`=installed、status=up to date。
  ⚠️ 此次 `--check` 抓到一个回归：Preview rule 原**未声明 `channel`**（默认 `.stable`），
  而 Codex 新加的 channel gate 要求 `rule.channel == app.releaseChannel`，导致 `.preview` 安装
  被 gate 拒、源不应答（status=unknown）。早先审计用的是 `--scan`（仅检测）+ 手动 live API，
  没跑全链所以漏掉。已给 rule 补 `channel: .preview`，并加断言 `…== .preview` 锁住。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan dev.zed.Zed-Preview --expect preview
# full production chain (catches channel-gate issues --scan misses):
swift run --package-path application-test channel-verify --check dev.zed.Zed-Preview --expect preview
swift run --package-path application-test channel-verify /tmp/zed-stable.dmg --expect stable
```
