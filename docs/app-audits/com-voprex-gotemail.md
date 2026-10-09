# GotEmail

## 基本信息
- Bundle ID: `com.voprex.gotemail`
- Team ID: `RQBC2CSG5T`
- 观测版本: 0.1.3（`CFBundleVersion` 4），2026-10-09
- 自更新机制: Sparkle 2.10.0（`SUFeedURL` = `https://gotemail.shipcat.app/appcast.xml`，`SUPublicEDKey` 已声明）
- 官网: https://gotemail.shipcat.app/ · What's New: https://gotemail.shipcat.app/whatsnew/
- 不开源；站点页脚标 "Built with ShipCat"

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（bundle 自带 `SUFeedURL`，无需 recipe）。

Homebrew（`brew search --cask gotemail` 无结果）、MAS（`mas search GotEmail` 无此 app）均未上架，2026-10-09。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.voprex.gotemail` | — | — | — | ✓ |

只有一条轨：appcast 的 item 不带 `<sparkle:channel>`；`releases.json` 无 prerelease 标记；主二进制 `strings` 里没有 beta / prerelease / `allowedChannels` 一类字样（出现的 "channel" 全是 SwiftNIO 的网络 Channel）。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover` 结论 `declared`）
- 端点: `https://gotemail.shipcat.app/appcast.xml`
- 注意事项:
  - feed 是**原地重写的单条文件**：只有最新一个 `<item>`，enclosure 指向不带版本号的 `/download/GotEmail.dmg`（2026-10-09 试过 `GotEmail-0.1.2.dmg`、`0.1.2/GotEmail.dmg` 等写法全是 404）。所以 release history 永远只有 1 条，上一版的安装包拿不到。
  - item 声明 `<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>`，与包内 `LSMinimumSystemVersion` 15.0 一致；没有上限。架构 `x86_64 arm64`。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2.10.0 自带） | 无 | 能（现成 `VendorAppcastDeltas` / `DeltaApplier`），但没有可消费的 |
| 证据 | 包内 `Sparkle.framework` | 2026-10-09 appcast 无 `<sparkle:deltas>`；`channel-verify` 报 `deltas 0` | — |

## Changelog
- 来源: recipe（`Recipes/com-voprex-gotemail.swift`，`structuredFormat: .gotEmailReleases`）读 `https://gotemail.shipcat.app/releases.json`
- 为什么不用 appcast 的 inline notes: feed 只有一条 item，版本轨只能显示一个版本；且 `<description>` 以 `<h2>GotEmail 0.1.3</h2>` 开头，pane 把它当成了一条改动（加 recipe 前 `channel-verify`：`source structured: 1 entries; newest 0.1.3: 4 items, headings []; first items ["GotEmail 0.1.3", …]`）
- `releases.json` 就是 What's New 页面渲染的文件（`/whatsnew/` 的 HTML 是空壳，`<div id="releases" data-releases="/releases.json">` 由 `/assets/site.js` 填充）。形状 `{releases: [{version, date, items: [{tag, text}]}]}`，newest-first。decoder 照 `site.js` 的 `releasesHTML` 读：非对象跳过，tag 只认 `new` / `changed` / `fixed`（不分大小写），其余一律算 Changed；每行保留 `New:` / `Changed:` / `Fixed:` 前缀、按文档顺序，和页面以及 appcast inline（`<b>Changed:</b> …`）一致，不重排成分组标题。
- 结构化（`channel-verify`，2026-10-09，加 recipe 后）: `recipe changelog:com.voprex.gotemail:-: 4 entries; newest 0.1.3: 3 items, headings []; first items ["Changed: When a provider refuses the pas", "New: AOL is a preset: pick it and the se", "Changed: Outlook.com, Hotmail, Live and "]`
- 跟随 channel: 不适用（单轨）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（通用 Sparkle 路径），端到端未跑
- 端到端: **未跑**。厂商只发布最新一版、地址不带版本号，拿不到 0.1.2 的包来装旧版。下一版（0.1.4）发布后，把现在这份 0.1.3 留作旧版即可跑。
- 格式: dmg（内含 `GotEmail.app` 与 `Applications` 软链）
- 校验（2026-10-09，真实下载 12452294 字节，与 enclosure `length` 一致）:
  - enclosure 的 `sparkle:edSignature` 用包内 `SUPublicEDKey` 验证通过；翻转文件中间一个字节后验证失败
  - `codesign --verify` 通过，`spctl`：Notarized Developer ID，Team `RQBC2CSG5T`
  - 无嵌套 app：没有 `Contents/Library/LoginItems`、`Contents/Helpers`
- **读的是**: 人人可手动下载的 GA —— appcast 的 enclosure 与官网 Download 按钮是同一个 `/download/GotEmail.dmg`，feed 无灰度字段
- 阻塞: 无

## 已知问题
- 无

## 如何复验

```bash
curl -sS https://gotemail.shipcat.app/appcast.xml
curl -sS https://gotemail.shipcat.app/releases.json
curl -sSL -o GotEmail.dmg https://gotemail.shipcat.app/download/GotEmail.dmg
swift run --package-path application-test feed-discover GotEmail.dmg     # → declared
swift run --package-path application-test channel-verify GotEmail.dmg    # → stable, winning source Sparkle, changelog pane = recipe
swift test --package-path DuoUpdaterCore --filter GotEmailRecipeTests
```

2026-10-09 结果：`feed-discover` → `GotEmail [com.voprex.gotemail] 0.1.3 (4) declared https://gotemail.shipcat.app/appcast.xml`；`channel-verify` → detected channel stable、winning source Sparkle、latest 0.1.3、status up to date、changelog pane 见上。

## 建议下一步
1. 0.1.4 发布后跑一键端到端（0.1.3 → 0.1.4，未运行与运行中两轮）。
