# Discord

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/ptb/canary 三 channel 全检测**

## 基本信息
- Bundle ID: `com.hnc.Discord`（PTB / Canary 独立：`com.hnc.DiscordPTB` / `com.hnc.DiscordCanary`）
- 自更新机制: Discord 自研 host updater（桌面端内置）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **ptb**      | —       | —        | —   | —      | ✓           |
| **canary**   | —       | —        | —   | —      | ✓           |

当前生效源: **VendorProbe**（每 channel 独立 manifest 端点）

## Channel 详情（Pattern A — 独立安装，各自 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.hnc.Discord`       | 独立 | bundle id 无后缀 → stable  | 独立端点 | ✓ |
| ptb     | `com.hnc.DiscordPTB`    | 独立 | bundle id `.PTB` 后缀 + 名称 "Discord PTB" → `.ptb` | 独立端点 | ✓ |
| canary  | `com.hnc.DiscordCanary` | 独立 | bundle id `.Canary` 后缀   | 独立端点 | ✓ |

PTB 无 `<sparkle:channel>`/版本后缀，靠名称中独立词 `"PTB"` 触发 `ReleaseChannel.ptb`（`channelWord` 表）。

## 更新检测
- 源: VendorProbe（`mode: .responseBody`）
- 端点: `https://updates.discord.com/distributions/app/manifests/latest?channel={stable|ptb|canary}&platform=osx&arch=x64`
- version 从 distro url 路径段提取（`stable.dl2.discordapp.net/.../osx/universal/<X.Y.Z>/` 等）
- JSON 中 `host_version:[0,0,393]` 三元组无法直接用（三个 capture group 问题），URL 路径是唯一可靠来源

## Changelog
- changelogURL: `https://discord.com/blog`（三 channel 共用，WebView 内嵌）
- 无 ChangelogRecipe

## 一键安装
- 状态: **已接入**（三 channel）。此前记为「仅检测」，是旧策略的残留。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- Squirrel/Electron 应用另有一层保护：`SelfUpdaterStaging` 读
  `~/Library/Caches/<bundleID>.ShipIt/`，若 app 自己已把新版下载解包、只等重启交换，
  `UpdatePolicy.canAutoInstall` 返回 false 让位给 Relaunch —— 既不重复下载，也不会撞上
  待执行的 ShipIt 交换。这一层由扫描时是否存在 `Contents/Frameworks/Squirrel.framework` 决定。

## channel-verify 状态
- ✓ **三 channel 全部已验证 2026-06-04**（官方 dmg 只读挂载、未安装）。stable `com.hnc.Discord` 0.0.393 / ptb `com.hnc.DiscordPTB` 0.0.237 / canary `com.hnc.DiscordCanary` 0.0.1136 各自 VendorProbe 应答=dmg 版本，无幽灵更新；channel 由 bundle id 后缀直读。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify /tmp/discord-stable.dmg --expect stable
swift run --package-path application-test channel-verify /tmp/discord-ptb.dmg    --expect ptb
swift run --package-path application-test channel-verify /tmp/discord-canary.dmg --expect canary
```
