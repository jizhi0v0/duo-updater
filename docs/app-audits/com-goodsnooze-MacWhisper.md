# MacWhisper

## 基本信息
- Bundle ID: `com.goodsnooze.MacWhisper`
- Team ID: `8Q7TMPA46J`
- 观测版本: `14.8` (build `1480`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://macwhisper-site.vercel.app/appcast.xml`）
- 分发: 官方 CDN `cdn.macwhisper.com` / Homebrew cask `macwhisper`

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
| stable  | `com.goodsnooze.MacWhisper` | 单一渠道 | — | — | ✓ |

单渠道。appcast 210 条（观测 2026-08-30），全部无 `<sparkle:channel>` 标记，
head = `14.8/1480`。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short `14.8` 与 build `1480` 双轨；feed 两个字段都有，比较落在
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
- 格式: feed enclosure 是 `MacWhisper-{build}.zip`（cdn.macwhisper.com）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，MacWhisper-1480.zip 解包）: `com.goodsnooze.MacWhisper` /
  short `14.8` / build `1480`，Team `8Q7TMPA46J`，notarized

## 已知问题
- 无。

## 如何复验
```
# GET https://macwhisper-site.vercel.app/appcast.xml → 210 条，head=14.8/1480
# 解包 MacWhisper-1480.zip → com.goodsnooze.MacWhisper / 14.8 / 1480
# channel-verify --check com.goodsnooze.MacWhisper → winning=Sparkle, up to date
```

## 建议下一步
无。检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
