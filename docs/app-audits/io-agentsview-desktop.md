# AgentsView

## 基本信息
- Bundle ID: `io.agentsview.desktop`
- Team ID: `2YMZH84KR8` (William McKinney)
- 观测版本: `0.41.1`（short == build）
- 自更新机制: 无（无 `SUFeedURL`）
- 分发: GitHub Releases (`kenn-io/agentsview`) / Homebrew cask `agentsview`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.agentsview.desktop` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。最近 40 个 release 全部非 prerelease；稳定 tag `vX.Y.Z`。

## 更新检测
- 源: `kenn-io/agentsview` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.41.1` → `0.41.1` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 dmg/AppImage/tar.gz/msi，无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `AgentsView_{v}_aarch64.dmg`（arm64-only；`_x64.dmg` 是 Intel 孪生）
- Pattern: `^AgentsView_[0-9.]+_aarch64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v0.41.1 挂载）: `io.agentsview.desktop` / `0.41.1`，
  `Developer ID Application: William McKinney (2YMZH84KR8)`，notarized
- **已知缺口**：最近 40 个 release 里 **2 个（v0.41.0、v0.33.1）没发 mac dmg**，
  只有 tar.gz。`GitHubReleasesSource` 的 release walk 会跳过这类条目、一键落在
  最近一个有 dmg 的 release 上（检测仍对最新 tag）——与 cask livecheck 的语义一致。

## 已知问题
- 见上：偶发无 mac 资产的 release 由 release walk 兜住（上限
  `maxReleasesWithoutMacOSAsset` 防 pattern 失效静默化）。

## 如何复验
```
# GET https://api.github.com/repos/kenn-io/agentsview/releases/latest → v0.41.1
# 挂载 AgentsView_0.41.1_aarch64.dmg → io.agentsview.desktop / 0.41.1
# channel-verify --check io.agentsview.desktop → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
