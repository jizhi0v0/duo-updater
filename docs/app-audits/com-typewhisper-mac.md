# TypeWhisper

## 基本信息
- Bundle ID: `com.typewhisper.mac`
- Team ID: `2D8ALY3LCL`
- 观测版本: `1.6.0` (build `1091`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://typewhisper.github.io/typewhisper-mac/appcast.xml`）
- 分发: GitHub Releases (`TypeWhisper/typewhisper-mac`) / Homebrew cask `typewhisper`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |
| **release-candidate** | ✓ | — | — | — | — |
| **daily**  | ✓       | —        | —   | —     | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe；三条轨都靠 feed 的 `<sparkle:channel>` 标记分轨）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.typewhisper.mac` | 共享 | — | default（无标记） | ✓ |
| release-candidate | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>release-candidate` | ✓ |
| daily   | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>daily` | ✓ |

共享 bundle id。appcast 3 条（观测 2026-08-30）：default = `1.6.0/1091`（stable），
`release-candidate` = `1.6.0-rc2/1083`，`daily` = `1.7.0-daily.20260830/1161`。
三轨互不串：`usableItems` 只允许装机 build 命中的那条 channel + 始终开放的 default 轨。

> ⚠️ 2026-08-31：rc 轨当时**没有真的分出来**。rc2 包的
> `CFBundleShortVersionString` 是 `1.6.0`——跟 default 条目一模一样（版本号在 feed 里
> 才带 `-rc2`，包里不带），而 `channel(ofInstalled:)` 当时按文档序取第一个「build 命中
> **或** short 命中」的条目，于是排在前面的 default 条目先靠 short 命中，rc 条目那个精确的
> build `1083` 没机会比。rc 安装被判成 stable。daily 轨没事，因为它的包 short 是
> `1.7.0`，不撞。
>
> 表现不是推错版本（当天 default head 1091 本来就比 rc 1083 新，两边都会提供它），而是
> **rc 用户自己那条轨消失**：rc 条目被 `usableItems` 滤掉，rc 轨再往前走也收不到。
> 已修为两趟匹配（先全表比 build，再全表比 short）。**装 rc2 真包上机复验过**：
> 修前 `releaseHistory` 1 条，修后 2 条（default + rc）。

配套的一个 GitHub 陷阱（写进 audit 免得下一个人踩）：该 repo 的**非 prerelease
release 全是 plugin 包**（`plugin-whisperkit-v1.2.0` 等，资产只有插件 zip），app
本体走 prerelease 的 daily tag。如果有人给这个 bundle 加 GitHub rule，
`/releases/latest` 会指到最新的 plugin release——GitHub 源不是这个 app 的版本面，
Sparkle feed 才是。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short 与 build 双轨；比较落在 build，显示走 short。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: **`ChangelogRecipe`**，解官网 https://www.typewhisper.com/en/changelog/
- 跟随 channel: **否**——静态 HTML 只有 stable 卡片；daily / RC / 插件版藏在「Show pre-releases」
  开关后面，由前端拉 `prereleases.json` 渲染。装 rc / daily 看到的是 stable 说明，每条带自己的版本号。
- Recipe 状态: 2026-08-31 新增；2026-10-03 官网改版后重写（#956）
- ⚠️ 2026-08-31 更正：原先写「Sparkle inline（feed `<description>`）」，是错的。
  feed 3 条**一条都没有** `<description>`，真包跑生产链拿到 0 字符 —— 此前没有任何说明。
- 这张页面**同时列 macOS 和 Windows 两个产品**，所以 `entryPattern` 锚在卡片的
  `id="mac-v<tag>"` 上（平台和版本都在里面）；锚错了就会把 Windows 的说明挂到 Mac 版本下面。
  版本取自 `id` 而不是可见标题：少数标题是自由文本（「TypeWhisper 1.0」「v0.7.0 - Notch Indicator」）。
- 卡片内部用 tempered 惰性扫描（止于 `</details>`）而不是 `.*?`：有少数老卡片没有正文块，
  裸 `.*?` 会越过它跑进下一张卡片，把后者的说明记到前者的版本上。

## 一键安装
- 状态: **支持**（Sparkle 原生路径，各轨 feed enclosure）
- 格式: `TypeWhisper-v{ver}.zip`
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，v1.6.0 解包）: `com.typewhisper.mac` / `1.6.0` / build
  `1091`，Team `2D8ALY3LCL`，notarized

## 已知问题
- **changelog 页把 stable 和 daily 两条轨按日期混排在一个列表里**，所以「最新一条」在版本号上
  会合法地倒退。2026-09-18 实测页面顶部的 macOS 卡片依次是
  1.6.1 → 1.7.0-daily.20260916 → 1.7.0-daily.20260913 → 1.7.0-daily.20260912 → 1.7.0-daily.20260911：
  stable 1.6.1 发布后压在了几条 daily 之上。recipe 取的就是第一张 macOS 卡片，行为符合设计
  （recipe 注释本来就写着「stable 装机会看到自己版本之上的 daily 条目」）。
  这触发过 `duo verify` 的「version went BACKWARDS」（#698，连报六轮）——**判据错，不是 recipe 错**：
  该检查假设「最新条目的版本单调不降」，这对按日期混排两条轨的页面不成立。
  已在 `Baseline.pageStillCarries` 修正：只有当基线那个版本**还在页面上**时才放行
  （厂商在其上发了新条目 → 还在，往下挪一行；pattern 滑到更旧的段落 → 掉出顶部）。
  2026-10-03 改版（#956）后服务端 HTML 只剩 stable，这种倒退不再出现；`pageStillCarries` 的修正仍然有效。

## 如何复验
```
# GET https://typewhisper.github.io/typewhisper-mac/appcast.xml
#   → 3 条：default=1.6.0，rc=1.6.0-rc2，daily=1.7.0-daily.20260830
# 解包 TypeWhisper-v1.6.0.zip → com.typewhisper.mac / 1.6.0 / 1091
# channel-verify --check com.typewhisper.mac → winning=Sparkle, up to date
```

## 建议下一步
无。三轨检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-typewhisper-mac.swift — ChangelogRecipe（mac 与 Windows 卡片数）

转引自 recipe 注释，未复测。整段原文；代码里的卡片数改成了「History has the card counts」。原句没写日期，引入它的提交是 `cff8d0ed`（2026-08-31）。

TypeWhisper — no notes in the appcast either. The official changelog
page is the vendor's own, and it interleaves **macOS and Windows**
releases in one list (203 mac cards, 167 Windows ones), so the entry
pattern is anchored on the platform badge that precedes the version
heading. Getting that wrong shows Windows notes under a Mac version.

### Recipes/com-typewhisper-mac.swift — ChangelogRecipe（tempered 扫描修掉的两条跨卡片条目）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（普通惰性扫描会越过没有 prose 的卡片、把下一张卡的说明挂到错版本上；tempered 之后没有条目跨卡片），当时出错的两个版本和「194 entries」搬到这里。原句没写日期，引入它的提交是 `cff8d0ed`（2026-08-31）。

The gap between the heading and the date is a TEMPERED lazy scan
(`(?:(?!>macOS</span><h3|>Windows</span><h3).)*?`), not a plain `.*?`:
a handful of old cards carry no prose block, and a plain lazy scan ran
past them into the NEXT card and filed its notes under the wrong
version — two entries did exactly that (0.6.1, 0.5.1) before this was
tempered. With it: 194 entries, none spanning a card boundary.

### 2026-10-03 官网改版（#956）

`duo verify` 连续两轮报 `noEntriesExtracted`。官网换成 Astro 新版式：卡片变成
`<details class="utility-entry" id="mac-v1.7.0" data-platform="mac" …>`，旧 pattern 锚的
`>macOS</span><h3` 和 `text-muted-foreground` 日期行都没了。服务端 HTML 只剩 stable：
87 张卡片（48 mac / 39 Windows，`data-kind` 全是 `stable`），其中 9 张 mac 卡片写着
「No detailed release notes.」没有正文块。新 pattern 在实拉页面上出 39 条 mac 条目，
最新 1.7.0（October 2, 2026），没有条目跨 `</details>`，每条版本都等于它所在卡片 id 的版本。
pre-release 走 `/en/changelog/prereleases.json`（JSON 里装着同样版式的 HTML 片段），recipe 不读它。
