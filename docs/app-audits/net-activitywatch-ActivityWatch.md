# ActivityWatch

## 基本信息
- App: ActivityWatch — 本地时间追踪（`ActivityWatch/activitywatch`，MPL-2.0）。同一个 release 里发两个 macOS 版本：**classic**（Python/Qt，Homebrew cask 装的就是它）和 **Tauri 重写版**（发布说明里标 experimental）
- Bundle ID: `net.activitywatch.ActivityWatch`（两个版本共用；版本号、Team 也相同）
- Team ID: `XM9GC3SUL2`（Developer ID Application: Erik Bjareholt）；两个版本的 `codesign --verify --deep --strict` 都通过；spctl: Notarized Developer ID
- 观测版本: 0.14.1（tag `v0.14.1`）classic `activitywatch-v0.14.1-macos-arm64.dmg`（64437220 字节）与 Tauri `activitywatch-tauri-v0.14.1-macos-arm64.dmg`（52789017 字节）；prerelease 0.14.0b8 两份同名资产；观测于 vmpal「macOS VM 1」（macOS 27.2），2026-11-01
- 自更新机制: 两个真包里都没有 `app-update.yml`、没有 `Sparkle.framework`。classic 的可执行文件是 `aw-qt`（PyInstaller 打包）；Tauri 版的可执行文件 `aw-tauri` 里编进了 `tauri-plugin-updater 2.11.0`，它的 Web UI CSP 也点名 `api.github.com/repos/ActivityWatch/activitywatch/releases/latest`
- 分发: GitHub Releases（classic 与 Tauri 各一套 dmg / zip / Linux 包）；Homebrew cask `activitywatch` 装 classic 的 arm64 dmg（0.14.1，非 auto_updates）；Mac App Store 无（`itunes.apple.com/lookup?bundleId=net.activitywatch.ActivityWatch` resultCount 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable — classic** | — | —（cask 装 classic） | — | ✓ 一键 classic arm64 dmg | — |
| **stable — Tauri**   | — | — | — | ✓ 只检测（Tauri 版发布说明标 experimental） | — |

当前生效源: **GitHub**（`duo check` 实测；`duo verify --only net.activitywatch` 的 2 条 GitHub rule 与 changelog 都 ✓）

## 覆盖清单
- 真包（都读自 dmg）:
  - classic 0.14.1 arm64: id / Team 同上，两个版本键都是 0.14.1，**`CFBundleExecutable = MacOS/aw-qt`（一个路径，不是文件名）**，`LSUIElement` 未设，包里没有 updater
  - Tauri 0.14.1 arm64: 同 id / 同版本，`CFBundleExecutable = aw-tauri`，`LSUIElement = true`，可执行文件里编进了 `tauri-plugin-updater`
  - prerelease 0.14.0b8：两份都同 id / 同 Team，版本键原样带 `b8`
- 嵌套: classic 是可执行文件 + Python.framework + PyQt6 的打包；Tauri 版是单个 `aw-tauri` 加资源。两边都没有 LoginItems / LaunchAgent / root helper
- 其他轨: prerelease tag 是 `v0.14.0b8` 形状（`b<N>` 后缀，没有点号），最新 75 个 release 里 48 个 prerelease；它们都早于当前 stable
- 主机下限: 只取 arm64 资产；`LSMinimumSystemVersion` 12.0（Tauri）/ 未设（classic）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.activitywatch.ActivityWatch` | 两个 edition 共享 | 版本纯数字 | `/releases/latest` | ✓ |
| beta    | 同 id | 共享 | 版本 `0.14.0b8` 形状 | 没有 beta rule：`b<N>` 后缀不进 stable tag pattern | —（prerelease 副本按 stable 毕业，安全） |

**两个 edition 怎么区分（`installedExecutableMarker`）:**
- Tauri 的主可执行文件 `aw-tauri` 里含 `tauri`（真包 strings 命中 237 次），classic 的 `aw-qt` 里 0 次；标了 marker 的 rule 只回答 Tauri 副本，未标的 classic rule 回答其余副本
- Tauri rule 没有 install spec：**只检测**。VM 里拿 0.14.0b8 的 Tauri 副本实测 `duo check` → `update 0.14.1`，route `manual`（不给一键）
- **没有 `OneClickGate`**：classic 的 `CFBundleExecutable` 是 `MacOS/aw-qt`（带路径），所有 executable-marker 闸都会把它读成 unknown 并 fail closed；先加闸时实测 classic 副本 route 变成 `manual`，去掉后恢复 `in-place`。Tauri 副本由 marker rule 本身挡住

## 更新检测
- 源: `ActivityWatch/activitywatch` GitHub Releases，`/releases/latest`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（`v0.14.0b8` 不匹配）
- `installAssetPattern`（classic）`^activitywatch-v[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$`；Tauri 资产名以 `activitywatch-tauri-v…` 开头，不会误配
- `duo check`（2026-11-01，vmpal）: classic 0.14.0b8 → `update 0.14.1`，route `in-place`；Tauri 0.14.0b8 → `update 0.14.1`，route `manual`；0.14.1 两个副本都 up-to-date

## 按架构 / 按 OS 分轨
- arm64 / x86_64 各一份；rule 只装 arm64。`LSMinimumSystemVersion` 12.0（Tauri）；classic 没设，按 macOS 12 的部署目标

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | Tauri 版有（tauri-plugin-updater 的 `.app.tar.gz` + `.sig`） | 有 `.app.tar.gz` 与 `.sig` | 不需要 |
| 证据 | `aw-tauri` 里编进 `tauri-plugin-updater 2.11.0`；release 资产有 tauri 的 tar.gz / sig | v0.14.1 资产列表 | 我们下载整包 dmg，用 GitHub `digest` 校验 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | classic 不会；Tauri 版不落盘（tauri updater 自己管理） | 无 | — |
| 证据 | 两个真包都没有 `app-update.yml` / Sparkle；Tauri 版更新走 `.app.tar.gz` | 2026-11-01 两轮 | 没有可拿的 |

## Changelog
- 来源: GitHub release 正文（`.gitHubReleases`，`tagPattern` 同 stable）
- 正文开头是 `# Installation` / `# Downloads`（classic 与 Tauri 的下载表）再 `# Support ActivityWatch` / `# Contributors`，真正的变更在 `# Changelog` → `## 📦 activitywatch` → `### ✨ Features (3)` / `### 🐛 Fixes (7)`
- `skipSections` 去掉 Installation / Downloads / Classic distribution / Tauri distribution（实验性说明那行全文）/ Support ActivityWatch / Contributors / Changelog；面板保留 `📦 activitywatch` 与 `✨ Features` / `🐛 Fixes` 标题，条目是 issue 链接
- 跟随 channel: 只有 stable

## 一键安装
- 状态: 支持（仅 classic；arm64 dmg，Team 闸 + GitHub digest）
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: classic 0.14.0b8 → `duo install ActivityWatch --yes` → `outcome installed`，`bytesDownloaded 64437220`；盘上 0.14.1，Team XM9GC3SUL2，codesign / spctl 通过
  - 第二轮（运行中）: classic 0.14.0b8 从 GUI 启动（pid 89735）→ `duo install` 装成 0.14.1 → `duo restart ActivityWatch` 成功（pid 89735 → 89812，输出 "ActivityWatch restarted"）
  - Tauri 副本（0.14.0b8）: `duo check` 报 `update 0.14.1`、route `manual`，没有一键；把 classic 0.14.1 换回去后 up-to-date
  - 终态: classic 0.14.1，`duo check` 报 up-to-date
- 校验: classic 资产 `sha256:225916c1e641151638a062c796743ea21ba29c5d1bc162d84fc5591473d822db`；Tauri 资产 `sha256:0bfd055cd369681d796f86049b08870239fcd10833702109dee8343b0b6db1c0`

## 已知问题
- Tauri 版只检测：发布说明自己标 experimental，Homebrew cask 装的是 classic；等厂商把它升为正式分发再考虑给一键
- classic 的 `CFBundleExecutable` 写成 `MacOS/aw-qt`（路径），任何按可执行文件内容的闸都读不到它；这是包里的既有形状，不是我们改的
- 运行中的 `duo restart` 要求副本从 GUI 会话启动：agent shell 里 `open` 的副本没有窗口，优雅退出不落地，restart 会卡在退出上。VM 里的运行轮用 Finder 启动的副本跑通

## 如何复验
```bash
curl -L -o /tmp/aw.dmg https://github.com/ActivityWatch/activitywatch/releases/download/v0.14.1/activitywatch-v0.14.1-macos-arm64.dmg
hdiutil attach -readonly /tmp/aw.dmg && codesign -dv --verbose=4 /Volumes/ActivityWatch/ActivityWatch.app
duo verify --only net.activitywatch
duo check --all --json | grep activitywatch
duo install ActivityWatch --yes --json
```
