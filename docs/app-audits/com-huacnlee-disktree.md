# Disktree NSH — 身份核对

核对日期：2026-11-15。此记录回答与已接入 disktree 的关系，尚未新增配方或执行安装。

## 本机副本

- 路径：`/Applications/Disktree NSH.app`；显示名 `Disktree`。
- Bundle ID：`com.huacnlee.disktree`；short/build：`0.1.7` / `0.1.7`。
- 签名：ad-hoc，无 Team ID；没有 `SUFeedURL`。
- `Contents/Resources/nsh/app.json` 声明同一 ID 与版本。
- `Contents/Resources/nsh/assets/nsh-updater.json` 声明
  `github = huacnlee/disktree`，不是 `tobi/disktree`。

## 与已有支持项的关系

[huacnlee/disktree](https://github.com/huacnlee/disktree) 的 README 明确说明是受
[tobi/disktree](https://github.com/tobi/disktree) 启发、用 NSH 实现的独立 App。
GitHub 元数据 `fork=false`；本机的 NSH 资源、ID 和更新器配置与其一致。

已有配方 `io-github-tobi-disktree.swift` 只对应 tobi 的 Rust + GPUI App，
ID `io.github.tobi.disktree`。不能把两者加入 `BundleIDMigration`，否则会把一个产品
替换成另一实现。它需要独立 recipe family，不能用新旧 ID 的别名覆盖。

## 当前覆盖与可接入方向

- 检测：本轮本机扫描为 unknown；尚无这个 ID 的配方。
- Changelog：可评估读取 `huacnlee/disktree` GitHub Release 正文。
- 一键：尚未实现或验证。上游最新非 prerelease 为 `v0.1.8`，发布普通 macOS
  `disktree-v0.1.8-aarch64-apple-darwin.tar.gz`、独立 updater 归档，以及 GitHub
  SHA-256 digest；不能把 updater 归档误选作普通安装包。
- 本机无 Team ID，不能直接按 Developer ID 路线安装；项目已有
  `.publishedDigestOnly` 能力，可以在读取真实新包、核对 ID、签名标识、目录结构
  及旧→新数据保留后评估。当前不能据此声称一键已可用。
- 其余分发源与其他渠道未在此身份调查中完整审计。

## 已有 ID 迁移案例

项目 `Models/BundleIDMigration.swift` 已处理 WorkBuddy、PrintCraft→PdfCraft、
WhatCable、Cork、MusicBrainz Picard、SwitchHosts、Museeks、Rclone UI 等真正的
上游 ID 变更。迁移有方向、签名团队和版本边界；不是仅凭名称相同就兼容。
