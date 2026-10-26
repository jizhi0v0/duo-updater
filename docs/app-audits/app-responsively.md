# ResponsivelyApp

## 基本信息
- App: Responsively App — 做响应式网页开发用的浏览器（Electron），AGPL-3.0
- Bundle ID: `app.responsively`（helper 是 `app.responsively.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: 源码 `responsively-org/responsively-app`（默认分支 `main`，未归档）；安装包和 `latest-mac.yml` 发在只放 release 的 `responsively-org/responsively-app-releases`。0.x（2020–2022）的 release 在源码仓库里
- Team ID: `M4H33HFC4K`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.18.0（tag `v1.18.0`，资产 `ResponsivelyApp-1.18.0-arm64.dmg`）；上一版 1.17.1；beta 2.0.0-beta.0；观测日期: 2026-10-26
- 自更新机制: **electron-updater**（Mac 上由 Squirrel.Mac 落地）。settled from source: `desktop-app/src/main/app-updater.ts`（v1.18.0 与 `main` 相同的调用方式）在启动时 `autoUpdater.checkForUpdatesAndNotify()`，不改任何默认值，所以 `autoDownload = true`、`autoInstallOnAppQuit = true`：发现新版就自己下载，退出时安装。v1.18.0 锁 electron-updater 6.1.8，`main` 锁 6.8.10。包内 `Contents/Resources/app-update.yml`（1.17.1、1.18.0、2.0.0-beta.0 相同）: `owner: responsively-org`、`repo: responsively-app-releases`、`provider: github`、`updaterCacheDirName: responsivelyapp-updater`
- 分发: GitHub Releases；Homebrew cask `responsively`（`auto_updates true`，`url` 指 arm64 dmg）；App Store 没有（`itunes.apple.com/lookup?bundleId=app.responsively` 返回 0 条）
- 产品终止: 仓库未归档，README 和官网没有停止维护的说法

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓      | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。`ElectronManifestSource` 接不上：`app-update.yml` 是 `provider: github`，不给地址；`feed-discover` 对 1.18.0 dmg 的结论是 `review electronProviderNeedsConstruction`。cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v1.18.0: `app.responsively`，Team M4H33HFC4K，Notarized，arm64，`LSMinimumSystemVersion` 10.15
  - v1.17.1: 同 id、同 Team、Notarized
  - v1.0.1（releases 仓库里最老的正式版）: 同 id、同 Team（脚本读的）
  - v0.19.1（源码仓库，0.x 最后一版）: 同 id、同 Team、Notarized，`archs=x86_64`，`app-update.yml` 指 `repo: responsively-app`。v0.19.1 源码 `package.json` 的 `build.appId` 也是 `app.responsively`
  - 没有改名前的旧 bundle id。没有换过 Team
- 其他轨: beta（GitHub prerelease，同 id），见「Channel 详情」
- 版本范围:
  - releases 仓库 28 个 release：26 个正式版 `v1.0.1`…`v1.18.0` 都是 `vX.Y.Z`，stable `versionPattern` 全读；`v1.0.0-beta.6`、`v2.0.0-beta.0` 标了 prerelease，stable 模式不收，beta 模式收（28 个全读）
  - 每个 release 都有 `ResponsivelyApp-<v>-arm64.dmg`；不带架构词的 `ResponsivelyApp-<v>.dmg` / `-mac.zip` 是 x64。没有 universal
  - 0.x 副本（0.1.0–0.19.1）: 它们自己的 electron-updater 读源码仓库的 `/releases/latest`，那里今天是 `v1.18.0`，但这个 release 没有资产（2026-10-26 `gh api` 核对），所以它们自己升不上去。stable rule 照样回答它们（channel-verify 实测 0.19.1 → `UPDATE → 1.18.0`），一键装 arm64 dmg，Team 相同、闸会放行。0.x → 1.x 是厂商自己走过的路：源码仓库的 v1.0.1 release 带了 `latest-mac.yml` 和全部安装包，当时 0.x 的更新器就是这样被带到 1.0.1 的
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；arm64 dmg 的 `LSMinimumSystemVersion` 1.18.0 是 10.15、2.0.0-beta.0 是 13.0，都在下限之下，不需要 `hostRequirement`
- 同 id 下的其他产品: 没有

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.responsively` | 共享 | 默认 | `/releases/latest` | ✓ |
| beta    | `app.responsively` | 共享 | 版本号 `-beta.N`（`ReleaseChannel.detect` 读成 beta） | `.beta` rule 读 release 列表，正式版和 beta tag 都收 | ✓（一键，`recipeAnchor` proof） |

**beta 怎么来的（settled from source: `.github/workflows/publish.yml` on `main`）:**
- 手动触发的 workflow，输入 `channel` = `beta` / `stable`。beta 时 `yarn version --preid beta --prerelease`，`EP_PRE_RELEASE=true`，直接发成 GitHub prerelease；stable 去掉后缀、默认存草稿等人审
- app 里没有 beta 开关。用户是从 release 页面手动下 beta 的（v2.0.0-beta.0 正文「Download the installer for your platform from the assets below」）
- electron-updater 6.1.8 `AppUpdater.js`：`allowPrerelease = hasPrereleaseComponents(currentVersion)`，即正在运行的版本带 prerelease 部分时自动打开；`GitHubProvider.js` 在 `allowPrerelease` 且当前通道是 `beta` 时，遍历 `releases.atom`，取第一个既不是自定义通道、也不是 `alpha` 的条目，也就是最新的正式版或 beta。正式版副本（`allowPrerelease = false`）走 `/releases/latest`，看不到 beta
- 所以 beta rule 的模式 `^v([0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?)$` 同时收正式版和 beta tag，取列表里第一个，和厂商一致。今天给 beta 副本的是 2.0.0-beta.0；2.0.0 正式版发出来后，beta 副本会看到 2.0.0
- 真包 2.0.0-beta.0: `app.responsively`、Team M4H33HFC4K、Notarized、`CFBundleShortVersionString` = `CFBundleVersion` = `2.0.0-beta.0`、`LSMinimumSystemVersion` 13.0；channel-verify `inferred beta` → `GitHub`、`latest 2.0.0-beta.0`、`up to date`
- 一键给 beta 副本：用 `ChannelProof.recipeAnchor`（`usePrereleases` 为 true 或 `versionPattern` 含 `-beta\.`），和 SwitchHosts 同形；不用 artifact proof，因为 beta rule 故意也收正式版
- 2023 年的 `1.0.0-beta.6` 副本也读成 beta，会被 beta rule 提供 2.0.0-beta.0（列表第一个）。按上面的 electron-updater 6.1.8 逻辑，厂商更新器给它的也是列表第一个；1.0.0-beta.6 自带的 electron-updater 版本和它的 `app-update.yml` 指向没下包核（未验证）

## 更新检测
- 源: `responsively-org/responsively-app-releases` GitHub Releases；stable 读 `/releases/latest`，beta 读 release 列表（默认 20 条）
- 版本方案: tag `v1.18.0` → `CFBundleShortVersionString` `1.18.0`、`CFBundleVersion` `1.18.0`（electron-builder 取 `release/app/package.json` 的 `version`）
- stable `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`v2.0.0-beta.0` 不读，`v2.0.0`、`v2.1` 读）
- stable install pattern `^ResponsivelyApp-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`；beta `^ResponsivelyApp-[0-9]+(?:\.[0-9]+)+(?:-beta\.[0-9]+)?-arm64\.dmg$`。同一 release 里另外的 `ResponsivelyApp-<v>.dmg`、`-mac.zip`（x64）、`-arm64-mac.zip`（electron-updater 用的）、`.blockmap`、`latest*.yml` 都不匹配
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，厂商更新器给正式版副本读的也是它）；beta 副本读的是列表里最新的正式版或 beta，和厂商更新器给 beta 副本的相同，也都是 release 页上公开的包
- `GitHubListPageSizeTests`: `app.responsively/beta` 下限 1（2026-10-26 全部 28 个 release 都匹配 beta 模式，第一个就命中）

## 按架构 / 按 OS 分轨
- 每版两套 Mac 资产：`-arm64.dmg` / `-arm64-mac.zip` 是 arm64，不带架构词的 `.dmg` / `-mac.zip` 是 x64（`package.json` `build.mac.target.arch` = `["arm64","x64"]`，没有 universal）。arm64 dmg `archs=arm64`
- `latest-mac.yml` 列出四个文件，没有 OS 上下限字段。`LSMinimumSystemVersion`: 1.x 10.15，2.0.0-beta.0 13.0

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 | 不能 |
| 证据 | electron-updater 6.1.8 / 6.8.10 | v1.18.0、v2.0.0-beta.0 的 release 带 `-arm64-mac.zip.blockmap` 等 blockmap 资产（2026-10-26 `gh api`） | `DeltaApplier` 只吃 Sparkle binary delta 和 MyGo；没有消费 blockmap 的机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有 blockmap 机制；全量 arm64 dmg 约 112 MB（1.18.0）

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（`autoDownload` 默认开） | 没查（真机第二轮待主会话） | 没查（布局 `SelfUpdaterStash` 已读） |
| 证据 | `app-updater.ts` 只调 `checkForUpdatesAndNotify()`；`app-update.yml` `updaterCacheDirName: responsivelyapp-updater` | — | `SelfUpdaterStash` 的 `.electronUpdater(cacheDirectoryName:)` 从包内 `app-update.yml` 读目录名，读 `~/Library/Caches/responsivelyapp-updater/pending/update-info.json` |

- 记录文件与字段: electron-updater 的 `pending/update-info.json`（下载完成并校验 `sha512` 后写）
- 容器: electron-updater 在 Mac 上下的是 zip（`ResponsivelyApp-<v>-arm64-mac.zip`），包根是 `ResponsivelyApp.app`
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`；`SelfUpdaterStash` 的归属闸处理

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`，`GitHubMarkdownParser`）
- 结构化（2026-10-26，channel-verify `changelog pane`）:
  - 从 1.17.1: `source structured: 1 entries; newest 1.18.0: 5 items, headings []; first items ["Added important devices", "Fixed non rotatable devices rotating whe", "fix: disable fullscreen on F while typin"]`
  - 从 2.0.0-beta.0: `source structured: 1 entries; newest 2.0.0-beta.0: 11 items, headings ["What\'s Changed"]; first items ["**A completely redesigned interface** — ", "**New Canvas mode** — freely arrange dev", "**Real device frames** — see your websit"]`
- v1.18.0 正文只有一个 `## What's Changed`（5 条）加 `## New Contributors` 和 `**Full Changelog**`：5 条全在，`headings []` 里没有 `What's Changed`，但它的文字也不在 items 里，不是被压平成条目；New Contributors 按设计丢掉。v2.0.0-beta.0 的正文开头有段落，`What's Changed` 标题保留，11 条全在
- 跟随 channel: 是（beta rule 读到的 release 正文就是 beta 的）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（stable 副本，含 0.x；beta 副本经 `recipeAnchor` proof）
- 端到端: 待主会话
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `ResponsivelyApp.app` + `Applications` 软链
- 嵌套: 只有 `Contents/Frameworks` 下四个 Electron helper（`LSUIElement`）和 `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`；没有 `Contents/Library/LoginItems`、`Contents/Helpers`。1.18.0 和 2.0.0-beta.0 的 `app.asar` 里 `setLoginItemSettings`、`openAtLogin`、`LaunchAgents`、`SMAppService` 都是 0 次
- 签名: 0.19.1、1.0.1、1.17.1、1.18.0、2.0.0-beta.0 都是 Team `M4H33HFC4K`、Notarized Developer ID；Team 没换过，上一版不会被闸拒
- 校验: GitHub 资产 `digest`。v1.18.0 arm64 dmg `sha256:870ef97ae7b23758411841f0c35058ddd36ba2dce51b1f8a48063664dc12d92b`、v1.17.1 `sha256:e7f0e6127182c5a749c6cde485d13258bb75062aad940b4ae3bdd69c90e09549`、v2.0.0-beta.0 `sha256:c32f1d6808e143af056ed342f947a18448cd1b281d7945ec3a6f7d8d9fcb1260`，都与下载文件的 `shasum -a 256` 相同。v1.16.0（2025-01）的资产没有 `digest`（GitHub 2025-06 才开始给），它不是安装目标。`latest-mac.yml` 的 `sha512` 不接
- **读的是**: 人人可手动下载的 GA（stable）；beta 副本读最新的公开 release（正式版或 beta），和厂商更新器一致
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 启动即检查更新并**自动下载**，退出时由 Squirrel ShipIt 安装。从 1.17.1 启动会在 `~/Library/Caches/responsivelyapp-updater/pending/` 停放 1.18.0 的 arm64 zip；第二轮可期望 `local stash hit`（同版本），或 duo 让路给已暂存的同版本（massCode 的同形）
  - 1.x 首次启动调 `installExtensions()`（`electron-devtools-assembler`），从 Chrome 扩展商店下载 React/Redux/Vue 等开发者工具扩展到 app 的 userData；数据目录 `~/Library/Application Support/ResponsivelyApp`、偏好 `~/Library/Preferences/app.responsively.plist`（cask `zap`）
  - 注册 `responsively://` URL scheme（`setAsDefaultProtocolClient`，v1.18.0 与 `main` 都有）
  - 2.0.0-beta.0 起默认在本机端口起一个 MCP HTTP 服务（`userPreferences.mcpEnabled` 未设为 false 时），并往 userData 写 beacon 文件；往 `~/.claude.json`、`claude_desktop_config.json`、`~/.cursor/mcp.json`、`~/.codex`、VS Code 的 `mcp.json` 写配置只在设置页点了添加时发生（`ipcMain.handle(MCP_SET_TOOL)` → `setToolEntry`）。1.18.0 的 `app.asar` 里没有 `.claude` 字符串
  - 没有登录项、LaunchAgent、root helper

## 已知问题
- 0.x 副本自己的更新器读源码仓库 `/releases/latest`（v1.18.0，无资产），升不上去；由本 rule 回答，一键装 arm64 dmg
- 1.18.0 的 changelog 面板不显示唯一的 `What's Changed` 标题（条目完整）

## 如何复验
```bash
gh release view v1.18.0 -R responsively-org/responsively-app-releases --json assets -q '.assets[]|select(.name|test("arm64\\.dmg$"))|.name+" "+.digest'
gh release download v1.18.0 -R responsively-org/responsively-app-releases -p 'ResponsivelyApp-1.18.0-arm64.dmg'
gh release download v1.17.1 -R responsively-org/responsively-app-releases -p 'ResponsivelyApp-1.17.1-arm64.dmg'
gh release download v2.0.0-beta.0 -R responsively-org/responsively-app-releases -p 'ResponsivelyApp-2.0.0-beta.0-arm64.dmg'
gh release download v0.19.1 -R responsively-org/responsively-app -p 'ResponsivelyApp-0.19.1.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh ResponsivelyApp-1.18.0-arm64.dmg   # app.responsively, M4H33HFC4K, Notarized, electron-updater github
swift run --package-path application-test feed-discover ResponsivelyApp-1.18.0-arm64.dmg      # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify ResponsivelyApp-1.17.1-arm64.dmg --expect stable
swift run --package-path application-test channel-verify ResponsivelyApp-1.18.0-arm64.dmg --expect stable
swift run --package-path application-test channel-verify ResponsivelyApp-2.0.0-beta.0-arm64.dmg --expect beta
swift run --package-path application-test channel-verify ResponsivelyApp-0.19.1.dmg --expect stable
```

channel-verify 原始输出（2026-10-26）:
```
1.17.1: detected channel → stable; winning source GitHub; latest 1.18.0;
  download https://github.com/responsively-org/responsively-app-releases/releases/download/v1.18.0/ResponsivelyApp-1.18.0-arm64.dmg;
  status UPDATE → 1.18.0
1.18.0: detected channel → stable; winning source GitHub; latest 1.18.0; status up to date
2.0.0-beta.0: inferred beta; detected channel → beta; winning source GitHub; latest 2.0.0-beta.0;
  download https://github.com/responsively-org/responsively-app-releases/releases/download/v2.0.0-beta.0/ResponsivelyApp-2.0.0-beta.0-arm64.dmg;
  status up to date
0.19.1: detected channel → stable; winning source GitHub; latest 1.18.0;
  download https://github.com/responsively-org/responsively-app-releases/releases/download/v1.18.0/ResponsivelyApp-1.18.0-arm64.dmg;
  status UPDATE → 1.18.0
```

## 建议下一步
1. 主会话真机两轮（上一版 1.17.1 → 1.18.0），结果写回「一键安装」并把 README 行改成 ✓；第二轮记下 `responsivelyapp-updater/pending/` 停放的那份
2. 2.0.0 正式版发布时读它的 release notes，看 1.x → 2.0 有没有要求先迁移数据；厂商更新器会自动把 1.x 正式版副本升上去，若有破坏性迁移再考虑 `OneClickGate`
