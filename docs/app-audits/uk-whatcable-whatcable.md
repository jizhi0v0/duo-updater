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
| beta | 同上 | 共享 | `CFBundleShortVersionString` = `1.5.0-beta.8` → `ReleaseChannel.detect` 第 4 步 | `usePrereleases: true`（读 releases 列表而不是 `/releases/latest`）| ✓ |

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
   这不是假想：第一条 beta 是 `v1.2.0-beta.1`，它是这个仓库 **135 个 release 里的第 115 个**
   （从最新往回数是 index 20）。**之前这里写的「前 79 个」是错的**——那是把「最新 100 条那一页
   里的位置」当成了「仓库历史里的位置」。

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
  `## Speed verdicts`…），每条 bullet 还带 issue 号和致谢。beta 也有正文，但 beta.7/beta.8 是
  33 个词的固定样板（"Beta build for testers. Not recommended for general use…"），0 个
  `##` 分区——不是「只有标题」，是「每条都一样的套话」。

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
- Channel proof: `.recipeAnchor(#"^true$|-beta\\\."#, in: ["usePrereleases", "versionPattern"])`,
  **不是 `.artifact`**。两条轨文件名一模一样（都叫 `WhatCable.zip`），tag 路径段是唯一的判据——
  可这条 rule 是**故意**允许解析出 stable tag 的，artifact proof 会在一次**合法**解析上开火。
  剩下能锚的只有请求，而请求这一半**分在两个字段上**，各锚各的：`usePrereleases` 决定读
  releases 列表还是 `/releases/latest`（后者 GitHub 定义上不返 prerelease），`versionPattern`
  决定取回来之后**认不认** prerelease。任一被改，beta rule 都会**无声地变成第二条 stable
  rule**——不报错、版本也在，只是 beta 用户从此收不到 beta。
  ⚠️ **不要只锚 `usePrereleases`**：这个仓库里有三条 **stable** rule 也设了它
  （`com.insomnia.app` / `com.bitwarden.desktop` / `com.microsoft.Headlamp`），所以它单独
  根本不是 beta 专有属性。第一版就是这么写的，而且还在注释里声称它「是这条 rule 全部的渠道
  身份」——两句都不对。
  ⚠️ 和 UTM 那条一样要说清够不到什么：它看不见"厂商开了第三条同名轨"，也不说被选中的是哪个
  release（`.recipeAnchor` 分支根本不看解析出来的 artifact）。

## 已知问题
- **beta 安装会被交付 stable 构件**（当 stable 是最新那条时）。这是上面写的刻意取舍，
  也是厂商自己更新器的行为；反方向不会发生。
- ⚠️ **而且这一步是单向的**：装完 `1.5.0` 之后 `detect` 判 `.stable`，下一轮起这台就由
  stable rule 服务，**我们不会再给它 beta**。两条 rule 都没设 `installedTagPrefix`，所以那条
  「跨安装记住渠道」的 discovery 路径在这里根本走不到。厂商自己的更新器（它读
  `receiveBetaUpdates`，我们不读）会继续给这类副本发 beta、把它带回 beta 轨——所以这跟上面
  那个「stable 构建 + 开关打开」是同一个缺口的另一面，补法也是同一个 `ChannelBinding`。
  **在补上之前，是 DuoUpdater 自己把用户送进那个格子的。**
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

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/uk-whatcable-whatcable.swift — stable GitHubReleaseRule（固定的资产名）

转引自 recipe 注释，未复测。整段原文；代码里 "on every one of the newest 100 releases (measured 2026-09-06)" 改成 "on every release checked (2026-09-06 and 2026-09-14; History has the counts)"；其余原样，重新折行。

WhatCable — an open-source menu-bar app (`uk.whatcable.whatcable`) that
reads what each USB-C/Thunderbolt cable plugged into the Mac can
actually do. Distributed from its own GitHub releases: one constant
asset name, `WhatCable.zip`, on every one of the newest 100 releases
(measured 2026-09-06). The `whatcable-cli-<version>.zip` beside it is
the standalone CLI, a different artifact — the app bundle ships its own
copy at `Contents/Helpers/whatcable`, which is what Homebrew's cask
symlinks — so the pattern is anchored end to end and cannot drift onto
it.

复测 2026-09-14（13:57 UTC，`gh api 'repos/darrylmorley/whatcable/releases?per_page=100'` 两页）：共 135 个 release，135 个都有 `WhatCable.zip`。

### Recipes/uk-whatcable-whatcable.swift — stable GitHubReleaseRule（一键 zip 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（资产里的 app、bundle id、short == tag、universal、签名者与 spctl、与装机副本同 Team），核对日期挂在句末，当时的版本号搬到这里。

One-click verified 2026-09-06 on the real v1.4.0 asset: `WhatCable.app`,
`uk.whatcable.whatcable`, CFBundleShortVersionString 1.4.0 == the tag,
universal (x86_64 + arm64), signed "Developer ID Application: Darryl
Morley (M4RUJ7W6MP)" and accepted by `spctl` as Notarized Developer ID —
the same Team as the installed copy, so the swap passes the
VendorInstaller gate.

### Recipes/uk-whatcable-whatcable.swift — beta GitHubReleaseRule（为什么必须有这条）

转引自 recipe 注释，未复测。整段原文。末句 "documented on its `.beta` recipe in `VendorProbeRecipe`" 指的位置迁移时已不对，代码里改了，见下面的更正；其余原样。

WhatCable beta — the same repo's prerelease train, and it MUST exist
rather than being left to the stable rule. The betas ship a version
string the bundle keeps verbatim (`CFBundleShortVersionString` reads
"1.5.0-beta.8", confirmed on the real v1.5.0-beta.8 artifact), which
`ReleaseChannel.detect` step 4 resolves to `.beta` — so a beta install
is refused by the stable rule's channel gate and, without this, would
have no source at all and read "Failed" indefinitely. That is not
hypothetical: it is the exact shape of the Alfred regression documented
on its `.beta` recipe in `VendorProbeRecipe`.

更正 2026-09-14：写这句时（`75802fee`，2026-09-06）Alfred 的 `.beta` recipe 在 `Sources/VendorProbeRecipe.swift`（`git grep -n "Alfred, PRE-RELEASE channel" 75802fee` → 第 1138 行）；拆分提交 `4adf2227`（2026-09-14）之后它在 `Recipes/com-runningwithcrayons-Alfred.swift:8`。代码里改成指向那个文件。

### Recipes/uk-whatcable-whatcable.swift — beta GitHubReleaseRule（pattern 为什么也收 stable tag：保险丝那一条）

转引自 recipe 注释，未复测。整段原文；两条缩进的要点整体用代码块围起来。代码里 "release 115 of the 135 this repo has published" 改成 "more than a hundred releases into this repo's history (History has the count)"（原句没写日期，引入它的提交是 `d8c3a6dc`，2026-09-06），「之前的草稿写成 79」那句更正的经过搬到这里；其余原样。本审计也记着 135 与 115。

```
  • A copy on `1.5.0-beta.8` would never be offered the plain `1.5.0`
    that graduates from it — it would sit on a superseded prerelease
    until the next cycle opened. `VersionComparator` ranks the
    graduation correctly (a missing 4th component pads to `.number(0)`
    and beats `.text("beta")`), so the only thing standing in the way
    was the pattern.
  • Worse, it is a fuse. If this vendor pauses the beta train, a
    `-beta\.`-only pattern matches nothing in the page, and the miss is
    a red `duo verify` finding on EVERY machine — the sweep walks rules,
    not installs — for a rule that is working exactly as written. Not a
    remote prospect: the beta train did not exist at all until
    `v1.2.0-beta.1`, release 115 of the 135 this repo has published.
    (An earlier draft said "79 releases in". That was a position inside
    the newest-100 page read as a position in the repo's history.)
```

复测 2026-09-14（同一次两页读取，按 `created_at` 排序）：`v1.2.0-beta.1` 是 135 个里的第 115 个（2026-07-15），也是最早的 `-beta.` tag。

### Recipes/uk-whatcable-whatcable.swift — beta GitHubReleaseRule（`listPageSize`）

转引自 recipe 注释，未复测。整段原文；代码里的 `listPageSize` 一句改成说条件（核对过的 release 的 tag 都匹配这条 pattern、都带 `WhatCable.zip`，所以首个匹配就在第 0 位），测量范围、日期与两种页大小搬到这里；其余原样，重新折行。

listPageSize: measured 2026-09-06 over the newest 100 releases — every
one of the 100 tags matches this pattern and carries `WhatCable.zip`,
so first-match index is 0 and the gap is 0. The floor is 1; 5 is kept
for headroom against a draft or a platform-partial release, and costs
5.9 KB gzipped against 23.8 KB at the default 20. `probesNewestFirst`
means the common round is a page of one anyway.

复测 2026-09-14（同一次两页读取）：135 个 tag 全部匹配 `^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?)$`，135 个都带 `WhatCable.zip`；最新的是 `v1.5.0-beta.8`（prerelease，2026-08-31）。页大小没有复测。
