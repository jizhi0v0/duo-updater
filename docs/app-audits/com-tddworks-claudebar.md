# ClaudeBar

## 基本信息
- Bundle ID: `com.tddworks.claudebar`
- Team ID: `Y5856NSDZU` (renwei han)
- 观测版本: `0.4.85` (build `203`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://tddworks.github.io/ClaudeBar/appcast.xml`）
- 分发: GitHub Releases (`tddworks/ClaudeBar`) / Homebrew cask `claudebar`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | —        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.tddworks.claudebar` | 单一渠道 | — | — | ✓ |

单渠道。appcast 仅 1 条（观测 2026-08-30），无 channel 标记。GitHub 发 `vX.Y.Z`
稳定 tag，无 prerelease。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `0.4.85` 与 build `203` 双轨；feed 两个字段都有，比较落在
  build，显示走 short。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: Sparkle inline（feed `<description>`）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Sparkle 原生路径）
- 格式: feed enclosure 是 `ClaudeBar-{v}.zip`（universal，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 条目与 GitHub release 资产同源）
- 包验（2026-08-30，v0.4.85 解包）: `com.tddworks.claudebar` / short `0.4.85` /
  build `203`，`Developer ID Application: renwei han (Y5856NSDZU)`，
  `spctl accepted / Notarized Developer ID`，universal（x86_64+arm64）

## 已知问题
- 无。

## 如何复验
```
# GET https://tddworks.github.io/ClaudeBar/appcast.xml → 1 条，head=0.4.85/203
# 解包 ClaudeBar-0.4.85.zip → com.tddworks.claudebar / 0.4.85 / 203
# channel-verify --check com.tddworks.claudebar → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
