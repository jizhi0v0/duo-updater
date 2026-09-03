# Paseo

## 基本信息
- Bundle ID: `sh.paseo.desktop`
- Team ID: `99ZMJMKU9Y` (Mohamed Boudra Ziani)
- 观测版本: `0.6.1`（short == build）
- 自更新机制: electron-updater（`app-update.yml`: provider github, channel latest）
- 分发: GitHub Releases (`getpaseo/paseo`) / Homebrew cask `paseo`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `sh.paseo.desktop` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |
| beta    | （同 bundle，beta 构建） | — | — | 未接入 | ○ |

单渠道（本接入只做 stable）。**beta 轨道存在**：repo 把 beta 发成 prerelease
release（`v0.7.0-beta.2`，资产 `beta-mac.yml` + dmg）——锚定的 stable pattern
拒读 `-beta` 后缀，且 `/releases/latest` 按 GitHub 定义排除 prerelease，双保险
不会把 beta 推给 stable 装机。beta 轨道本身未接入（构建 channel 不同，需要
装机 build 命中 beta feed 才能安全跟随，属 ChannelBinding 范畴）。

## 更新检测
- 源: `getpaseo/paseo` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.6.1` → `0.6.1` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | electron-updater 支持 | 无 | 不能 |
| 证据 | — | release 资产无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Paseo-{v}-arm64.dmg`（`.deb`/`AppImage` 是 Linux 兄弟）
- Pattern: `^Paseo-[0-9.]+-arm64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v0.6.1 挂载）: `sh.paseo.desktop` / `0.6.1`，Team
  `99ZMJMKU9Y`，`spctl accepted / Notarized Developer ID`；自包含 bundle
  （无 `Contents/Library`，daemon 由 app 自行管理）→ `.dmg` 正确

## 已知问题
- beta 轨道未接入（见上）。vendor 的 beta 是 prerelease 轨，不与 stable 冲突。

## 如何复验
```
# GET https://api.github.com/repos/getpaseo/paseo/releases/latest → v0.6.1
# 挂载 Paseo-0.6.1-arm64.dmg → sh.paseo.desktop / 0.6.1
# channel-verify --check sh.paseo.desktop → winning=GitHub, up to date
```

## 建议下一步
- beta 轨道：若要接，需先核实 beta 构建的装机形态与 channel 选择机制。
