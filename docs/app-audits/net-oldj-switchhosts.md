# SwitchHosts

## 基本信息
- App: SwitchHosts — hosts 文件管理/切换工具（Mac / Windows / Linux），Apache-2.0 开源；v5 起是 Tauri 2 应用，v3/v4 是 Electron
- Bundle ID: `net.oldj.switchhosts`（v4.3.0 起）；更早的 Electron 版是 `SwitchHosts`，见「旧 bundle id」
- 仓库: `oldj/SwitchHosts`（默认分支 `master`）；官网 `https://oldj.github.io/SwitchHosts/`
- Team ID: `J5J6USUX2F`（Developer ID + 公证；release.yml 另对 dmg 本身公证并 staple）
- 观测版本: 5.0.2（`CFBundleVersion` 同为 `5.0.2`）；beta 5.0.3-beta.3；观测日期: 2026-10-16
- 自更新机制: Tauri updater（`tauri-plugin-updater`），端点固定为
  `https://github.com/oldj/SwitchHosts/releases/latest/download/latest.json`（`src-tauri/tauri.conf.json`），
  启动时和每 12 小时检查一次（`commands.rs` `start_auto_update_checker`，受 `auto_check_update` 设置控制），下载/安装要用户点
- 分发: GitHub Releases；Homebrew cask `switchhosts`（`auto_updates` 未设，指向同一组 GitHub 资产）；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |
| **beta**   | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测，stable 与 beta 两个包都是）。`feed-discover` 给出 `—`（无 Sparkle、无
electron-builder 配置、无 MyGo feed）。Tauri 的 `latest.json` 是 app 自己的 updater 状态，不是我们读的 feed。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.oldj.switchhosts` | 共享 | 版本无后缀 | `/releases/latest`，`^v([0-9]+(?:\.[0-9]+)+)$` | ✓ |
| beta    | `net.oldj.switchhosts` | 共享 | 版本后缀 `-beta.N` | 列表（`usePrereleases`），`^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$` | ✓ |

Settled from source（`master`）:
- 版本: `scripts/sync-tauri-version.mjs` 把 `package.json` 的 version 写进 `tauri.conf.json` / `Cargo.toml`；
  `.github/workflows/release.yml` 拒绝与 `package.json` 不一致的 tag。真包核对：5.0.1、5.0.2、5.0.3-beta.3 的
  `CFBundleShortVersionString` 与 `CFBundleVersion` 都等于 tag 去 `v`（beta 保留 `-beta.3` 后缀）。
- 轨道: release.yml 里 tag 含 `-` 就建 prerelease（`if [[ "$TAG" == *-* ]]`）。v5 起的 prerelease 全是
  `vX.Y.Z-beta.N`。
- app 内没有 beta 开关: 更新端点只有 `/releases/latest`，GitHub 计算它时排除 prerelease。装 beta 的人是手动下载的。
  app 自己的 updater 在 beta 副本上只会在对应的正式版发布后提示更新（比如 5.0.3-beta.3 → 5.0.3）。
- beta rule 为什么要有: beta 副本的版本带 `-beta.N`，`ReleaseChannel.detect` 判为 `.beta`（channel-verify 实测），
  stable rule 的 channel 闸会拒绝它，没有 beta rule 就没有任何源应答。
- beta rule 为什么也收 stable tag: 与 WhatCable 的 beta rule 同理。beta 是下一个正式版的预览，beta 副本必须能拿到由它
  毕业的正式版（app 自己的 updater 也只给这个）；另外只收 `-beta.` 的 pattern 在厂商暂停 beta 时会在 `duo verify`
  里永久变红。代价: 装上正式版后副本就被判为 stable，此后只由 stable rule 应答，不会再被推 beta。与 app 自己的行为
  一致，没有缺口。
- 早期 tag: `v4.2.0-beta`、`v4.1.2-beta`（无序号）与 `v4.0.0-beta.N`、`v3.x` 的 prerelease 都在 Electron 时代，
  beta pattern 不收无序号的形状，不影响（它们远低于当前版本）。`v4.3.0` 是没有后缀但被标为 prerelease 的 Electron
  版（`net.oldj.switchhosts`，4.3.0/6139）：装着它的副本判为 stable，stable rule 给出 5.0.2（实测，见如何复验）。
- 全部非 prerelease tag（v3.0.0 … v5.0.2）都是 `vX.Y.Z`，stable pattern 都能读；下一个大版本 `v6.0.0` 也能读。

## 旧 bundle id

| 版本 | bundle id | Team | 公证 |
|---|---|---|---|
| 3.5.8 / 4.0.3 / 4.1.2 / 4.2.0（Electron） | `SwitchHosts` | J5J6USUX2F | ✓ |
| 4.3.0（Electron，prerelease） | `net.oldj.switchhosts` | J5J6USUX2F | ✓ |
| 5.0.1 / 5.0.2 / 5.0.3-beta.3（Tauri） | `net.oldj.switchhosts` | J5J6USUX2F | ✓ |

`BundleIDMigration(from: "SwitchHosts", to: "net.oldj.switchhosts", lastFromVersion: "4.2.0", firstToVersion: "4.3.0")`
把 4.3.0 以下的旧 id 副本归到 stable rule；channel-verify 在真 4.2.0 包上给出 `winning source GitHub`、`UPDATE → 5.0.2`。
v5 首次启动会把 v4 的 PotDb 数据（`~/.SwitchHosts/{data,config}`）迁到 v5 结构，并把旧目录归档到
`~/.SwitchHosts/v4/migration-<timestamp>/`（`src-tauri/src/migration/mod.rs`；v5.0.0 release notes 也写了
「支持首次启动从旧 PotDb 数据迁移」）。所以从 4.x 换成 5.x 就是厂商支持的升级路径，一键只是代替手动替换。
迁移已在真机跑过（2026-10-16，见「建议下一步」第 3 条）。

## 更新检测
- 源: `oldj/SwitchHosts` GitHub Releases。stable 读 `/releases/latest`；beta 读 releases 列表（默认 20 条），取第一个匹配的 tag
- 版本: 与 `CFBundleShortVersionString` 一致（真包 5.0.1 / 5.0.2 / 5.0.3-beta.3）
- `LSMinimumSystemVersion`: v5 为 `10.15`；4.3.0 为 `12.0`；`latest.json` 与 GitHub release 都不声明 OS 上下限

## 按架构 / 按 OS 分轨
- 每个 v5 release 有三个 mac dmg: `-mac-aarch64.dmg`、`-mac-x64.dmg`、`-mac-universal.dmg`（自 5.0.0-beta.22 起每个都有）。
  两条 rule 都只取 universal（`lipo` = `x86_64 arm64`），所以不需要按架构挑
- `latest.json` 也按 `darwin-aarch64` / `darwin-universal` / `darwin-x86_64` 给三份 `.app.tar.gz`，不按 OS 分

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Tauri updater 只下整包 `.app.tar.gz`（minisign 签名） | 2026-10-16 `latest.json` 只有 `version` / `notes` / `pub_date` / `platforms`，每个平台一个整包 URL | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（下完立即替换 bundle，实测） | — |
| 证据 | `commands.rs` `download_update` 调的是 `download_and_install`，下载完就装，之后才发 `update_downloaded` 让用户重启；没有「已下载待装」的记录文件。`tauri-plugin-updater` 内部实现没读 | 2026-10-16 真机：5.0.1 的 “New Version Found … Download Update” 点下后直接原地替换 `/Applications/SwitchHosts.app`（新 inode），再提示 “Version 5.0.2 has been installed and will take effect after restart” | — |

## Changelog
- 来源: GitHub release body，经 `GitHubMarkdownParser`（channel-verify 的 `changelog pane` 走的就是这条生产路径）
- 结构化（2026-10-16，channel-verify `changelog pane`）:
  - stable（5.0.1 包）: `source structured: 1 entries; newest 5.0.2: 3 items, headings []; first items ["chore(deps-dev): bump react-router from ", "chore(deps-dev): bump vite from 8.0.10 t", "chore(deps): bump undici from 7.25.0 to "]`。
    5.0.2 的 body 本身就只有 GitHub 自动生成的 `## What's Changed` 加三条 dependabot 条目，没有被压平的小节
  - beta（5.0.3-beta.3 包）: `source structured: 1 entries; newest 5.0.3-beta.3: 48 items, headings ["New Features", "Editor and Interface", "Bug Fixes and Reliability", "Localization", "Development and Maintenance", "新增功能", "编辑器与界面", "问题修复与可靠性", "多语言支持", "开发与维护"]`，英文与中文小节都保留为 heading
- 跟随 channel: 是（每条 rule 读自己选中的 release 的 body）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（stable 与 beta；按 Team 闸 + GitHub 资产 digest）
- 格式: dmg（universal，dmg 与内部 app 都已公证并 staple）
- Pattern: `^SwitchHosts-[0-9][0-9A-Za-z.-]*-mac-universal\.dmg$`，kind `.dmg`；不匹配 aarch64/x64 dmg、Tauri updater 的
  `.app.tar.gz` / `.sig`、Linux/Windows 包与 `latest.json`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 5.0.2 = `d3203fb6…00effd58`、5.0.1 = `812949db…3b884656`、
  5.0.3-beta.3 = `f1d6d49a…0690de82`，都与各自 `digest` 相同
- Team: 3.5.8 → 5.0.3-beta.3 读过的每个包都是 `J5J6USUX2F`，上一版 5.0.1 与最新 5.0.2 相同，没有换 Team
- 公证: `spctl -a -vv -t exec` 对 5.0.2 的 app 第一次返回 `source=Unnotarized Developer ID`，随后两次都是
  `accepted, source=Notarized Developer ID`，`stapler validate` 对 dmg 与 app 都通过。按在线查询的偶发结果处理
- 嵌套组件: v5 bundle 里没有嵌套 `.app`。有一个 SMAppService LaunchDaemon:
  `Contents/Library/LaunchDaemons/net.oldj.switchhosts.helper.plist`（`BundleProgram` = `Contents/MacOS/swh_helper`，
  `MachServices`，没有 `RunAtLoad` / `KeepAlive`）。读源码得到的行为:
  - 只在用户第一次需要写 `/etc/hosts` 时（或在偏好设置里手动安装）才注册，要管理员授权（`hosts_apply/elevation.rs`
    `try_helper`，每次会话最多尝试一次）；启动 app 本身不注册
  - daemon 按需由 launchd 拉起，`dispatch_main()` 常驻，没有空闲退出；只接受签名满足
    `identifier "net.oldj.switchhosts" and anchor apple generic and certificate leaf[subject.OU] = "J5J6USUX2F"` 的连接方
  - app 每次查状态都做一次 XPC 握手比对 `PROTOCOL_VERSION`（当前为 1），不一致报 `Outdated`，界面提示重新注册
  - 换 bundle 后：已在跑的 `swh_helper` 继续是旧代码，直到重启或重新注册；新 app 同 identifier、同 Team，连接仍被接受。
    这与 app 自己的 Tauri updater 原地替换 bundle 后的状态完全相同，所以不因此拦一键。2026-10-16 真机已确认，见「建议下一步」第 2 条
- **读的是**: 人人可手动下载的 GA（stable 走 `/releases/latest`，beta 走 release 列表；都是 release 页上直接给的 dmg）。
  beta rule 只对已经装着 beta 的副本生效，不会把 beta 推给装正式版的人
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：5.0.1 → 5.0.2（含 `verifyingSignature`；未启动，`sfltool dumpbtm` 前后都无 SwitchHosts 项），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 阻塞: 无

## 已知问题
- 换包后已在跑的 `swh_helper` 仍是旧二进制（root 进程、按需拉起、不空闲退出），直到重启或重新注册；duo 的 `Still running the old code` 只列 app，不提 helper。实测新 app 照常经旧 helper 写 hosts，无提示
- 测 helper 要写 hosts：第一次写时 helper 还没在「允许在后台」里放行，注册报 `Operation not permitted`，app 退回一次性管理员授权；放行后要重开 app 才会用 helper（每次会话只试一次）。测完在设置 ▸ Background Helper 卸载，删 app 后 BTM 里仍留 `disabled` 记录

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：5.0.1 运行中，`duo install --yes` → `installed.` 并提示 `Still running the old code: SwitchHosts`；随后在旧进程里点 “Download Update”：Tauri updater 把 5.0.2 再原地装一次（新 inode），结果 Team `J5J6USUX2F`、`codesign --strict` 0、Notarized；`duo restart` → `restarted`，新进程映射 5.0.2，`duo check` 报 up to date。`/etc/hosts` 前后 SHA-256 相同。新增 `~/.SwitchHosts`、`~/Library/{Caches,Logs,WebKit}/net.oldj.switchhosts`，登录项前后无差异
2. （已做）helper 换包，2026-10-16，main `make cli`：5.0.1 运行中、`swh_helper` 已放行并在跑（root，21:08 起），`/etc/hosts` 已写入测试行；`duo install --yes` → `installed.`，`swh_helper` 与 `switchhosts` 换成新 inode，helper 进程不变、BTM 仍 `[enabled, allowed]`、launchd `state = running`；`duo restart` → `restarted`，新 5.0.2 进程改测试行并开关一次，`/etc/hosts` 照常更新（21:11），仍由 21:08 的旧 helper 写入、无授权或「Outdated」提示。卸载 helper、关掉条目后 `/etc/hosts` 与测试前逐字节相同
3. （已做）旧 id 一键 + v5 首启迁移，2026-10-16，main `make cli`：装 4.2.0 arm64 dmg（`SwitchHosts`，Team `J5J6USUX2F`，Notarized），启动后建一个关着的 Local 条目 `v4-migrate`（内容 `# v4 migration marker`）并退出；`duo check` 报 `4.2.0 → 5.0.2 [GitHub, in-place]`，`duo install --yes` → `verifyingSignature … verifyingCodeSignature … installed.`，结果 `net.oldj.switchhosts` 5.0.2、Team 不变、`codesign --strict` 0、Notarized，`duo check` up to date。启动 5.0.2：`~/.SwitchHosts/manifest.json` 里条目同 id、`on: false`、标题与内容都保留，旧 `data`/`config` 归档到 `~/.SwitchHosts/v4/migration-<时间戳>/`（含 `archive-metadata.json`），启动不写 `/etc/hosts`，BTM 里没有 SwitchHosts 记录。注意 v4 在条目开关时会写 `/etc/hosts`（本次多出一行空行），测前要备份

## 如何复验
```
.claude/skills/coverage-discovery/scripts/check-bundle.sh <SwitchHosts-5.0.2-mac-universal.dmg>
#   → net.oldj.switchhosts 5.0.2/5.0.2，LSMinimumSystemVersion 10.15，x86_64 arm64，Team J5J6USUX2F，无嵌套 app
swift run --package-path application-test channel-verify <SwitchHosts-5.0.1-mac-universal.dmg> --expect stable
#   → detected stable，winning source GitHub，latest 5.0.2，UPDATE → 5.0.2
swift run --package-path application-test channel-verify <SwitchHosts-5.0.2-mac-universal.dmg> --expect stable
#   → detected stable，winning source GitHub，latest 5.0.2，up to date
swift run --package-path application-test channel-verify <SwitchHosts-5.0.3-beta.3-mac-universal.dmg> --expect beta
#   → short version 5.0.3-beta.3，detected beta，winning source GitHub，latest 5.0.3-beta.3，up to date
swift run --package-path application-test channel-verify <SwitchHosts_mac_arm64_4.2.0.6119.dmg> --expect stable
#   → bundle id SwitchHosts，detected stable，winning source GitHub，UPDATE → 5.0.2
#   （把 BundleIDMigration 条目的 from 改成别的 id 再跑：winning source <none>，unknown (no source answered)）
swift run --package-path application-test channel-verify <SwitchHosts-v4.3.0.6139-mac-arm64.dmg> --expect stable
#   → bundle id net.oldj.switchhosts 4.3.0，detected stable，winning source GitHub，UPDATE → 5.0.2
```
