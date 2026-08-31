# GitHub Copilot for Xcode

## 基本信息
- Bundle ID: `com.github.CopilotForXcode`
- Team ID: `VEKTX9H2N7` (GitHub)
- 观测版本: `0.51.0`（short == build）
- 自更新机制: **Sparkle**（`SUFeedURL = https://githubcopilotide.z13.web.core.windows.net/appcast.xml`）
- 分发: Azure 静态站点（`githubcopilotide.z13.web.core.windows.net`，域名已固定为该 IP 直连
  形式）+ Homebrew cask `github-copilot-for-xcode`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable**     | ✓   | — (`auto_updates`) | — | — | — |
| **prerelease** | ✓   | —        | —   | —     | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe；两轨都靠 feed 里的 `<sparkle:channel>` 标记分轨）。

## Channel 详情

| Channel     | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|-------------|-----------|----------|---------|---------|------|
| stable      | `com.github.CopilotForXcode` | 共享 | — | default（无标记） | ✓ |
| prerelease  | `com.github.CopilotForXcode` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>prerelease</sparkle:channel>` | ✓ |

共享 bundle id。appcast 12 条（观测 2026-08-30）：default 轨道是正式版
（`0.51.0`），`prerelease` 轨道是 `0.51.182` 这类高频 build。两轨互不串：
`usableItems` 只允许装机 build 命中的那条 channel。stable 用户绝不收到
prerelease；prerelease 装机只收 prerelease。

一个值得写下的现象：prerelease 的 `shortVersionString` 是 `0.51.182`——把 build
编码进了 short。default 轨的 `0.51.0` 与它同域可比（`0.51.182 > 0.51.0`），但
channel 门先于比较，所以不构成跨轨推送。

## 更新检测
- 源: 泛化 Sparkle。`comparisonKey = version ?? shortVersionString`，两条轨都短串
  当道，同构无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: Sparkle inline（feed `<description>`）
- 跟随 channel: 是（按装机轨道）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Sparkle 原生路径，两轨各自 feed enclosure）
- 格式: `GitHubCopilotForXcode.dmg`（universal，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，0.51.0 挂载）: `com.github.CopilotForXcode` / `0.51.0`，
  `Developer ID Application: GitHub (VEKTX9H2N7)`，`spctl accepted / Notarized
  Developer ID`，universal（x86_64+arm64）

## 已知问题
- 用户如何在 app 内切入 prerelease 轨道（设置开关的位置）未查；对 duo-updater
  无影响——装机 build 命中哪条轨道就跟随哪条，与 Sparkle 自身语义一致。

## 如何复验
```
# GET https://githubcopilotide.z13.web.core.windows.net/appcast.xml
#   → 12 条，default=0.51.0，prerelease=0.51.182
# 挂载 GitHubCopilotForXcode.dmg → com.github.CopilotForXcode / 0.51.0
# channel-verify --check com.github.CopilotForXcode → winning=Sparkle, up to date
```

## 建议下一步
无。两轨检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
