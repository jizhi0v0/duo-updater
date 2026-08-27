# Msty Studio

## 基本信息
- Bundle ID: `MstyStudio`
- Team ID: `S6CF5A8MX9`
- 已验证版本: `2.9.7`
- 自更新机制: electron-builder generic provider

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `MstyStudio` | latest-mac.yml `version` | ✓ |

## 更新检测
- 端点: `https://next-assets.msty.studio/app/latest/mac/latest-mac.yml`。
- 生产验证: mounted DMG `2.9.7 → 2.9.7`, stable/up-to-date。

## Changelog
- `https://msty.ai/resources/changelog/studio/`。

## 一键安装
- 状态: 仅检测。
- 阻塞: manifest 同时列 x64/arm64，Vendor 安装规格不能按 host 安全选择。

## 已知问题
- Bundle ID 为无点形式 `MstyStudio`，不得按产品名推导成反向域名。

## 建议下一步
1. 架构感知安装规格落地后使用对应 DMG 与 sha512。

