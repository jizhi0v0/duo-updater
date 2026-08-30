# WeChat (微信 · 官网版)

> 审计于 2026-06-16。官网直装版（非 MAS）。

## 基本信息
- Bundle ID: `com.tencent.xinWeChat`
- Team ID: `5A4RE8SF68`（Developer ID Application: Tencent Mobile International Limited）
- 观测版本: `4.1.10`（marketing）/ build `268851`
- 分发形态: 官网下载版无 `_MASReceipt`（MAS 版有），是区分两种分发的判据；官网版不要求装在 `/Applications`
- 自更新机制: 自研 in-app 更新器；**Info.plist 无 `SUFeedURL`、无 `KSChannelID`、无 `SUPublicEDKey`**
  （它内部用 Sparkle，但 feed URL 在运行时设置，公钥也不暴露在 bundle 里）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ○¹      | ✗²       | —³  | —      | ✓ ★         |

★ = 生效源（已实现）。单 channel（Mac 版只有 stable，无 beta/canary）。

> **已接入（2026-06-16）**: VendorProbe（**marketing 版本**）+ 一键 dmg + ChangelogRecipe（**官网 per-version 页**）。
> live smoke 实测：`updates: 1, upToDate: 58` —— WeChat 正确归到 **up to date**（装机 4.1.10 == 最新 4.1.10）。317 个 core 测试全绿。
>
> **设计修正（初版用 build 号被推翻）**: 初版用 `versionIsBuild`（比 `sparkle:version` 268853 vs 装机 268851）
> 报「4.1.10 → 268853」——但用户装的就是 4.1.10、官网最新也是 4.1.10，他本就是最新；显示裸 build
> 268853 既无意义、在用户看来也是误报。改为**只比 marketing 三段版本**（feed `4.1.10.53` 截成 `4.1.10`），
> 与官网/装机一致 → 已是最新；落后时干净显示 `4.1.x`。代价：同 marketing 内的纯 build 重发不报（用户明确不想要这种噪音）。

- ¹ Sparkle feed **公开存在**（`https://dldir1.qq.com/weixin/mac/mac-release.xml`），可经
  `ChannelBinding.feedOverride` 注入给 `SparkleAppcastSource`（即使 plist 无 SUFeedURL，
  `AppScanner` 仍会用 override 设 feedURL）。检测安全（见下），但 **无一键**：
  `SparkleInstaller` 硬要求 `SUPublicEDKey`，WeChat 没有 → 退回手动下载。
- ² Homebrew cask `wechat` 标 `auto_updates: true` → `HomebrewCaskSource` 返回 nil、fall-through。
  cask 只是 metadata，不是更新源。
- ³ MAS 上有独立的「微信」(adamID 836500024，当前 4.1.9)，但本机这份无 receipt，是官网版，
  MAS 源不会对它应答。两者 bundle id 相同但分发源不同。

当前生效源（建议）: **VendorProbe**（读同一个 Sparkle feed XML）。

## 更新检测

- **源**: `https://dldir1.qq.com/weixin/mac/mac-release.xml`（公开 Sparkle appcast，cask 的
  livecheck 也用它）
- **版本字段抉择（关键陷阱）**:

  | 来源 | 短版本 | build |
  |------|--------|-------|
  | feed `sparkle:shortVersionString` | `4.1.10.53`（4 段） | `sparkle:version` = `268853` |
  | 装机 `CFBundleShortVersionString` | `4.1.10`（3 段） | `CFBundleVersion` = `268851` |

  装机版**剥掉了第 4 段**（`.53`，Mozilla 式后缀剥离）。所以：
  - ❌ 直接拿 feed 的 4 段 `4.1.10.53` 比 → **永久幽灵**（装机永远不报第 4 段）。
  - ❌ 按 **build**（`268853` vs `268851`）比 → 技术上能归零，但对用户是误报（同 marketing 版本、显示无意义裸号）。**初版踩了这个，已推翻。**
  - ✅ **截成 3 段 marketing**（`4.1.10.53` → `4.1.10`）跟装机 `4.1.10` 比 → 已是最新；落后才报、显示 `4.1.x`。

  实现：`versionPattern = sparkle:shortVersionString[>="]+\s*(\d+\.\d+\.\d+)`（元素/属性两种形态都匹配），
  `selectHighest`，**不**设 `versionIsBuild`。

- **官网 dmg == feed enclosure（已字节级证实）**: `WeChatMac_4.1.10.dmg`（官网无版本名）与
  `xWeChatMac_universal_4.1.10.53_39917.dmg`（feed enclosure）`Content-Length` **逐字节相同**
  （496,955,386）→ 同一个文件 = build 268853。所以官网与 feed 的 build 锁步，build 比较不会留幽灵。
  装机 268851 是真的比现行 268853 旧 2 个 build（用户装的是稍早的 4.1.10 构建）。

- **feed item 选取**: feed 含多个按 `min/maxSystemVersion` 分档的 item（都是同版本 268853），
  外加一条老的 `3.8.10.17`。最新 macOS（本机 Darwin 27）匹配 min 12.0 / 无 max 的 item 1，
  它带 enclosure dmg。注意 item 3（min 14.3）notes 写「需前往官网下载」且**无 enclosure**——
  `selectHighest`/首匹配会落在带 dmg 的 item 1，安全。

## Changelog

- **生效源：官网 per-version 页** `https://weixin.qq.com/updates?platform=mac&version=<X.Y.Z>`。
  虽是 Nuxt SPA，但每个版本一页、notes 服务端内联：`faq_title`「微信 <ver> for Mac …」+
  `发布日期：<date>` + `#page_center` 里的 `<h4>- …</h4>` 改动行。用 **sourceTemplate `{version}`**
  （Thunderbird 同款）按目标 marketing 版本取页 → 标签/日期与官网完全一致（4.1.10、4.1.9…）。
  itemPattern 去掉行首 `- ` 避免与 UI bullet 叠成「• -」。body 锚定 `#page_center`，页脚 `<h4>` 不会混入。
  **配图（按文档顺序交错）**：notes 里夹着的 feature 截图（`res.wxqcloud.qq.com.cn`/`res.wx.qq.com`）
  通过新增的 `ChangelogRecipe.imagePattern` 抽出，连同文字行按**原始位置**合并进 `Changelog.Entry.content`
  （`.note`/`.image` 有序块）→ 详情卡片用 `AsyncImage` 内联渲染，图落在两行文字中间、与官网一致。
  纯文本条目 `content` 为空、仍走 `items` bullet（其余所有 app 渲染不变）。跨 app 小功能。
- **为何不用 Sparkle feed 当 changelog**：feed 只有稀疏 5 条、用 4 段标签（4.1.10.53）、跳过 4.1.9/4.1.8，
  与官网历史对不上 —— 初版用过，已弃。
- 兜底：解析失败回落 changelogURL webview（`weixin.qq.com/updates?platform=mac`）。

## 一键安装

- **可行**（推荐走 VendorProbe + `VendorInstaller`）。dmg，Developer ID Tencent `5A4RE8SF68`，
  与装机同 Team → `VendorInstaller` 的 Team-ID 签名门通过。官网/feed 同 channel，无跨轨。
- 安装 URL：从 feed body 抠 enclosure（`enclosure url="(…\.dmg…)"` 首匹配 = 最新 item），
  带 `?t=<token>`（每次探测从新鲜 feed 读，token 有效）。496MB。
- Sparkle 源**给不了**一键（无 `SUPublicEDKey`，`SparkleInstaller` 拒绝）。这是选 VendorProbe 的主因。

## 已知问题 / 取舍

- **只比 marketing 版本** → 同 marketing 内的纯 build 重发（268851→268853）不报。这是刻意取舍：
  用户按 marketing 版本认知 WeChat，build 噪音会被当误报。落后一个真版本（4.1.9→4.1.10）正常报。
- WeChat 自带更新器在新版 macOS 上有时会让用户「前往官网手动下载」（见 feed item 3 notes）——
  我们的一键正好补这个缺口。
- 备选路径（未采用）：给 `ChannelBinding` 加 `feedOverride: mac-release.xml` 走 Sparkle 源可白拿
  三语 inline notes，但无一键（无 `SUPublicEDKey`）、且 changelog 标签是 4 段，不如官网页干净。

## 实现落点（已完成 2026-06-16）

1. **检测 + 一键** — `VendorProbeRecipe.swift`，`com.tencent.xinWeChat`：
   - `url: https://dldir1.qq.com/weixin/mac/mac-release.xml`，`mode: .responseBody`
   - `versionPattern: sparkle:shortVersionString[>="]+\s*(\d+\.\d+\.\d+)`（截 3 段 marketing），`selectHighest`，**不**设 `versionIsBuild`
   - `install: .bodyPattern(<enclosure url="(https://[^"]+\.dmg[^"]*)")`, `kind: .dmg`
   - `changelogURL: https://weixin.qq.com/updates?platform=mac`（webview 兜底）
2. **结构化 changelog** — `ChangelogRecipe.swift`，sourceTemplate `…&version={version}`，
   entry 锚 `微信 <ver> for Mac` + `发布日期` + `#page_center` 的 `<h4>` 行（去 `- ` 前缀）。
3. **测试** — `VendorProbeTests`（marketing 抽取 + 端到端不幽灵 + dmg 抠取）、
   `ChangelogExtractorTests`（sourceTemplate 解析 + per-version 页抽取）。本机 `com.tencent.xinWeChat`
   已装 = 真 bundle，单 channel 无需 channel-verify。317 测试全绿，live smoke = up to date。
