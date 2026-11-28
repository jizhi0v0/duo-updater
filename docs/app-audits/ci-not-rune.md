# Rune Player

## 基本信息

- 项目：[Losses/rune](https://github.com/Losses/rune)，本地音乐播放器。
- GitHub macOS 直装包：`Rune.app`，bundle ID `ci.not.rune`，Team `LG57TUQ726`，Developer ID。Stable 与 Alpha 共用 ID。
- [Mac App Store](https://apps.apple.com/us/app/rune-player/id6738841909?mt=12)：`ci.not.rune.appstore`，通过商店收据和通用 App Store 源检测及更新。

## 覆盖矩阵

| 安装副本 | 检测 | 一键安装 | 结构化日志 |
|---|---|---|---|
| GitHub Stable | GitHub 正式发布 | 官方 universal DMG，同 Team 且签名通过 | 当前发布的 GitHub 正文 |
| GitHub 2.x Alpha | GitHub 带 `-alpha.N` 的对应发布 | 官方 universal DMG，同 Team 且签名通过 | 当前发布的 GitHub 正文 |
| 历史 0.x、1.x 直装副本（`ci.not.rune`） | 归入已转正的 Stable 线 | Stable 较新时用同 ID、同 Team 的 DMG | 当前 Stable 发布正文 |
| 首批 0.x CI 副本（`com.example.player`） | 未覆盖 | 手动换正式包 | GitHub 发布页 |
| Mac App Store | 通用 App Store | 通用 App Store | 商店提供的版本说明 |

同 ID 的 2.x Alpha 装机版本以 `2.0.10xx` 这类数字编译号分流。Stable 与它各自查询 GitHub Release，DMG 文件名须含该发布的完整 tag。GitHub 的 tag 是公开版本，直装 bundle 的两个版本字段用 Flutter 的版本，因此读取 GitHub `refs/tags/<tag>/pubspec.yaml` 中顶层 `version:`，再用实际 bundle 版本比较及核对安装包。字段缺失、版本主次段或渠道对不上时不提供更新。

1.x 的 Alpha、Beta、RC 属于各次正式版的开发阶段。两个已转正版本的最终 RC 与各自 Stable 指向同一提交，编译版本相同。同版本副本视为已更新。早期开发包共用 `1.0.0`、build `1`，不能从装机版号还原具体测试 tag。2024 年的测试序列已经结束，后续同签名的 1.x 正式包由 Stable 规则提供。

最早带 macOS 资产的 `v0.0.0-dev.10` 到 `dev.12` 包使用 Flutter 通用 ID `com.example.player` 和相同的 `1.0.0`、build `1`，`dev.10` 为 ad-hoc，`dev.11` 和 `dev.12` 为 Apple Development 签名。Duo 的 ID 迁移会先按旧 ID 和版本匹配 recipe，再在安装时看 Team，无法用这些通用字段区分其他 Flutter 开发副本。手动换成由 Inkwire 公证的正式包后即可检测。从 `dev.13` 开始的已测包使用直装 ID 和 Developer ID。

## 安装与日志

两轨验证的旧版及新版均由 Inkwire 签名，支持 arm64 和 x86_64，四份应用通过严格签名检查及公证评估。较旧的 Stable 原包早于 GitHub 资产摘要，走 Developer ID 验证。Alpha 的 DMG 还带 GitHub SHA-256 摘要。GitHub Markdown 的功能、改进、修复等分节复用现有结构化解析器。[Alpha 发布说明](https://github.com/Losses/rune/releases/tag/v2.0.0-alpha.17)提醒不要混用测试版和正式版，测试版可能升级数据库及配置格式。

## 夜扫覆盖

- 版本：`github:Losses/rune:stable` 和 `github:Losses/rune:alpha` 由 GitHub recipe 注册表枚举。
- 安装包：`install:github:Losses/rune:stable` 和 `install:github:Losses/rune:alpha` 由 `verify-install` 检查同一条规则选择的 DMG。
- App Store 更新由商店通用源负责，GitHub 安装扫描不检查商店字节。历史已转正的同 ID 副本共用 Stable 的当前包，无独立存续发布轨。通用 Flutter ID 的 CI 副本没有单独的可监测渠道。

## 历史与实测

2026-11-28，挂载 GitHub DMG，读取应用 plist、架构及签名，无需启动应用。

| 发布 tag | 两个 bundle 版本字段 | 最低 macOS |
|---|---|---|
| [v1.0.0](https://github.com/Losses/rune/releases/tag/v1.0.0) | 1.0.4002 | 10.14.6 |
| [v1.1.0](https://github.com/Losses/rune/releases/tag/v1.1.0) | 1.1.4002 | 10.14.6 |
| [v2.0.0-alpha.1](https://github.com/Losses/rune/releases/tag/v2.0.0-alpha.1) | 2.0.1001 | 10.14.6 |
| [v2.0.0-alpha.16](https://github.com/Losses/rune/releases/tag/v2.0.0-alpha.16) | 2.0.1016 | 12.0 |
| [v2.0.0-alpha.17](https://github.com/Losses/rune/releases/tag/v2.0.0-alpha.17) | 2.0.1017 | 12.0 |

另读取 `v0.0.0-dev.23`、`v0.0.0-alpha.23`、`v1.1.0-beta.3` 与 `v1.1.0-rc.2` 的实际 DMG，均为同 ID、同 Team 的 universal app。2026-11-28 检查到 17 个 2.x Alpha 发布连续排列，只有 `alpha.6` 缺少 macOS 包，前一项 `alpha.5` 有包。
