# GitHub Copilot for Xcode

## 基本信息
- Bundle ID: `com.github.CopilotForXcode`
- Team ID: `VEKTX9H2N7` (GitHub)
- 观测版本: `0.51.0`（short == build）
- 自更新机制: **Sparkle**（`SUFeedURL = https://githubcopilotide.z13.web.core.windows.net/appcast.xml`）
- 分发: Azure 静态站点（`githubcopilotide.z13.web.core.windows.net`，域名已固定为该 IP 直连
  形式）+ Homebrew cask `github-copilot-for-xcode`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable**     | ✓   | — (`auto_updates`) | — | — | — |
| **prerelease** | ✓   | —        | —   | —     | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe；两轨都靠 feed 里的 `<sparkle:channel>` 标记分轨）。

## Channel 详情

| Channel     | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|-------------|-----------|----------|---------|---------|------|
| stable      | `com.github.CopilotForXcode` | 共享 | — | default（无标记） | ✓ |
| prerelease  | `com.github.CopilotForXcode` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>prerelease</sparkle:channel>` | ✓ |

共享 bundle id。appcast 12 条（观测 2026-08-30）：default 轨道是正式版
（`0.51.0`），`prerelease` 轨道是 `0.51.182` 这类高频 build。两轨互不串：
`usableItems` 允许「装机 build 命中的那条 channel + 始终开放的 default 轨」。

**两侧都用真包跑过生产源链（2026-08-31）**，不是推断：

- stable 0.51.0 → `releaseHistory` **6** 条（只有 default 那 6 条），头是 0.51.0，
  up to date —— 没有被推 prerelease 的 0.51.182。
- prerelease 0.51.182 → `releaseHistory` **12** 条（default ∪ prerelease），头是
  0.51.182，up to date —— 留在自己那条轨上。

这个 feed 不会踩 Supacode / TypeWhisper 那个「short 撞车导致渠道推断失手」的坑：
两轨的 short 串本来就分得开（default 是 `0.51.0`/`0.50.0`，prerelease 是 `0.51.18x`），
不存在一个 default 条目跟 prerelease 包共用同一个 short。

一个值得写下的现象：prerelease 的 `shortVersionString` 是 `0.51.182`——把 build
编码进了 short。default 轨的 `0.51.0` 与它同域可比（`0.51.182 > 0.51.0`），但
channel 门先于比较，所以不构成跨轨推送。

## 更新检测
- 源: 泛化 Sparkle。`comparisonKey = version ?? shortVersionString`，两条轨都短串
  当道，同构无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: **`ChangelogRecipe`**，解 repo 里的 Keep-a-Changelog 文件
  `raw.githubusercontent.com/github/CopilotForXcode/main/CHANGELOG.md`
- 跟随 channel: 否（一份文件涵盖两轨；prerelease 的 0.51.18x 不单独立条目）
- Recipe 状态: 2026-08-31 新增
- ⚠️ 2026-08-31 更正：原先写「Sparkle inline（feed `<description>`）」，是错的。
  feed 12 条**一条都没有** `<description>`；GitHub release 正文也只有一句话
  （0.51.0 的正文全文是 "Release 0.51.0 of Copilot extension for Xcode"，45 字符）。
  真包跑生产链 0 字符、`changelogURL` nil —— 加 recipe 之前完全没有说明。
- 写 `\n##` 而不是 `^##`：`ChangelogExtractor` 编译正则时给的是
  `.dotMatchesLineSeparators`，**没有** `.anchorsMatchLines`，`^` 只匹配整份文档开头。
- `markdownSource: true`：条目里有行内代码（`/v1/messages`）和 `[text](url)`，
  不开这个开关会把反引号和方括号原样端到用户面前。实测解出 21 条，head 0.51.0。

## 一键安装
- 状态: **支持**（Sparkle 原生路径，两轨各自 feed enclosure）
- 格式: `GitHubCopilotForXcode.dmg`（universal，真包核实）
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，0.51.0 挂载）: `com.github.CopilotForXcode` / `0.51.0`，
  `Developer ID Application: GitHub (VEKTX9H2N7)`，`spctl accepted / Notarized
  Developer ID`，universal（x86_64+arm64）
- 包验（2026-08-31，**prerelease 0.51.182 挂载**，453 MB）: 同 bundle id，short ==
  build == `0.51.182`，同 Team，`spctl accepted / Notarized Developer ID`

## 已知问题
- 用户如何在 app 内切入 prerelease 轨道（设置开关的位置）未查；对 duo-updater
  无影响——装机 build 命中哪条轨道就跟随哪条，与 Sparkle 自身语义一致。

## 如何复验
```
# GET https://githubcopilotide.z13.web.core.windows.net/appcast.xml
#   → 12 条，default=0.51.0，prerelease=0.51.182
# 挂载 GitHubCopilotForXcode.dmg → com.github.CopilotForXcode / 0.51.0
# channel-verify --check com.github.CopilotForXcode → winning=Sparkle, up to date
```

## 建议下一步
无。两轨检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
