# SwiftPlantUML

## 基本信息
- App: SwiftPlantUML（`SwiftPlantUMLApp.app`）— 给 Swift 代码画 PlantUML 类图。主 app 只是设置窗口；功能在两个扩展里：Xcode Source Editor 扩展（Editor 菜单「Open editable diagram in browser」）和 Finder 快速操作（`com.apple.services` Action 扩展，1.5.0 起）；MIT
- Bundle ID: `us.eidinger.SwiftPlantUML`
- 仓库: `MarcoEidinger/SwiftPlantUML-Xcode-Extension`
- Team ID: `6V66CC3AN6`（Developer ID Application: Marco Eidinger；1.0.0–1.6.0 每一版都是 Notarized Developer ID）
- 观测版本: 1.6.0（`CFBundleVersion` 3，2024-01-02 发布）；上一版 1.5.1（build 1）；观测日期: 2026-10-22
- 自更新机制: **无**。可执行文件里的 `github.com/MarcoEidinger/SwiftPlantUML-Xcode-Extension/releases` 是菜单项「Release Notes」用 `NSWorkspace.shared.open` 在浏览器打开发布页（源码 `SwiftPlantUMLApp/AppDelegate.swift` `showReleaseNotes(_:)`，`Main.storyboard` 里接到菜单）。主可执行文件只链接系统框架（`otool -L`：Foundation/AppKit/Combine/SwiftUI…），`strings` 里 `sparkle|appcast|URLSession` 0 处，没有 Frameworks 目录
- 分发: GitHub Releases（每版一个 `SwiftPlantUMLApp.zip`）；Homebrew cask `swiftplantumlapp`（url 就是同一个 GitHub 资产，`auto_updates` 未设，装到 `/Applications/SwiftPlantUMLApp.app`）；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | 通用 cask 源（本次未单独验） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，1.5.1 / 1.0 / 1.6.0 三份真包都是 `winning source  GitHub`）。`feed-discover` 对 1.5.1: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（读真包 1.0.0、1.3.0、1.4.0、1.4.1、1.5.0、1.5.1、1.6.0）: 主 app 一直是 `us.eidinger.SwiftPlantUML`，Team 一直是 `6V66CC3AN6`，全部 `spctl` accepted / Notarized Developer ID。没有改名前的旧 id，不需要 `BundleIDMigration`
- 嵌套组件的 id 也没变过: `us.eidinger.SwiftPlantUMLSourceEditorExtension`（1.0.0 起）、`us.eidinger.SwiftPlantUMLXPCService`（1.0.0 起）、`us.eidinger.SwiftPlantUMLActionExtension`（1.5.0 起才有）
- 其他轨: 11 个 tag（1.0.0–1.6.0）全是正式版，没有 prerelease，没有 beta/nightly 发版
- 版本范围: 1.0.0 的包里 `CFBundleShortVersionString` 是 `1.0`（tag `1.0.0`），比较照样是旧版。**1.4.0 的资产实际是 1.4.1 的构建**（两个 release 的 zip SHA-256 都是 `4edf29cb…05db`，包内 1.4.1(1)），所以从 1.4.0 资产装的副本读作 1.4.1，不影响检测
- 主机下限: 1.0.0 `LSMinimumSystemVersion` 11.0，1.3.0 起 10.15，都低于我们的下限；全部 universal（`x86_64 arm64`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `us.eidinger.SwiftPlantUML` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `MarcoEidinger/SwiftPlantUML-Xcode-Extension` GitHub Releases，`/releases/latest`
- 版本: tag 不带 `v`，`^([0-9]+(?:\.[0-9]+)+)$` 读 11/11 个 tag；`2.0.0`、`1.7` 能读，`1.7.0-rc.1`、`1.7.0-beta` 不匹配（锚定）
- 注意: 最近一版是 2024-01-02，仓库之后只有一个 CI 提交（`29539e2 ci: fix Homebrew Bump Formula Workflow`），基本不活跃

## 按架构 / 按 OS 分轨
- 一个 universal zip；不分轨

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见基本信息） | 每个 release 只有一个 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 1.5.1，没有更新器） | 不需要 |
| 证据 | 不下载任何东西（源码，见基本信息） | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify，1.5.1 起）: `source structured: 1 entries; newest 1.6.0: 1 items, headings ["Features"]; first items ["support `package` access level ([SE-0386"]`
- 1.6.0 正文是 `## Features`（一条列表）+ `## Internal Dependencies`（一句「uses SwiftPlantUML@0.8.0」，不是列表）。`Features` 标题保留、没被压平；`Internal Dependencies` 那节只有一段文字，面板里没有它（items 只有 1 条、headings 只有 Features）。依赖版本对用户不重要，不改
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（rule 有 `installAssetPattern`），真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）
  - 第一轮（不运行）: 1.5.1 → `duo check` `1.5.1 → 1.6.0 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.6.0、可执行文件 inode 变、`TeamIdentifier=6V66CC3AN6`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.6.0 包相同
  - 第二轮（运行中）: 启动 1.5.1，pkd 当即登记了两个扩展（`pluginkit -m -v`：`SwiftPlantUMLActionExtension(1.5.1)`、`SwiftPlantUMLSourceEditorExtension(1.5.1)`，未启用）；`duo install` 后提示 `Still running the old code`，`duo restart SwiftPlantUML` 后新进程起来，之后 10 s 磁盘一直是 1.6.0、签名有效；**换包后 pkd 自动把两个扩展重新登记为 1.6.0**
  - 没跑的：扩展**已启用**时换包后是否仍为 `+`、Xcode 开着时换包——启用要用户在系统设置里点，这次没做
- 格式: zip，根目录 `SwiftPlantUMLApp.app`。Pattern `^SwiftPlantUMLApp\.zip$`，kind `.zip`
- 签名: 1.5.1、1.6.0（以及更早的所有版本）Team `6V66CC3AN6`，Notarized，hardened runtime；Team 没换过，旧副本都过得了安装闸
- 校验: 资产没有 GitHub `digest`（`gh api …/releases/tags/1.6.0` 的 `digest` 为 null，2024 年上传，早于 GitHub 加摘要），只靠 Team-ID 闸。真包 SHA-256: 1.6.0 `74b2c77a…f067d`（6882756 字节）、1.5.1 `0c264321…91aa`（6925930 字节）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；README 的手动安装说明指向发布页）
- 阻塞: 无

### 外部组件：扩展与 XPC service（待审项结论）
包里的嵌套组件（1.6.0）:

| 路径 | id | 类型 |
|---|---|---|
| `Contents/PlugIns/SourceEditorExtension.appex` | `…SwiftPlantUMLSourceEditorExtension` | `com.apple.dt.Xcode.extension.source-editor`，sandbox |
| `Contents/PlugIns/ActionExtension.appex` | `…SwiftPlantUMLActionExtension` | `com.apple.services`（Finder 快速操作），sandbox |
| `Contents/XPCServices/XPCService.xpc`（两个 appex 里各有一份同 id 的） | `…SwiftPlantUMLXPCService` | `XPCService.ServiceType = Application` |

没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent plist，源码里没有 `SMAppService` / `SMLoginItemSetEnabled`。

- **XPC service 是按需起的，不常驻。** 两个扩展用 `NSXPCConnection(serviceName: "us.eidinger.SwiftPlantUMLXPCService")` 连它（源码 `GenDiagramInBrowser.swift`、`ActionRequestHandler.swift`）。Apple 文档：XPC service 由 launchd「launches them on demand … and terminates them (by sending SIGKILL) when they are idle」，且服务包在调用方 bundle 的 `Contents/XPCServices` 里查找（[Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)）。主 app 自己那份 `Contents/XPCServices/XPCService.xpc` 源码里没有人连（主 app 源码无 `NSXPCConnection`）
- **扩展进程由宿主拉起。** Apple 文档：宿主发请求才启动扩展，「An extension typically terminates soon after it completes the request」，且「the containing app isn't even running while a contained extension is running」（[App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html)）。Xcode Source Editor 扩展在 Xcode 开着时会不会一直挂着进程，Apple 文档没写；README 说首次启动初始化要约 30 s。**未验证**：Xcode 开着时换包，Xcode 可能还用着旧扩展进程，直到它退出或 Xcode 重启——这和用户手动拖新版覆盖完全一样，不损坏任何东西。新旧版本之间的 XPC 协议只增不改（`XPCServiceProtocol` 1.5.0 起多一个 `generateDiagram(for:)`），旧扩展连到新 service 也能用（推断，未实测）
- **启用状态（系统设置 › 通用 › 登录项与扩展 › Xcode Source Editor / Finder）。** `man pluginkit`（本机）:「Elections are applied to all plug-ins with given identifier」——用户的「use / ignore」选择按扩展 identifier 记，不按路径或版本记；换包后 identifier 不变（上表，1.0.0 起没变过）。按这个说明选择应保留，**未真机验证**，列为主会话的检查项
- **结论：一键直接开，不加 `OneClickGate`。** 没有常驻 helper；`OneClickGate` 是按版本/版本形态扣一键，跟「Xcode 开着」无关，加了也挡不住什么。最坏情况（Xcode 里还是旧扩展）与厂商唯一的更新方式（手动覆盖）一样

### 启动副作用（2026-10-22 真机核对的已注明）
- 首启：只开一个 Preferences 窗口（`ContentView` / `SettingsView`）；app 有 sandbox，写 `~/Library/Containers/us.eidinger.SwiftPlantUML`、group container `group.6V66CC3AN6.us.eidinger.SwiftPlantUML`（cask `zap` 段也列了 `~/Library/Application Scripts/…`、`~/Library/Group Containers/…`）。真机：首启建了 app 和两个扩展各自的 `Containers`、`Application Scripts`，以及 group container
- 登录项 / LaunchAgent / root helper: 包里和源码里都没有
- 系统 UI: 首次放进 `/Applications` 后 pkd 会登记两个扩展（不弹框）；不会自动启用，用户要在系统设置里勾
- 不往 `~/.claude` / `~/.agents` 写东西（源码无此类路径；sandbox 也写不到）
- 不改默认 app、壁纸、输入法；注册 URL scheme `swiftplantumlapp://`

## 已知问题
- `Internal Dependencies` 这类纯文字小节不进面板（见 Changelog）
- 1.4.0 的资产是 1.4.1 构建（见覆盖清单）

## 如何复验
```
gh api repos/MarcoEidinger/SwiftPlantUML-Xcode-Extension/releases/tags/1.6.0 --jq '.assets[]|.name+" "+(.size|tostring)+" "+(.digest//"null")'
.claude/skills/coverage-discovery/scripts/check-bundle.sh SwiftPlantUMLApp.zip         # → us.eidinger.SwiftPlantUML, 6V66CC3AN6, Notarized
ditto -x -k SwiftPlantUMLApp.zip out/
swift run --package-path application-test feed-discover out/SwiftPlantUMLApp.app         # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify out/SwiftPlantUMLApp.app --expect stable   # 1.5.1 → UPDATE 1.6.0；1.6.0 → up to date
pluginkit -m -v -A -i us.eidinger.SwiftPlantUMLSourceEditorExtension                      # 装好后看登记与 +/- 选择
```

## 建议下一步
1. 可补一轮：在系统设置里先启用 Xcode Source Editor 扩展再换包，然后用 `pluginkit -m -v -A -i us.eidinger.SwiftPlantUMLSourceEditorExtension` 确认仍是 `+` 且路径/版本是 1.6.0
2. 厂商发新版后复查资产名仍是 `SwiftPlantUMLApp.zip`
