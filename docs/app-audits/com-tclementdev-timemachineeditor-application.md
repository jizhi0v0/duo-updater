# TimeMachineEditor

## 基本信息
- Bundle ID: `com.tclementdev.timemachineeditor.application`
- Team ID: `68GTH78H6S` (Thomas CLEMENT)
- 已知版本: 5.2.2 (build 219), released 2023-02-16 — no newer release since
- 自更新机制: 无（vendor 没有内建更新器；用户需要手动重新下载 pkg）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**

只有一个 channel；vendor 从未发布过 beta/nightly。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.tclementdev.timemachineeditor.application` | 独立（无其他 channel） | — | — | ✓ |

## 更新检测

- 源: VendorProbe，`https://tclementdev.com/timemachineeditor/`（vendor 主页本身，无 JSON/API）
- 端点: 主页 HTML 里唯一的下载链接 `<a href="…/TimeMachineEditor.pkg">TimeMachineEditor 5.2.2</a> (2023, February 16) - macOS 10.13 or newer`
- Pattern: `<a href="https://tclementdev\.com/timemachineeditor/TimeMachineEditor\.pkg">TimeMachineEditor\s+([0-9]+(?:\.[0-9]+)+)</a>` — 锚定完整 href 和 `</a>` 边界，避免读到同一句里紧跟着的 "macOS 10.13" 系统版本号
- 与 Homebrew cask 自己的 `livecheck` 独立印证：cask 的 `livecheck` 块正是 `url :homepage` + `regex(/href=.*TimeMachineEditor\s*v?(\d+(?:\.\d+)+)/i)`，说明这条链接就是 vendor 自己承认的版本源，不是猜的
- 注意事项:
  - vendor 没有 JSON API、没有 changelog 页、没有 Sparkle/appcast——这是本仓库能找到的唯一可解析版本来源
  - 下载 URL 是**静态、不带版本号**的文件名（`TimeMachineEditor.pkg`），永远指向当前发布版，所以 install spec 用 `.fixed`，不需要正则
  - 版本方案已核对：下载并展开真实 pkg（2026-08-29），`PackageInfo` 读到 `CFBundleShortVersionString="5.2.2" CFBundleVersion="219"`，探测到的 "5.2.2" 与 marketing 字段完全一致，不是 build——**不需要** `versionIsBuild`

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | 不是 Sparkle app（bundle 无 `SUFeedURL`，无 `Sparkle.framework`），pkg 只有 ~1MB，页面上没有任何 `.delta`/`.patch` 链接 | 同上 | — |

- 格式: 不适用
- 阻塞项: 无（vendor 从不提供增量更新，全量 pkg 是唯一分发形式）

## Changelog

- 来源: 无。vendor 主页没有 changelog/release-notes 链接（核实过：页面只有一个下载链接 + FAQ，没有版本历史）
- 跟随 channel: 不适用（单 channel）
- Recipe 状态: 不需要（没有可读的 changelog 源；`ChangelogRecipe` 不适用）

## 一键安装

- 状态: 支持
- 格式: pkg
- **读的是**: 人人可手动下载的 GA —— 探测端点就是 vendor 官网首页公开展示的同一个下载链接，任何访客都能拿到同一个文件，不存在「轨道最新但本机未分配」的问题
- `kind` 必须是 `.pkg`（不是 `.dmg`/`.zip`）: 展开真实 pkg 后确认 payload 在 `.app` 之外还装了 `/Library/LaunchDaemons/com.tclementdev.timemachineeditor.scheduler.plist`（一个特权 LaunchDaemon）、`/Library/TimeMachineEditor/` 下的 scheduler 二进制和 `tmectl` CLI 工具，以及一个 `com.tclementdev.timemachineeditor.upgrader` pre/postinstall 脚本负责在升级时管理这个 daemon。只换 `.app` 会把新版本的界面装上，却把 daemon、CLI 留在旧版本，且没有任何报错能提醒到这一点
- 签名核实: pkg 本身 `pkgutil --check-signature` 显示 "signed by a developer certificate issued by Apple for distribution"、"Notarized: trusted by the Apple notary service"；内部 `.app` 由 `codesign` 确认 Team `68GTH78H6S`（"Developer ID Application: Thomas CLEMENT"）
- 阻塞: 无

## 已知问题

- vendor 更新节奏极慢（上一次发布是 2023-02-16），探测端点是纯静态首页，没有任何机器可读的版本 API——一旦 vendor 改版首页结构，这条 recipe 会直接读不到版本（沿用仓库惯例：读不到就退化为 unknown，不会误报）

## 建议下一步

1. ~~加 stable 检测~~ 已完成：`VendorProbeRecipe` 注册在 `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift`（"2026-08-29 TimeMachineEditor" 区块），回归测试在 `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/VendorProbeRecipeTests.swift`（同名区块，3 条：pattern 命中、pattern 不误伤相邻的 macOS 版本号、install spec 校验）
2. 无待办事项——这是单 channel、无 changelog、无增量更新的最简形态，探测+一键均已覆盖并经真实端点验证（2026-08-29 `duo verify --only tclementdev`：`status: ok, version: 5.2.2, warnings: []`）
