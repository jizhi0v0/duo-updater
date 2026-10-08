# Rectangle

> 首次审计 2026-06-04（只核了 bundle 身份：Team ID、版本、`SUFeedURL`）；
> **2026-10-08 重审**：真包跑生产检测、查渠道、量 changelog 渲染。下文所有结论以 2026-10-08 为准。

## 基本信息
- Bundle ID: `com.knollsoft.Rectangle`
- Team ID: `XSYZ3E4B7D`（Developer ID Application: Ryan Hanson；2.0.3 与 2.0.2 两个真包一致）
- 观测版本: `2.0.3` (build `110`，最新) / `2.0.2` (build `109`，上一版)；首次审计时是 `0.96` (`102`)
- 自更新机制: Sparkle（内嵌 Sparkle.framework `2.10.0`），签名 feed（bundle 带 `SUPublicEDKey`，enclosure 带 `sparkle:edSignature`）
- 架构: universal（`x86_64 arm64`）；`LSMinimumSystemVersion` = `14.0`（2.x 起，1.100 及以前是 `10.15`）；`LSUIElement` = true（菜单栏 app，无 Dock 图标）
- 开源: `github.com/rxhanson/Rectangle`（默认分支 `main`）。Info.plist 与 `AppDelegate.swift` 读自 `main` @ `18c058a`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic，无 recipe） | ✗（`auto_updates: true`，按设计让路） | — | —（包放在 GitHub Releases，但 Sparkle 先应答，不需要 rule） | — |
| **beta**     | — | — | — | — | — |
| **canary**   | — | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify` 实测 `winning source  Sparkle`）。

MAS：`itunes.apple.com/lookup?bundleId=com.knollsoft.Rectangle` 返回 `resultCount: 0`，没有 App Store 版。

## Channel 详情

只有一条轨。三处证据互相印证：

1. **settled from source: `Rectangle/AppDelegate.swift` on `main`**：
   `SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: self)`。没有 updater delegate，
   也就没有 `allowedChannels(for:)`、没有 `feedURLString(for:)`，Sparkle 只读 Info.plist 的
   `SUFeedURL`，只接受 default channel。全仓库 `grep` `allowedChannels|feedURLString|prerelease|beta`
   没有命中更新相关代码。设置页里与更新有关的只有 "Check for updates automatically" 一个开关
   （`SettingsWindow/AppSettingsView.swift`，存为 `SUEnableAutomaticChecks`），它只控制是否自动检查，
   不切轨。
2. **feed**：`https://rectangleapp.com/downloads/updates.xml` 14 个 item，**14/14 没有 `<sparkle:channel>`**。
   这和 OBS 那种「每条都打 stable/beta 标签、app 内有渠道开关」的形状不同，这里没有可被漏掉的轨。
3. **GitHub Releases**：共 107 个 release，8 个标了 prerelease，最近的一个是 `v0.62`（2022-11-13）。
   之后三年多没有 prerelease，最近 15 个全部是正式版。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.knollsoft.Rectangle` | — | `SUFeedURL`，feed 全部 item 无 channel 标签 | — | ✓（真包验证，见「如何复验」） |

`ChannelBinding.resolver(for:)` 对这个 id 没有 binding，`channel-verify` 打印 `ChannelBinding  <none for this app>`。
没有渠道可接，所以不需要 binding。

**Rectangle Pro 不是一条轨，是另一个产品**：真包 `Rectangle Pro 3.94.dmg`（`rectangleapp.com/pro/downloads/`）
的 `CFBundleIdentifier` = `com.knollsoft.Hookshot`，`SUFeedURL` = `https://rectangleapp.com/pro/downloads/updates.xml`
（11 个 item，同样全部无 channel 标签），Team 同为 `XSYZ3E4B7D`，付费授权。和本 app 不共享 bundle id、不共享 feed，
不在本文范围。它包内有一个 `Contents/Library/LoginItems/RectangleProLauncher.app`（`LSBackgroundOnly` = true），
将来审它的一键时要看这个 launcher 的行为。

## 更新检测
- 源: `SparkleAppcastSource`（generic，读 bundle 自带的 `SUFeedURL`，无 registry 条目）
- 端点: `https://rectangleapp.com/downloads/updates.xml`（Cloudflare，`cache-control: public, max-age=0, must-revalidate`，带 ETag）
- `feed-discover` 判定: `declared`
- 上一版 2.0.2 → `status  UPDATE → 2.0.3`；最新版 2.0.3 → `status  up to date`
- 注意事项:
  - **OS 下限按条目变化**：2.0 起 item 的 `minimumSystemVersion` 是 `14.0`（4 条），1.100 及以前是 `10.15`（10 条）。
    没有 `maximumSystemVersion`、没有 `hardwareRequirements`、没有 `phasedRolloutInterval`、
    没有 `minimumAutoupdateVersion`、没有 `criticalUpdate`。`SparkleAppcastSource.usableItems` 按
    `minimumSystemVersion` / `maximumSystemVersion` 过滤（读代码得出，**未在 macOS 13 上实测**），
    所以 macOS 13 上的 1.x 副本不会被推 2.x，跟 Sparkle 自己的行为一致。
  - feed 跳过了 0.97（GitHub 上有 `v0.97` release，feed 里没有对应 item；0.98 条目的 Details 链接指向 `v0.97`）。
    不影响检测。
  - **大版本标记**：从 1.x（或 0.x）升到 2.x 时，`VersionComparator.isMajorUpgrade` 实测为 true
    （`1.100→2.0.3` true、`0.99→1.100` true、`2.0.2→2.0.3` false，临时测试，跑完已删）。来源是
    `Sparkle`，不在 `licenseNeutralSources` 里，feed 也没写 `minimumAutoupdateVersion`，所以按
    `UpdateResult.isMajorUpgrade` 的代码，这类行会走 `majorUpgrade` 路由，弹「可能需要新授权」的确认。
    Rectangle 是免费软件，这条提示对它是误报，但只多一次确认，不会装错。见「已知问题」。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（未端到端跑） |
| 证据 | 内嵌 Sparkle 2.10.0 的 `Autoupdate` 含 `deltaFromSparkleExecutableSize` / `deltaFromSparkleLocales` 字符串 | 2026-10-08 抓的 feed：14/14 item 带 `<sparkle:deltas>`，2.0.3 有 5 个 patch（from build 109/108/107/105/104）。`Rectangle110-109.delta` 363770 B，完整 dmg 4730793 B | `SparkleInstaller.download` 在 `DeltaApplier.isAvailable` 且已装 build 等于某个 `deltaFrom` 时走 patch；`channel-verify` 打印 `deltas  5`，说明解析到了 |

- 格式: Sparkle binary delta
- 阻塞项: 无。2.0.2 (109) → 2.0.3 应走 `Rectangle110-109.delta`；1.100 (106) 不在 2.0.3 的 deltaFrom 列表里，会取完整 dmg。
- 历史：`SparkleAppcastSource.swift` 的 `deltasDepth` 注释记录过 Rectangle 曾因 delta enclosure 被当成主下载而整个不可见，
  已修；本次 `channel-verify` 的 `download` 行是完整 dmg，说明修复仍然有效。

## Changelog
- 来源: Sparkle inline（`<description>` HTML，`<ul><li>`；没有 `releaseNotesLink`、没有 `markdownDescription`）
- 结构化: `changelog pane  source structured: 12 entries; newest 2.0.3: 4 items, headings []; first items ["Various bug fixes for the v2 redesign.", "Stacked windows can now be cycled throug", "Closing tabs in Chrome now will not trig"]`
  - `headings []` 不是被压平：整个 feed 没有一个 `<h2>`–`<h4>`，vendor 本来就只写平铺列表。
  - 14 个 item 里 12 个带 `<description>`；**2.0 和 2.0.1 没有 notes**，所以是 12 entries。
  - **2.0.2 条目丢了它自己那句话**（临时测试实测，跑完已删）：2.0.2 的 description 是一行裸文本
    `v2.0.2: Fixes a couple of issues for macOS 15 and earlier, introduced in v2.0`，后面跟 `<p>v2.0:</p>`
    和 v2.0 的 5 个 `<li>`。`AppcastHTMLChangelogParser.entry` 只收 `<li>` 和 `<h2>`–`<h4>`，
    产出的 2.0.2 条目是 v2.0 的 5 条，那句 2.0.2 自己的修复说明不在里面。因为有 `<li>`，
    `isStructured` 为 true，不会退回 HTML 渲染，丢失没有任何提示。
  - 每条 notes 末尾的「Details」「Recent version history」链接不进条目（2.0.3 是 4 个 `<li>` → 4 items）。
- 跟随 channel: 不适用（只有一条轨）
- Recipe 状态: 不需要 recipe。2.0.2 那种「列表外的散文」丢失是通用 HTML 解析器的问题，见「建议下一步」。

## 一键安装
- 状态: 支持（generic Sparkle 路径；Team、签名、OS 下限都对得上）
- 端到端: 未跑（由协调会话串行执行）
- 格式: dmg（feed enclosure；GitHub release 另有 `Rectangle.pkg`，feed 不用它）
- 校验: Sparkle EdDSA（bundle `SUPublicEDKey` = `lpt9M3PhocbZ3MZiLH+crEqRfU11kfoNzGxSqiEIdvM=`，enclosure 带 `sparkle:edSignature`）。
  另外 GitHub 资产带 `digest`，下载的两个 dmg 的 `shasum -a 256` 与之一致
  （2.0.3 `a48883b5…a3dcb5`，2.0.2 `7a42f6b9…c38833`），但 Sparkle 路径不读 GitHub digest
- **读的是**: 人人可手动下载的 GA。feed 顶部 item 就是 GitHub `releases/latest` 的同一个 dmg，没有灰度字段
- 包内结构: 无嵌套 app、无 `Contents/Library/LoginItems`；开机启动走 `SMAppService.mainApp`（`LaunchOnLogin.swift`），
  没有常驻 helper。唯一嵌套的是 Sparkle 自己的 `Updater.app` 和 XPC 服务
- Team ID 闸: 2.0.2 与 2.0.3 均为 `XSYZ3E4B7D`，`codesign --verify --deep --strict` 退出 0，`spctl` `source=Notarized Developer ID`
- 阻塞: 无

## 已知问题
- 2.0.2 的 changelog 条目丢掉了列表之外的那句版本说明（见 Changelog）。只在 vendor 把说明写成裸文本加列表时出现，2.0.3 不受影响。
- 1.x/0.x → 2.x 会走大版本确认（「可能需要新授权」）。Rectangle 免费，这条提示对它是误报。代码本意就是偏保守（Sparkle 源不算 license-neutral），记在这里，不算 bug。
- 自更新器会不会和我们抢：Rectangle 的 Sparkle 默认每 172800 秒（2 天）检查一次，没有在 Info.plist 里关掉自动下载（没有 `SUAllowsAutomaticUpdates`）。运行中被 Sparkle 暂存后再 `duo install` 的情况没测过，留给端到端第二轮。

## 建议下一步
1. 检测和一键不需要代码改动，也不需要 `ChannelBinding`。协调会话按 `coverage-discovery` Phase 5 跑端到端：先装 2.0.2，`duo install` 到 2.0.3，看是否走 `delta route ... build 109`。
2. Changelog（可选，通用修复，不是 Rectangle 专属）：`AppcastHTMLChangelogParser.entry` 遇到 `<li>` 之外的顶层裸文本或 `<p>` 时，现在直接丢弃。
   两种做法任选：(a) 把列表前的顶层文本/`<p>`（排除只含链接的 `<p>`）收成条目开头的 item；(b) 只要存在 `<li>` 之外的非链接正文就返回 nil，退回 HTML 渲染。
   不管选哪种，都要用 2.0.2 这段 description 当 fixture，还要 bump `Changelog` 的解析代数。
3. 不需要改 `CHANNEL_COVERAGE_TODO.md` 的结论（「无 beta 渠道」经源码和 feed 证实）。那一行写的「GitHub releases」只是包的托管位置，检测走的是 Sparkle。

## 如何复验

```bash
# 源码（main @ 18c058a）
gh api "repos/rxhanson/Rectangle/contents/Rectangle/AppDelegate.swift?ref=main" -H "Accept: application/vnd.github.raw" | grep -n "SPUStandardUpdaterController"
#   → updaterController = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: self)

# feed
curl -sS "https://rectangleapp.com/downloads/updates.xml" -o feed.xml
#   → 14 items；<sparkle:channel> 0 个；每条都有 <sparkle:deltas>；minimumSystemVersion 14.0×4 / 10.15×10；
#     无 maximumSystemVersion / hardwareRequirements / phasedRolloutInterval / minimumAutoupdateVersion

# 真包（放在 mktemp -d 目录）
curl -sSL -O "https://github.com/rxhanson/Rectangle/releases/download/v2.0.3/Rectangle2.0.3.dmg"
curl -sSL -O "https://github.com/rxhanson/Rectangle/releases/download/v2.0.2/Rectangle2.0.2.dmg"
.claude/skills/coverage-discovery/scripts/check-bundle.sh Rectangle2.0.3.dmg Rectangle2.0.2.dmg
swift run --package-path application-test feed-discover Rectangle2.0.3.dmg
swift run --package-path application-test channel-verify Rectangle2.0.2.dmg
swift run --package-path application-test channel-verify Rectangle2.0.3.dmg
```

2026-10-08 结果：

| 检查 | 2.0.2 dmg | 2.0.3 dmg |
|---|---|---|
| `CFBundleIdentifier` | `com.knollsoft.Rectangle` | `com.knollsoft.Rectangle` |
| short / build | `2.0.2` / `109` | `2.0.3` / `110` |
| `LSMinimumSystemVersion` | `14.0` | `14.0` |
| archs | `x86_64 arm64` | `x86_64 arm64` |
| TeamIdentifier | `XSYZ3E4B7D` | `XSYZ3E4B7D` |
| `codesign --verify --deep --strict` | exit 0 | exit 0 |
| spctl | `Notarized Developer ID` | `Notarized Developer ID` |
| 嵌套 app（check-bundle） | 无 | 无 |
| `shasum -a 256` = GitHub `digest` | 是 | 是 |
| `feed-discover` | — | `declared  https://rectangleapp.com/downloads/updates.xml` |
| detected channel | `stable` | `stable` |
| ChannelBinding | `<none for this app>` | `<none for this app>` |
| winning source | `Sparkle` | `Sparkle` |
| latest / download | `2.0.3` / `.../v2.0.3/Rectangle2.0.3.dmg` | 同左 |
| release history / deltas | 14 / 5 | 14 / 5 |
| status | `UPDATE → 2.0.3` | `up to date` |

`changelog pane` 行原文（两次相同）：

```
changelog pane  source structured: 12 entries; newest 2.0.3: 4 items, headings []; first items ["Various bug fixes for the v2 redesign.", "Stacked windows can now be cycled throug", "Closing tabs in Chrome now will not trig"]
```

另外两条临时测试（`DuoUpdaterCore/Tests` 下，跑完即删，未提交）：

```
AppcastHTMLChangelogParser.entry(html: <2.0.2 的 description 原文>, version: "2.0.2", date: nil)
  → isStructured=true；items = v2.0 的 5 条 <li>；含 "macOS 15 and earlier" = false
VersionComparator.isMajorUpgrade: 1.100→2.0.3 true；2.0.2→2.0.3 false；0.99→1.100 true（isCalendarVersion 均 false）
```
