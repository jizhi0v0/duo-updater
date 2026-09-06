# WhatCable

## 基本信息
- Bundle ID: `uk.whatcable.whatcable`
- Team ID: `M4RUJ7W6MP`（Developer ID Application: Darryl Morley）
- 观测版本: stable `1.4.0`（build `130`）· beta `1.5.0-beta.8`（build `137`）
- 架构: universal（`lipo -archs` → `x86_64 arm64`）
- `LSMinimumSystemVersion`: 14.0
- 自更新机制: **app 自带更新器，直接读 GitHub Releases**（不是 Sparkle——
  仓库 `Package.swift` 里没有 Sparkle 依赖，bundle 里没有 `SUFeedURL`）
- 分发: GitHub Releases（`darrylmorley/whatcable`）+ Homebrew cask `whatcable`
  （`auto_updates: true`）+ 官网 whatcable.uk
- 开源: 是（仓库公开）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub Releases**（两条 rule，各自 `channel` 门控）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `uk.whatcable.whatcable` | 共享 | 版本串**无**后缀 | `/releases/latest`（GitHub 不返 prerelease）| ✓ |
| beta | 同上 | 共享 | `CFBundleShortVersionString` = `1.5.0-beta.8` → `ReleaseChannel.detect` 第 4 步 | `usePrereleases: true` + 锚定 `-beta.<N>` 的 versionPattern | ✓ |

**为什么 beta 这条必须有**：beta 包的 marketing 串原样带 `-beta.8`（实测 v1.5.0-beta.8
的 Info.plist），`detect` 判为 `.beta`，stable rule 的 channel 闸就会拒它——没有 beta
rule 的话，一个 beta 安装会**没有任何源**、行永远显示 Failed。这是 `VendorProbeRecipe`
里 Alfred `.beta` 那条注释记录过的同一个形状。

### 未覆盖的那一半：app 内的 beta 开关

WhatCable 设置里有 "Receive beta updates"，落盘在 `uk.whatcable.whatcable` 的
`receiveBetaUpdates` key（源码 `Sources/WhatCable/App/AppSettings.swift`）。它的注释
自己写着：关掉时"the updater keeps hitting `releases/latest`, which GitHub never
returns a pre-release from"。

我们**没有读这个 key**。缺口是单向的、已知的：一个跑 **stable** 构建但把开关打开的用户，
厂商自己的更新器会给他 beta，我们只给 stable。反方向——把 beta 推给没开开关的人——不可能
发生，因为 beta rule 只对**已经在跑 beta** 的副本生效。补上要写一个 `ChannelBinding`，
记在 `CHANNEL_COVERAGE_TODO.md` §2，不在本次范围内。

## 更新检测
- stable: `/releases/latest`，tag `v1.4.0`，pattern `^v([0-9]+(?:\.[0-9]+)+)$`
- beta: releases 列表，pattern `^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$`
  —— **后缀必须保留**（截成 `1.5.0` 会让每个 beta 都读成比自己新），
  **而且 stable tag 也要收**，见下。
- `listPageSize: 5`（实测 2026-09-06，最新 100 个 release：**100 条全部匹配**这条 pattern
  且全部带 `WhatCable.zip`，首命中 index 0、gap 0，地板是 1；留 5 是给草稿/平台缺件的余量。
  gzip 后 per_page=5 是 5.9 KB，默认的 20 是 23.8 KB。`probesNewestFirst` 让常规一轮其实
  只取 1 条。）

### beta pattern 为什么收 stable tag

厂商自己的更新器在同一份源码里写着这条轨的语义："the updater still picks whichever
release is newest, so a stable always supersedes its own betas."。锚死 `-beta.` 会同时踩两个坑：

1. **跑 `1.5.0-beta.8` 的副本永远等不到毕业版 `1.5.0`**，得干等到下一轮 `1.6.0-beta.1`。
   `VersionComparator` 本身是对的（少的第 4 段补 `.number(0)`，数字压 `.text("beta")`，
   所以 `1.5.0 > 1.5.0-beta.8`），挡路的只有 pattern。
2. **更要命的是它是一根引信。** 厂商一旦停发 beta，锚死的 pattern 在整页里匹不到任何东西，
   而 `duo verify` 扫的是 rule 不是安装，于是**每台机器上这条都变红**，而 rule 本身完全正常。
   这不是假想：这个仓库前 **79 个 release 根本没有 beta 轨**，第一条 `v1.2.0-beta.1` 在
   index 20。

代价是 beta 安装可能被交付一个 GitHub 标为 stable 的构件——和 UTM 的 `.beta` rule 一样，
理由也一样（预览会毕业进同一条编号线，不是平行轨）。装完之后 `detect` 判为 `.stable`，
行自然转到 stable rule，方向是单向的。
- 版本方案: tag 去 `v` 即 marketing 串，与 bundle 同构。build（`CFBundleVersion`）
  单调递增（127 → 130 → 137）但 GitHub 不发布它，比较只用 marketing。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 非 Sparkle，无 delta 概念 | 无 | 不能 |
| 证据 | 仓库无 Sparkle 依赖 | 每个 release 只有 `WhatCable.zip` + `whatcable-cli-<ver>.zip` | — |

## Changelog
- 来源: **GitHub release body**，`GitHubMarkdownParser` 原生渲染，**不需要
  ChangelogRecipe**。
- 质量: v1.4.0 的 body 是几百字的分区 Markdown（`## Connected devices` /
  `## Speed verdicts`…），每条 bullet 还带 issue 号和致谢。beta 也有正文
  （beta.7/beta.8 只有标题、没有分区，属于正常的短说明）。

## 一键安装
- 状态: **支持**（两个 channel 都支持）
- 格式: zip —— 资产名两条轨**完全相同**：`WhatCable.zip`
- 资产 pattern: `^WhatCable\.zip$`。同 release 里的 `whatcable-cli-<ver>.zip` 是独立的
  CLI 产物（app bundle 内部另有一份 `Contents/Helpers/whatcable`，Homebrew cask 就是
  symlink 那份），锚定后不会串。
- 包验（2026-09-06，真实下载解包）:
  - v1.4.0 → `WhatCable.app` / `uk.whatcable.whatcable` / `1.4.0` / build 130 /
    universal / `Developer ID Application: Darryl Morley (M4RUJ7W6MP)` /
    `spctl` = `Notarized Developer ID`
  - v1.5.0-beta.8 → 同 bundle id、同 Team、`1.5.0-beta.8` / build 137
  - 两条轨 Team 相同 → 签名闸拦不住跨轨，靠 channel 闸 + channel proof
- Channel proof: `.recipeAnchor(#"^true$"#, in: ["usePrereleases"])`，**不是
  `.artifact`**。两条轨文件名一模一样（都叫 `WhatCable.zip`），tag 路径段是唯一的判据——
  可这条 rule 是**故意**允许解析出 stable tag 的，artifact proof 会在一次**合法**解析上开火。
  剩下能锚的只有请求：`usePrereleases` 就是这条 rule 全部的渠道身份，它决定读 releases 列表
  还是 `/releases/latest`（后者 GitHub 定义上不返 prerelease）。把它翻成 false，beta rule
  会**无声地变成第二条 stable rule**——不报错、版本也在，只是 beta 用户从此收不到 beta。
  ⚠️ 和 UTM 那条一样要说清够不到什么：它看不见"厂商开了第三条同名轨"，也不说被选中的是哪个
  release。这与 `bindingProofs` 是同一种、同一强度的主张。

## 已知问题
- **beta 安装会被交付 stable 构件**（当 stable 是最新那条时）。这是上面写的刻意取舍，
  也是厂商自己更新器的行为；反方向不会发生。
- **UTM 那条路没走**：`candidateScope: .installedMajorLineOrNewestStable` +
  `installedTagPrefix` 也能处理"预览毕业"，但它的天花板管的是「把预览关在自己的**大版本线**
  里」——WhatCable 没有这个问题（只有一条线，beta 就是下一个 release，不是平行的 v-next），
  所以用不上那套额外机械。
- Homebrew cask 存在但 `auto_updates: true`，按本仓库既定策略不作为源。

## 如何复验
```
# GET https://api.github.com/repos/darrylmorley/whatcable/releases/latest → v1.4.0
# GET .../releases?per_page=5 → 首条 v1.5.0-beta.8（prerelease）
# 解包 WhatCable.zip → uk.whatcable.whatcable / Team M4RUJ7W6MP / notarized
duo verify --only whatcable
```

## 建议下一步
- `ChannelBinding` 读 `receiveBetaUpdates`，覆盖"stable 构建 + 开了开关"这一格。
