# Porting Kit

## 基本信息
- App: Porting Kit — 用 Wine 封装（Wineskin 等引擎）安装、管理 Windows 游戏和软件的 Electron 应用
- Bundle ID: `com.paulthetall.portingkit`
- 仓库: `vitor251093/porting-kit-releases`（只放发布产物，`main` 分支只有一个 README；源码在 Bitbucket，`package.json` 的 `repository`）
- Team ID: `45WEPZ3433`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 6.7.0（tag `v6.7.0`，资产 `Porting.Kit-6.7.0-arm64.dmg`）；上一版 6.5.0；观测日期: 2026-10-26
- 自更新机制: **electron-updater**（Squirrel.Mac / ShipIt 换包）。settled from source（6.7.0 与 6.5.0 的 `app.asar` → `maino.js`，主进程）:
  - `const _ = 1 == store.get("experimentalFeatures"); _ || autoUpdater.setFeedURL({provider:"github", owner:"vitor251093", repo:"porting-kit-releases"})`。`store` 是 `electron-store`，`name: "userData"`，即 `~/Library/Application Support/portingkit/userData.json`（目录名与 cask 的 zap 一致；文件名见 changelog 4.x 条目「PK's userData.json file」，真机上未核）
  - 偏好关时读本仓库；开着时不覆盖，沿用包内 `Contents/Resources/app-update.yml`（`provider: github`、`repo: porting-kit-releases-dev`、`updaterCacheDirName: portingkit-updater`，另带厂商自己的 `token` 字段，本文不抄录）
  - 没有改 `autoDownload` / `autoInstallOnAppQuit`（`maino.js` 里 `autoDownload` 只出现在库的默认值和库内部，共 2 处），所以一次检查就会自己下载，退出时由 ShipIt 装上。`update-available` 时：偏好 `automaticUpdate` 为 true 走 `checkForUpdatesAndNotify`，否则弹「Software Update」窗口
- 分发: GitHub Releases（本仓库）；Homebrew cask `porting-kit`（`auto_updates true`，arm 装 `-arm64.dmg`、Intel 装无架构词的 dmg，6.7.0）；不在 Mac App Store（`itunes.apple.com/lookup?bundleId=com.paulthetall.portingkit` 返回 0 条）
- 产品终止: 官网首页、两个仓库都没有停更说法（仓库未 archived）；本仓库最近一版 2025-11-19，实验仓库 2025-12-19

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                  | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------------|---------|----------|-----|--------|-------------|
| **stable**       | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **experimental** | —       | —        | —   | ○（需 `ChannelBinding`） | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。无 `SUFeedURL`、无 MyGo；`app-update.yml` 是 `provider: github` 无 `url`，feed-discover 报 `review electronProviderNeedsConstruction`（6.7.0）。4.x 的 `app-update.yml` 是 `provider: generic`、`url: https://portingkit.com/pub/portingkit/`，那个 `latest-mac.yml` 2026-10-26 仍停在 6.3.2（feed-discover 对 4.1.6 报 `electronVersionMismatch`）；`SourceStack` 里 `GitHubReleasesSource` 排在 `ElectronManifestSource` 前面，所以 4.x 副本也由 GitHub 回答（channel-verify 实测）。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v6.7.0 arm64 dmg: `com.paulthetall.portingkit`，Team 45WEPZ3433，Notarized，arm64
  - v6.5.0 dmg（上一版，只有这一种 dmg）: 同 id、同 Team、Notarized，**x86_64**
  - v4.1.6（列表里最老的一版）: 同 id、同 Team、Notarized，x86_64，`LSMinimumSystemVersion` 10.10.0
  - 实验仓库 v6.6.3 arm64 dmg: 同 id、同 Team、Notarized、arm64
  - 没有改名前的旧 bundle id（4.1.6 起都是这一个；cask 只认这一个）
- 其他轨: 实验轨（见「Channel 详情」）。本仓库 34 个 release 全是 `prerelease: false`、非草稿；tag 里另有 `v4.2.20-2`、`v4.2.23` 两个没有 release 的 tag
- 版本范围: 34 个 release 的 tag 都是 `v<数字>(.<数字>)+`，`versionPattern` 全读得出；锚定后 `v4.2.20-2` 不匹配，`v7.0`、`v7.0.0` 匹配
- 架构: 只有 6.7.0 带 arm64 dmg；6.5.0 及更早只有 x86_64 dmg。install pattern 只取 `-arm64.dmg`：无架构词的 dmg 是 Intel 单架构（cask 的 `intel:` sha 就是它），引擎会把无架构词当成通用包，放进来会在下一次没有 arm64 包的发布里把原生副本换成 Intel 版
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Porting Kit `LSMinimumSystemVersion` 10.13.0（6.7.1 实验版改成 10.15，见其 `CHANGES`），都在下限之下，不需要 `hostRequirement`
- 资产命名: 厂商在 `Porting-Kit-<v>` 与 `Porting.Kit-<v>` 之间换过（6.6.3 实验版是连字符，6.7.0 是点号，后者是 GitHub 对文件名里空格的改写），pattern 两种都收

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.paulthetall.portingkit` | 共享 | `experimentalFeatures` 不为 1 | GitHub `porting-kit-releases` `/releases/latest` | ✓ |
| experimental | `com.paulthetall.portingkit` | 共享 | `userData.json` 的 `experimentalFeatures` == 1 | feed-swap 到 `porting-kit-releases-dev` | ○ |

- 实验轨 settled from source（见「基本信息」的 `maino.js` 摘录）：同一个构建，按偏好换仓库，不是按包区分。实验仓库是公开仓库，release 也都是 `prerelease: false`，2026-10-26 最新 v6.7.1（`CHANGES`: 「Changing minimum required macOS version to 10.15」），还有 6.6.0–6.6.3 等本仓库没有的版本；两边都有的版本是同一份字节（6.7.0 arm64 dmg 的 GitHub digest 两边都是 `sha256:7e33b70e…5fbf5a`，Intel dmg 两边都是 `sha256:2f19f92a…b0ab`）
- 我们对实验副本做了什么: 判成 stable，由本 rule 回答。6.7.1 读成 up to date；6.6.x 读成 → 6.7.0 并可一键（真包 6.6.3 channel-verify 实测）。装进去的 6.7.0 与实验仓库的 6.7.0 是同一份字节，偏好还在，它下次检查照样读实验仓库，所以不会被我们拉离实验轨；代价只是这类副本看到的是 stable 视角（实验仓库有更新的构建时行上仍显示 up to date）
- 真正接上实验轨需要一个读 `userData.json` `experimentalFeatures` 的 `ChannelBinding` 加一个读 `porting-kit-releases-dev` 的 `.beta` 规则，是引擎（`Sources/`）改动，本次没做，见「建议下一步」

## 更新检测
- 源: `vitor251093/porting-kit-releases` GitHub Releases，`/releases/latest`
- 版本方案: tag `v6.7.0` → `CFBundleShortVersionString` `6.7.0`、`CFBundleVersion` `6.7.0`（三个真包都是 short == build == tag）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^Porting[.-]Kit-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`。v6.7.0 里被排除的: `Porting.Kit-6.7.0.dmg`（x86_64）、`Porting.Kit-6.7.0-arm64-mac.zip`、`Porting.Kit-6.7.0-mac.zip`（electron-updater 用的 zip）、两个 `.blockmap`、`latest-mac.yml`、`changelog.html`
- 下一次发布若没有 arm64 dmg（6.5.0 及更早都没有），`GitHubReleasesSource` 会往回找带 arm64 dmg 的 release（最多跳过 5 个），行上显示的是旧版本；这是 pattern 有意的选择，不拿 Intel 包换原生副本
- 厂商 `latest-mac.yml` 里的文件名和真实资产对不上：6.7.0 的清单写 `Porting-Kit-6.7.0-mac.zip`、`Porting-Kit-6.7.0-mac-arm64.zip`，资产叫 `Porting.Kit-6.7.0-mac.zip`、`Porting.Kit-6.7.0-arm64-mac.zip`。2026-10-26 `curl -I -L` 实测清单里两个名字都是 404、真实名字 200。electron-updater 的 GitHub provider 照清单名拼下载地址（`maino.js`: `getBaseDownloadPath(tag, name.replace(/ /g, "-"))`），所以从 6.5.0 自更新到 6.7.0 应当会下载失败（推断，未在真机上跑）

## 按架构 / 按 OS 分轨
- 6.7.0 分架构资产（arm64 dmg、x86_64 dmg 各一份）；6.5.0 及更早只有 x86_64；`LSMinimumSystemVersion` 10.13.0；release 不声明 OS 上限
- 厂商自己的更新器在 Apple Silicon 上（包括 Rosetta 下跑的 Intel 版）选 arm64 包：`maino.js` MacUpdater 读 `sysctl.proc_translated`、`uname -a`，有 arm64 文件就只留 arm64。我们把 Intel 6.5.0 一键换成 arm64 6.7.0，与厂商这一选择一致

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 blockmap 文件 | 不能 |
| 证据 | `maino.js` 里 `disableDifferentialDownload` 默认 false，`differentialDownload` / `.blockmap` 共 9 处 | v6.7.0 release 带 `Porting.Kit-6.7.0-arm64-mac.zip.blockmap`、`-mac.zip.blockmap`（2026-10-26 release 列表） | 引擎的 `DeltaApplier` 只吃 Sparkle / MyGo 补丁；blockmap 只在 `ElectronManifest` 里被跳过，没有差分下载实现 |

- 格式: electron-builder blockmap（针对 zip，不是二进制补丁）
- 阻塞项: 需要新机制；收益只是少下一部分 zip，而一键装的是 dmg

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 没查（真机第二轮待主会话） | 能（已接，electron-updater 布局） |
| 证据 | electron-updater 默认 `autoDownload`，`app-update.yml` `updaterCacheDirName: portingkit-updater` → `~/Library/Caches/portingkit-updater/pending/` | — | `SelfUpdaterStash.electronUpdater` 读 `updaterCacheDirName`，zip 暂存也能给 dmg 路由用 |

- 记录文件与字段: `pending/update-info.json`（`fileName`、`sha512` base64、`isAdminRightsRequired`），下载完成后才写（electron-updater `setDownloadedFile`）
- 容器: zip（electron-updater 在 macOS 只下 zip），包根是 `Porting Kit.app`（推断，未解开厂商 zip 核对）
- 两份副本会不会共用这个目录: 会，目录名只跟 `updaterCacheDirName` 走；同 id 只有这一个产品
- 实际能否停放到 6.7.0: 见「更新检测」最后一条，清单文件名 404，按推断会下载失败、什么也不停放

## Changelog
- 来源: **recipe**。release 正文只有 tag（`v6.7.0`），GitHub 源的结构化结果是 1 条「v6.7.0」，没有信息量；每个 release（5.0.4 起）带一个 `changelog.html` 资产，是从新到旧的完整历史，`Porting Kit 6.7.0 (19/11/2025):` 后接 `<ul><li>…</li></ul>`。`ChangelogRecipe` 读 `releases/latest/download/changelog.html`
- 结构化（2026-10-26，channel-verify `changelog pane`）: `recipe changelog:com.paulthetall.portingkit:-: 40 entries; newest 6.7.0: 1 items, headings []; first items ["Introducing proper Silicon builds"]`。没有标题可保留（厂商每个版本只有一个平铺列表），不是被压平
- 加 recipe 前同一行是 `source structured: 1 entries; newest 6.7.0: 1 items, headings []; first items ["v6.7.0"]`
- 真文件 193 个版本块全部匹配；两个空 `<ul>` 的块（重复的 6.1.2、4.2.30）不产出条目（`PortingKitChangelogRecipeTests` 断言）。日期是日/月/年，原样保留
- 跟随 channel: 文件跟着 stable release 走，顶条就是 stable 版本；两次 stable 之间只在实验仓库发的版本（6.6.0–6.6.4）照厂商原文列在里面
- Recipe 状态: 已有（本次新增）

## 一键安装
- 状态: 支持（端到端待主会话）
- 端到端: 待主会话（真机从上一版装到最新版）
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `Porting Kit.app`
- 嵌套: `Contents/Frameworks/Porting Kit Helper.app`、`Helper (GPU)`、`Helper (Renderer)`、`Helper (Plugin)`，都是 Electron 的子进程（`LSUIElement=true`），随主进程退出；没有 `Contents/Library/LoginItems`、`Helpers`、LaunchAgent / LaunchDaemon；`maino.js` 里没有 `setLoginItemSettings`、`SMAppService`、`LaunchAgents`、`with administrator privileges`、`.claude`
- 签名: 4.1.6、6.5.0、6.6.3（实验仓库）、6.7.0 都是 Team `45WEPZ3433`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产 `digest`。v6.7.0 arm64 dmg `sha256:7e33b70e326c7e5a99c531b65b678b605c44aaa107f51688777ad5dd9e5fbf5a`，下载文件 `shasum -a 256` 相同、142767508 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Porting Kit 默认偏好下自己的更新器读的也是这个仓库）
- 阻塞: 无
- 主会话真机要注意（来自包内容与 `app.asar`，均未在真机上观察）:
  - 上一版 6.5.0 是 x86_64，没装 Rosetta 的机器上启动它会弹系统的 Rosetta 安装框；要原生的上一版可用实验仓库的 `Porting-Kit-6.6.3-arm64.dmg`（同 id、同 Team、Notarized，channel-verify → 6.7.0）
  - 首启有启动向导（4.x/6.4 changelog：麦克风权限说明页、Antivirus 窗口、分析选项），可能触发麦克风 TCC 框（`NSMicrophoneUsageDescription` 写着用来「explicit deny」）
  - 启动后会检查更新并自动下载；从 6.5.0 起这次下载按推断会 404 失败；弹「Software Update」窗口时不要点安装。若真下完了，退出 app 会由 ShipIt 装上它暂存的版本
  - 写 `~/Library/Application Support/portingkit/`（`userData.json` 等）、`~/Library/Caches/portingkit-updater/`；`keytar` 存凭据进钥匙串，可能有钥匙串框
  - 注册 URL scheme `pkid`（`setAsDefaultProtocolClient`），文档类型 `.exe`、`.wsi`/`.wsi2`/`.wsi3` 的 `LSHandlerRank` 是 `Default`（会抢 `.exe` 的默认打开方式）
  - 渲染进程会执行 `launchctl setenv <名字被混淆> 0`，改的是用户 launchd 会话的环境变量
  - 封装好的游戏/软件（wrapper）是包外的独立 `.app`，换 Porting Kit 本体不碰它们（推断）

## 已知问题
- 实验轨副本按 stable 显示，实验仓库更新的构建看不到（见「Channel 详情」）
- 厂商 `latest-mac.yml` 的文件名与资产名不一致（6.7.0 起），它自己的更新器按推断下载不到 6.7.0；这不影响我们（我们读 release 资产列表）
- 下一次 stable 若只发 Intel dmg，行上会退回显示最近一个带 arm64 dmg 的版本

## 如何复验
```bash
gh release view v6.7.0 -R vitor251093/porting-kit-releases --json assets -q '.assets[]|.name+" "+.digest'
gh release download v6.7.0 -R vitor251093/porting-kit-releases -p 'Porting.Kit-6.7.0-arm64.dmg'
gh release download v6.5.0 -R vitor251093/porting-kit-releases -p 'Porting-Kit-6.5.0.dmg'
gh release download v4.1.6 -R vitor251093/porting-kit-releases -p 'Porting.Kit-4.1.6.dmg'
gh release download v6.6.3 -R vitor251093/porting-kit-releases-dev -p 'Porting-Kit-6.6.3-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Porting-Kit-6.5.0.dmg   # Team 45WEPZ3433, x86_64
swift run --package-path application-test feed-discover Porting.Kit-6.7.0-arm64.dmg   # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Porting-Kit-6.5.0.dmg --expect stable
swift run --package-path application-test channel-verify Porting.Kit-6.7.0-arm64.dmg --expect stable
swift test --package-path DuoUpdaterCore --filter portingKitChangelog
curl -sSL https://github.com/vitor251093/porting-kit-releases/releases/download/v6.7.0/latest-mac.yml
curl -s -o /dev/null -w '%{http_code}\n' -I -L https://github.com/vitor251093/porting-kit-releases/releases/download/v6.7.0/Porting-Kit-6.7.0-mac-arm64.zip   # 404
```

channel-verify 原始输出（2026-10-26）:
```
6.5.0 dmg:  detected channel → stable; winning source GitHub; latest 6.7.0;
  download https://github.com/vitor251093/porting-kit-releases/releases/download/v6.7.0/Porting.Kit-6.7.0-arm64.dmg;
  changelog pane recipe changelog:com.paulthetall.portingkit:-: 40 entries; newest 6.7.0: 1 items, headings []; first items ["Introducing proper Silicon builds"];
  status UPDATE → 6.7.0
6.7.0 arm64 dmg: detected channel → stable; winning source GitHub; latest 6.7.0; (同一条 changelog pane); status up to date
4.1.6 dmg: detected channel → stable; winning source GitHub; latest 6.7.0; status UPDATE → 6.7.0
  （第一次 changelog pane 是 FAILED to load → web page，重跑一次为 40 entries，同上）
6.6.3 arm64 dmg（实验仓库）: detected channel → stable; winning source GitHub; latest 6.7.0; status UPDATE → 6.7.0
```

## 建议下一步
1. 主会话真机两轮（上一版 → 6.7.0），结果写回「一键安装」并把 README 行改成 ✓
2. 实验轨（需要决定是否做引擎改动）: `ChannelBinding` 读 `~/Library/Application Support/portingkit/userData.json` 的 `experimentalFeatures`（== 1 → beta，先在真机上拨一次开关核对文件和取值），再加一个 `.beta` `GitHubReleaseRule` 读 `vitor251093/porting-kit-releases-dev`（同 pattern；该仓库 release 都没标 prerelease，规则需按 stable 方式读 `/releases/latest`）
