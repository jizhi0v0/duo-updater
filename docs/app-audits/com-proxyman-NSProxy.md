# Proxyman

## 基本信息
- Bundle ID: `com.proxyman.NSProxy`
- Team ID: `3X57WP8E8V`（证书名 `Developer ID Application: TablePlus Inc`，与 TablePlus 同一个 Team；26.0.0 与 26.0.1 两个包相同）
- 观测版本: 26.0.1（`CFBundleVersion` 260001，feed 与 GitHub 最新）；上一版 26.0.0（260000）。2026-10-08 观测
- 自更新机制: Sparkle 1.27.0（`SUUpdater`），`SUFeedURL` 固定，`SUEnableAutomaticChecks` = false

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | 退让（`auto_updates`） | — | ○（只作 changelog 源） | — |
| **beta**     | —       | —        | —   | —      | —           |
| **HTTP/2 Beta（一次性特性构建）** | ✗（与 stable 无法区分，见下） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify` 实测 `winning source Sparkle`）

- Mac App Store: 没有 Mac 版。iTunes lookup `id1551292695` 是 iOS 版（`com.nsproxy.NSProxy-iOS`）。
- Setapp 版是另一个 bundle id：`com.proxyman.NSProxy-setapp`，出现在 helper 的 `SMAuthorizedClients` 里。更新由 Setapp 管，本文不覆盖。
- Homebrew cask `proxyman`：`version 26.0.1,260001`，`auto_updates: true`，`depends_on macos >= 14`。按 `HomebrewCaskSource` 的规则会退让，落到 Sparkle。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.proxyman.NSProxy` | — | — | 唯一 feed，唯一 item，无 `<sparkle:channel>` | ✓ |
| HTTP/2 Beta | `com.proxyman.NSProxy` | 共享 | 无 | 不是更新轨道：app 设置里的按钮从 `/v1/apps/osx/http2-beta` 拿一个 dmg 链接，装上后仍走同一个 stable feed | ✗（不需要） |

只有一条更新轨道。证据：

- feed `https://proxyman.com/osx/version.xml` 只有 1 个 `<item>`（26.0.1），未打 `<sparkle:channel>` 标签。全文 0 处 `sparkle:channel`、`phasedRollout`、`maximumSystemVersion`、`hardwareRequirements`。
- 26.0.1 的 `Info.plist` 里 `SUFeedURL` 写死。用 `dyld_info -objc` 看主二进制：`_TtC8Proxyman14SparkleUpdater : NSObject <SUUpdaterDelegate>` 只实现了 `init` 和 `.cxx_destruct`，没有实现 `feedURLStringForUpdater:`、`feedParametersForUpdater:sendingSystemProfile:`、`bestValidUpdateInAppcast:forUpdater:`。也就是说，app 不在运行时换 feed，也不按偏好筛 item。Sparkle 1.x 本身没有 `allowedChannels`。
- 二进制里没有第二个 appcast 地址。`strings` 中带 proxyman 的 URL 只有文档、授权、workspace 和埋点几类。和 beta 相关的只有 `getHTTP2Beta`、`HTTP2BetaInfo`、`/v1/apps/osx/http2-beta` 和设置页文案 "Download the HTTP/2 beta in Settings."。TablePlus 用 `X-Tiny-Beta-Update` 请求头切 beta，这个头在 Proxyman 的二进制里出现 0 次。
- 用三种 UA 拉同一个 feed（浏览器 UA、`Proxyman/26.0.0 Sparkle/1.27.0`、`Proxyman/6.10.0 Sparkle/1.27.0`），三份响应 sha256 完全一致（`4d2f12c5…`）。没看到按 UA 或版本分流。

**HTTP/2 Beta。** 2026-10-08 `GET https://proxyman.com/v1/apps/osx/http2-beta` 返回 200，内容为
`{"download_url":"https://assets.proxyman.com/beta/Proxyman_6.17.0_HTTP_2_Beta.dmg","message":"HTTP/2 Beta for macOS"}`。
下载这个包（63352167 字节，签名时间 2026-09-07）和 GitHub 上 stable 6.17.0 的包对比：

| | HTTP/2 Beta 包 | stable 6.17.0 包 |
|---|---|---|
| dmg sha256 | `f8f658d3…` | `533e622c…` |
| bundle id | `com.proxyman.NSProxy` | `com.proxyman.NSProxy` |
| 版本 | 6.17.0 / 61700 | 6.17.0 / 61700 |
| `SUFeedURL` | `https://proxyman.com/osx/version.xml` | 同左 |
| `LSMinimumSystemVersion` | 13.0 | 13.0 |
| Team | `3X57WP8E8V` | `3X57WP8E8V` |

两个包的 `Info.plist` 键集合完全一样，只有 `DT*`/`BuildMachineOSBuild` 这类构建机字段不同。从外部区分不了它们（属于 Pattern D）。不过也没必要区分：beta 包读的是同一个 stable feed，Proxyman 自己的 Sparkle 给它推的也是 26.0.1。HTTP/2 已在 26.0.0 进入 stable（26.0.0 的发布说明写了 "Proxyman can capture HTTP/2 traffic"），这个端点给出的 6.17.0 构建反而比 stable 旧。`channel-verify` 对这个 beta 包的结果是 `UPDATE → 26.0.1`，和厂商自己的更新器一致。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover` 结论为 `declared`）
- 端点: `https://proxyman.com/osx/version.xml`（Cloudflare，200，`application/xml`，264051 字节）
- feed 形状: 只有 1 个 item，没有历史 item。enclosure 是 `https://assets.proxyman.com/260001/Proxyman_26.0.1.dmg`，`length` 63757299，同时带 `sparkle:edSignature` 和 `sparkle:dsaSignature`
- 注意事项:
  - **OS 下限写错了命名空间，值也是旧的。** item 里是不带前缀的 `<minimumSystemVersion>12.0</minimumSystemVersion>`，而包里实际声明 `LSMinimumSystemVersion` = 14.0（26.0.0 与 26.0.1 都是；6.17.0 是 13.0）。`SparkleAppcastParser.sparkleLocalName` 只认 Sparkle 命名空间或 `sparkle:` 前缀，所以这个元素不会被读（读代码得出，未单测）。结果是：macOS 13 上的 6.17.0 会被提示 26.0.1，Proxyman 自己的 Sparkle 1 同样会提示。安装时由 `SignatureVerifier` 的 Gate 6 读下载包的 `LSMinimumSystemVersion` 拦下。
  - **Release Log 拿不到日期。** `pubDate` 是 `Sun, 27 Sep 2026 16:09:46 GMT+0200`，`channel-verify` 实测 `release history 0 entries`。原因已用临时 Swift 脚本验证：`ReleaseDate.rfc822Formatters` 里的 `EEE, dd MMM yyyy HH:mm:ss Z` 和 `… zzz` 解析这个字符串都返回 nil。
  - GitHub `ProxymanApp/Proxyman` 也发 dmg（26.0.1 资产 sha256 `09bc0385…` = feed 下载 = cask `sha256`），但 Sparkle 排在前面。221 个 release 里只有 2018 年的 `1.0` 标了 prerelease，而且没有资产。

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不适用（没有可消费的） |
| 证据 | `Sparkle.framework` 1.27.0 的 `Autoupdate` 里有 `SUBinaryDeltaUnarchiver` / `SUBinaryDeltaCommon.m`，`Sparkle` 里有 `sparkle:deltas` / `sparkle:deltaFrom` | 2026-10-08 feed：0 个 `<sparkle:deltas>`（`channel-verify`：`deltas 0`） | 若以后发 delta，`SparkleAppcastSource` + `DeltaApplier` 是现成的 |

- 格式: Sparkle binary delta（客户端能力；服务端未发）
- 阻塞项: 无

按设备灰度：feed 里没有 `phasedRolloutInterval`，三种 UA 拉到的内容逐字节相同。按架构/OS 分轨：包是 universal（`x86_64 arm64`），feed 不分架构，OS 下限的问题见上。自更新器会不会和我们抢：见「一键安装」。

## Changelog
- 来源: Sparkle inline（item 的 `<description>`，HTML）
- 结构化: `changelog pane  raw inline notes, 203022 chars, no structure`（26.0.0、26.0.1、HTTP/2 Beta 三个包结果一样）
  - 原因（实测）：唯一 item 的 `<description>` 是**累积**的发布说明，从 26.0.1 一路写到 1.8.0，共 132 个 `<h2>… Proxyman X.Y.Z` 版本标题、203097 字符。`<li>` 开标签 1798 个、`</li>` 1793 个，不配对，`AppcastHTMLChangelogParser.isStructured` 因此返回 false，pane 退回原始 HTML。就算配对了，这条路径也会把 132 个版本压成一个 26.0.1 条目，同样不能用。
- 跟随 channel: 不适用（只有一条轨道）
- Recipe 状态: **需要**。`ProxymanApp/Proxyman` 的 GitHub release 正文是干净的 Markdown，每版一个 release，标题稳定：26.0.1 是 `## Improvements` / `## Bug Fixes`；26.0.0 到 6.6.0 是 `## Features` / `## Improvements` / `## Bug Fixes` / `## Screenshots`。tag 就是版本号本身（`26.0.1`）。

## 一键安装
- 状态: 支持（通用 Sparkle 路径，第一轮端到端 ✓）
- 端到端（2026-10-08，第一轮：未运行）: 26.0.0 (260000) → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 63757299`，27 s。之后版本 26.0.1 (260001)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `3X57WP8E8V`；和厂商新版包里的 app 逐文件比对（SHA-256 + 符号链接 + 目录，2003 行）完全一致。没启动过 app，所以 `/Library/PrivilegedHelperTools` 里没有 helper，helper 与新版的关系没测到。第二轮（运行中、app 自己的更新器已暂存）未跑。
- 格式: dmg（`Proxyman.app` 加一个 `/Applications` 软链）
- 校验: Sparkle 路径用 `sparkle:edSignature`（`SUPublicEDKey` = `moo+qhr/…`，两个版本相同）。feed 没有单独的摘要字段。补充一项交叉核对：feed 下载的 dmg sha256 `09bc0385…` 和 GitHub 资产 `digest`、cask `sha256` 三者一致，大小 63757299 也等于 feed 的 `length`
- **读的是**: 人人可手动下载的 GA。feed 只有一个 item，同一个 dmg 也挂在 GitHub Releases 和 cask 上，不存在按设备分配
- 签名: 26.0.0、26.0.1 都是 `TeamIdentifier=3X57WP8E8V`，`codesign --verify --deep --strict` 退出码 0，`spctl` 结果 `Notarized Developer ID`
- 嵌套组件（`check-bundle.sh` 没找到嵌套 `.app`；用 `ls Contents/` 补查）:
  - **特权 helper `Contents/Library/LaunchServices/com.proxyman.NSProxy.HelperTool`**，用 SMJobBless 安装。内嵌 launchd plist 只有 `MachServices` 和 `AssociatedBundleIdentifiers`，没有 `RunAtLoad`/`KeepAlive`，按需拉起。生效的是 app 拷到 `/Library/PrivilegedHelperTools/` 的那份副本，换 bundle 不会动它。26.0.0 和 26.0.1 里的 helper 都是 `PMHelperToolVersion` 1.7.0 / `CFBundleVersion` 170，二进制 sha256 不同（重新构建/签名），声明的版本没变。所以从 26.0.0 换到 26.0.1，helper 不会出现「新 app 配旧 helper」的版本差。helper 版本以后真变了怎么办，取决于 app 启动时会不会比对版本、重新 bless（会弹管理员授权），这一点未验证。不过 Proxyman 自己的 Sparkle 也只换 bundle、不碰 helper，一键在这点上和厂商路径一样，不构成阻塞。
  - `Contents/MacOS/mcp-server`：由外部 MCP 客户端以 stdio 子进程方式启动。换包时若正有客户端连着，它会继续跑旧代码，直到客户端重启。`proxyman-cli` 是一次性命令，cask 会把它软链到 `bin`，换包后链接路径不变。
- 自更新器: Sparkle 1.27.0 的 `Autoupdate` 在 app 退出时安装已暂存的更新。`SUEnableAutomaticChecks` 默认 false，用户可以在设置里打开。需要按 Phase 4 第二轮验证会不会和我们抢
- 阻塞: 无已知阻塞，待端到端

## 已知问题
- Changelog 只能显示 203 KB 原始 HTML（132 个版本混在一个条目里），见上。
- Release Log 没有日期：`pubDate` 是 `GMT+0200` 写法，现有 RFC822 formatter 不认。
- feed 的 OS 下限（不带前缀、值为 12.0）不会被读，也和包里的 14.0 对不上。macOS 13 上的旧版会被提示 26.x，到安装闸才会被拦。
- 旧版本审计（2026-06-04）只核了身份，结论是「No code change」。本次重审推翻的部分：changelog 实际是未结构化的原始 HTML，Release Log 没有日期，一键的 helper 情况此前没写。

## 建议下一步
1. 加 changelog: `/fragile-recipe Proxyman`（ChangelogRecipe），照 `pro-betterdisplay-BetterDisplay.swift` 写：
   `source: https://api.github.com/repos/ProxymanApp/Proxyman/releases?per_page=40`、`mode: .json`、
   `structuredFormat: .gitHubReleases`、`channel: .stable`、`maxEntries: 15`。
   `## Screenshots` 一节里只有图片，要不要用 `skipSections: ["Screenshots"]`，先看 `GitHubMarkdownParser`
   在真实正文上渲染出什么再定。做完后 `channel-verify` 的 `changelog pane` 应该显示为 `recipe …`，并保留
   `Features`/`Improvements`/`Bug Fixes` 这几个标题。
2. Release Log 日期: 在 `ReleaseDate.rfc822Formatters` 加一个能解析 `EEE, dd MMM yyyy HH:mm:ss 'GMT'Z`
   （或等价写法）的 formatter，并用 `Sun, 27 Sep 2026 16:09:46 GMT+0200` 写单测。这会影响所有 feed，属通用修复，
   不放在 Proxyman 的 recipe 里做。
3. 一键端到端: 由协调会话按 Phase 4 跑两轮（26.0.0 → 26.0.1，Sparkle 路线），重点看 helper 和自更新器有没有冲突。
4. Channel: 不需要 binding。HTTP/2 Beta 是一次性构建，和 stable 无法区分，也不另有 feed。`CHANNEL_COVERAGE_TODO.md`
   里「无 beta 渠道」那一行应改为「有一次性 HTTP/2 Beta 构建（同 id、同版本、同 feed），不构成轨道」。

## 如何复验
```
# feed
curl -sS -A "<browser UA>" "https://proxyman.com/osx/version.xml" -o feed.xml   # 200, 264051 B
#   → 1 item, 0 <sparkle:channel>, 0 deltas, no phasedRolloutInterval,
#     unprefixed <minimumSystemVersion>12.0</minimumSystemVersion>, pubDate "Sun, 27 Sep 2026 16:09:46 GMT+0200"

# packages (newest from the feed enclosure, previous from GitHub Releases)
curl -sSL -o Proxyman_26.0.1.dmg "https://assets.proxyman.com/260001/Proxyman_26.0.1.dmg"
curl -sSL -o Proxyman_26.0.0.dmg "https://github.com/ProxymanApp/Proxyman/releases/download/26.0.0/Proxyman_26.0.0.dmg"
shasum -a 256 *.dmg
#   09bc03852f524549f0f46b1294f33fb01ee1003af0c720f9ac54ac26a4163706  Proxyman_26.0.1.dmg
#   ae4a395f78afaa01f34515ae678ef8ca20fe35c124944279e5989382ec048840  Proxyman_26.0.0.dmg

swift run --package-path application-test feed-discover Proxyman_26.0.1.dmg
#   → declared  https://proxyman.com/osx/version.xml
swift run --package-path application-test channel-verify Proxyman_26.0.0.dmg
swift run --package-path application-test channel-verify Proxyman_26.0.1.dmg
swift run --package-path application-test channel-verify Proxyman_6.17.0_HTTP_2_Beta.dmg
.claude/skills/coverage-discovery/scripts/check-bundle.sh Proxyman_26.0.0.dmg Proxyman_26.0.1.dmg

# helper (dmg mounted with hdiutil attach -nobrowse -readonly -noautoopen)
launchctl plist __TEXT,__info_plist   <mnt>/Proxyman.app/Contents/Library/LaunchServices/com.proxyman.NSProxy.HelperTool
launchctl plist __TEXT,__launchd_plist <mnt>/Proxyman.app/Contents/Library/LaunchServices/com.proxyman.NSProxy.HelperTool
dyld_info -arch arm64 -objc <mnt>/Proxyman.app/Contents/MacOS/Proxyman | grep -A3 SparkleUpdater
```

| 包 | bundle id | 版本 | Team | detected channel | winning source | status | changelog pane |
|---|---|---|---|---|---|---|---|
| 26.0.0（上一版） | `com.proxyman.NSProxy` | 26.0.0 / 260000 | `3X57WP8E8V` | stable | Sparkle | `UPDATE → 26.0.1` | `raw inline notes, 203022 chars, no structure` |
| 26.0.1（最新） | `com.proxyman.NSProxy` | 26.0.1 / 260001 | `3X57WP8E8V` | stable | Sparkle | `up to date` | 同上 |
| 6.17.0 HTTP/2 Beta | `com.proxyman.NSProxy` | 6.17.0 / 61700 | `3X57WP8E8V` | stable | Sparkle | `UPDATE → 26.0.1` | 同上 |

三个包的 `channel-verify` 都输出 `ChannelBinding <none for this app>`、`release history 0 entries`、`deltas 0`。
`check-bundle.sh`：两个包都是 `archs=x86_64 arm64`，`codesign-verify-exit=0`，`spctl source=Notarized Developer ID`，无嵌套 `.app`。
helper 1.7.0 / 170（两版相同），launchd plist：`MachServices` + `AssociatedBundleIdentifiers`（`com.proxyman.NSProxy`、`com.proxyman.NSProxy-setapp`）。
