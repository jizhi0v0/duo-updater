# Plexo

## 基本信息
- App: Plexo — 多连接并行的下载加速器（Mac / Windows / Linux），Electron + electron-builder，MIT 开源
- Bundle ID: `com.plexo.app`
- 仓库: `anmolkapil/plexo`（默认分支 `main`）；官网 `https://getplexo.app/`
- Team ID: `8YNW6SHRQ8`（Developer ID + 公证，自 rc.15 起；rc.14 及更早未签名，见「一键安装」）
- 观测版本: 1.0.0-rc.15（`CFBundleVersion` 同为 `1.0.0-rc.15`）；观测日期: 2026-10-12
- 自更新机制: Electron（electron-updater，`provider: github`）。`src/main/updater.ts` 启动时查一次、之后每 4 小时一次；
  默认自动下载，重启或下次退出时安装；「Update Automatically」可关
- 分发: GitHub Releases（arm64 / x64 两个 dmg，另有给 electron-updater 用的 `*-mac.zip` + `latest-mac.yml`）。
  没有 Homebrew cask（`brew search --cask plexo` 无结果）、没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 rc.15 给出 `review electronProviderNeedsConstruction`：
bundle 里的 `app-update.yml` 只有 `owner` / `repo` / `provider: github`，通用 electron 源不从它拼地址，所以要一条
`GitHubReleaseRule`。

## Channel 详情

只有一条轨，settled from source: `src/main/updater.ts` on `main`。

- `autoUpdater.allowPrerelease = false` 写死，没有设置能改；源码注释说明 app 只跟 GitHub 标成 **Latest** 的
  release，标成 pre-release 的 release「不会推给任何人」。
- 1.0 的候选版本都打成 `v1.0.0-rc.N`。rc.1–rc.14 在 GitHub 上是 pre-release；rc.15（2026-10-11）是第一个标成
  Latest 的，也是第一个带 `latest-mac.yml` 的（rc.14 bundle 里的 `app-update.yml` 还是
  `provider: generic` / `url: https://example.com/auto-updates` 占位）。
- 版本号里的 `-rc` 不是渠道：`ReleaseChannel.detect()` 对 `1.0.0-rc.14` / `1.0.0-rc.15` 都判 `stable`（channel-verify）。
- 1.0.0 正式版之后作者是否还发 pre-release，仓库没说。发了也不影响：app 自己不会装，规则走 `/releases/latest`
  （GitHub 计算时排除 pre-release）同样跳过。若以后加了「接收 beta」开关，需要重新审计并接 `ChannelBinding`。

## 更新检测
- 源: `anmolkapil/plexo` GitHub Releases，`/releases/latest`
- 版本: tag `v1.0.0-rc.15` 去掉 `v` 等于 `CFBundleShortVersionString`。`versionPattern` 保留 `-rc.N` 后缀
  （`^v?([0-9]+(?:\.[0-9]+)+(?:-[A-Za-z]+\.[0-9]+)?)$`）；默认 pattern 会把每个候选都读成 `1.0.0`
- 排序: `VersionComparator` 把 `1.0.0-rc.15` 切成 `1,0,0,rc,15`；数字段胜过文字段，所以 `1.0.0` > `1.0.0-rc.15` >
  `1.0.0-rc.14`，`rc.10` > `rc.9`（读源码确认，见 `VersionComparator.Token.compared`）

## 按架构 / 按 OS 分轨
- 两个 dmg: `plexo-<v>-arm64.dmg`（`lipo` = arm64）与 `plexo-<v>-x64.dmg`（`lipo` = x86_64），install pattern
  两个都匹配，由资产选择器按文件名里的架构标记挑
- `LSMinimumSystemVersion` = `13.0`（rc.14、rc.15 两个架构相同）；release 与 `latest-mac.yml` 都不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 有 blockmap | 不能 |
| 证据 | 未核对本 app 打包的 electron-updater 版本是否对 mac zip 做差分下载 | rc.15 release 带 `*-mac.zip.blockmap` 与 `*.dmg.blockmap` | blockmap 是 electron-updater 的分块差分下载，不是 Sparkle `BinaryDelta`；`DeltaApplier` 用不上 |

- 格式: electron-builder blockmap
- 阻塞项: 格式不是 Sparkle 的

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-12，channel-verify `changelog pane`，从 rc.14 起）: `source structured: 1 entries; newest
  1.0.0-rc.15: 6 items, headings ["What's new"]; first items ["**New: Automatic updates.** New versions",
  "**New: Scheduled downloads.** Let downlo", "**New: Downloads from your browser.** Th"]`
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（rc.15 及以后的安装）**；rc.14 及更早的安装只检测
- 格式: dmg（公证）；嵌套的只有 Electron 标准的四个 `Plexo Helper*.app`（`Contents/Frameworks`，`LSUIElement`），
  没有 LoginItems、LaunchAgent 或常驻 helper
- Pattern: `^plexo-[0-9][0-9A-Za-z.-]*-(?:arm64|x64)\.dmg$`, kind `.dmg`；不匹配 `.blockmap`、`*-mac.zip`、`.exe`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: rc.15 arm64 = `3e05a6ad…7e64d`、
  x64 = `1e02f606…453ed`，都与各自 `digest` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，release 正文里的下载链接就是这两个 dmg）
- 端到端（2026-10-12，不运行）: rc.14 → `duo check` `1.0.0-rc.14 → 1.0.0-rc.15 [GitHub, in-place]` →
  `duo install --yes --json` → `failed: Could not read a Team Identifier from the installed app.`（12.6 s）。
  磁盘上 rc.14 原样（版本、inode 不变）。这是 `SignatureVerifier.verifyTeamIdentifierMatch` 的预期拒绝：rc.14
  未签名（`TeamIdentifier=not set`），没有身份可比
- **rc.15 → 下一个签名版本的端到端未跑**：截至 2026-10-12 只有 rc.15 一个签名版本，没有「上一个签名版」可装。
  rc.15 与下一版同 Team 时按 Team 闸走通，但这一步没有实测
- 运行中一轮（自更新器暂存）未跑：同上，没有可让它暂存的更新版本
- 阻塞: rc.14 及更早的安装要手动更新一次到 rc.15

## 已知问题
- **rc.14 → rc.15 一键被拒（设计如此）。** 未签名 → 签名没有 Team ID 可比，`duo` 拒绝；rc.14 自己的
  `app-update.yml` 是占位地址，也不会自更新。行上仍提示有更新，用户需从 release 页手动装一次。
- **与 electron-updater 的碰撞未测。** rc.15 默认自动下载并在退出时安装（`autoInstallOnAppQuit` 默认值）。若它已暂存
  一个版本、`duo` 又换了 bundle，退出时可能被换回暂存版。要等出现第二个签名版本才能复现（见 coverage-discovery
  Phase 5 的运行中一轮）。

## 建议下一步
1. 下一个签名 release 出来后：装 rc.15，跑两轮端到端（不运行；运行且 electron-updater 已暂存），补进本文件。
2. 1.0.0 正式版发布后复查 `/releases/latest` 是否指向它、`versionPattern` 读出 `1.0.0`。

## 如何复验
```
swift run --package-path application-test feed-discover <plexo-1.0.0-rc.15-arm64.dmg>    # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify <plexo-1.0.0-rc.14-arm64.dmg>   # → stable，winning source GitHub，UPDATE → 1.0.0-rc.15
swift run --package-path application-test channel-verify <plexo-1.0.0-rc.15-arm64.dmg>   # → up to date
codesign -dv <rc.14 Plexo.app>                                                            # → TeamIdentifier=not set
codesign -dv <rc.15 Plexo.app>                                                            # → TeamIdentifier=8YNW6SHRQ8
```
