# Calibre

## 基本信息
- Bundle ID: `net.kovidgoyal.calibre`
- Team ID: `NTY7FVCEKP`（downloaded cask verified 2026-06-04）
- 已验证版本: 9.9.0 (`CFBundleVersion` 9.9.0)
- 自更新机制: Homebrew cask（`auto_updates` 未声明，即 false）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew** only when the installed app came from Homebrew; direct installs without Sparkle remain out of scope.

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.kovidgoyal.calibre` | — | brew provenance | Homebrew cask | ✓ |

## 更新检测
- 源: `HomebrewCaskSource`
- 端点: Homebrew cask `calibre`
- 注意事项: downloaded cask bundle has no `SUFeedURL`; source only answers for locally brew-installed copies.

## Changelog
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有，`https://calibre-ebook.com/whats-new`

## 一键安装
- 状态: Homebrew-managed only
- 格式: cask app
- 阻塞: direct-install detection not implemented.

## 已知问题
- `docs/app-onboarding-status.md` already notes Calibre rides Homebrew detection.

## 建议下一步
1. No custom detection needed for brew-installed Calibre.
2. If direct-download Calibre should be supported, audit vendor update metadata first and then use `/fragile-recipe Calibre`.
