# Vivaldi

## 基本信息
- Bundle ID: `com.vivaldi.Vivaldi`
- Team ID: `4XF3XNRN6Y`（downloaded cask verified 2026-06-04）
- 已验证版本: 8.0.4033.35 (`CFBundleVersion` 8.0.4033.35)
- 自更新机制: Sparkle / Homebrew cask `auto_updates`

## 覆盖矩阵

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | ✗        | —   | —      | —           |

当前生效源: **Sparkle** for installed direct app with `SUFeedURL`.

## 更新检测
- 源: `SparkleAppcastSource`
- 已验证 `SUFeedURL`: `https://update.vivaldi.com/update/1.0/public/mac/appcast.xml`
- Homebrew: cask `vivaldi`, `auto_updates: true`, so Homebrew defers.
- Changelog: Sparkle/appcast-provided notes only; no custom recipe.

## 一键安装
- 状态: Sparkle path only
- 阻塞: 无。

## 建议下一步
1. No code change.
