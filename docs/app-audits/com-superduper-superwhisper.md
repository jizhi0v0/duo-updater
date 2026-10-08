# Superwhisper

审计 2026-10-08（重审；2026-08-17 那版只核对了 bundle 身份（Team、版本、`SUFeedURL`），没在新旧两个包上跑生产检测，
没查渠道和 changelog 结构，也没跑一键）。

## 基本信息
- Bundle ID: `com.superduper.superwhisper`
- Team ID: `XDP69BYUP9` — Developer ID Application: SuperUltra, Inc.（2.19.1 与 2.19.2 两个真包相同，均 `Notarized Developer ID`）
- 观测版本: `2.19.2`（`CFBundleVersion` 也是 `2.19.2`）、上一版 `2.19.1`。universal（`x86_64 arm64`），`LSMinimumSystemVersion` 14.0
- 自更新机制: Sparkle，`SUEnableAutomaticChecks` = true，`SUScheduledCheckInterval` = 86400（设置页文案写的是
  「every three hours」）。**两个相邻版本带的 Sparkle 不同**：2.19.1 是 2.6.4（2039.1），2.19.2 是 2.9.6（2061）；
  2.19.2 的说明只有一条「Fixed an issue where app updates could get stuck during installation」
- Homebrew: cask `superwhisper`，`auto_updates: true`，URL 与 feed 的 enclosure 相同
- 不开源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让位） | — | — | — |
| **beta**（`includeBetaUpdates`，推断） | 没查到（feed 无带标签条目，开关存在与否未证实） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`SparkleAppcastSource`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.superduper.superwhisper` | — | — | 单一 Sparkle feed | ✓ |
| beta | 同上 | 共享 | 偏好 `includeBetaUpdates`（**推断**） | 未知（Sparkle 标签 or 换 feed） | 未验证 |

**查到了什么（实测）和没查到什么：**

- 主程序字符串里有 `includeBetaUpdates`，紧挨着 `status.menu.checkForUpdates`、`Check for Updates...`、
  `sparkle_error_code`，也就是在更新相关代码附近。看起来像 UserDefaults 键名（**推断**；存在哪里、什么类型都没验证）。
- 设置页的文案里只找到「Automatically check for updates」和它的说明，**没有** beta 开关的文案；资源里的
  `.strings`/`.plist`/`.json` 也没有。可能是没有 UI 的隐藏偏好（和 MonitorControl 的 `isBetaChannel` 同形），**推断**。
- `allowedChannelsForUpdater:`、`feedURLStringForUpdater:` 在二进制里，但和 `feedParametersForUpdater:sendingSystemProfile:`、
  `updaterDidNotFindUpdate:` 等一起出现，是 `SPUUpdaterDelegate` 整份协议的方法名表，**不能**据此说实现了。
- 二进制里没有第二个 appcast 地址（`appcast`、`builds.superwhisper.com` 都不在字符串里）。顺手试了 4 个常见写法
  （`builds.superwhisper.com/appcast-beta.xml`、`/beta/appcast.xml`、`/beta-appcast.xml`、`superwhisper.com/appcast-beta.xml`），
  全是 404。这只说明这几个猜测不对，不说明没有 beta feed。
- feed 233 条，`<sparkle:channel>` 0 条。只看了今天这一份，没有历史可翻。
- 官网 changelog 里出现的「beta」是功能标注（「Super mode beta release」「Dictation history view (Beta)」），不是渠道。

结论：**有一个指向 beta 更新的偏好键名，但它怎么起作用、存在哪里、服务端发不发，都没证实**。要确认需要在真 app 里
找到并拨这个开关（或 `defaults write` 后观察 Sparkle 请求的地址/接受的标签）。这是 agent 类 app，按规定本次不启动。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared  https://superwhisper.com/appcast.xml`）
- 端点: `https://superwhisper.com/appcast.xml` → 307（Vercel）→ `https://builds.superwhisper.com/appcast.xml`（Cloudflare，
  带 `etag` / `last-modified`）。2026-10-08 连取三次、以及换成 Sparkle 风格的 UA，SHA-256 都相同，不按请求变化
- feed 形状（2026-10-08）: 233 条（2.19.2 一直到 1.6.0），`<sparkle:channel>` 0 条；每条只有 `version`、
  `shortVersionString`、`minimumSystemVersion`（最新为 14.0）；217 条有 `<description>`（HTML）；没有 `releaseNotesLink`、
  `maximumSystemVersion`、`hardwareRequirements`、`phasedRolloutInterval`、`criticalUpdate`、deltas
- 版本方案: `sparkle:version` = `shortVersionString` = `CFBundleShortVersionString` = `CFBundleVersion`（`2.19.2`）
- 发布日期: `Mon, 05 Oct 2026 01:25:53 GMT`，生产解析能读（`release history 233 entries`）

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不适用 |
| 证据 | 两个包的 `Sparkle.framework/Versions/B/Autoupdate` 都含 `BinaryDelta` 等串 | 2026-10-08 feed 233 条都没有 `<sparkle:deltas>` | `channel-verify`：`deltas 0` |

- 格式: —
- 阻塞项: 无（zip 约 65 MB）

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval` | 否 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 否：universal 单包；只有下限（14.0） | `SparkleAppcastSource` 读下限 |
| 自更新器会不会和我们抢 | 会：自动检查。2.19.1 带 Sparkle 2.6.4，2.19.2 换成 2.9.6 并说修了「更新卡在安装」；两者是否同一件事是**推断** | 是：同一个 feed | 端到端第二轮未跑 |

## Changelog
- 来源: Sparkle inline（`<description>`，HTML）
- 结构化: `changelog pane  source structured: 40 entries; newest 2.19.2: 2 items, headings []; first items ["Fixes", "Fixed an issue where app updates could g"]`
  （2.19.1、2.19.2 两个包相同；40 是解析器的条数上限）
- 判断: **分节被压平了**。厂商的写法是 `<b>Fixes</b>`、`<b>Features & Improvements</b>`、`<b>Improvements</b>` 这样的粗体
  小标题，后面各接一个 `<ul>`。`AppcastHTMLChangelogParser` 只认 `<h2>`–`<h4>` 作标题，粗体落在列表外的空隙里，被当成
  一段普通文字收进 `items`，所以面板里「Fixes」是一个条目、`headings []`。条目本身完整。
  **写 ChangelogRecipe 收益不大**：feed 已经内联了说明；官网 `superwhisper.com/changelog` 是 Next.js 页面，每版的
  `version` / `description`（同样的 `<ul><li>` HTML）以 JSON 嵌在页面里（与 feed 是否逐条相同没比）。更合适的是改通用解析器：列表前面紧挨着、只有一个 `<b>`/`<strong>` 的空隙段当作分节标题。
  这比 OpenClaw 的 `<h3>` 情形更需要判断，误判会把正文的粗体句子当标题，要有反例测试。本次没改代码
- 跟随 channel: 否
- Recipe 状态: 不需要（需要的是通用解析器改进）

## 一键安装
- 状态: 需要验证（通用 Sparkle 路径，整包 zip）
- 端到端: **未跑**。协调会话串行执行；预期 `duo check` 报 2.19.2，`duo install` 走 Sparkle 路由，下载 65,229,770 B
- 格式: zip（`v2.19.2/superwhisper.zip` 65,229,770 B、`v2.19.1/superwhisper.zip` 65,130,709 B，均与 feed `length` 相等，
  `unzip -t` 无错）
- 校验: feed 没有 SHA 摘要，有 `edSignature`。下载 SHA-256（仅作记录）：2.19.2 `69270589…4ec6`、2.19.1 `8c686bd1…f6dd`
- **读的是**: 人人可手动下载的 GA（静态 feed，无灰度；同一个 zip 也是 Homebrew cask 的地址）
- Team: 上一版、最新版同为 `XDP69BYUP9`
- 嵌套: 没有 `Contents/Library`、LoginItems、Helpers；嵌套 `.app` 只有 Sparkle 的 `Updater.app`
- agent 集成: `Contents/Resources/claude-hook`（shell 脚本）和 `agent-hook`（universal Mach-O）；主程序字符串里有
  `.claude/plugins/installed_plugins.json`、`.claude/local/claude`、`.pi/agent/settings.json`，以及
  `curl -fsSL https://superwhisper.com/install-claude-code.sh | bash` 这类安装命令。启动时可能读写 `~/.claude`（**推断**）
- 阻塞: 无已知

## 已知问题
- beta：有 `includeBetaUpdates` 这个键名，机制和服务端都没证实（见上）
- changelog 的粗体分节被压平成条目
- 一键端到端两轮都未跑

## 建议下一步
1. 一键端到端（协调会话）：2.19.1 → 2.19.2。⚠️ agent 类 app，启动前后对比 `~/.claude`（skills、plugins、settings）。
   第二轮值得做：2.19.1 自带旧版 Sparkle，而 2.19.2 的说明正是修「更新卡在安装」（两者相关是推断）。
2. beta：在真 app 上确认 `includeBetaUpdates`（`defaults read com.superduper.superwhisper includeBetaUpdates`，拨开关或
   `defaults write` 后看 Sparkle 是换 feed 还是加标签）。在确认前、且 feed 里出现带标签条目前，不做 binding。
3. 通用解析器：`AppcastHTMLChangelogParser` 把列表前的粗体小标题识别为分节（与 OpenClaw 的 `<h3>` 一起考虑；单独开任务）。

## 如何复验

2026-10-08，包从 feed 的 enclosure 直接下载，长度与 feed `length` 相等，`unzip -t` 无错，`ditto -x -k` 解包，不安装、不启动。

```bash
curl -sSL -o feed.xml https://superwhisper.com/appcast.xml
grep -c "<item" feed.xml                      # 233
grep -c "<sparkle:channel" feed.xml           # 0
curl -fL -C - -o new.zip  https://builds.superwhisper.com/v2.19.2/superwhisper.zip
curl -fL -C - -o prev.zip https://builds.superwhisper.com/v2.19.1/superwhisper.zip
ditto -x -k new.zip new/                      # prev/ 同理
swift run --package-path application-test feed-discover new/superwhisper.app
swift run --package-path application-test channel-verify new/superwhisper.app   # prev/ 同理
strings -a new/superwhisper.app/Contents/MacOS/superwhisper \
  | grep -nE 'includeBetaUpdates|allowedChannelsForUpdater|appcast|Automatically check for updates'
```

| 包 | bundle id | short / build | Team | Sparkle | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 2.19.1 | `com.superduper.superwhisper` | 2.19.1 / 2.19.1 | XDP69BYUP9 | 2.6.4 | stable | **UPDATE → 2.19.2** | source structured: 40 entries; 2 items, headings [] |
| 2.19.2 | 同上 | 2.19.2 / 2.19.2 | XDP69BYUP9 | 2.9.6 | stable | **up to date** | 同上 |

两个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`、来源 `Notarized Developer ID`，`lipo -archs` 为 `x86_64 arm64`。
`channel-verify` 两个包都是 `winning source  Sparkle`、`deltas 0`、`release history 233 entries`、
`release notes 130 chars inline, changelogURL <nil>`。
