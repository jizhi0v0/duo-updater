# CleanClip

## 已接入的副本

| 副本 | 检测 | 一键升级 | 更新日志 |
| --- | --- | --- | --- |
| 官网正式版 `com.antiless.cleanclip.mac` | GitHub Releases 正式标签，版本取营销版本 | 同一发布的签名 universal DMG，校验 GitHub 已发布的摘要及包身份 | 从官网发布记录提取正式版本、日期、标题和条目 |
| 官网旧正式版（实查 1.0.0、1.3.2） | 同 ID，GitHub 正式版规则可接续已退役的旧 Sparkle 源 | 实查旧包与当前正式包的 ID 和 Team 一致，可用相同的一键路径 | 同正式版，展示有正文条目的历史版本 |
| 厂商公开 beta | 包内营销版本保留 `-beta.N`，GitHub beta 路径只跟踪 beta tag | 选择 beta 标签下的签名 universal DMG，与正式版资产隔离 | 官网 beta 版本、日期和条目 |
| Homebrew `cleanclip` | cask 标为 `auto_updates true`，由 Homebrew 默认管理 | 默认经 Homebrew 升级，允许非 Homebrew 来源后可按现有回退策略使用 GitHub | 按安装副本渠道选日志 |
| Mac App Store | App Store ID `6463153747`，与官网包共用 bundle ID；以商店收据区分 | 商店副本使用现有 App Store 路由 | 使用商店副本的更新信息 |

官网与 Homebrew 指向厂商同一发布序列。Homebrew 用的 appcast 提供 GitHub ZIP 链接，实际 2.4.6 与 2.4.7 官网包没有 Sparkle framework 或 feed，GitHub 发布同时提供经验证的 DMG 和摘要。只认可与标签版本完全相同的 DMG 文件名，防止用旧资产建立新版本。日志中的 Download 链接可能嵌在最后一条修改里，提取保留修改文本，省去下载控件。

公开 beta 包自己的版本足以区分渠道。GitHub 发布列表共 59 项，版本最高的 beta 排在第 8 项，较早一版排在第 59 项。配方在默认 20 项窗口内按版本排序。官网的 2.4.1-beta.1 下载别名返回 404，GitHub Releases 的原始 DMG 可下载。2.4.6 二进制还含自带更新器的 beta 选项线索，尚无该偏好在磁盘上的实际字段和更新语义证据。装着正式版且启用厂商 beta 选项的副本在 DuoUpdater 仍使用正式轨，厂商更新器可继续处理它的 beta 选项。

## 夜扫覆盖

- `github:CleanClip/CleanClipApp:stable` 和 `github:CleanClip/CleanClipApp:beta` 检查各自的版本源，`install:github:CleanClip/CleanClipApp:stable` 和 `install:github:CleanClip/CleanClipApp:beta` 检查两轨的完整 DMG。正式 2.4.7 的 GitHub 资产提供 SHA-256，历史 beta 资产依赖签名和包身份校验。
- `changelog:com.antiless.cleanclip.mac:stable` 和 `changelog:com.antiless.cleanclip.mac:beta` 分别检查同一官方发布页上的结构化条目。旧版 1.3.2 的退役 feed 不能独立作为夜扫目标。

## 历史与实测

2026-11-28，只读检查 2.4.6/2040600、2.4.7/2040701、2.2.0-beta.1/20200、2.4.1-beta.1/2040100 和旧正式版 1.0.0/1、1.3.2/10302。六个 DMG 中的应用均为 arm64 / x86_64 universal，bundle ID 为 `com.antiless.cleanclip.mac`，Team ID 为 `JDZMWLF652`，通过严格签名和 Gatekeeper 公证检查。1.0.0 的 `SUFeedURL` 为空。1.3.2 声明 `https://clip.macaify.com/appcast.xml`，当前重定向到官网 HTML 首页。

2.4.7 中的 `com.antiless.cleanclip.mac-LaunchAtLoginHelper` 标识为 Sindre Sorhus 的 LaunchAtLogin 登录启动器。该组件在登录时启动主程序并退出。

[厂商正式版与测试版发布](https://github.com/CleanClip/CleanClipApp/releases) · [官网发布记录](https://cleanclip.cc/docs/changelog) · [Homebrew cask](https://formulae.brew.sh/cask/cleanclip) · [App Store](https://apps.apple.com/ca/app/cleanclip-clipboard-manager/id6463153747?platform=mac) · [LaunchAtLogin Helper 源码](https://github.com/sindresorhus/LaunchAtLogin-Legacy/blob/f1cc3b8/Sources/LaunchAtLoginHelper/main.swift)
