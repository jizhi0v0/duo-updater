# Mac Performance Monitor

审计日期：2026-09-06。**结论：接 changelog（用户提的 #374），检测本来就已经覆盖。**

## 基本信息

- Bundle ID：`uk.co.bzwrd.macperfmonitor`
- 仓库：[Zesty0wl/mac-performance-monitor](https://github.com/Zesty0wl/mac-performance-monitor)
- `SUFeedURL`：`https://github.com/Zesty0wl/mac-performance-monitor/releases/latest/download/appcast.xml`
  —— 指向 **release 资产**，不是仓库里的文件（`raw.githubusercontent.com/.../main/appcast.xml` 是 404）。
- 观测版本：`1.7.1` / build `206`（2026-09-05 那条 release）
- 每条 release 三个资产：`appcast.xml`、`MacPerformanceMonitor-<版本>.zip`、`MacPerformanceMonitor.pkg`

以下都是打真实端点量的。

## 为什么需要一条 changelog recipe

appcast 里**一条说明都没有**。真实响应体（2026-09-06 取那个 release 资产，987 字节）：

```
items: 1
version 206 / shortVersionString 1.7.1
releaseNotesLink:     无
fullReleaseNotesLink: 无
description:          无
子元素: title pubDate link version shortVersionString minimumSystemVersion
        hardwareRequirements enclosure
```

GitHub release 正文也不是说明，是一句指路（75 字节）：

> Mac Performance Monitor 1.7.1 (build 206). See CHANGELOG.md for what's new.

所以 issue 说的是对的：真正的说明只在仓库的 `CHANGELOG.md` 里，格式是 Keep a Changelog。

更正 2026-09-14：上面三段写的是审计当天（1.7.1 及以前）的 appcast 与 release 正文。按 release 取回的
`appcast.xml` 资产（`gh api …/releases/assets/<id>`，15:13 UTC）：`v1.7.1.206` 987 B、1 个 `<item>`、
0 个 `<description>`；`v2.0.0.231` 5,771 B 与 `v2.1.0.236`（当前 latest）5,520 B 都是 1 个 `<item>`、
1 个 `<description>`（2.1.0 那条是整篇 HTML 说明），三份都没有 `releaseNotesLink` / `fullReleaseNotesLink`。
2.0.0（2026-09-10）与 2.1.0（2026-09-11）两条 release 的正文也已带完整说明。两处都只覆盖最新一版，
历史仍只在 `CHANGELOG.md` 里：它有这两版的条目，recipe 的 entry pattern 在当天的文件上解析出 19 条
（`gh api …/releases` 与只读 GET raw `CHANGELOG.md`）。

## Recipe

```
source        raw.githubusercontent.com/Zesty0wl/mac-performance-monitor/main/CHANGELOG.md
entryPattern  (?:^|\n)##\s+\[(?<version>[0-9][^\]]*)\]\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)
itemPatterns  \n-\s+(?<item>.+?)(?=\n-\s|\n###\s|\n##\s|\n\[|\z)
markdownSource: true
headingPattern  \n###\s+(?<heading>[^\n]+)
```

更正 2026-09-15：上面这块以前的 `itemPatterns` 没有 `\n\[`，也没有 `headingPattern` 这一行，
与代码不符。`\n\[` 是 `bf5db16b`（2026-09-06）加进代码的（下面「第三处」写的就是它），
`headingPattern` 是 `e57d1f47`（#562，2026-09-12）加的；这块两次都没跟着改。现在按
`Recipes/uk-co-bzwrd-macperfmonitor.swift` 的 `ChangelogRecipe` 逐字补上。

跟仓库里那条同形的 CopilotForXcode recipe（也是读 repo 的 `CHANGELOG.md`）比，两处不同，
都是这份文件逼出来的：

1. **版本号带方括号**，而且方括号里要求首字符是数字 —— 这一条是用来挡掉文件顶部的
   `## [Unreleased]`。那是个有真实条目的小节，描述的是还装不了的构建。
2. **条目要跨行**。这个作者把 bullet 折在 ~78 列、续行缩进两格，所以别的 recipe 通用的
   `[^\n]+` 会把大多数条目截在半句话上（"…every CPU instruction-set" 就没了）。
   现在是懒扫描，扫到下一个 bullet、下一个 `###` 组标题、下一个 `##` 条目、
   文件末尾的链接定义块（`\n\[`，见下面第三处）或结尾为止。

⚠️ 第三处，是复审补的：条目的终止条件里必须有 **`\n\[`**。Keep a Changelog 的文件末尾是
一整块链接定义（`[1.3.2]: https://…/compare/…`），而最后一条 entry 的 body 一直跑到文件尾，
所以没有这个边界时，**最老那条的最后一项会把 17 条链接全吞进去** —— 实测 1709 字符，
加上边界之后 137 字符。不缩进，所以不会误伤这个作者两格缩进的续行。

### 实测

- 真实文件 43,695 字节，18 个 `## [` 标题，其中 1 个是 `[Unreleased]`。
  解析出 **17 条**，正好是全部已发布版本，`[Unreleased]` 没有混进来。
- 头条 `1.7.1` / `2026-09-03`，条目是完整句子，`### Fixed` / `### Changed` 这类组标题
  没有变成条目。
- 加上链接边界前后：**17 条 entry、每条的条目数一个没变**，没有任何一项再带链接定义；
  最长的条目 1919 字符是真的（这个作者的 bullet 就写这么长，句子结尾干净）。
- `duo verify --only macperf` 打真实端点：`changelog ✓ 1`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | ✓ 检测（bundle 自带 `SUFeedURL`） | ○ 仓库里有 `Casks/` | — | ○ | — |

检测一直是通的（Sparkle 源读它自己的 appcast），这次补的只是**说明**。

## 没做的

- **没验过真包**：没有下载 zip/pkg 核对 Team ID、公证和版本字段。接的是 changelog，
  不碰安装路径，所以没做这一步；要接一键安装必须先补上。
- 仓库里有 `Casks/`，Homebrew 那条路没查。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/uk-co-bzwrd-macperfmonitor.swift — ChangelogRecipe（appcast 与 release 正文都没有说明）

转引自 recipe 注释，未复测。整段原文。"one item" 这个观测值搬到这里；"its appcast carries no notes at all" 与 "The GitHub release body is one sentence that says where to look" 迁移时都已不成立，代码里改写了，见下面的更正；其余原样。

Mac Performance Monitor — its appcast carries no notes at all: one item,
and no `sparkle:releaseNotesLink`, no `sparkle:fullReleaseNotesLink`, no
`<description>` (fetched 2026-09-06 from the `appcast.xml` asset its
`SUFeedURL` points at). The GitHub release body is one sentence that
says where to look: "Mac Performance Monitor 1.7.1 (build 206). See
CHANGELOG.md for what's new." Requested in #374.

更正 2026-09-14（`gh api 'repos/Zesty0wl/mac-performance-monitor/releases?per_page=10'`、`…/releases/latest`，14:19 UTC；只读 GET raw `CHANGELOG.md`，14:20 UTC）：`v1.7.1.206` 及以前的正文仍是那一句指路；`v2.0.0.231`（2026-09-10）与 `v2.1.0.236`（2026-09-11）的正文是带标题的完整说明；`CHANGELOG.md` 有 `[2.1.0]` 与 `[2.0.0]` 两节，recipe 的 entryPattern 在当天的文件上解析出 19 条。按 release 取回的 `appcast.xml` 资产（`gh api -H 'Accept: application/octet-stream' …/releases/assets/<id>`，15:13 UTC）：`v1.7.1.206` 987 B、1 个 `<item>`、0 个 `<description>`；`v2.0.0.231` 5,771 B 与 `v2.1.0.236`（当前 latest）5,520 B 都是 1 个 `<item>`、1 个 `<description>`，2.1.0 那条是整篇 HTML 说明；三份都没有 `releaseNotesLink` / `fullReleaseNotesLink`。代码里改成：到 1.7.1 为止 appcast 没有说明、release 正文是那一句；2.0.0 起 appcast 唯一的那条带 HTML `<description>`、正文也带说明，都只覆盖最新一版，所以历史仍只有这条 recipe 读得到；`CHANGELOG.md` 两版都有条目。同一说法的副本一并改了：`Tests/DuoUpdaterCoreTests/MacPerformanceMonitorChangelogRecipeTests.swift` 的文档注释、本审计「为什么需要一条 changelog recipe」一节（加了更正）、`docs/app-audits/README.md` 的索引行（同一行里的条数也按 rule 5 补上了复测的 19 条）。

### Recipes/uk-co-bzwrd-macperfmonitor.swift — ChangelogRecipe（item pattern 的链接定义边界）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（不加这个边界，最老那条的最后一项会吞下整个链接块），被吞下的链接数、两种长度的实测与 "the same 17 entries" 里的条数搬到这里（原句没写日期，引入它的提交是 `bf5db16b`，2026-09-06）；其余原样，重新折行。本审计也记着同一组数。

⚠️ `\n\[` is in that list because the file ends with the link-reference
block the format prescribes (`[1.3.2]: https://…/compare/…`), and the
last entry's body runs to `\z`. Without that boundary the oldest entry's
final bullet swallowed all 17 of them — measured at 1709 characters of
prose plus compare URLs, against 137 with it. Nothing else changes: the
same 17 entries parse with the same item counts, and no item carries a
link definition any more. Unindented, so it cannot fire on a wrapped
continuation line, which this vendor indents by two spaces.
