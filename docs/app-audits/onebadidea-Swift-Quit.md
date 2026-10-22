# Swift Quit

## 基本信息
- App: Swift Quit — 菜单栏常驻 app（`LSUIElement=true`），某个 app 的最后一个窗口关掉后自动退出该 app；开源（`onebadidea/swiftquit`，默认分支 `main`）
- Bundle ID: `onebadidea.Swift-Quit`（三个 release 相同）
- Team ID: v1.5 `M4FH9KS7W7`（Developer ID Application: John Baird），`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID；**v1.4、v1.3 是 ad-hoc**（`Signature=adhoc`、`TeamIdentifier=not set`、`flags=0x10002(adhoc,runtime)`，`spctl` rejected）
- 观测版本: 1.5（`CFBundleVersion` 1）；上一版 1.4、再上一版 1.3（build 都是 1）；观测日期: 2026-10-22
- 自更新机制: **无**。settled from source: `Swift Quit/AppDelegate.swift`、`SwiftQuit.swift` on `v1.5`，没有任何更新检查；Info.plist 无 `SUFeedURL`；依赖（`Package.resolved`）只有 AXSwift、Swindler、PromiseKit、LaunchAtLogin，没有 Sparkle；可执行文件 `strings` 里没有 sparkle / appcast
- 分发: GitHub Releases（每版一个 `Swift.Quit.zip`）；Homebrew cask `swift-quit`（1.5，`url` 就是 GitHub 的 v1.5 资产，sha256 `a4e467cb…74efb` 与 GitHub 下载一致，无 `auto_updates`）；没有 MAS 版（`mas search` / iTunes search 无此 bundle id）
- 厂商近况: 最后一个 release 是 v1.5（2023-03）。`main` 之后还有提交（2025-09 可调关闭延迟、2025-11 崩溃修复，最近一次合并 2026-01-29），但没有新 release

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源，只管 brew 装的副本；本次未单独验证） | — | ✓ | — |

当前生效源（非 brew 装的副本）: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 1.4: `no Sparkle, no electron-builder update config and no MyGo feed`。`SourceStack` 里 `HomebrewCaskSource` 在 GitHub 之前，brew 装的副本由 cask 回答，两者版本与资产相同。

## 覆盖清单
- bundle id：v1.3 / v1.4 / v1.5 都是 `onebadidea.Swift-Quit`，没有改名，同仓库没有别的产品。
- 版本范围 / 签名：
  - v1.5: Team `M4FH9KS7W7`，公证 → 一键 ✓
  - v1.4、v1.3: ad-hoc，无 Team → 检测 ✓（UPDATE → 1.5），**一键被门 3 拒**（见一键安装）。这两版的资产下载数分别为 140 和 114（v1.5 为 32769，2026-10-22 读 API），且 cask 只发过 1.5。`.publishedDigestOnly` 不适用：它只给「两边都没有 Team」的情况，这里新版有 Team（`digestOnlyIdentity` → `.teamAppeared`，信任只升不降）；而且三个资产 GitHub 都没有 `digest`
  - v1.5 的资产创建于 2023-03-16，比 release 发布（03-13）晚三天，签名时间戳也是 03-16，说明 v1.5 资产被替换过；最初 03-13 那份的签名无从查证（推测为 ad-hoc，**未验证**）
- 其他轨: 三个 release 都不是 prerelease，tag 只有 `v1.3`/`v1.4`/`v1.5`；仓库没有 beta / nightly 的构建脚本或分支。单轨
- 主机下限: DuoUpdater 是 arm64、macOS 15.0（`App/project.yml`）；Swift Quit 是 universal，`LSMinimumSystemVersion` 11.0，无需架构 / OS 门控

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `onebadidea.Swift-Quit` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `onebadidea/swiftquit` GitHub Releases，`/releases/latest`
- 版本: tag `v1.5` → `^v([0-9]+(?:\.[0-9]+)+)$` → `1.5`，等于 `CFBundleShortVersionString`；`CFBundleVersion` 恒为 1，不参与比较
- 模式核对（Python `re`，同一正则）: `v1.3`/`v1.4`/`v1.5` → 1.3/1.4/1.5；`v1.6`、`v2.0`、`v2.0.0`、`v1.10.1` 可读；`v1.6-beta`、`v2.0.0-rc.1`、无 `v` 的 `1.6`、`v2` 不匹配
- install pattern `^Swift\.Quit\.zip$`，kind `.zip`
- channel-verify（2026-10-22，真包解压后的 bundle）:
  - 1.4: `detected channel → stable`、`winning source GitHub`、`latest 1.5`、`status UPDATE → 1.5`
  - 1.3: `winning source GitHub`、`latest 1.5`、`status UPDATE → 1.5`
  - 1.5: `winning source GitHub`、`latest 1.5`、`status up to date`

## 按架构 / 按 OS 分轨
- 一个 universal zip（`lipo -archs` = `x86_64 arm64`，1.4 / 1.5 相同）；`LSMinimumSystemVersion` 11.0

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见基本信息） | 每个 release 只有一个 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（真机待做） | 不需要 |
| 证据 | 没有更新器，不下载 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 1.4 起）: `source structured: 1 entries; newest 1.5: 5 items, headings []; first items ["Removed unnecessary options", "Code cleanup", "Add ability to hide menubar"]`
- v1.5 正文就是 5 条无标题列表加一行 `**Full Changelog**` 链接；5 条全保留，没有标题可丢，链接行不进条目
- 从 1.3 起看也只有 1 条（1.5）：`/releases/latest` 的 rule 只读一个 release，1.4 的说明不显示（引擎设计，非本 rule 问题）
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（只对 Developer ID 的 1.5 及以后的副本）**
- 格式: zip，根目录就是 `Swift Quit.app`；pattern `^Swift\.Quit\.zip$`，kind `.zip`
- 签名: 1.5 `TeamIdentifier=M4FH9KS7W7`、Notarized Developer ID、hardened runtime；嵌套的 LaunchAtLoginHelper 同 Team
- 校验: GitHub 没有给这三个资产发 `digest`（API 的 `digest` 字段为空），Team-ID 路线不需要它
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- **1.4 / 1.3 → 1.5 会被拒**: 默认信任 `.developerID` 走 `SignatureVerifier.verifyTeamIdentifierMatch`，已装副本没有 Team → `noTeamIdentifier(which: "installed")`（「Could not read a Team Identifier from the installed app.」）。检测照常提示 1.5，用户需手动装一次；之后 1.5 → 未来版本走一键（前提是厂商继续用同一个 Team 签名）。按代码推断，**未真机验证**
- **目前没有「Developer ID 旧版 → 新版」的真实组合**：1.5 是唯一一个有 Team 的 release，也是最新版
- 嵌套 / 常驻组件: `Contents/Library/LoginItems/LaunchAtLoginHelper.app`（`onebadidea.Swift-Quit-LaunchAtLoginHelper`，`LSBackgroundOnly=true`）。来自 `sindresorhus/LaunchAtLogin`（`Package.resolved` 钉在 `e8171b3e`，即 4.2.0），`Sources/LaunchAtLoginHelper/main.swift`：主 app 没在跑就 `launchApplication` 它，然后 `NSApp.terminate`，**是启动完就退出的 launcher，不常驻**。可执行文件里有 `runningApplicationsWithBundleIdentifier:`、`launchApplication:`、`-LaunchAtLoginHelper$`，与该源码一致。只有用户在设置里打开「Launch at Login」时才经 `SMLoginItemSetEnabled` 注册（默认 `launchAtLogin=false`）。不需要 `loginItemAgentRestarts`
- 端到端: **未跑，待主会话真机**（本次只做了 channel-verify 与静态检查）

### 真机注意事项（从 v1.5 源码读出，标注来源）
- **启动即请求辅助功能权限**：`applicationDidFinishLaunching` 先 `AXSwift.checkIsProcessTrusted(prompt: true)`，未授权就弹系统的辅助功能授权框并立刻 `NSApp.terminate`（`AppDelegate.swift` on `v1.5`；可执行文件导入 `_AXIsProcessTrustedWithOptions`）。所以没授权时 app 根本「运行」不住
- **授权后会退出别的 app**：`activateAutomaticAppClosing` 监听窗口销毁，某 app 没有窗口了就 2 秒后 `terminate()` 它；默认 `excludeBehaviour=excludeApps` 且排除列表为空，1.5 只豁免 Finder 和 Spotlight（`SwiftQuit.swift` on `v1.5`）。真机上让它运行时，关掉任何 app 的最后一个窗口都会把那个 app 退掉
- ad-hoc 的 1.4 和 Developer ID 的 1.5 签名身份不同，从 1.4 换到 1.5 后辅助功能授权大概率要重新给（TCC 按代码签名要求记授权，ad-hoc 的要求是 cdhash；**推断，未验证**）
- app 变为 active 时会打开设置窗口（`applicationDidBecomeActive` → `openSettings`）
- 偏好写在 `~/Library/Preferences/onebadidea.Swift-Quit.plist`（键 `SwiftQuitSettings`、`SwiftQuitExcludedApps`）。没有 LaunchAgent、没有 root helper（bundle 里没有 `Library/LaunchServices`，没有 `SMJobBless` / `SMAppService`），可执行文件里没有 `.claude` / `.agents` 字样

## 已知问题
- 1.4 / 1.3 的副本不能一键（见上），只能手动换到 1.5 一次
- 厂商 `main` 上有未发版的改动，下一个 release 的签名方式未知：若退回 ad-hoc，1.5 副本会被门 3 拒（`noTeamIdentifier(which: "downloaded")`），rule 要重新评估

## 如何复验
```bash
gh api repos/onebadidea/swiftquit/releases -q '.[]|.tag_name+" "+.assets[0].name+" "+(.assets[0].digest//"nodigest")'
gh release download v1.5 --repo onebadidea/swiftquit --pattern 'Swift.Quit.zip' --dir v1.5
gh release download v1.4 --repo onebadidea/swiftquit --pattern 'Swift.Quit.zip' --dir v1.4
.claude/skills/coverage-discovery/scripts/check-bundle.sh v1.5/Swift.Quit.zip v1.4/Swift.Quit.zip   # Team M4FH9KS7W7 / not set
ditto -x -k v1.4/Swift.Quit.zip v1.4/x
swift run --package-path application-test feed-discover "v1.4/x/Swift Quit.app"                      # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify "v1.4/x/Swift Quit.app" --expect stable     # → GitHub，UPDATE → 1.5
gh api "repos/sindresorhus/LaunchAtLogin-Legacy/contents/Sources/LaunchAtLoginHelper/main.swift?ref=e8171b3e38a2816f579f58f3dac1522aa39efe41" -q .content | base64 -d
```

## 建议下一步
1. 真机一键（主会话）后，把结果写进「一键安装」并更新 README 那一行。
2. 厂商发下一个 release 时复查：签名是否仍是 `M4FH9KS7W7`、资产名是否仍是 `Swift.Quit.zip`、tag 仍是 `v<x.y>`。
