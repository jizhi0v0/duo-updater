# AstrLink

## 基本信息
- App: AstrLink — 本地 AI 网关（Tauri 桌面壳 + Go `astrlink-core` 等 sidecar），Mac / Windows / Linux，另有 Docker 版
- Bundle ID: `com.astrlink.desktop`
- 仓库: `Calcium-Ion/AstrLink`（默认分支 `main`）；官网 `https://astrlink.com`
- Team ID: `7XWQYGN832`（Developer ID + 公证，0.2.4 / 0.2.5 / 0.2.6 三版相同）
- 观测版本: 0.2.6（`CFBundleVersion` 同为 `0.2.6`）；上一版 0.2.5；观测日期: 2026-10-13
- 自更新机制: 自研，基于 `tauri-plugin-updater`（`apps/desktop/src-tauri/src/updates.rs`）。不是 Sparkle，
  也不是 electron-builder
- 分发: 只有 GitHub Releases。没有 Homebrew cask（`brew search --cask astrlink` 无结果），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | —        | —   | ✓      | —           |
| **preview** | —       | —        | —   | ○      | —           |

0.2.x 副本由 **GitHub** 回答。0.3.2 副本装后复查由 **MyGo** 回答，见「历史与实测」。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.astrlink.desktop` | 共享 | — | `/releases/latest` + `$` 锚定的 tag | ✓ |
| preview | `com.astrlink.desktop` | 共享 | app 偏好 `updates.channel = "preview"`（未在真 app 上确认落盘） | 全部 release 按 SemVer 取最高 | ○ 未接 |

Settled from source: `apps/desktop/src-tauri/src/updates.rs` 和 `apps/desktop/scripts/release-updates.mjs`，均在 `main`。

- app 内有 `UpdateChannel { Stable, Preview }`，存在 `desktop-preferences.json` 的 `updates.channel`（`"stable"` /
  `"preview"`，默认 stable）。文件在 Tauri 的 `app_config_dir`，即 `~/Library/Application Support/com.astrlink.desktop/`
  （Tauri `PathResolver::app_config_dir` = `config_dir/${bundle_identifier}`，macOS 的 `config_dir` 是
  `$HOME/Library/Application Support`；`tauri.conf.json` 没有 `appDirectoriesOverride`）。
- stable: app 读 `releases/latest/download/latest.json`；preview: app 读 `/releases` 列表，取 SemVer 最高的非 draft
  release，**包括 pre-release**。
- 发版脚本 `releaseVersion` 接受 SemVer tag（`v` 可选），带 `-…` 的标 GitHub pre-release；`newestStable` 只把
  最高的正式版标成 `latest`。
- **截至 2026-10-13 一共 17 个 release（v0.1.0–v0.2.6），没有一个是 pre-release。** 所以 preview 轨现在没有自己的
  构建：选了 preview 的副本，app 自己的更新器给的也是正式版，和 stable 规则给的一样。
- **缺口（未接，原因见下）**: 第一个 pre-release 出来之后，(1) 选了 preview、跑正式版的副本，app 会给 pre-release，
  我们只给正式版；(2) 装了 pre-release 的副本，若它的 `CFBundleShortVersionString` 带 `-beta.N` 之类后缀，
  `detect()` 第 4 步会判成非 stable，stable 规则拒绝跨轨，这个副本就没有检测。没接的原因：没有任何 preview 构建，
  pre-release 的版本串和 tag 形状都没有真包可验（Phase 3¾），偏好落盘也没在真 app 上确认（审计不启动下载的 app）。
  补法是一个读 `updates.channel` 的 `ChannelBinding` + 一条 `usePrereleases` 的 GitHub 规则，等第一个 pre-release
  出来、在真包上验过再做。登记在 `CHANNEL_COVERAGE_TODO.md` §2b。

## 更新检测
- 源: `Calcium-Ion/AstrLink` GitHub Releases，`/releases/latest`
- 版本: `^v?([0-9]+(?:\.[0-9]+)+)$`。发版脚本把 tag 去掉 `v` 后写进 `tauri.conf.json` 的 `version`，所以
  `CFBundleShortVersionString` == `CFBundleVersion` == tag 的版本（0.2.4 / 0.2.5 / 0.2.6 真包都是如此）
- 按架构: 旧包用 `AstrLink_<v>_aarch64.dmg` 和 `AstrLink_<v>_x64.dmg`，新包用
  `astrlink-<v>-arm64.dmg` 和 `astrlink-<v>-amd64.dmg`。GitHub 资产选择器识别这两种命名，优先选择原生架构。
- OS: `LSMinimumSystemVersion` = `13.4`（三个版本、两个架构都一样）；release 不写 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `tauri-plugin-updater` 下载完整的 `.app.tar.gz`（`updates.rs`） | v0.2.6 的 `latest.json` 每个平台只有 `url` + minisign `signature`，没有 patch | — |

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`。正文是手写的双语，`## 中文` 和 `## English` 两节内容相同
  （`latest.json` 的 `notes` 只是一行 Full Changelog 链接，我们不用）
- 结构化（2026-10-13，channel-verify `changelog pane`，0.2.5 包）: `source structured: 1 entries; newest 0.2.6: 14 items,
  headings ["中文", "English"]; first items ["**日期**：默认不再替换日期。已经保存过各类型设置的策略保持原样。",
  "**恢复默认**：各类型脱敏、请求与响应设置可以一键恢复默认。免脱敏名单可以把默", "**没替换的原因**：请求记录会写明哪些内容命中了但没替换，以及原因：在免脱敏名"]`
- ⚠️ 结构保住了（两个小标题都是标题），但**每条改动出现两次**，一次中文一次英文（7 条改动 → 14 项）。
  正文开头的 `> [!IMPORTANT]` 提示不进条目。parser 只认 magpie 的 `<!-- lang:xx -->` 切分，不认按语言分的小标题
- 跟随 channel: —（只接了 stable）
- Recipe 状态: 不需要。要去掉重复，得挑一种语言（`ChangelogRecipe` 加 `skipSections`），这是产品决定，没做

## 一键安装
- 状态: **支持**（按 Team 闸；端到端两轮都过，见下）
- 格式: dmg（公证、staple），按架构选；bundle 里没有嵌套 app、LoginItems 或 helper
- 文件名范围: 旧、新两种命名的 macOS DMG。Tauri 更新归档、增量包和其他平台的安装器均在匹配范围之外。
- Sidecar: `Contents/MacOS/` 里有 `astrlink-core`、`astrlink-privacy-worker`、`astrlink-classifier-worker`、
  `astrlink-cli`。`sidecar.rs` 启动 core 时带 `--parent-pid <app pid>`，core 跟着 app 的生命周期走，不是常驻 helper
- 校验: GitHub 资产 `digest`（sha256），每个规则都会传下去。四个真包（0.2.6 aarch64 / x64、0.2.5 aarch64、
  0.2.4 x64）下载后的 `shasum -a 256` 都与各自的 `digest` 相同（完整值见「如何复验」）
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest` 上的 dmg，就是 README 下载链接指向的那份）
- 自更新器: 默认开着自动检查（每 3 小时）和自动下载，验签后放进缓存，进入 `ready`；**只有用户在界面上点安装
  （`install_app_update`）才替换并重启**，不会自己悄悄装。duo 装完新版后，app 下一次检查判定 up_to_date
- 端到端（2026-10-13，0.2.5 arm64 → 0.2.7，审计期间 0.2.7 刚发布）:
  - 不运行: `duo install` 走 `backed up → verifyingSignature（GitHub digest）→ verifyingCodeSignature → installed`。
    装好的副本 0.2.7，Team `7XWQYGN832`，`codesign --verify --deep --strict` 退 0，`spctl` accepted
    （Notarized Developer ID），之后 `duo check` 报 up to date
  - 运行中且 app 自己的更新器已下载好（启动约 30 s 后 `~/Library/Caches/com.astrlink.desktop/updates/<sha>.update`
    出现，46 MB）: `duo install` 换包成功并提示 `Still running the old code`；`duo restart` 后 app 和
    `astrlink-core --parent-pid <新 pid>` 都是新进程，旧 core 随旧 app 退出
  - 启动不装登录项、LaunchAgent 或 helper（前后 `sfltool dumpbtm` 无新增），不写 `~/.claude/skills`、
    `~/.agents/skills`。会写 `~/Library/Application Support/com.astrlink.desktop`、上面的更新缓存，以及钥匙串里的
    `com.astrlink.desktop.local-key`、`com.astrlink.desktop.raw-key-pin`
- 阻塞: 无

## 已知问题
- changelog 中英文重复（见上）。
- 厂商偶尔不发 x86_64 包（v0.2.5）。Intel Mac 在那一版上没有可提供的更新，下一版补上后恢复。

## 建议下一步
1. 第一个 pre-release 出来后：下载真包读 `CFBundleShortVersionString`，在真 app 上确认 `updates.channel` 落盘，
   再接 `ChannelBinding` + preview GitHub 规则（见 Channel 详情）。
2. 决定 changelog 显示哪种语言（或者保持两种都显示）。

## 如何复验
```
gh api repos/Calcium-Ion/AstrLink/releases/latest -q .tag_name              # → v0.2.6
swift run --package-path application-test feed-discover AstrLink_0.2.6_aarch64.dmg
#   → no Sparkle and no electron-builder update config
.claude/skills/coverage-discovery/scripts/check-bundle.sh <dmg>
#   0.2.6 aarch64 / 0.2.6 x64 / 0.2.5 aarch64 / 0.2.4 x64:
#   com.astrlink.desktop, short == build == tag 版本, LSMinimumSystemVersion=13.4, SUFeedURL=<none>,
#   archs arm64 / x86_64 / arm64 / x86_64, TeamIdentifier=7XWQYGN832, codesign-verify-exit=0,
#   spctl source=Notarized Developer ID, 无 nested app
swift run --package-path application-test channel-verify AstrLink_0.2.5_aarch64.dmg --expect stable
#   → detected stable, winning source GitHub, latest 0.2.6,
#     download …/v0.2.6/AstrLink_0.2.6_aarch64.dmg, status UPDATE → 0.2.6
swift run --package-path application-test channel-verify AstrLink_0.2.6_aarch64.dmg --expect stable
#   → detected stable, winning source GitHub, latest 0.2.6, status up to date
swift run --package-path application-test channel-verify AstrLink_0.2.4_x64.dmg --expect stable   # → UPDATE → 0.2.6
swift run --package-path application-test channel-verify AstrLink_0.2.6_x64.dmg --expect stable    # → up to date
shasum -a 256 *.dmg
#   2797ba7fe28a43fa5379c84c6048f03fb935c940227cd0e37f32e12933785362  AstrLink_0.2.6_aarch64.dmg
#   f1493656d532b4b6662f3e7a045b2d739f88e3f61409aca9c357153647b5b0e2  AstrLink_0.2.6_x64.dmg
#   cf8dd578dca07fe9c397b805fafd7f1b88f8a6a4db69cd908e94bf35cc4c2c7b  AstrLink_0.2.5_aarch64.dmg
#   3302e6647dd3ebbb2ed40b85ae4a249300b5fe58bdfaae36584d15df8beebe6c  AstrLink_0.2.4_x64.dmg
#   每个都等于 GitHub 资产的 digest
```


## 夜扫覆盖

- 版本与安装器共用 `github:Calcium-Ion/AstrLink:stable`，安装告警使用 `install:github:Calcium-Ion/AstrLink:stable`。
  GitHub 规则自动进入两种扫描，覆盖仍通过 GitHub 更新的旧副本。
- 0.3.2 的 MyGo 来源已由 VM 中的装后检查确认。MyGo 独立夜扫尚无 `mygo:com.astrlink.desktop` 条目，
  其 manifest、独立更新归档及签名检查不在 GitHub DMG 夜扫范围内。

## 历史与实测

### 2026-11-19 · DMG 改名

macOS 27.2 ARM64 VM 的定向夜扫命中 [0.3.2 发布](https://github.com/Calcium-Ion/AstrLink/releases/tag/v0.3.2) 的
`astrlink-0.3.2-arm64.dmg`。`duo verify-install --only com.astrlink.desktop --full` 所检 DMG 的包内版本和构建号均为
0.3.2，签名身份为 `com.astrlink.desktop` / `7XWQYGN832`，主程序架构为 ARM64。

同一台 VM 用 `duo install com.astrlink.desktop --yes` 将旧 GitHub 副本 0.2.30 原地更新为 0.3.2，报告
`applied: true`。装后严格代码签名检查通过，Gatekeeper 返回 Notarized Developer ID。`duo check` 由 MyGo
回答已是最新的 0.3.2，本次检测时无需应用 MyGo 安装包。
