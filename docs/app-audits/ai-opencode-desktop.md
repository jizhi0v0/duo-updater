# OpenCode Desktop

## 基本信息
- Bundle ID: `ai.opencode.desktop`
- Team ID: `5NZ4Q7NXJ4`
- 已验证版本: `1.18.18`（short/build 相同）
- 自更新机制: electron-builder / GitHub Releases

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | ✓      | —           |

当前生效源: **GitHub**。cask 为 `auto_updates:true`，Homebrew 不参与检测。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `ai.opencode.desktop` | GitHub stable tag `vX.Y.Z` | ✓ |

## 更新检测
- 源: `anomalyco/opencode` GitHub Releases。
- tag `v1.18.18` 与真实包 short/build `1.18.18` 同构。

## Changelog
- GitHub release body（优先）及既有 `ChangelogRecipe`。

## 一键安装
- 状态: ✓，host-native arm64/x64 DMG。
- 安全: arm64 DMG 已确认 notarized，Team `5NZ4Q7NXJ4`。

## 已知问题
- 无。

## 建议下一步
1. 保持 GitHub tag 与资产文件名 fixture 测试。

