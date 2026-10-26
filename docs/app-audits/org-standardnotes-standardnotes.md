# Standard Notes

## 基本信息
- App: Standard Notes — 开源端到端加密笔记（Electron），AGPL-3.0
- Bundle ID: `org.standardnotes.standardnotes`
- 仓库: `standardnotes/app`（monorepo，默认分支 `main`；桌面端源码在 `packages/desktop/`）。2022-06 之前桌面端在 `standardnotes/desktop`（已 archived，最后一版 v3.22.11），那里的 `package.json` 从 v2 起 `appId` 就是 `org.standardnotes.standardnotes`
- Team ID: `HKF9BXSN95`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.202.10（tag `@standardnotes/desktop@3.202.10`，资产 `standard-notes-3.202.10-mac-arm64.dmg`）；上一稳定版 3.202.7；观测日期: 2026-10-26
- 自更新机制: **electron-updater，`github` provider**。包内 `Contents/Resources/app-update.yml` = `owner: standardnotes` / `repo: app` / `provider: github` / `updaterCacheDirName: '@standardnotesinner-desktop-updater'`。settled from source: `packages/desktop/app/javascripts/Main/UpdateManager.ts` on `main`（见「一键安装」的抢跑一节）
- 分发: GitHub Releases（每版 arm64 / x64 各一个 dmg + zip，外加 Linux / Windows 包和 `latest*.yml`）；Homebrew cask `standard-notes`（`auto_updates: true`，3.202.10，装的是 arm64 zip）；Mac App Store 没有这个 id（`itunes.apple.com/lookup?bundleId=org.standardnotes.standardnotes` 0 条）。iOS 版是 `com.standardnotes.standardnotes`，另一个 id，不归这条 rule
- 终止: repo 没 archived，README 没有停止维护的说法（2026-10-26）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`；`app-update.yml` 是 `github` provider，`ElectronManifestSource` 不替 `github` / `s3` provider 拼地址（见该文件头注释），所以要这条 `GitHubReleaseRule`；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh` / scaffold）:
  - @standardnotes/desktop@3.202.10: `org.standardnotes.standardnotes`，Team HKF9BXSN95，Notarized，`CFBundleVersion` 3.202.10
  - @standardnotes/desktop@3.202.7: 同 id、同 Team，Notarized，`CFBundleVersion` 3.202.7
  - @standardnotes/desktop@3.201.18（2026-02）: 同 id、同 Team
  - 更老的包（2022–2025）没下真包核 Team。id 由源码定：`standardnotes/desktop` 的 `package.json` 在 v2.0.0、v3.0.0、archived 时的 `main` 上 `appId` 都是 `org.standardnotes.standardnotes`。若老包 Team 不同，一键的 Team 闸会拒装，只剩检测（未实测）
- 改名前的旧 id: 没有。v2 / v3.0 时代 `package.json` 里有一个 `build-beta` 脚本，用 `--em.appId=org.standardnotes.standardnotes.beta` 打「Standard Notes (Beta)」；archived 时的 `package.json` 里已经没有这个脚本。这类副本是另一个 id，本 rule 不匹配，记为缺口：2020 年前后的 x64 测试版，没有下包核过它到底是不是这个 id（推断自源码），也没有活的 feed 可接
- 其他轨: 见「Channel 详情」。没有应用内 beta 开关（`StoreKeys.ts` 只有 `enableAutoUpdates`）
- 版本范围: 全部 2908 个 release 里非 prerelease 的 107 个，105 个是 `@standardnotes/desktop@<数字>(.<数字>)+`，`versionPattern` 都读得出；另 2 个是 `@standardnotes/mobile@3.24.0` / `3.24.1`（2022-06），不匹配，本来也不是桌面版。1054 个 desktop prerelease 的 tag 也全是纯数字版本。`4.0.0`、两段式 `3.203` 能读；`3.203.0-beta.1`、`-alpha.0` 不匹配（锚定）
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Standard Notes `LSMinimumSystemVersion` 11.0，在下限之下，不需要 `hostRequirement`。x64 包不装（主机只有 arm64）
- 商店副本: 没有 Mac App Store 版

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.standardnotes.standardnotes` | — | 纯数字版本 | GitHub `/releases/latest` | ✓ |

**prerelease 不是另一条轨（settled from source: `.github/workflows/desktop.release.reuse.yml` on `main`）:**
- CI 用 `softprops/action-gh-release` 发布每个桌面构建，写死 `prerelease: true`、`draft: false`；厂商再手动把其中一些取消 prerelease。2026-08-17 之后 3.202.0 / 3.202.7 / 3.202.10 被转正，3.202.1–6、8、9、11 仍是 prerelease
- 这些 prerelease 和正式版是同一条版本线、同一个 id、纯数字版本，不是 beta。Standard Notes 自己的更新器也不提供它们：electron-updater 的 `allowPrerelease` 默认等于「当前版本有没有 semver prerelease 段」（包内 asar 里的 `allowPrerelease = hasPrereleaseComponents(currentVersion)`），app 没改它，所以纯数字版本只读 `/releases/latest`
- 手动下载了 prerelease 的副本：比最新正式版新的（如 3.202.11）显示 up to date；比它旧的（如 3.202.9）被提供更新的正式版，这是正常升级，不需要 gate
- 有些未转正的 release 资产不全（3.202.11 发布时 18 个资产，没有 Windows 包；3.202.6 0 个）。`/releases/latest` 不会落到它们上
- 2020–2022 年 `standardnotes/desktop` 还发过 `v3.x.y-beta.N` 这种 semver 测试版（最后是 v3.15.0-beta.4，2022-05）。现在的 monorepo 没再发过，厂商那边这条轨已经停了。这样的副本 `ReleaseChannel.detect` 读成 beta，稳定版 rule 不收：2026-10-26 在真包 3.15.0-beta.4（arm64 dmg，`org.standardnotes.standardnotes`，Team HKF9BXSN95，Notarized）上 channel-verify 读 `winning source <none>`、`status unknown (no source answered)`。所以另加了一条只检测的 `.beta` rule（同 Ferdium 旧 beta 的做法），读同一个 `/releases/latest`，beta 副本被提供当前正式版；不做一键（非 stable 安装要渠道证明）。真机（2026-10-26）: 装 3.15.0-beta.4 真包 → `duo check` 给 `3.15.0-beta.4 → 3.202.10 [GitHub]`，`duo install` 跳过并说 `detection only — this source publishes no installable artefact`，副本没动

## 更新检测
- 源: `standardnotes/app` GitHub Releases，`/releases/latest`
- 为什么 monorepo 也能用 `/releases/latest`: 2908 个 release 里，除桌面版外不带 prerelease 标记的只有 2022-06 的 mobile 3.24.0 / 3.24.1，mobile 和 clipper 之后的 release 全是 prerelease。所以 `/releases/latest` 是最新转正的桌面版（2026-10-26 实测：`@standardnotes/desktop@3.202.10`）。厂商自己的 electron-updater 也读这个地址。哪天 mobile / clipper 的 release 占了 `/releases/latest`，`versionPattern` 不匹配，行会变 unknown，不会读错版本
- 版本方案: tag `@standardnotes/desktop@3.202.10` → `CFBundleShortVersionString` `3.202.10`、`CFBundleVersion` `3.202.10`
- `versionPattern` `^@standardnotes/desktop@([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^standard-notes-[0-9]+(?:\.[0-9]+)+-mac-arm64\.dmg$`。同一 release 里的 `-mac-arm64.zip`、`-mac-x64.dmg`、`-mac-x64.zip`、`.blockmap`、Linux / Windows 包不匹配
- 下载 URL 用的是 GitHub 给的 `browser_download_url`（`%40standardnotes/desktop%40…`，斜杠没转义），实测 `curl -sIL` 200

## 按架构 / 按 OS 分轨
- 架构: arm64 / x64 分包（`latest-mac.yml` 四个文件），rule 只装 arm64 dmg；`LSMinimumSystemVersion` 11.0。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（blockmap 差分下载） | 有 `.zip.blockmap` / `.dmg.blockmap` | 不消费 |
| 证据 | 3.202.10 的 `app.asar` 里有 electron-updater 的 `blockmapFiles` / `downloadBlockMap` / `isUseDifferentialDownload` 代码 | 3.202.10 release 有 `standard-notes-3.202.10-mac-arm64.zip.blockmap`（161528 B）等 | 我们整包下 dmg；blockmap 差分是 electron-updater 下 zip 时自己用的，不是可直接套的补丁 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（自动更新开着时） | 真机（2026-10-26）：3.202.7 从 20:36:49 起运行，20:37:21 前已把 `standard-notes-3.202.10-mac-arm64.zip` 和 `update-info.json` 停放进 `~/Library/Caches/@standardnotesinner-desktop-updater/pending` | 第二轮 `duo install` 看到「它自己的更新器已暂存 3.202.10」而跳过 |
| 证据 | electron-updater 默认 `autoDownload = true`；`enableAutoUpdates` 默认 true（`createSanitizedStoreData.ts`）。下完放在 `~/Library/Caches/@standardnotesinner-desktop-updater/pending/`（`update-info.json` + arm64 zip），再交给 Squirrel，暂存在 `~/Library/Caches/org.standardnotes.standardnotes.ShipIt/`（cask 的 zap 也列了这个目录） | — | `SelfUpdaterStash` 按包内 `updaterCacheDirName` 找 `pending/update-info.json`；ShipIt 暂存由通用 `SelfUpdaterStaging` 识别 |

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`，按 `versionPattern` 只取桌面 tag）
- 结构化（2026-10-26，channel-verify `changelog pane`，从 3.202.7 起）: `source structured: 1 entries; newest 3.202.10: 2 items, headings ["Bug Fixes", "Desktop Changes"]; first items ["Fixes backups copy styling ([#3065](http", "Version bump only for package @standardn"]`
- 结构化 ✓，标题保留：正文是 `## Web Changes` → `### Bug Fixes` → 条目，加 `## Desktop Changes` → 条目。分节显示为 `Bug Fixes` 和 `Desktop Changes`（外层的 `Web Changes` 没成为单独的分节）。`Desktop Changes` 下几乎每版只有一条 "Version bump only for package @standardnotes/desktop"，这是厂商正文本身的内容
- 预览里的条目带着 `([#3065](http…` 这种 issue / commit 链接（channel-verify 只显示前 40 个字符）。我没在 UI 里核对它显示成链接还是原样 markdown
- **缺口**: 每个 release 的正文只写自己这一版，不累计。没转正的 prerelease 的说明不进历史：从 3.202.7 起只有 3.202.10 一条，3.202.8 的两条修复（`Fixes footer loading items string`、`Fixes Open file preview button on Android`）不显示。要补得把同一版本线上的 prerelease 正文也算进历史，这是引擎改动，本次没做
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-26，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 3.202.7 → `duo install` → 3.202.10、`TeamIdentifier=HKF9BXSN95`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 3.202.7 从 20:36:49 起运行，它的 electron-updater 在 20:37:21 前停放了 `standard-notes-3.202.10-mac-arm64.zip` 和 `update-info.json`。第一次 `duo install` 报 `app scan did not finish within 20.0 seconds`（当时负载 320）；重试 → `Skipping: Standard Notes — its own updater already has 3.202.10 staged`。`duo restart "Standard Notes"` → `quit — its own updater applied 3.202.10`，磁盘 3.202.10、`codesign` 0，20:38:13 重新拉起
  - 终态: 3.202.10，未运行
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `Standard Notes.app` + `Applications` 软链
- 嵌套: `Contents/Frameworks/` 下 Electron 的四个 helper（`Standard Notes Helper.app`、`(GPU)`、`(Renderer)`、`(Plugin)`，id `org.standardnotes.standardnotes.helper[.GPU|.Renderer|.Plugin]`，都是 `LSUIElement`）。没有 `Contents/Library`、LoginItems、LaunchAgent；`app.asar` strings 里 `setLoginItemSettings` / `openAtLogin` / `SMAppService` / `LaunchAgents` 都是 0 次
- `app.asar.unpacked/node_modules`: `keytar`、`sqlite3`、`microtime`、`cbor-extract` 原生模块，随 bundle 一起换
- 签名: 3.201.18、3.202.7、3.202.10 都是 Team `HKF9BXSN95`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产 `digest`。3.202.10 arm64 dmg `sha256:bca34d9aa92a25c22f4d211cdc2a684985a4b58dc4960edfab942f3a2c1569d6`，与下载的包一致，160120544 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Standard Notes 自己的更新器读的也是这一版）
- 阻塞: 无
- 自更新器会不会抢（settled from source: `packages/desktop/app/javascripts/Main/UpdateManager.ts` on `main`）: 启动时 `enableAutoUpdates`（默认 true）开着就调 `autoUpdater.checkForUpdates()`；`autoDownload` / `autoInstallOnAppQuit` 用 electron-updater 默认的 true，下完弹「更新已就绪」框（「稍后安装」/「退出并安装」），**用户不点也会在正常退出时由 Squirrel/ShipIt 换包**。所以 app 运行着、已经下完新版时，我们为装包让它退出，也会触发 ShipIt。暂存的版本和我们装的一样时无害；两者不一样的情况由通用的 `SelfUpdaterStaging` / `ParkedInstallerProbe` 处理，不是这条 recipe 独有的问题。`enableAutoUpdates` 关掉时启动不检查，只在用户手动「检查更新」时才查
- 真机前的注意点（来自源码 / 包内容；2026-10-26 实测见上面的「端到端」）:
  - 从 3.202.7 启动就会去 `/releases/latest` 检查并在后台下 3.202.10 arm64 zip（约 154 MB）到 `~/Library/Caches/@standardnotesinner-desktop-updater/`，然后弹更新框。退出时 ShipIt 会自己装，想测我们的路径就别在它下完后正常退出，或先在偏好里关掉自动更新
  - 每次启动都会注册成 `standardnotes://` 的默认处理程序（`setAsDefaultProtocolClient`，asar 里 3 处）
  - `minimizeToTray`（默认 false）开着时关窗口不退出，进程留在菜单栏
  - 用户数据在 `~/Library/Application Support/Standard Notes/`（cask zap 列表；`user-preferences.json` 在 Electron `userData` 下）。`useNativeKeychain` 会用 keytar 写钥匙串
  - 包里有一个「Home Server」功能（`@standardnotes/home-server`，`HomeServerDataLocation`），用户开了才在 app 进程里起本地服务；不是独立的常驻 helper（推断，未验证）

## 已知问题
- Changelog 不含没转正的 prerelease 的说明（见上）
- `org.standardnotes.standardnotes.beta` 这个老测试版 id 没覆盖（见「覆盖清单」）
- 2022–2025 的老包没有逐个核 Team；Team 若不同，一键会被闸拒绝，只剩检测

## 如何复验
```bash
gh api repos/standardnotes/app/releases/latest -q .tag_name     # @standardnotes/desktop@3.202.10
gh release download @standardnotes/desktop@3.202.10 --repo standardnotes/app --pattern 'standard-notes-3.202.10-mac-arm64.dmg'
gh release download @standardnotes/desktop@3.202.7 --repo standardnotes/app --pattern 'standard-notes-3.202.7-mac-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh standard-notes-3.202.7-mac-arm64.dmg   # Team HKF9BXSN95, Notarized, electron-updater github
swift run --package-path application-test channel-verify standard-notes-3.202.7-mac-arm64.dmg --expect stable    # GitHub, UPDATE → 3.202.10
swift run --package-path application-test channel-verify standard-notes-3.202.10-mac-arm64.dmg --expect stable   # up to date
```

channel-verify 原始输出（2026-10-26）:
```
3.202.7 dmg:
  detected channel  → stable
    winning source  GitHub
    latest          3.202.10
    download        https://github.com/standardnotes/app/releases/download/%40standardnotes/desktop%403.202.10/standard-notes-3.202.10-mac-arm64.dmg
    changelog pane  source structured: 1 entries; newest 3.202.10: 2 items, headings ["Bug Fixes", "Desktop Changes"]; first items ["Fixes backups copy styling ([#3065](http", "Version bump only for package @standardn"]
    status          UPDATE → 3.202.10
3.202.10 dmg:
  detected channel  → stable
    winning source  GitHub
    latest          3.202.10
    status          up to date
```

## 建议下一步
1. 如果要补 changelog 缺口：让 GitHub 历史把同一版本线上没转正的 prerelease 正文也算进来（引擎改动，需先定）
