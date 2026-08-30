# Ollama

## 基本信息
- Bundle ID: `com.electron.ollama`
- Team ID: 未复核（local bundle signature not checked）
- 观测版本: 0.24.0（审计当天 Homebrew cask 为 0.30.4）
- 自更新机制: Electron / Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | ✓      | ○           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`ollama/ollama` `/releases/latest`）。`auto_updates: true` cask 会让 Homebrew 返回 nil。2026-06-06 接入 `GitHubReleaseRule`，验证 latest zip 内 `.app` 自报 `0.30.6` 与 tag `v0.30.6` 同构。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.electron.ollama` | — | — | GitHub releases | C ✓ / 检测未接 |

## 更新检测
- 源: `GitHubReleaseRule`（`ollama/ollama`，默认 pattern 剥 `v` 前缀）；local bundle has no `SUFeedURL`.
- 端点: `https://api.github.com/repos/ollama/ollama/releases/latest`。
- 验证（2026-06-06）: `ollama.com/install.sh` 与 `ollama.com/download/Ollama.dmg` 均 307→ github `releases/latest/download`；latest zip 内 `.app` 自报 `CFBundleShortVersionString = 0.30.6`，与 tag `v0.30.6` 同构，无幽灵更新。
- 备选（未采用）: redirect-VendorProbe 抠最终 path 的 `v0.30.6`，可免 GitHub API 60/时限流；本次保留 API 方式（用户决定，2026-06-06）。
- 注意事项: 本机版本 0.24.0 与 cask 0.30.4 漂移，说明 `auto_updates` cask 不能当检测源。

## Changelog
- 来源: `ChangelogRecipe` + `ChangelogCatalog`
- 跟随 channel: 否
- Recipe 状态: 已有，GitHub releases page（`https://github.com/ollama/ollama/releases`）

## 一键安装
- 状态: 仅 notes
- 格式: 未实现
- 阻塞: 先需要检测 recipe。

## 已知问题
- 只有 release notes；更新状态仍会是 unknown。

## 建议下一步
1. 如需检测，走 `/fragile-recipe Ollama`（GitHubReleaseRule 或 VendorProbe），验证 GitHub tag/version 与 installed `CFBundleShortVersionString` 是否同构。
