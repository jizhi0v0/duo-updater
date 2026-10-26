# TimeScribe

## 基本信息
- App: TimeScribe — 开源工时记录（菜单栏 app），GPL-3.0。技术栈是 **NativePHP**：Laravel 应用由包内的 PHP（`Contents/Resources/build/php/php`）运行，外壳是 Electron（`Contents/Resources/build/app` 是 Laravel 源码，`app.asar` 里是 NativePHP 的 `electron-plugin` 和 `out/main/index.js`）
- Bundle ID: `de.amplussoftware.timescribe`（helper 是 `de.amplussoftware.timescribe.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: `WINBIGFOX/TimeScribe`（默认分支 `main`，未归档）
- Team ID: `69A277BV6W`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.17.1（tag `v1.17.1`，2026-09-21 发布，资产 `TimeScribe-1.17.1-arm64.dmg`）；上一版 1.17.0；观测日期: 2026-10-26
- 自更新机制: **electron-updater 6.8.3**（`provider: github`），在 Mac 上由 Squirrel.Mac 落地，详见「更新检测」
- 分发: GitHub Releases；Homebrew cask `timescribe`（`auto_updates: true`，`url` 指 arm64 zip，1.17.1）；App Store 没有（`itunes.apple.com/lookup?bundleId=de.amplussoftware.timescribe` 返回 0 条）；官网 timescribe.app 的下载指向 GitHub

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **beta**     | —       | —        | —   | ✓（只检测，给最新稳定版）| — |

当前生效源（channel-verify 实测）: **GitHub**。

`ElectronManifestSource` 接不上：`app-update.yml` 是 `provider: github`，不给地址。`feed-discover` 对 1.17.1 dmg 的结论是 `review electronProviderNeedsConstruction`。

## 覆盖清单
- **bundle id / Team**（读真包，`check-bundle.sh`）:
  - v1.17.1、v1.17.0: `de.amplussoftware.timescribe`，Team 69A277BV6W，Notarized，`CFBundleShortVersionString` = `CFBundleVersion` = tag 去掉 `v`
  - v1.2.0-beta.3: 同 id、同 Team、Notarized，版本 `1.2.0-beta.3`，`LSMinimumSystemVersion` 10.15
  - v0.1.0（release 列表里最老的一版，脚本读）: 同 id、同 Team
  - 没有改名前的旧 bundle id；`brew search` 只有 `timescribe` 一个 cask
- **其他轨**: `v1.2.0-beta.1`…`beta.3`（2025-05-08 至 05-16，标了 prerelease，资产名带 `-beta.N`，另发 `beta-mac.yml`）。同一个 id；真包 1.2.0-beta.3 的版本号带 `-beta.3`，`ReleaseChannel.detect` 读成 **beta**，stable rule 不服务它（加 beta rule 之前 channel-verify：`winning source <none>`、`status unknown (no source answered)`）。之后只发正式版（1.2.0 起），所以加了一条只检测的 `channel: .beta` rule，读 `/releases/latest`，给这些副本看最新稳定版。只检测的理由：非 stable 轨的安装要 channel proof，而能区分两条轨的只有已装副本的版本号。另有 tag `v1.1.2-dev`，没有 release，模式也不收
- **版本范围**: tag 全部是 `v<数字>(.<数字>)+`（beta 三个和 `v1.1.2-dev` 除外），脚本核过 45 个稳定 release 全读得出；`v1.1.1`、`v0.3.0`、`v0.3.1`、`v0.2.x`、`v0.1.1` 有 tag 无 release，同样是纯数字形状
- **主机下限**: DuoUpdater 只出 arm64、macOS 15（`App/project.yml`）；arm64 dmg `LSMinimumSystemVersion` 12.0（1.17.x），不构成限制
- **同 id 下的其他产品**: 没有。每版的 Mac 资产只有 arm64 / x64 两套，同一产品；Windows 的 `setup.exe` 不相干

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `de.amplussoftware.timescribe` | 共享 | 默认 | `/releases/latest` | ✓ |
| beta（2025-05 的 1.2.0-beta.N） | `de.amplussoftware.timescribe` | 共享 | 版本号 `-beta.N` | `.beta` rule 读 `/releases/latest` | ✓（只检测） |

应用内没有切 beta 的开关（settled from source: `app/Settings/AutoUpdaterSettings.php` 只有 `autoUpdate` / `lastCheck` / `lastVersion` / `isDownloaded`；`config/nativephp.php` 的 github provider `channel` 默认 `latest`，1.17.1 的 `app-update.yml` 是 `channel: latest`）。electron-updater 在当前版本带预发布段时自己打开 `allowPrerelease`（`AppUpdater.js` 第 218 行，`hasPrereleaseComponents(currentVersion)`），所以 beta 副本自己的更新器也会走到最新 release（今天是稳定版 1.17.1）。

## 更新检测
- 源: `WINBIGFOX/TimeScribe` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.17.1` → `CFBundleShortVersionString` `1.17.1`、`CFBundleVersion` `1.17.1`（`.env` 的 `NATIVEPHP_APP_VERSION`）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`v1.2.0-beta.3`、`v1.1.2-dev` 不读，`v2.0`、`v2.0.0` 读）
- install pattern `^TimeScribe-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`。同一 release 里另外的 `-arm64.zip`、`-x64.dmg`、`-x64.zip`、`setup.exe`、`*.blockmap`、`latest*.yml` 不匹配
- **厂商自己的更新器**（settled from source: v1.17.1 的 `routes/console.php`、`app/Console/Commands/{CheckUpdate,CheckCanInstall}.php`、`app/Http/Controllers/UpdaterController.php`；包内 `out/main/index.js` 与 `electron-plugin/src/server/api/autoUpdater.ts`）:
  - 启动时 `startAutoUpdater` 调 `autoUpdater.checkForUpdatesAndNotify()`（`.env` `NATIVEPHP_UPDATER_ENABLED="true"`、provider `github`）；之后调度器每 2 小时跑 `app:check-update`
  - 没改 `autoDownload` / `autoInstallOnAppQuit`，electron-updater 6.8.3 默认都是 `true`（`AppUpdater.js` 第 109、114 行）：**发现新版就自己下载，退出时由 ShipIt 安装**；下完会发一条系统通知（`checkForUpdatesAndNotify`）
  - 应用设置「自动更新」`auto_updater.autoUpdate` 默认 `true`（迁移 `2025_05_23_151159_auto_updater_settings.php`）。开着时调度器每 5 分钟跑 `app:check-can-install`：**没有打开的窗口**（`Window::all()` 为空）且已下载，就自己 `quitAndInstall()`——不等用户退出。关掉这个设置只是不自动 quitAndInstall；下载和退出即装照旧（electron-updater 的默认值不读这个设置）
  - 「更新」窗口里的安装按钮也是 `quitAndInstall()`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；厂商自己的更新器读的也是这一版的 `latest-mac.yml`）

## 按架构 / 按 OS 分轨
- 每版两套 Mac 资产：`-arm64` 和 `-x64`（各有 dmg、zip），没有 universal。arm64 dmg `archs=arm64`（check-bundle）
- `latest-mac.yml`（v1.17.1，2026-10-26 取）列了四个文件，electron-updater 自己按架构挑 zip；没有 `minimumSystemVersion` 字段。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 | 不能 |
| 证据 | 包内 `node_modules/electron-updater` 6.8.3 | v1.17.1 资产有 `TimeScribe-1.17.1-arm64.zip.blockmap`（173515 字节）等 blockmap | `DeltaApplier` 只吃 Sparkle binary delta 和 MyGo；没有消费 blockmap 的机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有 blockmap 机制；全量 arm64 dmg 约 165 MB

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（默认自动下载） | 2026-10-26 运行中一轮：约 37 s 内停放了 `TimeScribe-1.17.1-arm64.zip`（`~/Library/Caches/timescribe-updater/pending/`） | 能，且 duo 让路（见一键安装） |
| 证据 | electron-updater 默认 `autoDownload = true`；`app-update.yml` `updaterCacheDirName: timescribe-updater` | — | `SelfUpdaterStash.parkingSpot` 对任何带 `app-update.yml` 的 app 用 `.electronUpdater(cacheDirectoryName:)`，读 `~/Library/Caches/timescribe-updater/pending/update-info.json` |

- 记录文件与字段: electron-updater 的 `pending/update-info.json`（下载完成并校验 `sha512` 后才写）
- 容器: electron-updater 在 Mac 上下 zip（`TimeScribe-<v>-arm64.zip`），包根是 `TimeScribe.app`
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`；`SelfUpdaterStash` 的归属闸处理

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 1.17.0 起）: `source structured: 1 entries; newest 1.17.1: 1 items, headings []; first items ["🔒 **Dependency and security updates** In"]`
- 1.17.1 的正文只有一个分类标题 `### 🐛 Bug Fixes`（另一个 `## 📦 v1.17.1 – …` 带数字，按设计当作版本标题跳过）；解析器要同一正文里至少 2 个合格标题才保留标题，所以 `headings []` 是按设计不显示，不是被压平，唯一一条在
- 生产解析器另跑了两版正文（临时测试，已删）:
  - 1.17.0: 5 items，headings `["✨ New Features", "🛠 Improvements"]`
  - 1.16.0: 7 items，headings `["✨ New Features", "🛠 Improvements", "🐛 Bug Fixes"]`
  - 条目是「**粗体标题** + 续行说明」，续行并进同一条；开头一句导语和结尾致谢段不进面板
- 跟随 channel: —（beta rule 读的也是稳定版正文）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（stable 副本）**；beta 副本只检测
- 端到端（2026-10-26，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 1.17.0 → `duo install` → 1.17.1，Team `69A277BV6W` ✓
  - 第二轮（运行中）: 它的 electron-updater 约 37 s 内在 `~/Library/Caches/timescribe-updater/pending/` 停放了 `TimeScribe-1.17.1-arm64.zip`；`duo install` 跳过（`own updater already has 1.17.1 staged`）✓；`duo restart` → `quit — its own updater applied 1.17.1` ✓
  - 发现: 每次启动都会留下一个孤儿的内置 PHP 进程 `artisan nightwatch:agent --listen-on=127.0.0.1:8100`（PPID 1），一直打开着 `~/Library/Application Support/timescribe/database/database.sqlite`；见「已知问题」
  - 终态: 1.17.1，未运行
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `TimeScribe.app` + `Applications` 软链。模式 `^TimeScribe-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`，kind `.dmg`
- 嵌套: 只有 `Contents/Frameworks` 下四个 Electron helper（`LSUIElement=true`，随主进程退出）和 `Squirrel.framework` / `Mantle.framework` / `ReactiveObjC.framework`；没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent。包内 PHP 本以为是 app 进程的子进程、不常驻——真机上不是，退出后会留下孤儿进程（见「已知问题」）
- 签名: 1.17.1、1.17.0、1.2.0-beta.3 都是 Team `69A277BV6W`、Notarized Developer ID；0.1.0 同 Team。上一版没换 Team，不存在换 Team 拒装
- 校验: GitHub 资产 `digest`。v1.17.1 dmg `sha256:c7f6a78bb7fb0f4db547997970ffe21de106ed1a73a0abe54603577ad6f8de72`、v1.17.0 dmg `sha256:4df3910fbf73bbf0ad4e166fbf5e41fbca47bd510a625f00aed6b3d0256aa925`，与下载文件的 `shasum -a 256` 相同。`latest-mac.yml` 的 `sha512` 不接（GitHub rule 已带 digest）。2025-06 之前上传的资产没有 `digest`（v1.2.0-beta.3 的 API `digest` 为空）
- **读的是**: 人人可手动下载的 GA
- 阻塞: 无

### 启动副作用（来自源码与包内容，未在真机上观察；真机上见到的孤儿 PHP 进程见「已知问题」）
- 数据目录：Electron `userData` 下（NativePHP 把 Laravel 的 storage 和 SQLite 放在那里）。cask `zap` 写的是 `~/Library/Application Support/timescribe`（小写），具体大小写以真机为准；另有 `~/Library/Caches/timescribe-updater`（更新缓存）及 Electron 常规的 `~/Library/{Caches,HTTPStorages,Preferences}/de.amplussoftware.timescribe*`
- 首启：没完成向导时打开 Welcome 窗口；向导里有「登录时打开」一步，**由用户选**，选了才调 `app.setLoginItemSettings({openAtLogin})`（`WelcomeController::update`）；设置页同样。首启本身不注册登录项
- Dock：菜单栏 app，`showDockIcon(false)`；有窗口时 `Dock::show()`，关窗后 `Dock::hide()`。不改 Dock 的持久配置
- 注册 `timescribe://` URL scheme（Info.plist `CFBundleURLTypes`；`out/main/index.js` 调 `setAsDefaultProtocolClient`）；没有文档类型，不改其他默认 app
- 全局快捷键：迁移里 start/stop/pause/overview/projectPicker 默认都是空，首启不注册
- 「应用活动记录」`general.appActivityTracking` 默认关；开了会每 5 秒 `osascript` 问 System Events 前台进程（会弹自动化授权框），首启不会
- `general.showTimerOnUnlock` 默认开：启动（`Booted`）和解锁时自动弹出菜单栏面板
- Sentry 错误上报：包内 `.env` 带 DSN，首启生成一个 UUID 作为 Sentry 用户 id（`NativeAppServiceProvider::boot`）
- 不写 `~/.claude` / `~/.agents`：`config/nativephp.php` 里的 `.agents` / `.codex` 是打包时**排除**的目录名，不是运行时路径
- 本地 HTTP：PHP 内置服务器只为 Electron 服务（Info.plist ATS 例外仅 `127.0.0.1` / `localhost`）

### 真机前的注意点（2026-10-26 的实测见「一键安装」的端到端）
- **自更新器不等用户退出**：从 1.17.0 启动后会自己下 1.17.1 到 `~/Library/Caches/timescribe-updater/pending/`；若没有打开的窗口，最多 5 分钟后 `app:check-can-install` 自己 `quitAndInstall()`（ShipIt 换包）。想在第二轮看到「停放后 duo 介入」，需要在下载完成后、5 分钟内动手，或保持一个窗口开着（菜单栏面板算不算 `Window::all()` 没核）
- 下载完成会弹系统通知（`checkForUpdatesAndNotify`）
- 首启有 Welcome 向导窗口，别勾「登录时打开」
- 启动和解锁会自动弹菜单栏面板

## 已知问题
- 厂商自更新器默认自动下载、退出即装，且无窗口时自己 quitAndInstall；真机第二轮（2026-10-26）它在 37 s 内停放了 1.17.1，`duo install` 让路、`duo restart` 由它自己换包，没有碰撞
- 每次启动都留下孤儿的内置 PHP 进程 `artisan nightwatch:agent --listen-on=127.0.0.1:8100`（PPID 1），一直打开着 `~/Library/Application Support/timescribe/database/database.sqlite`。它在 app 退出后和厂商自己的更新后都还活着（1.17.0 留下的那个仍在跑旧代码）。真机测试留下的孤儿已用 SIGTERM 结束
- 1.17.1 这类只有一个分类标题的正文，面板不显示标题（解析器的 ≥2 阈值）

## 如何复验
```bash
gh release view v1.17.1 -R WINBIGFOX/TimeScribe --json assets -q '.assets[]|.name+" "+.digest'
gh release download v1.17.1 -R WINBIGFOX/TimeScribe -p 'TimeScribe-1.17.1-arm64.dmg'
gh release download v1.17.0 -R WINBIGFOX/TimeScribe -p 'TimeScribe-1.17.0-arm64.dmg'
gh release download v1.2.0-beta.3 -R WINBIGFOX/TimeScribe -p 'TimeScribe-1.2.0-beta.3-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh TimeScribe-1.17.1-arm64.dmg     # → de.amplussoftware.timescribe, 69A277BV6W, Notarized
swift run --package-path application-test feed-discover TimeScribe-1.17.1-arm64.dmg      # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify TimeScribe-1.17.0-arm64.dmg --expect stable   # → GitHub, UPDATE → 1.17.1
swift run --package-path application-test channel-verify TimeScribe-1.17.1-arm64.dmg --expect stable   # → up to date
swift run --package-path application-test channel-verify TimeScribe-1.2.0-beta.3-arm64.dmg --expect beta   # → GitHub, UPDATE → 1.17.1, download 是 releases 页
```

channel-verify 原文（2026-10-26）:
```
TimeScribe-1.17.0-arm64.dmg --expect stable
  detected channel  → stable
    winning source  GitHub
    latest          1.17.1
    download        https://github.com/WINBIGFOX/TimeScribe/releases/download/v1.17.1/TimeScribe-1.17.1-arm64.dmg
    changelog pane  source structured: 1 entries; newest 1.17.1: 1 items, headings []; first items ["🔒 **Dependency and security updates** In"]
    status          UPDATE → 1.17.1

TimeScribe-1.17.1-arm64.dmg --expect stable
  detected channel  → stable
    winning source  GitHub
    latest          1.17.1
    status          up to date

TimeScribe-1.2.0-beta.3-arm64.dmg --expect beta
  detected channel  → beta
    winning source  GitHub
    latest          1.17.1
    download        https://github.com/WINBIGFOX/TimeScribe/releases
    status          UPDATE → 1.17.1
```

## 建议下一步
1. （已做，2026-10-26）真机两轮一键见「一键安装」；孤儿 PHP 进程（见「已知问题」）是否要处理待定
