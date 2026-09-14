# Vivaldi

## 基本信息
- Bundle ID: `com.vivaldi.Vivaldi`
- Team ID: `4XF3XNRN6Y`（downloaded cask verified 2026-06-04）
- 已验证版本: 8.0.4033.35 (`CFBundleVersion` 8.0.4033.35)
- 自更新机制: Sparkle / Homebrew cask `auto_updates`

## 覆盖矩阵

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | ✗        | —   | —      | —           |

当前生效源: **Sparkle** for installed direct app with `SUFeedURL`.

## 更新检测
- 源: `SparkleAppcastSource`
- 已验证 `SUFeedURL`: `https://update.vivaldi.com/update/1.0/public/mac/appcast.xml`
- Homebrew: cask `vivaldi`, `auto_updates: true`, so Homebrew defers.
- Changelog: Sparkle/appcast-provided notes only; no custom recipe.

## 一键安装
- 状态: Sparkle path only
- 阻塞: 无。

## 建议下一步
1. No code change.

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-vivaldi-Vivaldi.swift — Snapshot VendorProbe（一键 `.tar.xz` 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（enclosure 是 universal `.tar.xz`、bundle id、Team、spctl 接受，checked 2026-08-09），被核对的版本 8.2.4126.4 搬到这里。

One-click verified 2026-08-09 on 8.2.4126.4: the enclosure is a universal
`.tar.xz` holding `Vivaldi Snapshot.app`, bundle id
com.vivaldi.Vivaldi.snapshot, Team 4XF3XNRN6Y, spctl "Notarized Developer
ID". `.tarGz` covers xz — see the ImageOptim note.

### Recipes/com-vivaldi-Vivaldi.swift — Snapshot VendorProbe（检测已被 Sparkle 接管）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论和日期（真实 Snapshot bundle 声明的 `SUFeedURL` 就是这个地址，所以 Sparkle 先应答），被量的 build 8.2.4133.31 搬到这里。

DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender and
ImageOptim. Measured on the real 8.2.4133.31 bundle (2026-08-31): it
declares `SUFeedURL = https://update.vivaldi.com/update/1.0/snapshot/mac/
appcast.xml`, this exact address, so Sparkle answers first.
