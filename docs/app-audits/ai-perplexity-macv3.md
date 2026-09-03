# Perplexity (Personal Computer)

## 基本信息
- Bundle ID: `ai.perplexity.macv3`
- Team ID: `7S8W4W365S`
- 观测版本: `26.34.0` (build `87`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://macos-download.perplexity.ai/appcast.xml`）
- 分发: 官方 CDN `macos-download.perplexity.ai` + Homebrew cask `perplexity`
  （`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe）。注意与 registry 里既有 Perplexity 系条目区分：`ai.perplexity.comet`（Comet
浏览器）是另一个 bundle id。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.perplexity.macv3` | 单一渠道 | — | — | ✓ |

单渠道。appcast 单条（观测 2026-08-30），无 channel 标记。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `26.34.0` 与 build `87` 双轨；feed 两个字段都有，比较落在
  build，显示走 short。`sparkle:minimumSystemVersion` = 15.0，由下载后检查兜住。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: **没有**（已查，未找到可用来源）
- Recipe 状态: 无
- ⚠️ 2026-08-31 更正：原先写「Sparkle inline（feed `<description>`）」，是错的。
  feed 只有 1 条且**不带** `<description>`、不带 `sparkle:releaseNotesLink`；真包跑
  生产链 `releaseNotesHTML` 0 字符、`changelogURL` nil。这个 app 现在没有任何更新说明。
- 查过并排除的：`docs.perplexity.ai/docs/resources/changelog` 是 **API 的** changelog，
  和桌面端不是一回事，接上去会给用户看无关内容。
- 同厂的 Comet（`ai.perplexity.comet`，独立 bundle、既有 VendorProbe + 一键）**也没有**
  changelog，同一个缺口。要补得先找到 Perplexity 桌面端的公开发布说明面。

## 一键安装
- 状态: **支持**（Sparkle 原生路径）
- 格式: feed enclosure 是版本无关的 `Perplexity.dmg`（官方 CDN）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，26.34.0 挂载）: `ai.perplexity.macv3` / `26.34.0` / build
  `87`，Team `7S8W4W365S`，notarized

## 已知问题
- 历史（2026-08-17 审计）：当时的 dmg 是 `Unnotarized Developer ID`，签名闸挡一键，
  故早期结论是 detection-only。**2026-08-30 复核：vendor 已恢复公证**（`spctl
  accepted / Notarized Developer ID`），一键现在可用——本审计据此升级为支持一键。

## 如何复验
```
# GET https://macos-download.perplexity.ai/appcast.xml → 1 条，head=26.34.0/87
# 挂载 Perplexity.dmg → ai.perplexity.macv3 / 26.34.0 / 87
# channel-verify --check ai.perplexity.macv3 → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
