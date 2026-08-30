# DuoPaste

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel，ChannelBinding channel-tag；无 ChangelogRecipe**

## 基本信息
- Bundle ID: `io.duopaste.daemon`（两 channel **共用**）
- 自更新机制: Sparkle（单一 appcast，`<sparkle:channel>beta</sparkle:channel>` 标记 beta 条目）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(channel-tag) | — | — | — | — |
| **beta**     | ✓(channel-tag) | — | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 设置 `channel`，SparkleAppcastSource 筛选 `<sparkle:channel>` 标签）

## Channel 详情（Pattern C — 共享 bundle id，channel-tag 过滤）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.duopaste.daemon` | 共享 | `sparkleIncludePrereleases = false` | 仅接受无 channel 标签条目 | ✓ |
| beta    | `io.duopaste.daemon` | 共享 | `sparkleIncludePrereleases = true`  | 接受 `<sparkle:channel>beta</sparkle:channel>` 条目 | ✓ |

`DuoPasteChannel.resolveCurrent()` 读 `CFPreferencesCopyAppValue("sparkleIncludePrereleases", "io.duopaste.daemon")` → Bool。no feedOverride（appcast URL 不变；channel-tag 过滤靠 SparkleAppcastSource 逻辑）。

## Changelog
- 无 ChangelogRecipe
- ○ 可加（DuoPaste 有 changelog 页面，待调研）

## 一键安装
- Sparkle 自更新

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`，对真实 DuoPaste bundle）。`sparkleIncludePrereleases=1` 且 bundle 是 `…-beta` 构建时判定为 **beta**；appcast 当前仅 `<sparkle:channel>beta` 项，head=0.1.1251-beta=installed。VendorProbe 故意无应答（机制是 channel-tag Sparkle）。**stable 也已本机验证**（`sparkleIncludePrereleases=false` 时 `--scan` 结果=stable；该偏好默认值为 1）。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan io.duopaste.daemon --expect beta
```

## 端点

- appcast 托管在 `raw.githubusercontent.com/jizhi0v0/duo-paste-releases`。
