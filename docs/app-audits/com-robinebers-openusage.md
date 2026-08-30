# OpenUsage

## 基本信息
- Bundle ID: `com.robinebers.openusage`
- Team ID: `QC3D3H67V9` (SUNSTORY LLC)
- 观测版本: `0.7.10` (build `550`)
- 自更新机制: **Sparkle**（Tauri 构建，`SUFeedURL = https://robinebers.github.io/openusage/appcast.xml`）
- 分发: GitHub Releases (`robinebers/openusage`) / 官网 / Homebrew cask `openusage`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe——`SUFeedURL` 在 Info.plist 里，feed 实测可解析）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.robinebers.openusage` | 单一渠道 | — | — | ✓ |

单渠道。GitHub 仓库发 `vX.Y.Z` 稳定 tag + `vX.Y.Z-beta.N` prerelease tag，但更新
走的是 appcast 不是 GitHub，所以 repo 里的 beta 不影响本源。

## 更新检测
- 源: 泛化 Sparkle。feed 51 条（观测 2026-08-30）。
- **一个值得写下的坑：beta 条目没有 `<sparkle:channel>` 标记**。`0.7.10-beta.3`
  (build 545) 就裸混在默认渠道里、排在 stable `0.7.10` (build 550) 之后。
  `usableItems` 只按 tag 过的 channel 过滤，所以默认渠道里的所有条目对所有人
  可见——这**正是 Sparkle 自己的语义**，也就是 app 自带更新器对用户做的事。
  `comparisonKey` 取 build（`sparkle:version` == `CFBundleVersion`），stable 的
  build 总比同代 beta 高，故 stable 安装拿到的是 stable 条目；下一轮 beta
  cycle 开启时（`0.7.11-beta.1` 的 build 会超过 550），stable 用户会看到
  beta——vendor 自己的 feed 对自家用户也这么干，我们镜像而非纠正。
- 版本方案: short `0.7.10` 与 build `550` 双轨；feed 两个字段都有，比较落在
  build（`comparisonKey`），显示走 short。build-only 变化的形状已由既有机制覆盖。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: Sparkle inline（feed 条目的 `<description>`）
- 跟随 channel: 不适用（单渠道）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Sparkle 原生路径；`SUPublicEDKey` 在包里 → EdDSA 校验 + 签名
  Team/bundle id 闸）
- 格式: feed enclosure 是 `OpenUsage-<ver>.dmg`（universal x86_64+arm64，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 公开条目，与 GitHub release 资产同源）
- 包验（2026-08-30，v0.7.10 挂载）: `com.robinebers.openusage` / short `0.7.10` /
  build `550`，`Developer ID Application: SUNSTORY LLC (QC3D3H67V9)`，
  `spctl accepted / Notarized Developer ID`，内嵌 `Sparkle.framework`

## 已知问题
- beta 条目裸混在默认渠道（见上）。不做纠正：加过滤会与 vendor 自家更新器的
  行为分叉，反而制造"我们比厂商更懂"的错位。
- `LSMinimumSystemVersion = 15.0`，低版本宿主由下载后检查兜住。

## 如何复验
```
# GET https://robinebers.github.io/openusage/appcast.xml → 51 条，head=0.7.10/550
# 挂载 OpenUsage-0.7.10.dmg → com.robinebers.openusage / 0.7.10 / 550
# channel-verify --check com.robinebers.openusage → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
