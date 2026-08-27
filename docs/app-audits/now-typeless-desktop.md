# Typeless

## 基本信息
- Bundle ID: `now.typeless.desktop`
- Team ID: `947QKAND4W`
- 已安装版本: 1.8.0 (build 1.8.0.109)
- 自更新机制: Electron + electron-updater (Squirrel.Mac framework bundled)

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**

- Sparkle: 无 `SUFeedURL`（electron-updater，非 Sparkle.framework）。
- Homebrew: cask `typeless` 存在但 `auto_updates true` → `HomebrewCaskSource` 返回 nil，不应答。
- MAS: 无 `_MASReceipt`。
- GitHub: 无公开 release 仓库映射。

## Channel 详情

| Channel | Bundle ID            | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|----------------------|----------|---------|---------|------|
| stable  | now.typeless.desktop | 单一      | —       | —       | ✓    |

只有 stable 一条轨：cask 无 `@beta`/`@nightly` 变体，官网/feed 无其它渠道。

## 更新检测
- 源: VendorProbe（electron-builder feed）
- 端点: `https://typeless-static.com/desktop-release/arm64-mac.yml`（x64 为 `latest-mac.yml`，按仓库 Apple-Silicon 约定只探 arm64）
- 版本方案: feed `version: 1.8.0` = 安装版 `CFBundleShortVersionString 1.8.0`（marketing），**不**比 build `1.8.0.109` → 无 `versionIsBuild`。end-to-end `channel-verify` 实测 verdict「up to date」，无幽灵更新。
- 注意事项: changelog 页会提前几天列出未发布版本（如 1.9.0 标 2026-06-23），但「有更新」只由 GA electron-builder feed 门控，changelog 仅作展示。

## Changelog
- 来源: `https://www.typeless.com/help/release-notes/macos`（**原先猜 /changelog /releases /whats-new 全 404；正确路径在 help center 下**）
- 结构: Next.js SSG，整份 release notes JSON **base64+gzip 塞在 `__NEXT_DATA__.props.pageProps.compressedData`**（`<version> -> <locale> -> {date, features:[{title, content}]}` map，content 是带首图的 markdown），正则够不到。
- 跟随 channel: —（单轨）
- Recipe 状态: **已接入** — 新增 `StructuredFormat.typelessReleaseNotes`：解 `__NEXT_DATA__` → base64 → gunzip（新 `GzipDecode` helper，Apple Compression framework 跑裸 DEFLATE）→ 按 semver 降序出富 Entry（首图 + 正文 block，含 inline 图片）。`maxEntries: 12`。`VendorProbe.changelogURL` 指同页作 WebView 兜底。

## 一键安装
- 状态: 支持
- 格式: dmg（`Typeless-<ver>-arm64.dmg`，同 feed 内 base64 sha512 校验 + VendorInstaller 强制同 Team 门 947QKAND4W）
- 阻塞: 无

## 已知问题
- 无。

## 建议下一步
1. 已接入并部署：VendorProbe + 一键 dmg + 结构化 changelog（含 inline 图片）。全链路绿。
2. 脆弱点: changelog 依赖 `compressedData` 仍是 base64+gzip 且 `__NEXT_DATA__` 结构不变；任一改了 `StructuredChangelogDecoder.decodeTypeless` 会返回 nil → 自动回退到 `changelogURL` WebView，不崩。
