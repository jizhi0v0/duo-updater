# Meetily

## 基本信息
- Bundle ID: `com.meetily.ai`
- Team ID: `554AZZ38TB` (ZACKRIYA SOLUTIONS)
- 观测版本: `0.4.0`（short == build）
- 自更新机制: Tauri 自研（无 `SUFeedURL`；release 里的 `latest.json` 是 Tauri
  updater 状态文件，不是我们能读的 feed）
- 分发: GitHub Releases (`Zackriya-Solutions/meetily`) / Homebrew cask `meetily`
  （arm64-only）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.meetily.ai` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。全部近 5 个 release 非 prerelease。历史深处有一个裸 tag（`0.1.1`，无 v）——
v 锚定 pattern 拒读它；`/releases/latest` 反正只给最新 stable v-tag。

## 更新检测
- 源: `Zackriya-Solutions/meetily` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.4.0` → `0.4.0` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | Tauri updater 可能支持 | 无 | 不能 |
| 证据 | — | release 资产只有 dmg/exe/msi/latest.json，无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `meetily_{v}_aarch64.dmg`（arm64-only；x64 资产是 Windows 的
  setup.exe/msi）
- Pattern: `^meetily_[0-9.]+_aarch64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v0.4.0 挂载）: `com.meetily.ai` / `0.4.0`，Team
  `554AZZ38TB`，`spctl accepted / Notarized Developer ID`，arm64-only

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/Zackriya-Solutions/meetily/releases/latest → v0.4.0
# 挂载 meetily_0.4.0_aarch64.dmg → com.meetily.ai / 0.4.0
# channel-verify --check com.meetily.ai → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
