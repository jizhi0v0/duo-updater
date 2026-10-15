# MC Download Manager

## 基本信息
- App: MC Download Manager — 多连接下载管理器，带 Safari / Chrome / Firefox 扩展，视频下载走内置 yt-dlp；英文、土耳其文
- Bundle ID: `com.mesutcevik.mcdownloadmanager`（1.0.0–1.3.0 五个真包相同）
- 仓库: `mstcvk/mc-download-manager`（默认分支 `main`）
- Team ID: `D547CSD5CA`（Developer ID + 公证，自 1.1.0 起）。1.0.0 是 ad-hoc 签名（`TeamIdentifier=not set`）
- 观测版本: 1.3.0（`CFBundleVersion` 5）；观测日期: 2026-10-15
- 自更新机制: 自研检查，不替换 bundle。`App/Sources/DownloadManager/Services/UpdateChecker.swift` 读
  `api.github.com/repos/mstcvk/mc-download-manager/releases/latest`，去掉 tag 的 `v` 比较，有新版就弹窗，「Download Update」
  把 dmg 当普通下载任务交给自己的下载器，用户自己装
- 分发: GitHub Releases；厂商自己的 tap `mstcvk/homebrew-tap` 有 cask `mc-download-manager`（url 指向同一个 GitHub dmg，
  livecheck `github_latest`，不设 `auto_updates`）。官方 homebrew/cask 里没有。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。从厂商 tap（`brew install --cask mstcvk/tap/mc-download-manager`）装的拷贝
也由 GitHub 规则应答：`HomebrewCaskSource` 只查官方目录 `formulae.brew.sh/api/cask.json`（`HomebrewCaskCatalog.swift`），
那里没有这个 cask（`/api/cask/mc-download-manager.json` 2026-10-15 返回 404），候选为空就返回 nil，不会走到 Caskroom 判定。

## Channel 详情

只有一条轨，settled from source: `UpdateChecker.swift` on `main` 只读 `/releases/latest`（GitHub 计算时排除 pre-release），
没有切渠道的设置。截至 2026-10-15 共 5 个 release（v1.0.0–v1.3.0），全部非 pre-release。

## 更新检测
- 源: `mstcvk/mc-download-manager` GitHub Releases
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`（锚定）。tag `vX.Y.Z` 去 `v` 等于 `CFBundleShortVersionString`，唯一例外是 1.0.0 的
  bundle 写 `1.0`；`VersionComparator` 下 `1.0` < `1.3.0`，channel-verify 实测 1.0 → UPDATE 1.3.0
- 注意: `CFBundleVersion` 是递增构建号（1.0.0=1 … 1.3.0=5），不参与比较

## 按架构 / 按 OS 分轨
- 每个 release 一个通用 dmg `MC-Download-Manager-<v>.dmg`（`lipo` = x86_64 arm64）
- `LSMinimumSystemVersion` = `13.0`（五个版本相同；cask 写 `depends_on macos: :ventura`）；release 不声明上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `UpdateChecker.swift` 只下整个 dmg | release 只有一个 dmg | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-15，channel-verify `changelog pane`，从 1.2.0 起）: `source structured: 1 entries; newest 1.3.0:
  6 items, headings []; first items ["If MC Download Manager is not running wh", "Works in Safari, Chrome, Brave, Edge and",
  "Only file types the app captures trigger"]`
- 分节: 厂商用加粗段落（`**Updating the extensions**`）而不是 Markdown 标题分节，所以 `headings []`，条目按出现顺序平铺
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（1.1.0 及以后的安装）**；1.0.0 的安装只检测
- 格式: dmg（`^MC-Download-Manager-[0-9][0-9.]*\.dmg$`，kind `.dmg`）
- 嵌套: `Contents/PlugIns/MC Download Manager Extension.appex`（Safari web extension）；`Contents/Helpers/` 下
  `ffmpeg`、`yt-dlp`、`mcdm-native-host` 三个可执行文件（不是 `.app`）。`mcdm-native-host` 由浏览器按需拉起（native
  messaging），不是常驻进程；没有 LoginItems、LaunchAgent
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256` 前 16 位: 1.0.0 `0a175169b35885c2`、1.1.0
  `7d5746937890cbe8`、1.1.1 `004b1aa4811fcce2`、1.2.0 `013de8819b183f8c`、1.3.0 `da5c92884b53d8aa`，都与各自 `digest` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest` 的附件，也是 app 自己的检查读的那个）
- 端到端（2026-10-15，不运行）: 1.2.0 → `duo check` `1.2.0 → 1.3.0 [GitHub, in-place]` → `duo install --yes --json`
  → `outcome: installed`，15.8 s，下载 108107021 字节。结果: 版本 1.3.0、可执行文件 inode 变了、Team `D547CSD5CA`、
  `codesign --verify --deep --strict` = 0、`spctl` = Notarized Developer ID、`diff -r` 与 vendor 的 1.3.0 bundle 完全相同
- 端到端（2026-10-15，1.0 ad-hoc）: `duo check` `1.0 → 1.3.0` → `duo install` → `failed: Could not read a Team Identifier
  from the installed app.`（14.2 s）。磁盘上 1.0 原样（版本、inode 不变）。这是 Team 闸的预期拒绝
- 端到端（2026-10-15，运行中）: 启动 1.2.0 → `duo install` 14.5 s，提示 "Still running the old code" → `duo restart` 报
  `still running — likely a save prompt, left it alone`：全新安装首次启动会弹「Welcome to MC Download Manager」设置 sheet
  （模态），挡住了退出。这是首启状态，走完设置的用户不会有。手动结束旧进程后启动 1.3.0，`lsof` 看到进程跑的是磁盘上的新文件。
  app 自己的更新器不替换 bundle，不存在暂存碰撞
- 启动副作用: 1.3.0 启动时往已装的 Chromium 系浏览器的 `NativeMessagingHosts/` 写 `com.mesutcevik.mcdownloadmanager.json`
  （release notes 也这么说）；不登记登录项（前后 `sfltool dumpbtm` 无该 app 条目）
- 阻塞: 1.0.0 的安装要手动更新一次

## 已知问题
- **1.0.0 → 新版一键被拒（设计如此）。** ad-hoc → Developer ID 没有 Team ID 可比。行上仍提示有更新。
- **厂商 tap 装的拷贝一键后 Caskroom 不跟着更新。** 这类拷贝走 GitHub 规则原地替换，brew 的 Caskroom 仍记旧版本，
  `brew outdated` 会继续报它，下次 `brew upgrade` 重装同一版本。所有只在第三方 tap 的 cask 都是这样，不是这条规则特有。
- **首启设置 sheet 挡 `duo restart`。** 只影响刚装、还没走完首启设置的拷贝；`duo` 不强退，留给用户。

## 建议下一步
1. 若 MC 进了官方 homebrew/cask，重新审计：届时 brew 装的拷贝会改由 `HomebrewCaskSource` 应答。

## 如何复验
```
.claude/skills/coverage-discovery/scripts/check-bundle.sh <MC-Download-Manager-1.3.0.dmg>        # → id、Team D547CSD5CA、无 SUFeedURL
swift run --package-path application-test channel-verify <MC-Download-Manager-1.0.0.dmg>        # → stable，GitHub，UPDATE → 1.3.0
swift run --package-path application-test channel-verify <MC-Download-Manager-1.2.0.dmg>        # → UPDATE → 1.3.0
swift run --package-path application-test channel-verify <MC-Download-Manager-1.3.0.dmg>        # → up to date
```
