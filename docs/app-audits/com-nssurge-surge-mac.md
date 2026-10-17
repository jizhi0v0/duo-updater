# Surge

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta 两 channel，ChannelBinding，Sparkle feed-swap；无 ChangelogRecipe**

## 基本信息
- Bundle ID: `com.nssurge.surge-mac`（两 channel **共用**）
- 自更新机制: Sparkle（Info.plist `SUFeedURL` 指向 release feed；运行时内部构造 `surge-data-pipe:///appcast.xml?beta=<0|1>` 请求——并非 http，外部无法直接访问）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(feed-swap) | ✗(auto) | — | — | — |
| **beta**     | ✓(feed-swap) | ✗(auto) | — | — | — |

当前生效源: **SparkleAppcastSource**（ChannelBinding 提供 feedOverride；Surge 的内部 `surge-data-pipe://` scheme 不经外部 HTTP，故 duo-updater 读公开 feed URL 而非 plist 中的 `SUFeedURL`）

## Channel 详情（Pattern B — 共享 bundle id，偏好切换 feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.nssurge.surge-mac` | 共享 | `IncludeBetaBuilds = false` in KDDefaults.plist | feed-swap → `nssurge.com/mac/latest/appcast-signed.xml` | ✓ |
| beta    | `com.nssurge.surge-mac` | 共享 | `IncludeBetaBuilds = true` in KDDefaults.plist  | feed-swap → `nssurge.com/mac/latest/appcast-signed-beta.xml` | ✓ |

`SurgeChannel.readIncludeBeta()` 读 `~/Library/Application Support/com.nssurge.surge-mac/KDDefaults.plist`（非 UserDefaults——Surge 自己管 plist）。文件缺失或 key 不存在时回落到 stable。

## Changelog
- 来源: Sparkle inline——feed 的 `<item>` 带 `<markdownDescription>`，由 `AppcastMarkdownParser` 转成结构化条目（不是 `<description>`，也不是 WebView）。stable feed 本次实测见下；beta feed 每条都带是 `acknowledged` 理由的说法，本次未复测。
- 无 ChangelogRecipe，也不需要：登记在 `ChangelogCoverage.acknowledged`（理由原文：Sparkle feeds carry inline markdownDescription notes on every item; the page is a JS shell）。`ChangelogCatalog` 另有 `nssurge.com/support/mac/release-notes`，只在 feed 没给 notes 时当 WebView 兜底页。
- 复测 2026-10-10（只读 GET `nssurge.com/mac/latest/appcast-signed.xml`，200，22,306 B）：22 个 `<item>`、22 个 `<markdownDescription>`，0 个 `<description>`。beta feed 这次没有请求。
- 早先这里写过「○ 可加（Surge changelog 在 `nssurge.com/mac/v5_changelog.html` 等页面，未实现）」，与上面三条不符，已改。

## 一键安装
- Sparkle 自更新

## 订阅门槛（2026-10-17）
- Surge 是订阅制：发布时间晚于订阅更新窗口的版本装上后打不开（Surge 自己的按钮变成「Renew Subscription…」）。
- 规则照 Surge 6.10.0 (12500) 自己的 `bestValidUpdateInAppcast:forUpdater:`：候选的 `dateString.integerValue < fusDate` 才可用。`fusDate` 存在 `~/Library/Application Support/com.nssurge.surge-mac` 的扩展属性 `com.nssurge.surge-mac.nsa.3` 里（JSON → `policy` base64 → JSON）。同一 policy 里的 `expiresOnDate` 是另一个时刻，不是这条规则。
- 实现：`SurgeSubscription` 读窗口（2026-10-17 起和 TablePlus 共用 `SubscriptionWindow`），`SparkleAppcastSource` 只从覆盖内的版本里挑，最新被拦下的版本挂在 `RemoteVersion.subscriptionHold` 上，行在动作列（✅ 的位置）显示橙色锁「Not covered by your subscription」，点开说明，不给 Update，`duo check` 的 status 后面带一句原因。读不到属性、格式变了、`<pubDate>` 解析不出日期时一律不提供更新版本（让用户去 Surge 里检查），不按 Surge 的 `integerValue`=0 放行。
- 续订：渠道偏好监听改成文件级 FSEvents（目录级流对被监听根目录自身的扩展属性改动没有事件，2026-10-17 实测），重检指纹带上订阅窗口，所以续订后会自动重检；Surge 启动/退出、回到 DuoUpdater 窗口这两个已有触发点也会重检。
- 真机 2026-10-17：`fusDate`=1792162109（2026-10-16 22:48 +0800），beta feed 6.11.0 发布于 1792168472 → 动作列显示锁，日志 `6.11.0 is not covered by the Surge subscription`（共用后措辞改为 `… is not covered by the subscription …`）。续订路径没有在真实授权上演练（不改用户的授权属性），只验了事件能到达 + 单测覆盖指纹变化。

## 已知问题
- Surge 运行时用内部 `surge-data-pipe://` scheme 绕过公开 feed URL，duo-updater 改读公开 appcast 而非拦截内部请求——两者版本应一致，但若 Surge 的内部参数与公开 feed 产生分歧时可能不同步

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。KDDefaults.plist `IncludeBetaBuilds=true` 时判定为 **beta**；beta feed head=6.6.0/11270=installed。VendorProbe 故意无应答（机制是 Sparkle feed-swap）。**stable 也已在真实 bundle 上验证**（该 flag 是 Surge 直读的文件、对运行进程不可见，所以无需退出进程即可验证：逐字节备份后改 `NO`，`--scan` 结果=stable，再还原原始字节，前后一致）。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan com.nssurge.surge-mac --expect beta
```
