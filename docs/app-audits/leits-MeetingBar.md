# MeetingBar

## 基本信息
- Bundle ID: `leits.MeetingBar`
- Team ID: `KGH289N6T8`（Developer ID Application: Andrii Leitsius）
- 观测版本: `4.11.6`（`CFBundleVersion` `169`，是构建计数，不参与比较）
- 自更新机制: 无（包内没有 `SUFeedURL`、没有 `Frameworks/`，`feed-discover` 结论
  `no Sparkle and no electron-builder update config`）
- 分发: GitHub Releases（`leits/MeetingBar`）/ Homebrew cask `meetingbar` / Mac App Store
  （id `1532419400`，同一 bundle id `leits.MeetingBar`，2026-09-29 商店版本 `4.11.6`）
- 开源: 是（`leits/MeetingBar`，默认分支 `master`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓        | ✓   | ✓      | —           |
| **beta**（V5 预发布） | — | — | — | ✗ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: DMG 安装的副本是 **GitHub**；
brew 安装的副本由 `HomebrewCaskSource` 先应答（cask 非 `auto_updates`）；MAS 副本由
`MacAppStoreSource` 应答，`GitHubReleasesSource` 对 `isMASApp` 直接跳过，不会给商店副本
推 Developer ID 包。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `leits.MeetingBar` | 共享 | — | `/releases/latest` + tag 锚 `^vX.Y.Z$` | ✓ |
| beta（V5 预发布） | `leits.MeetingBar` | 共享 | 无 | — | ✗（Pattern D） |

仓库的预发布轨: `v4.11.beta`、`v4.11.beta2`（2025-05）、`v5.0.0`（标题 `5.0.0 (RC-1)`，
2026-06-19）、`v5.0.0-rc2`（2026-07-04），全部标了 prerelease。挂载 `v5.0.0-rc2` 的
`MeetingBar.dmg`: bundle id `leits.MeetingBar`、`CFBundleShortVersionString` `5.0.0`、
`CFBundleVersion` `171`，没有 `KSChannelID`、app 名里没有渠道词、版本号没有后缀——
装着 RC 的副本和正式版无从区分，属于 Pattern D，不接入。

## 更新检测
- 源: `leits/MeetingBar` GitHub Releases，`/releases/latest`（GitHub 计算时排除
  prerelease；2026-09-29 返回 `v4.11.6`）
- 版本方案: 仓库没有 release workflow（`.github/workflows/` 只有 `ci.yml` / `lint.yml` /
  `security.yml`），release 由作者手动上传；版本号来自 `project.pbxproj` 的
  `MARKETING_VERSION`（`master` 上当前为 `5.0.0` / `CURRENT_PROJECT_VERSION` `171`）。
  tag `v4.11.6` → `4.11.6` == 包的 `CFBundleShortVersionString`；`v4.11.5` 同样相等。
- tag 形状: 近 30 个 release 里稳定版都是 `vX.Y.Z` 或 `vX.Y`（`v4.0`），pattern
  `^v([0-9]+(?:\.[0-9]+)+)$` 两种都收；`v4.11.beta`、`v5.0.0-rc2` 被锚点拒绝。
- 资产: 每个 release 只有一个不带版本号的 `MeetingBar.dmg`，30 个里没有缺资产的，
  名字没漂移。
- 注意事项: 装着 V5 RC 的副本自报 `5.0.0` > `4.11.6`，stable 规则判为最新，不会被降级；
  但 V5 正式版若也是 `5.0.0`，这类副本同样看不到（Pattern D 的代价）。

## 按 OS 分轨
- `LSMinimumSystemVersion` `12.0`（`4.11.6` 与 `5.0.0-rc2` 相同）；release 没有声明 OS 上限。
- 架构: `x86_64 arm64` universal，单一资产。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 包里没有更新框架（无 `Frameworks/`、无 `SUFeedURL`） | release 只有整包 `MeetingBar.dmg`（2026-09-29） | — |

## Changelog
- 来源: GitHub Release 正文（`v4.11.6` 正文 135 字符，一句说明 + compare 链接）。
  `channel-verify` 显示 `0 chars inline`，changelogURL 指向 release 页。
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 4.11.5 检查）: ✓ 1 条（正文只有一句说明加 `**Full Changelog**` 链接，链接被当作全量链接跳过），无小标题；只带回最新一版的说明（1 个条目）
- 跟随 channel: 只接 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg，`MeetingBar.app` 在 dmg 根目录（旁边是 `/Applications` 链接）
- Pattern: `^MeetingBar\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产，`/releases/latest`，也是
  Homebrew cask 指向的同一个包）
- 包验（2026-09-29）: `4.11.6` 与 `4.11.5` 两个 dmg 均为 Team `KGH289N6T8`、
  `Notarization Ticket=stapled`、`spctl` `accepted / Notarized Developer ID`，universal。
  `4.11.6` 资产 sha256 `4f19af49…38d7`，与 GitHub API 的 `digest` 一致。
- 端到端（2026-09-29）: 装 4.11.5 → `duo check` 报 `4.11.5 → 4.11.6 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `4.11.6`、Team `KGH289N6T8`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- V5 预发布轨（同 bundle id、无检测信号）未接入，见上。

## 如何复验
```
# GET https://api.github.com/repos/leits/MeetingBar/releases/latest → v4.11.6
# 挂载 v4.11.6 MeetingBar.dmg → leits.MeetingBar / 4.11.6 (169) / Team KGH289N6T8
swift run --package-path application-test channel-verify <v4.11.6>/MeetingBar.dmg --expect stable
#   → detected channel stable, winning source GitHub, latest 4.11.6, status up to date
swift run --package-path application-test channel-verify <v4.11.5>/MeetingBar.dmg --expect stable
#   → detected channel stable, winning source GitHub, latest 4.11.6, status UPDATE → 4.11.6
```

## 建议下一步
无。stable 检测 + 一键已覆盖；V5 预发布轨转正后 `/releases/latest` 会自动跟上。
