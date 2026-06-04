# Ghostty

## 基本信息
- Bundle ID: `com.mitchellh.ghostty`
- Team ID: 未复核（local bundle signature not checked）
- 已安装版本: 1.3.1（本机 `/Applications/Ghostty.app`）
- 自更新机制: 自研 / Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | ○      | ○           |
| **tip**      | —       | —        | —   | ✗      | ✗           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **unknown**。`HomebrewCaskSource` 会因为 cask `auto_updates: true` 返回 nil；当前没有 `GitHubReleaseRule` 或 `VendorProbeRecipe`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mitchellh.ghostty` | — | — | — | C ✓ / 检测未接 |
| tip     | `com.mitchellh.ghostty` | 共享 | 无 | GitHub prerelease/tip | ✗ |

## 更新检测
- 源: 当前无可靠检测源；local bundle has no `SUFeedURL`.
- 端点: 未接入。
- 注意事项: Tip/nightly 与 stable 同 bundle id、同名安装且无本机检测信号，不能安全区分 channel。

## Changelog
- 来源: `ChangelogRecipe` + `ChangelogCatalog`
- 跟随 channel: 否，只覆盖 stable release notes
- Recipe 状态: 已有，两阶段 index → 最新版本页（`https://ghostty.org/docs/install/release-notes`）

## 一键安装
- 状态: 仅 notes
- 格式: 未实现
- 阻塞: 先需要可靠检测源；tip channel 不可接。

## 已知问题
- Homebrew 已安装也不会作为检测源，因为 `auto_updates` cask 按架构必须让位。

## 建议下一步
1. stable 检测如需接入，走 `/fragile-recipe Ghostty`（VendorProbe 或 GitHub path），必须先确认版本端点/标签与 `CFBundleShortVersionString` 完全同构。
2. tip channel 保持 BLOCKED，除非未来真实 bundle 暴露可靠 channel marker。
