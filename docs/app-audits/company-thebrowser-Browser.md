# Arc

审计 2026-10-08（重审；2026-06-04 那版只核对了 bundle 身份）。

## 基本信息
- Bundle ID: `company.thebrowser.Browser`（stable 与 Early Birds / Release Candidate 构建共用）
- Team ID: `S6N382Y83G` — Developer ID Application: The Browser Company of New York Inc.
  （stable 1.167.0、1.167.1 与 RC 1.168.0 三个真包相同，均 `Notarized Developer ID`）
- 观测版本: stable `1.167.1`（build `88217`）、上一版 `1.167.0`（`88045`）；RC `1.168.0`（`88345`）。
  `LSMinimumSystemVersion` 13.0.0；universal（`x86_64 arm64`）
- 自更新机制: Sparkle 2.9.4（`SUAutomaticallyUpdate` = true，`SUScheduledCheckInterval` = 28800，
  自定义 user driver，退出时安装）
- Homebrew: cask `arc`，`auto_updates: true`，版本 `1.167.1,88217`，URL 与 feed 的 enclosure 相同（2026-10-08）
- 不开源
- 仍在更新：stable feed 三条 9-23 / 9-30 / 10-02，RC feed 10-06；近十几版的说明都只写
  Chromium 版本与安全修复

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
| stable | `company.thebrowser.Browser` | 共享 | — | stable 构建的 `SUFeedURL` | ✓ |
| beta（Early Birds，feed 叫 Release Candidate） | `company.thebrowser.Browser` | 共享 | 包内 `BCNYReleaseType` = `Release Candidate`（duo 据此判 rc，#1069）；应用内选择存在哪里**没查到** | feed-swap：RC 构建的 `SUFeedURL` 本身就指向 RC feed；stable 构建在运行时覆盖 feed | 半 ✓（见下） |
| dev / canary / prototype / PR | 同上 | 共享 | — | 内部 | ✗ |

**轨道怎么来的（从二进制字符串读出，属客户端能力，不是服务端事实）:**

- 主程序里有 `SoftwareUpdaterClient`，带 `setUpdaterFeedOverride` / `hasFeedOverride` /
  `currentUpdaterFeed`，`SoftwareUpdaterFeed` 的 CodingKeys 是 `release` / `releaseCandidate` /
  `canary` / `prototype` / `pullRequest` / `test`，路径串为 `release-candidate/D5B696F0-…/`、
  `dev/B86BBA98-…`、`prototype/57610351-…`、`pull-request/CF26021F-…/`，主机串有 `releases.arc.net`
  和内部的 `releases.browserinternal.com`。stable 构建里就带着这些串。
- 设置页（Advanced）里有用户可见的 beta 计划，名叫 **Early Birds**：`allowSwitchToBeta`、
  `_confirmSwitchToBetaSheetIsShown`、`_confirmReturnToReleaseSheetIsShown`，以及
  `_termsOfServiceSheetIsShown`（加入前要同意一份 Early Birds 服务条款）。开关受远端 feature flag
  `switch-to-beta-enabled` 控制。退出的文案说退回 stable 要等下一个 stable 周期，最长一周。
- UserDefaults 键名表里有 `updateChannelOverride`，与 `feedOverride` / `currentUpdaterFeedOverride`
  同在。**推断**这就是存应用内选择的地方，**未验证**：键名、值的编码、关闭时是删键还是写 release，都要在真 app 里拨开关读两遍才算数。
- Early Birds = `releaseCandidate` 这条对应也是推断：RC feed 条目原文是 “Thanks for using Arc
  Beta!”，RC 构建的图标是 `AppIconBeta`，两者都对得上，但没有在真 app 里拨开关看它切到哪个 feed。

**各 feed 实测（2026-10-08，`releases.arc.net`）:**

| Feed | HTTP | 条目 | 最新 | 结论 |
|---|---|---|---|---|
| `/updates.xml`（stable 包的 `SUFeedURL`） | 200 | 3 | 1.167.1 (88217)，10-02 | stable |
| `/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/updates.xml`（RC 包的 `SUFeedURL`） | 200 | 1 | 1.168.0 (88345)，10-06 | Early Birds / RC，比 stable 早一个 minor |
| `/dev/B86BBA98-6C49-428C-9BC6-CBEB71D8651D/updates.xml` | 200 | 1 | 1.68.0 (55319)，2024-10-28 | 已冻结，内部 |
| `/prototype/…/updates.xml`、`/pull-request/…/updates.xml` | 404 | — | — | 内部 |
| `/BoostBrowser-updates.xml` | 200 | 4 | `Browser 0.7.0`，2024-10-24 | 不是 Arc（同厂商早期另一个产品的旧 feed） |

`releases.browserinternal.com` 没探（内部主机，二进制里还有 `setAccessTokenProvider`）。

**duo 今天跟不跟（实测）:**

- stable 构建 → 读 stable feed（`channel-verify`：1.167.0 → UPDATE 1.167.1；1.167.1 → up to date）。
- RC 构建 → 读它自己 `SUFeedURL` 里的 RC feed（`channel-verify`：1.168.0 → up to date，下载 URL 在
  RC 目录下）。所以**已经装上 RC 构建**的副本跟的是 RC 轨。
- `detected channel`：`ReleaseChannel.detect()` 读包里唯一的轨道标记 `BCNYReleaseType`（stable 包为
  `Release`，RC 包为 `Release Candidate`），RC 构建报 **rc**（#1069；之前报 stable）。只改行上显示的渠道，
  不改推送：没有 `ChannelBinding`，`SparkleAppcastSource` 仍按已装 build 匹配到的 feed 条目定渠道，两条轨的条目都不带标签。

**缺口（形状同 OBS，但持续时间不同）:**

1. **在应用内加入 Early Birds、但还是 stable 构建**：Arc 自己按运行时覆盖去读 RC feed，会推 1.168.0；
   duo 读包里的 stable `SUFeedURL`，报 up to date。实测部分是「stable 1.167.1 包 → up to date，同时 RC
   feed 有 1.168.0」；Arc 会去读 RC feed 这一半是从二进制推断的。Arc 默认自动下载、退出时安装，
   装上 RC 构建后包里的 `SUFeedURL` 就变成 RC，duo 自然跟上。所以这个窗口只持续到 Arc 自己装上
   RC 为止，不像 OBS 那样一直卡着。
2. **RC 构建上退出 Early Birds**（推断，未验证）：Arc 说退回 stable 最长要一周，期间应该是把运行时覆盖改成 release、等 stable 版本号超过已装的 RC。duo 仍读包里的 RC `SUFeedURL`，会把**下一个 RC** 推给已经退出的用户，属跨渠道推送。要先读到退出后偏好里写的是什么，才能确认。
3. （更正）这里原来写「RC 构建被标成 stable，非 stable 一键安装要求的 `ChannelProofRegistry` 闸也就不会触发」，
   前提不成立：`ChannelProofRegistry` 只管 duo 自己选渠道的三类（vendor recipe、GitHub rule、`ChannelBinding`），
   一键安装路径上没有按渠道触发的 proof 闸。RC 拷贝读的是包里自带的 `SUFeedURL`，渠道不是 duo 选的，没有可登记的 proof。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover`：`declared https://releases.arc.net/updates.xml`）
- 端点: `https://releases.arc.net/updates.xml`（S3 + Cloudflare，`Last-Modified` 随发版变）
- feed 形状（stable，2026-10-08）: 3 条，**没有** `<sparkle:channel>`（0 条带标签，3 条无标签），
  没有 `phasedRolloutInterval`、`maximumSystemVersion`、`hardwareRequirements`、`releaseNotesLink`；
  每条 `minimumSystemVersion` 13.0.0；每条都有 `<sparkle:deltas>`（2 / 2 / 3 个）
- 版本方案: `sparkle:version` = `CFBundleVersion`（88217）；feed 的 `shortVersionString` 写成
  `1.167.1 (88217)`，包里是 `1.167.1`。比较结果正确（上一版 UPDATE、最新版 up to date），但
  `latest` 显示串带着 ` (88217)`
- 注意事项: feed 把发布日期写成小写 `<pubdate>`，格式是 `Oct 2, 2026 at 9:45:23 PM`（没有时区）。
  #1066 起 `SparkleAppcastParser` 在条目没有 `<pubDate>` 时读 `<pubdate>`，`ReleaseDate` 把这个格式读到
  「日」（没有时区，不编造钟点），`channel-verify` 由 `release history 0 entries` 变为 `3 entries`。
  Sparkle 自己按大小写精确匹配 `pubDate`，读不到这个日期；它只在分阶段推送里用日期，feed 也没有
  `phasedRolloutInterval`，所以多读日期不改变推送哪个包

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（生产链读出来了）；实际安装时走没走 delta 没验 |
| 证据 | `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` / `SUBinaryDeltaCommon.m` / `/usr/bin/bspatch`；Sparkle 2.9.4 | 2026-10-08 stable head 带 `Arc-from-88045-to-88217.delta`（42,151,554 B）与 `from-87668`；RC head 带 3 个（from 88300 / 88217 / 88045） | `channel-verify` 生产链 `deltas 2`（stable）/ `deltas 3`（RC）；`DeltaApplier` 吃 Sparkle binary delta |

- 格式: Sparkle binary delta（`.delta`，带 `sparkle:edSignature`）
- 阻塞项: 无

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval`；Arc 另有 `auto-update-*` 安装时机 flag（只管什么时候装，不管分不分配） | 否：stable 与 RC feed 都没有 `phasedRolloutInterval` | 不需要 |
| 按架构 / 按 OS 分轨 | — | 否：universal 单包；每条只有 `minimumSystemVersion` 13.0.0，没有上限 | `SparkleAppcastSource` 读 min/max 两端，下限会生效 |
| 自更新器会不会和我们抢 | 会：`SUAutomaticallyUpdate` true，8 小时检查一次，`Will install update on quit` | 是：同一个 feed | 端到端第二轮未跑 |

## Changelog
- 来源: Sparkle inline（`<description>` 里是一个 `<h3>` 包住的整段话）
- 结构化: `changelog pane  raw inline notes, 270 chars, no structure`（stable 1.167.0 / 1.167.1 两个包相同）；
  RC 包为 `raw inline notes, 194 chars, no structure`
- 内容: 每版只有一段话（Chromium 版本 + 安全修复 + “That's everything in this release”），**厂商的说明里本来就没有分节**，所以没有标题可保留。缺的是历史：面板只有最新一条
- 网页: `https://arc.net/release-notes` 跳到 Zendesk 文章 `resources.arc.net/hc/en-us/articles/20498293324823-…`，
  直接 curl 拿到的是 Cloudflare 挑战页（403 “Just a moment...”）。但 Zendesk Help Center API
  `https://resources.arc.net/api/v2/help_center/en-us/articles/20498293324823.json` 返回 200 JSON（2026-10-08），
  `body` 每版一个 `<h2>`（日期）+ `<p>V.1.167.0</p>` + 一段话，最新到 1.167.0；**补丁版（1.167.1）不单列**
- 跟随 channel: 否。RC 条目的说明只有一句 “Thanks for using Arc Beta!”，并说应用内显示的是当前公开版的说明
- Recipe 状态: 不需要（可做但收益低，见建议下一步）

## 一键安装
- 状态: 支持（通用 Sparkle 路径，第一轮端到端 ✓）
- 端到端（2026-10-08，第一轮：未运行）: 1.167.0 (88045) → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 42151554`，14 s。之后版本 1.167.1 (88217)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `S6N382Y83G`；和厂商新版包里的 app 逐文件比对（SHA-256 + 符号链接 + 目录，1947 行）完全一致。42151554 字节就是 `Arc-from-88045-to-88217.delta`。第二轮（运行中、app 自己的更新器已暂存）未跑。
- 格式: zip（stable `Arc-1.167.1-88217.zip` 452,211,252 B，与 feed `length` 相等）
- 校验: feed 没有 SHA 摘要；有 `sparkle:edSignature`，包里有 `SUPublicEDKey`（两版相同）。下载哈希
  1.167.1 `2847c892…1a73`、1.167.0 `e00521ef…056d`（SHA-256，仅作记录）
- **读的是**: 人人可手动下载的 GA（feed 无 `phasedRolloutInterval`，所有 Arc 客户端读到的都是同一个 head；
  该 zip 也是 Homebrew cask 的下载地址）
- Team: 上一版与最新版同为 `S6N382Y83G`，`codesign --verify --deep --strict` 均通过
- 嵌套: `check-bundle.sh` 没报 LoginItems / Helpers。包内有 `ArcCore.framework/Versions/A/Helpers/Browser Helper*.app`
  （Chromium 子进程，`LSUIElement`，跟随浏览器进程退出，不常驻）、`Sparkle.framework/Updater.app`、
  `PlugIns/DockTilePlugIn.plugin`，没有常驻 agent
- 阻塞: 无已知；包大（约 450 MB），且 Arc 的自更新器会在退出时安装，端到端第二轮（两边会不会冲突）未跑

## 已知问题
- 已在应用内加入 Early Birds、但还是 stable 构建时：duo 报 up to date，Arc 自己会推 RC（见 Channel 详情缺口 1）
- RC 构建退出 Early Birds 后，duo 可能推下一个 RC（缺口 2，推断，未验证）
- 发布日期只到「日」（feed 无时区，#1066 的处理）
- `latest` 显示为 `1.167.1 (88217)`（feed 的 `shortVersionString` 原样）

## 建议下一步
1. **应用内开关：不做 binding（2026-10-08 定）。** 加入 Early Birds 要先申请：官方页 `https://arc.net/earlybirds` 的 “Join our next cohort” 指向一份 Typeform 申请表（`browserco.typeform.com/to/gVGTIjRO`），help center 没有切换或退出的步骤。二进制里的远端开关 `switch-to-beta-enabled`、“Hey there, Early Bird!”、“Switch to Stable” 等文案说明，应用内的切换项只对获批的账号出现（这一条是推断）。没获批就观察不到偏好怎么存，键名和编码都没法在真 app 上确认。收益也小：已经装上 RC 构建的拷贝，包内 `SUFeedURL` 就是 RC feed，duo 已经跟随（见「如何复验」）。缺口 1 只存在于「刚加入、Arc 还没自己装上 RC」这段时间，Arc 会在退出时自动安装，窗口自己会关上。缺口 2（RC 构建退出 Early Birds）仍是推断，没有可观察的偏好就不处理。
2. （已撤）原计划的 `ArcChannel` feed-swap 绑定，原因见第 1 条。
   还有一层理由让这件事更不值得做：Arc 处于维护状态。The Browser Company 2025-05 宣布停止 Arc 的功能开发，此后只发 Chromium 引擎升级和安全补丁，新功能转到 Dia（二手报道，如 The Register 2025-05-27；原文是 CEO 的 Substack，没取到）。一手旁证是 Arc 自己 help center 的 macOS release notes（Zendesk API 读取，2026-10-08）：1.165.0–1.167.0 每条都只写升级 Chromium、修安全漏洞，并说明「这一版就这些」。所以 RC 轨现在只是更早拿到下一次 Chromium 升级。
   服务器侧试探（2026-10-08，HEAD 请求）没有改变这个判断：`releases.arc.net/release/Arc-latest.dmg` → 301 `arc.net/release/Arc-latest.dmg` → 302 `Arc-1.167.1-88217.dmg`（stable）；`/release-candidate/Arc-latest.dmg` 在 arc.net 那一跳是 404，RC 没有公开的 latest 入口；RC 目录下有和 zip 同名的 dmg（`…/release-candidate/<UUID>/Arc-1.168.0-88345.dmg` 200）。RC feed 带 `Arc-from-88217-to-88345.delta`，88217 是当时的 stable，说明厂商就是为「stable 拷贝切到 RC」准备的，缺口 1 确实存在；但加入状态存在本机哪里，服务器那头试探不出来。
3. （已做，#1069）`ReleaseChannel.detect()` 读 `BCNYReleaseType`，`Release Candidate` → `.rc`，Arc 与 Dia 共用。
   不登记 `ChannelProofRegistry`，理由见「缺口」第 3 条。
4. （可选，收益低）changelog recipe 读 Zendesk API JSON，换来带日期的历史；每版仍只有一段话，补丁版不在页上。
5. （已做，#1066）读小写 `<pubdate>`，`Oct 2, 2026 at 9:45:23 PM` 按「日」解析。

## 如何复验

2026-10-08，包从 feed 的 enclosure 直接下载，`ditto -x -k` 解包，不安装、不启动。

```bash
curl -sS -A "<browser UA>" -o feed.xml "https://releases.arc.net/updates.xml"
grep -c "<item>" feed.xml                      # 3
grep -c "sparkle:channel" feed.xml             # 0
curl -sS -o Arc-1.167.1-88217.zip "https://releases.arc.net/release/Arc-1.167.1-88217.zip"
curl -sS -o Arc-1.167.0-88045.zip "https://releases.arc.net/release/Arc-1.167.0-88045.zip"
curl -sS -o Arc-1.168.0-88345.zip \
  "https://releases.arc.net/release-candidate/D5B696F0-E63E-475D-92F6-28176299CA06/Arc-1.168.0-88345.zip"
ditto -x -k Arc-1.167.1-88217.zip new/      # 另两个同理
swift run --package-path application-test feed-discover Arc-1.167.1-88217.zip
swift run --package-path application-test channel-verify new/Arc.app      # prev/、rc/ 同理
.claude/skills/coverage-discovery/scripts/check-bundle.sh Arc-1.167.1-88217.zip
codesign -dvv new/Arc.app 2>&1 | grep TeamIdentifier
plutil -p rc/Arc.app/Contents/Info.plist | grep -E 'BCNYReleaseType|SUFeedURL|CFBundleIconName'
strings -a new/Arc.app/Contents/MacOS/Arc | grep -E 'Early Birds|updateChannelOverride|release-candidate/|switch-to-beta-enabled'
```

| 包 | bundle id | short / build | Team | `SUFeedURL` | `BCNYReleaseType` | detected | status | changelog pane |
|---|---|---|---|---|---|---|---|---|
| stable 1.167.0 | `company.thebrowser.Browser` | 1.167.0 / 88045 | S6N382Y83G | `/updates.xml` | `Release` | stable | **UPDATE → 1.167.1 (88217)** | raw inline notes, 270 chars, no structure |
| stable 1.167.1 | 同上 | 1.167.1 / 88217 | S6N382Y83G | `/updates.xml` | `Release` | stable | **up to date** | raw inline notes, 270 chars, no structure |
| RC 1.168.0 | 同上 | 1.168.0 / 88345 | S6N382Y83G | `/release-candidate/D5B6…/updates.xml` | `Release Candidate` | stable（#1069 起为 rc） | up to date（读 RC feed） | raw inline notes, 194 chars, no structure |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` 来源 `Notarized Developer ID`。
`feed-discover` 对 1.167.1：`declared  https://releases.arc.net/updates.xml`。
`channel-verify` 三个包都是 `winning source Sparkle`、`release history 0 entries`，stable `deltas 2`、RC `deltas 3`。
（#1066 之前的结果；之后 stable 1.167.1 为 `release history 3 entries`。）
