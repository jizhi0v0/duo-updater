# CleanShot X

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**license-keyed feed（个性化 Sparkle），ChannelBinding + Changelog；非真正"多 channel"**

## 基本信息
- Bundle ID: `pl.maketheweb.cleanshotx`
- 自更新机制: Sparkle（个性化 appcast URL，URL 含 license key 参数）
- 分发模式: 订阅许可证（Setapp 或直购），feed 带 key → 服务商验证后返回该 license 对应版本

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(legit feed) | ✗(auto) | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 读 `activationKey` → 构造个性化 `feedOverride`）

## Channel 详情（Pattern B-variant — 共享 bundle id，license-keyed feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `pl.maketheweb.cleanshotx` | 单一 | — | `activationKey` 注入到 feed URL | ✓ |

CleanShot 不是真正的多 channel 应用——"channel"是订阅授权校验的副产品，不同 license key 对应不同授权等级，均指向同一 stable 版本。`CleanShotChannel.resolveCurrent()` 读 `activationKey`，拼入 legit appcast feed URL，`feedOverride` 绕过订阅检测死结。全链路不 log key。

## Changelog
- ChangelogRecipe ✓（`cleanshot.com/release-notes` 等，bundleID `pl.maketheweb.cleanshotx`）

## 一键安装
- Sparkle 自更新（个性化 feed `<enclosure>` 含下载链接）

## 已知问题
- 订阅到期后个性化 feed 可能拒绝返回版本（服务商侧校验），但 duo-updater 不处理订阅授权状态——降级为"无版本信息"而非误报更新

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。`activationKey` 存在 → 解析出个性化 legit feed，head=4.8.8=installed（消除 4.8.8↓3.7.1 幽灵降级）。key 是凭据、全程不打印。VendorProbe 故意无应答（机制是 license Sparkle feed）。证据：`application-test/records/pl-maketheweb-cleanshotx.md`
