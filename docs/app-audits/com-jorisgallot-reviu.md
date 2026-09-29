# Reviu

## 基本信息
- Bundle ID: `com.jorisgallot.reviu`
- Team ID: `V3N3ZQ3643`
- 观测版本: `1.4.0`（`CFBundleVersion` 是构建时间戳 `20260929.095014`，不参与比较）
- 自更新机制: 自研（Rust/GPUI；`POST api.reviu.dev/desktop/update/check`，下载 dmg 后
  挂载并 rsync 覆盖当前 bundle，需用户在 app 内点击）
- 分发: GitHub Releases（`reviu-dev/reviu`）/ 官网 `api.reviu.dev/desktop/update/download/latest/…`
  （无 Homebrew cask，无 MAS）
- 开源: 是。以下渠道、版本方案、端点均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.jorisgallot.reviu` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。settled from source: `desktop/crates/workspace/src/app_profile.rs` on `main`——
`AppProfile` 只有 Prod / Dev 两种，Dev 仅在 debug 构建或 `REVIU_PROFILE=dev` 时生效，
bundle id 不变，不对外分发。仓库 36 个 release 全部非 prerelease。

## 更新检测
- 源: `reviu-dev/reviu` GitHub Releases，`/releases/latest`
- 版本方案: settled from source: `.github/workflows/desktop-release.yml` on `main`——tag
  `v<version>`，dmg 名 `Reviu-<version>-macos-<arch>.dmg`。tag `v1.4.0` → `1.4.0` ==
  包的 `CFBundleShortVersionString`。
- 厂商端点对照（2026-09-29）: `POST https://api.reviu.dev/desktop/update/check`，请求体
  `{"currentVersion":"1.3.0","platform":"macos","arch":"aarch64"}` → `updateAvailable:true`、
  `latestVersion:"1.4.0"`、`releaseNotesUrl` 指向 GitHub `v1.4.0`，artifact sha256
  `0f314de5…9598` 与 GitHub 资产 `Reviu-1.4.0-macos-aarch64.dmg` 相同。请求只含版本/平台/
  架构，没有设备标识，不存在按设备灰度。
- 注意事项: 最早的 `v0.0.2` release 资产名是旧格式（`Reviu-0.0.2-beta.4-macos-arm64.dmg`），
  pattern 不收；它不是最新，不影响。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | `app_update.rs` 只下载整包 dmg 并 rsync（读源码） | release 资产与 check 响应都只有整包 dmg（2026-09-29） | — |

## 按 OS 分轨
- 包的 `Info.plist` 没有 `LSMinimumSystemVersion`；check 响应和 manifest 均无 min/max 系统版本字段。
  无可读的 OS 窗口。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 经 `GitHubMarkdownParser` 结构化带回）；
  官网 `/changelog` 页读的是同一份（`/desktop/update/changelog`）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Reviu-{v}-macos-aarch64.dmg`（`-macos-x86_64.dmg` 是 Intel 兄弟）
- Pattern: `^Reviu-[0-9.]+-macos-aarch64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；官网下载按钮给的也是同一个包）
- 包验（2026-09-29，v1.4.0 挂载）: `com.jorisgallot.reviu` / `1.4.0`，Team `V3N3ZQ3643`，
  `spctl accepted / Notarized Developer ID`，arm64 单架构
- 端到端（2026-09-29）: 装 1.3.0 → `duo check` 报 `1.3.0 → 1.4.0 [GitHub, in-place]` →
  `duo install --yes` 走完 backup / download / verifyingCodeSignature / install → 装好的包
  `1.4.0`、Team `V3N3ZQ3643`、`codesign --verify --deep --strict` 通过、`spctl` Notarized →
  再 `duo check` 为 up to date

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/reviu-dev/reviu/releases/latest → v1.4.0
# 挂载 Reviu-1.4.0-macos-aarch64.dmg → com.jorisgallot.reviu / 1.4.0 / Team V3N3ZQ3643
swift run --package-path application-test channel-verify Reviu-1.4.0-macos-aarch64.dmg --expect stable
#   → winning source GitHub, latest 1.4.0, status up to date
swift run --package-path application-test channel-verify Reviu-1.3.0-macos-aarch64.dmg --expect stable
#   → winning source GitHub, latest 1.4.0, status UPDATE → 1.4.0
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
