# Firefox

> 审计 2026-06-04 · **严格验证后修复**（5 个真实 bundle 跑 `channel-verify`）。
> 早先"靠版本后缀区分 channel"的结论被实测推翻：beta/esr 安装把后缀剥掉了,曾被误判
> stable（esr 还会被跨 channel 推 stable）。已改用 `application.ini` 的 `RemotingName`。
>
> **2026-08-30 复审 · beta/dev-edition/nightly 的更新检测已修**。同一个"后缀被剥掉"
> 的事实还有第二个后果：`product-details` 只发 marketing 串，于是整个预发布周期
> 一次更新都报不出来（beta 恒 `155.0`，nightly 每天出构建却全叫 `157.0a1`）。
> 三条 channel 改读 Mozilla 自己的更新服务 `aus5.mozilla.org`，比较 `application.ini`
> 的 `BuildID`。stable / esr 不受影响，仍走 `product-details`。
> 真实 bundle 验证证据见下文「如何复验」。

## 基本信息
- Bundle ID: `org.mozilla.firefox`（Release/Beta/ESR 共享）；Developer Edition =
  `org.mozilla.firefoxdeveloperedition`；Nightly = `org.mozilla.nightly`
- Team ID: `43AQ936H96`
- 观测版本（2026-08-30，各 channel 官方 dmg 挂载后直读）:
  | Channel | `CFBundleShortVersionString` | `CFBundleVersion` | `application.ini` `BuildID` |
  |---|---|---|---|
  | stable      | `154.0.1` | `15426.8.24` | `20260824154132` |
  | beta        | `155.0`   | `15526.8.26` | `20260826090609` |
  | dev-edition | `155.0`   | `15526.8.26` | `20260826090609` |
  | nightly     | `157.0a1` | `15726.8.29` | `20260829211045` |

  两点值得记住：`CFBundleVersion` **是**逐 build 变的（`<major><yy>.<month>.<day>`），
  但**没有任何 Mozilla 端点发布它**，所以它不能当比较键；`BuildID` 两边都有。
  Developer Edition 与 Beta 同一次构建，`BuildID` 相同。
- 自更新机制: **Firefox 自带更新器**（无 Sparkle feed，`SUFeedURL` 不存在）。
  我们 **只检测、不一键** —— 升级交给 app 自身。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|                       | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-----------------------|---------|----------|-----|--------|-------------|
| **stable**            | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**              | —       | —        | —   | —      | ✓           |
| **esr**               | —       | —        | —   | —      | ✓           |
| **dev-edition**       | —       | —        | —   | —      | ✓           |
| **nightly**           | —       | —        | —   | —      | ✓           |

当前生效源（优先链中第一个应答的）: **VendorProbe**
（Firefox 无 Sparkle/MAS；Homebrew cask 是 `auto_updates`，`HomebrewCaskSource`
返回 nil 后落到 VendorProbe）。

## Channel 详情

这是**混合形态**：Release/Beta/ESR 是 Pattern C（同一 bundle id），Dev Edition 与
Nightly 是 Pattern A（各自独立 bundle id）。下表"真实短版本/RemotingName"列均为
2026-06-04 对官方 DMG 实测值。

| Channel | Bundle ID | 真实短版本 | `RemotingName` | detect() | 状态 |
|---------|-----------|-----------|----------------|----------|------|
| stable      | `org.mozilla.firefox`                  | `151.0.3` | `firefox`         | stable | ✓ |
| beta        | `org.mozilla.firefox`（共享）          | `152.0`（无 b7） | `firefox-beta`    | beta   | ✓ |
| esr         | `org.mozilla.firefox`（共享）          | `140.11.0`（无 esr） | `firefox-esr` | esr    | ✓ |
| dev-edition | `org.mozilla.firefoxdeveloperedition`  | `152.0`（无 b7） | `firefox-dev`     | dev    | ✓ |
| nightly     | `org.mozilla.nightly`                  | `153.0a1` | `firefox-nightly` | nightly| ✓ |

**Channel 检测**（`ReleaseChannel.detect`，第 0 级最高优先）：权威信号是
`Contents/Resources/application.ini` 的 `RemotingName`，`AppScanner` 对 `org.mozilla.*`
读取。**关键**：安装包的 `CFBundleShortVersionString` 把 `b`/`esr` 后缀剥掉了
（beta 报 `152.0`、esr 报 `140.11.0`），且 beta/esr 与 stable **共享** `org.mozilla.firefox`、
app 名都叫 "Firefox" —— 所以版本后缀/名字都不可靠,RemotingName 是唯一可靠信号。
Dev Edition 的 `RemotingName=firefox-dev` 归 `.dev`（旧"版本是 bN → 归 .beta"的假设也错了,
它报 `152.0`）。见 `ChannelGuardTests.mozillaRemotingNameIsAuthoritative`。

**多 recipe 路由**：`org.mozilla.firefox` 在 `VendorProbeRecipe` 里挂了 3 条 recipe
（stable/beta/esr），`VendorProbeSource` 按安装实例的 detected channel 选对应那条，
各自从同一份 JSON 抽不同字段。`ChannelGuardTests.firefoxSharedBundleResolvesPerChannel`
（live）断言三者解析出不同版本、且 b/esr 后缀正确。

## 更新检测

**两个源，按 channel 分工。** stable / esr 的 marketing 串每次发布都动，`product-details`
够用；beta / dev-edition / nightly 的 marketing 串在周期内是冻住的，只能读 build。

### stable / esr — `product-details`

- 源: `https://product-details.mozilla.org/1.0/firefox_versions.json`
- 字段映射（2026-08-30 复测）:
  | Channel | JSON key | 实测值 | 正则 |
  |---------|----------|-------|------|
  | stable | `LATEST_FIREFOX_VERSION` | `154.0.1` | `"LATEST_FIREFOX_VERSION"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"` |
  | esr    | `FIREFOX_ESR`            | `140.14.0esr` | `…"([0-9]+(?:\.[0-9]+)+esr)"` |
- **stable 版本方案 ✓ 安全**：endpoint 值 == 安装 app 短版本，普通 marketing 比较。
- **esr 带后缀、安装版剥后缀，但仍安全**：`140.14.0esr` 比 `140.14.0` 多一截，比较器把
  预发布串排在正式版**之下**，所以当前版判"已是最新"、不会误报；真正升版
  （`140.14.0esr`→`140.15.0esr`）仍比得出更新。
- `FIREFOX_ESR_NEXT`（当前 `153.1.0esr`）没跟 —— ESR 切版重叠期的双轨，低优先级。

### beta / dev-edition / nightly — AUS（`aus5.mozilla.org`）

`product-details` 在这三条 channel 上**结构性不可用**：它只发 marketing 串，而安装版的
`CFBundleShortVersionString` 已经把 `bN`/`aN` 之外的信息丢光了。

| Channel | 远程 `155.0b5` 之类 | 安装版短版本 | `isNewer` |
|---|---|---|---|
| beta / dev | `155.0b5` | `155.0` | **恒假**（预发布排在正式版之下） |
| nightly | `157.0a1` | `157.0a1` | **恒假**（逐字相同，一天一个 build） |

改读 app 自己的更新服务 —— `application.ini` 的 `[AppUpdate] URL` 指的就是它：

```
https://aus5.mozilla.org/update/6/Firefox/<Version>/<BuildID>/Darwin_aarch64-gcc3/en-US/<channel>/Darwin%2025.0.0/default/default/default/update.xml
```

应答（2026-08-30 实测，beta）：

```xml
<update appVersion="155.0" buildID="20260826090609" displayVersion="155.0 Beta 5" type="minor">
  <patch type="complete" URL="https://download.mozilla.org/?product=firefox-155.0b5-complete&os=osx&lang=en-US" …/>
```

- **比较键** = `buildID`，与安装版 `application.ini` 的 `BuildID` **逐字节相同**（五条
  channel 全部实测）。recipe 是 `versionIsBuild: true` + `buildNamespace: .vendor`，
  比的是 `InstalledApp.vendorBuildVersion`，**不是** `CFBundleVersion`。
- **显示串**取自 `<patch>` 的下载 URL（`product=firefox-155.0b5-complete`），不是
  Mozilla 自己的 `displayVersion="155.0 Beta 5"`。这不是审美：beta 的 changelog recipe
  用这个串套 URL（`urlVersionToken` 把 `155.0b5` 变成 `155.0beta`），喂进散文体会 404。
  nightly 的 `displayVersion` 本来就是 `157.0a1`，直接用属性。
- **channel token**：Firefox beta = `beta`，Developer Edition = **`aurora`**，nightly =
  `nightly`。product 一律是 `Firefox`。

#### 锚点是写死的，以及为什么这样是安全的

AUS 是**条件式端点**：它回答的是"比你报的这个 build 新的是什么"，你已经最新就返回空的
`<updates></updates>`。如果代入本机自己的 build，同一个空应答在用户机上是"已最新"、在
无 app 的扫描机上是"坏了" —— 一种形状两种含义，是检查静默死掉的标准路径。所以锚点写死：
每个用户和夜间扫描发的是**同一个请求**，永远期待有应答，空就是失败。

实测出的锚点约束（2026-08-30）：

| 约束 | 实测 |
|---|---|
| 版本必须 ≥ 最新的 watershed | `ver=124.0` → 回 125.0 Beta 9 的老 build；`125.0` 及以上 → 当前 build。nightly 无 watershed（`90.0a1` 仍给今天的 build） |
| build id 必须新于约 2023-01-15 | `20230115` → 空，`20230201` → 有应答；三条 channel 一致，与版本无关 |
| OS 版本不影响 | `Darwin 20` … `Darwin 27` 应答相同 |
| 无限流 | 连打 10 次，10 次相同 |

两个锚点最终都会退化 —— watershed 涨到 155.0 以上，或 build id 门槛涨过 2025。**两种
退化都会被抓到**，这正是写死锚点安全的原因：watershed 回的是**更老**的 build id，门槛
涨了则回空，两种情况下 `duo verify` 记的值都**往下走**，baseline 直接报版本回退。这一点
对被它取代的 marketing 锚点**不成立**，那才是这个方案以前被判死的原因。

nightly 的锚点特意用 `120.0a1` 而不是当前的 `157.0a1`：`RecipeSanity` 会在"抽出的版本
原样出现在请求 URL 里"时告警 —— 那正是"正则匹配到 URL 而不是响应体"的形状，不该让它
长期亮着。

## Changelog
- 来源: **WebView 内嵌官网 release notes**，每条 recipe 自带 `changelogURL`：
  stable `firefox/notes/`、beta `firefox/beta/notes/`、esr `firefox/organizations/notes/`、
  nightly `firefox/nightly/notes/`。
- 跟随 channel: **是**（每 channel 一个 notes 页）。
- Recipe 状态: **不需要**专门的 `ChangelogRecipe`（`ChangelogRecipe.swift` 无 Firefox 条目）。
  官网 notes 页直接 WebView 展示即可。

## 一键安装
- 状态: **已接入**，stable / beta / esr 三条 recipe 都带 `install: VendorInstallSpec`
  （`download.mozilla.org/?product=firefox{,-beta,-esr}-latest` 302 → dmg，Team `43AQ936H96`）。
  此前本节记为「仅检测（设计如此）」，是旧策略的残留。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- ⚠️ **Mozilla 的更新器既不是 Squirrel 也不是 Sparkle**，所以 `SelfUpdaterStaging` 那层
  「它已经下好了就让位」的保护**不覆盖 Firefox**（判据是 `Squirrel.framework` 是否存在）。
  这里唯一的闸就是 `vendorInstallPolicy`。
- `downloadURL` 是"去官网下载"的展示链接，不是安装产物；产物由 `install` 的重定向解析。

## 已修（2026-06-04）
- detect() 加 `RemotingName` 信号（修 beta 漏检 + esr 跨 channel 误推 stable）。
- dev-edition recipe channel `.beta` → `.dev`（实测 `RemotingName=firefox-dev`、版本 `152.0`）。
- 与 Thunderbird 同一根因、同一次修复，见 [`org-mozilla-thunderbird.md`](org-mozilla-thunderbird.md)。

## 已修（2026-08-30）
- beta / dev-edition / nightly 的版本源 `product-details` → `aus5.mozilla.org`，比较键
  从 marketing 串换成 `application.ini` 的 `BuildID`。**这是这三条 channel 从来没报出过
  一次更新的根因**，不是精度问题。
- 引擎侧新增 `InstalledApp.vendorBuildVersion` 与 `RemoteVersion.buildNamespace`：厂商
  自己的 build id 是**另一个命名空间**，跟 `CFBundleVersion` 比不会报错，只会永远给同一个
  答案。**没有**改写 `buildVersion`（即没有走 `AppScanner.buildVersionIsOverridden` 那条
  路）—— 那会让"磁盘 build vs 运行中 build"的重启角标对 Firefox 失效，而 Firefox 正是
  会后台自更新、然后需要重启的那类 app，那个角标就是为它准备的。
- 回归测试 `MozillaPreReleaseTests`（14 条，五条 channel 的真实响应体 + 真实 `BuildID`），
  其中 `theOldMarketingComparisonIsWhyThisExists` 把旧写法为什么恒假直接钉住。

## 已知限制 / 下一步
- **锚点会退化，但会被抓到**：watershed 涨过 `155.0`、或 AUS 的 build id 门槛涨过
  `20250101000000`，都会让 `duo verify` 记的值往下走 → baseline 报版本回退 → 换锚点。
  详见上面「锚点是写死的」。
- **AUS 不发布发布时间**：没有 `pubDate` 之类的字段，所以这三条 channel 的 Release Log
  仍然只有"我们何时看见"，没有"厂商何时发布"。
- `FIREFOX_ESR_NEXT` 当前为 `153.1.0esr`；ESR 重叠期双轨低优先级，暂不加。
- **一键安装仍然装 `-latest`**，不是 AUS `<patch>` 里那个 `.mar`。`.mar` 是 Mozilla 自己
  更新器用的增量/完整补丁格式，我们不解析它；`-latest` 的重定向产物就是 AUS 报的那个
  build（2026-08-30 五条 channel 逐一对过 `BuildID`）。
- **部署**：改的是 core 检测逻辑，菜单栏 App 需 `xcodebuild` 重建才生效。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `AppScanner` 的
`application.ini` 读取 + `VendorProbeSource` + `UpdateChecker.evaluate()`（全部是生产代码，
不是重实现）。原始 channel 验证 2026-06-04；检测修复的红→绿 2026-08-30。

```
# 各 channel 的官方 dmg：
#   https://download.mozilla.org/?product=firefox{,-beta,-devedition,-esr,-nightly}-latest&os=osx&lang=en-US
# 想要「落后一个 build」的样本，从 archive 取上一个：
#   https://archive.mozilla.org/pub/firefox/releases/155.0b4/mac/en-US/Firefox%20155.0b4.dmg
#   https://archive.mozilla.org/pub/firefox/nightly/2026/08/<stamp>-mozilla-central/firefox-157.0a1.en-US.mac.dmg

swift run --package-path application-test channel-verify /tmp/ff-155.0b4.dmg --expect beta
#   → BuildID 20260824090350 ／ verdict UPDATE 155.0 (20260824090350) → 155.0b5 (20260826090609)
swift run --package-path application-test channel-verify /tmp/ff-beta.dmg   --expect beta
#   → BuildID 20260826090609 ／ verdict up to date
swift run --package-path application-test channel-verify /tmp/ff-nightly-prev.dmg --expect nightly
#   → 同一天的两个 build，verdict UPDATE 157.0a1 (20260829093200) → 157.0a1 (20260829211045)
swift run --package-path application-test channel-verify /tmp/ff-esr.dmg    --expect esr
swift run --package-path application-test channel-verify /tmp/ff-dev.dmg    --expect dev
```

端点侧：

```
duo verify --only mozilla          # 9 条 vendor probe + 3 条 changelog
```

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-mozilla-firefox.swift — Release / ESR VendorProbe（开头的说明）

转引自 recipe 注释，未复测。整段原文；代码里两处带值的核对改成只留日期的 "(checked on real Beta and ESR bundles 2026-06-04; History has the versions)" 与 "(checked for all five product codes 2026-06-17; History has the versions)"，核对到的版本号搬到这里；其余原样。

Firefox — `product-details` carries Release and ESR. Beta, Developer
Edition and Nightly are NOT readable there and go to Mozilla's own
update service instead; see the block above those three recipes.
Release, Beta and ESR all ship as
`org.mozilla.firefox`; the channel is told apart by `application.ini`
RemotingName (`firefox`/`firefox-beta`/`firefox-esr` — see
`ReleaseChannel`), NOT the version suffix, because the installed
`CFBundleShortVersionString` DROPS the `b`/`esr` (verified on real
bundles 2026-06-04: Beta reports `152.0`, ESR `140.11.0`). So three
recipes share that bundle id and are picked by the install's detected
channel. Developer Edition (`org.mozilla.firefoxdeveloperedition`,
RemotingName `firefox-dev`) and Nightly (`org.mozilla.nightly`) have
their own ids. Where `product-details` IS the source (Release, ESR) the
captured version keeps the feed's `esr` form: it sorts as a pre-release
(never phantoms against the suffix-less install) while a real bump still
compares newer. One-click: identical mechanism to
Thunderbird — `download.mozilla.org/?product=…-latest&os=osx` 302→ the
per-channel `.dmg` (verified 2026-06-17: firefox-latest 152.0,
-beta-latest 152.0b10, -esr-latest 140.12.0esr, -devedition-latest
152.0b10, -nightly-latest 154.0a1). All Mozilla-signed (Team `43AQ936H96`),
so VendorInstaller's same-Team gate is satisfied / fails closed. Note Dev
Edition's product code is `firefox-devedition-latest` (its dmg lives under
/pub/devedition/, not /pub/firefox/).

### Recipes/org-mozilla-firefox.swift — 预发布渠道（为什么读不了 `product-details`）

转引自 recipe 注释，未复测。整段原文；代码里 "produced exactly zero update notices" 改成现在时 "gives"，句末括号改成 "(checked 2026-08-30 against real bundles; History has how both halves went unnoticed before that)"；beta 那半边 2026-06-04 被记成可接受限制、nightly 那半边一直没人注意到的经过搬到这里。

Beta, Developer Edition and Nightly cannot be tracked from
`product-details` at all, and the reason is on the DISK side, not the
feed's. An installed Firefox beta reports `CFBundleShortVersionString`
= "155.0" for the whole cycle — the `b5` is stripped — so a feed that
says "155.0b5" is measured against "155.0" and the tokenizer ranks the
pre-release BELOW the release: `isNewer` is false for every build of
the cycle. Nightly is worse: Mozilla ships one EVERY DAY and they are
all called `157.0a1`, so a ~4-week cycle produced exactly zero update
notices. (Measured 2026-08-30 against real bundles; the beta half was
recorded as an accepted limitation on 2026-06-04, the nightly half was
never noticed because "remote == installed" had been written down as a
*good* sign — no phantom updates — without taking the next step.)

### Recipes/org-mozilla-firefox.swift — 预发布渠道（`BuildID` 两边逐字节一致的核对）

转引自 recipe 注释，未复测。整段原文；连同它后面缩进的摘录（五个 channel 的 build id）。代码里留下的是结论（AUS 回的 `BuildID` 与包里的逐字节相同），核对的日期与做法挂在句末，build id 表搬到这里。

The bundle does carry a per-build number — `CFBundleVersion` is
`<major><yy>.<month>.<day>`, `15526.8.26` for 155.0b5 — but no Mozilla
endpoint publishes it, so it cannot be the comparison key. What both
sides DO share is `application.ini`'s `BuildID`: the app's own updater
asks `aus5.mozilla.org` (the URL is in `application.ini` itself, under
`[AppUpdate]`) and that service answers with the same `BuildID`, byte
for byte. Verified 2026-08-30 on all five channels by unpacking the
official dmg and diffing against the live response:

```
    FF beta        20260826090609    FF dev  20260826090609
    FF nightly     20260829211045    TB beta 20260826184332
    TB daily       20260829100815
```

### Recipes/org-mozilla-firefox.swift — 预发布渠道（锚点写死，以及锚点的实测约束）

转引自 recipe 注释，未复测。整段原文；连同它后面缩进的三条约束。代码里把 "Measured constraints on the anchor (2026-08-30):" 改成 "The anchor has to meet these constraints (measured 2026-08-30; History has the requests and answers):"，三条约束只留条件：watershed 的具体请求与应答（`ver=124.0` → 125.0 Beta 9、`125.0` 起给当前 build、nightly 的 `90.0a1`）、build id 下限的具体日期、`Darwin 20`…`27` 与「10 次相同请求、10 个相同应答」搬到这里；下限改写成「当时落在这个锚点的 2025-01-01 之下很远」。本审计「锚点是写死的」一节有同一组约束的中文表。

**The URL is a fixed anchor, and that is deliberate.** AUS is a
*conditional* endpoint: it answers "what is newer than the version and
build you name", so passing this machine's own build would make an empty
`<updates></updates>` mean "you are current" — and the same empty
response in a sweep, which has no installed app, would mean "broken".
One response shape, two meanings, is how a check goes quietly dead.
With a frozen anchor every user and the nightly sweep send the SAME
request, an answer is always expected, and empty is unambiguously a
failure. Measured constraints on the anchor (2026-08-30):

```
  • The version must be at or above Mozilla's newest *watershed*.
    `ver=124.0` is answered with the 125.0 Beta 9 watershed build;
    `125.0` and everything above gets the current one. Nightly has no
    watershed (`90.0a1` still gets today's build).
  • The build id must be newer than roughly 2023-01-15 — below that AUS
    answers nothing, on every channel, regardless of version.
  • The OS version does not affect the answer (`Darwin 20`…`27` all
    agree), and there is no throttling: 10 identical requests, 10
    identical answers.
```

### Recipes/org-mozilla-firefox.swift — 预发布渠道（锚点不能是问题的复印件）

转引自 recipe 注释，未复测。整段原文；代码里 "rather than the current 157.0a1" 改成 "rather than the current nightly version"（原句没写日期，引入它的提交是 `9e6bf386`，2026-08-30），括号里 "90.0a1 still gets today's build" 这条实测改成不带值的说法。

The five recipes' anchors are set so the answer can never be a copy of the
question: `RecipeSanity` warns when an extracted version appears
verbatim in the request URL, which is exactly the shape a pattern
matching the URL instead of the body would take. Nightly is anchored at
120.0a1 rather than the current 157.0a1 for that reason (nightly has no
watershed at all — 90.0a1 still gets today's build).
Thunderbird's `application.ini` names `aus.thunderbird.net`, which 302s
to the same path on `aus5.mozilla.org`. We follow Thunderbird's own host
rather than short-cutting to the redirect target: if the two ever
diverge, the app's URL is the one that stays right.
