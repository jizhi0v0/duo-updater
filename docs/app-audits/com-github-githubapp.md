# GitHub Copilot

## 基本信息
- Bundle ID: `com.github.githubapp`
- Team ID: `VEKTX9H2N7` (GitHub)
- 观测版本: `1.1.14`（short == build）
- 自更新机制: 自研（electron 系，无 `SUFeedURL`）
- 分发: GitHub Releases (`github/app`) / Homebrew cask `github-copilot-app`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.github.githubapp` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。repo 至今只发非 prerelease 的 `vX.Y.Z` tag；锚定 pattern 防未来
prerelease 在 list fallback 时被截成 stable。

## 更新检测
- 源: `github/app` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.1.14` → `1.1.14` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | release 资产只有 dmg/zip/tar.gz(+sig)，无 `.delta`（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `GitHub-Copilot-darwin-arm64.dmg`（文件名不带版本号）
- Pattern: `^GitHub-Copilot-darwin-arm64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v1.1.14 挂载）: `com.github.githubapp` / `1.1.14`，
  arm64-only dmg（darwin-x64.dmg 是另一个资产），`Developer ID Application:
  GitHub (VEKTX9H2N7)`，`spctl accepted / Notarized Developer ID`

## 已知问题
- 同一 release 同时发 `.zip`、`.tar.gz`(+`.sig`)、x64 dmg 以及 Windows/Linux
  资产——pattern 以 `-darwin-arm64\.dmg$` 收尾，只放行这一件。

## 如何复验
```
# GET https://api.github.com/repos/github/app/releases/latest → v1.1.14
# 挂载 GitHub-Copilot-darwin-arm64.dmg → com.github.githubapp / 1.1.14
# channel-verify --check com.github.githubapp → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
