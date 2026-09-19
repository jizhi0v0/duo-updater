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

**顺带一个当时判成「不是 bug」的坑**：磁盘缓存按「目标版本」做 key，我们在 `22:40:53` 抓的时候
厂商还没发（页面 `last-modified` 是 `22:46:36`），于是 4.8.10 的内容被存进了 `5.0` 这个 key；
之后重新抓又撞上改版失败，而「重新校验失败就保留已画出的缓存」这条规则让它一声不吭——**标题 5.0、
列表停在 4.8.10，看起来完全正常**。当时的结论是「装上修复后一次命中就会重抓覆盖、自愈」。

那个结论只在「同一版本还会被重抓」的前提下成立，而这一版没有：见下一节，同一个坑 17 天后自己又
发作了一次。

### 2026-09-18：5.0.1 发布，同一个竞态又中一次（缓存已修）

recipe 没坏（live 页 `duo verify --changelog --only cleanshot` ✓，生产解析器读今天的页面第一条就是
5.0.1）。坏的是磁盘缓存：

| | 时刻(UTC) | |
|---|---|---|
| 我们抓 `cleanshot.com/changelog` | `2026-09-18 11:52:42` | 只此一次，7 天内再无第二次 |
| 页面 `last-modified` | `2026-09-18 12:01:56` | 晚 9 分钟 |

抓回来的页面最新条目是 5.0，被存进 `pl.maketheweb.cleanshotx__default__5.0.1.json`。**key 不会再变**
（feed 就停在 5.0.1），而「已发布版本的 changelog 不会变」这条不变式让这条记录永久有效——于是
5.0.1 的说明永远取不回来，标题 5.0.1、列表停在 5.0，无报错、无重试。5.0 那次是同一个机制，只是被
「页面改版」盖过去了，所以当时归到 recipe 上。

修法（`Changelog.carries(version:)` + `ChangelogDiskCache.provisionalWindow`）：一次抓取如果没带回
它被归档的那个版本，这条记录就是 **provisional**——照样存、照样画（这是当下能拿到的最好的说明），
但只在 6 小时内有效，过期即 miss，下一次 pre-warm/打开会重抓；抓到带 5.0.1 的页面就转正、恢复永久
有效。app 侧「本会话重校验一次」的欠账也改成同一个判据：抓回来没带这个版本 = 没还账。

判据的边界：「页面落后」有两种来源——真的发布慢（说明按周发、build 天天出），和号段比 build 粗
（Raycast 页面写 `2.4`，build 是 `2.4.1.0`；JetBrains Toolbox 写 `3.8.1`，build 是 `3.8.1.88030`，
均 2026-09-18 实测）。判据分不开这两种，也不需要分：两者都只是多一次重读，不会给错答案——但也因此
**不能**拿它去报「recipe 坏了」。按这个判据统计，会读作落后的缓存条目大致占四分之一。

## 一键安装
- Sparkle 自更新（个性化 feed `<enclosure>` 含下载链接）

## 已知问题
- 订阅到期后个性化 feed 可能拒绝返回版本（服务商侧校验），但 duo-updater 不处理订阅授权状态——降级为"无版本信息"而非误报更新

## channel-verify 状态
- ✓ **已验证 2026-06-04**（`--scan` 跑生产 `AppScanner`→`ChannelBinding`）。`activationKey` 存在 → 解析出个性化 legit feed，head=4.8.8=观测版本（消除 4.8.8↓3.7.1 幽灵降级）。key 是凭据、全程不打印。VendorProbe 故意无应答（机制是 license Sparkle feed）。证据见下文「如何复验」。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `VendorProbeSource`（不是重实现）。原始验证 2026-06-04。

```
swift run --package-path application-test channel-verify --scan pl.maketheweb.cleanshotx --expect stable
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/pl-maketheweb-cleanshotx.swift — ChangelogRecipe（号码到列表之间的间隙为什么要回火）

转引自 recipe 注释，未复测。整段原文；代码里 "All 102 blocks on today's page carry a `ul.changes`" 改成 "Every block on the page carried a `ul.changes` when checked (2026-09-01 and 2026-09-14; …)"（原句没写日期，引入它的提交是 `4a6c8d2d`，2026-09-01 16:40 UTC，同一注释开头写着 "Re-derived 2026-09-01"），"Costs 0.6 ms over the whole 183 KB page" 改成不带值的说法；其余原样，重新折行。本审计「2026-09-01：5.0 发布」一节也记着 102 这个数。

That gap is tempered rather than a plain `.*?` so it cannot leave the
block it started in. All 102 blocks on today's page carry a
`ul.changes`, so a lazy `.*?` finds the right one — but the day one of
them doesn't, a lazy gap silently pairs that version with the *next*
one's notes, which is the failure that reads as correct. Costs 0.6 ms
over the whole 183 KB page.

复测 2026-09-14（13:59 UTC，只读 GET `cleanshot.com/changelog`，Safari UA，解压后 183,359 B）：`<div class="version"` 共 102 个，102 个都带 `ul.changes`；recipe 的 entryPattern 解析出 102 条，第一条 `5.0`。耗时没有复测。
