# Spotifast（原 Fastpotify）

## 基本信息
- App: Spotifast — Rust 写的原生 Spotify 客户端
- Bundle ID: `rocks.spotifast.Spotifast`（0.10.0 起）；0.9.1 及以前是 `me.paolino.fastpotify`
- 仓库: `crmne/spotifast`
- Team ID: `JPL7999US3`（PlentyLabs UG），Developer ID + 公证；0.7.1 是 ad-hoc 签名、无 Team
- 观测版本: 0.12.0（2026-10-03）
- 观测日期: 2026-10-07
- 自更新机制: 自带，读本仓库 GitHub Releases（0.9.1/0.10.0 二进制里有
  `api.github.com/repos/crmne/spotifast/releases/latest`，UI 字符串有「从 GitHub 下载更新」「准备重启」）；
  无 Sparkle、无 `SUFeedURL`
- 分发: 只有 GitHub Releases（另有 Windows / Linux / Flatpak / AppImage）
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（channel-verify 实测，见「如何复验」）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `rocks.spotifast.Spotifast` | — | — | `/releases/latest` + tag 锚 `^vX.Y.Z$` + dmg 名锚 | ✓ |
| 改名前旧 id | `me.paolino.fastpotify` | 独立 | bundle id | 同仓库、同 tag 锚，**只检测**；`variant: "fastpotify"` 让它的 `recipeID` 与新 id 规则分开 | ✓（只检测） |

- `-rcN` tag（v0.4.0-rc1…v0.5.0-rc2）全部 `prerelease: true`，`/releases/latest` 本就跳过；tag 锚是后备。

## 更新检测
- 源: `crmne/spotifast` GitHub Releases，`/releases/latest`
- 版本方案: tag `vX.Y.Z` == `CFBundleShortVersionString` == `CFBundleVersion`（0.10.0 / 0.11.2 / 0.12.0 真包）
- 注意事项 —— **改名**: v0.8.0–v0.9.1 每个 release 同时有 `fastpotify-…` 和 `spotifast-…` 两个 dmg，
  两个 dmg 里的 app（0.9.1 里叫 Fastpotify.app / Spotifast.app）bundle id 都是 `me.paolino.fastpotify`；
  v0.10.0 起只有 `spotifast-…`，bundle id 换成 `rocks.spotifast.Spotifast`。dmg 锚只收 `spotifast-v…`。
- 旧 id 规则只检测：下载的是新 id，bundle-id 闸会拒；没登记 `BundleIDMigration` 改名表（#1087 起
  GitHub 规则也按 `InstalledApp.recipeBundleID` 查，登记了就会走新 id 规则和一键）。不登记的理由是厂商 0.12.0 说明写明
  0.9.0 及更早直接跳到 0.12.0 会丢设置。0.9.1 二进制已含新 id 与 `Spotifast.app` 字符串，看起来
  它自己的更新器是为这次搬迁准备的（读字符串得出，没实跑）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 自更新器下整包 | release 资产只有整包 + checksums（2026-10-07） | — |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `11.0`；release 不声明逐版本 min/max。
- 架构: 只发 universal（`lipo -archs` = `x86_64 arm64`）。

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser` 结构化
- 结构化（2026-10-07，channel-verify `changelog pane`）: ✓ `source structured`；0.12.0 15 条，
  小节 `New` / `Fixed` / `Changed` 保留；顶部「Download Spotifast」链接行与 `Thanks` 不计入条目
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（`rocks.spotifast.Spotifast`）；旧 id `me.paolino.fastpotify` 只检测（见上）
- 格式: dmg — `spotifast-vX.Y.Z-macos-universal.dmg`，GitHub 为每个资产发布 sha256 `digest`
- Pattern: `^spotifast-v[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$`, kind `.dmg`
- 包验（2026-10-07）: 0.10.0 / 0.11.2 / 0.12.0 挂载，Team `JPL7999US3`，`codesign --verify --deep --strict` 0，
  `spctl` Notarized Developer ID
- 端到端（2026-10-07）:
  - 不运行: 0.11.2 装进 `/Applications` → `duo check` `0.11.2 → 0.12.0 [GitHub, in-place]` →
    `duo install --yes --json` `installed`（13 s，30390590 字节）→ 0.12.0、inode 变、Team 不变、
    `--deep --strict` 0、Notarized、与厂商包 `diff -r` 一致、`duo backups` 有 0.11.2 备份
  - 运行中: 重装 0.11.2 并启动（它的更新器没自行暂存东西，是按钮式的）→ `duo install` `installed` →
    `duo restart Spotifast` → 新进程起来，之后 10 s 磁盘版本保持 0.12.0
- 机器现状: Spotifast 0.12.0 仍装在 `/Applications`，未运行

## 已知问题
- 数据目录仍叫 `~/Library/Application Support/me.paolino.spotifast`（新 id 也用它），与本接入无关，备查。

## 如何复验
```
swift run --package-path application-test channel-verify spotifast-v0.12.0-macos-universal.dmg
#   → winning source GitHub, latest 0.12.0, status up to date
swift run --package-path application-test channel-verify spotifast-v0.11.2-macos-universal.dmg
#   → winning source GitHub, latest 0.12.0, status UPDATE → 0.12.0
swift run --package-path application-test channel-verify fastpotify-v0.9.1-macos-universal.dmg
#   → me.paolino.fastpotify, latest 0.12.0, download = releases 页（只检测）, UPDATE → 0.12.0
```
