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
- 状态: **已启用**（2026-08-29），`.versionTemplate` →
  `https://static.aionui.com/releases/{version}/AionUi-{version}-mac-arm64.zip`，
  带 sha512 校验和闸。
- **为什么不能用 `.bodyPatternRelative`**: manifest 里 `path:` / `files[].url` 是裸文件名，
  但它们**不相对 manifest 自己的目录**解析。2026-08-29 实测:
  `…/releases/AionUi-2.1.61-mac-arm64.zip` → 403 AccessDenied，
  `…/releases/2.1.61/AionUi-2.1.61-mac-arm64.zip` → 200。真实布局把版本插成一层目录，
  相对解析会产出一个永远下不动的链接。
- **checksum 取顶格的那个**: 正则锚在第 0 列，避开 `files:` 下缩进的逐资产摘要（那份
  同时列了 dmg，而缩进列表里第一条恰好是 zip 的，纯属排序巧合）。顶层摘要按定义对应
  `path:`，也就是模板拼出的那个 zip。实测 `openssl dgst -sha512 -binary` 与 manifest 值逐字节一致。
- 包实测 2026-08-29: `com.aionui.app` 2.1.61,
  `Developer ID Application: AionUi Inc. (52JQX2HUSC)`, spctl accepted / Notarized, 已 staple, `lipo -archs` = arm64。
- 端到端实测 2026-08-29: 装 2.1.56 → `duo check` 报 2.1.61 → `duo install`（日志里多一步
  `verifyingSignature`，即校验和闸真的跑了）→ 磁盘 2.1.61，`duo check` 转 up-to-date。

## 已知问题
- `latest-mac.yml` 是 x64；arm64 必须使用 `latest-arm64-mac.yml`。
- 早先此处记的阻塞（"要按 host 选包"）不成立：本 recipe 读的就是 arm64 manifest，
  Intel 那套没有任何宿主能来要（arm64-only，见 `App/project.yml`）。

## 建议下一步
1. 若 vendor 改用带 hash 的资产名，模板会 404 大声失败；届时改模板。

