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
- 来源: feed 只给 `releaseNotesLink` → `https://handbrake.fr/appcast/stable.html`（`unstable.html` 逐字节相同）
- 结构化: `changelog pane  web page https://handbrake.fr/appcast/stable.html, no structure`
  （1.11.1、1.11.2、snapshot、1.3.3 四个包都是这一行）
- 该页面是陈旧的：2026-10-08 拉到的 `stable.html` 标题是 **HandBrake 1.11.0**，而 feed 发的是 1.11.2；
  正文只有 Upgrade Notice、一句「View the full release notes on GitHub for 1.11.0」链接和系统要求，
  没有任何变更条目。所以 pane 里看到的是一个说错版本、没有内容的网页。
- 真正的变更说明在 GitHub Release body（`HandBrake/HandBrake`），Markdown，分节清晰：
  `## HandBrake 1.11.2` → `### All platforms` → `#### Video` / `#### Audio` / `#### Subtitles` /
  `#### Build system` / `#### Third-party libraries`，再 `### Linux` / `### Mac` / `### Windows`；
  前面还有一个 `## Upgrade Notice`（含 Windows .NET 运行时说明）。
- 用生产解析器试过（2026-10-08，临时测试，已删）: 把 `api.github.com/repos/HandBrake/HandBrake/releases?per_page=40`
  的真实响应喂给 `StructuredChangelogDecoder.decode(format: .gitHubReleases)`：
  - 不加 `skipSections`: 1.11.2 → 16 条，headings `Upgrade Notice, Video, Audio, Subtitles,
    Build system, Third-party libraries, Linux, Mac, Windows`；前两条是 Windows 的 .NET 下载链接
    （来自 `Upgrade Notice`）。`All platforms` 这一层（只有子标题、没有直属条目）不出现，
    其下的 `Video` 等与 `Mac` 平级。
  - 加 `skipSections: ["Upgrade Notice", "Linux", "Windows"]`: 1.11.2 → 9 条，headings
    `Video, Audio, Subtitles, Build system, Third-party libraries, Mac`；1.11.1 → 2 条，
    headings `Audio, Third-party libraries`（该版 Mac 节为空）。
  - `Updated libraries` 下的嵌套子项（`FFmpeg 8.0.2 …`、`SVT-AV1 4.1.0 …`）不进 items。
  - 结论: 分节保留为 heading，没有被压平。
- 跟随 channel: 否（stable.html 与 unstable.html 相同；snapshot 无 release notes）
- Recipe 状态: **需要**（`.gitHubReleases` ChangelogRecipe，见建议下一步；未实现）

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
- Changelog 窗格显示的是一个停在 1.11.0、没有变更条目的网页（厂商侧 `stable.html` 未更新）。
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

四个包的 `changelog pane` 行相同：`web page https://handbrake.fr/appcast/stable.html, no structure`；
`release history 0 entries`，`deltas 0`，`ChannelBinding <none for this app>`。

## 建议下一步
1. 加结构化 changelog: `/fragile-recipe HandBrake`（ChangelogRecipe，`structuredFormat: .gitHubReleases`，
   source `https://api.github.com/repos/HandBrake/HandBrake/releases?per_page=10`，`mode: .json`，
   `skipSections: ["Upgrade Notice", "Linux", "Windows"]`）。解析结果已在真实响应上试过（见 Changelog 节）。
   每个 release 带十几个资产，`per_page=40` 的响应约 1.3 MB，所以 `per_page` 取小值。
   新家族文件 + `AppRecipeIndex.all` 一行 + fixture 测试 + 重录 `RecipeGoldenTests`。
   Sparkle 源的 changelogURL 仍是 `stable.html`，要确认 recipe 在 pane 的优先序里排在网页之前
   （skill 写的顺序是 recipe → structured → raw → web page）。
2. 一键：第一轮端到端已跑通（1.11.1 → 1.11.2）；第二轮未跑。
3. `CHANNEL_COVERAGE_TODO.md` 的 HandBrake 条目：结论（不需要单独接轨、无独立 bundle id、无 app 内开关）
   成立，但「snapshot 与 stable 同构建」不对——snapshot 是 `master` 的构建，版本串、签名、`SUFeedURL`
   都不同；不需要接轨的真正原因是每个包写死自己的 feed，而通用源读的就是它。同文件里把 HandBrake
   列为「已接的 GitHub releases 型」changelog 也不对：代码里没有任何 `fr.handbrake.HandBrake` 的 recipe。
