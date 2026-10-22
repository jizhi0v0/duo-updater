# Folo

## 基本信息
- App: Folo（2025-03 前叫 Follow）— RSSNext 的 Electron RSS 阅读器；仓库 `RSSNext/Folo` 是 monorepo，同时放桌面端（`apps/desktop`）和移动端
- Bundle ID: `is.follow`（Follow 时期和 Folo 时期一样；Follow 时期的 bundle 叫 `Follow.app`，0.3.13 起叫 `Folo.app`）
- 仓库: `RSSNext/Folo`（默认分支 `dev`）
- Team ID: `492J8Q67PF`（0.3.4-beta.0 起）；0.3.3-beta.0 及更早是 `NCLY2BLCL2`
- 观测版本: 1.16.0（`desktop/v1.16.0`，2026-10-16）；上一版 1.15.0（`desktop/v1.15.0`）；观测日期: 2026-10-22
- 自更新机制: electron-updater 6.x 的 `MacUpdater`（底层 Squirrel.Mac），custom provider；另有 renderer 热更新（只换 userData 里的前端资源，不动 bundle）。settled from source: `apps/desktop/layer/main/src/updater/{index,configs,follow-update-provider,api,hot-updater}.ts` on `desktop/v1.16.0`
- 分发: GitHub Releases（`desktop/vX` 每版 arm64/x64 各一个 dmg 和 zip）；Homebrew cask `folo`（`auto_updates`）；Mac App Store 上 `is.follow` 是 **iOS 版**（「Folo - AI RSS Reader」0.6.1，`iosUniversal`，iTunes lookup 2026-10-22），见覆盖清单

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，`HomebrewCaskSource` 让出） | —（只有 iOS 版） | ✓ | — |
| **beta**（Follow 时期 `-beta.N` 副本） | — | — | — | ✓（只检测，给最新稳定版） | — |

当前生效源: **GitHub**（channel-verify 实测，见如何复验）。`feed-discover` 对 1.16.0 dmg: `review electronProviderNeedsConstruction`——bundle 里的 `app-update.yml` 是 `provider: custom`，地址在代码里构造，`ElectronManifestSource` 读不了，所以需要 GitHub rule。

## 覆盖清单
- **bundle id**: 读了 5 个年代的真包，都是 `is.follow`：0.1.0-beta.0（universal，`Follow.app`）、0.2.6-beta.0、0.3.12（最后一个 Follow 名字的版本）、0.9.0、1.15.0、1.16.0。改名没换 id，不需要 `BundleIDMigration`。
- **Team**: 二分真包得出换 Team 的点：0.3.3-beta.0 = `NCLY2BLCL2`，0.3.4-beta.0 / 0.3.5 / 0.3.7 / 0.3.12 / 0.9.0 / 1.15.0 / 1.16.0 = `492J8Q67PF`。0.3.3-beta.0 及更早的副本一键会被 Team 闸拒（它们都是 `-beta.N` / `-alpha.N` 版本，见下一条）。
- **Follow 时期的 `-beta.N` 副本（`0.1.0-beta.0` … `0.3.4-beta.1`，2024-10 到 2025-02，21 个 release）**: 这些 tag 在 GitHub 上**不标 prerelease**，当时就是主线；但 bundle 的 `CFBundleShortVersionString` 带 `-beta.N`，`ReleaseChannel.detect` 按版本后缀判成 beta，stable rule 按通道闸不服务它们。**✓（只检测）**：加了一条 `channel: .beta` 的 GitHub rule，同一个仓库、同样的 tag 模式、读 `/releases/latest`（`desktop/v1.16.0`），不带 `installAssetPattern` / `installerKind` / `installedTagPrefix`，这批副本看到最新稳定版。只检测的理由：非 stable 轨的安装要 channel proof，而能区分两者的只有已装副本的版本号；`≤0.3.3-beta.0` 的副本还是 Team `NCLY2BLCL2`，一键本来也会被 Team 闸拒。副本手动换成稳定版后由 stable rule 服务。真包结果见「历史与实测」。更早的 `0.0.1-alpha.N` 副本 `ReleaseChannel.detect` 判 stable（单测探针：`0.0.1-alpha.22`、`0.0.1-alpha.3` → stable），由 stable rule 检测，没有读真包
- **其他轨**: 桌面端现在只有 stable。`desktop/v1.6.0`、`v0.6.0` 标了 prerelease，`/releases/latest` 本来就跳过；`allowPrerelease = channel !== "stable"`（`index.ts`），channel 是构建时定的，GitHub 上没有非 stable 的桌面构建可读。
- **移动端 tag**（`mobile/v0.6.1` 等 19 个）: 是 iOS/Android app，没有 macOS 资产，pattern 锚定 `^(?:desktop/)?v…$` 有意不收。`/releases/latest` 目前指 `desktop/v1.16.0`（2026-10-22），尽管 `mobile/v0.6.1` 发得更晚——仓库手动把桌面版标成 latest。万一哪天 latest 变成 mobile tag：它不带匹配的 dmg，source 会退到列表页（20 条，`stableOnly`），mobile tag 不匹配 pattern、不计入「缺资产」次数，往下找到最近的 desktop tag。
- **iOS 版（App Store 的 `is.follow`）**: 同一个 bundle id，在 Apple 芯片 Mac 上能装的是 wrapped iOS bundle。`AppScanner` 对 wrapped bundle 置 `isMASApp = true`（`Scan/AppScanner.swift` `isMAS = !isTestFlight && (isiOSAppOnMac || hasReceipt)`），`UpdateChecker` 对 `isMASApp` 跳过 `answersAppStoreCopies == false` 的 source（GitHub 是 false），所以 GitHub rule 不会给 iOS 版报 1.16.0、更不会拿 dmg 盖掉它。**这条是读代码得出的，没有在真实的 wrapped 副本上跑过**。
- **版本范围、主机下限**: `LSMinimumSystemVersion` 1.15.0/1.16.0 = 13.0，0.9.0 = 12.0，0.3.x = 11.0，都低于 DuoUpdater 的 15.0。x64 资产不选：DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`）。
- **版本模式**: 在全部 123 个 release 上跑过（2026-10-22）：收 60 个（`desktop/vX` 31 个 + `vX` 29 个，含两个本来就被 `/releases/latest` 排除的 prerelease），不收 63 个 = 19 个 `mobile/` + 44 个带 `-beta.N`/`-alpha.N`/`-internal.N` 后缀的。`desktop/v2.0.0` → 2.0.0、`desktop/v1.17` → 1.17、`desktop/v1.17.0-rc.1` 和 `mobile/v1.0.0` → 不匹配。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `is.follow` | — | 默认 | `/releases/latest` + 锚定 pattern | ✓ |
| （Follow 时期 `-beta.N` 副本） | `is.follow` | 共享 | 版本后缀 → beta | `.beta` rule 读 `/releases/latest` | ✓（只检测） |

## 更新检测
- 源: `RSSNext/Folo` GitHub Releases，`/releases/latest`
- 版本: tag `desktop/v1.16.0` → `^(?:desktop/)?v([0-9]+(?:\.[0-9]+)+)$` → `1.16.0`，等于 `CFBundleShortVersionString`（`CFBundleVersion` 也是 1.16.0）
- 厂商自己的更新器读的也是同一批资产：`GET https://ota.folo.is/manifest`（头 `X-App-Platform: desktop/macos/dmg`、`X-App-Version`、`X-App-Runtime-Version`、`X-App-Channel: stable`），2026-10-22 以 1.15.0 身份请求得 200，`app.version = 1.16.0`，`files[]` 是 `github.com/RSSNext/Folo/releases/download/desktop/v1.16.0/Folo-1.16.0-macos-{arm64,x64}.{dmg,zip}`，每项带 `sha512`；以 1.16.0 身份请求得 204（无更新）。`/policy` 两次都是 `{"action":"none","distribution":"direct",…}`
- 注意: 这个 manifest 按请求头里的版本回答，可以做 VendorProbe，但它给的东西和 GitHub 一样，没有必要

## 按架构 / 按 OS 分轨
- 分架构资产：`Folo-<v>-macos-arm64.{dmg,zip}`、`Folo-<v>-macos-x64.{dmg,zip}`。1.16.0 arm64 dmg 的 bundle `archs=arm64`。0.1.x 时期是 universal
- `LSMinimumSystemVersion` 13.0（1.15.0、1.16.0）；release 和 OTA manifest 都不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 的 blockmap 差分下载） | 无 | — |
| 证据 | electron-updater 6.x 打包在 `app.asar` 里 | `desktop/v1.16.0` 的资产里没有 `.blockmap`（`gh api …/releases/tags/desktop/v1.16.0` 计数 0）；OTA manifest 只给整包 | 没有可消费的东西 |

- 另有 renderer 热更新（`render-asset.tar.gz`，解到 `<userData>/render/<version>/`（`constants/app.ts` `HOTUPDATE_RENDER_ENTRY_DIR`）），只换前端资源、bundle 版本不变，与我们无关；1.15.0 请求时 manifest 的 `renderer` 是 `null`

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会，两处 | 真机（2026-10-22）：1.15.0 启动 16 s 后 `~/Library/Caches/Folo/pending/` 有 `Folo-1.16.0-macos-arm64.zip` + `update-info.json`，`is.follow.ShipIt/update.*/Folo.app` 已武装（`ShipItState.plist` 指向 `/Applications/Folo.app`） | ○（ShipIt 那份由通用路径让路，见一键安装） |
| 证据 | `configs.ts`: `autoCheckUpdate`、`autoDownloadUpdate` 都是 true，15 min 轮询；`index.ts`: `autoInstallOnAppQuit = true`。`app.asar` 里 `MacUpdater`：electron-updater 下完 zip 后立刻起本地代理喂给 Squirrel.Mac（`nativeUpdater.checkForUpdates()`），Squirrel 再暂存一份 | — | `SelfUpdaterStash` 的 electron 布局只认 bundle 自己声明的 `updaterCacheDirName`，Folo 的 `app-update.yml` 没有（`owner/repo/provider: custom/private`），所以不读 |

- 停放位置（从 `app.asar` 读）: electron-updater 是 `path.join(baseCachePath, dirName || app.name)`，没有 `updaterCacheDirName` 时就是 `~/Library/Caches/Folo/pending/`（`update-info.json` + zip，完成后才写记录，sha512 base64）；Squirrel.Mac 是 `~/Library/Caches/is.follow.ShipIt/`。后者由引擎通用的 ShipIt 处理（`SelfUpdaterStaging`）
- 容器: zip（`Folo-<v>-macos-arm64.zip`，包根是 `Folo.app`）
- 两份副本会不会共用目录: 会，目录名来自 `app.name` 不分副本。这正是 `electronCacheDirectoryName` 不猜回退名的原因；要读这份停放包得在 `SelfUpdaterStash` 里给它一个明确的名字，是引擎改动

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify 从 1.15.0 起的 `changelog pane`）: `source structured: 1 entries; newest 1.16.0: 33 items, headings ["Shiny new things", "Improvements", "No longer broken"]; first items ["Two-factor authentication setup now has ", "Smoother timeline, sidebar, reader and A", "Much better keyboard and screen reader s"]`——三个 `##` 小节标题都保留，条目没被压平。正文顶部的 `# What's new in v1.16.0` 是标题行，不进条目
- 跟随 channel: —（beta rule 读的也是稳定版正文）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Folo.app`。Pattern `^Folo-[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$`，kind `.dmg`
- 嵌套: 只有 `Contents/Frameworks/Folo Helper{, (GPU), (Plugin), (Renderer)}.app`（Electron 的子进程 helper，随主进程退出），没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent
- 签名: 1.15.0 和 1.16.0 都是 `TeamIdentifier=492J8Q67PF`，`spctl` `Notarized Developer ID`，`codesign --verify` 通过
- 校验: GitHub 资产 `digest`。1.16.0 arm64 dmg 资产 `sha256:0b44b8d39115ec6d1c0f88e0f47abb0da5d866a4dc19248c22ac51b4e6922673`，下载的文件 `shasum -a 256` 相同，140223564 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；厂商自己的 OTA manifest 也指向同一批 GitHub 资产）
- 端到端:
  - 第一轮（不运行）: 1.15.0 → `duo check` `1.15.0 → 1.16.0 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.16.0、可执行文件 inode 变、`TeamIdentifier=492J8Q67PF`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.16.0 包相同
  - 第二轮（运行中）: 启动 1.15.0，等它自己停放 1.16.0（见上表）后 `duo install --json` → `skipped`，原因 `its own updater already has 1.16.0 staged — quit it to apply, or duo restart`（让路给同版本的暂存）；`duo restart Folo` → `quit — its own updater applied 1.16.0`：ShipIt 13:33:29 开始、13:33:30 装完，新进程 13:33:30 起来，之后 10 s 磁盘一直是 1.16.0、签名有效
- 启动副作用（2026-10-22 真机核对的已注明）:
  - 启动会注册 `folo://` URL scheme（`setAsDefaultProtocolClient`）
  - 开机启动是设置里的开关（`setLoginItemSettings({openAtLogin})`），不是默认写入；没有 LaunchAgent / root helper
  - 1.15.0 的 release note 之后修了「每次启动都把会话写进 Folo CLI 配置」：`~/.folo/config.json`（`app.asar` 里 `CLI_CONFIG_DIR = ~/.folo`）。不登录时预计不写。真机：没登录，启动后没有 `~/.folo`
  - 真机首启建了 `~/Library/{Application Support,Logs,Caches}/Folo`、`~/Library/Caches/is.follow{,.ShipIt}`、`~/Library/HTTPStorages/is.follow`、`~/Library/Preferences/is.follow.plist`；不往 `~/.claude`、`~/.agents` 写（`app.asar` 里没有 `.claude`；`.agents` 两处命中是无关的压缩代码）
  - 运行中会自己下载并经 Squirrel 暂存新版，退出时由 ShipIt 装上（`autoInstallOnAppQuit`）
- 阻塞: 无。Follow 时期 `-beta.N` 副本只检测、没有一键，见覆盖清单

## 已知问题
- 改名前的 `Follow.app`（0.3.5–0.3.12，Team 已是 `492J8Q67PF`）会被一键原地换成 `Folo.app` 的内容、路径仍叫 `Follow.app`（解包按 `.app` 取、换包按已装路径）。和厂商自己的 Squirrel 原地换包同一结果，未真机验证

## 如何复验
```
gh api repos/RSSNext/Folo/releases/latest -q .tag_name                    # → desktop/v1.16.0
gh api repos/RSSNext/Folo/releases/tags/desktop/v1.16.0 -q '.assets[]|select(.name|test("macos-arm64"))|.name+" "+(.size|tostring)+" "+.digest'
swift run --package-path application-test feed-discover Folo-1.16.0-macos-arm64.dmg   # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Folo-1.15.0-macos-arm64.dmg --expect stable
  # → detected stable，winning source GitHub，latest 1.16.0，UPDATE → 1.16.0，changelog pane 见上
swift run --package-path application-test channel-verify Folo-1.16.0-macos-arm64.dmg --expect stable   # → up to date
swift run --package-path application-test channel-verify Follow-0.3.12-macos-arm64.dmg --expect stable # → stable，UPDATE → 1.16.0
swift run --package-path application-test channel-verify Follow-0.3.4-beta.1-macos-arm64.dmg --expect beta # → beta，GitHub，UPDATE → 1.16.0，download 是 releases 页
.claude/skills/coverage-discovery/scripts/check-bundle.sh <dmg>            # Team / spctl / nested / updater
curl -s -H 'X-App-Platform: desktop/macos/dmg' -H 'X-App-Version: 1.15.0' -H 'X-App-Runtime-Version: 1.15.0' \
  -H 'X-App-Channel: stable' https://ota.folo.is/manifest                  # → app.version 1.16.0，GitHub 资产 URL
```

## 历史与实测

### 2026-10-22 —— Follow 时期 `-beta.N` 副本加只检测的 `.beta` rule

- 加 rule 之前（同日接入时）: `Follow-0.2.6-beta.0-macos-arm64.dmg` channel-verify 是 `inferred beta` → `winning source <none>`、`status unknown`
- `gh api` 核对: `v0.1.0-beta.0` … `v0.3.4-beta.1` 共 21 个 desktop release 全是 `prerelease: false`，各带 `Follow-<v>-macos-arm64.dmg` 或 universal dmg；`/releases/latest` 是 `desktop/v1.16.0`
- 加 rule 之后，`Follow-0.3.4-beta.1-macos-arm64.dmg`（97042582 字节，sha256 `aa85a8d50748df2a3a139d7a62e02a542235ebe15f24b5443ee2d88c9a2c6748`；这个 release 的资产没有 API `digest`）:
  ```
  app             Follow
  short version   0.3.4-beta.1
  detected channel  → beta
  ✓ detection matches --expect beta
  winning source  GitHub
  latest          1.16.0
  download        https://github.com/RSSNext/Folo/releases
  status          UPDATE → 1.16.0
  ```
- 对照 `Folo-1.15.0-macos-arm64.dmg` `--expect stable`，结果不变: `winning source GitHub`、`latest 1.16.0`、`download https://github.com/RSSNext/Folo/releases/download/desktop/v1.16.0/Folo-1.16.0-macos-arm64.dmg`、`UPDATE → 1.16.0`

## 建议下一步
1. 若要用上停放的 zip：`SelfUpdaterStash` 给 `is.follow` 明确停放目录 `Folo`（引擎改动；先确认两份副本共用目录的处理）
