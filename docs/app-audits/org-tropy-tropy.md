# Tropy

## 基本信息
- App: Tropy — 研究用照片管理（Roy Rosenzweig Center 出品），Electron，AGPL-3.0
- Bundle ID: stable `org.tropy.tropy`（`Tropy.app`）；beta `org.tropy.tropy-beta`（`Tropy Beta.app`）。settled from source: `scripts/build.js` on `main`，`appBundleId: qualified.appId.toLowerCase()`，`src/common/release.js` 里 `qualified.appId` 对 prerelease 版本是 `org.tropy.Tropy-Beta`（`-alpha` 版本会是 `-Alpha`，但从没发过 alpha 版）
- 仓库: `tropy/tropy`（默认分支 `main`）
- Team ID: `8LAYR367YV`，1.12.0（2022）、1.17.2、1.17.3、1.18.0-beta.5、1.18.0-beta.6 五个真包全部相同；全部 `spctl` `Notarized Developer ID`
- 观测版本: stable 1.17.3（2026-01-21），上一版 1.17.2；beta 1.18.0-beta.6（2026-09-16），上一版 beta.5；观测日期 2026-10-22
- 自更新机制: **Electron 内置 `autoUpdater`（Squirrel.Mac）**，不是 electron-updater，也不是 Sparkle。settled from source: `src/main/updater.js` on `main`，`autoUpdater.setFeedURL(feed)`，`feed` = `https://tropy.org/update/<channel>/darwin/<arch>/<version>`（`src/common/release.js`）。x64 版在 Rosetta 下运行时把 feed 换成 arm64（`app.runningUnderARM64Translation`）
- 分发: GitHub Releases；Homebrew cask `tropy`（无 `auto_updates`，cask url 是 `tropy-<v>-arm64.dmg`）；没有 beta cask，没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（cask 装的副本，通用源） | — | ✓ | — |
| **beta**     | —       | —        | —   | ✓      | —           |

当前生效源: 两轨都是 **GitHub**（channel-verify 实测，见「如何复验」）。`feed-discover` 对 1.17.2: `no Sparkle, no electron-builder update config and no MyGo feed`。

厂商自己的 feed 也查了：`curl https://tropy.org/update/latest/darwin/arm64/1.17.2` → 200 `{"name":"1.17.3","notes":"https://github.com/tropy/tropy/releases/tag/v1.17.3","url":"…/v1.17.3/tropy-1.17.3-darwin-arm64.zip"}`，对 1.17.3 → 204。它指的就是本 rule 装的那个 zip，所以没必要另写 VendorProbe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.tropy.tropy` | 独立 | 默认 | `/releases/latest` | ✓ |
| beta    | `org.tropy.tropy-beta` | 独立（Pattern A） | `CFBundleName` = `Tropy Beta`，版本后缀 `-beta.N` → `.beta` | list + `^v?(…-beta\.[0-9]+)$` | ✓ |
| beta（v1.11.0-beta.3 及以前） | `org.tropy.tropy` | 与 stable 共享 id | 同上：`CFBundleName` = `Tropy Beta`，版本 `x.y.z-beta.N` → `.beta` | 同一 list + 同一 pattern，只检测 | ✓（只检测） |

- 两轨是两个 app，可以并存，不存在同 id 跨轨误推。例外是 v1.11.0-beta.3 及以前的旧 beta：它和 stable 共用 `org.tropy.tropy`，靠 `.beta` 走到 `org.tropy.tropy` 下那条 `.beta` 规则（channel gate 按 `releaseChannel` 选规则；这条规则没有 `installedTagPrefix`，所以 stable 副本照旧直接走 stable 规则）。
- beta 的自更新器读 `tropy.org/update/beta/darwin/arm64/<v>`，2026-10-22 对 1.17.3-beta.1、1.18.0-beta.5、1.18.0-beta.6 都回 204（什么都不给），所以 beta 副本只有我们这条 rule 会提示更新。服务端为什么不给没查（未验证）。
- beta 的 `CFBundleShortVersionString` 带后缀（真包 `1.18.0-beta.6`），pattern 捕获组也保留后缀，否则 beta 永远比自己新。
- beta rule 不收 stable tag：stable 是另一个 app，beta 副本永远不会变成它。
- 发版流程：`.github/workflows/release.yml` 先建 `prerelease: true` 的空 release 再分平台上传，stable 由维护者事后去掉 prerelease。所以新 release 头几分钟没有 mac 资产、stable 头几分钟还在 prerelease 里，两种都由 `resolve` 的「没有 mac 资产就往回找」和 `/releases/latest` 处理。v1.15.0 是个 stable 版本至今还挂着 prerelease 标记（`/releases/latest` 不读它，后来的版本已经覆盖它）。

### 覆盖清单
- **bundle id**：stable 从 1.12.0 到 1.17.3 都是 `org.tropy.tropy`（真包）；beta `org.tropy.tropy-beta`（真包）。**v1.11.0-beta.3 及以前的 beta 也是 `org.tropy.tropy`**（`scripts/build.js` 在 `v1.11.0-beta.3` 是 `appBundleId: 'org.tropy.tropy'`，`v1.11.1-beta.1` 起才是 ``org.tropy.${qualified.name}``，GitHub contents API 2026-10-22 核过；v1.10.0-beta.2、v1.11.0-beta.3 真包也是，见「历史与实测」）。这批旧 beta 由 `org.tropy.tropy` 的第三条规则（`.beta`，只检测）覆盖，告诉它当前 beta tag。`build.js` 的大小写规则（`org.tropy.Tropy` 小写化）在更早的版本是否一样没读包（未验证，1.12.0 之前的副本已有四年）。
- **版本轨**：stable、beta 两轨都接了。alpha 轨源码里有（`release.js` 非 beta 的 prerelease → `alpha`），但仓库从未发过 alpha tag，不收。`1.0.0-rc.1`（2017）同理。
- **版本范围**：Team 从 2022 到今天一致。arm64 资产从 1.9.0 开始（1.9.0 只有 arm64 dmg，1.10.0 起才有 `-darwin-arm64.zip`），之前只有 x64；DuoUpdater 只跑 arm64（`App/project.yml`），所以更早的 x64 副本照样被供 arm64 zip——厂商自己也把 Rosetta 下的 x64 版迁到 arm64 feed。
- **主机下限**：`LSMinimumSystemVersion` 10.13.0，低于我们的下限。
- **一键**：两轨都是 Developer ID + 同一 Team + 公证，一键都开。旧 beta（`org.tropy.tropy` + `.beta`）只检测：当前 beta tag 的包是 `org.tropy.tropy-beta`，是另一个 app，装过去会换掉 bundle id，所以不给安装资产。

## 更新检测
- 源: `tropy/tropy` GitHub Releases。stable 读 `/releases/latest`；beta 读 list（`listPageSize` 8）。旧 beta（`org.tropy.tropy` + `.beta`）读同一个 list、同一个 pattern。
- stable 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`。tag `v1.17.3` → `1.17.3` = `CFBundleShortVersionString`。
- beta 版本: `^v?([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$`。`v1.18.0-beta.6` → `1.18.0-beta.6` = 真包的 `CFBundleShortVersionString`。
- `CFBundleVersion` 两轨都等于 short version，不影响比较。

### 待审项「有 tag 读不出」
分诊说 22 个 stable tag 里读出 16 个，没读出 1.9.0、1.8.2、1.8.1、1.8.0、1.7.0、1.6.0。

结论：**这些是同一个产品的旧 tag，只是没有 `v` 前缀，放宽到 `^v?`。** 证据：
- `gh api repos/tropy/tropy/releases --paginate` 全量列表：1.9.0（2021-02-11）及以前的 release 全部是无 `v` tag，资产都是 `tropy-<v>.dmg` / `tropy-<v>-darwin.zip`，与今天同名同形；1.10.0-beta.4（2021-09）起改成 `v` 前缀。tag 表里唯一不是版本的是 `daedalus`（一个指向 commit 的裸 tag，`releases/tags/daedalus` 404），两个 pattern 都不收。
- 放宽后在最新 100 个 release 上实测（python 跑同一个正则）：stable pattern 命中 23 个（含被误标 prerelease 的 v1.15.0），beta pattern 命中 77 个 beta tag、0 个 stable tag。
- 锚定：`v1.18.0-beta.6`、`1.10.0-beta.2` 不被 stable pattern 读成 `1.18.0` / `1.10.0`；`v2.0.0`（下一个大版本）两条都能读（stable 读、beta 不读）。

### 待审项「v1.16.2 没有 mac 资产」
分诊的说法要修正：**v1.16.2 有 mac 资产，缺的只是 arm64 dmg**。资产表里有 `tropy-1.16.2-arm64.dmg.integrity`、`tropy-1.16.2-darwin-arm64.zip`、`tropy-1.16.2-darwin.zip`、`tropy-1.16.2.dmg`，唯独没有 `tropy-1.16.2-arm64.dmg`（上传失败留下的 `.integrity`）。分诊草稿用的是 arm64 dmg pattern，所以看成「没有」。

处理：**一键改用 `-darwin-arm64.zip`**。它就是厂商 feed 的 `url`（Squirrel 自己装的那份），v1.16.2 也有，比 arm64 dmg 发得更稳。

### 待审项「arm64 / universal dmg 叫什么」
没有 universal。`release.yml` 的矩阵是 `macos-15-intel`（x64）和 `macos-26`（arm64）分别构建。`tropy-<v>.dmg`、`tropy-<v>-darwin.zip` 是 x64，`tropy-<v>-arm64.dmg`、`tropy-<v>-darwin-arm64.zip` 是 arm64（真包 `archs=arm64`）。

## 按架构 / 按 OS 分轨
- 只选 arm64 zip，理由见上。Info.plist `LSMinimumSystemVersion` 10.13.0（四个真包相同），release 不声明 OS 范围。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Squirrel.Mac 没有 delta 机制（`SelfUpdaterDownload.swift` 的注释同样这么说） | feed 只回一个整包 zip 的 `url` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（Squirrel.Mac） | 真机（2026-10-22）：1.17.2 启动 15 s 后 `~/Library/Caches/org.tropy.tropy.ShipIt/update.*/Tropy.app`（1.17.3）已武装 | **不能**，但已有的让路 / Relaunch 路线认得它（见一键安装） |
| 证据 | 启动即 `updater.start()`（`src/main/tropy.js`，`state.updater` 默认 true、`--auto-updates` 默认 true），立刻检查并下载；`update-downloaded` 后弹「update ready」提示，用户点了才 `quitAndInstall()`。Electron 官方文档：「a successfully downloaded update will always be applied the next time the application starts」（https://www.electronjs.org/docs/latest/api/auto-updater） | — | `SelfUpdaterStash` 只认 electron-updater 的 `pending/` 和 Cindy，**不读 Squirrel**；但 `SelfUpdaterStaging.staged` 读 `~/Library/Caches/org.tropy.tropy.ShipIt/ShipItState.plist`（按 `targetBundleURL` 对路径），比已装新时走 Relaunch；`SelfUpdaterDownload.squirrelInFlight` 认得下载中。要让 Stash 也读 Squirrel 的包得改引擎，本次不做 |

## 嵌套 helper（待审项「4 个 helper 的 bundle id 都是 org.tropy.tropy-helper」）
结论：**不影响**。
- 这是 Electron 的标准做法：`scripts/build.js` 写死 `helperBundleId: ${appId}-helper`，GPU/Renderer/Plugin/主 helper 共用一个 id。beta 是 `org.tropy.tropy-beta-helper`。
- 四个 helper 都在 `Contents/Frameworks/` 下，`LSUIElement=true`。`NestedAppGuard` 明确排除 `Contents/Frameworks/` 下的 helper；`AppScanner.admit` 只收顶层 `.app`，不进 bundle 里扫，所以不会出一个 `org.tropy.tropy-helper` 行。
- 代码里没有用 `hasPrefix(bundleID)` 匹配运行中 app 的地方会把 `org.tropy.tropy-helper` 当成 `org.tropy.tropy`（`grep -rn "hasPrefix" DuoUpdaterCore/Sources` 只命中 Mozilla / JetBrains / 输入法备份 / NestedAppGuard 的路径前缀）。
- 包里没有 `Contents/Library/`（无 LoginItems、无 LaunchAgents），没有 `.xpc` / `.appex`。

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- stable 结构化 ✓（channel-verify `changelog pane`，从 1.17.2 起）: `source structured: 1 entries; newest 1.17.3: 5 items, headings []; first items ["Added Finnish translations :finland:", "Improved dark/light theme switching", "Fixed item table column picker"]`。厂商正文本来就是一层平铺的 `*` 列表、没有标题，所以没有标题可丢，也没有被压平。`:finland:` 是 GitHub 的 emoji 短码，面板按原文显示，不渲染成旗子（小瑕疵，不改解析器）
- 最新 100 个 release 里 22 个 stable 正文全部非空
- beta ✗：77 个 beta release 里 76 个正文为空（厂商不写），面板退回 `web page https://github.com/tropy/tropy/releases/tag/v1.18.0-beta.6, no structure`
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（stable），真机通过（2026-10-22，本分支 `make cli` 的 duo）**；beta 轨没在真机上跑
  - 第一轮（不运行）: 1.17.2 → `duo check` `1.17.2 → 1.17.3 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.17.3、可执行文件 inode 变、`TeamIdentifier=8LAYR367YV`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.17.3 包相同
  - 第二轮（运行中，不加 `--no-auto-updates`）: Squirrel 15 s 内暂存了 1.17.3；`duo install --json` → `skipped`，`its own updater already has 1.17.3 staged — quit it to apply, or duo restart`；`duo restart Tropy` **在非 TTY 的 shell 里跑**（stdin 不是终端）→ **`still running — likely a save prompt, left 1.17.3 staged`**，并没有存盘框：有暂存更新时 Tropy 退出很慢，旧进程约 40 s 后才退，ShipIt 14:51:42 开始、14:52:11 装完，磁盘 1.17.3、签名有效，但 app 没被拉起来。原因是非 TTY 的 `duo restart` 走 `.grace`：约 5 s（`StagedRelaunch.quitGraceTicks`）还没退就报「likely a save prompt」并放弃，不重新拉起（只有 app 先关掉窗口时才延长到约 30 s，`slowQuitTicks`）。TTY 里跑会打印「hasn't quit yet」并等最多 10 分钟（`quitHandoffMaxAge`），这一轮没测。另测一次没暂存时的普通退出：9.3 s，在普通路径约 30 s 的等待之内（`AppRestarter`），会被重新拉起。各路径见「已知问题」
- 格式: zip（`ditto -x -k`，根目录就是 `Tropy.app` / `Tropy Beta.app`）。stable `^tropy-[0-9]+(?:\.[0-9]+)+-darwin-arm64\.zip$`，beta `^tropy-[0-9]+(?:\.[0-9]+)+-beta\.[0-9]+-darwin-arm64\.zip$`，kind `.zip`。两个 pattern 互不相交（stable 的不允许 `-beta.N`）
- 签名: 见「基本信息」，Team 前后一致
- 校验: GitHub 资产 `digest`；`curl` 下来的四个 zip `shasum -a 256` 都等于资产 digest（1.17.3 `92dd44c6…b42192`，1.17.2 `302a4afe…bd2972`，beta.6 `49c1a856…feed0c`，beta.5 `86986cd4…b7f73`）
- **读的是**: 人人可下的 GA（`/releases/latest`）；beta 是 GitHub 上公开的 prerelease

### 启动副作用（读源码得来；2026-10-22 真机核对的已注明）
- **自带更新器启动即下载**：stable 1.17.2 启动后会立即请求 `tropy.org/update/latest/darwin/arm64/1.17.2`，拿到 1.17.3 的 zip 解到 `~/Library/Caches/org.tropy.tropy.ShipIt/` 并弹「update ready」提示。这会和我们抢：第二轮（运行中）里，如果 Squirrel 已暂存，我们的行可能变成 Relaunch 而不是 Update。只想测我们的下载路线的话，用 `--no-auto-updates` 启动（`src/main/args.js`：`'auto-updates': { type: 'boolean', default: true }`，`parseArgs` 开了 `allowNegative`、`strict: false`；注意 `--auto-updates=false` 不行，`strict: false` 下它会被读成字符串 `"false"`，仍是真值——按 Node `util.parseArgs` 行为推断，未实测），或者先启动、等它暂存完再看 Relaunch 路线。
- **造「暂存了比 latest 旧的版本」**：只有 1.17.3 是 latest，没法让厂商 feed 暂存更旧的。办法是装 1.17.1，`--no-auto-updates` 启动避免下载；或者让 Squirrel 先暂存 1.17.3 再换回更旧的副本——`SelfUpdaterStaging` 只认 `targetBundleURL` 指向本路径、且比已装新的暂存包。
- **改系统设置**：启动时 `app.setAsDefaultProtocolClient('tropy')`（`src/main/index.js`），把 `tropy://` URL scheme 注册给自己。不动壁纸、输入法、默认浏览器。
- **本地端口**：起一个本地 API 服务，stable 端口 2019，beta 2029（`src/main/tropy.js` `static defaults.port`；`src/main/api.js`）。
- 没有登录项、LaunchAgent、root helper（包里没有 `Contents/Library/`；GitHub code search `repo:tropy/tropy setLoginItemSettings`、`openAtLogin` 各 `total_count` 0）。没有往 `~/.claude` / `~/.agents` 写东西的迹象（code search `repo:tropy/tropy .claude` `total_count` 0；code search 不覆盖依赖）。真机首启建了 `~/Library/{Application Support,Caches,Logs}/Tropy`、`~/Library/Caches/org.tropy.tropy{,.ShipIt}`、`~/Library/HTTPStorages/org.tropy.tropy`、偏好 plist
- 首启：会打开最近项目或空窗口；有没有首启向导没读到，未验证。
- 单实例锁：`app.requestSingleInstanceLock`，第二次启动会把参数交给已运行的实例然后退出。
- 数据：`~/Library/Application Support/Tropy`（stable）、`Tropy Beta`（beta），项目文件在用户自选位置。

### 推荐的两轮真机步骤
1. 第一轮（不运行）：把 1.17.2 的 `Tropy.app` `ditto` 进 `/Applications`（不启动）→ `duo check` 期望 `1.17.2 → 1.17.3 [GitHub]` → `duo install --yes --json` → 校验 1.17.3、Team `8LAYR367YV`、`codesign --verify --deep --strict`、`diff -r` 与厂商 1.17.3 zip 一致。
2. 第二轮（运行中）：再放 1.17.2，用 `open -a … --args --no-auto-updates` 启动（不让 Squirrel 抢先下载）→ `duo install` → `duo restart Tropy` → 新进程是 1.17.3。可选第三轮：不带参数启动，等 `~/Library/Caches/org.tropy.tropy.ShipIt/ShipItState.plist` 出现，看我们的行是否变成 Relaunch。
3. beta 可选：`Tropy Beta.app` 1.18.0-beta.5 → beta.6，同样步骤。

## 已知问题
- beta 的 changelog 基本为空（厂商）。
- `:finland:` 之类 emoji 短码按原文显示。
- **有暂存更新时退出慢，非 TTY 的 `duo restart` 不重新拉起**（真机 2026-10-22；记录的那一轮就是非 TTY）：有暂存更新时 Tropy 约 40 s 才退，没暂存时 9.3 s。按路径：
  - 没暂存（普通路径，`AppRestarter`）：等约 30 s，9.3 s 的退出在内，会重新拉起。
  - 有暂存、非 TTY 的 `duo restart`（脚本、agent 的 shell）：约 5 s 宽限后报「likely a save prompt」并放弃，不重新拉起；更新仍由 ShipIt 装上。宽限只在 app 先关掉窗口时延长到约 30 s，结局一样是放弃。PR #1588 在 main 上对 SIGSTOP 住的 Tropy 实测约 7 s 放弃。
  - 有暂存、TTY 里的 `duo restart`：打印「hasn't quit yet … waiting up to 10 min」，最多等 10 分钟；退了就等换包并拉起。
  - 菜单栏 app：仍在运行时把退出交给 quit hand-off，app 退出后再拉起。

## 建议下一步
1. beta 轨（`Tropy Beta.app` beta.5 → beta.6）可补一轮真机。
2. 非 TTY `duo restart` 的放弃由 PR jizhi0v0/duo-updater#1588 处理（有暂存、没有新窗口/模态框时最多等约 60 s；未合并）。合并后用非 TTY 的 `duo restart Tropy` 复测一轮。
3. 1.18.0 正式版出来后复查：`/releases/latest` 指向它、资产名仍是 `tropy-<v>-darwin-arm64.zip`。

## 历史与实测
- 2026-10-22 旧 beta 真包（`gh` 列出的 release 资产，`curl` 下载、`unzip -Z1` 看根目录、`PlistBuddy` 读 `Contents/Info.plist`）：
  - `tropy-1.11.0-beta.3-darwin-arm64.zip`（sha256 `4292f97a…2ce80e`）：根目录 `Tropy Beta.app`；`CFBundleIdentifier` `org.tropy.tropy`，`CFBundleName` `Tropy Beta`，`CFBundleShortVersionString` `1.11.0-beta.3`，`CFBundleVersion` `1.11.0-beta.3`
  - `tropy-1.10.0-beta.2-darwin-arm64.zip`（sha256 `50cee8c0…60c5dc31`）：根目录 `Tropy Beta.app`；`CFBundleIdentifier` `org.tropy.tropy`，`CFBundleName` `Tropy Beta`，`CFBundleShortVersionString` `1.10.0-beta.2`，`CFBundleVersion` `1.10.0-beta.2`
  - 两者 `channel-verify --expect beta`：`inferred beta`、`detected channel → beta`、winning source GitHub、`latest 1.18.0-beta.6`、`download https://github.com/tropy/tropy/releases`（只检测，没有安装资产）、`UPDATE → 1.18.0-beta.6`。同时 1.17.2 stable 包照旧 `detected channel → stable`、`UPDATE → 1.17.3`、download `…/v1.17.3/tropy-1.17.3-darwin-arm64.zip`。
- 2026-10-22（从 `org-tropy-tropy.swift` beta 规则注释迁出）：原文「listPageSize 8: worst run between two beta tags in the newest 100 releases is 2 (2026-10-22), floor 3, pinned in `GitHubListPageSizeTests`.」——最新 100 个 release 里两个 beta tag 之间最长隔 2 个非 beta release，测试里的下限是 3，规则取 8。

## 如何复验
```
gh api "repos/tropy/tropy/releases?per_page=100" -q '.[].tag_name'
gh release view v1.17.3 -R tropy/tropy --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Tropy.app            # 1.17.2 → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify <1.17.2>/Tropy.app --expect stable
swift run --package-path application-test channel-verify <beta.5>/"Tropy Beta.app" --expect beta
swift run --package-path application-test channel-verify <1.11.0-beta.3>/"Tropy Beta.app" --expect beta   # 旧 beta，org.tropy.tropy
```

2026-10-22 实测（zip 用 `ditto -x -k` 解开后跑）：

| 包 | bundle id | 版本 | detected | 胜出源 | 结论 |
|---|---|---|---|---|---|
| 1.17.2 zip | `org.tropy.tropy` | 1.17.2 | stable ✓ | GitHub | `UPDATE → 1.17.3`，download `…/v1.17.3/tropy-1.17.3-darwin-arm64.zip` |
| 1.17.3 zip | `org.tropy.tropy` | 1.17.3 | stable ✓ | GitHub | up to date |
| 1.18.0-beta.5 zip | `org.tropy.tropy-beta` | 1.18.0-beta.5 | beta ✓（inferred beta） | GitHub | `UPDATE → 1.18.0-beta.6`，download `…/v1.18.0-beta.6/tropy-1.18.0-beta.6-darwin-arm64.zip` |
| 1.18.0-beta.6 zip | `org.tropy.tropy-beta` | 1.18.0-beta.6 | beta ✓ | GitHub | up to date |
| 1.11.0-beta.3 zip | `org.tropy.tropy` | 1.11.0-beta.3 | beta ✓（inferred beta） | GitHub | `UPDATE → 1.18.0-beta.6`，只检测（download 是 releases 页） |
| 1.10.0-beta.2 zip | `org.tropy.tropy` | 1.10.0-beta.2 | beta ✓ | GitHub | `UPDATE → 1.18.0-beta.6`，只检测 |

`check-bundle.sh` 对 1.12.0 / 1.17.2 / 1.17.3 / beta.5 / beta.6：全部 `TeamIdentifier=8LAYR367YV`、`codesign-verify-exit=0`、`spctl source=Notarized Developer ID`、`archs=arm64`。
