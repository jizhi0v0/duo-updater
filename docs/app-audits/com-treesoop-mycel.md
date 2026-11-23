# Trina AX

2026-11-23 接入调研。审计对象为 Trina AX macOS Desktop 的公开 DMG，Bundle ID `com.treesoop.mycel`，Team `YWW96288YY`。

## 覆盖清单

| 安装来源 | 更新职责 |
| --- | --- |
| 公开签名 DMG | GitHub Stable recipe，版本检测、DMG 原位替换、结构化 release notes |
| 站点团队提供的 Desktop | 客户端内建 updater 使用当前团队的版本和会话。VM 验证 0.14.0 客户端可沿用会话连接 0.13.1 团队 |
| Mac App Store Desktop | vendor 构建配置使用独立 ID `app.trina.ax`，走现有 App Store 路径 |
| Office Mac ZIP | 自托管服务端，含独立的 `teamax` 运维入口。Desktop 使用精确 DMG 选择器 |
| Android、Linux 服务端、Windows / Linux 客户端 | 与 Desktop 共用仓库或发布页，使用平台各自的更新入口 |

抽测 GitHub 公开 DMG 的 0.5.14、0.13.1、0.14.0 均使用同一 ID 和 Team，arm64 与 x86_64 通用包，最低 macOS 13.0。公开 release 列表有 19 个三段式应用版本及一个 `android-v1.0.9`。仓库还有旧的 beta Git tags，当前公开 `office/stable.json` 与 `office/beta.json` 均列出 0.14.0 和同一个 DMG 摘要。历史 beta 安装包及在用 beta 团队的客户端行为尚无真包或服务端实测证据。[发布列表](https://github.com/trina-app/trina-ax/releases) · [App Store 打包配置](https://github.com/trina-app/trina-ax/blob/v0.14.0/editions/trina/mac-app-store/electron-builder.mas.config.ts)

## 检测、一键安装与 Changelog

- 公开 Stable 路径复用 `build-miguel-Exo.swift` 的 `GitHubReleaseRule`。版本用 `^v([0-9]+\.[0-9]+\.[0-9]+)$`，安装包用 `^Trina-AX-[0-9]+\.[0-9]+\.[0-9]+-mac-universal\.dmg$`。GitHub 发布的 0.14.0 DMG 摘要与官网链接对应的公开 manifest 记录相同。使用默认 Developer ID 守卫和 GitHub digest。
- 包内 `app-update.yml` 指向占位地址 `https://localhost.invalid/downloads/`。签名版启动后按当前团队动态重设地址，登录后才拉取团队的 `/downloads/latest-mac.yml`，同时校验更新 ZIP 的签名发布清单，再交给 Squirrel.Mac。未连团队时没有客户端更新源可供通用 Electron 路径读取。Duo 的版本来自公开 Stable。团队当前提供的客户端版本可能不同，独立托管的服务器会继续按团队自己的发布节奏运行。
- 0.14.0 release body 有英韩双语 bullet，可由 `GitHubMarkdownParser` 结构化。内容还包括服务端条目及平台备注，显示效果待 Workbench 实测。

[0.14.0 发布与变更日志](https://github.com/trina-app/trina-ax/releases/tag/v0.14.0) · [官网签名清单](https://updates.trina.app/office/stable.json) · [Desktop updater](https://github.com/trina-app/trina-ax/blob/v0.14.0/desktop/src/main/updater.ts)

## VM 实测

Apple Silicon、macOS 27.2。签名 Release 的 `duo check` 检测到 0.13.1 → 0.14.0，`duo install --yes` 报告原位安装成功。严格签名、公证和升级后版本检查通过。0.13.1 客户端登录从同版本 Office 发布包启动的隔离测试团队。更新后，0.14.0 读取原客户端数据，保留登录态并打开仍运行 0.13.1 的团队界面。测试覆盖登录和客户端重连，团队内建更新器已暂存 ZIP 的行为仍待验证。

## 夜扫覆盖

公开 Stable 由 GitHub 注册表纳入夜扫，记录 ID 为 `github:trina-app/trina-ax:stable`。定向 `duo verify --github --only com.treesoop.mycel` 和 `duo verify-install --only com.treesoop.mycel --full` 均通过。团队更新源绑定每个团队与登录会话，当前无公共的等效 fixture 来覆盖该路径。App Store 由其独立 ID 使用现有索引机制。
