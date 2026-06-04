# Zed

> 审计日期 2026-06-04 · 模式 REPORT（部分接入）· 结论：**Preview channel 已检测（GitHub）；Stable channel 版本检测缺口（仅有 Changelog）**

## 基本信息
- Bundle ID (stable): `dev.zed.Zed`（Preview 独立：`dev.zed.Zed-Preview`）
- Homebrew cask: `zed`（`auto_updates: true`）→ HomebrewCaskSource 落穿
- 自更新机制: Zed 内置更新器（自研）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ?       | ✗(auto)  | —   | —      | ○(缺口)     |
| **preview**  | —       | —        | —   | ✓      | —           |

当前生效源:
- stable: **未知**（Homebrew auto_updates 落穿，无 VendorProbe，无 GitHub rule；若有 `SUFeedURL` 则 Sparkle 接管，否则为 "unknown"）
- preview: **GitHub** (`dev.zed.Zed-Preview`，`usePrereleases: true`，pattern `v([0-9]+\.[0-9]+\.[0-9]+)-pre`)

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `dev.zed.Zed`         | 独立 | — | ⚠️ 版本检测未确认 |
| preview | `dev.zed.Zed-Preview` | 独立 | bundle id `-Preview` 后缀 → `.preview` | ✓ |

## 更新检测
- stable: **缺口**
  - `brew cat zed` 显示 cask URL 形如 `https://zed.dev/api/releases/stable/<ver>/Zed-aarch64.dmg`
  - 潜在端点: `https://zed.dev/api/releases/stable/latest` 或类似 redirect；未验证，未加 VendorProbe
  - 若 Info.plist 有 `SUFeedURL`，SparkleAppcastSource 可自动接管（需安装实机验证）
- preview: GitHub `zed-industries/zed`，扫 prereleases，取第一个匹配 `v.*-pre` 的 tag

## Changelog
- stable: ChangelogRecipe ✓（`zed.dev/releases/stable`，id-锚点结构）
- preview: ChangelogRecipe ✓（`zed.dev/releases/preview`，相同结构）

## 一键安装
- 仅检测（两 channel 均无 installAssetPattern / install 字段）

## 建议下一步
1. 安装 Zed.app，确认是否有 `SUFeedURL`（若有则 SparkleAppcastSource 自动覆盖，stable 版本检测无缺口）
2. 若无 Sparkle，为 `dev.zed.Zed` 加 VendorProbe：端点 `https://zed.dev/api/releases/stable/<latest>` 或 redirect，pattern 待验证后走 `/fragile-recipe Zed stable`
3. 运行 `channel-verify` 确认 preview 在真实 bundle 上检测正确

## channel-verify 状态
- ✓ **preview 已验证 2026-06-04**（本机 `--scan`，`dev.zed.Zed-Preview` 1.6.0 → detect=preview；源是 GitHub `zed-industries/zed` prerelease，live 确认 newest prerelease `v1.6.0-pre`=installed）。
- ⚠️ **stable 缺口已在真实 bundle 上坐实**：官方 `dev.zed.Zed` 1.5.3 dmg 挂载 → detect=stable ✓，但 **无任何更新源**（VendorProbe miss，GitHub 规则只覆盖 prerelease）。→ 需补 stable GitHubReleaseRule 或 VendorProbe。证据：`application-test/records/dev-zed-Zed.md`
