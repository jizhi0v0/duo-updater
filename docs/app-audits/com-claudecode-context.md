# claude-devtools

## 基本信息
- Bundle ID: `com.claudecode.context`
- Team ID: `55PSHY2MW6` (NALY)
- 观测版本: `0.5.0`（short == build）
- 自更新机制: 无（无 `SUFeedURL`）
- 分发: GitHub Releases (`matt1398/claude-devtools`) / Homebrew cask `claude-devtools`
  （cask 有 `depends_on arch: :x86_64`，但 repo 一直发 arm64 dmg）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.claudecode.context` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。

> ⚠️ 2026-08-31 更正：原文写「全部 release 非 prerelease」。实测最近 15 个 release 里
> `v0.4.13` 就是 prerelease。结论不受影响（`usePrereleases: false` 走
> `/releases/latest`，GitHub 定义上不返回 prerelease），但这句断言本身是没数过就写的。

## 更新检测
- 源: `matt1398/claude-devtools` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.5.0` → `0.5.0` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | 资产只有 dmg/zip/deb/blockmap，无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `claude-devtools-{v}-arm64.dmg`（`-x64.dmg` 与 zip/blockmap 是同场兄弟）
- Pattern: `^claude-devtools-[0-9.]+-arm64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v0.5.0 挂载）: `com.claudecode.context` / `0.5.0`，Team
  `55PSHY2MW6`，`spctl accepted / Notarized Developer ID`

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/matt1398/claude-devtools/releases/latest → v0.5.0
# 挂载 claude-devtools-0.5.0-arm64.dmg → com.claudecode.context / 0.5.0
# channel-verify --check com.claudecode.context → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
