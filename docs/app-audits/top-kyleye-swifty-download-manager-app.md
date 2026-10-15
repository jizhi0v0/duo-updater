# Swifty Download Manager

## 基本信息
- App: Swifty Download Manager（SDM）— 原生 Swift 写的下载管理器（HTTP Range 分段、多连接、断点续传），带 Safari / Chrome 扩展
- Bundle ID: `top.kyleye.swifty-download-manager-app`（0.4.0 / 0.5.1 / 0.6.0 三个真包相同）
- 仓库: `Kyle-Ye/SwiftyDownloadManager`（默认分支 `main`）
- Team ID: `VB7MJ8R223`（Developer ID + 公证；0.4.0 / 0.5.1 / 0.6.0 相同）
- 观测版本: 0.6.0（`CFBundleVersion` 38）；观测日期: 2026-10-15
- 自更新机制: 无（Info.plist 没有 `SUFeedURL`，仓库里没有更新检查代码）
- 分发: 只有 GitHub Releases。没有 Homebrew cask（官方 tap 里搜不到）、没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 无可用结论（bundle 不声明任何 feed）。

## Channel 详情

只有一条轨，settled from source: `.github/workflows/release.yml` on `main`。

- 发布 workflow 拒绝不是 `MAJOR.MINOR.PATCH` 的 tag，并校验 app 的 `CFBundleShortVersionString`、扩展的版本和
  扩展 `manifest.json` 的 `version` 都等于 tag。tag 不带 `v`。
- 截至 2026-10-15 共 6 个 release（0.2.0–0.6.0），全部非 pre-release。0.2.0 / 0.2.1 / 0.3.0 没有附件，只能读出版本、不能装。

## 更新检测
- 源: `Kyle-Ye/SwiftyDownloadManager` GitHub Releases
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`（锚定；tag 等于 `CFBundleShortVersionString`）
- 注意: `CFBundleVersion` 是递增构建号（0.4.0=32、0.5.1=35、0.6.0=38），不参与比较

## 按架构 / 按 OS 分轨
- 每个 release 一个通用包 `SwiftyDownloadManager.app.zip`（`lipo` = x86_64 arm64）
- `LSMinimumSystemVersion` = `14.0`（三个版本相同）；release 不声明上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器 | release 只有一个 zip | — |

## Changelog
- 来源: GitHub Release body（GitHub 自动生成的 "What's Changed"），经 `GitHubMarkdownParser`
- 结构化（2026-10-15，channel-verify `changelog pane`，从 0.5.1 起）: `source structured: 1 entries; newest 0.6.0:
  4 items, headings ["Other Changes"]; first items ["Fix browser download interception and co", "Add configurable
  browser extension downl", "refactor: consolidate browser extension "]`。分节保留
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: zip（`^SwiftyDownloadManager\.app\.zip$`，kind `.zip`）。zip 里的 app 叫 `Swifty Download Manager.app`（带空格），与资产名不同
- 嵌套: 只有 `Contents/PlugIns/Swifty Download Manager Extension.appex`（`com.apple.Safari.web-extension`）。没有
  LoginItems、LaunchAgent、Helpers
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256` 前 16 位: 0.4.0 `f6fe8471d5ded827`、0.5.1
  `46947b31961a027a`、0.6.0 `9d279012eb037aaf`，都与各自 `digest` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest` 的附件）
- 端到端（2026-10-15，不运行）: 0.5.1 → `duo check` `0.5.1 → 0.6.0 [GitHub, in-place]` → `duo install --yes --json`
  → `outcome: installed`，4.6 s，下载 7090064 字节。结果: 版本 0.6.0、可执行文件 inode 变了、Team `VB7MJ8R223`、
  `codesign --verify --deep --strict` = 0、`spctl` = Notarized Developer ID、`diff -r` 与 vendor 的 0.6.0 bundle 完全相同
- 端到端（2026-10-15，运行中）: 启动 0.5.1 → `duo install` 5.9 s，提示 "Still running the old code" →
  `duo restart` → 新 pid，`lsof` 看到进程跑的可执行文件 inode 等于磁盘上新文件；10 s 后磁盘仍是 0.6.0。app 没有自更新器，
  不存在暂存碰撞。之后 `pluginkit` 看到 Safari 扩展登记为 0.6.0
- 首次启动不登记登录项（前后 `sfltool dumpbtm` 无该 app 条目）
- 阻塞: 无

## 已知问题
- 无

## 建议下一步
1. 若作者以后加 pre-release 或应用内更新开关，重新审计。

## 如何复验
```
.claude/skills/coverage-discovery/scripts/check-bundle.sh <SwiftyDownloadManager.app.zip>   # → id、Team VB7MJ8R223、无 SUFeedURL
ditto -x -k <0.5.1 zip> <dir>
swift run --package-path application-test channel-verify "<dir>/Swifty Download Manager.app"  # → stable，GitHub，UPDATE → 0.6.0
```
