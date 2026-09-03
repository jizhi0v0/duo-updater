# OpenSuperWhisper

## 基本信息
- Bundle ID: `ru.starmel.OpenSuperWhisper`
- Team ID: `8LLDD7HWZK` (Kornienko Vyacheslav)
- 观测版本: `0.1.0` (build `13`)
- 自更新机制: 无（无 `SUFeedURL`）
- 分发: GitHub Releases (`starmel/OpenSuperWhisper`) / Homebrew cask `opensuperwhisper`（arm64-only）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ru.starmel.OpenSuperWhisper` | 单一渠道 | — | tag 锚 `^X.Y.Z$`（无 v） | ✓ |

单渠道。全部 7 个 release 均为非 prerelease。

## 更新检测
- 源: `starmel/OpenSuperWhisper` GitHub Releases，`/releases/latest`
- 版本方案: tag `0.1.0`（**无 `v` 前缀**）→ `0.1.0` == 包的 short。build（13）独立，
  不与 tag 比较——沿用 generic 机制（marketing 优先、build 裁决）。
- 资产文件名**不带版本号**（`OpenSuperWhisper.dmg` 每个 release 同名），版本只来自 tag。
- cask livecheck 注释提到「tag 与 release 创建之间有缺口，故看 latest release 而非
  tags」——我们读的就是 `/releases/latest`，天然同语义。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 dmg 与 dSYM，无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `OpenSuperWhisper.dmg`（arm64-only，与 cask 的 `depends_on arch: :arm64` 一致）
- Pattern: `^OpenSuperWhisper\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，0.1.0 挂载）: `ru.starmel.OpenSuperWhisper` / `0.1.0`，
  `Developer ID Application: Kornienko Vyacheslav (8LLDD7HWZK)`，`spctl accepted /
  Notarized Developer ID`

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/starmel/OpenSuperWhisper/releases/latest → 0.1.0
# 挂载 OpenSuperWhisper.dmg → ru.starmel.OpenSuperWhisper / 0.1.0
# channel-verify --check ru.starmel.OpenSuperWhisper → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
