# Perplexity Mac

## 基本信息
- Bundle ID: `ai.perplexity.macv3`
- Team ID: `7S8W4W365S`
- 已验证版本: short `26.31.1`, build `69`
- 自更新机制: Sparkle

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | ✗        | —   | —      | —           |

当前生效源: **Sparkle**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `ai.perplexity.macv3` | `SUFeedURL` | ✓ |

## 更新检测
- Appcast: `https://macos-download.perplexity.ai/appcast.xml`。
- feed short/build 与真实包完全同构。

## Changelog
- 由 Sparkle item description 提供；无专用 recipe。

## 一键安装
- 状态: 仅检测。
- 阻塞: 2026-08-17 下载的 DMG 为同 Team Developer ID，但 `spctl` 报 `Unnotarized Developer ID`。

## 已知问题
- 在上游恢复公证前，安装安全闸会拒绝替换。

## 建议下一步
1. 新版本发布后复查公证状态。

