# AionUi

## 基本信息
- Bundle ID: `com.aionui.app`
- Team ID: `52JQX2HUSC`
- 已验证版本: `2.1.56`
- 自更新机制: electron-builder

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.aionui.app` | electron-builder manifest | ✓ |

## 更新检测
- 端点: `https://static.aionui.com/releases/latest-arm64-mac.yml`。
- 生产验证: mounted DMG `2.1.56 → 2.1.56`, stable/up-to-date。

## Changelog
- GitHub Releases 页面作为人工说明入口。

## 一键安装
- 状态: 仅检测。
- 阻塞: Intel/arm64 分离，Vendor 安装规格尚不能按 host 选包。

## 已知问题
- `latest-mac.yml` 是 x64；arm64 必须使用 `latest-arm64-mac.yml`。

## 建议下一步
1. 架构感知安装规格落地后启用对应 DMG 与 sha512。

