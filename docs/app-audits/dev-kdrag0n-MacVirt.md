# OrbStack

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta/canary 三 channel 全覆盖（检测+一键+ChannelBinding+Changelog）**

## 基本信息
- Bundle ID: `dev.kdrag0n.MacVirt`（三 channel **共用**同一 bundle id）
- 自更新机制: Sparkle appcast（`appcast.new.xml`，Info.plist 无 `SUFeedURL`，手动保存）
- Team ID: `HUAQ24HBR6`（无 SUPublicEDKey，一键走 codesign path）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✗(无SUFeedURL) | ✗(auto) | — | — | ✓ |
| **beta**     | ✗(无SUFeedURL) | —       | — | — | ✓ |
| **canary**   | ✗(无SUFeedURL) | —       | — | — | ✓ |

当前生效源: **VendorProbe**（三 channel 均命中，appcast URL 相同，regex 各自锚定 `<sparkle:channel>` 标签）

## Channel 详情（Pattern C — 共享 bundle id，channel-tag）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `dev.kdrag0n.MacVirt` | 共享 | `OrbStackChannel` 读 `updates_optinChannel` pref | `<sparkle:channel>stable</sparkle:channel>` | ✓ |
| beta    | `dev.kdrag0n.MacVirt` | 共享 | 同上 → `.beta` | `<sparkle:channel>beta</sparkle:channel>` | ✓ |
| canary  | `dev.kdrag0n.MacVirt` | 共享 | 同上 → `.canary` | `<sparkle:channel>canary</sparkle:channel>` | ✓ |

`OrbStackChannel.resolveCurrent()` 读 `UserDefaults[updates_optinChannel]`（String `"stable"`/`"beta"`/`"canary"`），unreadable 时回落到 `.stable`。ChannelBinding 只设 `channel`，不设 `feedOverride`（appcast 固定不变；VendorProbeRecipe 已写死 URL + channel）。

## 更新检测
- 端点: `https://cdn-updates.orbstack.dev/arm64/appcast.new.xml`（三 channel 共用）
- versionPattern: `(?s)<sparkle:channel><tag></sparkle:channel>(?:(?!</item>).)*?OrbStack_v([0-9.]+)_`
- 旧 appcast.xml 冻结于 2.1.2，已弃用，勿混用

## Changelog
- ChangelogRecipe ✓（`docs.orbstack.dev/release-notes`）
- 无 channel 分支（stable/beta/canary 共用同一 release notes 页）

## 一键安装
- ✓ 三 channel 均支持（dmg，从同一 appcast 对应 channel 块提取 `<enclosure url>`）
- Team HUAQ24HBR6 门控

## channel-verify 状态
- ✓ **stable 已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。`updates_optinChannel` 未设 → **stable**；VendorProbe 应答 2.1.3=installed。**beta/canary 也已本机验证**（临时写 `updates_optinChannel`=beta/canary→`--scan`=beta/canary→删键还原为 unset/stable，OrbStack 未运行）→ 三 channel 全部本机验证 ✓。证据：`application-test/records/dev-kdrag0n-MacVirt.md`
