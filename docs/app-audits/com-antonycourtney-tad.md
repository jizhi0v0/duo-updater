# Tad

## 基本信息
- App: Tad — 表格数据查看器（CSV / Parquet / SQLite / DuckDB，内嵌 DuckDB），Electron，MIT
- Bundle ID: `com.antonycourtney.tad`
- 仓库: `antonycourtney/tad`（默认分支 `master`，monorepo，app 在 `packages/tad-app`）
- Team ID: `VPS8BQAV8D`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 0.14.0（tag `v0.14.0`，资产 `Tad-0.14.0-arm64.dmg`）；上一版 0.13.0；观测日期: 2026-10-26
- 发布节奏: 最新 release v0.14.0 发布于 2024-06-21，之后没有新 release（仓库最后一次提交 2025-03-05）。仓库未归档，README 和仓库首页没有停止维护或终止的说法，所以不是 sunset，只是更新慢
- 自更新机制: **electron-updater 4.6.5**（GitHub provider，只在用户点菜单「Check for Updates」时检查），见下文
- 分发: GitHub Releases（每版 arm64 dmg/zip + 不带架构词的 x86_64 dmg/zip + Windows/Linux 包）；Homebrew cask `tad`（0.14.0，`auto_updates` 未设，arm 装 `-arm64.dmg`、Intel 装无架构词的 dmg）；没有 Mac App Store 版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | cask 副本走 cask 源 | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`；`app-update.yml` 是 `provider: github`，feed-discover 判 `review electronProviderNeedsConstruction`，`ElectronManifestSource` 不接这种 provider，所以要 GitHub rule。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v0.14.0 `Tad-0.14.0-arm64.dmg`: `com.antonycourtney.tad`，Team VPS8BQAV8D，Notarized，arm64，`CFBundleVersion` 0.14.0.1
  - v0.13.0 `Tad-0.13.0-arm64.dmg`: 同 id、同 Team，Notarized，arm64，`CFBundleVersion` 0.13.0.1
  - v0.11.0 `Tad-0.11.0.dmg`（最后一个只有 Intel 包的版本）: 同 id、同 Team，Notarized，x86_64，`CFBundleShortVersionString` 0.11.0、`CFBundleVersion` 0.10.2（只比前者，不影响）
  - v0.9.0 `Tad-0.9.0.dmg`: 同 id、同 Team，Notarized，x86_64
  - v0.6.4 `tad-0.6.4.dmg`（列表里最老的一版）: 同 id、同 Team，spctl 只说 Developer ID（2017 年，公证之前），x86_64
  - 没有改名前的旧 bundle id；Team 从 0.6.4 到 0.14.0 没换过
- 其他轨: 没有。15 个 release 全部 `prerelease: false`，tag 列表与 release 列表一一对应（v0.6.4 … v0.14.0），没有 beta / nightly 资产，也没有别的仓库发同 id 的包
- 版本范围: 15 个 tag 都是 `v<数字>.<数字>.<数字>`，`versionPattern` 全部读得出。v0.12.0 起才有 `-arm64.dmg`；更早的 release 只有无架构词的 x86_64 包。规则只看最新 release，老 release 没有 arm64 资产不影响
- 老的 x86_64 副本（0.11.0 及更早，或在 Apple 芯片上装了无架构词包的副本）: 同 id 同 Team，channel-verify 实测 0.11.0 → `UPDATE → 0.14.0`，一键会换成 arm64 版。DuoUpdater 自身只跑在 arm64（`App/project.yml` `ARCHS: arm64`），换成原生版没有坏处
- 主机下限: DuoUpdater macOS 15、arm64；Tad 0.14.0 `LSMinimumSystemVersion` 10.15，在下限之下，不需要 `hostRequirement`
- Homebrew 副本: cask 没设 `auto_updates`，cask 装的副本由 Homebrew 源回答（引擎已有的顺序，不是本 rule 的事）；cask 另装了一个 `tad` 命令（指向包内 `Contents/Resources/tad.sh` 的软链），换包后路径不变

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.antonycourtney.tad` | 独立 | — | — | ✓ |

没有其他轨（见覆盖清单）。

## 更新检测
- 源: `antonycourtney/tad` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.14.0` → `CFBundleShortVersionString` `0.14.0`、`CFBundleVersion` `0.14.0.1`（比的是前者）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`v1.0.0-rc.1` 不匹配，`v1.0`、`v1.0.0` 匹配）
- install pattern `^Tad-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`。同一个 release 里另外的 macOS 包: `Tad-0.14.0-arm64-mac.zip`（同版本的 arm64 zip，选 dmg）、`Tad-0.14.0.dmg` / `Tad-0.14.0-mac.zip`（x86_64，真包核过：zip 里 `Contents/MacOS/Tad` 是单架构 Mach-O，cputype `0x1000007`；cask 也把它当 Intel 变体），都不匹配
- 资产名从 v0.12.0 到 v0.14.0 都是 `Tad-<version>-arm64.dmg`；v0.8.5 及更早是小写 `tad-<version>.dmg`，与本 rule 无关

## 按架构 / 按 OS 分轨
- 架构: 分架构资产。arm64 dmg（`archs=arm64`）和 x86_64 dmg 各一个，没有 universal；`LSMinimumSystemVersion` 10.15（0.11.0 是 10.13，0.9.0 及更早是 10.9.0）。release 不声明 OS 上限
- `latest-mac.yml` 只列 x86_64 的 `Tad-0.14.0-mac.zip` 和 `Tad-0.14.0.dmg`（sha512 + size），没有 arm64 文件；对 Tad 自己更新器的影响见「已知问题」

## 自带更新器（electron-updater）
- settled from source: `packages/tad-app/app/updater.ts` on `master`，0.14.0 的 `app.asar` 里编译后的代码相同（`autoUpdater.autoDownload=!1`、「A new release of Tad is available. Do you want to update now?」）
- 只有菜单「Tad → Check for Updates」调 `autoUpdater.checkForUpdates()`；`main.ts` 启动时不检查，没有定时检查
- 发现新版先弹框问；选 Yes 才 `downloadUpdate()`，下完弹「Update downloaded, will update...」后立即 `quitAndInstall()`（Squirrel.Mac 换包）
- `app-update.yml`: `owner: antonycourtney`、`repo: tad`、`provider: github`、`updaterCacheDirName: tad-updater`；`app.asar` 内 `electron-updater` 版本 4.6.5
- 会不会和我们抢: 只有用户自己在菜单里点了检查并同意时才会动；它一下完就退出换包，不会把包长时间放着等下次启动

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 有 blockmap，无二进制补丁 | — |
| 证据 | 0.14.0 `app.asar` 里 electron-updater 4.6.5 的 `MacUpdater.doDownloadUpdate` 直接 `httpExecutor.download(zipFileInfo.url, …)` 整包下载，不走 blockmap 差分 | 2026-10-26 v0.14.0 release 带 `.blockmap`（electron-builder 默认产物），没有 Sparkle delta | 我们下整包 dmg |

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（短暂：下完立即 `quitAndInstall`） | 没查（真机第二轮待主会话） | 布局已接（通用 electron-updater 布局），但见已知问题 |
| 证据 | electron-updater 4.6.5（`app.asar` 内）：缓存目录 `~/Library/Caches/<updaterCacheDirName>/pending/`，下载完成后写 `update-info.json` | — | `SelfUpdaterStash` 的 `.electronUpdater(cacheDirectoryName:)` 从 `app-update.yml` 读 `tad-updater` |

- 记录文件与字段: `pending/update-info.json`（`fileName`、`sha512` base64，下载完成后才写）
- 容器: zip（electron-updater 在 Mac 上只下 zip），包根是 `Tad.app`
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`；`SelfUpdaterStash` 的归属闸处理

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 0.13.0 起）: `source structured: 1 entries; newest 0.14.0: 4 items, headings []; first items ["Updated to DuckDb 1.0", "Export filtered tables as Parquet (as we", "Fix bug with formatting numbers in scien"]`
- 正文只有一个通用的 `## What's Changed` 标题加 4 条手写条目和 `**Full Changelog**` 链接；`headings []` 是因为那个通用标题按规则不保留为分节，它没有混进条目里，不算压平。条目完整
- 跟随 channel: 只有 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持
- 端到端: 待主会话（真机从 0.13.0 装到 0.14.0）
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Tad.app` + `Applications` 软链
- 嵌套: `Contents/Frameworks/` 下 `Tad Helper.app`、`Tad Helper (GPU).app`、`Tad Helper (Plugin).app`、`Tad Helper (Renderer).app`（`LSUIElement`），是 Electron 主进程起的子进程，随主进程退出，不常驻；另有 `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`（Squirrel.Mac 用）。没有 `Contents/Library`、LoginItems、LaunchAgent。`app.asar` 里 `setLoginItemSettings`、`SMAppService` 只是孤立字符串，主进程 bundle 里没有调用点
- 签名: 0.6.4、0.9.0、0.11.0、0.13.0、0.14.0 都是 Team `VPS8BQAV8D`，Team 没换过；0.9.0 起 spctl 都是 Notarized Developer ID
- 校验: GitHub 资产 `digest` 为 null（资产 2024-06-21 上传，早于 GitHub 加 digest），只靠 Team ID 闸。`latest-mac.yml` 的 sha512 只描述 x86_64 的 zip/dmg，与本 rule 装的 arm64 dmg 不是同一个文件，不接
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Tad 自己的更新器读的也是这一版）
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 首启（每个新版本第一次启动）在 `~/Library/Application Support/Tad/` 写 `install-marker-<版本>.txt`，打包版第一次运行会弹 Quick Start 窗口
  - 不会自动检查更新；第二轮要造「已停放」只能在菜单里点「Check for Updates」并同意，而它下完会立即退出换包，而且下的是 x86_64 zip（见已知问题）
  - Info.plist 为 csv / tsv / parquet / sqlite / duckdb 等声明文档类型，`LSHandlerRank` 是 `Default`：装上并启动后，LaunchServices 可能把这些扩展名的默认打开方式交给 Tad（推断，未验证）
  - 没有 URL scheme、登录项、root helper
  - 首次打开 Parquet 等文件时 DuckDB 可能下载扩展（0.13.0 的 release 说明提到扩展下载失败的处理），不打开数据文件就不会触发（推断）

## 已知问题
- **Tad 自己的更新器在 Apple 芯片上装的是 x86_64 版**（源码 + `latest-mac.yml` 推出，未在真机上观察）: electron-updater 4.6.5 `MacUpdater.doDownloadUpdate` 只有在 `latest-mac.yml` 里有带 `arm64` 的文件时才挑 arm64，否则挑不带 `arm64` 的；Tad 的 `latest-mac.yml` 只列 x86_64 的 `Tad-0.14.0-mac.zip`。所以 arm64 副本用菜单更新后变成同版本的 Intel 版（走 Rosetta）。这份 0.14.0 Intel 副本在我们这里是 up to date，duo 不会把它换回 arm64
- 同一原因，如果 `pending/` 里停放着这份 x86_64 的 0.14.0 zip，而本机副本还是更旧的版本（Tad 自己换包失败时才会这样），`SelfUpdaterStash` 会命中它：包内 bundle id、版本、sha512 都对得上，它不检查架构，duo 装上的会是 x86_64 版而不是 arm64 dmg。这条需要引擎改动（stash 按架构核对），本次没做，见「建议下一步」
- 最新 release 是 2024-06-21 的 v0.14.0，此后 28 个月没有新版；检测对已是 0.14.0 的副本只会一直显示 up to date

## 如何复验
```bash
gh release download v0.14.0 --repo antonycourtney/tad --pattern 'Tad-0.14.0-arm64.dmg'
gh release download v0.13.0 --repo antonycourtney/tad --pattern 'Tad-0.13.0-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Tad-0.14.0-arm64.dmg   # Team VPS8BQAV8D, Notarized, arm64
.claude/skills/coverage-discovery/scripts/check-bundle.sh Tad-0.13.0-arm64.dmg
swift run --package-path application-test feed-discover Tad-0.14.0-arm64.dmg     # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Tad-0.13.0-arm64.dmg --expect stable   # GitHub, UPDATE → 0.14.0
swift run --package-path application-test channel-verify Tad-0.14.0-arm64.dmg --expect stable   # up to date
curl -sSL https://github.com/antonycourtney/tad/releases/download/v0.14.0/latest-mac.yml       # 只有 x86_64 文件
```

channel-verify 原始输出（2026-10-26）:
```
0.13.0 arm64 dmg: detected channel → stable; winning source GitHub; latest 0.14.0;
  download https://github.com/antonycourtney/tad/releases/download/v0.14.0/Tad-0.14.0-arm64.dmg;
  status UPDATE → 0.14.0
0.14.0 arm64 dmg: detected channel → stable; winning source GitHub; latest 0.14.0; status up to date
0.11.0 x86_64 dmg: detected channel → stable; winning source GitHub; latest 0.14.0; status UPDATE → 0.14.0
```

## 建议下一步
1. 主会话真机两轮（上一版 0.13.0 → 0.14.0），结果写回「一键安装」并把 README 行改成 ✓
2. 是否给 `SelfUpdaterStash` 加架构核对（停放 zip 里主可执行文件的架构要能在本机原生运行，或与要装的资产一致），挡掉 Tad 这类 `latest-mac.yml` 只发 x86_64 的 electron-updater 应用把 Intel 版经 stash 装到 Apple 芯片上。引擎改动，需要用户决定
