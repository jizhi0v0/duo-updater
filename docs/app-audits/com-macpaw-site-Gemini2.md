# Gemini 2

> 审计日期 2026-11-01 · 模式 INVESTIGATE → 已接入 · 结论：**单轨 DevMate appcast；版本按 build 比较（feed 最新一条的 marketing 字段写错了）；一键 zip**

MacPaw 的 Gemini 2（重复文件查找 / 磁盘整理），不是 Google 的 `Gemini.app`
（`com.google.GeminiMacOS`，两者同机共存、互不相干）。

## 基本信息
- Bundle ID: `com.macpaw.site.Gemini2`
- Team ID: `S8EX82NJP6`（Developer ID Application: MacPaw Way Ltd，已公证）
- 观测版本: 2.10.2（`CFBundleVersion` 407），universal（x86_64 + arm64）
- 自更新机制: 包内 `DevMateKit.framework`；**没有 `SUFeedURL`**——地址由 DevMate 在运行时按
  bundle id 填进 `https://updates.devmate.com/<bundle-id>.xml`，静态读不到，所以
  `feed-discover` 给出 `templatedAddress`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —（无 `SUFeedURL`） | ○（cask `auto_updates`，不提供检测） | — | — | ✓ |

当前生效源: **VendorProbeSource**（`com-macpaw-site-Gemini2.swift`）。

- Homebrew：cask `gemini` 是 `auto_updates true`，`HomebrewCaskSource` 对它返回 nil，直装副本
  只能靠 recipe。cask 只在首次安装时有用。
- MAS：无。
- GitHub：无。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.macpaw.site.Gemini2` | — | — | — | ✓ |

只有一条轨：feed 里没有任何 `<sparkle:channel>`；二进制里没有 beta/canary 相关字符串。

## 更新检测

- 源: `VendorProbeSource`
- 端点: `https://updates.devmate.com/com.macpaw.site.Gemini2.xml`（DevMate 的 Sparkle appcast，
  RSS 2.0，条目从新到旧）
- 版本字段：**`sparkle:version`（build）**，不是 `sparkle:shortVersionString`。
  - 旧条目两者都在：`sparkle:version="406"` + `sparkle:shortVersionString="2.10.1"`，与包内
    `CFBundleVersion` / `CFBundleShortVersionString` 一一对应。
  - 最新一条（407）把 build 写进了 marketing 字段：
    `sparkle:version="407" sparkle:shortVersionString="407"`，而那个包自己的
    `CFBundleShortVersionString` 是 **2.10.2**。照 The Unarchiver 的写法读 marketing 字段，
    会对着任何一个 2.10.2 副本永久报「有更新到 407」。所以这条 recipe 用
    `versionIsBuild: true`，比较 `CFBundleVersion`（406 → 407）；行里两侧因此都用 build 命名，
    显示为 `406 → 407`，装完是 `407`，不再有幻影更新。
  - release notes 页也印证：407 那一页的标题是「Gemini 2 407」，正文里没有 2.10.2 这个串。
- 注意:
  - 版本号只能取**第一条** `<enclosure>` 上的 `sparkle:version`。同一 item 里紧跟着的
    `<sparkle:deltas>` 也带 `sparkle:version`，`<enclosure ... .zip` 这个锚同时保证了安装
    地址不会落到 `.delta` 上。
  - feed 的 `sparkle:minimumSystemVersion`（旧条目是 10.13）没有对应 recipe 字段，未使用。

## Changelog

- 来源: DevMate 的 per-build 说明页，`https://updates.devmate.com/releasenotes/<build>/com.macpaw.site.Gemini2.html`
- 页面结构：`<hr />` 分隔每个版本，从新到旧；`<p>2.10.1</p>` 起头，其后是 `Bug Fixes` 之类的
  小标题与 `<ul><li>…`。**最新一节没有版本段落**——只有页头 `<span>407</span>`（build）。
- 没有 `ChangelogRecipe`，登记在 `ChangelogCoverage.acknowledged`：同一页里最新版只有 build、
  旧版只有 marketing 字符串，一条 recipe 无法给「探针报的那一版」命名，固定 URL 又会把说明钉在
  写 recipe 时的那个 build 上。recipe 的 `changelogURL` 仍指向该页，面板里嵌网页照常可读。

## 一键安装

- 状态: 支持，走通用 zip 安装路径（Team 闸 + 公证检查）。
- 包: 最新 item 的 `enclosure`，`https://dl.devmate.com/com.macpaw.site.Gemini2/407/<ts>/Gemini2-407.zip`
  （51,483,368 字节），解出 `Gemini 2.app`，bundle id / Team 与已装副本一致。
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 未运行：2.10.1（406）→ `update 407`，route `in-place`，装完 2.10.2（407）、Team 不变。
  - 运行中：换包成功，旧进程继续跑旧代码（`duo install` 提示 `Still running the old code`）；
    `duo restart` 因 app 有窗口（它自己弹出的提示）按设计拒绝退出，手动退出后重开，pid 换新、
    版本 2.10.2。
  - 装完再 `duo check`：`407 (latest 407)`，`0 updates`，无幻影更新。

## 已知问题

- **行里显示的是 build**（`406 → 407`），不是 2.10.x。这是 feed 把 build 写进 marketing 字段的
  直接后果：只有 build 两边的顺序是可比的，显示也就跟着用 build。厂商把 407 的
  `sparkle:shortVersionString` 改回 `2.10.2` 之后，这条 recipe 可以改回比 marketing（像
  The Unarchiver），显示也随之恢复。
- `changelogURL` 钉在 407，比最新版落后一版（cosmetic，与 The Unarchiver 同）。

## 如何复验

```bash
# 端点与两条 pattern
curl -sSL https://updates.devmate.com/com.macpaw.site.Gemini2.xml | head -30

# 检测 + 一键（VM 内）
duo check --all "Gemini 2"
duo install --yes "Gemini 2"

# 扫真实的 recipe 端点
duo verify --only com.macpaw.site.Gemini2
```

## 历史与实测

### Recipes/com-macpaw-site-Gemini2.swift — probe (stable)

转引自 recipe 注释，未复测；原始测量见上面的「更新检测」「一键安装」。

- 2026-11-01 实测 feed 与包：最新 item 407 的 `sparkle:version` 与 `sparkle:shortVersionString`
  都是 `407`；该 zip 解出的 app 报 `2.10.2` / build `407`，Team `S8EX82NJP6`，已公证。
  上一版 item 406 报 `2.10.1`。
- 2026-11-01 在 vmpal VM 跑通 2.10.1 → 2.10.2 的一键（未运行 / 运行中两轮）。
