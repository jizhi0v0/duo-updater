# CleanMyMac 5

> 审计日期 2026-11-01 · 模式 INVESTIGATE → 已接入 · 结论：**单轨 Sparkle appcast（厂商自己的更新主机）；营销版本比较；一键 zip；changelog 可结构化**

## 基本信息
- Bundle ID: `com.macpaw.CleanMyMac5`（应用名 `CleanMyMac_5.app`，Finder 里显示 CleanMyMac）
- Team ID: `S8EX82NJP6`（Developer ID Application: MacPaw Way Ltd，已公证）
- 观测版本: 5.7.3（`CFBundleVersion` `50703.0.2610281229`），universal（x86_64 + arm64）
- 自更新机制: 包内有 `Sparkle.framework` 和 `SparkleUpdaterService.framework`，**没有 `SUFeedURL`**；
  二进制里只有 `updates.cleanmymac.com/` 这个 host，feed 地址由代码拼出来，所以
  `feed-discover` 给 `noCandidate`。
- 包内辅助件：`Contents/Library/LoginItems/CleanMyMac_5_HealthMonitor.app`、
  `…/CleanMyMac_5_Menu.app`（登录项）；二进制里出现 `privilegedHelperTools` 字样。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —（无 `SUFeedURL`，地址在代码里） | ○（cask `auto_updates`，不提供检测） | — | — | ✓ |

当前生效源: **VendorProbeSource**（`com-macpaw-CleanMyMac5.swift`）。

- Homebrew：cask `cleanmymac` 是 `auto_updates true`，`HomebrewCaskSource` 返回 nil；cask 的
  `url` 指向同一个更新主机上的 zip。
- MAS：无。GitHub：无。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.macpaw.CleanMyMac5` | — | — | — | ✓ |

只有一条轨：feed 里没有任何 `<sparkle:channel>`，条目标题就是版本号。

## 更新检测

- 源: `VendorProbeSource`
- 端点: `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml`
  —— Sparkle 2 RSS，3 个 item，从新到旧；`<sparkle:version>`、`<sparkle:shortVersionString>`
  都是 **元素**，不是属性。
- 版本方案：`sparkle:shortVersionString`（5.7.3）与 `CFBundleShortVersionString` 一致，
  `sparkle:version`（`50703.0.2610281229`）就是 `CFBundleVersion`，所以按营销版本比较，不用
  `versionIsBuild`。
- **坑：`updates.devmate.com/com.macpaw.CleanMyMac5.xml` 不能用作版本源。** 它 200、格式正确、
  `shortVersionString` 也正常，但最新一条停在 5.3.1（2026-01-28），而同一个 app 在 2026-11-01
  已经是 5.7.3（cask 与厂商主机一致）。按它做探针会把每个 5.7.x 副本报成「已是最新」。
  这正是「响应可读」不等于「版本源正确」的一例。
- 安装地址：第一条 item 的 `/releases/…zip` enclosure。同一 item 下还有 `<sparkle:deltas>`，
  它们的 URL 在 `/deltas/` 下、以 `.delta` 结尾，`releases/…zip` 这个锚不会误取。

## Changelog

- 来源: `https://macpaw.com/cleanmymac/whats-new`，服务端渲染，从新到旧。
- 结构：每个版本一个块
  ```html
  <h2 class="version">Update 5.7.2</h2>
  <span class="date"><span class="pre-date">&#8197;&#8197;/ </span>October 15, 2026</span>
  … <div class="versions-item__description"><p>…</p></div>
  … 按主题分组的 versions-item__summary，正文是 <ul><li>…</li></ul>
  ```
- 以 `h2.version` 为锚，而不是 `data-versions-item` 外层：后者的属性跨多行、块边界容易越界，
  而每个版本都有标题。正文取到下一个 `<h2 class="version">` 或 releases 区段结束。
- 两条 `itemPatterns`，按顺序：先 `<li>`（功能版），再 `<p>`（修 bug 的版本常常只有一句话，
  没有列表）。没有第二条时，这批版本会整条消失，而不是显示成一条短说明。
- 页面比 feed 慢一版：2026-11-01 时页面最高是 5.7.2，feed 已发 5.7.3。这是厂商节奏，不是
  recipe 问题；面板会在新版说明发布后自动补上。

## 一键安装

- 状态: 支持，走通用 zip 安装路径（Team 闸 + 公证检查）。
- 包: `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_50703.0.2610281229.zip`
  （222,341,604 字节），解出 `CleanMyMac_5.app`，bundle id / Team 与已装副本一致。
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 未运行：5.7.2（`50702.0.2610141002`）→ `update 5.7.3`，route `in-place`，装完
    5.7.3 / `50703.0.2610281229`、Team 不变。
  - 运行中：换包成功。旧进程继续跑旧代码（`duo install` 提示 `Still running the old code`）；
    `duo restart` 因 app 有窗口（首次启动的对话框）按设计拒绝退出；手动结束旧进程后重开，
    pid 变化、版本 5.7.3。
  - 装完再 `duo check`：`5.7.3 (latest 5.7.3)`，无幻影更新。

## 已知问题

- **登录项/辅助进程跑旧代码**：`CleanMyMac_5_Menu` 与 `CleanMyMac_5_HealthMonitor` 是包内
  独立 app，duo 的运行检测以主 bundle 的路径比对，换包后它们继续跑旧二进制，直到注销或它们
  自己重启。厂商自己的更新流程同样要重启 app，这一点与我们一致。
- **首次启动的对话框**会挡住 `duo restart`（与 Gemini 2 同）。这是设计使然：有窗口就不强退。
- 页面 changelog 落后 feed 一版（见上）。

## 如何复验

```bash
# 正确的 feed（不是 devmate）
curl -sSL https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml | head -20
# 对照：这个也能读，但版本停在 5.3.1
curl -sSL https://updates.devmate.com/com.macpaw.CleanMyMac5.xml | grep shortVersionString | head -1

# 检测 + 一键（VM 内）
duo check --all "CleanMyMac"
duo install --yes "CleanMyMac"

# 扫真实端点（probe + changelog）
duo verify --only com.macpaw.CleanMyMac5
duo verify-install --only com.macpaw.CleanMyMac5
```

## 历史与实测

### Recipes/com-macpaw-CleanMyMac5.swift — probe (stable)

转引自 recipe 注释，未复测；原始测量见上面的「更新检测」「一键安装」。

- 2026-11-01 实测：`updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml` 有 3 个 item，
  最新 5.7.3 / `50703.0.2610281229`；`updates.devmate.com/com.macpaw.CleanMyMac5.xml` 最新仍
  是 5.3.1 / `50301.0.2601271414`（2026-01-28）。cask 的 `version` 是
  `5.7.3,50703.0.2610281229`，与厂商主机一致。
- 2026-11-01 真包：5.7.3 zip 解出的 app 报 `5.7.3` / build `50703.0.2610281229`，Team
  `S8EX82NJP6`，已公证。

### Recipes/com-macpaw-CleanMyMac5.swift — changelog (stable)

- 2026-11-01 抓取 `macpaw.com/cleanmymac/whats-new`：releases 区段 31 个版本块，最新 5.7.2；
  `h2.version` 锚点每块一个；`<li>` 覆盖带列表的版本，`<p>` 兜住只有段落的版本。
