# JetBrains Air

审计 2026-10-08（重审；2026-06-04 那版是空壳：没在真包上跑生产检测，一键写「未实现」，
「只有 preview 一条轨」也没核对 Sparkle feed 那一侧）。

## 基本信息
- Bundle ID: `com.jetbrains.air`（Public Preview 的 dmg、Toolbox 装的拷贝、nightly dmg 都是它）
- Team ID: `2ZEFAR8TH3` — Developer ID Application: JetBrains s.r.o.（262.834.70 与 262.1037.6 两个真包相同，
  均 `Notarized Developer ID`）
- 观测版本: `262.1037.6`（`CFBundleShortVersionString` = `CFBundleVersion`，2026-10-08 发布）、上一版 `262.834.70`
  （2026-09-30）
- 架构 / 系统: 按架构分包（`macos_aarch64` / `macos_x64` 两个 dmg、两个 feed）；aarch64 包 `lipo -archs` = `arm64`；
  `LSMinimumSystemVersion` 写的是 `10.9`（模板值），主程序 `vtool -show-build` 的 `minos` 是 `11.0`
- 自更新机制: Sparkle 2.6.4（Info.plist 只有 `SUFeedURL` 和 `SUPublicEDKey`，没有 `SUAutomaticallyUpdate` 等键）；
  也可以由 JetBrains Toolbox 安装和更新
- Homebrew: cask `jetbrains-air`，`auto_updates true`，2026-10-08 版本 `262.834.70`（arm sha256 与厂商
  `.sha256` 文件一致），livecheck 读 releases API `code=AIR&latest=true&type=preview`
- 基于 Fleet 的运行时（`Contents/app/bootstrap/ship.json` 的 `id` 是 `SHIP`，`supportedProducts` = `AIR`）；不开源
- **独立 app 与 IDE 插件是两个东西**，见下面「独立 app 与 IDE 插件」一节

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Toolbox |
|--------------|---------|----------|-----|--------|-------------|---------|
| **Public Preview**（API `preview`，feed `eap`） | ✓ 非 Toolbox 拷贝 | —（`auto_updates`，让位） | — | — | — | ✓ Toolbox 拷贝（只检测） |
| **nightly** | ✓ 已装 nightly 构建（读它自己的 nightly feed）；行上渠道显示为 stable、changelog 是 Public Preview 的（见下） | — | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）:
- **Toolbox 管理的拷贝** → **Toolbox**（`ToolboxSource`，releases API `code=AIR`，`type=eap,preview`）。
  `runSources` 对 Toolbox 拷贝不看任何别的源。
- **其余拷贝**（官网 / cask dmg） → **Sparkle**（`SparkleAppcastSource`，读包里的 `SUFeedURL`）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| Public Preview | `com.jetbrains.air` | — | 包里 `SUFeedURL` = `…/fleet-feed/AIR/eap/<arch>/feed.xml` | 包自带的 feed | ✓ |
| nightly | `com.jetbrains.air` | 共享 | 包里 `SUFeedURL` = `…/fleet-feed/AIR/nightly/<arch>/feed.xml`；版本两段式（`262.1054`） | 包自带的 feed | 半 ✓ 见下 |

- 厂商对外只有一条轨：releases API 里 `AIR` 共 37 条，全部 `type` = `preview`、`printableReleaseType` =
  `Public Preview`（2026-10-08）。`type=release`、`eap`、`rc`、`beta` 没有一条；不带 `type` 时返回 `{"AIR":[]}`。
- `ReleaseChannel.detect()` 把它报成 **stable**（`inferred stable`，没有任何渠道标记）。对单轨的 app 这不是问题：
  Sparkle feed 不带 `<sparkle:channel>`，`ToolboxSource` 自己按 `eap,preview` 查。
- **nightly feed 存在且公开**：`fleet-feed/AIR/nightly/macos_aarch64/feed.xml` 200，1 条，`262.1054`
  （两段式版本号，2026-10-08 03:34 GMT），enclosure 在 `plugins.jetbrains.com/fleet-parts/fleet-installer/…`，
  不在 `download.jetbrains.com/air/installers/`。两个 Public Preview 包的 `SUFeedURL` 都指向 `eap`，不是 nightly。
  官网、API、Toolbox 目录都不发 nightly。
- **nightly 包（2026-10-08 实测，`AIR-262.1054-aarch64.dmg`，316,808,491 B = feed `length`）**：只读挂载后读 Info.plist——
  `CFBundleIdentifier` = `com.jetbrains.air`、`CFBundleName` = `Air`，与 Public Preview **共用 bundle id 和名字**；
  `CFBundleShortVersionString` / `CFBundleVersion` 都是 `262.1054`（两段式，Public Preview 是三段式 `262.1037.6`）；
  `SUFeedURL` = `…/fleet-feed/AIR/nightly/macos_aarch64/feed.xml`；`SUPublicEDKey` 与 Public Preview 相同；
  Team `2ZEFAR8TH3`，`codesign --verify --deep --strict` 通过。**公证**：`stapler validate` 说没有装订票据，
  `spctl` 来源是 `Developer ID`（Public Preview 是 `Notarized Developer ID`，且有装订票据），
  `syspolicy_check distribution` 报 `Notary Ticket Missing`；是否已公证只是没装订，未验证。
- `channel-verify` 对 nightly 包：`inferred stable`、`detected channel → stable`，`winning source Sparkle`，读它自己的
  nightly feed，`latest 262.1054`、`status up to date`。所以**已装 nightly 的拷贝跟的是 nightly 轨**，不会被推 Public Preview
  （反过来也一样：Public Preview 拷贝读 eap feed）。两处不对：行上渠道显示为 stable；`changelog pane` 是 recipe 的
  Public Preview 说明（`newest 262.1037.6`），没有 262.1054 这一条。duo 的安装闸看签名、Team、架构、OS 下限，
  不看公证（读 `SignatureVerifier` 得出），所以未装订票据不会挡一键。
- 应用内有没有切到 nightly 的开关**未验证**：要启动 app 才能看，Air 是 agent 类 app，按审计约束没有启动。
- `release`、`preview`、`stable` 三个 feed 名都是 403（`release`/`preview`）或断连（`stable` arm），即不存在。

## 更新检测
- 源（非 Toolbox 拷贝）: `SparkleAppcastSource`。`feed-discover` 对 262.1037.6：
  `declared  https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml`
- 源（Toolbox 拷贝）: `ToolboxSource`。`state.json` 里 Air 条目的 `productCode` 是 `null`，靠
  `apiCodeWithoutToolboxCode["com.jetbrains.air"] = "AIR"` 查 releases API，与 Toolbox 记录的 `buildNumber` 比较；
  动作是「打开 Toolbox」，duo 不装
- 端点:
  - Sparkle: `https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml`（x64 把
    `macos_aarch64` 换成 `macos_x64`）。单条 item，`<sparkle:version>` 三段式，无 `shortVersionString`，
    `<description>` 为空，无 `<sparkle:channel>`、无 `minimumSystemVersion`/`maximumSystemVersion`、
    无 `phasedRolloutInterval`、无 `<sparkle:deltas>`；enclosure 带 `sparkle:edSignature`
  - releases API: `https://data.services.jetbrains.com/products/releases?code=AIR&type=eap,preview`（Toolbox 路径）；
    每条有 `build`（三段，= 包的 `CFBundleVersion`）、`version`（两段列车号）、各平台 `downloads.*.link` +
    `size` + `checksumLink`（`.sha256`）、`whatsnew`、`notesLink`（YouTrack 查询）、`patches`（37 条全空）
- 2026-10-08 两边一致：feed 和 API 的最新都是 262.1037.6，enclosure 与 API `macos_aarch64.link` 是同一个 URL、
  同一个 `length` 297,841,397。2026-09-21 曾经不一致（feed 先给了 API 从未出现过的 262.991.1，见「历史与实测」），
  截至 2026-10-08 API 的 37 条里仍没有任何 `262.991.*`
- 注意事项:
  - **Toolbox 目录比 API 晚**：2026-10-08 13:23 与 13:31 UTC 两次（feed `pubDate` 12:57:37 GMT 之后约 25 / 34 分钟），Toolbox 的
    `eap.feed.xz.signed` 与 `public-feed-arm.feed.xz.signed` 里 Air 最新仍是 262.834.70，而 API 已是 262.1037.6。
    所以 Toolbox 行在这段窗口里会显示「→ 262.1037」，点开 Toolbox 却还没有这个版本。和 #782 修的方向相反
    （那次是 Sparkle feed 领先），窗口有多长没量
  - Toolbox 行显示的是 API 的 `version`（两段 `262.1037`），比较用的是 `build`
  - Homebrew cask 落后（262.834.70），但 `auto_updates true` 让 `HomebrewCaskSource` 不应答，不影响

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不能（没东西可吃） |
| 证据 | `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta` 等字符串 32 处；Sparkle 2.6.4 | 2026-10-08 eap feed 无 `<sparkle:deltas>`；releases API 37 条 `patches` 全为 `{}` | `DeltaApplier` 只在 feed 给 delta 时才用 |

- 格式: 无
- 阻塞项: 厂商不发

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 支持 `phasedRolloutInterval` | 否：feed 无该字段；请求不带设备参数 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 按架构：是，两个 feed、两个 dmg。按 OS：否，feed 不写上下限；包 `minos` 11.0 | 包里的 `SUFeedURL` 已经是本架构的 feed，不用选 |
| 自更新器会不会和我们抢 | 会：Sparkle 2.6.4 在包里；Toolbox 拷贝由 Toolbox 更新 | 是：同一个 eap feed | 非 Toolbox 拷贝的端到端第二轮未跑 |
| 构建有效期 | `ship.json` 的 `meta.expirationDate` = `buildDate` + 60 天（262.834.70：2026-09-30 → 2026-11-29；262.1037.6：2026-10-08 → 2026-12-07） | 字段写在包里 | 到期后 app 会怎样**未验证**（没启动）；推断是预览版过期机制 |

**读的是**：Sparkle 路径读的是 eap feed 的唯一一条，也就是轨道最新；它与 releases API 最新、官网 / API 的
下载链接是同一个构建（2026-10-08 实测相同 URL 与长度），任何人都能手动下载，也是 app 自己的 Sparkle 会装的那个。
不存在「本机被分配」的概念。2026-09-21 那次 feed 领先 API 的情况说明 feed 偶尔会先于公开下载页给出构建；
对非 Toolbox 拷贝，这仍然是 Air 自己的更新器会装的那一版，所以跟随 feed 是对的。

## Changelog
- 来源: `ChangelogRecipe`（`structuredFormat: .jetBrainsProductReleases`），源
  `https://data.services.jetbrains.com/products/releases?code=AIR&type=eap,preview,release`，`maxEntries: 20`
- 结构化（两个包相同，`channel-verify` 原文）:
  `changelog pane  recipe changelog:com.jetbrains.air:-: 20 entries; newest 262.1037.6: 5 items, headings []; first items ["Pin tasks in a dedicated Pinned section", "Invoke built-in and custom Codex subagen", "Model search now filters the list to mat"]`
- 判断: `headings []` 不是压平。262.1037.6 的 `whatsnew` 是一个 `<h4>`（「Stability and performance improvements,
  pin tasks, and improved subagents support」）加 5 个 `<li>` 再加反馈页脚；decoder 把 `<h4>` 用作条目标题，
  5 个 `<li>` 逐条进面板，页脚被丢掉。37 条里 29 条有 `whatsnew`
- Sparkle feed 的 `<description>` 是空的、无 `releaseNotesLink`，所以只能靠 recipe（`release notes 0 chars inline`）
- Toolbox 拷贝: recipe 按 bundle id 挂，面板顺序 recipe 在先，**推断**同样显示这 20 条（`--check` 不打印 pane 行）
- 跟随 channel: 否（只有一条公开轨）
- Recipe 状态: 已有，有效

## 一键安装
- 状态: **非 Toolbox 拷贝：✓**（通用 Sparkle 路径）；**Toolbox 拷贝：不做**，
  行动作是「打开 Toolbox」（`requiresManualInstaller: true`）
- 端到端（2026-10-08，第一轮，不启动）: 上一版 262.834.70 用 `ditto` 放进 `/Applications`，`duo check` 报
  `update 262.1037.6`、`route in-place`、`source Sparkle`；`duo install /Applications/Air.app --yes --json` →
  `outcome installed`、`applied true`、`route sparkle`、`bytesDownloaded 297841397`（整包，feed 无 delta），约 36 s。
  装后：版本 262.1037.6，bundle inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted`
  （`Notarized Developer ID`），Team `2ZEFAR8TH3`；与厂商 262.1037.6 dmg 内的 `Air.app` 逐文件比 SHA-256，
  1560 个文件全部相同，9 个软链接目标全部相同。**按路径装**：同一台机器若还有 Toolbox 管理的另一份 Air，
  按名字会撞到那一份；那一份没有被动到
- 格式: dmg（`Air-<build>-aarch64.dmg` / `Air-<build>.dmg`），包内只有 `Air.app`
- 校验:
  - feed 有 `sparkle:edSignature`，包里 `SUPublicEDKey` = `U2jeSprto8p3VM94307OhPEaHn3Io31Cd48f5ti9nko=`（两个包相同）。
    对 262.1037.6 真包用 CryptoKit `Curve25519.Signing` 验签通过；翻转一个字节后验签失败
  - releases API 每个下载都有 `checksumLink`（SHA-256 文件）；两个真包与之相等：
    262.1037.6 `5dac143e6bef4015d14d2a8b9d53e46e0891e5945c9d57ad9bd3d108d5726791`，
    262.834.70 `0e491ba2c147f3ff77566cb2a85e63774dbea6591da60f4177d02432e2eb65ec`。
    Sparkle 路径不读 API，所以这个摘要用不上；EdDSA 已经覆盖完整性
- **读的是**: 轨道最新 = 人人可手动下载的那一版（理由见上「读的是」）
- Team: 上一版、最新版同为 `2ZEFAR8TH3`，`codesign --verify --deep --strict` 均通过，`spctl` `accepted`
- 嵌套: `Contents` 下只有 `Frameworks`（`Sparkle.framework`，含 `Updater.app`）、`MacOS`、`Resources`、`app`、`jbr`、
  `license`；没有 `Contents/Library/LoginItems` 或 `Contents/Helpers`，`find -name '*.app' -maxdepth 4` 无结果。
  `app/bin/jetbrainsd.tar.gz` 是个打包的守护进程（运行时解开，作用没查）
- 阻塞: 无已知；第二轮（Air 运行中、它自己的 Sparkle 也拿到同一版）未跑

## 独立 app 与 IDE 插件

**两种形态，duo 只管前一种：**

| | 独立 app「Air」 | IDE 插件「Air」 |
|---|---|---|
| 身份 | `com.jetbrains.air`，`Air.app` | Marketplace 插件 id 33314，`xmlId` = `com.intellij.air` |
| 分发 | 官网 dmg（现已无下载入口，见下）/ releases API / Toolbox / Homebrew cask | JetBrains Marketplace；2026.3 EAP 起随 IDE 捆绑 |
| 版本 | `262.1037.6` 这类 app 构建号 | 按 IDE 构建范围发：`262.8665.490`（`262.*`，即 2026.2）、`263.6259.32`（`263.6259.*`，2026.3 EAP） |
| 更新 | Sparkle / Toolbox | IDE 自己的插件更新器 |

**官方来源（2026-10-08 读取）:**

- JetBrains 博客 2026-09-22，Kirill Skrygan，「JetBrains Air: Building a System of Products for Agentic Software
  Development」（<https://blog.jetbrains.com/blog/2026/09/22/introducing-jetbrains-air/>）：Air 重新定义为一组产品，
  列出的是 Air in JetBrains IDEs、Air Teams、Air Governance（原 JetBrains Central）。**独立桌面 app 不在列表里，
  文中也没有说它停止、迁移或继续。**
- JetBrains Air 博客 2026-09-28，「Air Teams: …」（<https://blog.jetbrains.com/air/2026/09/introducing-air-teams/>）：
  原话 “developers don’t need another standalone app”，并说要 “expanding Air beyond a standalone desktop app”。
  这是方向表态，没有日期，也没有说现有 app 怎么处理。
- JetBrains AI 博客 2026-10-01，「A New Agentic Experience: JetBrains Air in IDEs – EAP Now Open」
  （<https://blog.jetbrains.com/ai/2026/10/air-in-ides-eap/>）：插件在 Marketplace 上，2026.3 EAP 构建内置；
  AI Assistant 继续作为单独插件提供；“Over time, we expect Air to become the primary experience …”。
  不提独立 app。
- 帮助文档「JetBrains Air in IDEs overview」（<https://www.jetbrains.com/help/air-ides/air-overview.html>，页面日期
  2026-10-05）：2026.2 需从 Marketplace 装插件，2026.3 EAP 捆绑；除 Android Studio 外的 JetBrains IDE 都可用。不提独立 app。
- 产品页 <https://www.jetbrains.com/air/>（2026-10-08）：「Try air today」下只有 In your IDE / In your browser（Air Teams）/
  From the command line（Air Gateway），**没有桌面 app 下载**；页面原始 HTML 里没有 `.dmg` / `macos` / `download`。
  `https://air.dev/download` 301 → `https://www.jetbrains.com/air/`，`https://www.jetbrains.com/air/download/` 404。
- 与此同时，独立 app **仍在发布**：262.1037.6 于 2026-10-08 同时出现在 releases API、eap Sparkle feed 和
  `download.jetbrains.com/air/installers/`。

**结论:**

1. 独立 app 在 2026.3 之后是否继续：**未找到官方说法**。没有公开的停止日期、迁移说明或「Air 已并入 IDE」的通知。
   能确认的只有：官方表态不再需要“another standalone app”，产品页已撤下桌面下载入口，但构建仍按周发布。
   2026.3 正式版「11 月」发布这一点只见于 JetBrains 的邮件公告；公开页面上只看到「2026.3 EAP」，没找到具体月份。
2. 包里 `expirationDate` = 构建日 + 60 天（见 Phase 3⅞）。**推断**：如果独立 app 停发，现有拷贝最晚在最后一个构建
   60 天后过期。没启动验证到期行为。
3. IDE 插件形态与 duo **无关**，不需要做任何事：它不是 app bundle，不在 `/Applications`，由宿主 IDE 的插件管理器
   从 Marketplace 更新，版本号绑定 IDE 构建范围；duo 的扫描、检测、安装单位都是 `.app`。宿主 IDE 本身
   （IntelliJ IDEA 等）duo 已经通过 Toolbox / releases API 覆盖，插件随 IDE 走。
4. 对独立 app 的影响要盯的是：eap feed 或 releases API 的 `AIR` 停更（行会一直报 up to date，这是对的）、
   或者某天 feed 换成「请改用 IDE」之类的终版构建。届时重审。

## 已知问题
- Toolbox 拷贝：API 先于 Toolbox 目录出新版本时（2026-10-08 观察到至少 34 分钟），行会提示一个 Toolbox 里还没有的版本
- `ToolboxSource` 注释里「Air/Fleet 的 baked-in `SUFeedURL` 指向 nightly」对 Air 已不成立：两个 Public Preview 包都指向
  `eap`。Air 走 API 分支、不用 `retargetChannel`，所以不影响行为，只是注释过时（Fleet 那半没核）
- Air 自己的 Sparkle 与 duo 会不会冲突（一键第二轮）未跑
- 已装 nightly 的拷贝：行上渠道显示为 stable；changelog 面板显示的是 Public Preview 的说明（recipe 不分轨）
- 能否在应用内切到 nightly 未知（要启动 app）

## 建议下一步
1. 一键第二轮需要启动 Air，先确认能接受它在启动时写 `~/.claude/skills`（启动前后对比）。第一轮已过（见「一键安装」）。
2. nightly 包已读（见「Channel 详情」）。剩下两件：要查应用内有没有渠道开关，得启动 app，同上；如果要让 nightly 拷贝的行
   显示 nightly、并且不显示 Public Preview 的 changelog，判据可以是 `SUFeedURL` 里的 `/nightly/`（未做，需要先定要不要）。
3. 2026.3 正式版发布后（预计 11 月）重查：releases API `code=AIR`、eap feed、产品页，看独立 app 是否停发或改名。
4. （可选，代码）把 `ToolboxSource` 里关于 Air 指向 nightly 的那句注释改掉。

## 如何复验

2026-10-08。dmg 用 `curl -fL --retry 5 -C -` 从 releases API 的 `downloads.macos_aarch64.link` 下载，大小与 API `size`、
feed `length` 相等，SHA-256 与 `checksumLink` 文件相等；`hdiutil attach -readonly -nobrowse` 挂载后 `ditto` 出
`Air.app`，不安装、不启动。

```bash
curl -fsS "https://data.services.jetbrains.com/products/releases?code=AIR&type=release,eap,preview,rc,beta" -o air.json
curl -fsS "https://data.services.jetbrains.com/products/releases?code=AIR"          # {"AIR":[]}
curl -fsS "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml"
curl -fsS "https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/nightly/macos_aarch64/feed.xml"
curl -fL --retry 5 -C - -o Air-262.1037.6-aarch64.dmg \
  https://download.jetbrains.com/air/installers/macos_aarch64/Air-262.1037.6-aarch64.dmg
curl -fL --retry 5 -C - -o Air-262.834.70-aarch64.dmg \
  https://download.jetbrains.com/air/installers/macos_aarch64/Air-262.834.70-aarch64.dmg
shasum -a 256 Air-*.dmg     # 对照 <link>.sha256
swift run --package-path application-test channel-verify Air-262.834.70-aarch64.dmg
swift run --package-path application-test channel-verify Air-262.1037.6-aarch64.dmg
swift run --package-path application-test feed-discover <unpacked>/Air.app
swift run --package-path application-test channel-verify --check com.jetbrains.air   # Toolbox 拷贝
# Toolbox 目录（CMS 签名的 xz JSON）
curl -fsS -o arm.signed https://download.jetbrains.com/toolbox/feeds/v1/public-feed-arm.feed.xz.signed
openssl cms -verify -noverify -inform DER -in arm.signed | xz -d > arm.json
```

| 包 | bundle id | short / build | Team | `SUFeedURL` | detected | winning source | status | changelog pane |
|---|---|---|---|---|---|---|---|---|
| 262.834.70 dmg | `com.jetbrains.air` | 262.834.70 / 262.834.70 | 2ZEFAR8TH3 | `…/AIR/eap/macos_aarch64/feed.xml` | stable | Sparkle | **UPDATE → 262.1037.6** | recipe: 20 entries; 5 items, headings [] |
| 262.1037.6 dmg | 同上 | 262.1037.6 / 262.1037.6 | 2ZEFAR8TH3 | 同上 | stable | Sparkle | **up to date** | 同上 |
| Toolbox 拷贝（`buildNumber` 262.834.44） | 同上 | 262.834.44 | — | 同上 | stable | **Toolbox** | **UPDATE → 262.1037** | 未打印 |

两个 dmg：`release notes 0 chars inline, changelogURL <nil>`、`release history 1 entries`、`deltas 0`；下载 URL 为
`https://download.jetbrains.com/air/installers/macos_aarch64/Air-262.1037.6-aarch64.dmg`。

## 历史与实测

- 2026-09-21（摘自 #782 与 `ToolboxSource` 注释）：`fleet-feed/AIR/eap` 给出 262.991.1（09-18 发布），而 releases API、
  Toolbox 的 `eap` / `public-feed-arm` 目录和官网下载都停在 262.834.44，Toolbox 行把用户引向 Toolbox 里没有的版本；
  于是 Toolbox 拷贝改为查 releases API（`code=AIR`，`type=eap,preview`）。`type=eap` 单查对 AIR 返回空；`latest=true`
  加多个 type 时只返回一条（跨 type 最新）。
- 2026-09-23：`https://air.dev/changelog` 已变成跳转壳（`window.location.replace("https://www.jetbrains.com/air/")` + meta refresh），
  `/assets/index-aByjwpFL.js`（142 KB）里只剩 React 运行时和同一个跳转，没有任何发布数据——旧的两阶段 JSX 正则 recipe 一条也匹配不上，
  界面退回嵌入网页。`jetbrains.com/air/changelog/`、`/air/whatsnew/` 均 404。
- 同日实测 releases API：不带 `type` 时 `AIR` 数组为空；`type=preview` 返回 33 条（`eap`、`release` 各 0 条），
  其中 25 条带 `whatsnew`，最早的 8 条（261.311.29 及更早，除 261.232.34 外）为空、被跳过。
  `version` 是两段式列车号（`262.834`，多个 build 共用），262.834.44 的包 `CFBundleShortVersionString` = `CFBundleVersion` = `262.834.44`，
  与 `build` 一致，所以按 `build` 建条目。
- `whatsnew` 三种形态：`<h4>` + `<ul><li>`（功能版）、`<h4>` + `<p>` 正文（262.43.30/32）、只有 `<p>`（小修复，261.311.x 第一段是标题式短句）；
  页脚是 `<p>Share your feedback…</p>`，或 `Learn more about Air… and share your feedback…`，早期几条页脚不在 `<p>` 里。
  相邻 build 常复用同一份说明（如 262.132.34/35），是厂商原样。
- 2026-09-23：多 type 请求的排序（为 `type=eap,preview,release` 下未来的 release build 会不会被 `maxEntries: 20` 截掉）。
  AIR 目前只有 preview，没法直接测；在同端点的 `IIU` 上测：`type=eap,release` 与 `type=release,eap` 都返回 408 条、顺序完全相同，
  eap/release 交错，按 build 降序（`263.5153.40` e、…、`262.10968.63` r、`262.10315.125` r、`262.10315.19` e…），不按 type 分组。
  同日补测 `IIU&type=eap,preview,release,rc`：452 条，eap/rc/release 三种交错，相邻对按 build 比较**零处**非降序。
  `preview` 与其他 type 并存的情况无法实测——扫了 16 个产品代码（IIU PCP WS GO RR CL DG TBA PS RD RM DS JCD 及 FL/QA/AI），
  没有一个同时发布 `preview` 和别的 type；「preview 也按 build 交错」是推断。
- 2026-10-08（本次重审）：API `AIR` 37 条，仍全部 `preview`，29 条带 `whatsnew`，最早 261.63.28（2025-12-01）；
  API 里从未出现 `262.991.*`。eap feed 与 API 同为 262.1037.6；nightly feed 262.1054。Toolbox 目录在 13:23 与 13:31 UTC 仍为
  262.834.70。两个 Public Preview 包的 `SUFeedURL` 都是 `eap`（旧文档与 `ToolboxSource` 注释说的 nightly 不成立）。
  产品页撤掉了桌面下载入口，`air.dev/download` 301 到产品页。
