# AppCleaner

## 基本信息
- Bundle ID: `net.freemacsoft.AppCleaner`
- Team ID: `X85ZX835W9`（downloaded cask verified 2026-06-04）
- 已验证版本: 3.6.8 (`CFBundleVersion` 4332)
- 自更新机制: Sparkle（release notes URL 来自 Sparkle feed）；Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | ✗        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。Downloaded cask verification confirmed `SUFeedURL`; Homebrew defers because cask `auto_updates: true`.

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.freemacsoft.AppCleaner` | — | `SUFeedURL` | Sparkle appcast | ✓ |

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: verified `SUFeedURL` `https://freemacsoft.net/appcleaner/updates.xml`
- 注意事项: none.

## Changelog
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有，`https://freemacsoft.net/appcleaner/releasenotes.html`

## 一键安装
- 状态: 由 Sparkle installer path 决定；无 custom install recipe
- 格式: Sparkle enclosure
- 阻塞: 无。

## 已知问题
- 未对安装副本取证，但 downloaded cask bundle 已完成 Info.plist proof。

## 建议下一步
1. No code change.
