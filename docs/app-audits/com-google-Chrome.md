# Google Chrome

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta/dev/canary 四 channel 全覆盖检测，工作正常**

## 基本信息
- Bundle ID: `com.google.Chrome`（beta/dev/canary 各自独立：`com.google.Chrome.beta` / `.dev` / `.canary`）
- 观测版本: `149.0.7827.54`（stable 轨）
- `CFBundleShortVersionString` = `149.0.7827.54`（完整 4 段）/ `CFBundleVersion` = `7827.54`（截断）
- `KSChannelID` = `universal`（stable 装机即此值，**非** 空/`stable`）
- 自更新机制: **Keystone**（Google 自家更新器，后台静默升级）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **beta**     | —       | ✗(auto)  | —   | —      | ✓           |
| **dev**      | —       | ✗(auto)  | —   | —      | ✓           |
| **canary**   | —       | ✗(auto)  | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**
- Sparkle: 无 `SUFeedURL`，Chrome 不用 Sparkle。
- Homebrew: cask `google-chrome`（及 `@beta`/`@dev`/`@canary`）均 `auto_updates: true` → `HomebrewCaskSource` 返回 nil，落到 VendorProbe。
- MAS: Chrome 不上架 App Store。

## Channel 详情（Pattern A — 独立安装，各自 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.google.Chrome`        | 独立 | —（默认）；KSChannelID `universal` 走 fall-through→stable | 独立端点 | ✓ |
| beta    | `com.google.Chrome.beta`   | 独立 | bundle id `.beta` 后缀 / KSChannelID `beta` | 独立端点 | ✓ |
| dev     | `com.google.Chrome.dev`    | 独立 | bundle id `.dev` 后缀 / KSChannelID `dev` | 独立端点 | ✓ |
| canary  | `com.google.Chrome.canary` | 独立 | bundle id `.canary` 后缀 / KSChannelID `canary` | 独立端点 | ✓ |

每个 channel 是独立 bundle id + 独立 `ReleaseChannel`，channel gate 把每个安装路由到匹配的端点——beta 装机永远不会拿到 stable 版本，反之亦然。`KSChannelID` 是最强信号（`ReleaseChannel.detect` 第 1 优先级）：stable 实测值为 `universal`，不在 beta/dev/canary/stable/extended 白名单内，default 分支 fall-through，最终靠"无后缀 + 名称无 channel 词 + 版本号是稳定形态"判定为 stable——逻辑正确，无误判。

## 更新检测
- 源: VendorProbe（`mode: .responseBody`）
- 端点: Chrome 官方 VersionHistory API，每 channel 一个：
  `https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/{stable|beta|dev|canary}/versions/all/releases?filter=endtime%3Dnone&order_by=version%20desc`
- versionPattern: `"fraction"\s*:\s*1(?:\.0+)?\s*,\s*"version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"`
- **rollout 防幽灵更新（关键设计）**: 用 `releases`（带 `fraction` 0–1 灰度比例）而非裸 `versions` 端点。裸端点会返回"仅存在"的最新 build（哪怕 0.5% 灰度），导致领先 Keystone 报幽灵更新（Chrome 自己还说"已是最新"）。pattern 锁 `fraction:1`（完全铺开 = Keystone 给所有人的版本），取其中最高版本。Canary 每个 build 都 fraction=1。
- **版本方案校验（Phase 3½）**: ✅ 端点返回完整 4 段（`149.0.7827.54`）= `CFBundleShortVersionString`，**不是** `CFBundleVersion`（`7827.54`）。无需 `versionIsBuild`，无幽灵更新风险。
- **实测**（2026-06-04）: stable 端点 fraction=1 最高版 = `149.0.7827.54`，与本机安装版**完全一致** → 检测口径正确。

## 一键安装
- 状态: **已接入**，四 channel 均为 `.fixed` dmg（`dl.google.com/chrome/mac/universal/<channel>/`，
  Team `EQHXZ8M8AV`）。此前本节记为「仅检测（设计如此）」，是旧策略的残留。
  「绝不碰自更新器」那条绝对规则已由用户设置 `vendorInstallPolicy` 取代：默认 `.deferWhenRunning` —— app 正在运行就交回它自己的更新器，没在运行才就地替换；选 `.alwaysOverwrite` 才总是由我们装。见 `UpdatePolicy.defersToSelfUpdater`。
- Keystone 不构成拒绝一键的理由：它管的是磁盘上那个 bundle，换成更新的构建不会让它困惑。
- **不会跑到 Keystone 前面**：版本只取 `fraction=1`（完全放量）的构建。裸 `versions` 端点
  会返回仅 0.5% 放量的版本，那会显示一个 Chrome 自己都说「已是最新」的幽灵更新。
- `downloadURL` = `chrome://settings/help`（app-scheme URL，UI 交给 Chrome 本体而非浏览器）：访问该页会让 Chrome 立即触发一次 Keystone 检查 + 下载，即它本channel 的真实更新路径。

## Changelog
- 来源: ChangelogRecipe（`com.google.Chrome`，**仅 stable**）
- 源页: `https://chromereleases.googleblog.com/search/label/Stable%20updates`（Chrome Releases blog / Blogger，server-rendered，正文内联在 `<script type='text/template'>`）
- entryPattern 用标题字面量 `Stable Channel Update for Desktop` 同时选中桌面 stable 帖、排除 Beta/Dev/Early/Extended（标题不同）。
- itemPatterns 两形态按序：① 安全帖的 `CVE-YYYY-N:` 内联 span；② 推广帖的 `promotion of Chrome…/been updated to…` 整段 `<p>`（tempered dot 防越界）。
- 跟随 channel: **否**——只覆盖 stable。beta/dev/canary 的 `changelogURL` 指向 `https://developer.chrome.com/release-notes`（按 channel 无独立 recipe，UI 内嵌网页）。
- Recipe 状态: stable 已有；beta/dev/canary 无 recipe，也写不出来，登记在 `ChangelogCoverage.acknowledged`（#1149，理由转引，本次未复测）：`developer.chrome.com/release-notes` 是个 stub；Chrome Releases blog 的 beta/dev 帖只有一行版本说明；Canary 没有发布过 notes（blog 的对应 label 是空的）。所以这三个渠道一直是 inline 网页兜底。

## 已知问题
- 无功能性问题。stable 检测端到端实测通过。

## 建议下一步
1. **无需改代码** — 四 channel 检测均已接入且实测正确，写/更新本审计文档即可。
2. beta/dev/canary 的 changelog recipe 不做：#1149 已查过 Chrome Releases blog 的 beta/dev 帖（只有一行版本说明）和 Canary（无 notes），理由见上面 Changelog 一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-Chrome.swift — stable / beta / dev / canary VendorProbe（per-channel dmg 一键）

转引自 recipe 注释，未复测。

All four channels install from Google's own permanent per-channel dmg
(`dl.google.com/chrome/mac/universal/<channel>/…`), verified 2026-08-09:
each holds the matching bundle id, Team EQHXZ8M8AV, spctl "Notarized
Developer ID", and a version in the same 4-part form the API reports.

### Recipes/com-google-Chrome.swift — ChangelogRecipe（Chrome Releases 博客 *Stable updates* 标签页）

转引自 recipe 注释，未复测。最后一段原句没写日期；日期取自引入这句话的提交：`da0845c5`（2026-09-02）。那段第一句的边界在代码里改成了引用 `ChromeChangelogPatternTests` 实际断言的值（100 000 匹配、300 000 不匹配）。

Measured against the live 852 KB page (6 posts) with the old form:
renaming the closing `</script>` ran past 150 s, and a page whose
4-part build numbers went away took 20.6 s, both on a thread the
caller is awaiting.

Same seven mutations, new form: worst case 0.074 s, and the pristine
page still yields the identical two entries.

A possessive/atomic run silently stops matching past ~250 000
characters — measured: 100 000 matches, 250 000 does not, and the
failure is a quiet "no match", not an error. Chrome's second post is
a 324 KB body, so that form drops it and the pane loses an entry with
nothing anywhere saying so.

复测 2026-09-14（03:13 UTC，只读 GET）：标签页 569,736 字节，只含 1 个 `title='Stable Channel Update for Desktop'`、3 个 `<script type='text/template'>`，最长的正文 216,368 字符。代码里 "second post is a 324 KB body" 那句已改写成不依赖具体帖子的说法。

### `duo verify` 的「entry count COLLAPSED」误报（#821）

标签页只有 1 个桌面帖是这个页面的正常状态（上面 09-14 那次就是），但夜扫的塌缩检查当时只看条数：从 >1 掉到 1 就报警，且不记录这个 1，于是之后每轮都拿旧的 3 比、反复报。

复测 2026-10-09（只读 GET，生产 `ChangelogExtractor` + 注册的 recipe，临时 Swift 测试）：622,955 字节的页面里只有 1 个桌面帖（另一个是 Chrome for Android），解析出 1 条 `155.0.8059.39`（Tuesday, October 6, 2026），正文停在它自己的 `</script>`，后面还有约 336k 字符没被吞。正文占了页面四成左右，所以「正文占页面比例」当不了判据。

修法（同一 PR）：只剩 1 条时，sweep 再问一次页面——这条的正文里是否还有另一条 entry 的开头（`ChangelogExtractor.anEntrySwallowsAnother`，记在 `Finding.entrySwallowsAnother`）。明确「没有」才不报；真塌缩（终止符失配、后面各条都被吞进第一条）照报。这个 1 仍不写进 baseline。
