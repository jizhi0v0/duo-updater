# OpenScreens

## 覆盖清单

| 安装来源 | Bundle ID 与签名 | 更新路径 |
| --- | --- | --- |
| GitHub macOS Stable 1.0.0、1.1.0 | `com.burakgon.openscreens`，Team `QCB78CL77T`，universal，最低 macOS 26 | GitHub Stable 检测、官方 DMG 一键更新、结构化发布说明 |

macOS 的两个公开版本沿用同一身份。README 把 Mac 用户指向 GitHub DMG，另列 iPhone 和 iPad 的安装方式。1.1.0 的正文包括 Apple 移动平台的变动以及 Mac 共享的改动，Mac 安装资产仍为 `OpenScreens-1.1.0.dmg`。 [项目 README](https://github.com/burakgon/OpenScreens/blob/v1.1.0/README.md#installation) · [1.0.0](https://github.com/burakgon/OpenScreens/releases/tag/v1.0.0) · [1.1.0](https://github.com/burakgon/OpenScreens/releases/tag/v1.1.0)

## 检测、一键更新与发布说明

实包无 `SUFeedURL`。GitHub 规则读取三段式 Stable 标签并选取同系列 Mac DMG。未来只有移动端资产的 release 会被现有 macOS 资产筛选跳过。下载沿用 GitHub 资产摘要和 Developer ID 连续性校验。发布正文由共享的 `GitHubMarkdownParser` 转成结构化发布说明。

## 历史与实测

2026-11-23 挂载官方 1.0.0 和 1.1.0 DMG，两个包的严格签名校验均通过。两包 `CFBundleShortVersionString` 分别为 1.0.0、1.1.0，构建号分别为 1、2。构建脚本用 Developer ID 签名并导出公证 App。 [Mac 发布脚本](https://github.com/burakgon/OpenScreens/blob/v1.1.0/scripts/release-mac.sh)

## 夜扫覆盖

GitHub 注册表枚举 macOS Stable，记录 ID 为 `github:burakgon/OpenScreens:stable`。
