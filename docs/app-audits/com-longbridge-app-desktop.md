# Longbridge Desktop（长桥桌面版）

## 基本信息
- Bundle ID: `com.longbridge.app.desktop`
- Team ID: `45NG8MW7WK`（LONG BRIDGE TECHNOLOGY HK LIMITED）
- 已验证版本: `0.19.1`（build `20260820.080114`）
- 自更新机制: 自研；无 `SUFeedURL`

## 覆盖矩阵

> ✓ = 已接入　○ = 可接入（未实现）　✗ = 已调查不可行　— = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | —      | ✓           |
| **preview**  | —       | —        | —   | —      | ✗（已停更） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。

Homebrew 的 `longbridge-pro` 是另一款应用 Longbridge Pro，不是本接入对象；Mac App
Store 搜索没有 Longbridge Desktop。公开 stable 分发由厂商自己的 release manifest 提供。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|-----------|----------|------|
| stable | `com.longbridge.app.desktop` | 独立 | 默认 stable | ✓ |
| preview（旧） | `com.longbridge.app.desktop.preview` | 独立 | bundle id / 显示名 / 版本后缀 | ✗ 已停更，不接 |

旧 preview 实包 `0.15.0-preview.0` 已验证为独立 Bundle ID，生产
`ReleaseChannel.detect()` 正确识别为 `.preview`；stable 配方不会跨渠道命中它。

## 更新检测
- 源: VendorProbe。
- 端点: `https://assets.lbkrs.com/github/release/longbridge-desktop/stable/latest.json`。
- 版本字段: 顶层 `version`，与实包 `CFBundleShortVersionString` 完全一致；不使用时间戳式
  `CFBundleVersion`。
- 发布时间: 顶层 `published_at`，写入 Release Log。
- 生产验证: mounted stable DMG `0.19.1 → 0.19.1`，stable / up-to-date。

## Changelog
- 来源: 同一份官方 JSON 的 `release_notes.en`，固定取英文作为默认。
- 状态: 原生结构化 changelog，JSON 解码后解析 Markdown 标题和条目。
- 网页兜底: `https://longbridge.com/desktop/release-notes/`。
- 限制: `latest.json` 只包含当前版本，因此原生视图一次显示一版；官网保留历史版本。

## 一键安装
- 状态: ✓（Apple Silicon）。
- 格式: 自包含 DMG；manifest 精确选择 `macos-aarch64.dmg`。
- 安全: 官方 JSON 的 SHA-256 与下载字节一致；应用代码签名有效，Team
  `45NG8MW7WK`，Gatekeeper 判定 `Notarized Developer ID`。
- Intel: manifest 虽提供 `macos-x86_64.dmg`，当前 VendorInstallSpec 不支持按运行架构
  分支选择 URL，因此本次不宣称 Intel 一键安装覆盖。

## 已知问题
- preview 渠道已经停止更新；保留为明确的死轨记录，不添加旧 endpoint recipe。
- 官方 manifest 发布十六进制 SHA-256，而 VendorInstallSpec 的内联 checksum 闸当前只支持
  base64 SHA-512；运行时仍由强制签名 / Team ID 闸保护。

## 建议下一步
1. 监控 stable manifest 的 `version`、`published_at`、`assets[].url` 字段形状。
2. 若 VendorInstallSpec 将来支持按 host architecture 选 URL，再补 Intel 一键安装。

