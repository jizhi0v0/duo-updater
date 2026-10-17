# macUSB

## 基本信息
- App: macUSB — 在 Mac 上制作可启动 U 盘（macOS / OS X / Windows / Linux 安装介质），MIT 开源
- Bundle ID: `com.kruszoneq.macUSB`
- 仓库: `Kruszoneq/macUSB`（默认分支 `main`）
- Team ID: `27NC66L8P2`（2.0 起 Developer ID + 公证；1.0–1.1.1 是 Apple Development 证书签的 zip，Team 相同）
- 观测版本: 2.5（`CFBundleVersion` 44）；观测日期: 2026-10-16
- 自更新机制: 只有菜单里的「检查更新」，settled from source: `macUSB/Shared/Services/UpdateChecker.swift` on `main`。
  它读 `raw.githubusercontent.com/Kruszoneq/macUSB/main/version.json`（`{"version": "2.5", "url": ".../releases/latest"}`），
  版本比 `CFBundleShortVersionString` 新就弹窗、点「下载」打开 GitHub release 页。不下载、不安装
- 分发: GitHub Releases；Homebrew cask `macusb`（`url` 就是同一个 GitHub dmg，`auto_updates` 未设）；没有 MAS

## 覆盖清单（Coverage checklist）
- **Bundle id**: 1.0、1.1.1、2.0、2.4、2.5 实测都是 `com.kruszoneq.macUSB`，没有改名，也没有别的版本/edition
- **Release track**: 只有一条。17 个 release 都不是 prerelease（2026-10-16 列表）；`version.json` 只有一个版本字段；
  `docs/AGENTS.md` 的发版规则里没有 beta/rc 轨。规则读 `/releases/latest`，`versionPattern` 用 `$` 锚定
- **Version range**: 所有 tag（`v1.0` … `v2.3.1` … `v2.5`，两段和三段都有）都匹配 `^v([0-9]+(?:\.[0-9]+)+)$`，
  捕获值与实测包的 `CFBundleShortVersionString` 相同（1.0 / 1.1.1 / 2.0 / 2.4 / 2.5）。旧副本没有任何 feed，
  检测不依赖 bundle 内容
- **Host floor**: 厂商 `LSMinimumSystemVersion` = 14.6，低于我们的 15.0，不构成限制
- **一键**: Team 闸按 Team ID 比对；实测的五个版本 Team 都是 `27NC66L8P2`，所以 1.x（Apple Development 签名）副本
  按代码读也能过 Team/bundle id 闸（读 `SignatureVerifier.verifyInstallArtifact`，**未实际运行**）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 结论：无 Sparkle、无 electron-builder 配置、无 MyGo feed。
`version.json` 只给版本号和 release 页链接，GitHub 规则读的是同一份发布，不需要 VendorProbe。

## Channel 详情

单轨，settled from source（`UpdateChecker.swift`、`version.json`、`docs/AGENTS.md` on `main`）。app 内没有渠道开关。

## 更新检测
- 源: `Kruszoneq/macUSB` GitHub Releases，`/releases/latest`
- 版本: `^v([0-9]+(?:\.[0-9]+)+)$`，与 `CFBundleShortVersionString` 一致

## 按架构 / 按 OS 分轨
- 1.1.2 起每个 release 一个通用 dmg（`macUSB.<v>.dmg`，`lipo` = `x86_64 arm64`，2.0/2.4/2.5 实测）。
  1.0 是 arm64-only zip，1.1.1 起通用；装 1.0 的副本换成通用包不触发架构降级闸
- 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有安装器，只打开 release 页 | 每个 release 只有一个 dmg 资产 | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-16，channel-verify `changelog pane`，2.5）: `source structured: 1 entries; newest 2.5: 16 items,
  headings ["ADDED", "CHANGES", "FIXED", "IMPROVEMENTS"]`；正文 16 条 `- ` 条目，与解析结果条数相同。
  开头的一段概述不进条目
- 2.4 用 `ADDED: WINDOWS` / `ADDED: DOWNLOADER` 这种带冒号的小节标题，同样是 `###`
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Team 闸）
- 格式: dmg（无 SLA，`hdiutil imageinfo` = `Software License Agreement: false`）。dmg 本身没 staple 公证票据
  （`spctl -t open` = Unnotarized Developer ID），里面的 app `spctl -a -t exec` = accepted, Notarized Developer ID
- Pattern: `^macUSB\.[0-9]+(?:\.[0-9]+)+\.dmg$`, kind `.dmg`；1.x 的 `macUSB.zip` / `macUSB.v1.0.3.zip` 不匹配
  （`/releases/latest` 不会再给它们）
- 校验: GitHub 资产 `digest`。`shasum -a 256`: 2.5 = `aec02175…bac6731c`、2.4 = `fe3f25cb…69fde1ae`，与 `digest` 相同
- 上一版 Team: 2.4 = `27NC66L8P2`，与 2.5 相同（实测）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，也是 app 自己的「下载」按钮打开的页面）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：2.4 → 2.5（含 `verifyingSignature`；未启动，root helper 未注册），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 阻塞: 无

### 特权 helper（换包后会怎样）
bundle 里有一个 LaunchDaemon：`Contents/Library/LaunchDaemons/com.kruszoneq.macusb.helper.plist`，
`BundleProgram` = `Contents/Library/Helpers/macUSBHelper`，通过 `SMAppService` 注册，需要用户在系统设置里批准。
从源码（`docs/reference/features/helper/HELPER.md`、plist）读到：
- 按需启动：没有 `RunAtLoad`，`KeepAlive` = false；app 断开 XPC 连接后 helper 空闲退出。2.5 的 release notes 写了
  修复「关掉 macUSB 后 helper 仍在运行」，所以 2.4 及更早的副本退出后 helper 可能还在
- 路径是 bundle 内相对路径，换包后同一路径指向新的 helper 二进制
- app 启动时比较 `CFBundleShortVersionString` + `CFBundleVersion` 指纹，变了就自动做一次完整 repair
  （unregister → register → XPC 健康检查），失败才弹一次警告。所以换包后第一次启动由 app 自己重新注册新 helper
- XPC 两端互相按代码签名要求校验（同一 Team 的 app 与 helper），换包后两边都来自新包
- 2.5 起「操作进行中不允许关闭 app」：正在写 U 盘时退出会被 app 拒绝，运行中一键在这种时候退不掉 app，属于预期

结论：helper 不阻止一键，但换包后要用户重新批准（2026-10-16 真机，见建议下一步 1）：批准过、正在跑的 root helper 在换包后继续跑旧二进制，
`duo install` 的 `Still running the old code` 只列 app、不列它；`duo restart` 后 2.5 启动时的 repair 把它 unregister（旧 helper 退出），
随后 `Register … error: 1`，helper 变成未注册、BTM 记 `[disabled, allowed]`，要用户再批一次。任何更新都会改版本指纹、触发同样的 repair，
所以手动拖拽更新应该也一样（推断，没测）。

## 已知问题
- 换包后 helper 需重新批准（见上）。
- 2.4 的 “Update available!” 与 2.5 的 “Full Disk Access Required” 提示开着时 app 拒绝退出，`duo restart` 报 `still running — likely a save prompt`，属于预期
- 2.5 原包 `codesign --verify --deep --strict` 报 `resource fork, Finder information, or similar detritus`（bundle 上有 `com.apple.FinderInfo`），厂商 `macUSB.2.5.dmg` 里的也一样；`spctl` 照常 Notarized

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：2.4 启动后注册 helper（`[enabled, disallowed]`），用户在「登录项与扩展 → 允许在后台」批准（前两次停在 per-user 记录的 `pending authorization`，第三次生效）后 root helper 运行；`duo install --yes` → `installed.` 并提示 `Still running the old code: macUSB`，root helper 仍跑旧二进制；关掉 2.4 自己的更新提示后 `duo restart` → `restarted`；2.5 的 repair 注销旧 helper、重新注册失败（`Register … error: 1`），需再批准。Team `27NC66L8P2`、Notarized。新增 `~/Library/{Caches,HTTPStorages}/com.kruszoneq.macUSB`、`~/Library/Preferences/com.kruszoneq.macUSB.plist`；登录项多了 macUSB（app，含 `pending authorization`）与 macUSBHelper（daemon）记录，app 进废纸篓 20 秒后仍在

## 如何复验
```
swift run --package-path application-test feed-discover <macUSB.2.5.dmg>   # → —（无 Sparkle / electron-builder / MyGo）
swift run --package-path application-test channel-verify <macUSB.2.4.dmg> --expect stable
#   → detected stable，winning source GitHub，latest 2.5，UPDATE → 2.5
swift run --package-path application-test channel-verify <macUSB.2.5.dmg> --expect stable
#   → up to date；changelog pane: source structured, headings ["ADDED", "CHANGES", "FIXED", "IMPROVEMENTS"]
codesign -dv <macUSB.app>          # → TeamIdentifier=27NC66L8P2
spctl -a -vv -t exec <macUSB.app>  # → accepted, source=Notarized Developer ID
```
