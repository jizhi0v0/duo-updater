# Helium

## 基本信息
- Bundle ID: `net.imput.helium`
- Team ID: `S4Q33XPHB4` (imput LLC)
- 观测版本: `0.16.2.1`（short == build）
- 自更新机制: 自研（无 `SUFeedURL`；release 资产里有 `-arm64.delta` 差分件）
- 分发: GitHub Releases (`imputnet/helium-macos`) / Homebrew cask `helium-browser`
  （`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.imput.helium` | 单一渠道 | — | tag 锚 `^X.Y.Z$`（无 v） | ✓ |

单渠道。**值得注意的陷阱**：repo 的 prerelease release（如 `0.16.1.1`）用的是
**纯数字 tag**，与 stable 同形——靠 GitHub 的 prerelease 标记区分。我们的
stable rule 走 `/releases/latest`（GitHub 定义上排除 prerelease），所以不会
读串；但任何想按 tag 形状过滤的代码在这里都不可靠。

## 更新检测
- 源: `imputnet/helium-macos` GitHub Releases，`/releases/latest`
- 版本方案: tag `0.16.2.1` → `0.16.2.1` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 客户端显然支持（自带 `.delta`） | 有 | 不能 |
| 证据 | — | release 资产含 `{from}-arm64.delta` 差分链（观测 2026-08-30） | 我们的安装路径不做二进制差分 |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `helium_{v}_arm64-macos.dmg`（`_x86_64-macos.dmg` 是 Intel 孪生）
- Pattern: `^helium_[0-9.]+_arm64-macos\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，0.16.2.1 挂载）: `net.imput.helium` / `0.16.2.1`，Team
  `S4Q33XPHB4`，`spctl accepted / Notarized Developer ID`

## 已知问题
- 无。delta 差分我们不用，但 release 里仍有一个全量 dmg，不影响一键。

## 如何复验
```
# GET https://api.github.com/repos/imputnet/helium-macos/releases/latest → 0.16.2.1
# 挂载 helium_0.16.2.1_arm64-macos.dmg → net.imput.helium / 0.16.2.1
# channel-verify --check net.imput.helium → winning=GitHub, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均已覆盖。
