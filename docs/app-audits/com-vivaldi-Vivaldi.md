# Vivaldi

审计 2026-10-08（重审；2026-06-04 那版只核对了 bundle 身份（Team、版本、`SUFeedURL`），没在新旧两个包上跑生产检测，
没查渠道、changelog，也没跑一键）。

## 基本信息
- Bundle ID: `com.vivaldi.Vivaldi`（Snapshot 是独立的 `com.vivaldi.Vivaldi.snapshot`，见下）
- Team ID: `4XF3XNRN6Y` — Developer ID Application: Vivaldi Technologies AS（8.2.4133.83 与 8.2.4133.84 两个真包相同，
  均 `Notarized Developer ID`）
- 观测版本: stable `8.2.4133.84`（`CFBundleVersion` 同为 `8.2.4133.84`）、上一版 `8.2.4133.83`。
  universal（`x86_64 arm64`），`LSMinimumSystemVersion` 13.0
- 自更新机制: Sparkle 2.9.1（2054），`SUEnableAutomaticChecks` / `SUAllowsAutomaticUpdates` = YES，
  `SUScheduledCheckInterval` = 86400。Sparkle 由 Vivaldi 自己的 `SparkleUpdaterDelegate`（`browser/init_sparkle.cc`）驱动
- Homebrew: cask `vivaldi`，`auto_updates: true`，URL 与 feed 的 enclosure 相同（`stable-auto/Vivaldi.<v>.universal.tar.xz`）
- 不开源。厂商在 `vivaldi.com/source` 发布 Chromium 改动的源码包；GitHub 上有一个非官方镜像
  `cedricschwyter/vivaldi`（最后推送 2023-04-18），下面引用的 `init_sparkle.cc` 来自那里，**是旧代码**

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让位） | — | — | — |
| **snapshot**（独立 bundle id） | ✓（包自带 snapshot `SUFeedURL`） | —（`vivaldi@snapshot`，`auto_updates`） | — | — | 有 recipe，但检测上是死的（Sparkle 先应答），留作 sweep 锚点 |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`SparkleAppcastSource`，读 bundle 自己的 `SUFeedURL`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `com.vivaldi.Vivaldi` | 独立 | — | 构建时写死的 public feed | ✓ |
| snapshot | `com.vivaldi.Vivaldi.snapshot` | 独立（Pattern A） | bundle id 后缀 `.snapshot` | 构建时写死的 snapshot feed | ✓ |
| 内部（sopranos） | — | — | — | 只在非官方构建里 | ✗ 不对外 |

**stable 构建里有没有别的轨（实测 + 旧源码）：**

- 8.2.4133.84 的 `Vivaldi Framework` 里，`update.vivaldi.com/update/1.0/` 下只有一个地址：
  `public/mac/appcast.xml`。`snapshot/mac/appcast.xml` 和 `sopranos` 都**不在**这个构建里（`grep -c` = 0）。
- 同一个二进制里有源文件名 `../../browser/init_sparkle.cc` 和日志串 `Vivaldi Update URL: `。2023 年的镜像里
  `init_sparkle.cc` 的写法是：feed 地址在**编译时**按构建类型三选一（official 的 TP/Beta/Final → `public/mac`，
  official snapshot → `snapshot/mac`，非 official → `sopranos_new/mac`），唯一的运行时覆盖是命令行开关
  `--vuu`（`kVivaldiUpdateURL`），覆盖时打印的正是 `Vivaldi Update URL: `。今天的构建是否仍是这套逻辑：
  **推断**（日志串和写死的 URL 都对得上，源码没看到新版）。
- `allowedChannelsForUpdater:` / `feedURLStringForUpdater:` 这两个串在二进制里，但它们和
  `feedParametersForUpdater:sendingSystemProfile:`、`updater:didFinishLoadingAppcast:` 等一起出现，是
  `SPUUpdaterDelegate` 整份协议的方法名表，**不能**据此说 Vivaldi 实现了它们。
- 设置里没有 beta / 渠道开关：Vivaldi 的 UI（`Resources/vivaldi/bundle.js`）里，更新相关的调用只有
  `autoUpdate.checkForUpdates`、`setAutoInstallUpdates`、`enable/disableUpdateNotifier`、`installUpdateAndRestart`
  等，没有任何 channel 选择；它引用的 `update.vivaldi.com` 地址只有 `relnotes/latest.html`。
- 2023 年源码注释说 public feed 承载「TP/Beta/Final」。今天 public feed 只有 1 条、没有 `<sparkle:channel>`，
  厂商近年只在 Snapshot 发预览版（**推断**，没去翻历史 feed）。

结论：stable 与 snapshot 是两个独立 bundle id，各自的 feed 写死在构建里。duo 读的就是 bundle 自己的 `SUFeedURL`，
两条轨都跟得上，**没有需要 binding 的同 id 渠道**。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared  https://update.vivaldi.com/update/1.0/public/mac/appcast.xml`）
- 端点: `https://update.vivaldi.com/update/1.0/public/mac/appcast.xml`（nginx 静态文件，带 `etag` / `last-modified`；
  2026-10-08 连取三次、以及换成 Sparkle 风格的 UA，SHA-256 都相同，不按请求变化）
- feed 形状（2026-10-08）: **只有 1 条**（8.2.4133.84，`pubDate` Wed, 07 Oct 2026 02:30:47 +0200），
  `<sparkle:channel>` 0 条；`minimumSystemVersion` 13.0，没有 `maximumSystemVersion`、`hardwareRequirements`、
  `phasedRolloutInterval`、`criticalUpdate`；没有 `<description>`，只有 `sparkle:releaseNotesLink`
  （`/update/1.0/relnotes/8.2.4133.84.html`）；带 1 个 delta（from 8.2.4133.83）
- 版本方案: `sparkle:version` = `shortVersionString` = `8.2.4133.84` = 包里的 `CFBundleShortVersionString` 与
  `CFBundleVersion`，四段都一样，没有陷阱
- 只留一条意味着 release history 只有 1 条（`channel-verify`：`release history 1 entries`）；落后两版以上的拷贝
  也能检测到（只比较版本），但只能整包下载

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有（只对上一版） | 能，实测：一键端到端 8.2.4133.83 → .84 走 delta，`bytesDownloaded 25117814`（整包 227,218,412 B），装后与厂商包逐文件相同（见「一键安装」） |
| 证据 | `Sparkle.framework/Autoupdate` 含 `BinaryDelta` 等 12 处相关串；Sparkle 2.9.1 | 2026-10-08 head 条目带 `Vivaldi-8.2.4133.84-8.2.4133.83.universal.delta`，`length` 25,117,814，`sparkle:deltaFrom` 8.2.4133.83；`deltaFromSparkleExecutableSize` 980432 与 .83 包里 `Sparkle.framework/Sparkle` 的大小相同 | `channel-verify`：`deltas 1`（两个包都是）；`DeltaApplier` 吃 Sparkle binary delta |

- 格式: Sparkle binary delta（带 `sparkle:edSignature`）
- 阻塞项: 无。注意包里的 `Sparkle.framework` 是**扁平布局**（`Autoupdate`、`Sparkle`、`Resources/` 直接在框架根下，
  没有 `Versions/`）；两个包 `codesign --verify --deep --strict` 都通过

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval` | 否：feed 里没有 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 否：一个 universal 包；只有 `minimumSystemVersion` 13.0 | `SparkleAppcastSource` 会按下限过滤 |
| 自更新器会不会和我们抢 | 会：自动检查 + `SUAllowsAutomaticUpdates`，每 24 h | 是：同一个 feed | 端到端第二轮未跑 |

## Changelog
- 来源: Sparkle `releaseNotesLink`（网页），feed 不内联
- 结构化（接入前，2026-10-08）: `changelog pane  web page https://update.vivaldi.com/update/1.0/relnotes/8.2.4133.84.html, no structure`
  （.83 与 .84 两个包相同）
- 现状: stable 与 snapshot 各有一个 ChangelogRecipe，都是 `sourceTemplate` + `versionFromTemplate`，
  只取第一段 `Changelog since …`（每页一条，版本取自 URL，标题留作 heading）：
  stable `relnotes/{version}.html`，snapshot `relnotes/snapshot/{version}.html`
- 页面形状（2026-10-08，9,551 B）: 每个版本一页，开头一个 `<h2>` 标题，然后 10 段
  `<h2>Changelog since Vivaldi 8.2 (4133.83)</h2><ul><li>…</li></ul>`，**累积**到上一个 minor。
  第一段 `<ul class="latestchanges">` 就是本版的改动；标题里的版本号是**上一版**（「since 4133.83」那段是 .84 的内容）。
  条目形如 `[Chromium] Update to … <span>VB-131314</span>`，`<span>` 是工单号/备注
- 判断: **写 recipe 有用**，页面结构干净。但标题里的版本号差一位，不能直接当 `version` 组用。可行的写法：
  `sourceTemplate` `https://update.vivaldi.com/update/1.0/relnotes/{version}.html` + `versionFromTemplate`，只取
  `latestchanges` 那一段（每页一条，版本取自 URL）；或 `feedPagePattern` 匹配 feed 给的 `releaseNotesLink`。
  `<span>` 要去掉或保留成括注。（以上为 2026-10-08 的接入前判断；后来按第一种写法接入，`<span>` 去标签后保留文字）
- Snapshot 页（2026-10-10）: `relnotes/snapshot/<version>.html`，无开头介绍，只有一段
  `<h2>Changelog since version 4175.3</h2><ul>…</ul>`（相对上一个 snapshot build），stable 的 pattern 原样适用
- 跟随 channel: 是，按 bundle id 分开：Snapshot 走自己的 feed 和页面（`relnotes/snapshot/`），
  Snapshot VendorProbe 的 `changelogURL` 仍指博客（检测上是死 recipe，Sparkle 先应答，给的是 `releaseNotesLink`）
- Recipe 状态: stable ✓、snapshot ✓

## 一键安装
- 状态: ✓（通用 Sparkle 路径，走 delta）
- 端到端（2026-10-08，第一轮，不启动）: 8.2.4133.83 → `duo check` `update 8.2.4133.84`、`source Sparkle`；`duo install /Applications/Vivaldi.app --yes --json` → `installed`、`route sparkle`、`bytesDownloaded 25117814`（delta，整包 227,218,412 B），约 11 s。装后 8.2.4133.84，strict 通过，`Notarized Developer ID`，Team `4XF3XNRN6Y`；与厂商 8.2.4133.84 包逐文件比 SHA-256，1417 个文件、5 个软链接全部相同
- 格式: `.tar.xz`（universal，`Vivaldi.8.2.4133.84.universal.tar.xz` 227,218,412 B，与 feed `length` 相等；
  `tar -tJf` 1957 条，解包无错）。`ArchiveExtractor` 认 `xz`
- 校验: feed 没有 SHA 摘要；有 `sparkle:edSignature`，包里有 `SUPublicEDKey`（两个包相同）。
  下载哈希（SHA-256，仅作记录）：.84 `587a45ac…a82f`、.83 `702f1c85…a720`
- **读的是**: 人人可手动下载的 GA（静态 feed，无灰度；同一个 tar.xz 也是 Homebrew cask 的地址）
- Team: 上一版、最新版同为 `4XF3XNRN6Y`
- 嵌套: 没有 `Contents/Library`（无 LoginItems / LaunchAgents）。`Vivaldi Framework.framework/Versions/<v>/Helpers/`
  下 4 个 Chromium helper（`Vivaldi Helper`、`(GPU)`、`(Renderer)`、`(Alerts)`，都 `LSUIElement`），加 Sparkle
  的 `Updater.app`；全在 `Frameworks/` 下，`NestedAppGuard` 不计，随主程序退出
- 阻塞: 无已知

## 已知问题
- 一键第二轮（app 运行中）未跑

## 建议下一步
1. 一键第一轮已过（delta，`bytesDownloaded` 25117814，见「一键安装」）；第二轮（Vivaldi 运行中）未跑。
2. Changelog recipe：已完成（stable 与 snapshot，见「Changelog」）。
3. 渠道：不需要动作。stable/snapshot 已是两个 bundle id，各读自己的 feed。

## 如何复验

2026-10-08，包从 vendor 的 `stable-auto/` 目录下载（.84 是 feed 的 enclosure；.83 由 feed 里
`sparkle:deltaFrom="8.2.4133.83"` 按同一命名取得，HEAD 200；对照 `Vivaldi.9.9.9999.1.universal.tar.xz` 回 404），
长度与 feed `length` / `content-length` 相等，`tar -xJf` 解包，不安装、不启动。

```bash
curl -sS -o feed.xml https://update.vivaldi.com/update/1.0/public/mac/appcast.xml
grep -c "<item" feed.xml                      # 1
grep -c "<sparkle:channel" feed.xml           # 0
curl -fL -C - -O https://downloads.vivaldi.com/stable-auto/Vivaldi.8.2.4133.84.universal.tar.xz
curl -fL -C - -O https://downloads.vivaldi.com/stable-auto/Vivaldi.8.2.4133.83.universal.tar.xz
mkdir new prev
tar -xJf Vivaldi.8.2.4133.84.universal.tar.xz -C new   # prev/ 同理
swift run --package-path application-test feed-discover new/Vivaldi.app
swift run --package-path application-test channel-verify new/Vivaldi.app     # prev/ 同理
strings -a "new/Vivaldi.app/Contents/Frameworks/Vivaldi Framework.framework/Versions/8.2.4133.84/Vivaldi Framework" \
  | grep -E 'update\.vivaldi\.com|init_sparkle|Vivaldi Update URL|sopranos|snapshot/mac/appcast'
curl -sS https://update.vivaldi.com/update/1.0/relnotes/8.2.4133.84.html | grep -E '<h2>|latestchanges'
```

| 包 | bundle id | short / build | Team | `SUFeedURL` | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 8.2.4133.83 | `com.vivaldi.Vivaldi` | 8.2.4133.83 / 8.2.4133.83 | 4XF3XNRN6Y | `…/public/mac/appcast.xml` | stable | **UPDATE → 8.2.4133.84** | web page `…/relnotes/8.2.4133.84.html`, no structure |
| 8.2.4133.84 | 同上 | 8.2.4133.84 / 8.2.4133.84 | 4XF3XNRN6Y | 同上 | stable | **up to date** | 同上 |

两个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`、来源 `Notarized Developer ID`，`lipo -archs` 为 `x86_64 arm64`。
`channel-verify` 两个包都是 `winning source  Sparkle`、`deltas 1`、`release history 1 entries`、
`release notes 0 chars inline, changelogURL https://update.vivaldi.com/update/1.0/relnotes/8.2.4133.84.html`。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-vivaldi-Vivaldi.swift — Snapshot VendorProbe（一键 `.tar.xz` 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（enclosure 是 universal `.tar.xz`、bundle id、Team、spctl 接受，checked 2026-08-09），被核对的版本 8.2.4126.4 搬到这里。

One-click verified 2026-08-09 on 8.2.4126.4: the enclosure is a universal
`.tar.xz` holding `Vivaldi Snapshot.app`, bundle id
com.vivaldi.Vivaldi.snapshot, Team 4XF3XNRN6Y, spctl "Notarized Developer
ID". `.tarGz` covers xz — see the ImageOptim note.

### Recipes/com-vivaldi-Vivaldi.swift — Snapshot VendorProbe（检测已被 Sparkle 接管）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论和日期（真实 Snapshot bundle 声明的 `SUFeedURL` 就是这个地址，所以 Sparkle 先应答），被量的 build 8.2.4133.31 搬到这里。

DEAD FOR DETECTION, kept as a sweep anchor — same as Bartender and
ImageOptim. Measured on the real 8.2.4133.31 bundle (2026-08-31): it
declares `SUFeedURL = https://update.vivaldi.com/update/1.0/snapshot/mac/
appcast.xml`, this exact address, so Sparkle answers first.

### 2026-10-08 — snapshot feed 形状

只取了 feed，没下 Snapshot 包：`snapshot/mac/appcast.xml` 1 条（8.3.4185.3，Thu, 08 Oct 2026 08:02:13 +0200），
`<sparkle:channel>` 0 条。

### 2026-10-10 — Snapshot ChangelogRecipe 接入

只读 GET。snapshot feed 1 条 8.3.4185.3（= baseline `vendor:com.vivaldi.Vivaldi.snapshot:preview` 的
`lastGoodVersion`），`releaseNotesLink` 为 `…/relnotes/snapshot/8.3.4185.3.html`（200，2344 B 正文）；上一个
snapshot 的 `…/snapshot/8.3.4175.3.html` 仍 200（10 条）。生产解析器（`ChangelogService.loadDiagnostic`，临时测试，
version 8.3.4185.3）：1 条，`8.3.4185.3`，无日期，48 条，heading `Changelog since version 4175.3`，
首条 `[Ad Blocker] Blocked pings show up in Site info while blocker is set to Off VB-131983`。
