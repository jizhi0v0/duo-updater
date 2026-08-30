# CodexBar

## 基本信息
- Bundle ID: `com.steipete.codexbar`
- Team ID: `Y5PE65HELJ` (Peter Steinberger)
- 观测版本: `0.56.1` (build `132`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml`）
- 分发: GitHub Releases (`steipete/CodexBar`) / Homebrew cask `codexbar`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | ○ | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe）。`ChangelogCatalog` 另有 GitHub releases 页兜底条目。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.steipete.codexbar` | 单一渠道 | — | — | ✓ |

单渠道。appcast 6 条（观测 2026-08-30），全部无 `<sparkle:channel>` 标记，
head = `0.56.1`。GitHub 发 `vX.Y.Z` 稳定 tag + CLI 的 Linux 资产，无 prerelease。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `0.56.1` 与 build `132` 双轨；feed 两个字段都有，比较落在
  build，显示走 short。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: Sparkle inline（feed `<description>`）；`ChangelogCatalog` 已另有
  `github.com/steipete/CodexBar/releases` 兜底条目
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Sparkle 原生路径）
- 格式: feed enclosure 是 `CodexBar-macos-universal-{v}.zip`（universal，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 条目与 GitHub release 资产同源）
- 包验（2026-08-30，v0.56.1 解包）: `com.steipete.codexbar` / short `0.56.1` /
  build `132`，`Developer ID Application: Peter Steinberger (Y5PE65HELJ)`，
  universal（x86_64+arm64）

## 已知问题
- 无。feed 未发现 beta 条目裸混（不像 OpenUsage）。

## 如何复验
```
# GET https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml → 6 条，head=0.56.1/132
# 解包 CodexBar-macos-universal-0.56.1.zip → com.steipete.codexbar / 0.56.1 / 132
# channel-verify --check com.steipete.codexbar → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
