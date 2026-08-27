# OpenChamber

## 基本信息
- Bundle ID: `dev.openchamber.desktop`
- Team ID: `5J7WJGPA2Q`
- 已验证版本: `1.18.4`
- 自更新机制: electron-builder / GitHub Releases

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | ✓      | —           |

当前生效源: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `dev.openchamber.desktop` | stable tag `vX.Y.Z` | ✓ |

## 更新检测
- 源: `openchamber/openchamber` GitHub Releases。
- tag、Info.plist short/build 均为 `1.18.4`。

## Changelog
- GitHub release body 内联。

## 一键安装
- 状态: ✓，host-native arm64/x64 DMG。
- 安全: arm64 DMG notarized，Team `5J7WJGPA2Q`。

## 已知问题
- 同一 release 有 mobile/VSIX/各平台资产，文件名正则必须保持完整锚定。

## 建议下一步
1. 保持 sibling asset 负例测试。

