# Fork

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel，ChannelBinding + Changelog，Sparkle feed-swap**

## 基本信息
- Bundle ID: `com.DanPristupov.Fork`（两 channel **共用**同一 bundle id）
- 自更新机制: Sparkle（两 channel 各自 feed，Info.plist `SUFeedURL` 永远指向 Developer/beta feed）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(feed-swap) | ✗(auto) | — | — | — |
| **beta**     | ✓(feed-swap) | ✗(auto) | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 提供 feedOverride）

## Channel 详情（Pattern B — 共享 bundle id，偏好切换 feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.DanPristupov.Fork` | 共享 | `applicationUpdateChannel` pref = 2 | feed-swap → `fork.dev/update/feed-stable.xml` | ✓ |
| beta    | `com.DanPristupov.Fork` | 共享 | pref ≠ 2（默认 unset = Developer） | feed-swap → `fork.dev/update/feed.xml` | ✓ |

Fork 命名反直觉：UI 称"Developer"为 beta 轨道（shipped default），"Stable（delayed 1 week）"为 stable。`applicationUpdateChannel = 2` → stable；unset/其他 → beta（Developer）。

## 更新检测
- `ForkChannel.resolveCurrent()` 读 `CFPreferencesCopyAppValue("applicationUpdateChannel", "com.DanPristupov.Fork")` → Int
- `ChannelBinding.resolve()` 返回 `ResolvedChannel(channel:, feedOverride:)`
- `SparkleAppcastSource` 使用 feedOverride 替换 plist `SUFeedURL`

## Changelog
- ChangelogRecipe ✓（`fork.dev/releasenotes`，`<h4 class="header4 release-notes">Fork <version></h4>` 结构）
- 仅一个 recipe，不分 channel（stable 和 beta 的 release notes 在同一页按版本降序）

## 一键安装
- Sparkle 自更新（stable/beta 各自 feed 带 `<enclosure>`），duo-updater 不额外覆盖安装

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。本机 `applicationUpdateChannel` 未设 → Fork 默认 **Developer/beta**（非 stable），developer feed head=2.67.0=installed。VendorProbe 故意无应答（机制是 Sparkle feed-swap）。**stable 也已本机验证**（临时写 `applicationUpdateChannel=2`→`--scan`=stable→删键还原为 unset/beta，Fork 未退出，end state==原始）。证据：`application-test/records/com-DanPristupov-Fork.md`
