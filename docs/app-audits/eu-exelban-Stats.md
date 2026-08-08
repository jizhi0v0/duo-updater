# Stats

macOS menu-bar system monitor (exelban/stats).

## 基本信息
- Bundle ID: `eu.exelban.Stats`
- Team ID: `RP2S87B72W` (Serhiy Mytrovtsiy)
- 已安装版本: 3.0.4 (build 804) — 审计时最新为 3.0.10
- 自更新机制: 自研 in-app updater（读 GitHub API）；**无 `SUFeedURL`**、无 Squirrel

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub Releases**（`exelban/stats`，`GitHubReleaseRule`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `eu.exelban.Stats` | — | — | — | ✓ |

单渠道。仓库不发 prerelease，`/releases/latest` 即所需；tag 带 `v` 前缀，被默认
`versionPattern` 剥掉。

## 更新检测
- 源: GitHub Releases `/repos/exelban/stats/releases/latest`
- 版本方案: tag `v3.0.10` → `3.0.10` == 安装包的 `CFBundleShortVersionString`。
  **不是** `CFBundleVersion`（832），所以走默认比较即可，无 build-number 陷阱。

## Changelog
- 来源: GitHub release body（通用路径，无需 recipe）
- 跟随 channel: 不适用（单渠道）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（2026-08-08 起）
- 格式: dmg — 每个 release 只有一个资产 `Stats.dmg`（7.5 MB）
- Pattern: `^Stats\.dmg$`, kind `.dmg`

### 验证记录（2026-08-08，v3.0.10）
下载真实 dmg 挂载核对，四项全过：

| 检查 | 结果 |
|------|------|
| dmg 结构 | 根目录 `Stats.app` + `/Applications` 符号链接（标准布局） |
| Bundle ID | `eu.exelban.Stats` == 已安装 |
| 版本 | `CFBundleShortVersionString` = `3.0.10` == tag |
| 签名 | `Developer ID Application: Serhiy Mytrovtsiy (RP2S87B72W)` == 已安装 copy 的 Team |
| 公证 | `spctl -a -t install` → `accepted / source=Notarized Developer ID` |

这正是此前规则留空 `installAssetPattern` 的原因（注释写着 "Team ID isn't confirmed
against the installed copy"）——现在确认过了，故开启一键。

## 已知问题
- Stats 自带 in-app updater。它没有 Sparkle feed，所以不受"让位给自更新器"那条路径
  影响；一键安装与它并行存在，谁先装上算谁的，不会冲突（都是原地换 bundle）。

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
