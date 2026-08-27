# Keka

## 基本信息
- Bundle ID: `com.aone.keka`
- Team ID: needs-verify（download stalled at 21 MB incomplete on 2026-06-04）
- 已验证版本: needs-verify
- 自更新机制: Sparkle / Homebrew cask `auto_updates`

## 覆盖矩阵

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ○       | ✗        | —   | —      | —           |

当前生效源: **needs-verify**. Homebrew cask says `auto_updates: true`, but the downloaded app bundle was not successfully verified in this audit.

## 更新检测
- 源: expected `SparkleAppcastSource`, pending downloaded-bundle proof
- Homebrew: cask `keka`, `auto_updates: true`, so Homebrew defers.
- Changelog: Sparkle/appcast-provided notes only; no custom recipe.

## 一键安装
- 状态: needs-verify
- 阻塞: Homebrew/GitHub asset download stalled; only incomplete `Keka-1.6.5.dmg.incomplete` was present.

## 建议下一步
1. Re-run download verification for Keka.app and confirm `CFBundleIdentifier`, Team ID, and `SUFeedURL` before marking Sparkle ✓.
