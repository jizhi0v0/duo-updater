# HandBrake

## 基本信息
- Bundle ID: `fr.handbrake.HandBrake`（正式版与 snapshot 同一个 id，见 Channel 详情）
- Team ID: `5X9DE89KYV`（`Developer ID Application: I.D.&.A. di Galassi Damiano & C. S.a.s.`；
  1.11.1 / 1.11.2 / 1.3.3 三个正式包相同；snapshot 包是 ad-hoc 签名、无 Team）
- 观测版本: `1.11.2`（`CFBundleVersion` `2026060700`），上一版 `1.11.1`（`2026032200`）；2026-10-08
- 自更新机制: Sparkle 2（HandBrake 自己的 fork，包内 `Sparkle.framework` 短版本
  `2.9.2-11-g5c8f3040`；仓库 `Package.resolved` 记为 `HandBrake/Sparkle` `2.9.2-handbrake`）；
  `SUAllowsAutomaticUpdates = false`
- 分发: handbrake.fr 下载页 / GitHub Releases（`HandBrake/HandBrake`，同一个 dmg）/ Homebrew cask
  `handbrake-app`（`auto_updates: true`，url 即 feed 里的 `rotation.php` 地址）；
  snapshot 在另一个仓库 `HandBrake/HandBrake-snapshots`；无 MAS
- 开源: 是。feed 地址、渠道、版本方案均 settled from source（`HandBrake/HandBrake` `master`，2026-10-08）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（通用源，读包自带 `SUFeedURL`） | —（`auto_updates`，让位） | — | — | — |
| **snapshot** | ✓（同上，包自带 `appcast_unstable` 地址） | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify` 对 1.11.1 / 1.11.2 /
snapshot 三个包实测 winning source 都是 Sparkle）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `fr.handbrake.HandBrake` | 共享 | 包内 `SUFeedURL` = `appcast.arm64.xml`（universal）或 `appcast.x86_64.xml`（老的 Intel-only 包） | 构建期写死的 feed（每个包只认自己那条） | ✓ |
| snapshot / beta | `fr.handbrake.HandBrake` | 共享 | 包内 `SUFeedURL` = `appcast_unstable.<arch>.xml` | 同上 | ✓（跟着包自己的 feed 走） |

settled from source: `make/configure.py` on `master`（`Project._action`）——
`url_appcast = 'https://handbrake.fr/appcast%s%s.xml' % (url_ctype, url_arch)`：

- `url_ctype` 为空，当且仅当构建来自官方仓库、HEAD 恰好是 tag、没加 `--snapshot`、tag 没有
  `-<word>.<n>` 后缀（正式版）；snapshot、开发构建、`1.4.0-beta.1` 这类 beta tag 一律是 `_unstable`。
- `url_arch` 是 `.<arch>`（Mac 才加）。官方正式包是 universal（`x86_64 arm64`），但声明的是
  `appcast.arm64.xml`；1.3.3 这种 Intel-only 老包声明 `appcast.x86_64.xml`。

**没有 app 内渠道开关。** `macosx/Base.lproj/Preferences.xib` 里绑到 `SPUStandardUpdaterController`
的只有 `updater.automaticallyChecksForUpdates`（"Automatically check for updates weekly"）；
`macosx/` 下没有任何 `.m`/`.h` 实现 `feedURLStringForUpdater:` 或 `allowedChannelsForUpdater:`
（grep `SPUUpdater|feedURL|allowedChannels` 零命中，Sparkle 只在 `MainMenu.xib` / `Preferences.xib`
里以 `SPUStandardUpdaterController` 实例出现）。渠道 = 你装的是哪个包，写死在包的 Info.plist 里。

snapshot 的实情（2026-10-08，`HandBrake-snapshots` 的滚动 release `mac`，资产
`HandBrake-20261002155018-174246fbe-master.dmg`）:

- bundle id `fr.handbrake.HandBrake`（与正式版相同）
- `CFBundleShortVersionString` `20261002155018-174246fbe-master`（提交时间-短哈希-分支），
  `CFBundleVersion` `2026100501`（构建日 + `01`；正式版是构建日 + `00`）
- `SUFeedURL` `https://handbrake.fr/appcast_unstable.arm64.xml`
- 签名 `adhoc,runtime`，`TeamIdentifier=not set`（仓库 README 自己写明 snapshot 不做数字签名）
- 无 Homebrew cask（`brew search --cask handbrake` 只有 `handbrake-app`）

`appcast_unstable.arm64.xml` / `appcast_unstable.x86_64.xml` 在 2026-10-08 与对应的正式 feed
**逐字节相同**（`diff` 无输出），都只列 1.11.2。也就是说厂商现在不往 unstable feed 发 snapshot。
（推断，未在 app 里实测：Sparkle 默认按 `sparkle:version` 对 `CFBundleVersion` 比较，snapshot 用户
在 app 内只会在出现「构建号比自己新的正式版」时被提示。）

**duo 是否跟随（实测）:** 跟随。`SparkleAppcastSource` 读的是包自己声明的 `SUFeedURL`，即 app 内
Sparkle 读的同一个地址；snapshot 包实测读 `appcast_unstable.arm64.xml`，构建号 `2026060700` 不比
`2026100501` 新 → up to date。
`channel-verify` 把 snapshot 的 `detected channel` 印成 `stable`（`inferred`），但这个 feed 没有
`<sparkle:channel>` 标签，channel 标签不参与过滤，不影响结果。

和 OBS 的不同：OBS 是同一个包 + app 内偏好 + feed 里每条都带 `<sparkle:channel>`；HandBrake 是
每个包写死自己的 feed、feed 不带任何 channel 标签、没有偏好。不需要 `ChannelBinding`。

## 更新检测
- 源: `SparkleAppcastSource`（通用，无 per-app recipe；`feed-discover` 判 `declared`）
- 端点: `https://handbrake.fr/appcast.arm64.xml`（官方 universal 包声明的地址）；
  `appcast.x86_64.xml`（老 Intel-only 包）；`appcast_unstable.{arm64,x86_64}.xml`（snapshot / beta 包）。
  `appcast.xml`、`appcast.universal.xml`、`appcast_unstable.xml` 均 404。
- feed 形态（2026-10-08，四条 feed 一样）: 1 个 `<item>`；`<sparkle:channel>` 0 条、无标签条目 1 条；
  `<sparkle:deltas>` 无；`phasedRolloutInterval` 无；`hardwareRequirements` 无；
  `minimumSystemVersion` `10.13.0`，无 `maximumSystemVersion`；release notes 只有
  `<sparkle:releaseNotesLink>https://handbrake.fr/appcast/stable.html`（无 `<description>`）；
  enclosure 带 `sparkle:edSignature`，`length` `47978117` 与 GitHub 资产同字节数；
  另有 Windows 用的 `<windows>` / `<windowsHash>` / `<windowsSignature>` 自定义元素。
- 注意事项:
  - x86_64 feed 的 `sparkle:shortVersionString` 是 `1.11.2 x86_64`（arm64 那条是 `1.11.2`）。
    读 x86_64 feed 的老包（1.3.3 实测）在 duo 里显示 `latest 1.11.2 x86_64`——比较走构建号，
    判定正确（UPDATE），只是显示串带了架构后缀。装成 1.11.2 universal 之后改读 arm64 feed，后缀消失。
  - snapshot 的短版本号是时间戳串，duo 只比 `CFBundleVersion`，不受影响。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不适用（没有可消费的） |
| 证据 | 1.11.2 包 `Sparkle.framework/Versions/B/Autoupdate` 的 strings 里有 32 处 `BinaryDelta`/`deltaFrom` | 四条 feed 均无 `<sparkle:deltas>`（2026-10-08）；`channel-verify` 报 `deltas 0` | 若日后发，`VendorAppcastDeltas` + `DeltaApplier` 现成可用 |

- 格式: Sparkle binary delta（客户端能力）；服务端未发
- 阻塞项: 无

## 按 OS / 架构分轨、灰度、自更新器

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 有（Sparkle 二进制含 `phasedRolloutInterval`） | 无（feed 无该元素） | — |
| 按架构 / 按 OS 分轨 | 有（按架构分 feed，构建期写死） | 两条架构 feed 指向同一个 universal dmg；只有 `minimumSystemVersion 10.13.0`，无上限 | 是（读包自带的地址；min 由 `usableItems` 判） |
| 自更新器会不会和我们抢 | `SUAllowsAutomaticUpdates = false`，Sparkle 不会后台静默安装，只弹窗由用户点 | — | 碰撞未实测（端到端第二轮未跑） |

- `LSMinimumSystemVersion`: 1.11.1 / 1.11.2 / snapshot 都是 `10.13.4`；1.3.3 是 `10.11`。

## Changelog
- 来源: feed 只给 `releaseNotesLink` → `https://handbrake.fr/appcast/stable.html`（`unstable.html` 逐字节相同）；
  该页不随版本更新、没有变更条目（实测见「历史与实测」），所以不用它。
- 结构化: ✓ `ChangelogRecipe`（`Recipes/fr-handbrake-HandBrake.swift`）读 GitHub Releases：
  source `https://api.github.com/repos/HandBrake/HandBrake/releases?per_page=10`，`mode: .json`，
  `structuredFormat: .gitHubReleases`，`maxEntries: 10`，`channel` 不设，
  `skipSections: ["Upgrade Notice", "Linux", "Windows"]`。
  `channel-verify HandBrake-1.11.2.dmg`（2026-10-08）的 pane 行:
  `changelog pane  recipe changelog:fr.handbrake.HandBrake:-: 10 entries; newest 1.11.2: 9 items, headings ["Video", "Audio", "Subtitles", "Build system", "Third-party libraries", "Mac"]; first items ["Fixed a crash that happened when doing a", "Fixed a memory leak that happened when d", "Updated the list of supported dithers an"]`
  （加 recipe 之前同一个包是 `changelog pane  web page https://handbrake.fr/appcast/stable.html, no structure`）。
  feed 的 changelogURL 仍是 `stable.html`，pane 照样先取 recipe——上面这行就是证据。
- body 形态: `## Upgrade Notice`（Windows .NET 运行时下载链接）→ `## HandBrake <version>` →
  `### All platforms` → `#### Video` / `#### Audio` / … → `### Linux` / `### Mac` / `### Windows`。
  版本号标题（含数字）和没有直属条目的 `All platforms` 不渲染成 heading；三个 skip 节整节丢掉。
- 版本对应: tag 是裸版本号（`1.11.2`），与包的 `CFBundleShortVersionString` 相同（1.11.2 包实测）。
- 渠道: recipe 不设 channel → 只读 `prerelease: false` 的 release。仓库里唯一的 prerelease 是
  `1.4.0-beta.1`；snapshot 在另一个仓库（`HandBrake-snapshots`），不在这个列表里。
  （推断，未实测：snapshot 包同 bundle id，也会拿到这条 recipe；它的版本串是时间戳，rail 上不会有
  匹配它的条目。）
- 嵌套子项: HandBrake 几乎每版都有一条 `Updated libraries`，库与版本（`FFmpeg 8.0.2 (decoding and
  filters)` 这类）写在它的子项里。`GitHubMarkdownParser` 保留顶层 bullet 下的嵌套子项，每个库是
  `Updated libraries` 之后的一条；1.11.0 的预设说明、1.10.0 的「preserving additional metadata
  including:」同理。计数见「历史与实测」。
- Recipe 状态: ✓

## 一键安装
- 状态: 支持（通用 Sparkle 路径，第一轮端到端 ✓）
- 端到端（2026-10-08，第一轮：未运行）: 1.11.1 (2026032200) → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 47978117`，34 s。之后版本 1.11.2 (2026060700)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `5X9DE89KYV`；和厂商新版包里的 app 逐文件比对（SHA-256 + 符号链接 + 目录，793 行）完全一致。整包下载（feed 没有 delta）。第二轮（运行中、app 自己的更新器已暂存）未跑。
- 格式: dmg（universal `x86_64 arm64`），feed enclosure
  `https://handbrake.fr/rotation.php?file=HandBrake-1.11.2.dmg&update=true` → 302 →
  `github.com/HandBrake/HandBrake/releases/download//1.11.2/HandBrake-1.11.2.dmg`（GitHub 资产）
- 包验（2026-10-08）: 1.11.1 与 1.11.2 Team 均为 `5X9DE89KYV`，`codesign --verify --deep --strict` 通过，
  `spctl` `Notarized Developer ID`；`check-bundle.sh` 未列出任何嵌套 app（`Contents/Library/LoginItems`、
  `Contents/Helpers` 都没有）。包里只有 `HandBrakeXPCService{,2,3,4}.xpc`（按需启动的编码 XPC）和
  Sparkle 自带的 `Updater.app` / XPC，都不是常驻 helper。
- 校验: feed 带 `sparkle:edSignature`（`SUPublicEDKey` `aeDqvDkd…GP+Vbg=`，三个正式包相同）；
  无 SHA 摘要字段。GitHub 资产 `digest` `sha256:4afe27aa…5de9d7` 与实际下载的
  `shasum -a 256` 相等，大小 `47978117` 与 feed `length` 相等。
- **读的是**: 人人可手动下载的 GA（feed 单条目、无 `phasedRolloutInterval`；同一个 dmg 挂在
  handbrake.fr 下载页与 GitHub Release 上）
- 阻塞: 无已知。snapshot 副本是 ad-hoc 签名、没有 Team：若将来正式版的构建号超过它而被提示更新，
  `SignatureVerifier` 的 Team 路线会以 `noTeamIdentifier(which: "installed")` 拒装
  （读代码得出，未实测）。

## 已知问题
- 老 Intel-only 包读 x86_64 feed 时，最新版本显示为 `1.11.2 x86_64`（比较正确，仅显示）。
- snapshot 与正式版同 bundle id；duo 与 app 内 Sparkle 一样只看包自己的 feed，snapshot 用户在
  正式版构建号赶上之前看不到更新——这是厂商的设计，不是缺口。

## 如何复验

```
# 源码（HandBrake/HandBrake master，2026-10-08）
#   make/configure.py   url_appcast = 'https://handbrake.fr/appcast%s%s.xml' % (url_ctype,url_arch)
#   macosx/Info.plist.m4  SUFeedURL = __HB_url_appcast；CFBundleIdentifier = fr.handbrake.${PRODUCT_NAME}
#   macosx/Base.lproj/Preferences.xib  唯一的 updater 绑定：updater.automaticallyChecksForUpdates
curl -sS "https://handbrake.fr/appcast.arm64.xml"            # 200，1 item，1.11.2 / 2026060700
curl -sS "https://handbrake.fr/appcast_unstable.arm64.xml"   # 200，与上一条 diff 为空
swift run --package-path application-test feed-discover HandBrake-1.11.2.dmg
#   → declared  https://handbrake.fr/appcast.arm64.xml
swift run --package-path application-test channel-verify <pkg>
.claude/skills/coverage-discovery/scripts/check-bundle.sh <pkg>
```

| 包（2026-10-08 下载） | 短版本 / 构建号 | `SUFeedURL` | Team | winning source | latest | status |
|---|---|---|---|---|---|---|
| `HandBrake-1.11.2.dmg`（GitHub `1.11.2`） | `1.11.2` / `2026060700` | `appcast.arm64.xml` | `5X9DE89KYV` | Sparkle | `1.11.2` | up to date |
| `HandBrake-1.11.1.dmg`（GitHub `1.11.1`） | `1.11.1` / `2026032200` | `appcast.arm64.xml` | `5X9DE89KYV` | Sparkle | `1.11.2` | UPDATE → 1.11.2 |
| `HandBrake-1.3.3.dmg`（GitHub `1.3.3`，Intel-only） | `1.3.3` / `2020061300` | `appcast.x86_64.xml` | `5X9DE89KYV` | Sparkle | `1.11.2 x86_64` | UPDATE → 1.11.2 x86_64 |
| `HandBrake-20261002155018-174246fbe-master.dmg`（`HandBrake-snapshots` `mac`） | `20261002155018-174246fbe-master` / `2026100501` | `appcast_unstable.arm64.xml` | 无（ad-hoc） | Sparkle | `1.11.2` | up to date |

上表四个包的 `changelog pane` 行（加 recipe 之前）相同：`web page https://handbrake.fr/appcast/stable.html, no structure`；
`release history 0 entries`，`deltas 0`，`ChannelBinding <none for this app>`。加 recipe 之后 1.11.2 包的那一行见 Changelog 节。

```
# changelog recipe
curl -sS "https://api.github.com/repos/HandBrake/HandBrake/releases?per_page=10"   # 10 个 release，无 prerelease
swift test --package-path DuoUpdaterCore --filter HandBrakeChangelogRecipeTests
swift run --package-path application-test channel-verify HandBrake-1.11.2.dmg     # 看 changelog pane 行
```

## 建议下一步
1. 结构化 changelog 已接，`Updated libraries` 下的库名与版本也显示（见 Changelog 节）。
2. 一键：第一轮端到端已跑通（1.11.1 → 1.11.2）；第二轮未跑。
3. `CHANNEL_COVERAGE_TODO.md` 的 HandBrake 条目：结论（不需要单独接轨、无独立 bundle id、无 app 内开关）
   成立，但「snapshot 与 stable 同构建」不对——snapshot 是 `master` 的构建，版本串、签名、`SUFeedURL`
   都不同；不需要接轨的真正原因是每个包写死自己的 feed，而通用源读的就是它。同文件里把 HandBrake
   列为「已接的 GitHub releases 型」changelog，在本次加 recipe 之前不成立，现在成立。

## 历史与实测

### Recipes/fr-handbrake-HandBrake.swift — ChangelogRecipe（2026-10-08）

- `stable.html` 为什么不用: 2026-10-08 拉到的 `https://handbrake.fr/appcast/stable.html` 标题是
  **HandBrake 1.11.0**，而 feed 发的是 1.11.2；正文只有 Upgrade Notice、一句「View the full release
  notes on GitHub for 1.11.0」链接和系统要求，没有变更条目。`unstable.html` 与它逐字节相同。
- 响应大小: `releases?per_page=10` 404,003 字节（每个 release 22–28 个资产）；`per_page=100` 一页就是
  全部 54 个 release，1,591,386 字节。资产列表占大头，所以 `per_page=10`。
- 全仓库 54 个 release 里 `prerelease: true` 只有 `1.4.0-beta.1`（2020-11-11），`draft` 0 个；
  最新 10 个（1.11.2 … 1.8.2）全是正式版。tag 都是裸版本号。
- 生产解析器（临时 Swift 测试，经 `ChangelogService.parse` 走注册的 recipe，已删）对 `per_page=10`
  真实响应: 10 条，`1.11.2, 1.11.1, 1.11.0, 1.10.2, 1.10.1, 1.10.0, 1.9.2, 1.9.1, 1.9.0, 1.8.2`；
  items 依次 9 / 2 / 23 / 3 / 4 / 25 / 2 / 7 / 16 / 4。
  - 1.11.2: headings `Video, Audio, Subtitles, Build system, Third-party libraries, Mac`。
  - 1.11.1: headings `Audio, Third-party libraries`（这一版没有 `### Mac` 节，不是空节）。
  - 不加 `skipSections`（re-audit 时用 `per_page=40` 试的）: 1.11.2 → 16 条，多出 `Upgrade Notice` /
    `Linux` / `Windows` 三个 heading，前两条是 Windows 的 .NET 下载链接。
- 被丢掉的嵌套子项（同一份 10 个 release，跳过三个 skip 节后按缩进 bullet 计）: 共 73 行，其中 57 行在
  `Updated libraries` 下（10 个 release 里 9 个有这一条）；其余是 1.11.0 预设说明 12 行、1.10.0
  「preserving additional metadata including:」下 3 行、1.9.0「Added new translations」下 1 行。
  1.11.2 丢的两行是 `FFmpeg 8.0.2 (decoding and filters)`、`SVT-AV1 4.1.0 (AV1 video encoding)`。
  解析器改为保留顶层 bullet 下的嵌套子项之后（`Changelog.parserGeneration` 10）：这两行跟在
  `Updated libraries` 之后，1.11.2 从 9 条变 11 条，1.11.1 从 2 条变 4 条（`HandBrakeChangelogRecipeTests`）。
- `channel-verify`（GitHub `1.11.2` 资产 `HandBrake-1.11.2.dmg`，47,978,117 字节，
  sha256 `4afe27aa…5de9d7`）: 短版本 `1.11.2`，与 tag 相同。`changelog pane` 行，前（index 里临时去掉
  这个家族）: `web page https://handbrake.fr/appcast/stable.html, no structure`；后: `recipe
  changelog:fr.handbrake.HandBrake:-: 10 entries; newest 1.11.2: 9 items, headings [...]`（全文见 Changelog 节）。
