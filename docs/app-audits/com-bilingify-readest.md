# Readest

## 基本信息
- App: Readest — 开源电子书阅读器（Tauri 2），AGPL-3.0
- Bundle ID: `com.bilingify.readest`
- 仓库: `readest/readest`（默认分支 `main`；早期叫 `chrox/readest`，0.7.9 的可执行文件里写的还是 `github.com/chrox/readest/releases/latest`，GitHub 会重定向）
- Team ID: `J5W48D69VR`（Developer ID Application: Bilingify LLC）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 0.12.16（tag `v0.12.16`，资产 `Readest_0.12.16_universal.dmg`）；上一版 0.12.12；nightly 0.12.16-2026102206；观测日期: 2026-10-22
- 自更新机制: **Tauri updater**（`tauri-plugin-updater`，`Cargo.lock` 锁 2.11.0）。settled from source: `apps/readest-app/src-tauri/tauri.conf.json` on `main` 的 `plugins.updater.endpoints` = `https://download.readest.com/releases/latest.json`、`https://github.com/readest/readest/releases/latest/download/latest.json`，minisign 公钥同在该文件。可执行文件里的 `github.com/readest/readest/releases/latest` 就是第二个端点
- 分发: GitHub Releases（每版一个 universal dmg + Tauri 用的 `.app.tar.gz`）；Homebrew cask `readest`（`auto_updates`，0.12.16）；App Store 也有（`itunes.apple.com/lookup?bundleId=com.bilingify.readest` 返回 id 6738622779，`release-mac-appstore.sh` 往 App Store Connect 传 Mac 包，同一个 bundle id）；nightly 只在 `download.readest.com/nightly/`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | —（`auto_updates`，让位） | 商店副本走 MAS 源 | ✓ | — |
| **nightly** | —       | —        | —   | —（只检测 stable，一键被 gate 挡） | ○ |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`、没有 `app-update.yml`、没有 MyGo feed；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。商店副本由 `UpdateChecker` 的 `answersAppStoreCopies` 闸挡在 GitHub 源外。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v0.12.16: `com.bilingify.readest`，Team J5W48D69VR，Notarized，`CFBundleVersion` 0.12.16
  - v0.12.12: 同上，`CFBundleVersion` 0.12.12
  - v0.10.1: 同上
  - v0.7.9（release 列表里最老的一版）: 同 id、同 Team，`CFBundleVersion` 是时间戳 `20241201.120129`（只比 `CFBundleShortVersionString`，不影响）
  - 没有改名前的旧 bundle id
- 其他轨: nightly（见下）；release 列表 108 个 release 里有两个 `prerelease: true`（v0.9.39、v0.11.16），都是普通版本号、正文是正常的 Release Highlights，后面都有正式版（v0.11.17、v0.11.18 …），不是独立的轨，`/releases/latest` 本来就跳过它们
- 版本范围: 108 个 release 的 tag 全部是 `v<数字>(.<数字>)+`，`versionPattern` 都读得出；每个 release 恰好一个 `Readest_<version>_universal.dmg`
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Readest `LSMinimumSystemVersion` 12.0、universal，都在下限之下，不需要 `hostRequirement`
- 商店副本: 同 id，按 receipt 识别，GitHub 源不应答（引擎已有的结构性闸，不是本 rule 的事）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.bilingify.readest` | 共享 | 版本号纯数字 | GitHub `/releases/latest` | ✓ |
| nightly | `com.bilingify.readest` | 共享 | `CFBundleShortVersionString` = `<base>-<YYYYMMDDHH>` | `OneClickGate` 挡一键 | 只检测 stable；nightly 自己的 feed ○ |

**nightly 怎么来的（settled from source: `apps/readest-app/docs/superpowers/specs/2026-06-14-nightly-update-channel-design.md`、`apps/readest-app/src/helpers/updater.ts`、`.github/workflows/nightly.yml` on `main`）:**
- 应用内开关「Nightly Builds (Unstable)」，存为系统设置 `updateChannel: 'stable' | 'nightly'`（`settings.json`，在 app 自己的数据目录；具体路径没在真机上核）
- CI 每天 22:00 UTC 从 `main` 构建，只传 R2：`https://download.readest.com/nightly/latest.json`，不发 GitHub release
- 版本是 `<package.json 版本>-<YYYYMMDDHH>`。真包核过：`nightly/0.12.16-2026102206/Readest_universal.app.tar.gz`（70629507 字节）解开后 `CFBundleIdentifier` = `com.bilingify.readest`、`CFBundleShortVersionString` = `CFBundleVersion` = `0.12.16-2026102206`、Team J5W48D69VR
- 厂商自己的比较规则（`nightly_update.rs::is_update_newer`）：先比 `X.Y.Z`；同 base 时 nightly 新于 stable、stable 不会"降级"回同 base。nightly 用户的更新器同时读 nightly 和 stable 两个 manifest，取较新者

**我们对 nightly 副本做了什么：**
- 检测：`ReleaseChannel.detect` 把它判成 stable（channel-verify 实测 `inferred stable`），所以由 stable rule 回答。`VersionComparator` 把 `-2026102206` 当作多出来的数字段：`0.12.16-2026102206` 对 `0.12.16` 实测 `up to date`；base 更低的 nightly（如 `0.12.12-…`）会看到 `→ 0.12.16`。这与厂商规则在"stable 的 base 更新"这一点上一致；看不到更新的 nightly（行上会显示 up to date 而 nightly 其实已有新构建）
- 一键：`OneClickGate` `.installedVersion(pattern: ^[0-9]+(?:\.[0-9]+)+$)`，nightly 版本形状不放行。不挡的话，stable 0.12.17 发布一天后，厂商给 `0.12.16-…` 副本的答案是 `0.12.17-…`（nightly），我们会用 stable dmg 把它换下 nightly
- 要把 nightly 真正接上（检测 nightly feed、一键装 nightly）需要：`ReleaseChannel.detect` 里按 bundle id 加一个分支，或一个 `ChannelBinding` 读 `settings.json` 的 `updateChannel`；再加一个 `.nightly` 的 `VendorProbeRecipe` 读 `nightly/latest.json`（`version` + `platforms.darwin-aarch64.url`，资产是 `.app.tar.gz`）。这是引擎（Swift `Sources/`）改动，本次没做，见「建议下一步」

## 更新检测
- 源: `readest/readest` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.12.16` → `CFBundleShortVersionString` `0.12.16`（`tauri.conf.json` `version` = `../package.json`，`CFBundleVersion` 同值）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`v1.0.0-rc.1` 不匹配，`v1.0`、`v1.0.0` 匹配）
- install pattern `^Readest_[0-9]+(?:\.[0-9]+)+_universal\.dmg$`。同一个 release 里另外的 zip 是 KOReader 插件（`Readest-<v>-1.koplugin.zip`）、Calibre 插件（`Readest-<v>.calibre-plugin.zip`）、CrossPoint 插件（`Readest-<v>.crosspoint-plugin.zip`）和浏览器扩展 `send-to-readest-<v>.zip`，都不是 app 本体，不匹配；`.app.tar.gz` 是 Tauri 更新器用的，也不匹配
- `download.readest.com/releases/latest.json` 与 GitHub 的 `latest.json` 在 2026-10-22 都是 0.12.16，`pub_date` 2026-10-13T23:14:37Z，darwin 各键都指向同一个 GitHub 资产（`api.github.com/repos/readest/readest/releases/assets/638528744`，即 `Readest_0.12.16_universal.app.tar.gz`）

## 按架构 / 按 OS 分轨
- 一个 universal dmg（`archs=x86_64 arm64`），`LSMinimumSystemVersion` 12.0；`latest.json` 的 darwin-aarch64 / x86_64 / universal 指向同一个包。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | tauri-plugin-updater 2.11.0 `updater.rs`：下载整个 `url` 到内存，校验 minisign，解 tar.gz | 2026-10-22 stable 与 nightly 的 `latest.json` 每个平台只有 `url` + `signature`，没有 patch 字段 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | tauri-plugin-updater 2.11.0（`updater.rs` macOS `install_inner`）：`download` 返回 `Vec<u8>`，装时解到 `tempdir`（前缀 `tauri_updated_app`），把旧 bundle 挪到另一个 `tempdir`（`tauri_current_app`），再 rename 新的进来；没有落盘的暂存包。Readest 的 `UpdaterWindow.tsx` 只在用户点了「Download and install now?」之后才调 `downloadAndInstall`，完成后 `relaunch()` | — | — |

- 目标目录不可写时，Tauri 退到 `do shell script "rm -rf … && mv -f …" with administrator privileges`（可执行文件里有这个字符串），会弹管理员框；只发生在用户自己点安装时

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 0.12.12 起）: `source structured: 1 entries; newest 0.12.16: 75 items, headings ["Release Highlights", "What\'s Changed"]; first items ["Text-to-Speech: Added Readest Voice prem", "Annotations: You can now handwrite and d", "Library: Books now show their page count"]`
- 标题保留、没被压平。正文 `## Release Highlights` 10 条 + `## What's Changed` 65 条 = 75；`## New Contributors` 的 12 条和 `**Full Changelog**` 被解析器按设计丢掉（`GitHubMarkdownParser` 的忽略节）
- 0.12.12 与 0.12.16 之间没有别的 release，所以从 0.12.12 起只有 1 条
- 跟随 channel: nightly 没有 GitHub release，`notes` 只有 "Nightly build"
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（stable 副本）**；nightly 副本被 `OneClickGate` 挡，只检测
- 端到端: **未跑**。真机（装上一版 → `duo install`）由主会话做
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Readest.app` + `Applications` 软链
- 嵌套: 无。0.12.16 dmg 里的 bundle 在 `Contents/` 下三层内找不到 `.app` / `.framework` / `LoginItems` / `Helpers` / `Library`，`MacOS/` 只有 `readest`（nightly 包 `Contents/` 为 `CodeResources`、`Info.plist`、`MacOS`、`Resources`、`_CodeSignature`、`embedded.provisionprofile`）；没有 LoginItems / Helpers / LaunchAgent / Frameworks。可执行文件里没有 `SMAppService`、`LaunchAgents`、`.claude`、`.agents`、`.codex` 字符串
- 签名: 0.7.9、0.10.1、0.12.12、0.12.16 都是 Team `J5W48D69VR`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产 `digest`。v0.12.16 dmg `sha256:493f8393b5f1e7d1cd26525f0737b2658cafc7efb0657d9102834c6bdd194f0f`，`gh release download` 的文件 `shasum -a 256` 相同、70983929 字节等于资产大小；v0.12.12 dmg `sha256:e6ea4dddaeed113eaa72e027b6b29c1a47846896a88727b343f6d8551937bd33` 同样相符
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Readest 自己的 stable 更新器读的也是这一版）
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 首启自动检查更新（`autoCheckUpdates` 默认 true，24 h 节流）：从 0.12.12 启动会弹一个「Software Update」窗口（`updater.ts` `showUpdateWindow`）。不要点里面的安装，否则是 Tauri 自己换包
  - 换到新版后再启动，`checkAppReleaseNotes` 会因版本变高弹出更新说明窗口
  - Info.plist 声明 epub / pdf / fb2 / cbz / mobi / azw / txt 的文档类型，`LSHandlerRank` 都是 `Alternate`（不抢默认打开方式）；URL scheme `readest`、`readest-onedrive`
  - entitlements 带 iCloud 容器 `iCloud.com.bilingify.readest`（CloudDocuments），首启可能在 iCloud Drive 建 Readest 文件夹（推断，未验证）
  - 包里没有登录项、LaunchAgent、root helper；不往 `~/.claude` / `~/.agents` 写（strings 无，推断）
  - 自更新器不暂存，第二轮无法造「暂存了一个比 latest 旧的版本」；能撞上的只有用户在它自己的更新窗口里点安装，那是就地换包

## 已知问题
- nightly 副本行上显示的是 stable 视角（同 base 时 up to date，看不到更新的 nightly 构建），一键被挡；接 nightly 需要引擎改动，见上
- App Store 版与 GitHub 版同 id；商店副本靠引擎的 MAS 闸避开 GitHub 源，本次没有商店副本可测

## 如何复验
```bash
gh release view v0.12.16 -R readest/readest --json assets -q '.assets[]|select(.name|test("dmg$"))|.name+" "+.digest'
gh release download v0.12.16 -R readest/readest -p 'Readest_0.12.16_universal.dmg'
gh release download v0.12.12 -R readest/readest -p 'Readest_0.12.12_universal.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Readest_0.12.12_universal.dmg   # Team J5W48D69VR, Notarized
swift run --package-path application-test channel-verify Readest_0.12.12_universal.dmg --expect stable   # GitHub, UPDATE → 0.12.16
swift run --package-path application-test channel-verify Readest_0.12.16_universal.dmg --expect stable   # up to date
# nightly 副本
curl -sSL https://download.readest.com/nightly/latest.json        # version 0.12.16-2026102206
curl -sSLO https://download.readest.com/nightly/0.12.16-2026102206/Readest_universal.app.tar.gz && tar -xzf Readest_universal.app.tar.gz
swift run --package-path application-test channel-verify Readest.app   # inferred stable, up to date（一键由 OneClickGate 挡）
swift test --package-path DuoUpdaterCore --filter readestOneClickIsForStableBuildsOnly
```

channel-verify 原始输出（2026-10-22）:
```
0.12.12 dmg: detected channel → stable; winning source GitHub; latest 0.12.16;
  download https://github.com/readest/readest/releases/download/v0.12.16/Readest_0.12.16_universal.dmg;
  status UPDATE → 0.12.16
0.12.16 dmg: winning source GitHub; latest 0.12.16; status up to date
0.12.16-2026102206 (nightly .app): inferred stable; winning source GitHub; latest 0.12.16; status up to date
```

## 建议下一步
1. 主会话真机两轮（上一版 0.12.12 → 0.12.16），结果写回「一键安装」并把 README 行改成 ✓
2. nightly 轨（需要决定是否做引擎改动）: `ReleaseChannel.detect` 按 bundle id 认 `-[0-9]{10}$` 版本后缀为 nightly（或 `ChannelBinding` 读 `settings.json` 的 `updateChannel`），加 `.nightly` `VendorProbeRecipe` 读 `https://download.readest.com/nightly/latest.json`；一键要装 `.app.tar.gz`（Tauri 包，minisign 签名、无摘要），另需 `ChannelProofRegistry` 条目
