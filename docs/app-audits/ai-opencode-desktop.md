# OpenCode

## 基本信息
- Bundle ID: `ai.opencode.desktop`
- Team ID: `5NZ4Q7NXJ4`（downloaded cask verified 2026-06-04）
- 已验证版本: 1.15.13 (`CFBundleVersion` 1.15.13)
- 自更新机制: Electron / Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | ○      | ○           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **unknown**。README 中曾列为 `C`，但生产 registry 未找到 `ChangelogRecipe` 或 `ChangelogCatalog` 条目。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.opencode.desktop` | — | — | 未调查 | ○ |

## 更新检测
- 源: 未接入。
- 端点: 未调查。
- 注意事项: downloaded cask bundle has no `SUFeedURL`; Homebrew cask token 为 `opencode-desktop`，`auto_updates: true`，所以 Homebrew 不会提供检测。

## Changelog
- 来源: 未接入
- 跟随 channel: 未调查
- Recipe 状态: **缺失**。`rg "ai.opencode|opencode"` 只命中 audit backlog 和 Ollama fixture 文本。

## 一键安装
- 状态: 未接入
- 格式: 未调查
- 阻塞: 需要先确认版本检测或 changelog source。

## 已知问题
- 当前 bucket 标记与代码不一致：它不是实际的 changelog-covered app。

## 建议下一步
1. 先走 `/fragile-recipe OpenCode`（Changelog path）确认 release notes URL 和页面结构。
2. 如还要检测，继续走 `/fragile-recipe OpenCode`（VendorProbe path）并验证版本方案。
