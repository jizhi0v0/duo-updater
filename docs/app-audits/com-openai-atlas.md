# ChatGPT Atlas

## 基本信息
- Bundle ID: `com.openai.atlas`
- Team ID: `2DC432GLL2` (OpenAI)
- 观测版本: `1.2026.189.1` (build `20260724200710000`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://persistent.oaistatic.com/atlas/public/sparkle_public_appcast.xml`）
- 分发: 官方静态 CDN `persistent.oaistatic.com/atlas/public/` + Homebrew cask
  `chatgpt-atlas`（`auto_updates: true`）

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
| stable  | `com.openai.atlas` | 单一渠道 | — | — | ✓ |

单渠道。appcast 3 条（观测 2026-08-30），全部无 `<sparkle:channel>` 标记，
head = `1.2026.189.1`。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `1.2026.189.1`（四段：大版本.年份.序.补丁）与 build
  `20260724200710000`（日期+时间戳）双轨；feed 两个字段都有，比较落在 build，
  显示走 short。四段 short 由既有版本比较机制按段处理。

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
- 格式: feed enclosure 是 `ChatGPT_Atlas_Desktop_public_{short}_{build}.dmg`
  （版本化文件名，官方 CDN）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，1.2026.189.1 挂载）: `com.openai.atlas` /
  `1.2026.189.1`，Team `2DC432GLL2`，notarized

## 已知问题
- 无。

## 如何复验
```
# GET https://persistent.oaistatic.com/atlas/public/sparkle_public_appcast.xml
#   → 3 条，head=1.2026.189.1
# 挂载 ChatGPT_Atlas_Desktop_public_1.2026.189.1_….dmg → com.openai.atlas
# channel-verify --check com.openai.atlas → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
