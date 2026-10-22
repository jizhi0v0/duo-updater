# Whispering

## 基本信息
- App: Whispering — 按快捷键说话、转写成文字（云端 API 或本地 Parakeet / Whisper.cpp / Moonshine），Tauri 2 应用；AGPL-3.0
- Bundle ID: `com.bradenwong.whispering`（4.x 起；更早的 v2.0.0 资产是 `com.bradenwong.com`，见覆盖清单）
- 仓库: `EpicenterHQ/epicenter`（monorepo，默认分支 `main`，app 在 `apps/whispering/`）。`epicenter-os/epicenter` 由 GitHub 重定向到这里（`gh api repos/epicenter-os/epicenter` 返回 `full_name: EpicenterHQ/epicenter`）；Homebrew cask 的 URL 还写着 `epicenter-os`。老仓库 `braden-w/whispering` **不是重定向**，是一个已归档的独立仓库（`archived: true`，描述「Moved to EpicenterHQ/epicenter」）。7.11.0 的可执行文件里写的是 `github.com/EpicenterHQ/epicenter/releases/latest`
- Team ID: `3C7J97QA5Z`（Developer ID Application: Braden Wong），7.11.0 与上一版 7.9.0 相同；dmg 内 app 已公证、stapled
- 观测版本: 7.11.0（tag `v7.11.0`，2025-12-27 发布；arm64 资产 2026-06-15 重新上传过，签名时间戳同日）；上一个有 Apple silicon 包的版本 7.9.0；观测日期: 2026-10-22
- 自更新机制: **Tauri updater**（`tauri-plugin-updater` 2.9.0，Cargo.lock @ v7.11.0）。settled from source: `apps/whispering/src-tauri/tauri.conf.json` @ `v7.11.0` 的 `plugins.updater.endpoints` = `https://github.com/EpicenterHQ/epicenter/releases/latest/download/latest.json`；启动时 `check-for-updates.ts` 只弹一条应用内通知，用户点「Install Update」才 `downloadAndInstall`
- 分发: GitHub Releases；Homebrew cask `whispering`（7.11.0，无 `auto_updates`）。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（cask 装的副本，通用源） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 7.9.0 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。经 Homebrew 装的副本由 `HomebrewCaskSource` 先应答（`SourceStack` 里它排在 GitHub 前面，cask 没有 `auto_updates`）。

## 覆盖清单
- 各版本的 bundle id / Team（逐个读真包，`check-bundle.sh`）:

  | 资产 | CFBundleIdentifier | 短版本 | 架构 | 签名 |
  |---|---|---|---|---|
  | v7.11.0 `Whispering_7.11.0_aarch64.dmg` | `com.bradenwong.whispering` | 7.11.0 | arm64 | Team 3C7J97QA5Z，Notarized |
  | v7.10.0 `Whispering_7.10.0_x64.dmg` | 同上 | 7.10.0 | x86_64 | 同上 |
  | v7.9.0 `Whispering_7.9.0_aarch64.dmg` | 同上 | 7.9.0 | arm64 | 同上 |
  | v7.7.1 `Whispering_7.7.1_aarch64_darwin.dmg` | 同上 | 7.7.1 | arm64 | 同上 |
  | v7.2.2 `Whispering_7.2.1_aarch64.dmg` | 同上 | **7.2.1** | arm64 | 同上 |
  | v6.5.0、v5.0.0、v4.8.0、v4.7.3 | 同上 | 与 tag 相同 | arm64 | 同上 |
  | v4.7.2、v4.5.0、v4.0.0 | 同上 | 与 tag 相同 | arm64 | **ad-hoc**（`TeamIdentifier=not set`，签名标识 `app-<hex>`） |
  | v3.4.0 `Whispering_3.4.0_x64.dmg` | 同上 | 3.4.0 | x86_64 | 无可用签名 |
  | v2.2.0 `Whispering_2.2.0_x64.dmg` | 同上 | **3.0.0** | universal | Team 3C7J97QA5Z，Notarized |
  | v2.0.0 `Whispering-v2.0.0.dmg` | **`com.bradenwong.com`** | 0.1.0 | x86_64 | 无可用签名 |

  - `com.bradenwong.com`（2023-03 的 v2.0.0，Intel、无签名）不收：`BundleIDMigration` 要求两个 id 由同一个 Team 签名（「A migration never crosses Teams」，`teamID` 必填），而这个副本没有 Team；它也无法一键（Team 闸要求已装副本有 Team）。缺口
  - 4.0.0–4.7.2 与 3.4.0 是 ad-hoc / 无签名：检测照常（同一 bundle id，规则读得到），一键被 `SignatureVerifier.verifyTeamIdentifierMatch` 以 `noTeamIdentifier(which: "installed")` 拒绝，用户手动更新一次后就进入一键范围。`.publishedDigestOnly` 不适用：新包有 Team，属于 `teamAppeared` 路线，被有意拒绝
  - Team 从 4.7.3 起一直是 `3C7J97QA5Z`，没有换过
- 其他轨: 没有。69 个非 prerelease release 里，`versionPattern` 读 67 个；唯一的 prerelease 是 `_assets`（只放一个 `macos_enable_accessibility.mp4`）。v3.0.0 / v3.1.0 是「Whispering Extension」（浏览器扩展），没有 mac 资产、版本远低于现行，不会被选中
- 版本范围、主机下限: `LSMinimumSystemVersion` 10.15（7.x）、10.13（≤6.5）；DuoUpdater 自己 `ARCHS: arm64`（`App/project.yml`），厂商下限低于我们的下限，不需要 `hostRequirement`。7.11.0 本身没有 Intel 包（`latest.json` 的 `platforms` 只有 `darwin-aarch64`），对我们无影响

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.bradenwong.whispering` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `EpicenterHQ/epicenter` GitHub Releases，`/releases/latest`
- 版本方案: tag `v7.11.0` → `CFBundleShortVersionString` `7.11.0`（7.x 起 `CFBundleVersion` 也是 `7.11.0`；6.x 以前是时间戳，不参与比较）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读 `v8.0.0`、`v10.0`；不读 `v8.0.0-rc.1`、`v7.12.0-beta`、`@epicenter/cli@0.1.0`
- install pattern `^Whispering_[0-9]+(?:\.[0-9]+)+_aarch64(?:_darwin)?\.dmg$`（`_darwin` 是 7.6.0–7.7.1 的命名，分诊草稿漏了它）
- **待审项「有 tag 读不出」**: 读不出的两个都有意不收——
  - `models/parakeet-tdt-0.6b-v3-int8`：Parakeet 模型权重的 release（6 个资产，没有 app），不是本产品的版本
  - `feature/whi-61-hotfix-infoplist-permissions-after-code-signing`：2024-07 的分支构建，资产是 `Whispering_4.7.1_*.dmg`；分支名不是版本号，4.7.1 早已被后续正式版覆盖
- **待审项「`/releases/latest` 是不是永远是 Whispering」**: 现在是（v7.11.0）。但这个 monorepo 已经发过非 Whispering 的正式 release（上面的 `models/…`，2025-09-19 发布），`main` 上还有 `@epicenter/*@x.y.z` 的 npm 包 tag（目前没有对应 release）。不需要改走列表：这条规则带 `installAssetPattern`，`GitHubReleasesSource.settle` 在 latest 那一个 release 没有匹配资产时会改读 `/releases?per_page=20` 并按 `stableOnly` 往回走，跳过 tag 不匹配的条目，走到最新的 Whispering release。如果以后非 Whispering 的 release 一次连发 20 个以上，那一页里会没有 Whispering，规则回报 `.unknown`（不会误报「已是最新」）
- 分诊说「v7.6.0/7.7.x/7.10.0 没有 mac 资产」**不对**：7.6.0、7.7.0、7.7.1 有 `Whispering_<v>_aarch64_darwin.dmg` 和 `…_x64_darwin.dmg`（已收进 install pattern）；7.7.2 有标准命名的包；7.10.0 只有 `Whispering_7.10.0_x64.dmg`，没有 arm64 包，规则按「没有本机架构的包」跳过它
- channel-verify（production `UpdateChecker.check()`，2026-10-22）:
  - 7.9.0 dmg → `winning source GitHub`、`latest 7.11.0`、`status UPDATE → 7.11.0`
  - 7.7.1（`_darwin` 命名）dmg → `UPDATE → 7.11.0`
  - 7.10.0 x64 dmg → `UPDATE → 7.11.0`
  - 7.11.0 dmg → `up to date`

## 按架构 / 按 OS 分轨
- 架构: 每版分 arm64 / x64 两个 dmg（7.10.0 只有 x64，7.11.0 只有 arm64）。规则只装 arm64；`LSMinimumSystemVersion` 10.15
- release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `tauri-plugin-updater` 只下载整个 `Whispering_aarch64.app.tar.gz`（minisign 签名的 `.sig` 校验） | `latest.json`（2026-10-22）的 `darwin-aarch64` 只有一个整包 URL | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 7.9.0 约 20 s，没有停放任何东西） | 不需要 |
| 证据 | `tauri-plugin-updater` 2.9.0 `updater.rs`（tag `updater-v2.9.0`）：`download` 返回内存里的 `Vec<u8>`，macOS 的 `install_inner` 解到 `tempfile` 临时目录、当场把旧 app 挪去备份并换上新 app；没有跨启动保留的下载目录。只有用户在 app 里点「Install Update」才会触发 | — | — |

- 记录文件与字段: 无
- 容器: `.app.tar.gz`（只在内存里）
- 两份副本会不会共用这个目录: 不适用

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 7.9.0 起）: `source structured: 1 entries; newest 7.11.0: 23 items, headings ["Moonshine (New-macOS/Linux)", "Other Improvements", "Features", "Bug Fixes", "Improvements"]; first items ["**Tiny** (~30 MB): 6-layer model, great ", "**Base** (~65 MB): 8-layer model, better", "**Settings Overhaul**: Reorganized with "]`
- 标题**保留、没有压平**（5 个带列表的小节各自成组；正文 23 个列表项全部在）。但 7.11.0 的正文大半是**纯段落小节**（「Windows: No More Vulkan Crashes」「Auto-Start on Login」「Initial Prompt Support」「Dark Mode: No More Flash」等），解析器只收列表，这些小节不进面板。面板看到的是 Moonshine 两个模型、Other Improvements 和 What's Changed 下的 PR 列表。这是通用解析器的取舍，和 Harp 一样；不改解析器
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 7.9.0 → `duo check` `7.9.0 → 7.11.0 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 7.11.0、可执行文件 inode 变、`TeamIdentifier=3C7J97QA5Z`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 7.11.0 包相同
  - 第二轮（运行中）: 启动 7.9.0（一个窗口，没有系统授权框），`duo install` 后提示 `Still running the old code`；`duo restart Whispering` 后新进程 13:39:58 起来，之后 10 s 磁盘一直是 7.11.0、签名有效。辅助功能授权是否跨版本保留没测（本机没给它授权）
- 格式: dmg（UDZO，GUID），根目录 `Whispering.app` + `Applications` 软链。app 里只有 `Contents/MacOS/whispering` 一个可执行文件和 `Resources/icon.icns`，没有 LoginItems / Helpers / XPC / 嵌套 app
- 签名: 7.11.0、7.9.0 都是 `TeamIdentifier=3C7J97QA5Z`、`spctl` Notarized Developer ID、hardened runtime、`stapler validate` 通过
- 校验: GitHub 资产 `digest`。v7.11.0 `Whispering_7.11.0_aarch64.dmg` = `sha256:7c15883a5562e594633e2636db5abbc8197b8ae93c4714711bf802b531eaf2d0`，下载到的 15606745 字节 `shasum -a 256` 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，和 app 自己的 Tauri updater 读的是同一个 release）
- 阻塞: 无。4.0.0–4.7.2 等无 Team 的老副本一键被拒，见覆盖清单
- 启动副作用（来自源码 @ `v7.11.0`；2026-10-22 真机核对的已注明）:
  - 启动时 `register-permissions.ts` 只**检查**辅助功能和麦克风权限，没给就弹应用内 toast；麦克风系统框要用户点 toast 上的「Enable Permission」才请求。辅助功能的 toast 写着「This often requires removing and re-adding the app after updates」——换包后辅助功能授权是否保留值得在真机上看一眼（同 Team、同 bundle id 的指定要求应当不变，未验证）
  - 「Start on login」是设置里的开关，默认关；打开后由 `tauri-plugin-autostart`（`MacosLauncher::LaunchAgent`）在 `~/Library/LaunchAgents/` 写一个启动 app 本体的 plist，不是常驻 helper，换包后路径不变
  - 启动即向 Aptabase（`us.aptabase.com`）发 `app_started` 事件（发行版编译进了 app key）；退出发 `app_exited`
  - `single-instance` 插件：再次启动只会聚焦已有窗口
  - 有首启引导（`register-onboarding.ts`，未读内容）；不写 `~/.claude` / `~/.agents`（源码里没有相关路径；真机启动前后这两处、`~/Library/LaunchAgents` 都没变）。真机首启建了 `~/Library/{Application Support,Caches,Logs,WebKit}/com.bradenwong.whispering`

## 已知问题
- v7.2.2 的 arm64 资产叫 `Whispering_7.2.1_aarch64.dmg`，里面的 bundle 也是 7.2.1（与 v7.2.1 的包不是同一个文件）。Developer ID 路线不比对包内版本，若厂商在最新版上再犯，一键会装上一个自报旧版本的包，然后继续提示更新。历史上只此一次（另有 v4.1.2 / v4.2.1 带着旧版本号的包），记录不处理
- `main` 上的下一代（`apps/whispering/src-tauri/tauri.conf.json`，`version` 7.11.1）已把 `identifier` 改成 `so.epicenter.whispering`、`signingIdentity` 改成 `"-"`（ad-hoc）、`bundle.targets` 只出 `app`，自动发版 workflow 写着「DISABLED until v8.0.0 is tagged」。若它按这个配置发布：新 id 与本规则无关；如果资产名仍匹配 `Whispering_*_aarch64.dmg`，老 `com.bradenwong.whispering` 副本会被提示升级、一键因新包没有 Team 被拒。那次发版时要重新审计

## 如何复验
```bash
gh api repos/EpicenterHQ/epicenter/releases/latest -q '.tag_name, (.assets[]|.name+" "+.digest)'
gh release download v7.11.0 --repo EpicenterHQ/epicenter --pattern 'Whispering_7.11.0_aarch64.dmg'
gh release download v7.9.0 --repo EpicenterHQ/epicenter --pattern 'Whispering_7.9.0_aarch64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Whispering_7.11.0_aarch64.dmg   # → Team 3C7J97QA5Z, Notarized
swift run --package-path application-test feed-discover Whispering_7.9.0_aarch64.dmg       # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify Whispering_7.9.0_aarch64.dmg --expect stable   # → GitHub, UPDATE → 7.11.0
swift run --package-path application-test channel-verify Whispering_7.11.0_aarch64.dmg --expect stable  # → up to date
curl -sL https://github.com/EpicenterHQ/epicenter/releases/latest/download/latest.json | python3 -m json.tool
```

## 建议下一步
1. 下一个正式版（很可能是 v8.0.0）发布时复查：bundle id 是否换成 `so.epicenter.whispering`、是否 ad-hoc、资产命名，以及 `/releases/latest` 是否仍是 Whispering。
