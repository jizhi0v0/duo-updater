# Amp

Sourcegraph 的 AI coding agent macOS 客户端（ampcode.com）。

## 基本信息
- Bundle ID: `com.ampcode.amp.macos`
- Team ID: `PZT9BJUAA5`
- 已安装版本: 1.0 (build 128) — 审计时 feed 最新已到 build 129
- 自更新机制: 标准 Sparkle（`Sparkle.framework` 内嵌 + `SUFeedURL` + `SUPublicEDKey`，无自研 updater）
- 架构: **universal**（x86_64 + arm64 fat binary），不是 arm64-only；DMG 文件名也不带架构 token

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | ✗(无cask) | —   | ✗(无公开仓库) | —      |

当前生效源: **Sparkle**（`SparkleAppcastSource`，通用路径，**无需任何 recipe 或注册**——
`AppScanner` 直接从已安装 bundle 的 `Info.plist` 读 `SUFeedURL` + `Sparkle.framework`
存在性，任何标准 Sparkle app 天然被发现）

- Homebrew: 无 cask（`brew search amp` 命中的都是无关包，`brew info --cask amp` 报不存在）。
- GitHub: `sourcegraph/amp`、`sourcegraph-community/amp` 均 404，无公开发布仓库。
- 结论: 不需要写任何代码——这次审计是"确认已经工作"，不是"接入"。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.ampcode.amp.macos` | — | — | — | ✓ |

单渠道。feed 里全部 10 个 `<item>` 都无 `<sparkle:channel>`，无迹象表明存在 beta/canary 轨。

## 更新检测
- 源: Sparkle appcast `https://static.ampcode.com/mac/appcast.xml`（GCS 托管，`br` 编码，
  `Cache-Control: no-cache, max-age=0, must-revalidate`——本身就会 revalidate，不受
  `duo-updater-version-feed-cache-policy` 那类"永久缓存"陷阱影响）。
- 版本方案: `sparkle:shortVersionString` 长期停在 `1.0`（marketing 版本不动），真正递增的是
  `sparkle:version`（build number，如 128→129，审计当天几小时内跳了好几个 build）。
  `SparkleAppcastSource.comparisonKey` 本来就优先取 `version`（build）而非
  `shortVersionString`——这正是这类"marketing 版本长期静止"的 vendor 需要的行为，
  Amp 不需要任何特殊处理就落在这条路径上。
- 现场验证: `duo check "/Applications/Amp.app" --json` 实测返回
  `{"hasUpdate":true,"installedBuild":"128","latestBuild":"129","latestVersion":"1.0","route":"in-place","source":"Sparkle"}`，
  与直接拉取的真实 feed（同一时刻最新 item 也是 `sparkle:version=129`）完全对得上。
- 无 `sparkle:minimumAutoupdateVersion` / `sparkle:hardwareRequirements` / delta，feed 结构
  是这几个月新 app 里少见的"干净"标准 Sparkle。

## Changelog
- 来源: 无。feed 的 10 个 `<item>` 全部没有 `<description>` / `<markdownDescription>`，
  `SparkleAppcastSource.structuredChangelog` 因此返回 nil，UI 会回退到（不存在的）
  `releaseNotesLink`——即基本不展示更新说明，只展示版本号跳动。这是 vendor 侧的现状，
  不是我们这边能修的东西。
- 跟随 channel: 不适用（单渠道）。
- Recipe 状态: 不需要（ChangelogRecipe 只在"有笔记但格式非结构化"时才有用；这里是
  "vendor 压根没发笔记"，写 recipe 也无米下锅）。

## 一键安装
- 状态: **支持**（标准 Sparkle in-place 路由，`SparkleInstaller` 通用逻辑，**非** VendorProbe
  的 Team-ID 门）
- 格式: dmg，`Amp-1.0-<build>.dmg`，~5.4MB，`sparkle:edSignature` 逐条签名
- 验证: `Info.plist` 有 `SUPublicEDKey`（`52CYhpBx3hVGP+44+5iNNNdzxxyzL1U1ilqe5Q8aeoA=`），
  Sparkle 自己的 ed25519 签名校验覆盖了下载完整性，不依赖 duo-updater 另外做 Team ID 比对
- 阻塞: 无

## 已知问题
- `/Applications` 下同时存在 `Amp.app` 与 `Amp 2.app`（本机残留的重复安装，与本次审计
  无关，`duo check amp` 会因为重名报歧义、需要按路径消歧）。

## 建议下一步
无代码改动。这是一次"零接入成本"确认：Amp 是标准 Sparkle app，`SUFeedURL` +
`Sparkle.framework` + `SUPublicEDKey` 齐全，duo-updater 的通用 Sparkle 路径（检测 + 一键
安装）开箱即用。唯一的缺口（无 changelog）是 vendor 没发笔记，不是我们的问题。
