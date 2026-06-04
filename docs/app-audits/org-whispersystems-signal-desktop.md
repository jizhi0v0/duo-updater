# Signal Desktop

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel 已检测**

## 基本信息
- Bundle ID: `org.whispersystems.signal-desktop`（Beta 独立：`org.whispersystems.signal-desktop-beta`）
- 自更新机制: electron-updater（自研，Squirrel-like）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**     | —       | ✗(auto)  | —   | —      | ✓           |

当前生效源: **VendorProbe**（各自 electron-builder yml 端点）

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `org.whispersystems.signal-desktop`      | 独立 | bundle id 无后缀 → stable      | ✓ |
| beta    | `org.whispersystems.signal-desktop-beta` | 独立 | bundle id `-beta` 后缀 → .beta | ✓ |

## 更新检测
- stable: `https://updates.signal.org/desktop/latest-mac.yml` → `version: X.Y.Z`
- beta:   `https://updates.signal.org/desktop/beta-mac.yml` → 同 pattern
- 仅检测（Signal 自更新）

## Changelog
- changelogURL: `https://github.com/signalapp/Signal-Desktop/releases`（两 channel 共用）
- 无 ChangelogRecipe

## 一键安装
- 仅检测

## channel-verify 状态
- ✓ **两 channel 已验证 2026-06-04**（官方 zip 解压后对真实 `.app` 跑 channel-verify、未安装）。stable `org.whispersystems.signal-desktop` 8.13.0 / beta `…-beta` 8.14.0-beta.1 各自 VendorProbe（latest-mac.yml / beta-mac.yml）应答=installed，无幽灵更新。证据：`application-test/records/org-whispersystems-signal-desktop.md`
