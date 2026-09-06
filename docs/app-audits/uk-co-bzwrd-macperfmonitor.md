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

## Recipe

```
source        raw.githubusercontent.com/Zesty0wl/mac-performance-monitor/main/CHANGELOG.md
entryPattern  (?:^|\n)##\s+\[(?<version>[0-9][^\]]*)\]\s*-\s*(?<date>[^\n]+)\n(?<body>.*?)(?=\n##\s|\z)
itemPatterns  \n-\s+(?<item>.+?)(?=\n-\s|\n###\s|\n##\s|\z)
markdownSource: true
```

跟仓库里那条同形的 CopilotForXcode recipe（也是读 repo 的 `CHANGELOG.md`）比，两处不同，
都是这份文件逼出来的：

1. **版本号带方括号**，而且方括号里要求首字符是数字 —— 这一条是用来挡掉文件顶部的
   `## [Unreleased]`。那是个有真实条目的小节，描述的是还装不了的构建。
2. **条目要跨行**。这个作者把 bullet 折在 ~78 列、续行缩进两格，所以别的 recipe 通用的
   `[^\n]+` 会把大多数条目截在半句话上（"…every CPU instruction-set" 就没了）。
   现在是懒扫描，扫到下一个 bullet、下一个 `###` 组标题、下一个 `##` 条目或结尾为止。

### 实测

- 真实文件 43,695 字节，18 个 `## [` 标题，其中 1 个是 `[Unreleased]`。
  解析出 **17 条**，正好是全部已发布版本，`[Unreleased]` 没有混进来。
- 头条 `1.7.1` / `2026-09-03`，条目是完整句子，`### Fixed` / `### Changed` 这类组标题
  没有变成条目。
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
