# Devin Desktop

## 基本信息
- Bundle ID: `com.exafunction.windsurf`
- Team ID: `83Z2LHX6XW`
- 已验证版本: `3.7.25`
- 自更新机制: VS Code fork 自研 API / ShipIt

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.exafunction.windsurf` | `windsurfVersion` | ✓ |

## 更新检测
- 端点: `https://windsurf-stable.codeium.com/api/update/darwin-arm64-dmg/stable/latest`。
- 只解析 `windsurfVersion=3.7.25`；拒绝误取 VS Code 基线 `productVersion=1.126.0`。
- 生产验证: mounted DMG stable/up-to-date。

## Changelog
- `https://windsurf.com/editor/releases/`。

## 一键安装
- 状态: 仅检测。
- 阻塞: API/资产按架构拆分，当前 Vendor 安装规格不能按 host 选包。

## 已知问题
- 产品已从 Windsurf 改名 Devin，但沿用旧 bundle ID 和更新域名。

## 建议下一步
1. 若新增 next/beta bundle，需真实验包后单独建 channel。

