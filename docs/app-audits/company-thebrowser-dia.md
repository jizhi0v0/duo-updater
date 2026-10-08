# Dia Browser

审计 2026-10-08（重审；2026-08-17 那版只核对了 bundle 身份，没在新旧两个包上跑生产检测，没查渠道、changelog，也没跑一键）。

## 基本信息
- Bundle ID: `company.thebrowser.dia`（stable 与 Early Birds / Release Candidate 构建共用）
- Team ID: `S6N382Y83G` — Developer ID Application: The Browser Company of New York Inc.
  （stable 1.51.0、1.51.1 与 RC 1.52.0 三个真包相同，均 `Notarized Developer ID`）
- 观测版本: stable `1.51.1`（build `88214`）、上一版 `1.51.0`（`88065`）；RC `1.52.0`（`88244`）。
  `LSMinimumSystemVersion` 14.0；**只有 arm64**（`lipo -archs` = `arm64`，Homebrew cask 也写
  `depends_on arch: arm64`）
- 自更新机制: Sparkle 2.9.4（`SUAutomaticallyUpdate` = true，`SUScheduledCheckInterval` = 28800，
  自定义 user driver「Install and Relaunch」）。主程序与 Arc 同一套 `SoftwareUpdaterClient`
- Homebrew: cask `thebrowsercompany-dia`，`auto_updates: true`，版本 `1.51.1,88214`，URL 与 feed 的
  enclosure 相同（2026-10-08）
- 不开源
- 同厂商的 Arc 见 [Arc 审计](company-thebrowser-Browser.md)。两者的 RC 路径用的是**同一个** UUID
  （`release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06`），只是主机不同

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让位） | 没查 | — | — |
| **beta**（Early Birds = RC） | ✓ 已装 RC 构建 / ○ 已在应用内加入但还是 stable 构建 | — | — | — | — |
| **dev / prototype / PR** | ✗ 内部轨 | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`SparkleAppcastSource`，读 bundle 自己的 `SUFeedURL`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `company.thebrowser.dia` | 共享 | — | stable 构建的 `SUFeedURL` | ✓ |
| beta（Early Birds，feed 叫 Release Candidate） | `company.thebrowser.dia` | 共享 | 包内 `BCNYReleaseType` = `Release Candidate`（duo 据此判 rc，#1069）、图标 `AppIconBeta`；应用内选择存在哪里**没查到** | feed-swap：RC 构建的 `SUFeedURL` 本身就指向 RC feed；stable 构建在运行时覆盖 feed（推断） | 半 ✓（见下） |
| dev / canary / prototype / PR | 同上 | 共享 | — | 内部 | ✗ |

**轨道怎么来的（从 stable 1.51.1 主程序 `Contents/MacOS/Dia` 的字符串读出，属客户端能力，不是服务端事实）:**

- `SoftwareUpdaterClient.setUpdaterFeedOverride` / `hasFeedOverride` / `currentUpdaterFeed` /
  `currentUpdaterFeedOverride`；feed 描述串 release / RC / canary / prototype / PR builds；
  紧挨着的路径串是 `BoostBrowser-updates.xml`、`release-candidate/D5B696F0-…`、`dev/B86BBA98-…`、
  `prototype/57610351-…`、`pull-request/CF26021F-…/`。主机串里同时有 `releases.diabrowser.com`、
  `releases.arc.net` 和内部的 `releases.browserinternal.com`。
- **Early Birds 就是 RC 构建，这一条有字符串直接对上**（Arc 那边是推断）：确认对话框的标题
  “Hey there, Early Bird!”，它的本地化注释是 “Title for the dialog confirming switch to release
  candidate build”，按钮注释 “Proceed and switch to the release candidate build”。对话框正文说
  Early Birds 可能每天更新、退出最长要一周。反方向有 “Switch to Stable” / “Switch to stable app
  build”，文案说退回要等下一个 stable 周期，最长一周。
- 开关受远端 feature flag `switch-to-beta-enabled` 控制（与 `auto-updates-enabled` 等 flag 同在一张表）。
- UserDefaults 键名 `updateChannelOverride` 与 `feedOverride` 同在。**推断**这就是存应用内选择的
  地方，**未验证**：键名、值的编码、退出时删键还是写 release，都要在获批的真 app 里拨开关读两遍才算数。
- 官网 `https://www.diabrowser.com/earlybirds` 的 “Join Early Birds” 指向一份 Typeform 申请表
  （`form.typeform.com/to/ukTpVjIv`），也就是**加入要申请**，和 Arc 一样。

**各 feed 实测（2026-10-08，`releases.diabrowser.com`）:**

RC 地址不是猜的：主机 + 二进制里的 `release-candidate/<UUID>` + 同一处的 `BoostBrowser-updates.xml`
拼出来，随后 RC 真包的 `SUFeedURL` 逐字相同。

| Feed | HTTP | 条目 | 最新 | 结论 |
|---|---|---|---|---|
| `/BoostBrowser-updates.xml`（stable 包的 `SUFeedURL`） | 200 | 4 | 1.51.1 (88214)，Oct 2 | stable |
| `/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/BoostBrowser-updates.xml`（RC 包的 `SUFeedURL`） | 200 | 1 | 1.52.0 (88244)，Oct 3 | Early Birds / RC，比 stable 早一个 minor |
| `/dev/…`、`/prototype/…`、`/pull-request/…` 同名文件 | 400 | — | `{"message":"invalid entry item: …"}` | 内部轨，不对外 |

`releases.browserinternal.com` 没探（内部主机）。

**下载入口（2026-10-08，HEAD 请求）:**

- `release/Dia-latest.dmg`（官网下载按钮）200，`content-length` 853,357,478，与
  `release/Dia-1.51.1-88214.dmg` 相同，即 stable head（只比了大小，没下载比哈希）。
- `release-candidate/Dia-latest.dmg` **200**，855,576,052 B，与 `release-candidate/<UUID>/Dia-1.52.0-88244.dmg`
  大小相同。也就是说 RC 有公开的 latest 入口，和 Arc 不一样（Arc 那一跳是 404）。
- 对照：`release/Dia-9.99.9-99999.dmg`、`release-candidate/Nope-latest.dmg`、`release/Dia-latest.zip`
  都是 404，服务器不会对任意路径回 200。
- 这些响应的 `Last-Modified` 等于请求时刻（同一分钟里几个文件依次差一秒），不能拿来判断构建日期。

**duo 今天跟不跟（实测）:**

- stable 构建 → 读 stable feed（`channel-verify`：1.51.0 → UPDATE 1.51.1；1.51.1 → up to date）。
- RC 构建 → 读它自己 `SUFeedURL` 里的 RC feed（`channel-verify`：1.52.0 → up to date，下载 URL 在
  RC 目录下）。所以**已经装上 RC 构建**的副本跟的是 RC 轨。
- `detected channel`：`ReleaseChannel.detect()` 读包里的轨道标记 `BCNYReleaseType`（stable 包为
  `Release`，RC 包为 `Release Candidate`），RC 构建报 **rc**（#1069；之前报 stable）。只改行上显示的渠道，
  不改推送：没有 `ChannelBinding`，`SparkleAppcastSource` 仍按已装 build 匹配到的 feed 条目定渠道，两条轨的条目都不带标签。

**缺口（与 Arc 同形）:**

1. **在应用内加入 Early Birds、但还是 stable 构建**：Dia 自己按运行时覆盖去读 RC feed，会推 1.52.0；
   duo 读包里的 stable `SUFeedURL`，报 up to date。实测部分是「stable 1.51.1 包 → up to date，同时
   RC feed 有 1.52.0」，而且 RC feed 带 `Dia-from-88214-to-88244.delta`（88214 正是 stable head），
   说明厂商就是为「stable 拷贝切到 RC」准备的。Dia 会去读 RC feed 这一半是从二进制推断的。
   Dia 默认自动更新，装上 RC 后包内 `SUFeedURL` 就变成 RC，duo 跟着变，所以窗口只到 Dia 自己装上 RC 为止。
2. **RC 构建上退出 Early Birds**（推断，未验证）：Dia 说退回 stable 最长要一周，期间应是运行时覆盖
   改成 release、等 stable 版本号超过已装的 RC。duo 仍读包里的 RC `SUFeedURL`，会把**下一个 RC** 推给
   已经退出的用户，属跨渠道推送。要先读到退出后偏好里写的是什么，才能确认。
3. （更正）这里原来写「RC 构建被标成 stable，非 stable 一键安装要求的 `ChannelProofRegistry` 闸也就不会触发」，
   前提不成立：`ChannelProofRegistry` 只管 duo 自己选渠道的三类（vendor recipe、GitHub rule、`ChannelBinding`），
   一键安装路径上没有按渠道触发的 proof 闸。RC 拷贝读的是包里自带的 `SUFeedURL`，渠道不是 duo 选的，没有可登记的 proof。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared https://releases.diabrowser.com/BoostBrowser-updates.xml`）
- 端点: `https://releases.diabrowser.com/BoostBrowser-updates.xml`（Cloudflare，`cache-control: no-store`）。
  文件名里的 `BoostBrowser` 是厂商内部的旧代号（主程序里的模块名也都是 `BoostBrowser_*`），不影响检测
- feed 形状（stable，2026-10-08）: 4 条（1.51.1 / 1.51.0 / 1.50.1 / 1.50.0），**没有** `<sparkle:channel>`
  （0 条），没有 `phasedRolloutInterval`、`maximumSystemVersion`、`hardwareRequirements`、
  `releaseNotesLink`、`fullReleaseNotesLink`、`criticalUpdate`；每条 `minimumSystemVersion` 14.0；
  每条都有 `<sparkle:deltas>`（各 3 个）；说明在 `<description>` 里（HTML）
- feed 的 namespace 声明是坏的（`xmlns:_xmlns="xmlns" _xmlns:sparkle=…`），sparkle 元素靠各自的
  `xmlns="…/sparkle"` 默认命名空间；生产解析器照样读出了版本、下限和 deltas（`channel-verify` 实测）
- 版本方案: `sparkle:version` = `CFBundleVersion`（88214）；feed 的 `shortVersionString` 写成
  `1.51.1 (88214)`，包里是 `1.51.1`。比较结果正确（上一版 UPDATE、最新版 up to date），但 `latest`
  显示串带着 ` (88214)`
- 发布日期: 小写 `<pubdate>`，格式 `Oct 2, 2026 at 9:47:01 PM`（无时区）。#1066 已修：读 `<pubdate>`，
  因为没有时区只取到「日」。在含 #1066 的 main 上 `release history 4 entries`（之前是 0）
- 架构: 只有 arm64，feed 不写 `hardwareRequirements`、文件名也不带架构标记。Intel Mac 上本来就装不了，
  所以对检测没有影响；如果以前出过 universal 版本，那种旧拷贝会怎样没查

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（生产链读出来了）；实际安装时走没走 delta 没验 |
| 证据 | `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` / `SUBinaryDeltaCommon.m` / `/usr/bin/bspatch`；Sparkle 2.9.4 | 2026-10-08 stable head 带 `Dia-from-88065-to-88214.delta`（21,850,370 B）、`from-87750`、`from-87649`；RC head 带 3 个（from 88214 / 88196 / 88189） | `channel-verify` 生产链 `deltas 3`（stable 两个包、RC 包都是）；`DeltaApplier` 吃 Sparkle binary delta |

- 格式: Sparkle binary delta（`.delta`，带 `sparkle:edSignature`）
- 阻塞项: 无

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval`；Dia 另有 `auto-update-*` 安装时机 flag（看名字只管什么时候装） | 否：stable 与 RC feed 都没有 `phasedRolloutInterval` | 不需要 |
| 按架构 / 按 OS 分轨 | — | 否：arm64 单包；每条只有 `minimumSystemVersion` 14.0，没有上限 | `SparkleAppcastSource` 读 min/max 两端，下限会生效 |
| 自更新器会不会和我们抢 | 会：`SUAutomaticallyUpdate` true，8 小时检查一次；flag 名 `auto-update-inactivity-delay-in-seconds` / `auto-update-required-idle-duration-in-seconds` 暗示会在空闲时装（推断） | 是：同一个 feed | 端到端第二轮未跑 |

## Changelog
- 来源: Sparkle inline（`<description>`：一段 `<p>` 引言 + `<ul>`，每个 `<li>` 以 `<strong>标题.</strong>` 开头，结尾署名 “Shipped by …”）
- 结构化: `changelog pane  source structured: 4 entries; newest 1.51.1 (88214): 14 items, headings []; first items ["Dia 1.51.1 brings queued and steerable c", "Option for Calmer Automatic Tab Group Ic", "Simpler Tab Switching. The tab switcher "]`
  （stable 1.51.0 / 1.51.1 两个包相同）；RC 包为 `raw inline notes, 211 chars, no structure`
- 判断: `headings []` 不是压平——厂商的 inline 说明里本来就没有分节标题，14 条 = 1 段引言 + 13 个列表项，
  逐条进了面板；每项的粗体小标题并进了该项文字。网页版多一个整版标题（如 1.51.0 的
  “More control, less clutter”）和每项一个 `<h3>`，feed 里没有。**不值得为此写 recipe**
- 网页: `https://www.diabrowser.com/changelog`（全部历史，Mac 与 Windows 混排，按月分组）；
  `/release-notes/latest` 跳到 `/changelog/mac/1-51-0`（2026-10-08 feed head 已是 1.51.1，补丁版的页面没单列）
- 跟随 channel: 否。RC 条目只有一句 `<h2>`「Thanks for being an early tester of Dia! …」加一段说明，
  并说应用内显示的是当前公开版的说明
- Recipe 状态: 不需要

## 一键安装
- 状态: ✓（通用 Sparkle 路径，走 delta）
- 端到端（2026-10-08，第一轮）: 上一版 1.51.0 (88065) 放进 `/Applications`（`ditto -x -k` 解包、不启动），
  `duo check` 报 `update 1.51.1 (88214)`、`route in-place`；`duo install /Applications/Dia.app --yes --json` →
  `outcome installed`、`applied true`、`route sparkle`、`bytesDownloaded 21850370`（即
  `Dia-from-88065-to-88214.delta`），耗时约 13 s。装后：版本 1.51.1 / 88214，bundle inode 变了，
  `codesign --verify --deep --strict` 通过，`spctl` `accepted`（`Notarized Developer ID`），Team `S6N382Y83G`；
  与厂商 1.51.1 zip 解包逐文件比 SHA-256，2251 个文件全部相同，22 个软链接目标全部相同
- 格式: zip（stable `Dia-1.51.1-88214.zip` 852,095,538 B，与 feed `length` 相等）
- 校验: feed 没有 SHA 摘要；有 `sparkle:edSignature`，包里有 `SUPublicEDKey`（三个包相同）。下载哈希
  1.51.1 `88e2e8c5…e093`、1.51.0 `762e669f…298a`、RC 1.52.0 `0c53169f…933a`（SHA-256，仅作记录）
- **读的是**: 人人可手动下载的 GA（stable feed 无 `phasedRolloutInterval`，所有客户端读到同一个 head；
  该 zip 也是 Homebrew cask 的下载地址）。RC 构建读的是 RC feed head，那条轨同样可公开下载
  （`release-candidate/Dia-latest.dmg`），只有已装 RC 构建的拷贝才会读到它
- Team: 上一版、最新版、RC 同为 `S6N382Y83G`，`codesign --verify --deep --strict` 均通过
- 嵌套: `check-bundle.sh` 没报 LoginItems / Helpers；包内没有 `Contents/Library`。有
  `ArcCore.framework/Versions/A/Helpers/Browser Helper*.app` 共 8 个（`LSUIElement`，bundle id
  `company.thebrowser.browser.helper`，Chromium 子进程；其中 4 个叫 “Aperitif”，作用没查）、
  `Sparkle.framework/Updater.app`、`PlugIns/DiaDockTilePlugIn.plugin`。主程序里没有 `SMAppService` /
  `LaunchAgents` 字符串，没看到常驻 agent
- 阻塞: 无已知；包大（约 850 MB，delta 只有约 21 MB），Dia 的自更新器默认自动装，第二轮（两边会不会冲突）未跑

## 已知问题
- 已在应用内加入 Early Birds、但还是 stable 构建时：duo 报 up to date，Dia 自己会推 RC（缺口 1）
- RC 构建退出 Early Birds 后，duo 可能推下一个 RC（缺口 2，推断，未验证）
- `latest` 显示为 `1.51.1 (88214)`（feed 的 `shortVersionString` 原样）
- 发布日期只到「日」（feed 无时区，#1066 的处理）

## 建议下一步
1. **应用内开关：先不做 binding**，理由同 Arc：加入要走 Typeform 申请，切换项受远端 flag
   `switch-to-beta-enabled` 控制，没获批就看不到偏好怎么存（`updateChannelOverride` 是推断）。
   已装 RC 构建的拷贝 duo 已经跟随。与 Arc 不同的是 Dia 仍在积极开发，RC 每周领先一个 minor，
   缺口 1 对 Dia 的价值比对 Arc 高；如果有获批的账号，值得在真 app 上拨开关读一次偏好再决定。
2. （已做，#1069）`ReleaseChannel.detect()` 读 `BCNYReleaseType`，`Release Candidate` → `.rc`，Arc 与 Dia 共用。
   不登记 `ChannelProofRegistry`，理由见「缺口」第 3 条。
3. 一键端到端第二轮：Dia 运行中、它自己的更新器也拿到同一版时，两边会不会冲突。

## 如何复验

2026-10-08，包从 feed 的 enclosure 直接下载（大文件分段 `curl -r` 后拼接，长度与 feed `length`
相等，`unzip -t` 无错），`ditto -x -k` 解包，不安装、不启动。

```bash
curl -sS -A "<browser UA>" -o feed.xml "https://releases.diabrowser.com/BoostBrowser-updates.xml"
grep -c "<item>" feed.xml                      # 4
grep -c "sparkle:channel" feed.xml             # 0
curl -sS -A "<browser UA>" -o rc.xml \
  "https://releases.diabrowser.com/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/BoostBrowser-updates.xml"
curl -sS -o Dia-1.51.1-88214.zip "https://releases.diabrowser.com/release/Dia-1.51.1-88214.zip"
curl -sS -o Dia-1.51.0-88065.zip "https://releases.diabrowser.com/release/Dia-1.51.0-88065.zip"
curl -sS -o Dia-1.52.0-88244.zip \
  "https://releases.diabrowser.com/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/Dia-1.52.0-88244.zip"
ditto -x -k Dia-1.51.1-88214.zip new/      # prev/、rc/ 同理
swift run --package-path application-test feed-discover Dia-1.51.1-88214.zip
swift run --package-path application-test channel-verify new/Dia.app      # prev/、rc/ 同理
.claude/skills/coverage-discovery/scripts/check-bundle.sh Dia-1.51.1-88214.zip
plutil -p rc/Dia.app/Contents/Info.plist | grep -E 'BCNYReleaseType|SUFeedURL|CFBundleIconName'
strings -a new/Dia.app/Contents/MacOS/Dia \
  | grep -E 'Early Bird|release candidate build|updateChannelOverride|release-candidate/|switch-to-beta-enabled'
```

| 包 | bundle id | short / build | Team | `SUFeedURL` | `BCNYReleaseType` | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|---|
| stable 1.51.0 | `company.thebrowser.dia` | 1.51.0 / 88065 | S6N382Y83G | `/BoostBrowser-updates.xml` | `Release` | stable | **UPDATE → 1.51.1 (88214)** | source structured: 4 entries; 14 items, headings [] |
| stable 1.51.1 | 同上 | 1.51.1 / 88214 | S6N382Y83G | `/BoostBrowser-updates.xml` | `Release` | stable | **up to date** | 同上 |
| RC 1.52.0 | 同上 | 1.52.0 / 88244 | S6N382Y83G | `/release-candidate/D5B6…/BoostBrowser-updates.xml` | `Release Candidate` | stable（#1069 起为 rc） | up to date（读 RC feed） | raw inline notes, 211 chars, no structure |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` 来源 `Notarized Developer ID`，`lipo -archs` 均为 `arm64`。
`feed-discover`：1.51.1 为 `declared  https://releases.diabrowser.com/BoostBrowser-updates.xml`；RC 1.52.0 为
`declared  https://releases.diabrowser.com/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/BoostBrowser-updates.xml`。
`channel-verify`（main 含 #1066）三个包都是 `winning source Sparkle`、`deltas 3`；stable 两个包
`release history 4 entries`，RC `1 entries`。#1066 之前同样的 stable 包是 `0 entries`。
