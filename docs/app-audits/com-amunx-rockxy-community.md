# Rockxy

开源的原生 macOS HTTP/HTTPS 抓包调试器（AGPL-3.0 源码版 + 官方二进制发行）。

## 基本信息
- Bundle ID: `com.amunx.rockxy.community`
- Team ID: `9YNS969KZE`（`Developer ID Application: Loc Nguyen`，`spctl` 判定
  `Notarized Developer ID`；对下载的 DMG 挂载只读取证，2026-09-09）
- 观测版本: 0.38.2（`CFBundleVersion` 57）
- 架构: universal（`x86_64 arm64`）
- 自更新机制: **Sparkle 2.9.1**（`SUFeedURL` + `SUPublicEDKey` 都在 Info.plist 里，
  `SUEnableAutomaticChecks` / `SUAllowsAutomaticUpdates` 均为 true）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | ✗        | —   | ○      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。
Homebrew cask `rockxy` 存在但是 `auto_updates: true`，`HomebrewCaskSource` 因此返回 nil、
落到下一级；GitHub Releases 也带完整的 macOS 资产，但排在 Sparkle 之后、不会被问到，
所以标 ○ 而不是 ✓ —— 它是「能用但用不上」，不是「已接入」。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.amunx.rockxy.community` | — | `SUFeedURL` | Sparkle appcast（无 channel 标签） | ✓ |

**只有一条轨道，这一点是从构建配置读出来的、不是从 feed 推的。**
仓库里 `Configuration/CommunityProduction.xcconfig`（`community-prod`）和
`CommunityStaging.xcconfig`（`community-stag`）都把 `ROCKXY_SPARKLE_FEED_URL` 指向
**同一个** `ROCKXY_PUBLIC_APPCAST_FEED_URL`，bundle id 也同为
`$(ROCKXY_FAMILY_NAMESPACE).community`；`community-stag` 的注释自己写着
"promotes the same build without rebuilding"。所以 staging 是构建阶段的标签，
不是用户可见的第二条发布轨。GitHub 上 40 个 release **全部** `prerelease=false`
（2026-09-09 实测），appcast 里也没有任何 `<sparkle:channel>` 标签。

## 更新检测
- 源: `SparkleAppcastSource`（零改动，无需 recipe）
- 端点: `https://raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml`
  —— 就是 bundle 自己 `SUFeedURL` 声明的地址，`feed-discover` 判 `declared`。
- 版本方案: **无错位**。appcast 的 `sparkle:shortVersionString="0.38.2"` /
  `sparkle:version="57"` 与真实 bundle 的 `CFBundleShortVersionString` / `CFBundleVersion`
  逐字相同，marketing 和 build 都不需要 `versionIsBuild` 这类补丁。
- OS 分轨: feed 带 `<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>`，
  **没有** `maximumSystemVersion`；真实 bundle 的 `LSMinimumSystemVersion` 也是 `14.0`，
  与 `Configuration/Base.xcconfig` 的 `MACOSX_DEPLOYMENT_TARGET = 14.0` 一致。
  `SparkleAppcastSource` 走的是自己的 `usableItems` 过滤，这个下限由它处理。
- 注意事项: feed 是**原地重写**的单条文件 —— 2026-09-09 抓下来 2225 字节、只有 1 个
  `<item>`。这不影响检测（要的就是最新那条），但决定了 changelog 那一节的做法。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 自带） | **无** | 能，但今天没东西可消费 |
| 证据 | bundle 内 `Contents/Frameworks/Sparkle.framework` 版本 2.9.1，`BinaryDelta` 随框架发行 | 2026-09-09 的 appcast 只有一个 `<enclosure>`，**没有** `<sparkle:deltas>`；GitHub release 资产只有 `.dmg` / `.dmg.sha256` / `manifest.json` / `THIRD_PARTY_NOTICES.txt`，没有 `.delta` | `DeltaApplier` + `VendorAppcastDeltas` 是现成的，厂商一旦开始发 `<sparkle:deltas>` 就自动生效 |

- 格式: 若将来有，会是 Sparkle binary delta（厂商没有自研更新器）。
- 阻塞项: 无 —— 是厂商不发，不是我们读不了。

## Changelog
- 来源: `ChangelogRecipe`（`.gitHubReleases`），
  `https://api.github.com/repos/RockxyApp/Rockxy/releases?per_page=40`
- 跟随 channel: 否（只有一条轨）
- Recipe 状态: 已有

**为什么明明有 inline notes 还要 recipe。** appcast 那一条 `<item>` 的
`<description>` 是真的内联 HTML（1005 字符），面板本来就能渲染 —— 但只有**一条**。
那个文件是原地重写的，历史不在里面，于是版本轨无论用户跳过了多少个构建都只有一格。
GitHub releases 有同一份正文加上完整历史，tag 就是 marketing 版本本身
（`v0.38.2` → `stripLeadingV` → `0.38.2`，与 `CFBundleShortVersionString` 一致）。
recipe 在渲染优先级上高于 `releaseNotesHTML`，所以加了它就是用 20 条历史换 1 条内联。

⚠️ **代价记在这里，而且这条 recipe 是唯一有这个代价的。** `ChangelogPane` 的
`fallback`（recipe 加载**失败**时走的那条）先看 `changelogURL`、后看
`releaseNotesHTML`。Rockxy 的 appcast 两样都给了，于是一次抓取失败
（`api.github.com` 未带 token、60 次/小时/IP，仓库里约 70 个 repo 共用这个额度）
会把面板从「原生渲染的内联 notes」变成「嵌一个 GitHub tag 页」。
Waku 的 appcast notes 是解析不出来的裸 markdown、Shotbase 的 appcast 根本没有 notes，
所以那两条 recipe 没有东西可失去，只有这条有。
**没有顺手把顺序调过来**：对这个 app 而言 `changelogURL` 只是一个 tag 页、内联稳赢，
但对一条 `changelogURL` 指向完整变更日志页的 recipe 而言现在的顺序才是对的 ——
所以那不是一处局部交换能修的事，要修得单独立项。

**不需要 `skipSections`。** 每条 release 正文都以
`> **Distribution notice:** …`（二进制 EULA 声明）开头，但它是引用块、不是顶层
`-`/`*`/`+` 列表项，`GitHubMarkdownParser` 的 strict pass 直接略过。2026-09-09 对
live 页面 40 条全量实测：40/40 有条目、0 prerelease、0 draft、0 空正文，
提取出的条目里「Distribution notice」出现 **0 次**。

## 一键安装
- 状态: 由 Sparkle installer path 决定；无 custom install recipe
- 格式: Sparkle enclosure（`.dmg`）
- **读的是**: 轨道最新 —— 但这里不构成 Phase 3⅞ 说的那种风险：appcast 只有一条
  item，它既是「轨道最新」也是「人人可从厂商 GitHub Release 页手动下载的 GA」，
  厂商没有做灰度分配（无 device id、无 rollout 参数，feed 是一个静态文件）。
- 阻塞: 无。

## 已知问题
- 无。

## 如何复验

```sh
swift run --package-path application-test feed-discover  <Rockxy-<版本>.dmg>
swift run --package-path application-test channel-verify <Rockxy-<版本>.dmg> --expect stable
```

2026-09-09 对 `Rockxy-0.38.2-57.dmg` 跑出来的证据（DMG 只读挂载、未安装）：

| 项 | 值 |
|---|---|
| `feed-discover` | `declared` → `raw.githubusercontent.com/RockxyApp/Rockxy/main/appcast.xml` |
| 真实 bundle id | `com.amunx.rockxy.community` |
| 真实 `CFBundleShortVersionString` / `CFBundleVersion` | `0.38.2` / `57` |
| channel 标记 | `KSChannelID` 无、`RemotingName` 无、`package.json` 无、`ChannelBinding` 无 |
| detected channel | `stable`（`--expect stable` 通过，退出码 0） |
| winning source | `Sparkle` |
| latest / download | `0.38.2` / `.../releases/download/v0.38.2/Rockxy-0.38.2-57.dmg` |
| release notes | 1005 字符 inline，changelogURL 指向 `releases/tag/v0.38.2` |
| status | `up to date` |
| 签名 | `Developer ID Application: Loc Nguyen (9YNS969KZE)`，`spctl` = `Notarized Developer ID` |
| DMG SHA256 | `95c38a821d161a6f747970ea0f16d645757b3c48428a8872920c8655f18818b9`，与厂商同发的 `.dmg.sha256` 及 `releases/latest.json` 的 `checksumSha256` 三方吻合 |

changelog 那半边的回归证据在 `RockxyChangelogRecipeTests`（fixture 是 2026-09-09
的两条真实 release 正文，含那段 Distribution notice 引用块）。

## 建议下一步
1. 检测: 无需改动，`SparkleAppcastSource` 已覆盖。
2. Changelog: 已加 recipe，见上。
3. 顺带记一笔厂商还发了 `releases/latest.json` 和 `releases/catalog.json`
   （schema 化的全量发布目录，带 sha256、EdDSA 签名、`minimum_system_version`）。
   今天用不到 —— Sparkle 已经答了检测、GitHub API 已经答了 changelog ——
   但如果哪天 appcast 挪走了，那两个文件是最省事的替代端点。
