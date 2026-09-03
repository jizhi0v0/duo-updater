# Docker Desktop

## 基本信息

- Bundle ID: `com.docker.docker`
- Team ID: `9BNSXJN65R`
- 观测版本: 4.89.0 / build 238018（Apple Silicon）
- stable 构建信号: `channelID=main`
- 外层可执行文件: `com.docker.backend`
- 界面 bundle: `Contents/MacOS/Docker Desktop.app`，Bundle ID
  `com.electron.dockerdesktop`，观测版本 4.89.0 / build 4.89.0.9
- 自更新机制: 外层 Go backend 的 `com.docker.backend.updater`；嵌套 Electron GUI
  虽然带 `Squirrel.framework`，但不拥有 Docker 的更新流程

## 覆盖矩阵

> ✓ = 已接入　○ = 可接入（未实现）　✗ = 已调查不可行　— = 不适用

| channel | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Changelog |
|---|---:|---:|---:|---:|---:|---:|
| stable | — | ✗（auto_updates 且版本滞后） | — | — | ✓ | ✓ |
| nightly | — | — | — | — | ○（缺真实构件/信号） | — |

当前生效源: **VendorProbe**。2026-09-02 用观测 stable bundle 跑完整生产链，检测到
stable，VendorProbe 返回 4.89.0 和 build 238018，结果为 up to date。

## 更新检测

- DuoUpdater 端点: `https://desktop.docker.com/mac/main/arm64/appcast.xml`
- 版本字段: enclosure 的 `sparkle:shortVersionString`，与
  `CFBundleShortVersionString` 同构
- 下载地址: 同一 enclosure 的完整 `Docker.dmg`；正则刻意排除相邻 delta
- 选择方式: `.selectHighestVersion`。Docker 的 feed 不是严格 newest-first，不能取第一项
- Docker 自身的 backend 使用同一发布面的 JSON 版本：
  `https://desktop.docker.com/mac/main/arm64/appcast.json`

XML 里使用 Sparkle namespace 只是 feed 格式，不代表 Docker.app 嵌入 Sparkle。实际 bundle
没有 `Sparkle.framework` 或 `SUFeedURL`。

## 更新所有权：为什么不跟随嵌套界面 bundle

`AppRuntimeDetector.interfaceBundle(at:)` 会进入唯一的嵌套 GUI，让产品行正确显示 Electron
及其版本；这个重定向只描述 UI runtime，不能改变更新所有权。四类更新探针仍读取外层安装
bundle：`SUFeedURL`、`app-update.yml`、Squirrel 和 Sparkle。

证据链：

1. backend 日志以 `com.docker.backend.updater` 组件执行 background check，读取
   `mac/main/arm64/appcast.json` 并维护更新状态。
2. GUI 的设置代码读取 backend 提供的 `stateFromBackend`，安装动作调用
   `desktopBackendsClient.update.applyUpdate()`，不是 Electron `autoUpdater`。
3. 嵌套 bundle 没有 `app-update.yml`；也没有 Docker 对应的 ShipIt 进程或
   `ShipItState.plist` 命名空间。

因此嵌套的 `Squirrel.framework` 是闲置实现细节。若把它借给外层 bundle，
`hasSelfUpdater` 会错误变成 true，通用探针随后只会寻找不存在的
`com.docker.docker.ShipIt` 状态。#217 的处理是固定这条边界，而不是重定向探针。

## Changelog

- 已有 `ChangelogRecipe` 从 Docker Desktop release notes 的 Markdown 生成原生条目
- VendorProbe 的 `changelogURL` 指向 `https://docs.docker.com/desktop/release-notes/`
- release notes 中包含多平台下载链接；抽取器已有回归测试，避免把这些链接当正文噪声

## 一键安装

- 状态: 支持
- 格式: Apple Silicon dmg
- 产物: `Docker.app`
- 安全闸: bundle ID `com.docker.docker`、Team ID `9BNSXJN65R`、签名/公证及架构检查
- VendorProbe 与 Docker backend 指向同一 build 238018 的 dmg，版本命名空间一致

## Channels

stable 已验证。GUI 代码里另有 feature-flagged `useNightlyBuildUpdates` 设置，但 stable
构建只观测到 `channelID=main`。在拿到真实 nightly 构件、落盘信号和 endpoint 前，不把它
登记为可检测渠道；缺口记录在 `CHANNEL_COVERAGE_TODO.md` §2b。

## 已知边界

- 通用 `SelfUpdaterStaging` 能识别 Sparkle/ShipIt 标准缓存，不能识别 Docker backend 私有的
  已下载待安装状态。若要覆盖，应以实际 backend 状态布局另做 detector，不能借嵌套 Squirrel。
- nightly 尚未验证，stable recipe 必须继续由 channel gate 限定，不能猜测跨轨更新。

## 如何复验

```sh
swift run --package-path application-test channel-verify "<Docker.app>" --expect stable

# 外层和界面 bundle 的身份、版本及 channelID
plutil -p "<Docker.app>/Contents/Info.plist"
plutil -p "<Docker.app>/Contents/MacOS/Docker Desktop.app/Contents/Info.plist"

# 嵌套 GUI 有 Squirrel，但没有标准 electron-updater manifest
find "<Docker.app>/Contents/MacOS/Docker Desktop.app/Contents" \
  -maxdepth 3 \( -name 'Squirrel.framework' -o -name 'app-update.yml' \) -print
```

复验更新所有权时，应在 Docker 执行一次后台检查后搜索 host logs 中的
`com.docker.backend.updater`、`appcast.json` 和 `applyUpdate`；不要用 Squirrel 框架的存在
替代运行证据。

## 下一步

1. 若能取得真实 nightly 构件，比较其 Info.plist、backend settings 和更新 endpoint，再决定
   ChannelBinding 或独立 recipe。
2. 若产品需要展示 Docker 已下载待安装状态，先记录 backend 的稳定状态文件/IPC，再添加专用
   staging detector；不要复用 ShipIt。
