# Docker Desktop

## 基本信息

- Bundle ID: `com.docker.docker`
- Team ID: `9BNSXJN65R`
- 观测 stable 版本: 4.89.0 / build 238018、4.98.0 / build 245422、
  4.99.0 / build 245822（Apple Silicon）
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

当前生效源为 **VendorProbe**。同一个 stable recipe 覆盖 Apple Silicon 的
`com.docker.docker`。Docker 的 Intel 分发包不在 DuoUpdater 的宿主范围内。

## 更新检测

- DuoUpdater 与 Docker backend 均使用 Apple Silicon stable 的 [JSON appcast](https://desktop.docker.com/mac/main/arm64/appcast.json)。
- 读取同一个 `Items` 条目的 `AppVersion` 与 `BuildNumber`，对应
  `CFBundleShortVersionString` 与 `CFBundleVersion`。
- 在 `Visibility` 为正且符合宿主 `MinOSVersion` 的条目中按版本选最新项，
  同版本用 build 决定。若可见版本都要求更新的 macOS，沿用现有系统版本提示。
- `PreviousBuild` 不限制全量 DMG 的升级起点。DuoUpdater 读取公开发布的条目，
  Docker 仍独立决定每个副本的分批推送。

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
- 格式: 同一发布条目的完整 Apple Silicon DMG。只接受 Docker CDN 上
  `/mac/main/arm64/<BuildNumber>/Docker.dmg` 和该 artifact 的 SHA-256。
  DMG 或摘要缺失时版本仍可检测。Docker 的交互安装也使用这个 DMG 中的应用包。
  [Docker for Mac 安装文档](https://docs.docker.com/desktop/setup/install/mac-install/#install-interactively)
- 产物: `Docker.app`
- 安全闸: bundle ID `com.docker.docker`、Team ID `9BNSXJN65R`、签名/公证及架构检查

## Channels

stable 已验证。GUI 代码里另有 feature-flagged `useNightlyBuildUpdates` 设置，但 stable
构建只观测到 `channelID=main`。在拿到真实 nightly 构件、落盘信号和 endpoint 前，不把它
登记为可检测渠道；缺口记录在 `CHANNEL_COVERAGE_TODO.md` §2b。

历史上的 public Edge 与 Stable 已在 Docker Desktop 3.0.0 合并成单一发布流。
[Docker 3.0.0 发布公告](https://www.docker.com/blog/docker-desktop-3-0-0-smaller-faster-releases/)

## 夜扫覆盖

- `duo verify --only com.docker.docker` 走现有 VendorProbe 注册表，版本行仍为
  `vendor:com.docker.docker:stable`，并检查原来的 changelog 行
  `changelog:com.docker.docker:-`。
- `duo verify-install --only com.docker.docker` 枚举
  `install:vendor:com.docker.docker:stable`，继续对照既有的 Apple Silicon 安装包身份
  记录 `vendor:com.docker.docker:stable`。
- Docker 的 nightly 轨缺少经过验证的构件及更新源，因此没有该轨的扫描行。

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

## 历史与实测

### 2026-11-20 — #2119 stable JSON 切换

VM 中两份 Docker 原厂签名的 Apple Silicon 副本，4.98.0（245422）和
4.99.0（245822），均由原生 backend 读取 JSON appcast，并直接发现
4.100.0（246961）的全量 DMG。该条目当时为 `Visibility=99`，
`PreviousBuild=245822`。旧 XML 仍只返回到 4.99.0。
[Docker 4.100.0 发布说明](https://docs.docker.com/desktop/release-notes/#41000)

JSON 里同时含 DMG 和 PKG。4.100.0 的 DMG SHA-256 与 Docker 单独发布的校验清单一致。
[Docker 官方校验清单](https://desktop.docker.com/mac/main/arm64/246961/checksums.txt)

### 2026-09-02 — 4.89.0 stable

用 4.89.0（238018）副本跑完整生产检测，检测到 stable，VendorProbe 返回
4.89.0，结果为 up to date。旧 XML 与 Docker backend 的下载都指向 build 238018。

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-docker-docker.swift — stable VendorProbe（一键 `Docker.dmg`）

转引自 recipe 注释，未复测。唯一的改写：一处本机状态措辞（具体版本号），按本目录的机器状态规则改成了针对那台被量的机器的说法。

On 2026-08-17 it listed 4.86.0 (build
236216) ahead of 4.87.0 (236836), so a first-match download fetched
4.86.0 over the 4.86.0 installed on the machine measured that day — 574 MB, a 2.26 GB backup, "install
done", and the update still pending.

Verified 2026-08-09 on 4.85.0 (build 235549): `Docker.app` in the
image, bundle id com.docker.docker, Team 9BNSXJN65R, spctl "Notarized
Developer ID". 573 MB, arm64-specific feed path.

### Recipes/com-docker-docker.swift — ChangelogRecipe（`release-notes.md`）

转引自 recipe 注释，未复测。唯一的改写：末尾一处本机状态措辞（具体版本号），按本目录的机器状态规则改成了针对那台被量的机器的说法。

`docs.docker.com/desktop/release-notes.md` serves `text/markdown`
directly (the `.md` twin of the HTML page), 142 versions deep, newest
4.87.0 on 2026-08-17 — the version installed on the machine measured that day.
