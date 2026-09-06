# CotEditor

审计日期：2026-09-06。**结论：调查完成，暂不接入**——见「为什么没接」。

## 基本信息

- Bundle ID：`com.coteditor.CotEditor`；Team ID：`HT3Z3A72WZ`（Mineko IMANISHI）。
- 官方真包观测：stable `7.0.9` / build `843`；beta `7.1.0-beta.6` / build `845`。
- 两轨 universal DMG 均通过 Gatekeeper：`Notarized Developer ID`。
- 直装版内置 Sparkle，带 `SUPublicEDKey`，但**没有 `SUFeedURL`**。地址
  `https://coteditor.com/appcast.xml` 在两份签名二进制及官方 `UpdaterManager.swift` 中可确认。
- 也在 Mac App Store 上架；Homebrew 有 cask，`auto_updates`。

## 为什么没接

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

## 接进来需要什么

不是补一个 `ChannelBinding` 就够——那只解决「知不知道自己在 beta 轨」，解决不了
「跨轨按 build 排序」。而且 `SparkleAppcastSource.sparkleChannelName(.beta)` 给的是
`"beta"`，CotEditor feed 用的标签是 `"prerelease"`，对不上。

真正缺的是一条**「远端 marketing 比装机的旧就不提供」**的守卫。那条守卫落在每个 Sparkle
app 都要走的检查路径上，属于 CLAUDE.md 说的「十行改在所有请求都要走的路径上」，该单独
走一轮对抗复审，不该塞进发版日。

顺带一条，同一条 `SparkleFeedCatalog` 补丁还有第二个副作用需要一起决定：
`AppScanner` 填这张表时**不看 `isMASApp`**（与 `GitHubReleasesSource.swift:591` 的
`guard !app.isMASApp` 和 `HomebrewCaskSource.swift:33` 不同），而 `MacAppStoreSource`
查不到时是 `continue` 而不是终止。CotEditor 有商店版，所以一次商店查询落空就会让商店版
副本拿到一个直装 DMG 的一键更新。

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
