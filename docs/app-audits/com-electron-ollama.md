# Ollama

## 基本信息
- Bundle ID: `com.electron.ollama`
- Team ID: 未复核（local bundle signature not checked）
- 已安装版本: 0.24.0（本机 `/Applications/Ollama.app`；Homebrew cask 当前为 0.30.4）
- 自更新机制: Electron / Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | ○      | ○           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **unknown**。`auto_updates: true` cask 会让 Homebrew 返回 nil；当前只有 changelog coverage。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.electron.ollama` | — | — | GitHub releases | C ✓ / 检测未接 |

## 更新检测
- 源: 当前无 `VendorProbeRecipe` / `GitHubReleaseRule`；local bundle has no `SUFeedURL`.
- 端点: 可调查 GitHub Releases 或 vendor endpoint。
- 注意事项: 本机版本 0.24.0 与 cask 0.30.4 已出现明显漂移，说明 `auto_updates` cask 不能当检测源。

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
