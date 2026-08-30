# Figma

## 基本信息
- Bundle ID: `com.figma.Desktop` (stable) · `com.figma.DesktopBeta` (beta)
- Team ID: `T8RA8NE3B7` (Figma, Inc.) — stable 与 beta 同签名
- 已安装版本: stable 126.4.11（最新 126.4.13）
- 自更新机制: Electron / Squirrel（应用自带）。无 Sparkle（无 `SUFeedURL`）。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | (cask `figma` auto_updates→fall-through) | — | — | ✓ 检测+一键安装 |
| **beta**     | —       | (cask `figma@beta`) | — | — | ✓ 检测+一键安装 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.figma.Desktop`     | 独立 | bundle id / 名称 | — | ✓ |
| beta    | `com.figma.DesktopBeta` | 独立 | 名称 "Figma Beta" → `.beta`（真机 channel-verify 确认） | Pattern A 天然隔离 | ✓ |

**用户的三个问题：**
1. **有独立渠道 app 吗？** 有。Figma Beta 是**完整独立 app**（独立 bundle id、独立
   "Figma Beta.app"、独立端点）。**Pattern A（独立安装）**，与 stable 并存。
   > ⚠️ 旧 `CHANNEL_COVERAGE_TODO` 写的"应用内 feature flag、无独立 bundle"是**错的**，本次更正。
2. **能在 app 内切换渠道吗？** 不能。Beta 是单独下载安装的另一个 app，没有 in-app toggle。
3. **changelog 跟随渠道吗？** 不跟随，也无需跟随：`figma.com/release-notes` 是
   **全产品**公告页（Design / Make / FigJam），stable 与 beta 共用一份；Figma 不提供
   独立的 beta release notes。

## 更新检测
- 源: VendorProbe（`responseBody` 模式）
- 端点:
  - stable: `https://desktop.figma.com/mac-arm/RELEASE.json`
  - beta:   `https://desktop.figma.com/mac-arm/beta/RELEASE.json`
- 响应结构（两条线一致）: `{"version":"126.4.13","name":"…","rollback":true,"url":"https://desktop.figma.com/mac-arm/Figma-126.4.13.zip"}`
- versionPattern: `"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)"` —
  与 `CFBundleShortVersionString` 同方案（无 build/marketing 陷阱）。

## Changelog
- 来源: ChangelogRecipe(`com.figma.Desktop`) 抓 `figma.com/release-notes`（结构化）；
  beta 经 VendorProbe 的 `changelogURL` 走同一页（web view）。
- 跟随 channel: 否（全产品公告页，无 per-channel 区分）
- Recipe 状态: stable 已有；beta 共用，无需独立 recipe。

## 一键安装
- 状态: **支持**（stable + beta）
- 格式: zip
- URL 来源: 探测响应体里的 `"url":"…/…​.zip"`（`VendorInstallSpec.bodyPattern`）
- Team 门控: `T8RA8NE3B7` — 2026-06-06 真机验证下载产物（stable `Figma-126.4.13.zip`
  与 beta `FigmaBeta-126.6.2.zip`）均为 notarized Developer ID，bundle id 与各自安装一致。

## 真机验证（Phase 3¾）
证据已折入本文档。两个 channel 都跑过
`channel-verify` 绿灯：stable → UPDATE 126.4.11→126.4.13；beta → up to date 126.6.2。

## 已知问题
- 无。（Figma 自身也会 Squirrel 自更新；我们的一键安装是手动 fallback，同渠道、同签名，
  不会跨渠道混装。）

## 建议下一步
- 已完成。后续仅在端点结构或签名变化时复核 recipe。
