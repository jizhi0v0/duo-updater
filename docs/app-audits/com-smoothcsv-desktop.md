# SmoothCSV

## 基本信息
- App: SmoothCSV — 跨平台 CSV 编辑器（Tauri 2 + WebView），付费授权、未授权时定期弹提醒
- Bundle ID: `com.smoothcsv.desktop`（可执行文件 `smoothcsv-app`，另有 `Contents/MacOS/smoothcsv-cli`）
- 仓库: `kohii/smoothcsv3`——只放 release 和 issue，源码不公开（README「This repository is used for issue tracking and release management」）
- Team ID: `46PHP2W2TP`（Developer ID Application: KOHEI ISHIKAWA）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID；hardened runtime
- 观测版本: 3.26.0（tag `v3.26.0`，2026-10-20）；上一版 3.25.1（2026-09-21）；观测日期: 2026-10-22
- 自更新机制: Tauri updater（`tauri-plugin-updater` 2.10.1），见下「自带更新器」
- 分发: GitHub Releases（官网 smoothcsv.com/download 的 mac 链接直接指向 `SmoothCSV_<v>_universal.dmg`）；Homebrew cask `smoothcsv`（没有 `auto_updates`，url 就是同一个 GitHub dmg，另把 `smoothcsv-cli` 链成 `smoothcsv`）；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | （cask 存在，不是生效源） | — | ✓ | — |
| **beta**（3.0.0 前的 beta 副本） | — | — | — | ✓（仅检测，给最新稳定版） | — |

当前生效源: **GitHub**（channel-verify 实测：3.25.1、3.0.0、3.26.0 的 `winning source GitHub`）。`feed-discover` 对 3.25.1 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（都读真包，`check-bundle.sh`）:
  - v3.26.0、v3.25.1、v3.0.0: `com.smoothcsv.desktop`，Team `46PHP2W2TP`，Notarized Developer ID，版本 = tag
  - v3.0.0-beta.11: `com.smoothcsv.desktop`，Team `46PHP2W2TP`，Notarized；`CFBundleShortVersionString` = `3.0.0-beta.11`，`CFBundleVersion` = `20250624.003112`
  - v0.1.0-alpha.5（`SmoothCSV.3_0.1.0-alpha.5_universal.dmg`）: **`com.smoothcsv`**，`CFBundleName` = `SmoothCSV 3`，签名 `Identifier=smoothcsv3-8e3c6ecf2ea6a021`、`TeamIdentifier=not set`、`codesign-verify-exit=1`、spctl `no usable signature`；可执行文件里没有 `releases/latest`
  - Team 没换过（beta.11 到 3.26.0 都是 `46PHP2W2TP`），安装闸不会因 Team 拒旧副本
- 其他轨:
  - `v3.0.0-beta.1` … `beta.11`（2024-11-13 – 2025-06-24）：GitHub 上**没有**标 prerelease，但都早于 v3.0.0（2025-06-30），之后再没有 beta。beta 副本的版本号带 `-beta.N`，`ReleaseChannel.detect` 判成 beta，稳定规则不服务它（加规则前 channel-verify：`detected channel → beta`、`status unknown (no source answered)`）。所以加了一条 `.beta` 规则，读和稳定规则一样的 tag，只检测（理由见下）。加规则后：`detected channel → beta`、`winning source GitHub`、`UPDATE → 3.26.0`
  - `v0.1.0-ahpha.1`、`alpha.2`–`alpha.4`（标了 prerelease）和 `v0.1.0-alpha.5`（没标）：另一个 bundle id `com.smoothcsv`、无签名。**有意不收**：`BundleIDMigration` 要求两个 id 同一 Team（「A migration never crosses Teams」），alpha 没有 Team；一键安装闸也会拒无 Team 的副本。只检测它们要另写一条 `com.smoothcsv` 规则；`com.smoothcsv` 是不是也是旧版 SmoothCSV 2 的 id **没核**（smoothcsv.com/2/ 没给出下载），在这之前不给这个 id 推 3.x
  - Windows / Linux 资产（`*_portable.zip` 是 Windows 便携版：`unzip -l` 里是 `SmoothCSV.exe`、`bin\smoothcsv.exe`、`smoothcsv-portable.flag`；`.msi` / `-setup.exe` / `.deb` / `.rpm` / `.AppImage`）和 Tauri 更新包 `SmoothCSV_universal.app.tar.gz` 都不匹配安装模式
- 版本范围、主机下限: `LSMinimumSystemVersion` 10.13（beta.11 起都一样），universal（x86_64 + arm64）。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），不需要架构门控

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.smoothcsv.desktop` | — | 默认 | `/releases/latest` | ✓ |
| beta（已停）| `com.smoothcsv.desktop` | 共享 | 版本号 `-beta.N` | `ReleaseChannel.detect` | ✓ 仅检测 |

beta 规则只检测、不开一键：非 stable 轨的安装要 channel proof，而这两条轨在 release 上没有任何区别（同样的 tag、同样的资产），能区分的只有已装副本的版本号。beta 副本更新到稳定版之后就由稳定规则服务，一键也就有了。

## 更新检测
- 源: `kohii/smoothcsv3` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.26.0` → `CFBundleShortVersionString` `3.26.0`、`CFBundleVersion` `3.26.0`（beta 时代的 `CFBundleVersion` 是时间戳，不参与比较）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：60 个 tag 读出 48 个（全部稳定版）；读不出的 12 个是上面的 11 个 `v3.0.0-beta.N` 和 `v0.1.0-alpha.5`（另 4 个 alpha 标了 prerelease、不在稳定列表里）。锚定，`v3.0.0-beta.11` 不会被读成 `3.0.0`
- install pattern `^SmoothCSV_[0-9]+(?:\.[0-9]+)+_universal\.dmg$`：只有 universal dmg 一个 mac 安装包；beta 时代的 `SmoothCSV_3.0.0-beta.11_universal.dmg` 也不匹配
- **自带更新器**（证据：3.26.0 可执行文件的 strings；插件行为来自官方源码 `tauri-apps/plugins-workspace` tag `updater-v2.10.1` 的 `plugins/updater/src/{updater,commands}.rs`）:
  - 是 Tauri updater：`tauri-plugin-updater/2.10.1`，App 自己的 `smoothcsv::features::updater::{manager,status}`，前端命令 `download_update`、`request_install_update`、`get_update_state`
  - 端点: `https://api.smoothcsv.com/api/updates` 和 `https://github.com/kohii/smoothcsv3/releases/latest/download/latest.json`。前者实测（2026-10-22）`301` 到后者。`latest.json` 的 `darwin-*` 都指向 `releases/latest/download/SmoothCSV_universal.app.tar.gz`，`version` 3.26.0。和本规则读的是同一个 `/releases/latest`
  - 会不会暂存: 插件的 `download` 返回 `Vec<u8>`，命令层存成内存资源 `DownloadedBytes`；`install_inner`（macOS）把 tar.gz 解到临时目录 `tauri_updated_app*`，把当前 app 挪到 `tauri_current_app*`，再 rename 新 app 到原路径（没权限时用 AppleScript `with administrator privileges`）。**插件不在磁盘上停放下载**。App 自己的 manager 是闭源的；2026-10-22 真机运行 3.25.1 约 20 s，前后 diff 没看到写盘的更新包（`$TMPDIR/com.smoothcsv.desktop` 只有 `WebKit/`）。没在 App 里点下载，所以「点了下载之后」会不会写盘仍没核
  - 设置: v3.13.0 起 `Settings › Application › Update` 可设成 Manual（release notes）；默认模式是只检查还是自动下载**没核**
- 已安装 3.0.0-beta.11 的可执行文件里也有 `releases/latest`（`check-bundle.sh` 的 `exe-references`），beta 副本自己的更新器同样走稳定版

## 按架构 / 按 OS 分轨
- 一个 universal dmg（x86_64 + arm64）；`LSMinimumSystemVersion` 10.13；`latest.json` 的 darwin-aarch64 / darwin-x86_64 指向同一个 universal 包，不分轨

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Tauri 插件 macOS 只解整包 tar.gz（`install_inner`） | 2026-10-22 的 `latest.json`：每个平台一个 `url` + `signature`，没有 patch 字段；release 资产里没有 delta | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 插件不会（内存）；App 自己会不会写盘没完全核 | 无（2026-10-22 真机，没在 App 里点下载） | 不能（内存里的字节拿不到） |
| 证据 | `commands.rs` `struct DownloadedBytes(pub Vec<u8>)`；`updater.rs` `download` → `Result<Vec<u8>>` | — | `SelfUpdaterStash` 读磁盘布局，这里没有 |

- 和我们抢的方式: 运行中的旧进程如果已经下载了某个版本 X（在内存里），duo 装上更新的 Y 之后用户再点 App 里的「安装更新」，插件会把磁盘上的 Y 挪走、换成 X——**降级**。插件安装时不比版本，只换 `extract_path`（源码如上）。这是推断，没真机复现，见「一键安装」的第二轮步骤

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 3.25.1 起）: `source structured: 1 entries; newest 3.26.0: 22 items, headings ["Improvements", "Bug Fixes"]; first items ["**File name in the window title** - The ", "**Trim Whitespace** - **Edit › Transform", "**SQL in the column menu filter** - The "]`
- **面板丢了「New Features」整节。** 厂商每个小版本的正文都是 `## New Features` 下若干 `### 功能名` + 段落 + 截图，然后 `## Improvements` / `## Bug Fixes` 的列表、最后 `## Download`。解析器的严格列表那一轮已经拿到列表项，就不再收段落（`GitHubMarkdownParser.parse` 的三轮设计），所以 New Features 的段落全丢，连标题也没留下。用生产解析器跑最近 4 个版本的正文（临时测试，已删）：
  - 3.26.0: 22 项，headings Improvements / Bug Fixes；`### Hot Exit 💾` 丢
  - 3.25.0: 37 项；`Copy with Options`、`Fill Blanks Down`、`See the Spaces You Can't See` 三个新功能丢
  - 3.24.0: 30 项；六个新功能丢
  - 3.25.1（补丁版，没有 New Features）: 12 项，完整
- 标题保留: `Improvements`、`Bug Fixes` 作为 heading 保留，没有被压平进 items；`## Download` 段只有一个链接，没出现在 items 里
- 嵌套列表被摊平: 3.26.0 的「Fixed wrong results in filter queries:」下面 4 条子项成了与它并列的 4 条
- 跟随 channel: —（beta 规则读的也是稳定版正文）
- Recipe 状态: 不需要 recipe；要保留 New Features 得改通用解析器（引擎改动），没做

## 一键安装
- 状态: **支持**（稳定规则）；beta 规则仅检测
- 端到端（2026-10-22，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 3.25.1 → `duo check` `3.25.1 → 3.26.0 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 3.26.0、可执行文件 inode 变、`TeamIdentifier=46PHP2W2TP`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 3.26.0 包相同
  - 第二轮（运行中）: 启动 3.25.1（一个窗口，没有未存文档），`duo install` 后提示 `Still running the old code`；`duo restart SmoothCSV` 后新进程起来，之后 10 s 磁盘一直是 3.26.0、签名有效
  - 「内存里有一个比 latest 旧的版本、用户再点 App 内安装」那个降级场景没跑（要本地代理改写两个更新端点），仍是推断
- 格式: dmg（UDZO，GUID 分区），根目录 `SmoothCSV.app` + `Applications` 软链 + `.VolumeIcon.icns`
- 嵌套 / 常驻组件: 无。`Contents/` 下只有 `MacOS/{smoothcsv-app,smoothcsv-cli}`、`Resources/icon.icns`、Info.plist、签名；没有 LoginItems / Helpers / XPC / LaunchAgent；strings 里没有 `SMAppService`、`LaunchAgents`、`LoginItems`
- 签名: 3.25.1、3.26.0 都是 `46PHP2W2TP`、Notarized Developer ID
- 校验: GitHub 资产 `digest`。v3.26.0 `sha256:75f8428947c86c91a70c19eed001f8bbd71a84c2a605af77fcba69bf09ea6681`、v3.25.1 `sha256:88024528426c8426e45ade15233c1e1cd28e77cd75067318a833108b89ff9d76`，`gh release download` 下来的 dmg `shasum -a 256` 都相同，大小 35811363 / 34876703 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；官网下载页和 Tauri 更新器都指向它）
- 启动副作用（来源已标；2026-10-22 真机核对的已注明）:
  - 首启: 未授权时会弹授权提醒（3.25.1 release notes「The reminder now appears every 3 days」）；`verify_license_key` 命令在 strings 里。真机这次没看到授权提醒（只有一个主窗口），是不是模态框仍没核
  - 退出: 3.26.0 起 Hot Exit 默认开，退出不问保存（3.26.0 release notes）；3.25.x 从外部退出（Dock、AppleScript）有未存改动时会问（3.25.0 release notes）。3.25.1 运行时别留未存文档
  - 文件关联: Info.plist 声明 csv / tsv（`LSHandlerRank Default`）和 `smoothcsv://` URL scheme（deep-link 插件）。strings 里没有 `LSSetDefault*`，没看到主动抢默认 app 的代码
  - CLI: 命令面板「Install 'smoothcsv' command in PATH」才装，写 `/usr/local/bin/smoothcsv`，可能弹管理员框（strings 里 `/usr/local/bin/smoothcsv`、`with administrator privileges`；`docs/cli.md`）。启动时不做。真机别点它
  - 不写 `~/.claude` / `~/.agents`（strings 里没有这两个路径）；数据在 `~/Library/Application Support/com.smoothcsv.desktop` 等（Homebrew cask 的 zap 列表）。真机首启建了 `~/Library/{Application Support,Caches,Logs,WebKit}/com.smoothcsv.desktop`，没有 `/usr/local/bin/smoothcsv`
  - 自带更新器会在启动后检查（默认模式没核），插件安装时可能弹管理员框（app 所在目录没写权限时）
- 第二轮怎么造「内存里有一个比 latest 旧的版本」（没试过）: 装 3.25.0 并启动，让它的更新器拿到 3.25.1。两个端点都指向 `/releases/latest`（现在是 3.26.0），所以要把 `api.smoothcsv.com/api/updates` 和 GitHub 的 `latest.json` 映射到一份本地 JSON：内容取 v3.25.1 的 `latest.json`（它的 `signature` 是 3.25.1 tar.gz 的签名），把 `darwin-*` 的 `url` 改成 `releases/download/v3.25.1/SmoothCSV_universal.app.tar.gz`（原文是 `releases/latest/download/…`，会拿到 3.26.0 的包而签名对不上）。在 App 里下载但不装 → `duo install` 装 3.26.0 → 再在 App 里点安装 → 看磁盘是不是回到 3.25.1

## 已知问题
- Changelog 面板没有 New Features 段（见上）；改要动 `GitHubMarkdownParser`
- 运行中的旧进程里有已下载的更新时，duo 装完之后用户再从 App 里装，可能降级（推断，见「已停放整包」）
- `com.smoothcsv`（2024 年的 0.1.0 alpha，无签名）不检测，见覆盖清单

## 如何复验
```bash
gh release view v3.26.0 -R kohii/smoothcsv3 --json assets -q '.assets[]|.name+" "+.digest'
gh release download v3.26.0 -R kohii/smoothcsv3 -p 'SmoothCSV_3.26.0_universal.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh SmoothCSV_3.26.0_universal.dmg   # → com.smoothcsv.desktop, 46PHP2W2TP, Notarized
swift run --package-path application-test feed-discover SmoothCSV_3.25.1_universal.dmg      # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify SmoothCSV_3.25.1_universal.dmg --expect stable       # → GitHub, UPDATE → 3.26.0
swift run --package-path application-test channel-verify SmoothCSV_3.26.0_universal.dmg --expect stable       # → up to date
swift run --package-path application-test channel-verify SmoothCSV_3.0.0-beta.11_universal.dmg --expect beta  # → GitHub, UPDATE → 3.26.0
curl -sS -D - -o /dev/null https://api.smoothcsv.com/api/updates                            # → 301 to releases/latest/download/latest.json
```

## 建议下一步
1. 要不要让 `GitHubMarkdownParser` 在有列表时也保留 `###` 小节的段落（SmoothCSV 每个小版本的重点都在那里）——通用解析器改动，要 owner 定
