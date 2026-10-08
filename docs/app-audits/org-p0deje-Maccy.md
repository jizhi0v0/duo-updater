# Maccy

## 基本信息
- Bundle ID: `org.p0deje.Maccy`（直装版与 Mac App Store 版同一个 id，见下）
- Team ID: `MN3X4648SC`（2.7.0 与 2.7.1 两个真包一致，2026-10-08 `codesign -dvv`）
- 观测版本: 2.7.1（`CFBundleVersion` 62，2026-10-08 最新）；上一版 2.7.0（61）
- 自更新机制: Sparkle 2（包内 Sparkle.framework 2.6.4，build 2039.1）
- 分发: GitHub Releases（`p0deje/Maccy`，资产 `Maccy.app.zip`）/ Homebrew cask `maccy`
  （`auto_updates: true`，url 指向同一个 GitHub zip）/ Mac App Store（trackId `1527619437`，付费）
- 开源: 是。下面的渠道、feed 生成方式均读自仓库源码（`master` 分支），不是从 feed 推断的

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让给 Sparkle） | ✓（仅检测，代码路径，未在真实 MAS 副本上实测） | —（Sparkle 先应答，无 rule） | — |
| **beta**     | —（当前无此轨） | — | — | —（仅 2024 年的 2.0.0 beta，见下） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 直装副本是 **Sparkle**
（`channel-verify` 实测 winning source `Sparkle`）；MAS 副本是 **App Store**（代码路径，见「MAS 副本」）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.p0deje.Maccy` | — | — | feed 单条、无 `<sparkle:channel>` | ✓ |

**只有一条轨。** settled from source（`master`，2026-10-08）:

- `Maccy/SoftwareUpdater.swift`: `SPUStandardUpdaterController(startingUpdater: true,
  updaterDelegate: nil, userDriverDelegate: nil)`。没有 updater delegate，所以没有
  `allowedChannels(for:)`，也没有 `feedURLString(for:)` 换 feed。
- `Maccy/Settings/GeneralSettingsPane.swift`: 更新相关只有「自动检查更新」开关
  （`automaticallyChecksForUpdates`）和「立即检查」按钮，没有 beta / prerelease 开关。
- `Maccy/Info.plist`: 只声明 `SUFeedURL`、`SUEnableDownloaderService`、
  `SUEnableInstallerLauncherService`；没有 `SUPublicEDKey`，也没有别的 feed 地址。
- 仓库里唯一的 feed 是根目录 `appcast.xml`（递归树 `truncated=false`，按
  `appcast|updat|sparkle|release|feed` 过滤只命中 `appcast.xml`、`Maccy/SoftwareUpdater.swift`、`Maccy/Info.plist`）。

**GitHub prerelease**：release 列表里有 15 个 prerelease，`2.0.0.beta.1` – `2.0.0.beta.15`
（2024-07-24 – 2024-09-10），之后再没有。它们从没进过 feed：`appcast.xml` 的提交历史在
2024-07-08（Release 1.0.0）和 2024-09-07（Release 2.0.0）之间没有任何提交；这两个提交时的
feed 都是 1 条 item、0 个 `<sparkle:channel>`。也就是说当年的 beta 只能手动下载，应用内
没有跟 beta 的途径。这不是漏接的轨，是一次性的公测，现在不存在。

`ChannelBinding.resolver(for:)` 里没有这个 id 的 binding，也不需要：feed 的唯一一条是
untagged 的默认轨，stable 副本能匹配（`channel-verify` 对 2.7.0 实测 `UPDATE → 2.7.1`）。

## MAS 副本
- iTunes lookup `bundleId=org.p0deje.Maccy`（2026-10-08）: 1 条，trackId `1527619437`，
  `bundleId` `org.p0deje.Maccy`，version `2.7.1`，`currentVersionReleaseDate`
  `2026-08-11T15:23:51Z`（比 GitHub 晚一天），`minimumOsVersion` `14.0`，付费。
- 和直装版**同一个 bundle id**，靠收据区分：`InstalledApp.isMASApp` 为真的副本，
  `UpdateChecker` 只交给 `answersAppStoreCopies == true` 的源（目前只有 `MacAppStoreSource`），
  Sparkle / GitHub / VendorProbe 一律跳过，即使 MAS 包里也带 `SUFeedURL`。
  `SourceStorePolicyTests.aStoreCopyIsNotOfferedByANonStoreSource` 用的正是「MAS 副本 +
  有 `sparkleFeedURL`」这种形状。直装包里没有 `_MASReceipt`（2.7.0 / 2.7.1 的 `Contents/`
  实测只有 `CodeResources Frameworks Info.plist MacOS PkgInfo Resources _CodeSignature`），
  `MacAppStoreSource` 对它返回 nil，于是落到 Sparkle。
- 没拿到真实的 MAS 包（付费、DRM 绑定 Apple ID），所以 MAS 副本是否带 `SUFeedURL`、
  走 App Store 源的结果，都**没有在真包上验证**；上面是读代码加现有单测得出的。
- 一键：MAS 副本由 App Store 自己更新，不走 duo 的安装器。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://raw.githubusercontent.com/p0deje/Maccy/master/appcast.xml`（2.7.0 / 2.7.1 两个包的 `SUFeedURL` 一致；2026-10-08 HTTP 200）
- feed 形状（2026-10-08，1910 字节）:

  | 项 | 值 |
  |---|---|
  | `<item>` 数 | 1（只保留最新一版，每次发版整份覆盖） |
  | `<sparkle:channel>` | 0 条，唯一一条 untagged |
  | `<sparkle:deltas>` | 无 |
  | `phasedRolloutInterval` / `criticalUpdate` / `minimumAutoupdateVersion` | 无 |
  | `sparkle:minimumSystemVersion` | `14.0`（= 两个包的 `LSMinimumSystemVersion`） |
  | `maximumSystemVersion` / `hardwareRequirements` | 无；包是 universal（`x86_64 arm64`） |
  | `sparkle:edSignature` | 无（包里也没有 `SUPublicEDKey`） |
  | enclosure | `.../releases/download/2.7.1/Maccy.app.zip`，`sparkle:version="62"`，`sparkle:shortVersionString="2.7.1"`，`length="0"` |
  | release notes | `<description>` 里的 HTML `<ul>`（CDATA，12 条 `<li>`） |
  | `<pubDate>` | `2026-08-10`（只有日期，非 RFC 822；`SparkleAppcastSource` 按 vendor day 处理） |
  | 外链 | `<releaseNotesLink>`，**没有 `sparkle:` 前缀** |

- 注意事项:
  - 无前缀的 `<releaseNotesLink>` 两边都不认：Sparkle 2.6.4 只认 `sparkle:releaseNotesLink`
    （`SUConstants.m`：`SUAppcastElementReleaseNotesLink = @"sparkle:releaseNotesLink"`），
    `SparkleAppcastParser` 也只把 Sparkle 命名空间或 `sparkle:` 前缀的元素当 Sparkle 词汇。
    所以 `channel-verify` 显示 `changelogURL <nil>`。不影响检测和结构化 changelog（正文是 inline 的），
    只是行上没有「在网页上看」的链接。
  - `length="0"`：只喂给 `downloadSize`（批量安装排序），不参与校验。
  - 版本方案：feed 的 `sparkle:version` = 包的 `CFBundleVersion`（62），`shortVersionString` = 包的
    `CFBundleShortVersionString`（2.7.1），两边一致，无陷阱。
  - feed 只有一条：从任何旧版看都是「最新一版」，不存在中间版本可选，也没有发布历史可回看（`release history 1 entries`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 不能（没东西可消费） |
| 证据 | 包内 `Sparkle.framework/Versions/B/Autoupdate` 的 strings 有 10 处 `BinaryDelta` / `SUBinaryDelta`（Sparkle 2.6.4） | 2026-10-08 feed 无 `<sparkle:deltas>`；`channel-verify` 显示 `deltas 0` | 若将来发 Sparkle delta，`DeltaApplier` + `VendorAppcastDeltas` 现成可用 |

- 格式: Sparkle binary delta（客户端能力）；服务端没发
- 阻塞项: 无

## 按 OS 分轨 / 灰度 / 自更新器
- OS: feed 只有下限 `14.0`，与包一致；无上限、无分架构资产。
- 灰度: feed 无 `phasedRolloutInterval`，人人拿到同一版。
- 自更新器: Maccy 自己的 Sparkle 会和我们并存（「自动检查更新」开关由用户控制），属一般 Sparkle app 的常规情况；端到端的「运行中 + 自更新器已暂存」一轮由协调会话执行。

## Changelog
- 来源: Sparkle inline（`<description>` 里的 HTML 列表）
- 结构化（2026-10-08，`channel-verify` 的 `changelog pane` 行，原文）:
  `source structured: 1 entries; newest 2.7.1: 12 items, headings []; first items ["Updated app icon for Liquid Glass.", "Increased the minimum popup height to 3 ", "Enabled Portuguese translation."]`
- `headings []` 是如实的，不是被压平：feed 里的 `<ul>` 本来就没有分节；同版本的 GitHub release
  正文（2026-10-08 读取）也是 12 条平铺的 `- ...`，没有标题。
- 只有 1 个条目（feed 只留最新一版）。
- 跟随 channel: 不适用（只有一条轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: 需要验证（路由与闸已就绪，端到端未跑）
- 端到端: 未跑（本轮未执行，原因与 app 本身无关）
- 预期路由: `SparkleInstaller`（`result.remote.sourceName == "Sparkle"`），zip 归档。
  因为包里没有 `SUPublicEDKey`、feed 里也没有 `sparkle:edSignature`，走的是无密钥分支
  （与 Fork 同）：跳过 EdDSA，由代码签名有效 + Team ID 相同 + bundle id 相同这道闸兜底，
  验不过即不装。zip 不进 `InstallCoordinator.verifyInstallerDownload` 那条「Sparkle 必须有 EdDSA」的 pkg 路径。
- 格式: zip（`Maccy.app.zip`，解出单个 `Maccy.app`）
- 校验: feed 不带摘要（无 `edSignature`，`length="0"`）。GitHub 资产自带 `digest`，2026-10-08 实测
  与下载一致：2.7.1 `sha256:f388aee34de09a0c7531631303785d9938bef9a92130e21ce1049c8f56aad077`（4709233 字节，
  也等于 Homebrew cask 的 `sha256`），2.7.0 `sha256:9e2ff4393059a71dcdcd27c5d111de31673080ae2c18fec44ba65c1ab264383c`
  （3578987 字节）。Sparkle 路由不读 GitHub 的 `digest`，所以这条摘要目前没被用上。
- 签名: 两个包都是 `Developer ID Application`，Team `MN3X4648SC`，hardened runtime（`flags=0x10000(runtime)`），
  `codesign --verify --deep --strict` 通过，`stapler validate` 通过，`spctl` `source=Notarized Developer ID`。
  上一版与最新版 Team 相同，旧副本不会被 Team 闸拦下。
- 嵌套: 没有 `Contents/Library/LoginItems` / `Contents/Helpers`；`check-bundle.sh` 两个包都没列出 nested。
  包里只有 Sparkle 自带的 `Updater.app` 与 `Downloader.xpc` / `Installer.xpc`（`SUEnableDownloaderService` /
  `SUEnableInstallerLauncherService` 为真），不常驻。开机启动用 `LaunchAtLogin`（源码
  `GeneralSettingsPane.swift`），登记的是主 app 本身，没有 helper。
- 其他: 直装版也是沙盒 app（entitlements 含 `com.apple.security.app-sandbox`），这对替换 bundle 没有影响；
  Maccy 是 `LSUIElement` 菜单栏 app。
- **读的是**: 人人可手动下载的 GA（feed 唯一的一条 = GitHub 最新 release 的资产；Homebrew cask 指向同一个 zip）
- 阻塞: 无已知阻塞；待端到端确认

## 已知问题
- feed 的 `<releaseNotesLink>` 没有 `sparkle:` 前缀，Sparkle 和我们都读不到，行上没有 changelog 外链（厂商侧问题，不需要我们改）。
- MAS 副本的路由是代码 + 单测结论，没有真包验证。

## 如何复验

```sh
# 下载两个真包到自己的临时目录（GitHub release 资产）
curl -sSL -o <tmp>/v271/Maccy.app.zip "https://github.com/p0deje/Maccy/releases/download/2.7.1/Maccy.app.zip"
curl -sSL -o <tmp>/v270/Maccy.app.zip "https://github.com/p0deje/Maccy/releases/download/2.7.0/Maccy.app.zip"
ditto -x -k <tmp>/v271/Maccy.app.zip <tmp>/v271/x
ditto -x -k <tmp>/v270/Maccy.app.zip <tmp>/v270/x

swift run --package-path application-test feed-discover <tmp>/v271/Maccy.app.zip
swift run --package-path application-test channel-verify <tmp>/v270/x/Maccy.app
swift run --package-path application-test channel-verify <tmp>/v271/x/Maccy.app
.claude/skills/coverage-discovery/scripts/check-bundle.sh <tmp>/v271/Maccy.app.zip
.claude/skills/coverage-discovery/scripts/check-bundle.sh <tmp>/v270/Maccy.app.zip
codesign -dvv <tmp>/v27x/x/Maccy.app

# feed 与 MAS
curl -sS "https://raw.githubusercontent.com/p0deje/Maccy/master/appcast.xml"
curl -sS "https://itunes.apple.com/lookup?bundleId=org.p0deje.Maccy&entity=macSoftware"
gh api "repos/p0deje/Maccy/releases?per_page=30" -q '.[] | "\(.tag_name)\t\(.prerelease)"'
gh api "repos/p0deje/Maccy/commits?path=appcast.xml&per_page=100"
```

`channel-verify` 只收 `.app` / `.dmg`，zip 要先 `ditto -x -k` 解开。

结果（2026-10-08）:

| 检查 | 2.7.0（上一版） | 2.7.1（最新） |
|---|---|---|
| bundle id / 短版本 / build | `org.p0deje.Maccy` / 2.7.0 / 61 | `org.p0deje.Maccy` / 2.7.1 / 62 |
| `SUFeedURL` | `.../p0deje/Maccy/master/appcast.xml` | 同左 |
| `SUPublicEDKey` | 无 | 无 |
| Team ID | `MN3X4648SC` | `MN3X4648SC` |
| `LSMinimumSystemVersion` / 架构 | 14.0 / `x86_64 arm64` | 14.0 / `x86_64 arm64` |
| `codesign --verify --deep --strict` / spctl | 通过 / Notarized Developer ID | 通过 / Notarized Developer ID |
| `check-bundle.sh` nested | 无 | 无 |
| `feed-discover` | — | `declared  https://raw.githubusercontent.com/p0deje/Maccy/master/appcast.xml` |
| `channel-verify` detected channel | stable（`ChannelBinding <none for this app>`） | stable |
| winning source / latest | Sparkle / 2.7.1 | Sparkle / 2.7.1 |
| release notes | 922 chars inline, `changelogURL <nil>` | 同左 |
| deltas / release history | 0 / 1 | 0 / 1 |
| status | `UPDATE → 2.7.1` | `up to date` |

非 stable 轨：没有可下的包（feed 无 tag，最后一个 prerelease 是 2024-09-10 的 `2.0.0.beta.15`，比现行 stable 旧），
所以没有对非 stable 包跑 `channel-verify`。

## 建议下一步
1. 协调会话串行跑端到端一键：装 2.7.0 → `duo check` 应报 `2.7.0 → 2.7.1 [Sparkle]` → `duo install --yes`，
   确认走无 EdDSA 分支后装上 2.7.1、Team `MN3X4648SC`、签名完好；再跑「运行中 + 自更新器」一轮。
2. 无代码改动：不需要 `ChannelBinding`（单轨、feed 无 tag）、不需要 recipe（Sparkle inline 已结构化）。
3. 可选、非我们侧：如果想让行上有 changelog 外链，需要厂商把 `<releaseNotesLink>` 改成
   `<sparkle:releaseNotesLink>`；我们不应为一个两边都不认的无前缀元素放宽解析器。
