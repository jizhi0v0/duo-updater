# VoiceInk

## 基本信息
- Bundle ID: `com.prakashjoshipax.VoiceInk`
- Team ID: `V6J6A3VWY2` (Prakash Joshi)
- 观测版本: `2.13` (build `213`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://beingpax.github.io/VoiceInk/appcast.xml`）
- 分发: GitHub Releases (`Beingpax/VoiceInk`) / Homebrew cask `voiceink`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.prakashjoshipax.VoiceInk` | 单一渠道 | — | — | ✓ |

单渠道。appcast 仅 1 条（观测 2026-08-30），无 channel 标记。GitHub 历史上唯一
prerelease（`v2.0-beta.3`）后跟了正式 `v2.0`——beta 未进 appcast。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `2.13` 与 build `213` 双轨（build = short 去点）；feed 两个
  字段都有，比较落在 build，显示走 short。tag 有两段号（`v2.1`），不影响——比较
  走 appcast 不碰 tag。

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
- 格式: feed enclosure 是 `VoiceInk.dmg`（版本号不进文件名；universal，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 条目与 GitHub release 资产同源）
- 包验（2026-08-30，v2.13 挂载）: `com.prakashjoshipax.VoiceInk` / short `2.13` /
  build `213`，`Developer ID Application: Prakash Joshi (V6J6A3VWY2)`，
  `spctl accepted / Notarized Developer ID`，universal（x86_64+arm64）

## 已知问题
- 无。

## 如何复验
```
# GET https://beingpax.github.io/VoiceInk/appcast.xml → 1 条，head=2.13/213
# 挂载 VoiceInk.dmg → com.prakashjoshipax.VoiceInk / 2.13 / 213
# channel-verify --check com.prakashjoshipax.VoiceInk → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
