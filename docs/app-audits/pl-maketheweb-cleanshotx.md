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
- ChangelogRecipe ✓（`cleanshot.com/changelog`，bundleID `pl.maketheweb.cleanshotx`）

### 2026-09-01：5.0 发布，页面结构重建（recipe 已修）

厂商随 5.0 把 changelog 页重排了，旧 pattern **一条都匹配不上**（`duo verify` 报
`noEntriesExtracted`）。三处同时变了：

| | 旧 | 新 |
|---|---|---|
| 日期位置 | 版本号**之后** | 版本号**之前** |
| 版本号外层 | 直接在 `div.version` 下 | 多了 `div.content` > `div.topbar` |
| 版本号→列表之间 | 紧邻 | 功能版会插 `p.change-intro` + 两个 `a.video-link` |

现在的结构：

```html
<div class="version"><div class="date">1 September, 2026</div>
  <div class="content"><div class="topbar">
    <div class="number">5.0</div><div class="text-badge">Major Update</div></div>
    <p class="change-intro">…</p><a class="video-link">…</a>   ← 仅功能版
    <ul class="changes"><li class="change">…</li>…</ul></div></div>
```

版本号到列表之间用 tempered gap（`(?:(?!<div class="version").)*?`）而不是 `.*?`：当天页面上
102 个 block 全都有 `ul.changes`，懒惰匹配也对；但只要有一个 block 没有列表，懒惰匹配会**静默地
把下一版的更新说明挂到这一版名下**。回归测试见 `CleanShotChangelogRecipeTests`。

**顺带一个不是 bug 的坑**：磁盘缓存按「目标版本」做 key，我们在 `22:40:53` 抓的时候厂商还没发
（页面 `last-modified` 是 `22:46:36`），于是 4.8.10 的内容被存进了 `5.0` 这个 key；之后重新抓
又撞上改版失败，而「重新校验失败就保留已画出的缓存」这条规则让它一声不吭——**标题 5.0、列表停在
4.8.10，看起来完全正常**。装上修复后一次命中就会重抓覆盖、自愈。

## 一键安装
- Sparkle 自更新（个性化 feed `<enclosure>` 含下载链接）

## 已知问题
- 订阅到期后个性化 feed 可能拒绝返回版本（服务商侧校验），但 duo-updater 不处理订阅授权状态——降级为"无版本信息"而非误报更新

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。`activationKey` 存在 → 解析出个性化 legit feed，head=4.8.8=installed（消除 4.8.8↓3.7.1 幽灵降级）。key 是凭据、全程不打印。VendorProbe 故意无应答（机制是 license Sparkle feed）。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan pl.maketheweb.cleanshotx --expect stable
```
