# Bartender

审计日期 2026-10-10。Bartender 6 与 Bartender 7 共用一个 bundle id，是两个分别售卖的大版本；本文覆盖两者。

## 基本信息
- Bundle ID: `com.surteesstudios.Bartender`（6 与 7 相同；app 名分别是 `Bartender 6.app` / `Bartender 7.app`）
- Team ID: `24J875RH8J`（Bartender App LLC；6.6.2、7.0.4、7.0.5 三个真包相同，均 spctl「Notarized Developer ID」）
- 观测版本: 6.6.2（`CFBundleVersion` 662000）、7.0.4（700011）、7.0.5（700012）
- 自更新机制: Sparkle 2.6.4，两代 `SUPublicEDKey` 相同；**各自声明自己的 `SUFeedURL`**。两代 Info.plist 都是 `SUAllowsAutomaticUpdates = false`（`SUEnableAutomaticChecks` TRUE）：只自动检查，不静默下载、不在退出时安装，所以没有「自更新器暂存了包、等 app 退出」这一态。
  - 6.x: `https://www.macbartender.com/B2/updates/AppcastB6.xml`（307 到 `downloads.macbartender.com` 同路径）
  - 7.x: `https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml`
- `LSMinimumSystemVersion` 两代都是 14.0；但 7.0.0 的说明写明这一版只支持 macOS 27，7.0.5 的说明也说"requires macOS 27 or later"，厂商购买页写「Includes Bartender 6 for Tahoe, and 7 for Golden Gate」。feed 的 `sparkle:minimumSystemVersion` 是 `14.0`，不表达这条限制。
- 嵌套: `Contents/XPCServices/Bartender Service.xpc`、`Sparkle.framework/Updater.app`，两代一样。

## Bartender 7 是付费升级

厂商 `/Bartender7/purchase/` 与 `/Bartender7/upgrade/`（2026-10-10 只读 GET）：2026 年内买的 Bartender 6 完整授权免费升级到 7，其余 6 授权是折扣付费升级；Pro / Mega Supporter 已含 7。所以 7 不是 6 的"下一个版本"，**6 的安装绝不能被提示 7**。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                 | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-----------------|---------|----------|-----|--------|-------------|
| **6 stable**    | ✓       | — (cask 已是 7) | — | — | ✓（sweep 锚点，检测上不跑；钉在 `^6\.`） |
| **7 stable**    | ✓       | `auto_updates`，退让给 Sparkle | — | — | — |
| **Test Builds** | ✗       | —        | —   | —      | —           |

当前生效源: 两代都是 **Sparkle**（bundle 声明的 feed，`feed-discover` 两个真包都是 `declared`）。

## Channel 详情

| 轨 | Bundle ID | 独立/共享 | 区分信号 | 门控方式 | 状态 |
|----|-----------|----------|---------|---------|------|
| Bartender 6 | `com.surteesstudios.Bartender` | 共享 | 已装 bundle 自己的 `SUFeedURL`；版本 `6.x` | feed 按代分开 | ✓ |
| Bartender 7 | `com.surteesstudios.Bartender` | 共享 | 同上；版本 `7.x` | feed 按代分开 | ✓ |
| Test Builds | — | — | 没找到 | — | ✗ 见下 |

6 和 7 不是 channel（两个都是 stable），是两个产品；区分它们的是每个 bundle 自己声明的 feed，各自只列本代版本，所以 Sparkle 这一层天然不会跨代。recipe 层按代区分靠版本：VendorProbe 用 `installedVersionPattern`（CCC 5/6/7 同样做法），changelog 用 `belowAppVersion`/`minimumAppVersion` 在 7 处拼接（Audacity 同样做法）。

Test Builds：`/Bartender7/release_notes/` 有「Test Builds」一节，`…/Bartender7/updates/7-0-2/`、`7-0-3/` 的 `rnotes.html` 存在（200）但不在 AppcastB7 里。没找到它的 feed 地址或 app 内开关，没接；要接需要先找到 app 里怎么切到测试版。

## 更新检测
- 源: `SparkleAppcastSource`，读 bundle 声明的 feed。两个 appcast 都是升序（最旧在前）。
- AppcastB6: 16 个 item，6.0.0 → 6.6.2。AppcastB7: 4 个 item，7.0.0 / 7.0.1 / 7.0.4 / 7.0.5（7.0.2、7.0.3 是 Test Builds，不在 feed 里）。
- 每个 item 有 `<sparkle:releaseNotesLink>`，不内联说明。
- 6 的安装只会读到 6.x，7 的安装只会读到 7.x：已用生产 `UpdateChecker.check()`（`channel-verify`）在 6.6.2、7.0.4、7.0.5 三个真 bundle 上确认，见「如何复验」。
- VendorProbe（AppcastB6）在生产里不跑（Sparkle 先答），留作 `duo verify` 的 sweep 锚点。它现在带 `installedVersionPattern: ^6\.`：不加的话，7.x 安装的 Sparkle 检查一旦失败，它会拿"最新 6.6.2"、6 的 zip 和 6 的说明页回答 7.x 安装。不加 pin 时用生产 `VendorProbeSource` 对 7.0.5 安装实测确实会去取 AppcastB6 并作答。
- 没有 Bartender 7 的 VendorProbe：7 的 feed 由它自己的 bundle 声明，Sparkle 已经回答；`duo verify` 通过 7 的 changelog recipe 的 `source`（AppcastB7）读这个 feed。

### Homebrew
cask `bartender` 已是 7.0.5（`app "Bartender #{version.major}.app"`、`auto_updates true`、livecheck 读 AppcastB7）。对 Bartender 6 用户的影响，已对照代码确认：
- `HomebrewCaskSource` 遇到 `auto_updates` 的 cask 返回 nil，app 落到 Sparkle；所以 brew 装的 6 不会因 cask 版本 7.0.5 被提示 7。
- `brew upgrade --cask` 只对不带 app 的 cask 运行（`BrewFormulaService.upgrade(casks:)` 的调用约定），不会把 6 升成 7。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2.6.4） | 无 | — |
| 证据 | Sparkle.framework 2.6.4 | AppcastB6 / AppcastB7（2026-10-10）都没有 `<sparkle:deltas>`；`channel-verify` 报 deltas 0 | 无可消费 |

## Changelog
- 来源: recipe，`feedPagePattern`：页面就是 Sparkle 检查解析出的那一条 `releaseNotesLink`。两条 recipe 共用 bundle id，按版本窗口分：
  - Bartender 6（`belowAppVersion: "7"`）：`…/B2/updates/<6-x-y>/rnotes.html`
  - Bartender 7（`minimumAppVersion: "7"`）：`…/Bartender7/updates/<7-x-y>/rnotes.html` 或 `rnotes-stable.html`（7.0.4 的 feed 链接是后者：上一个正式版以来的累计说明；同目录的 `rnotes.html` 只是相对上一个测试版的增量）
- 两代页面是同一个模板（`<h2>Bartender 7.0.5</h2>`、`<h3>` 分类标题、`<li>` 条目，到 `</table>` 为止），entry/item/heading 三个 pattern 共用。
- 结构化（`channel-verify` 的 `changelog pane` 行）：
  - 7.0.5: `recipe changelog:com.surteesstudios.Bartender:-:7+: 1 entries; newest 7.0.5: 6 items, headings ["Fixes"]`
  - 6.6.2: `recipe changelog:com.surteesstudios.Bartender:-:<7: 1 entries; newest 6.6.2: 8 items, headings ["Fixes"]`
- 跟随代: 是（窗口 + 各自的 `feedPagePattern`；对方那一代的页面两条 recipe 都拒，拒了就嵌入该页）。
- 加 7 的 recipe 之前，7.x 安装的 pane 是 `web page …/Bartender7/updates/7-0-5/rnotes.html, no structure`（内容对，无结构）。

## 一键安装
- 状态: 支持（走 Sparkle enclosure，zip）。
- 端到端（2026-10-10，本分支 `make cli` 构建的 duo，按路径 `duo install "/Applications/Bartender 7.app" --yes --json`）：
  - 未运行：7.0.4 → 7.0.5，`{"outcome":"installed","route":"sparkle","bytesDownloaded":60564183}`，约 20 s。结果 `CFBundleVersion` 700012、inode 变、`codesign --verify --deep --strict` 0、Team `24J875RH8J`、spctl Notarized Developer ID；与厂商 7.0.5 zip 解出的 bundle `diff -r --no-dereference` 无差异；`duo backups` 留了 7.0.4 的回滚副本。
  - 运行中：7.0.1 启动后（未授予任何权限、未处理引导页）`duo install` → `installed`/`sparkle`，旧进程继续跑；`duo restart "Bartender 7"` → 新进程，`lsappinfo` 报 Version 700012；之后 16 s 内磁盘版本一直是 7.0.5，无回退。因为 `SUAllowsAutomaticUpdates = false`，这一轮无法让 Bartender 自己的 Sparkle 先暂存一个包（试过本地 feed 的办法，读到这个键后放弃），「暂存冲突」在这个 app 上没有前提。
  - 两轮都没有装上 privileged helper 或 audio plug-in（启动时它们需要用户授权，没给）。
- 签名: 7.0.4 与 7.0.5 真包同为 Team `24J875RH8J`、Notarized Developer ID，从上一版 7.x 一键过 Team 闸；6.6.2 同 Team。
- 格式: zip（`Bartender 7.app` / `Bartender 6.app`）。7.0.0 的 enclosure 带 `?revision=` 查询串。
- 校验: appcast 只有 `sparkle:edSignature`（6.x 另有 `dsaSignature`），没有 SHA 摘要字段。
- **读的是**: 轨道最新，也就是人人可手动下载的版本（`/Bartender6/support/` 链出 `…/Bartender7/updates/Latest/Bartender%207.dmg`；feed 里的每个 zip 也公开可下）。
- 阻塞: 无。嵌套的 `Bartender Service.xpc` 在重启前后的进程没单独核对（只核了主进程）。

## 已知问题
- AppcastB6 的 `pubDate` 写作 `September 13, 2025 09:45:00 +0000`，`channel-verify` 对 6.6.2 报 `release history 0 entries`（AppcastB7 用 RFC 822 日期，报 4 条）。未查是不是这个日期格式导致的。
- Test Builds 轨未接（见上）。
- 厂商说 7 目前只支持 macOS 27，但 feed 和 bundle 都写 14.0；在 macOS 26 上的 7.x 安装（若存在）会被提示更新到同样不支持该系统的构建。没有可读的上限，`SparkleAppcastSource` 也就无从过滤。

## 建议下一步
1. Test Builds：先找到 app 里切测试版的方式（偏好键 / 单独 feed），再决定是否加 `ChannelBinding`；在那之前记为缺口。
2. 查 AppcastB6 release history 为 0 的原因。

## 如何复验

```bash
curl -sSL https://downloads.macbartender.com/Bartender7/updates/AppcastB7.xml | grep -E "shortVersionString|releaseNotesLink"
curl -sSLo b7.zip "https://downloads.macbartender.com/Bartender7/updates/7-0-5/Bartender%207.zip" && ditto -x -k b7.zip b7
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :SUFeedURL' "b7/Bartender 7.app/Contents/Info.plist"
swift run --package-path application-test feed-discover "b7/Bartender 7.app"
swift run --package-path application-test channel-verify "b7/Bartender 7.app"
```

2026-10-10 结果（真包，解压未运行）：

| 包 | bundle id | 版本 | `SUFeedURL` | 胜出源 / latest | changelog pane |
|---|---|---|---|---|---|
| 7.0.5 zip | `com.surteesstudios.Bartender` | 7.0.5 (700012) | AppcastB7 | Sparkle / 7.0.5，up to date | recipe `7+`，6 条，`["Fixes"]` |
| 7.0.4 zip | `com.surteesstudios.Bartender` | 7.0.4 (700011) | AppcastB7 | Sparkle / 7.0.5，UPDATE | recipe `7+` |
| 6.6.2 zip | `com.surteesstudios.Bartender` | 6.6.2 (662000) | AppcastB6 | Sparkle / 6.6.2，up to date | recipe `<7`，8 条，`["Fixes"]` |

7.x 两个包上 `channel-verify` 的 VendorProbe 行是 `✗ no version`（6 的 probe 被 `^6\.` 排除，预期如此）；6.6.2 上是 `✓ 6.6.2`。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-surteesstudios-Bartender.swift — stable VendorProbe（检测上是死的，留作 sweep 锚点）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（bundle 声明的 `SUFeedURL` 就是这个地址，所以 `SparkleAppcastSource` 先应答，保留了读取日期），当年那句保留意见和读的是哪个版本搬到这里。

DEAD FOR DETECTION, kept as a sweep anchor. The hedge this comment used
to carry ("if the installed app has SUFeedURL … Sparkle takes priority")
was settled on 2026-08-31 by reading the real 6.6.2 bundle: it declares
`SUFeedURL = https://www.macbartender.com/B2/updates/AppcastB6.xml`, the
same address as below, so `SparkleAppcastSource` answers first and this
recipe never runs in production. It stays because `duo verify` sweeps the
recipe registries and nothing sweeps Sparkle feeds — deleting the row
would leave the endpoint unwatched. Do not "fix" this by re-pointing it.

### Recipes/com-surteesstudios-Bartender.swift — stable VendorProbe（一键 zip）

转引自 recipe 注释，未复测。整段原文；括号里那句原样留在代码里。

Verified 2026-08-09 on 6.6.2: `Bartender 6.app` in the archive, bundle
id com.surteesstudios.Bartender, Team 24J875RH8J, spctl "Notarized
Developer ID". (Note the older entries are served from macbartender.com
and the recent ones from downloads.macbartender.com — the pattern
accepts either host.)

复测 2026-09-14（约 07:30 UTC，只读 GET；`www.macbartender.com/B2/updates/AppcastB6.xml` 先 307 到 `downloads.macbartender.com` 同一路径）：16 个 `<item>`，第一个 enclosure 是 6.0.0（`macbartender.com/B2/updates/6-0-0/…`），最后一个是 6.6.2（`downloads.macbartender.com/…/6-6-2/…`）。代码里 "the first enclosure is 6.0.0" 和两个主机的说法因此原样保留。

### Recipes/com-surteesstudios-Bartender.swift — ChangelogRecipe（`feedPagePattern`，2026-10-10 接入）

只读 GET，2026-10-10。appcast（`www.` 307 到 `downloads.macbartender.com`）16 个 `<item>`，升序，最新 6.6.2
（= baseline `vendor:com.surteesstudios.Bartender:stable` 的 `lastGoodVersion`），每个 item 一个
`<sparkle:releaseNotesLink>`，无 `xml:lang`。6.0.0–6.4.1 链接 `macbartender.com/B2/updates/<6-x-y>/rnotes.html`，
6.5.1 起是 `downloads.macbartender.com/…`。16 个链接全部被 `feedPagePattern` 接受；逐个 GET：6.1.2、6.1.3、6.2.1、
6.3.0、6.3.1、6.4.1 共 6 个 404，其余 10 个 200。

生产解析器（`ChangelogExtractor`，临时测试）在 10 个活页上都出 1 条，版本 = 链接版本，唯独 6.0.0 页标题是
"Bartender 6"，版本读成 `6`；该页正文多数是 `<h4>` 下的散文，只有末尾 4 条 `<li>`（已知问题）成为条目，
6 个 `<h4>` 成为 heading。6.0.3 页没有列表，落到 `<p>`（1 条）。`ChangelogService.loadDiagnostic(feedPage: nil)`
从 appcast 解析出 `…/6-6-2/rnotes.html`（200），1 条 `6.6.2`、8 条、heading `Fixes`，首条
"Memory usage should no longer creep up over longer sessions for users with triggers enabled."；
`ChangelogService.load(forBundleID:)` 按设计返回 nil（没有更新结果可取页面）。

### Recipes/com-surteesstudios-Bartender.swift — VendorProbe `changelogURL`（2026-10-10 改）

接入前 probe 的 `changelogURL` 是 appcast `www.macbartender.com/B2/updates/AppcastB6.xml`（307 到
`downloads.macbartender.com`），recipe 出不了内容时 pane 会嵌一份原始 XML。只读 GET 找人读的页面：
`/Bartender6/support/` 链出 `/Bartender6/release_notes/`（200，9314 B，标题 "Bartender 6 - Release Notes"，
同页列出 6.x 各版说明，最新 6.6.2；另有 "Test Builds" 一节）；`/Bartender6/releasenotes/`、`/Bartender6/changelog/`、
`/B2/updates/` 均 404。改指 `/Bartender6/release_notes/`。它不匹配 `feedPagePattern`，所以只会被嵌入，不会被 recipe 解析。
同一 support 页还链出 `/Bartender7/release_notes/` 与 Bartender 7 的 dmg：Bartender 7 已存在，本次未调查。

### Bartender 7 接入（2026-10-10）

只读 GET 与真包（7.0.4、7.0.5、6.6.2 的 zip，解压后只读 plist / codesign / spctl，未运行）。上一节末尾"Bartender 7 已存在，本次未调查"的那次调查即本节。

- bundle id、Team、EdDSA key 两代相同；`SUFeedURL` 不同。cask `bartender` 的 livecheck 给出 `…/Bartender7/updates/AppcastB7.xml`（`www.macbartender.com` 上同路径 404）。
- AppcastB7：4 个 item，升序，`releaseNotesLink` 全部在 `downloads.macbartender.com/Bartender7/updates/`；7.0.4 链 `rnotes-stable.html`（200，19 个 `<li>`，两节），同目录 `rnotes.html`（200）是测试版增量。7.0.2、7.0.3 的 `rnotes.html` 200 但不在 feed。
- 6.x 的 entry/item/heading pattern 在 7.0.0–7.0.5 全部 7 个页面上读出正确版本；7.0.0 页 16 条、标题 `New` / `Known Issues`。
- 改动前生产链路：7.0.5 安装 Sparkle 胜出、pane 只嵌网页；6 的 VendorProbe 对 7.0.5 安装作答 `latest 6.6.2, verdict up to date`。改动后见「如何复验」。
- 变异：去掉 `installedVersionPattern` → `theBartender6ProbeIsPinnedToBartender6` 红（并实际去网络取了 AppcastB6）；去掉两个版本窗口 → `eachTrainsPageSelectsItsOwnRecipe` 等红。
- `duo verify --only surteesstudios`（改动后的 CLI）：第一次跑报 ⚠ `changelog:…:7+` "newest changelog entry (7.0.5) reads AHEAD of every probe row (6.6.2)"——拿 7 的说明和 6 的 probe 比。`Verify.changelogLeadsProbeComplaint` 因此改为只和 recipe 版本窗口内的 probe 行比（与上面滞后检查用 `covers` 的做法一致；没窗口的 recipe 不受影响）。改后 vendor probe ✓ 1、changelog ✓ 2、⚠ 0；另两个带窗口的家族 `--only raycast` / `--only audacity` 各 ✓ 5、⚠ 0。
