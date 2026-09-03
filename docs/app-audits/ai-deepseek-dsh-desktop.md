# DSH Desktop (DeepSeek Harness)

## 基本信息
- Bundle ID: `ai.deepseek.dsh.desktop`
- Team ID: `UM3Z9G5DNH`
- 观测版本: `2.0.4`（short == build）
- 自更新机制: 无（无 `SUFeedURL`）
- 分发: GitHub Releases (`anywhere-labs/dsh-desktop`) / 官网（无 Homebrew cask）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.deepseek.dsh.desktop` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。全部 release 非 prerelease。

## 更新检测
- 源: `anywhere-labs/dsh-desktop` GitHub Releases，`/releases/latest`
- 版本方案: tag `v2.0.4` → `2.0.4` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 universal dmg 与 Windows exe（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `DSH.Desktop-{v}-universal.dmg`（x64-Setup.exe 是 Windows 兄弟）
- Pattern: `^DSH\.Desktop-[0-9.]+-universal\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v2.0.4 挂载）: `ai.deepseek.dsh.desktop` / `2.0.4`，Team
  `UM3Z9G5DNH`，`spctl accepted / Notarized Developer ID`

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/anywhere-labs/dsh-desktop/releases/latest → v2.0.4
# 挂载 DSH.Desktop-2.0.4-universal.dmg → ai.deepseek.dsh.desktop / 2.0.4
# channel-verify --check ai.deepseek.dsh.desktop → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
