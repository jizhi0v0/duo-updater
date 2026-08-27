# Granola

## 基本信息
- Bundle ID: `com.granola.app`
- Team ID: `QZ7DHHLN25`
- 已验证版本: `7.478.0`
- 自更新机制: electron-builder

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.granola.app` | latest-mac.yml `version` | ✓ |

## 更新检测
- 端点: `https://api.granola.ai/v1/check-for-update/latest-mac.yml`。
- 生产验证: mounted DMG `7.478.0 → 7.478.0`, stable/up-to-date。
- `releaseDate` 写入 Release Log。

## Changelog
- 暂无公开、逐版本的稳定 changelog 页面。

## 一键安装
- 状态: ✓，universal DMG。
- 安全: notarized，Team `QZ7DHHLN25`；URL 由已解析版本生成。

## 已知问题
- manifest 的 sha512 对应 zip，不对应所选 DMG，由签名/Team gate 校验。

## 建议下一步
1. 监控 CloudFront 路径格式是否变化。

