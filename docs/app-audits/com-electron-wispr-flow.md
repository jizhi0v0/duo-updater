# Wispr Flow

## 基本信息
- Bundle ID: `com.electron.wispr-flow`
- Team ID: `C9VQZ78H85`
- 已验证版本: `1.6.531`
- 自更新机制: 自研 `RELEASES.json` / ShipIt

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.electron.wispr-flow` | `currentRelease` | ✓ |

## 更新检测
- 端点: `https://dl.wisprflow.com/wispr-flow/darwin/arm64/RELEASES.json`。
- 生产验证: mounted DMG `1.6.531 → 1.6.531`, stable/up-to-date。

## Changelog
- feed 的 `notes` 当前为空；无稳定公开 changelog 页面。

## 一键安装
- 状态: 仅检测。
- 阻塞: Intel/arm64 分离，当前 `VendorInstallSpec` 不能按 host architecture 选包。

## 已知问题
- 两架构当前同版本；若未来分叉需拆分来源。

## 建议下一步
1. Vendor installer 支持架构模板后再启用一键更新。

