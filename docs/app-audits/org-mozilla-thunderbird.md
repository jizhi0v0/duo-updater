# Thunderbird

> 审计 2026-06-04 · 严格验证 + **修复完成**（4 个真实 bundle 跑 `channel-verify` 全绿）
> stable/beta/esr/nightly 全部正确路由；曾发现 beta/esr recipe 已坏，已用 RemotingName 修。
>
> **2026-08-30 复审 · beta / daily 的更新检测已修**。channel 路由一直是对的，
> 但**版本比较**在这两条 channel 上从来没能报出一次更新：`product-details` 只发
> marketing 串，而安装版整周期恒 `155.0`（daily 更是每天出构建、全叫 `157.0a1`）。
> 两条 channel 改读 `aus.thunderbird.net`，比较 `application.ini` 的 `BuildID`。
> stable / esr 不受影响。与 Firefox 同一根因、同一次修复，见
> [`org-mozilla-firefox.md`](org-mozilla-firefox.md)（锚点的实测约束写在那边，不重复）。
> 真实 bundle 验证证据见下文「如何复验」。

## 基本信息
- Bundle ID: `org.mozilla.thunderbird`
- Team ID: `43AQ936H96`（与 Firefox / Mozilla 同签名）
- 观测版本（2026-08-30，各 channel 官方 dmg 挂载后直读）:
  | Channel | `CFBundleShortVersionString` | `CFBundleVersion` | `application.ini` `BuildID` |
  |---|---|---|---|
  | stable  | `154.0`   | `15426.8.18` | `20260818021538` |
  | beta    | `155.0`   | `15526.8.26` | `20260826184332` |
  | daily   | `157.0a1` | `15726.8.29` | `20260829100815` |

  Thunderbird beta 与 Firefox beta 同版本号（`155.0b5`）但**不是同一次构建** ——
  `BuildID` 分别是 `20260826184332` 和 `20260826090609`。
- 自更新机制: Mozilla 自研更新器（Balrog/AUS，非 Sparkle）—— `SUFeedURL` 不存在
- Homebrew cask: `thunderbird`，**`auto_updates: true`** → `HomebrewCaskSource` 返回 nil，
  穿透到 VendorProbe（cask 只是元数据，不是检测通道）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

> ✓ = 已验证可用  ○ = 可接入(未实现)  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —(auto)  | —   | —      | ✓           |
| **beta**     | —       | —        | —   | —      | ✓（独立 bundle id `…thunderbirdbeta`）|
| **esr**      | —       | —        | —   | —      | ✓（RemotingName 检测）|
| **nightly**  | —       | —        | —   | —      | ✓（Daily，独立 bundle id）|

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**
（Sparkle 无；Homebrew `auto_updates` 让位；无 MAS / GitHub 源）。

## Channel 详情（真实 bundle 实测，非 JSON 推断）

**修复后**：channel 由 `ReleaseChannel.detect()` 最高优先级的 Mozilla `RemotingName`
信号判定（`AppScanner` 从 `Contents/Resources/application.ini` 读取，每个 Mozilla 构建
烤死、不启动即可读）。product-details JSON 的 `…esr`/`…b3` 后缀**不进**安装包的
`CFBundleShortVersionString`，所以旧的版本后缀检测对 beta/esr 失效——已不再依赖它。

| Channel | 真实 Bundle ID | 真实短版本 | `RemotingName` | detect() 结果 | recipe 触发？ |
|---------|---------------|-----------|----------------|--------------|--------------|
| stable  | `org.mozilla.thunderbird`       | `151.0.1` | `thunderbird`         | `stable` ✓ | ✓ |
| esr     | `org.mozilla.thunderbird`       | `140.11.1`（无 esr） | `thunderbird-esr` | `esr` ✓ | ✓（RemotingName，不再被推 stable） |
| beta    | `org.mozilla.thunderbirdbeta`   | `152.0`（无 b3） | `thunderbird-beta` | `beta` ✓ | ✓（recipe bundle id 已改对） |
| nightly | `org.mozilla.thunderbird-daily` | `153.0a1` | `thunderbird-nightly` | `nightly` ✓ | ✓ |

> 四个真实 bundle 都跑过 `channel-verify` 实测确认。nightly 的 `a1` 后缀是唯一**没被**
> 安装包剥掉的（版本后缀检测对它仍成立），但现在统一由 RemotingName 主判，更稳。

## 更新检测

**两个源，按 channel 分工**，与 Firefox 完全同构。

### stable / esr — `product-details`

- 端点: `https://product-details.mozilla.org/1.0/thunderbird_versions.json`
- stable `LATEST_THUNDERBIRD_VERSION` = `154.0`，== 安装版短版本 ✓
- esr `THUNDERBIRD_ESR` = `140.14.1esr`，比安装版 `140.14.1` 多一截后缀；比较器把预发布
  排在正式版之下，所以不会误报，真正升版仍比得出来 ✓

### beta / daily — AUS（`aus.thunderbird.net`）

`product-details` 在这两条 channel 上结构性不可用（安装版短版本整周期冻住，daily 更是
每天一个 build 全叫 `157.0a1`）。改读 app 自己的更新服务：

```
https://aus.thunderbird.net/update/6/Thunderbird/<Version>/<BuildID>/Darwin_aarch64-gcc3/en-US/<channel>/Darwin%2025.0.0/default/default/default/update.xml
```

- **host 用 Thunderbird 自己的**。`application.ini` 的 `[AppUpdate] URL` 写的是
  `aus.thunderbird.net`，它 302 到 `aus5.mozilla.org` 上的同一条路径 —— 两边今天回的
  字节一样。走 Thunderbird 自己那个：万一两者将来分家，站在会保持正确的那一侧。
- **daily 的 channel token 是 `nightly`**，不是 `daily`。
- 比较键 = `buildID`（`versionIsBuild: true` + `buildNamespace: .vendor`）；显示串取自
  `<patch>` 的 `product=thunderbird-155.0b5-complete`，daily 直接用 `displayVersion`。
  显示串的形式是硬约束：beta 的 `ChangelogRecipe` 用它套 `/155.0beta/releasenotes/`。
- 锚点写死，实测约束与退化如何被抓到，见 Firefox 那份的「锚点是写死的」。

## Changelog
- 来源: 三条结构化 ChangelogRecipe（stable、ESR、beta），都按版本套
  `https://www.thunderbird.net/en-US/thunderbird/{version}/releasenotes/`，每页一个版本
  （`maxEntries: 1`）；ESR 补回 `esr` 后缀，beta 去掉 `bN` 再加 `beta`，读整个周期的累积页
  （`urlVersionToken`）。daily 没有 ChangelogRecipe（理由见 recipe 注释）。
  stable、beta、ESR 三条 probe recipe 的 `changelogURL` 仍指向
  `https://www.thunderbird.net/thunderbird/releases/`
- 跟随 channel: 是（stable 与 ESR 同一个 bundle id，靠 recipe 的 `channel` 分开；beta 有自己的 bundle id）
- Recipe 状态: 已有（`5ff7b648`，2026-06-05）
- 更正 2026-09-15：本节原写「来源: 无结构化 ChangelogRecipe」「跟随 channel: 否（一个 releases 页覆盖全部
  channel）」「Recipe 状态: 不需要」。这几句随 2026-06-04 的审计写下（`068d8239`）时成立，次日 `5ff7b648`
  加了这三条 ChangelogRecipe 之后就不成立了；`6d4ffe79`（2026-08-27）发布审计文档时原样带了过来。

## 一键安装
- 状态: **已接入**，best-effort 就地 dmg 替换，叠在 Thunderbird 自己的更新器之上
  （Team `43AQ936H96`）。此前本节记为「仅检测」、并称「三条 recipe 均无安装链」——
  两句都已不成立，recipe 带 `install: VendorInstallSpec`。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- ⚠️ 与 Firefox 同理：Mozilla 更新器不是 Squirrel/Sparkle，`SelfUpdaterStaging` 不覆盖它，
  唯一的闸是 `vendorInstallPolicy`。
- 格式: dmg（官网直发）
- 阻塞: 无需求——自更新器接管。

## 已修（2026-06-04）
1. `ReleaseChannel.detect()` 加最高优先级 `mozillaRemotingName` 信号；`AppScanner`
   对 `org.mozilla.*` app 读 `application.ini` 的 `RemotingName`。
2. beta recipe `bundleID` 改 `org.mozilla.thunderbirdbeta`。
3. esr 不再误判 stable → 跨 channel 误推已消除。
4. 同根问题的 **Firefox** 也一并修了（beta/esr/devedition），见
   [`docs/app-audits/org-mozilla-firefox.md`](org-mozilla-firefox.md)。
5. 加了单测 `mozillaRemotingNameIsAuthoritative` + `scannerTagsMozillaChannelViaRemotingName`；
   270 个 core 测试全过。

## 已修（2026-08-30）
- beta / daily 的版本源 `product-details` → `aus.thunderbird.net`，比较键换成
  `application.ini` 的 `BuildID`。
- 2026-06-04 那条「若要周期内检测需用 `application.ini` 的 `BuildID`（单调递增）——
  新机制，暂不做」当时就写对了修法，只是把远程侧当成了不存在。远程侧一直在
  `application.ini` 自己的 `[AppUpdate] URL` 里。
- 同一次改动里 daily 才第一次被记下来：2026-06-04 把「远程 == 安装版」记成了 ✓
  （确实没有幽灵更新），没有往下推出「因此新构建永远看不见」这一步。

## 已知限制
- **alpha (`54.0a2`)**：`LATEST_THUNDERBIRD_ALPHA_VERSION` 是陈旧冻结值，`detect()` 把
  `a` 后缀统一归 `.nightly`，不单独覆盖。
- **AUS 不发布发布时间**，这两条 channel 的 Release Log 仍只有"我们何时看见"。
- **一键安装仍然装 `-latest`**，不是 AUS `<patch>` 里的 `.mar`（我们不解析那个格式）。
- 锚点会退化，但退化会表现为版本回退、被 baseline 抓到 —— 详见 Firefox 那份。

## 部署提醒
- 改的是 core 的扫描/检测逻辑。菜单栏 App 要 `xcodebuild` 重建才会生效（`swift test`
  只编 core 包，不更新 app 二进制）。

## 如何复验

`channel-verify` 对**真实 bundle** 跑生产 `ReleaseChannel.detect()` + `AppScanner` 的
`application.ini` 读取 + `VendorProbeSource` + `UpdateChecker.evaluate()`（不是重实现）。
原始 channel 验证 2026-06-04；检测修复 2026-08-30。

```
# 官方 dmg：https://download.mozilla.org/?product=thunderbird{,-beta,-esr,-nightly}-latest&os=osx&lang=en-US
swift run --package-path application-test channel-verify /tmp/tb.dmg        --expect stable
swift run --package-path application-test channel-verify /tmp/tb-esr.dmg    --expect esr
swift run --package-path application-test channel-verify /tmp/tb-beta.dmg   --expect beta
#   → BuildID 20260826184332 ／ latest 155.0b5 ／ verdict up to date
swift run --package-path application-test channel-verify /tmp/tb-daily.dmg  --expect nightly
#   → BuildID 20260829100815 ／ latest 157.0a1 ／ verdict up to date
```

想看红：从 `https://archive.mozilla.org/pub/thunderbird/nightly/<年>/<月>/` 取前一个
build 的 dmg，同一个 `157.0a1` 会判出 UPDATE。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-mozilla-thunderbird.swift — Release / ESR VendorProbe（开头的说明）

转引自 recipe 注释，未复测。整段原文；代码里把 "(verified 2026-06-17: thunderbird-latest → 152.0, …)" 改成 "(checked for all four product codes 2026-06-17; History has the versions)"，其余原样，重新折行。

Thunderbird — same Mozilla `product-details` mechanism for Release and
ESR; Beta and Daily go to `aus.thunderbird.net` for the same reason the
Firefox pre-release channels do (see that block). Channel routing
is by `application.ini` RemotingName (see `ReleaseChannel`), NOT the
version suffix: the installed `CFBundleShortVersionString` DROPS the
`b`/`esr` suffix (verified on real bundles 2026-06-04). Bundle ids differ
per channel — Release & ESR share `org.mozilla.thunderbird`, Beta is
`org.mozilla.thunderbirdbeta`, Daily is `org.mozilla.thunderbird-daily`.
The `product-details` probes still capture the feed's full `esr` form: it
sorts as a pre-release (< the suffix-less installed version) so it never
phantoms; a real bump (140.11.1→140.12.0esr) still compares newer.
One-click: Mozilla's `download.mozilla.org/?product=…-latest&os=osx`
302-redirects to the per-channel `.dmg` on its CDN (verified 2026-06-17:
thunderbird-latest → 152.0, -beta-latest → 152.0b4, -esr-latest →
140.12.0esr, -nightly-latest → 154.0a1). Every channel is signed by
Mozilla Corporation (Team `43AQ936H96`), so the VendorInstaller same-Team
gate is satisfied and fails closed if Mozilla ever rotates. Best-effort
in-place dmg swap on top of Thunderbird's own self-updater.

### Recipes/org-mozilla-thunderbird.swift — beta ChangelogRecipe（按周期取页）

转引自 recipe 注释，未复测。整段原文。"~41 items" 是没写日期的条数（引入它的提交是 `5ff7b648`，2026-06-05），搬到这里；"`source` is the current cycle page" 迁移时已不成立，代码里改写了，见下面的更正。

Thunderbird Beta — its own bundle id (`org.mozilla.thunderbirdbeta`),
version-templated like the others. The notes URL is keyed by MAJOR, not
build: `/152.0beta/releasenotes/` is one cumulative page for the whole
152 beta cycle (b1→b2→…, several "What’s Fixed" sections under one
"152.0beta" heading, ~41 items). `urlVersionToken` drops the bN build
suffix and appends "beta" (152.0 / 152.0b3 → 152.0beta), so the template
auto-tracks the current cycle with no pin to bump. `source` is the
current cycle page as a fallback only.

更正 2026-09-14（13:59–14:01 UTC，只读 GET，不跟随重定向）：`source` 仍是 `/152.0beta/releasenotes/`（`Recipes/org-mozilla-thunderbird.swift:161`），而当前 beta 周期已是 156：`product-details.mozilla.org/1.0/thunderbird_versions.json` 的 `LATEST_THUNDERBIRD_DEVEL_VERSION` 是 `156.0b3`；`/en-US/thunderbird/156.0beta/releasenotes/` 200，标题 "Version 156.0beta | Released August 31, 2026"；`/152.0beta/releasenotes/` 仍 200（"Released May 21, 2026"）。代码里改成：`source` 是某一个固定周期的页（152.0beta），只作兜底。
