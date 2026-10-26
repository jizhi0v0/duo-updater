# AFFiNE

## 基本信息
- App: AFFiNE — 开源文档 / 白板 / 数据库工作区（Electron Forge），桌面端在 monorepo 的 `packages/frontend/apps/electron`
- Bundle ID: stable `pro.affine.app`；beta `pro.affine.beta`；canary `pro.affine.canary`（settled from source: `packages/frontend/apps/electron/scripts/make-env.ts` on `canary` 的 `appIdMap`；还有一个 `internal` = `pro.affine.internal`，不发 GitHub release，自更新器对它关闭）
- 仓库: `toeverything/AFFiNE`（默认分支 `canary`，没有归档，README 没有停更声明）
- Team ID: `73YMMDVT2M`（`forge.config.mjs`: `Developer ID Application: TOEVERYTHING PTE. LTD.`）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID（三轨都是）
- 观测版本: stable 0.27.4（tag `v0.27.4`，资产 `affine-0.27.4-stable-macos-arm64.dmg`），上一版 0.27.3；beta 0.27.5-beta.1、0.27.5-beta.0；canary 2026.10.25-canary.907、2026.10.23-canary.908；观测日期: 2026-10-26
- 自更新机制: **electron-updater 6.8.9（custom provider）+ Squirrel.Mac**，见「更新检测」
- 分发: GitHub Releases（每版 arm64 / x64 各一个 dmg 和 zip，外加 Linux / Windows 包、`latest*.yml`、自托管服务端的 `docker-compose.yml` / `config.*.json`）；Homebrew cask `affine`（`auto_updates true`，0.27.4，装 arm64 zip）；没有 `@beta` / `@canary` cask；Mac App Store 按三个 bundle id 查都是 0 条（`itunes.apple.com/lookup?bundleId=…&entity=desktopSoftware`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓ | — |
| **canary** | —       | —        | —   | ✓ | — |

当前生效源: **GitHub**（三轨 channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`；`app-update.yml` 写的是 `provider: custom`，feed-discover 给 `review electronProviderNeedsConstruction`，`ElectronManifestSource` 读不了 custom provider；没有 MyGo feed；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v0.27.4、v0.27.3、v0.23.2、v0.12.3、v0.6.0: 都是 `pro.affine.app`，Team 73YMMDVT2M，Notarized，`CFBundleShortVersionString` = `CFBundleVersion` = tag 去掉 `v`（0.12.3 及更早资产名不带版本号：`affine-stable-macos-arm64.dmg`）
  - v0.5.2（release 名 "AFFiNE Desktop App Preview"，2023-04）: **`com.electron.affine`**，Team 相同，`CFBundleShortVersionString` 0.0.0，资产 `affine-darwin-arm64.dmg`。见「已知问题」的缺口
  - beta 0.27.5-beta.0 / .1: `pro.affine.beta`，`CFBundleName` AFFiNE-beta，Team 相同
  - canary 2026.10.23-canary.908 / 2026.10.25-canary.907: `pro.affine.canary`，`CFBundleName` AFFiNE-canary，Team 相同
  - Team 从 0.5.2 到 0.27.4 没换过，上一版 0.27.3 的副本一键不会被 Team 闸拒
- 其他轨: beta、canary 各有自己的 bundle id 和 app 名，装在旁边、不覆盖 stable（Pattern A），各接一条 rule，见「Channel 详情」。release 列表 596 个: 98 个 `vX.Y.Z`（97 个正式版，`v0.5.3` 标了 prerelease），164 个 beta（153 个 `vX.Y.Z-beta.N`，11 个不带 `v`），329 个 canary（2026-03-06 起是 `vYYYY.M.D-canary.N`，之前是 `v0.x.y-canary.N`，3 个不带 `v`），1 个 `0.11.0-nightly-…`，3 个早期 alpha。2026 年起的 beta / canary 全部 `prerelease: true`；2023 年的 `v0.5.4-beta.0` … `v0.8.2-beta.0` 共 14 个没标 prerelease，但它们早被正式版压在下面，`/releases/latest` 不会再落到它们上，`versionPattern` 的 `$` 锚也不收 `-beta`
- `/releases/latest`（2026-10-26）= `v0.27.4`，是桌面正式版，带 macOS 资产；0.13 起每个正式版都有 `affine-<v>-stable-macos-arm64.dmg`
- 版本范围: 正式版 tag 全部 `v<数字>(.<数字>)+`，`versionPattern` 都读得出；`v1.0.0`、`v0.28` 这类下一个大版本 / 两段 tag 也匹配，`v0.27.5-beta.1` 不匹配
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；AFFiNE `LSMinimumSystemVersion` 12.0（0.12.3 是 10.15），在下限之下，不需要 `hostRequirement`。三条 rule 都只装 arm64 dmg；装在 Apple 芯片 Mac 上的 x64 副本也会被换成 arm64 包（同 id、同 Team，等于从 Rosetta 换到原生）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `pro.affine.app` | 独立 | — | GitHub `/releases/latest` | ✓ |
| beta    | `pro.affine.beta` | 独立 | bundle id 后缀 `.beta`（`ReleaseChannel.detect` 实测 `inferred beta`） | GitHub 列表取第一个 `-beta.N` tag | ✓ |
| canary  | `pro.affine.canary` | 独立 | bundle id 后缀 `.canary`（实测 `inferred canary`） | GitHub 列表取第一个 `-canary.N` tag | ✓ |

- 三轨怎么出包（settled from source: `scripts/make-env.ts`、`forge.config.mjs` on `canary`）: `BUILD_TYPE` 决定 `productName`（stable `AFFiNE`，其余 `AFFiNE-<buildType>`）和 `appBundleId`；数据目录随 `productName` 分开（源码注释 "so stable and canary will not share the same app data"）
- 版本串: beta / canary 的包内版本就是 tag 去掉 `v`（`0.27.5-beta.1`、`2026.10.25-canary.907`），rule 的捕获组保留后缀，跟包内版本逐字相等
- 厂商的 beta 更新器只给 beta 构建（`allowPrerelease = buildType !== 'stable'`，feed 按 `channel=beta` 过滤），我们的 beta rule 也只读 `-beta.N` tag，不会给 beta 副本推 stable
- `listPageSize`: canary 几乎总是列表第一个，两个日期 canary 之间最多隔 12 个别的 release，默认 20 够。beta 在 2026-10-26 排第 26（8-26 之后只有 canary）；2025 年以来两个 beta 最多相隔 14 位。取 50。超过这一页时 rule 读不到 beta，行上是 unknown，不会给错版本
- 一键: 非 stable 轨有 `githubChannelProofs`，要求安装 URL 的 tag 和文件名都带本轨的词（`/download/v…-beta.N/affine-…-beta.N-beta-macos-arm64.dmg`、canary 同形）

## 更新检测
- 源: `toeverything/AFFiNE` GitHub Releases。stable 读 `/releases/latest`；beta / canary 读列表（`usePrereleases`）
- `versionPattern`: stable `^v([0-9]+(?:\.[0-9]+)+)$`；beta `^v?([0-9]+(?:\.[0-9]+)+-beta\.[0-9]+)$`；canary `^v?([0-9]+(?:\.[0-9]+)+-canary\.[0-9]+)$`
- install pattern: `^affine-[0-9]+(?:\.[0-9]+)+-stable-macos-arm64\.dmg$`（beta / canary 把 `-stable` 换成 `-beta\.[0-9]+-beta` / `-canary\.[0-9]+-canary`）。同一个 release 里的 x64 dmg、两个 zip、Linux / Windows 包、yml 都不匹配
- **AFFiNE 自己的更新器**（settled from source: `src/main/updater/electron-updater.ts`、`affine-update-provider.ts` on `canary`；包内 `app.asar` 的 `node_modules/electron-updater` 是 6.8.9）:
  - `autoUpdater.setFeedURL(AFFiNEUpdateProvider.configFeed({channel: buildType}))`，请求 `https://affine.pro/api/worker/releases?channel=<stable|beta|canary>&minimal=true`，取返回数组第一个，再读那个 release 的 `latest.yml`
  - 启动后按设置检查（`autoCheckUpdate` 默认 true），之后窗口获得焦点时最多 30 分钟一次；`autoDownloadUpdate` 默认 true，有更新就自动下载；`autoInstallOnAppQuit = false`，只有用户点重启更新时才交给 Squirrel.Mac（`quitAndInstall`）
  - 2026-10-26 实测这个端点: `channel=stable` 返回 `[]`（Cloudflare 缓存 `max-age=14400`），`channel=beta` 返回 0.27.5-beta.1 / .0 两条，`channel=canary` 返回 28 条。三条加起来正好是 GitHub release 列表的前 30 个（逐个 tag 比过），所以这个 worker 只看列表第一页；0.27.4 排第 32，于是 stable 更新器眼下拿到空数组，按源码会抛 "No published versions in channel stable"。"只看第一页"是从这组数据推的，worker 源码不在仓库里
  - 0.6.0 的 `app-update.yml` 还是 `provider: github`，那一代自己读 GitHub
- 本 rule 读的是人人能手动下载的 GA / 公开 prerelease，与厂商更新器读同一批 release；不是按设备分配的灰度

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`-macos-arm64`、`-macos-x64`），没有 universal；rule 只装 arm64。`latest-mac.yml` 四个文件都列（x64/arm64 × zip/dmg），厂商更新器用 `filterFilesForArch` 选 arm64 zip
- `LSMinimumSystemVersion`: 12.0（0.27.x 三轨），release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 无 | — |
| 证据 | 包内 electron-updater 6.8.9 `MacUpdater.js`: `differentialDownloadInstaller`，前提是缓存里有上一份 `update.zip` | 2026-10-26 v0.27.4 的 18 个资产里没有 `.blockmap`，差分无从做起，只能整包 | — |

- 格式: electron-builder blockmap（不是 Sparkle binary delta）

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 真机（2026-10-26）：0.27.3 运行约 40 s，它自己的更新器没有停放任何东西（stable 的厂商 feed 返回 `[]`） | ○ |
| 证据 | electron-updater 6.8.9 `DownloadedUpdateHelper` / `AppUpdater.getOrCreateDownloadHelper`（包内 asar 读的） | — | `SelfUpdaterStash` 的 electron-updater 读法要求包里 `app-update.yml` 写 `updaterCacheDirName`；AFFiNE 的只有 owner / repo / provider / private，于是返回 nil |

- 目录: `~/Library/Caches/<app.name>/pending/`。`updaterCacheDirName` 缺省时 electron-updater 用 `app.name`（会记一条 error 日志），stable 即 `~/Library/Caches/AFFiNE/pending/`，beta / canary 是 `AFFiNE-beta` / `AFFiNE-canary`（推断自源码，未在真机上看到）
- 记录文件与字段: `update-info.json`，`fileName` + `sha512`（base64，整个 zip），下载完成后写；另把 zip 复制成同目录上一层的 `update.zip` 供下次差分
- 容器: arm64 zip（forge `maker-zip`）；包根是不是 `AFFiNE.app` 没拆开核
- 两份副本会不会共用这个目录: 三轨不会（目录名随 `productName`）；同一轨装两份会
- 2026-10-26 stable feed 是空数组，stable 副本此刻不会下载任何东西

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- stable 结构化（2026-10-26，channel-verify `changelog pane`，从 0.27.3 起）: `source structured: 1 entries; newest 0.27.4: 9 items, headings ["Web & Editor", "Native Client", "Backend"]; first items ["Improve byok model editing", "Fix code block line number trigger", "Fix journal can see trashed docs"]`
  - 三个 `###` 分节保留、没被压平，3 + 3 + 3 = 9 条。正文开头的配图和 `## Breaking change` 下的三段纯文字（客户端 / 服务端版本兼容、BYOK 说明）不是列表项，解析器按设计丢掉
- beta / canary: **不是结构化**。pane 是 `web page https://github.com/toeverything/AFFiNE/releases/tag/<tag>, no structure`，因为厂商发的 beta / canary release 正文是空的（`gh api …/releases/tags/v0.27.5-beta.1 -q .body`、`v2026.10.25-canary.907` 都是空串）。没有可解析的说明，不是解析失败
- 跟随 channel: 是（每条 rule 读本轨的 release）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（三轨）**；stable 真机两轮通过（2026-10-26），beta / canary 只做过 channel-verify，没在真机上跑
- 端到端（2026-10-26，本分支 `make cli` 的 duo，stable）:
  - 第一轮（不运行）: 0.27.3 → `duo install` → 0.27.4、`TeamIdentifier=73YMMDVT2M`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 0.27.3 用 `open -g` 启动，约 40 s 后它自己的更新器没停放任何东西（厂商 feed 对 stable 返回 `[]`）；`duo install` 就地装好，提示 `Still running the old code`；`duo restart AFFiNE` → `restarted`，20:00:43 起的新进程是 0.27.4，`codesign` 0
  - beta / canary 轨: 检测只有 channel-verify，没有真机运行
  - 终态: 0.27.4，未运行。副作用: `~/Library/Application Support/AFFiNE`
- 格式: dmg（`hdiutil imageinfo` exit 0），根目录 `AFFiNE.app` + `/Applications` 软链（forge `maker-dmg`）
- 嵌套: `Contents/Frameworks/` 下四个标准 Electron Helper（`AFFiNE Helper.app`、`(GPU)`、`(Plugin)`、`(Renderer)`，id `pro.affine.app.helper`，`LSUIElement`）——主进程的子进程，随主程序退出；另有 `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`（Squirrel.Mac 及其依赖）。没有 `Contents/Library/LoginItems`、LaunchAgent / LaunchDaemon；`dist/main.js` 里没有 `setLoginItemSettings` / `openAtLogin` / `SMAppService`
- 签名: 0.5.2、0.5.3、0.6.0、0.12.3、0.23.2、0.27.3、0.27.4 及 beta / canary 都是 Team 73YMMDVT2M、Notarized Developer ID
- 校验: GitHub 资产 `digest`。v0.27.4 arm64 dmg `sha256:4bbb5def9e377f513be0fa05f1cc29ec2738e2d5432029df3f02c91f5ffadfea`，下载的文件 `shasum -a 256` 相同、158774537 字节等于资产大小；v0.27.3 dmg 9f726ef6…、0.27.5-beta.1 dmg 79582d5f…、2026.10.25-canary.907 dmg 350e6e37… 同样由 GitHub `digest` 覆盖
- **读的是**: 人人可手动下载的 GA（stable `/releases/latest`）；beta / canary 读本轨最新的公开 prerelease，就是厂商自己的 beta / canary 更新器会给的那一版
- 阻塞: 无
- 真机前的注意点（来自源码和包内容；2026-10-26 实测见上面的「端到端」）:
  - 首启会检查更新；stable 的 feed 眼下是空数组，应只在日志里报错、不弹窗；若 feed 恢复，`autoDownloadUpdate` 默认开，会把 arm64 zip 下到 `~/Library/Caches/AFFiNE/pending/`，界面出现「重启更新」，不要点（点了就是 Squirrel 自己换包）
  - 注册 URL scheme `affine`（`setAsDefaultProtocolClient`）
  - 数据在 `~/Library/Application Support/AFFiNE`（`userData`），日志 `~/Library/Logs/AFFiNE`
  - Info.plist 声明麦克风、摄像头、蓝牙、系统音频捕获（`NSAudioCaptureUsageDescription`）的用途说明，首启是否立即请求没核
  - `dist/main.js` 里没有 `.claude` / `.codex` / `.agents` 字符串
  - 自更新器只在用户点重启时才交给 Squirrel，所以第二轮"让它暂存一个比 latest 旧的版本"需要它的 feed 先给出一个旧版本；当前 stable feed 为空，无从暂存

## 已知问题
- **`com.electron.affine`（0.5.x 预览版）经 `BundleIDMigration` 接上**: 0.5.2 的真包是 `com.electron.affine`、版本 0.0.0、同 Team；0.6.0 起才是 `pro.affine.app`。`BundleIDMigration.all` 有一条 `com.electron.affine → pro.affine.app`（Team 73YMMDVT2M，`lastFromVersion` 0.5.3，`firstToVersion` 0.6.0；v0.5.3 prerelease 真包也是 `com.electron.affine`、版本 0.5.3、同 Team，2026-10-26 实测），预览版副本按 `pro.affine.app` 检测、被提供最新稳定版。这个 id 是 Electron 工具链的通用形状（`com.electron.<name>`）：Team 只约束换包和回滚（Gate 4、`restoreMigration`），检测阶段不看 Team，任何 0.6.0 以下的 `com.electron.affine` 副本都会被当成 AFFiNE 检测；别的 Team 签的副本在安装的 Team 闸被拒、原副本不动，ad-hoc 副本只检测不一键。`covers` 只比 `firstToVersion` 这一个界。标成 `isRewrite`：一键前先让用户确认，因为预览版的工作区能否带到 0.27 没验证。`BundleIDMigrationTests.affinePreviewCopyIsFiledUnderTheStableApp` 钉住这条
- AFFiNE 的 stable 自更新器眼下拿不到版本（worker 只看列表前 30 个，0.27.4 已被 canary / beta 挤出去），这是厂商侧的问题；它不影响我们的检测，反而意味着此刻没有自更新器和我们抢
- beta 轨从 2026-08-26 起没有新版本；如果 canary 持续发而 beta 长期不发，beta 会滑出 50 条的页，beta 行变 unknown（不是错版本）。厂商自己的 beta 更新器在第 30 条外就已经读不到了

## 如何复验
```bash
gh api repos/toeverything/AFFiNE/releases/latest -q .tag_name                      # v0.27.4
gh release download v0.27.4 -R toeverything/AFFiNE -p 'affine-0.27.4-stable-macos-arm64.dmg'
gh release download v0.27.3 -R toeverything/AFFiNE -p 'affine-0.27.3-stable-macos-arm64.dmg'
gh release download v0.27.5-beta.1 -R toeverything/AFFiNE -p 'affine-0.27.5-beta.1-beta-macos-arm64.dmg'
gh release download v2026.10.25-canary.907 -R toeverything/AFFiNE -p 'affine-2026.10.25-canary.907-canary-macos-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh affine-0.27.3-stable-macos-arm64.dmg    # pro.affine.app, Team 73YMMDVT2M, Notarized
swift run --package-path application-test channel-verify affine-0.27.3-stable-macos-arm64.dmg --expect stable
swift run --package-path application-test channel-verify affine-0.27.4-stable-macos-arm64.dmg --expect stable
swift run --package-path application-test channel-verify affine-0.27.5-beta.1-beta-macos-arm64.dmg --expect beta
swift run --package-path application-test channel-verify affine-2026.10.25-canary.907-canary-macos-arm64.dmg --expect canary
curl -sS 'https://affine.pro/api/worker/releases?channel=stable&minimal=true'       # 2026-10-26: []
```

channel-verify 原始输出（2026-10-26，节选）:
```
0.27.3 dmg: bundle id pro.affine.app; short version 0.27.3; inferred stable; detected channel → stable
  winning source  GitHub
  latest          0.27.4
  download        https://github.com/toeverything/AFFiNE/releases/download/v0.27.4/affine-0.27.4-stable-macos-arm64.dmg
  changelog pane  source structured: 1 entries; newest 0.27.4: 9 items, headings ["Web & Editor", "Native Client", "Backend"]; first items ["Improve byok model editing", "Fix code block line number trigger", "Fix journal can see trashed docs"]
  status          UPDATE → 0.27.4
0.27.4 dmg: detected channel → stable; winning source GitHub; latest 0.27.4; status up to date
0.27.5-beta.0 dmg: bundle id pro.affine.beta; inferred beta
  winning source  GitHub
  latest          0.27.5-beta.1
  download        https://github.com/toeverything/AFFiNE/releases/download/v0.27.5-beta.1/affine-0.27.5-beta.1-beta-macos-arm64.dmg
  changelog pane  web page https://github.com/toeverything/AFFiNE/releases/tag/v0.27.5-beta.1, no structure
  status          UPDATE → 0.27.5-beta.1
0.27.5-beta.1 dmg: detected channel → beta; winning source GitHub; status up to date
2026.10.23-canary.908 dmg: bundle id pro.affine.canary; inferred canary
  winning source  GitHub
  latest          2026.10.25-canary.907
  download        https://github.com/toeverything/AFFiNE/releases/download/v2026.10.25-canary.907/affine-2026.10.25-canary.907-canary-macos-arm64.dmg
  changelog pane  web page https://github.com/toeverything/AFFiNE/releases/tag/v2026.10.25-canary.907, no structure
  status          UPDATE → 2026.10.25-canary.907
2026.10.25-canary.907 dmg: detected channel → canary; winning source GitHub; status up to date
```

## 建议下一步
1. 若想用自更新器已下好的 zip: `SelfUpdaterStash` 需要在 `updaterCacheDirName` 缺省时按 `app.name`（= `CFBundleName`）回退，这是引擎改动；回退的风险写在那个属性的注释里
