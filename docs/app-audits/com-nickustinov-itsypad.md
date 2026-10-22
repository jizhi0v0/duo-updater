# Itsypad

## 基本信息
- App: Itsypad — 草稿本 + 剪贴板管理器（编辑器窗口 + 菜单栏图标），MIT 开源
- Bundle ID: `com.nickustinov.itsypad`（31 个带资产的 GitHub 版本全部一致；Mac App Store 版同 id，见下）
- 仓库: `nickustinov/itsypad-macos`（默认分支 `main`；2026-10-22 `main` 与 `v1.18.0` 之间没有差异，`compare v1.18.0...main` ahead_by 0）
- Team ID: `R892A93W42`（Developer ID Application: Nikolajs Ustinovs）；只有 1.0.1 是 `6484NTXXS4`（Developer ID Application: StoryjarApp, Inc.），见「覆盖清单」
- 观测版本: 1.18.0（`CFBundleVersion` 118001）；上一版 1.17.0（117001）；观测日期: 2026-10-22
- 自更新机制: **只提示**。settled from source: `Sources/App/UpdateChecker.swift` on `main`（与 `v1.17.0` 的同名文件逐字相同）。只有「Check for updates...」菜单项（app 菜单、状态栏菜单各一个，`AppDelegate.checkForUpdates`）会调用它：读 `api.github.com/repos/nickustinov/itsypad-macos/releases/latest` 的 `tag_name` 和 `html_url`，比 `CFBundleShortVersionString`，新就弹 `NSAlert`，点「Open downloads」用 `NSWorkspace.open` 打开 release 网页。不下载、不暂存、不换包；启动时不自动检查（源码里 `UpdateChecker.check()` 唯一的调用点就是 `checkForUpdates`）。整个文件在 `#if !APPSTORE` 里，商店版没有。1.3.0 起才有（v1.3.0 release 说明；1.0.0–1.0.5 的可执行文件里没有这个 URL，1.3.0 起 26 个版本都有）
- 分发: GitHub Releases（每版一个 dmg）；Homebrew cask `itsypad`（官方 homebrew-cask，BrewTestBot autobump，`auto_updates` 未设，url 指向同一个 GitHub dmg）；Mac App Store `id6758999332`（付费，iPhone/iPad/Mac 通用购买）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用） | ✓（通用） | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测，对 dmg 里的非商店副本）。brew 装的副本由排在前面的 `HomebrewCaskSource` 应答（cask 不是 `auto_updates`）；商店副本只由 `MacAppStoreSource` 应答。`feed-discover` 对 1.17.0 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（31 个带资产的 release 全部下了真包，`check-bundle.sh`）：bundle id 全是 `com.nickustinov.itsypad`，全部 `Notarized Developer ID`、`codesign --verify --deep --strict` 通过、universal（`x86_64 arm64`）。Team：只有 **1.0.1** 是 `6484NTXXS4`，其余 30 个（含 1.0.0、1.17.0、1.18.0）都是 `R892A93W42`。1.0.1 的副本一键会被 Team 闸拒（`teamIdentifierMismatch`），检测照常显示更新，用户手动更新一次后就回到 `R892A93W42`。这是同一个 app、同一个仓库，只是那一版用另一个开发者账号签的，不是需要 gate 隔开的另一个产品
- 包名大小写：1.0.0–1.6.0 的资产是 `itsypad-<version>.dmg`、里面是 `itsypad.app`；1.8.2 起是 `Itsypad-<version>.dmg`、`Itsypad.app`。两段的 `CFBundleExecutable` 都是 `Itsypad`、`CFBundleName` 都是 `Itsypad`。规则只装最新版的资产，pattern `^[Ii]tsypad-…\.dmg$` 两种都收，免得厂商改回小写时被当成「没有 macOS 资产」往回走
- 没有资产的 release：v1.0.2、v1.8.0、v1.8.1 一个资产都没有（API `assets: []`）。分诊说的「v1.0.0 没有资产」不对：v1.0.0 有 `itsypad-1.0.0.dmg`，是脚手架的 pattern `^Itsypad-` 区分大小写才没匹配上（小写的共 14 个：1.0.0–1.6.0）。资产缺失的 release 若成为最新，`GitHubReleasesSource` 会退到 releases 列表往回找带资产的那一版
- 其他轨：没有。34 个 release 都不是 prerelease，也没有 draft；34 个 tag 和 34 个 release 一一对应；仓库里没有 beta/nightly 的构建脚本，`scripts/build-release.sh` 只出一个 Developer ID dmg
- Mac App Store 版：`project.yml` 的 `Release-AppStore` 配置用同一个 `PRODUCT_BUNDLE_IDENTIFIER: com.nickustinov.itsypad`；iTunes lookup（2026-10-22，`?bundleId=com.nickustinov.itsypad&country=us`）`trackId 6758999332`、`bundleId com.nickustinov.itsypad`、`version 1.2.1`、`price 5.99`，版本线和 GitHub 不同步。商店副本不会走到这条规则：`UpdateChecker` 对 `isMASApp` 只问 `answersAppStoreCopies` 的源（`UpdateChecker.swift` 168、387 行），`GitHubReleasesSource.latestVersion` 里另有 `guard !app.isMASApp`（801 行）
- 版本范围、主机下限：所有版本 `LSMinimumSystemVersion` 14.0（cask 写 `>= 14`），不高于 DuoUpdater 自己的下限，不用门控；全部 universal

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.nickustinov.itsypad` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `nickustinov/itsypad-macos` GitHub Releases，`/releases/latest`
- 版本: tag `v1.18.0` → `^v([0-9]+(?:\.[0-9]+)+)$` → `1.18.0`，等于 `CFBundleShortVersionString`（settled from source: `build-release.sh` 从 `project.yml` 的 `MARKETING_VERSION` 取版本、`gh release create v$VERSION`）。34/34 个 tag 都读得出；`v2.0.0`、`v1.19` 读得出，`v1.19.0-rc.1`、`v1.19.0-beta`、不带 `v` 的 `1.19.0` 不匹配（锚定）
- `CFBundleVersion` 是递增整数（100…197、1100…1160、117001、118001），不参与比较
- 注意事项: 无

## 按架构 / 按 OS 分轨
- 架构: 每版一个 universal dmg（`x86_64 arm64`）；`LSMinimumSystemVersion` 14.0（每版相同）。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 自带检查只打开网页（上面的源码） | 每个 release 最多一个 dmg 资产（API 2026-10-22） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（未做真机第二轮） | 不需要 |
| 证据 | `UpdateChecker.swift` 不下载任何东西 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 1.17.0 起）: `source structured: 1 entries; newest 1.18.0: 3 items, headings []; first items ["Indent and outdent lines with ⌘] and ⌘[,", "Markdown notes with code blocks no longe", "Mouse-wheel scrolling now scrolls the ta"]`。1.18.0 的正文就是三条不带小标题的列表，3 条全在，没有压平
- 全部 34 个 release body 跑了生产解析器（临时测试调用 `GitHubMarkdownParser.parse`，跑完已删）：
  - 有两个以上小标题的正文，小标题作为 heading block 保留：1.0.1（Bug fixes / Improvements）、1.4.1（New features / Fixes）、1.8.0、1.8.1（Features / Fixes）
  - 只有一个盖住全部条目的小标题（1.5.0 `## Features`、1.9.0 `## What's new`、1.9.1 `## Fixes`）时小标题被丢掉，条目都在、没有混进 items
  - 1.3.0 的正文把没单独发 release 的 1.2.0、1.1.0 也写在里面（`### 1.2.0`、`### 1.1.0`），解析器全部收成 26 条，`Features:` / `Improvements:` 这类冒号行不是 Markdown 小标题、被丢掉。只在 1.3.0 是最新版时才会显示，现在不影响
  - 1.0.0 正文只有一行 Full Changelog 链接，解析为 nil
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（规则已开；真机端到端未跑，由主会话做）
- 格式: dmg（`hdiutil imageinfo` Format UDZO），根目录 `Itsypad.app` + `Applications` 软链。kind `.dmg`
- 嵌套: 1.8.2 起 `Contents` 下只有 `Info.plist`、`MacOS`、`PkgInfo`、`Resources`、`_CodeSignature`、`embedded.provisionprofile`：没有 LoginItems / Helpers / XPC / Frameworks / LaunchAgent plist（1.0.0–1.0.5 带一个 `CodeLanguages_Container.framework`，1.3.0 起去掉）。「Open at login」是设置里的开关，`SMAppService.mainApp.register()` 把 app 本身登记为登录项，默认关（`SettingsStore.launchAtLogin = false`），没有常驻 helper
- 沙盒: Developer ID 版也带 `com.apple.security.app-sandbox`，外加 CloudKit / iCloud KVS、`network.client`、`~/Library/Application Support/Itsypad/` 的临时例外（旧版数据迁移用）；数据在 `~/Library/Containers/com.nickustinov.itsypad`
- 签名: 1.17.0、1.18.0 都是 `TeamIdentifier=R892A93W42`，`spctl` Notarized Developer ID；1.0.1 的 Team 例外见「覆盖清单」
- 校验: GitHub 资产 `digest`。下载的 1.17.0 / 1.18.0 dmg `shasum -a 256` 分别为 `8cf7bb25…304c68` / `d93d98de…2cff7bbe`，与 API 的 `digest` 相同，字节数等于资产大小（3519026 / 3535231）；其余 29 个包同样一致
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 的下载说明指向 GitHub releases）
- 端到端: 未跑（这一轮的接入不做真机）。主会话真机时注意（均读自 `main` 源码，未在运行中观察）：
  - 启动即显示编辑器窗口并 `NSApp.activate(ignoringOtherApps: true)` 抢前台（`AppDelegate.setupEditorWindow`）；首次启动在窗口里放一个「Welcome to Itsypad」标签页，不是模态框
  - 启动时按设置注册全局热键（`HotkeyManager.shared.register()`；无设置时的默认是三击左 Option，是否因此触发输入监控/辅助功能授权框未验证）、默认开剪贴板监控（`clipboardEnabled` 默认 true），会把运行期间的剪贴板内容记进它自己的历史
  - iCloud 同步默认开（`icloudSync` 默认 true，`SettingsStore` 339 行），启动时 `registerForRemoteNotifications` 并经 CloudKit 同步标签页和剪贴板历史到登录的 iCloud 账号。真机验证会把测试期间的内容写进那个账号的私有库，验完要在设置里关掉或清理（未验证实际写入了什么）
  - 「粘贴到别的 app」才会弹它自己的辅助功能提示框（`AccessibilityHelper.requestPermission`），启动不弹
  - 自带检查不会和我们抢；不点菜单就不联网查更新
- 阻塞: 无

## 已知问题
- 从 1.6.0 及更早（`itsypad.app`）一键到 `Itsypad.app`：bundle 目录名的大小写变了（可执行文件名两段都是 `Itsypad`）。安装器在原路径换包，换完的目录名是否保持小写没有验证（我的推断：不影响启动）
- 1.0.1 的副本一键被 Team 闸拒，见「覆盖清单」

## 如何复验
```
gh api repos/nickustinov/itsypad-macos/releases --paginate -q '.[]|.tag_name+" "+([.assets[]|.name+" "+.digest]|join(" "))'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Itsypad-1.17.0.dmg Itsypad-1.18.0.dmg itsypad-1.0.1.dmg   # Team R892A93W42 / R892A93W42 / 6484NTXXS4
swift run --package-path application-test feed-discover Itsypad-1.17.0.dmg                  # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify Itsypad-1.17.0.dmg --expect stable # → GitHub，UPDATE → 1.18.0
swift run --package-path application-test channel-verify itsypad-1.6.0.dmg --expect stable  # → GitHub，UPDATE → 1.18.0
swift run --package-path application-test channel-verify itsypad-1.0.1.dmg --expect stable  # → GitHub，UPDATE → 1.18.0
swift run --package-path application-test channel-verify Itsypad-1.18.0.dmg --expect stable # → up to date
curl -sS "https://itunes.apple.com/lookup?bundleId=com.nickustinov.itsypad&country=us"      # 商店版 bundleId com.nickustinov.itsypad, 1.2.1
```

## 建议下一步
1. 主会话真机端到端：1.17.0 → 1.18.0，不运行 + 运行中 + `duo restart`，然后把 README 那一行的「一键端到端待主会话」换成结果。
