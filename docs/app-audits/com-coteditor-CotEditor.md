# CotEditor

审计日期：2026-09-06。**结论：已接入 —— 走 GitHub 两条规则 + 一个 ChannelBinding，
appcast 故意不读。**

三次改口，按顺序记着，因为每一步都是量出来的：

1. 第一版补 `SparkleFeedCatalog` 地址走 appcast，端到端 `7.0.8 → 7.0.9` 装成功了，
   但**旧 beta 会被推降级包**，于是撤回（见「为什么当初没接」）。
2. 补了降级守卫（#368 / PR #375）。守卫挡住了伤害，但没解决盲区：那台
   `7.1.0-beta.3` 从「按 Update 就降级」变成「行里写着 7.0.9、状态已是最新」，
   feed 里的 `7.1.0-beta.6` 它**仍然看不见**。
3. 现在这一版**换源**：GitHub 保留全部 release，tag 自己说明在哪条轨，
   渠道判断不再依赖「能不能在 feed 里找到自己」——盲区从根上消失。

## 基本信息

- Bundle ID：`com.coteditor.CotEditor`；Team ID：`HT3Z3A72WZ`（Mineko IMANISHI）。
- 官方真包观测：stable `7.0.9` / build `843`；beta `7.1.0-beta.6` / build `845`。
- 两轨 universal DMG 均通过 Gatekeeper：`Notarized Developer ID`。
- 直装版内置 Sparkle，带 `SUPublicEDKey`，但**没有 `SUFeedURL`**。地址
  `https://coteditor.com/appcast.xml` 在两份签名二进制及官方 `UpdaterManager.swift` 中可确认。
- 也在 Mac App Store 上架；Homebrew 有 cask，`auto_updates`。

## 为什么当初没接（appcast 那条路）

补一条 `SparkleFeedCatalog` 地址就能让检测跑起来，第一版就是这么做的，端到端
`7.0.8 → 7.0.9` 也真的装成功了。撤回的原因是**旧 beta 会被推一个降级包**，而且这条路
是所有闸都放行的。

真实 `coteditor.com/appcast.xml`（2026-09-06 取）一共 13 条 item，其中只有 **1 条**
prerelease：

| build | short | channel | minimumSystemVersion |
|---|---|---|---|
| 845 | `7.1.0-beta.6` | `prerelease` | 26.0 |
| 843 | `7.0.9` | （默认） | 15.0 |
| 730 | `5.2.3` | （默认） | 14.0 |
| …余下 10 条是给旧系统的兼容梯子 | | | |

也就是说 `7.1.0-beta.1` ~ `beta.5` **不在 feed 里**。而 build 号是跨两轨单调的，7.0.9 是
843、beta.6 是 845，中间只剩一个 844，所以那几条旧 beta 的 build **必然低于当前 stable**。

拿真实响应体跑生产代码（`SparkleAppcastParser` → `allowedChannels` → `bestItem` →
`UpdateChecker.evaluate`）：

```
INSTALLED 7.1.0-beta.3/840  detect=beta  allowed=[nil]
  → best=7.0.9/843  status=updateAvailable(latest: "7.0.9")
INSTALLED 7.1.0-beta.6/845  detect=beta  allowed=[prerelease, nil]
  → best=7.1.0-beta.6/845  status=upToDate
```

链条是这样的：

1. `SparkleAppcastSource.channel(ofInstalled:)` 按 build、再按 shortVersion 去 feed 里找
   自己那一条。旧 beta 被裁掉了，两次都落空，返回 nil。
2. 于是 `allowedChannels` 只剩默认渠道 `{nil}`——PR 原文把这一步写成
   "conservatively falls back to stable"，**前提不成立**：它不是保守，它是把这台机器
   在 beta 轨这件事忘了。
3. `bestItem` 按 `comparisonKey`（`version ?? shortVersionString`，即 **build**）排序，
   给出 843 / `7.0.9`。
4. `UpdateChecker.evaluate` 在两边都有 build 时**只比 build、完全不看 marketing**
   （`UpdateChecker.swift:326`）：`isNewer("843", than: "840")` 为真。
5. 结果：`7.1.0-beta.3` 的用户看到写着 Update 的按钮，装下去是 `7.0.9`。marketing 上
   这是**降级**。包是厂商真包、EdDSA 用 bundle 自己的 `SUPublicEDKey` 验得过、Team 一致、
   公证正常，**没有任何一道闸会拦**——仓库里唯一的降级守卫是
   `SignatureVerifier.verifyNoArchitectureDowngrade`，只管架构。
6. 装完之后副本报 `7.0.9`，`ReleaseChannel.detect` 判 `.stable`，beta 轨从此消失。

`UpdatePolicy.laggingRemoteVersion`（「你比远端新，没事」那条静默提示）帮不上忙：它被
限定在 `effectiveReleaseChannel == .stable`（`UpdatePolicy.swift:432`），beta 副本走不到。

次生的同一机制：即使 build 在 feed 里，排序也是**跨轨取最高 build**。CotEditor 现在
同时维护 7.0.x stable 和 7.1.0 beta 两条线，所以只要出现一个 build 高于当前 beta 的
7.0.x 补丁，跑 beta 的副本照样会被喂 stable。

## 现在怎么接的

**源：GitHub Releases，两条规则，同一个 bundle id。** `SparkleFeedCatalog` **不加**
地址——`SourceStack` 里 Sparkle 排在 GitHub 前面，加了就等于把它送回那份 feed。
`CotEditorChannelTests.theAppcastIsDeliberatelyNotInTheCatalog` 钉住这个决定。

```
stable  versionPattern  ^([0-9]+\.[0-9]+\.[0-9]+)$
        installAsset    ^CotEditor_[0-9.]+\.dmg$
beta    usePrereleases: true
        versionPattern  ^([0-9]+\.[0-9]+\.[0-9]+-beta(?:\.[0-9]+)?)$
        installAsset    ^CotEditor_[0-9.]+-beta(?:\.[0-9]+)?\.dmg$
```

最新 100 条 release 实测（2026-09-06，Python 独立复算，不是读 Swift 得出的）：
0 条草稿；**每条 release 恰好一个资产**（100/100）；tag 只有三种形状
`7.0.9` / `7.1.0-beta` / `7.1.0-beta.6`，**没有 `v` 前缀**；
两条 versionPattern 把 100 个 tag **正好切开**——94 stable + 6 beta，没有一个被两条同时
命中，也没有一个两条都不中；100 个资产名同样切开，命名一律 `CotEditor_<tag>.dmg`。

`listPageSize` 用默认 20，实测下限是 **2**（beta 之间最坏间隔 1 条：beta.6 和 beta.5
之间隔着 7.0.9），记在 `GitHubListPageSizeTests.measuredMinimumDepth`。

⚠️ **beta 轨是新开的**：这 100 条里 6 个 prerelease 全属于 2026-07-26 开始的 7.1.0 轮，
它之前的 94 条（一路回到 2022-04）一个都没有。所以等这一轮转正、新一轮没开时，最新的 prerelease 会往下沉，
20 行窗口大约覆盖这个厂商七个月的节奏，之后 beta 规则会匹配不到东西（**答 nil，不报错**）。
那时候跑 beta 的副本也已经被 7.1.0 正式版接走了（正式版压过自己的预发布标签）。

**渠道：`CotEditorChannel`**，还原厂商自己那行
`Bundle.main.version.isPrerelease || checksUpdatesForBeta`：

| 装机 | 框 | 解析 | 结果 |
|---|---|---|---|
| `7.1.0-beta.6` | 勾 | binding → beta | beta 轨 |
| `7.1.0-beta.3` | 没勾 | **nil** → `detect()` → beta | beta 轨 |
| `7.0.9` | 勾 | binding → beta | `7.1.0-beta.6` |
| `7.0.9` | 没勾 | nil → `detect()` → stable | stable 轨 |

关键是第二行：框没勾时**返回 nil 而不是 `.stable`**。返回 `.stable` 是权威的，会把
`detect()` 关掉，于是一台从没打开过那个设置面板的 `7.1.0-beta.3` 被钉死在 stable 轨上
——#368 换一扇门又进来一次。

那个键在**沙盒容器里**（`~/Library/Containers/com.coteditor.CotEditor/Data/Library/Preferences/`），
容器外没有 plist。实测：没有完全磁盘访问的 shell 也读得到，`defaults read com.coteditor.CotEditor
checksUpdatesForBeta` 不指路径就能解析。CapCut 是表里另一个沙盒 app，但它的 flag 在容器
**外**，所以现有两个监视根都盖不到这里，`preferenceWatchCandidates` 补了第三个。

### 实测（打真实端点，2026-09-06）

```
installed=7.1.0-beta.3/840 box=off  → 7.1.0-beta.6  CotEditor_7.1.0-beta.6.dmg  updateAvailable
installed=7.1.0-beta.6/845 box=on   → 7.1.0-beta.6                              upToDate
installed=7.0.9/843        box=off  → 7.0.9         CotEditor_7.0.9.dmg         upToDate
installed=7.0.8/842        box=off  → 7.0.9         CotEditor_7.0.9.dmg         updateAvailable
installed=7.0.9/843        box=on   → 7.1.0-beta.6  CotEditor_7.1.0-beta.6.dmg  updateAvailable
```

第一行就是 #368 那台机器：以前被推 `7.0.9`（降级），守卫之后是「已是最新」，
现在拿到的是它本来就该拿的 `7.1.0-beta.6`。

本机 `duo check coteditor`（装着 beta.6）：`source=GitHub`、`latestVersion=7.1.0-beta.6`、
`status=up-to-date`。

## 还差什么

- **Changelog 没有单独接 recipe**。GitHub 源自己会把 release body 解成结构化条目，
  所以最新一条的说明是有的；多版本历史需要一条 `ChangelogRecipe`，没做。
- **丢掉了 appcast 的两样东西**：EdDSA 签名（改由 Developer ID + 公证兜住）和
  feed 声明的 `minimumSystemVersion`。后者实测被安装时那道闸兜住——`SignatureVerifier`
  读的是下载包自己的 `LSMinimumSystemVersion`，而两个真包里这个值跟 feed 写的一致
  （7.0.9 → 15.0，7.1.0-beta.6 → 26.0）。差别是「先给按钮、装的时候拦」而不是
  「装了个跑不起来的」。
- **`AppScanner` 填 `SparkleFeedCatalog` 时不看 `isMASApp`** 这条老问题还在（#368 的第二半），
  只是 CotEditor 不再走那条路，所以对它不再有影响。

## Changelog

官方 GitHub releases JSON 走现有结构化解码器即可，两轨都验证过能出版本、日期和 Markdown
条目，draft 两轨均排除。这部分没有问题，只是没有单独接入的价值——检测不接，日志接了也
没有入口。

## 如何复验

1. `curl -s https://coteditor.com/appcast.xml` — 数一下有几条 `sparkle:channel` 是
   `prerelease`，以及 stable 与 beta 的 `sparkle:version` 差多少。
2. 临时给 `SparkleFeedCatalog.feeds` 加回 `"com.coteditor.coteditor"`，构造一个
   `shortVersion: "7.1.0-beta.3", buildVersion: "840"` 的 `InstalledApp`，依次调
   `SparkleAppcastSource.allowedChannels` / `bestItem` / `UpdateChecker.evaluate`。
   守卫之前 `bestItem` 给 `7.0.9`/843、`evaluate` 给 `updateAvailable`；守卫之后
   `bestItem` 仍然给 `7.0.9`/843，但 `evaluate` 给 `upToDate`。`allowedChannels`
   两次都是 `[nil]`——这一步没有被修。同一份 feed 的固定装在
   `SparkleMarketingDowngradeTests`，不必联网也能复现。
