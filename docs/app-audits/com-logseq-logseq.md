# Logseq

## 基本信息
- App: Logseq 2.x — 开源大纲笔记，2.0 起是「DB 版」（数据库图谱）；Electron
- Bundle ID: `com.logseq.logseq`
- 仓库: `logseq/logseq`
- Team ID: `K378MFWK59`（Developer ID Application: Logseq Inc.）；`codesign --verify --deep --strict` 通过；`spctl` Notarized Developer ID；hardened runtime
- 观测版本: 2.0.2（tag `2.0.2`，资产 `Logseq-darwin-arm64-2.0.2.dmg`）；上一版 2.0.1；观测日期: 2026-10-22
- 自更新机制: **electron-updater 6.8.3**，`app-update.yml` = `provider: github`、`owner: logseq`、`repo: logseq`、`updaterCacheDirName: logseq-updater`。源码 `src/electron/electron/updater.cljs`（tag 2.0.2）：`channel` 设成 `latest-arm64`（读 `latest-arm64-mac.yml`），`allowDowngrade false`，`autoInstallOnAppQuit false`；启动时（`:auto-update` 设置不是 false，默认开）`autoDownload true` 去检查并**下载**，装要用户点（`quitAndInstall`）
- 分发: GitHub Releases；Homebrew cask `logseq`（2.0.2，`auto_updates true`，url 就是 GitHub 的 arm64 dmg）。Mac App Store 没有 Mac 版：`itunes.apple.com/lookup?bundleId=com.logseq.logseq` 只回一个 iOS app（0.10.9，`supportedDevices` 里没有 Mac）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | cask `logseq`（没单独核走 brew 的副本） | — | ✓ | — |
| **nightly** | — | — | — | 不单独接（见下） | — |

当前生效源: **GitHub**（channel-verify 实测，2.0.1 → 2.0.2）。`feed-discover` 对 2.0.1 dmg: `review electronProviderNeedsConstruction`，即 `ElectronManifestSource` 不会替 `provider: github` 拼地址，必须写 GitHub rule。

## 覆盖清单
- **bundle id**
  - `com.logseq.logseq`：2.0.1、2.0.2、nightly 三个真包一致，规则覆盖。
  - `com.electron.logseq`：0.10.x 及更早（0.10.15 真包：`com.electron.logseq`，Team `3K44EUN829`，没有 `app-update.yml`）。**有意不收，不加 `BundleIDMigration`**：厂商把产品拆成两个（官方说明 https://logseq.io/p/e3YDyX5AYr ：文件图谱版改名 Logseq OG、搬到 `logseq/og`，只修安全和升级依赖；DB 版留在 `logseq/logseq`，两个可以并装；Markdown 用户「不会被强制迁移」）。把 0.10.x 的副本换成 2.x 等于替用户把文件图谱版换成 DB 版，不是升级。而且 Team 也换了，就算迁移，安装闸也会拒。channel-verify 对 0.10.15：`winning source <none>`、`status unknown`。Logseq OG（cask `logseq-og`，`Logseq-OG.app`，cask zap 写的是 `com.logseq.logseq-og`）要单独接入，不在这次范围内
  - iOS 版也用 `com.logseq.logseq`（App Store 0.10.9）。苹果芯片 Mac 上装的 iPhone/iPad 版是 App Store 副本，`GitHubReleasesSource` 在 `app.isMASApp` 时直接跳过（`GitHubReleasesSource.swift`「App Store copy, the store owns its updates」）。按代码判断，没有拿真实的 wrapped 副本验证（未验证）
- **其他轨**：rolling 的 `nightly` prerelease（见 Channel 详情）
- **版本范围**：2.0.1、2.0.2 都是 Team `K378MFWK59`，`LSMinimumSystemVersion` 12.0
- **主机下限**：DuoUpdater 只出 arm64，`LSMinimumSystemVersion` 12.0 低于我们的下限，不需要 `hostRequirement`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.logseq.logseq` | — | 默认 | `/releases/latest` | ✓ |
| nightly | `com.logseq.logseq` | 共享 | 只有 `app.asar` 里的 `VERSION` 文件（`2.0.2-alpha+nightly.20261021`） | 不门控 | 按 stable 处理 |

- nightly 是 tag `nightly` 的 prerelease，资产名 `Logseq-darwin-arm64-2.0.2-alpha+nightly.20261021.dmg`。真包里 `CFBundleShortVersionString`、`CFBundleVersion`、`package.json` 的 `version` 都是 `2.0.2`，和 stable 完全一样；channel-verify 的 `inferred stable`。
- **不门控的理由**：nightly 副本自己的 electron-updater 也读 `/releases/latest`。它的 `app.getVersion()` 是 `2.0.2`，没有 prerelease 段，所以 `allowPrerelease` 是 false（`AppUpdater.js`：`allowPrerelease = hasPrereleaseComponents(currentVersion)`）；`GitHubProvider.getLatestTagName` 取 `releases/latest`。下一个 stable 出来时，厂商自己的更新器也会把 nightly 用户带到 stable，我们给的是同一个版本。tag 是同版本号时（nightly 2.0.2 对 stable 2.0.2），两边都判为已是最新。
- 版本 pattern 不会读到 `nightly` 这个 tag，安装 pattern 也读不到 nightly 的资产名（多了 `-alpha+nightly…`）。

## 更新检测
- 源: `logseq/logseq` GitHub Releases，`/releases/latest`
- 版本: tag `2.0.2` → `CFBundleShortVersionString` `2.0.2`、`CFBundleVersion` `2.0.2`
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`。154 个 release 里有 146 个不是 prerelease，读出 143 个，读不出的 3 个都不是这个桌面 app：
  - `mobile-0.1`：「Android Alpha Testing」，只有 `logseq-android-0.1.apk`
  - `0.0.1-100`：「Backend jar」，只有 `logseq.jar`
  - `v0.0.1`：「Publishing」，只有 `logseq_publishing.tar.gz`

  所以不扩 pattern。`3.0.0`、`2.1` 能读；`2.0.3-rc.1`、`2.0.3-beta`、`v2.0.3`、`nightly` 读不出（锚定）
- install pattern `^Logseq-darwin-arm64-[0-9]+(?:\.[0-9]+)+\.dmg$`：能读 `Logseq-darwin-arm64-2.0.2.dmg`；读不到 x64 dmg、zip、`.blockmap`、nightly dmg
- 「0.3.9 没有能匹配的资产」：0.3.x 及更早的资产都是小写的 `logseq-darwin-…`。这是 0.x 的 `com.electron.logseq` 时代，本规则不服务这些副本；规则只读 `/releases/latest`，不影响

## 按架构 / 按 OS 分轨
- 有 arm64 和 x64 两套 dmg/zip，没有 universal。DuoUpdater 只跑在 arm64 上，所以选 arm64
- `LSMinimumSystemVersion` 12.0（2.0.1、2.0.2 相同）；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 `.zip.blockmap` / `.dmg.blockmap` | ✗ |
| 证据 | 随包的 `electron-updater/out/MacUpdater.js` 有 `differentialDownloadInstaller`；没有上一份 `update.zip` 缓存时退回整包 | 2.0.2 资产列表 | `DeltaApplier` 只吃 Sparkle / MyGo 的补丁；blockmap 是按块拼下载，不是补丁 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 真机（2026-10-22）：2.0.1 启动 21 s 后停放 `Logseq-darwin-arm64-2.0.2.zip`（171440323 B）+ `update-info.json` | 能：`duo install --json` 给 `bytesDownloaded: 0`，直接用了这份 zip |
| 证据 | 启动时 `autoDownload true` → `~/Library/Caches/logseq-updater/pending/` + `update-info.json`（目录名来自 `app-update.yml` 的 `updaterCacheDirName`），停放的是 arm64 **zip**（`latest-arm64-mac.yml` 的 `path`）。`autoInstallOnAppQuit false`：`MacUpdater.js` 只在 `quitAndInstall` 时才把 zip 交给 Squirrel，所以退出时不会自己装 | — | `SelfUpdaterStash` 从归档本身判断容器格式，不看路线是 dmg（`LocalStagedInstaller.kind` 的注释） |

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22 channel-verify，从 2.0.1 起）: `source structured: 1 entries; newest 2.0.2: 7 items, headings ["Features", "Thanks", "Enhancements"]; first items ["Gallery cards can now use URL properties", "Added a "Clear heading" slash command.", "Improved video embeds, with resizable de"]`
- 标题保留，没有被压平。**但 `## Fixed issues` 整节没了**：这一节是 13 条编号列表（`1. **Preserve unsaved edits:** …`），解析器只在 `-`/`*`/`+` 圆点那一遍什么都没读到时，才读编号列表（`GitHubMarkdownParser` 文件头注释，「also accepting … numbered lists」那一遍是兜底）。这是通用解析器的取舍，这次不改；面板上是 Features 3 条 + Thanks 2 条 + Enhancements 2 条
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（arm64 dmg）
- 格式: dmg（`hdiutil imageinfo`：UDIF ULFO / lzfse，GUID），根目录 `Logseq.app` + `Applications` 软链
- 签名: 2.0.1、2.0.2 都是 `TeamIdentifier=K378MFWK59`，`spctl` `accepted / Notarized Developer ID`。0.10.x（`com.electron.logseq`）是 Team `3K44EUN829`，本来就不归这条规则
- 嵌套: 只有 `Contents/Frameworks` 下 4 个 Electron Helper（`LSUIElement`，随主进程起落），没有 `Contents/Library/LoginItems`、`Helpers`、LaunchAgent plist
- 校验: GitHub 资产 `digest`。2.0.2 dmg `sha256:b9a16b6ddef1659aa3c2301ce37a0336377644bbf1016051e3d19d1a66776314`，2.0.1 dmg `sha256:b76af25384f8aaa0ba322f8b5523aea712d9750d9f3e79cac55dc783796439cd`，下载的包 `shasum -a 256` 都相同，大小等于 Content-Length
- **读的是**: 人人可手动下载的 GA（`/releases/latest`），也是 app 自己更新器读的那一个
- 端到端（2026-10-22，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 2.0.1 → `duo check` `2.0.1 → 2.0.2 [GitHub, in-place]` → `duo install` `verifyingSignature extracting verifyingCodeSignature installing done installed.` → 2.0.2、可执行文件 inode 变、`TeamIdentifier=K378MFWK59`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 2.0.2 包相同
  - 第二轮（运行中）: 启动 2.0.1，等 electron-updater 停放 2.0.2（见上表）后 `duo install --json` → `outcome installed`、`bytesDownloaded 0`；`duo restart Logseq` 后主进程和 `db-worker-node` 都是新的（13:09:03 / 13:09:06），旧 worker 已退出；之后 10 s 磁盘一直是 2.0.2、签名有效；停放的 zip 还留在 `pending/`（`autoInstallOnAppQuit false`，退出不会再装）
- 启动副作用（读 2.0.2 `app.asar` 的 `electron.js`；2026-10-22 真机启动核对）:
  - 每次启动往 `~/.local/bin/logseq` 写一个 CLI 启动脚本（`#!/usr/bin/env sh` + `# logseq-cli-managed`，`ELECTRON_RUN_AS_NODE=1 exec "<Logseq 可执行文件>" "<app.asar>/js/logseq-cli.js"`），mode 755。文件已存在且不带 `logseq-cli-managed` 标记时不覆盖；目录建不出来或不可写时弹 `dialog.showErrorBox`（模态框）。2.0.1 也有这段，0.10.15 没有。真机：启动 2.0.1 即写出该文件
  - 包里有 `Contents/Resources/.agents/skills/logseq-cli/SKILL.md`，`logseq-cli.js` 用它（`skill_file_under`）。在 `electron.js` 里没找到往 `~/.claude`、`~/.agents` 写东西的代码（`grep` 计数 0）。真机：启动前后 `~/.claude/skills`、`~/.agents/skills` 列表不变
  - 注册 `logseq://` URL scheme（Info.plist `CFBundleURLTypes`）
  - 建图谱目录（`~/logseq/graphs` 一类，`ensureDirSync`）。真机：首启建了 `~/logseq`（含 Demo 图谱）、`~/.logseq`、`~/Library/Application Support/Logseq`、`~/Library/Logs/Logseq`、`~/Library/Caches/logseq-updater`
  - MCP server 要在设置里打开才起（`settings.ai/enable-mcp-server`）
  - Rosetta 下跑 x64 版才弹「去下载 arm64 或 nightly」框（`runningUnderARM64Translation`），arm64 包不会弹
  - 没有 `setLoginItemSettings` / `openAtLogin`（计数 0）

## 已知问题
- **正常退出后 `db-worker-node` 不退**（真机 2026-10-22）：AppleScript `quit` 让主进程退出后，`Logseq …/app.asar/js/db-worker-node.js --repo logseq_db_Demo` 被 launchd 收养（ppid 1），30 s 后仍在。`duo restart` 那次旧 worker 随重启退出了，所以不影响换包；这是厂商行为，记在这里
- changelog 面板丢了 `Fixed issues` 编号列表，见上
- `com.electron.logseq`（0.10.x）副本没有任何来源回答（`unknown`），有意如此，见覆盖清单

## 建议下一步
1. 单独接入 Logseq OG（`logseq/og`，cask `logseq-og`）：先读真包确认 bundle id，再决定 0.10.x 的 `com.electron.logseq` 副本该不该经 `BundleIDMigration` 交给 OG（同为文件图谱版；要先查 OG 的 Team）。

## 历史与实测
- 2026-10-22：下载 2.0.2 / 2.0.1 / 0.10.15 / nightly(20261021) 四个 arm64 dmg 读身份（`check-bundle.sh`），结果见上面各节；channel-verify：2.0.1 → `UPDATE → 2.0.2`，2.0.2 `up to date`，nightly `inferred stable`、`up to date`，0.10.15 `unknown (no source answered)`。

## 如何复验
```bash
gh release download 2.0.1 --repo logseq/logseq --pattern 'Logseq-darwin-arm64-2.0.1.dmg'
gh release download 2.0.2 --repo logseq/logseq --pattern 'Logseq-darwin-arm64-2.0.2.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Logseq-darwin-arm64-2.0.2.dmg
swift run --package-path application-test feed-discover Logseq-darwin-arm64-2.0.1.dmg            # → electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Logseq-darwin-arm64-2.0.1.dmg --expect stable   # → GitHub, UPDATE → 2.0.2
swift run --package-path application-test channel-verify Logseq-darwin-arm64-2.0.2.dmg --expect stable   # → up to date
```
