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
- 状态: **已启用**（2026-08-29），`.bodyPattern` 取同一份响应里的
  `"url": "…/Devin-darwin-arm64-<version>.dmg"`。url 与 version 出自同一份文档，
  既不用拼模板也不用赌顺序；正则要求 `.dmg` 结尾，vendor 加字段也不会漂到别的绝对 URL 上。
- 无 checksum: 响应里的 `sha256hash` 是 SHA-256 十六进制，而 `checksumPattern` 验的是
  base64 SHA-512，接错摘要会让每次安装都失败。完整性由签名 + Team 闸承担。
- 包实测 2026-08-29（3.8.20）: 挂载后 `com.exafunction.windsurf`,
  `Developer ID Application: EXAFUNCTION, INC. (83Z2LHX6XW)`, spctl accepted / Notarized,
  已 staple, `lipo -archs` = arm64。
- 端到端实测 2026-08-29: 装 3.7.25（旧 dmg URL 从 homebrew-cask `devin-desktop` 历史取得）
  → `duo check` 报 3.8.20 → `duo install` → 磁盘 3.8.20，Team 不变，`duo check` 转 up-to-date。

## 已知问题
- 产品已从 Windsurf 改名 Devin，但沿用旧 bundle ID 和更新域名。
- 早先此处写"检测是架构中立的、故不接一键"，与同一条 recipe 的 probe URL 自相矛盾：
  端点是 `/api/update/darwin-arm64-dmg/…`，响应自己的 `displayName` 也写着
  "macOS for Apple Silicon (.dmg)"。架构在检测这步已经定死。

## 建议下一步
1. 若新增 next/beta bundle，需真实验包后单独建 channel。

