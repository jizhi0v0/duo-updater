# VimR

## 基本信息
- App: VimR — Neovim 的原生 macOS GUI（`qvacua/vimr`，MIT，未归档）
- Bundle ID: `com.qvacua.VimR`
- Team ID: `H96Q2NKTQH`（Developer ID Application: Tae Won Ha）；spctl: `accepted`，`source=Notarized Developer ID`
- 观测版本: 0.67.0（tag `v0.67.0-20261010.130648`，资产 `VimR-v0.67.0.tar.bz2`，19530909 字节，`CFBundleVersion` 20261010.130648），2026-11-11
- 自更新机制: 内置 Sparkle 2（`Sparkle.framework`、`SUPublicEDKey` `G37CFFnc1dSRxbsuzquapWYKBVaEatiParffxNIvghI=`），但 Info.plist **没有 `SUFeedURL`**：feed 在代码里按偏好二选一（见 Channel 详情）。`feed-discover` 因此报 `review ambiguousCandidates`（二进制里两个候选：`appcast.xml` 与 `appcast_snapshot.xml`）
- 分发: GitHub Releases（单个 universal `.tar.bz2`）；Homebrew cask `vimr`（0.67.0,20261010.130648，`auto_updates true`，所以通用 Homebrew 源让位）；Mac App Store 无
- 产品终止: 没有。仓库未归档，README 无停止维护说明，最近一个 release 是 2026-10-10

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle（ChannelBinding 供 feed） | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓ 一键 universal tar.bz2（EdDSA + Team 闸） | —（auto_updates，让位） | — | —（Sparkle 先应答；changelog 用 GitHub releases） | — |
| **snapshot** | ✓ feed swap 到 `appcast_snapshot.xml`（`.preview`） | — | — | — | — |

当前生效源: **Sparkle**，地址由 `VimRChannel`（`ChannelBinding`）给出，因为 bundle 自己不声明

## 覆盖清单
- 真包（都从 tar.bz2 用 `tar -xf` 解出）:
  - v0.67.0（最新）: `com.qvacua.VimR`，Team H96Q2NKTQH，Notarized，0.67.0 / 20261010.130648，`LSMinimumSystemVersion` 14.6，`x86_64 arm64`，无 `SUFeedURL`，有 `SUPublicEDKey`
  - v0.66.1（上一个）: 同 id、同 Team、同 EdDSA key，0.66.1 / 20260920.105849，universal，无 `SUFeedURL`
  - snapshot/20250715.204752（最近一个 snapshot，GitHub prerelease）: 同 id、同 Team、同 EdDSA key，`CFBundleShortVersionString` `SNAPSHOT-20250715.204752` / `CFBundleVersion` 20250715.204752，**arm64 only**，`LSMinimumSystemVersion` 13.5
  - v0.34.0-355（最后一个 build 号还是整数的版本）: 同 id、同 Team，0.34.0 / 355，**x86_64 only**，Info.plist 里**有** `SUFeedURL` = `…/master/appcast.xml`，只有 DSA key（`SUPublicDSAKeyFile`），没有 `SUPublicEDKey`
  - v0.9.0-112（列出的最老 stable）: 同 id、同 Team，0.9.0 / 112，x86_64，`SUFeedURL` 同上，DSA
- 旧 bundle id: 没有。0.9.0 到 0.67.0 一直是 `com.qvacua.VimR`，Team 一直是 H96Q2NKTQH
- 版本范围与版本方案: v0.35.0（2021-11）起 `CFBundleVersion` 是 `yyyymmdd.hhmmss`；之前是整数（112…355）。两种都和 feed 的 `sparkle:version` 按 build 比较，整数 355 < 20261010.130648，所以老副本被正确提示更新。`sparkle:shortVersionString` 带 `v`（`v0.67.0`），而包内是 `0.67.0`；比较走 build，`VersionComparator` 也会去掉前导 `v`
- 同仓库的其他发布物: `neovim-v<nvim>-<build>` prerelease（裸 nvim tarball，不是 app）、`snapshot/<build>` prerelease、`vimr-deps-…` prerelease。检测走 appcast，这些 tag 都不会被当成 VimR 版本；changelog 的 `tagPattern` 只收 `v<x.y.z>-<8 位日期>.<6 位时间>`
- 主机下限: universal 资产；`LSMinimumSystemVersion` 14.6（appcast 写 14.8），都低于我们的 macOS 15 下限
- 老副本的签名差异: ≤0.34 系列只有 DSA key。`SparkleInstaller` 在副本没有 `SUPublicEDKey` 时跳过 EdDSA，仍走 Team ID 闸（同 Team），所以一键照常；它们是 x86_64-only，在 Apple Silicon 上靠 Rosetta 运行，换成 universal 新版没有问题

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable   | `com.qvacua.VimR` | — | 偏好缺省 / false | feed `…/master/appcast.xml` | ✓ |
| snapshot | 同 id | 共享 | `UserDefaults["168"]["use-snapshot-update-channel"]` = true | feed `…/master/appcast_snapshot.xml` | ✓（`.preview`） |

从源码确认（`qvacua/vimr` 的 `master`）:
- 切换方式: `VimR/VimR/AppDelegate.swift` 的 `UpdaterDelegate.feedURLString(for:)`，`useSnapshotChannel` 为真时返回 `appcast_snapshot.xml`，否则 `appcast.xml`；它取自 `AppState.useSnapshotUpdate`，启动时读、状态变化时同步
- 偏好位置: `VimR/VimR/States.swift` 把它编码成 `use-snapshot-update-channel`（Bool，默认 false）；`VimR/VimR/PrefMiddleware.swift` 把整个 `AppState` 编码成一个字典，写进 `UserDefaults.standard` 的 key `PrefMiddleware.compatibleVersion` = `"168"`，`AppDelegate.init` 从同一个 key 读回
- 两个 feed 怎么生成: `bin/build_jenkins.sh` 在 stable 发布时执行 `cp appcast.xml appcast_snapshot.xml`；snapshot 发布（`snapshot/<build>` tag，`--prerelease`）只写 `appcast_snapshot.xml`（`bin/publish_release.sh`、`bin/set_appcast.py`）。所以 snapshot feed = stable feed，外加比上一个 stable 新的 snapshot
- snapshot 包本身没有渠道标记: 同 id、同名、同 Team，`ReleaseChannel.detect` 把 `SNAPSHOT-20250715.204752` 读成 `.stable`（`channel-verify` 实测）。偏好是唯一信号，读不到时给 stable；这时没有任何 `detect()` 信号被压掉
- snapshot 叫 `.preview`：`ReleaseChannel` 里 "snapshot" 这个词在别处都映射到 `.preview`
- `"168"` 这个 key 的风险: VimR 一旦把 `compatibleVersion` 改掉，新版本从默认值（stable）开始写新 key，旧的 `"168"` 字典留在原处。只读 `"168"` 时，最坏情况是一个在新版本里重新打开 snapshot 的用户继续被当成 stable，不会把 stable 用户推到 snapshot。改了要同步改 `VimRChannel.stateKey`
- 偏好监视: VimR 不是沙盒 app，偏好在 `~/Library/Preferences/com.qvacua.VimR.plist`，已在 `ChannelBinding.preferenceWatchCandidates` 的根目录里；`boundBundleIDs` 已登记
- 渠道证明: `bindingProofs` 里 `(com.qvacua.VimR, .preview)` 锚定 `appcast_snapshot\.xml` 于 `feedOverride`（和 IINA 一样，请求侧的证明）

## 更新检测
- 源: `SparkleAppcastSource`，feed 由 `VimRChannel.resolve` 的 `feedOverride` 提供（bundle 不声明 `SUFeedURL`）
- 每个 appcast 只有一条 item（`set_appcast.py` 每次重写整份文件）；`enclosure` 带 `sparkle:edSignature`
- `<releaseNotesLink>` 与 `<minimumSystemVersion>` 没有 `sparkle:` 前缀，解析器不认，所以 `changelogURL` 为 nil、最低系统版本不过滤；对 macOS 15+ 主机无影响（14.8 < 15）
- `channel-verify` 结果见「如何复验」

## 按架构 / 按 OS 分轨
- stable 只有一个 universal tar.bz2；snapshot 曾经是 arm64-only。没有按 OS 分轨（每份 appcast 只有一条 item）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2） | 没有 `<sparkle:deltas>` | 不需要 |
| 证据 | `Sparkle.framework` | 两个 appcast（2026-11-11）各一条 item、一个 tar.bz2 enclosure | 整包 + EdDSA |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | Sparkle 标准行为 | 未观测 | — |
| 证据 | 内置 Sparkle 2 | — | — |

## Changelog
- 来源: GitHub release 正文（`.gitHubReleases`，`api.github.com/repos/qvacua/vimr/releases?per_page=40`，`maxEntries` 20）。appcast 的 `<description>` 就是 `markdown.markdown(<release body>)`，内容相同，但每份 appcast 只有一条，看不到历史
- `tagPattern` `^v([0-9]+(?:\.[0-9]+)+)-[0-9]{8}\.[0-9]{6}$`：只收 stable tag，捕获的版本就是包内 `CFBundleShortVersionString`（`0.67.0`）；`neovim-v…`、`snapshot/…`、`vimr-deps-…` 都不收
- 结构化: 有条目、有日期；**厂商不写分节标题**（正文是平铺的 `*` 列表，依赖升级用缩进的 `-` 子条目），所以 `headings []` 是真实情况，不是被压平
- 跟随 channel: 配方 `channel: .stable`、`excludedChannels: [.preview]`。snapshot 副本回落到 snapshot feed 自带的 inline 说明，它总是描述正在被提供的那一项

## 一键安装
- 状态: 支持（Sparkle 路径：EdDSA 校验 + Team ID 闸；`ArchiveExtractor` 对 `bz2` 用 `/usr/bin/tar -xf`）
- 端到端: ✓ 第一轮（2026-11-11，本机，未运行，偏好域不存在 → stable）：/Applications 放 0.66.1，`duo check` 报 `0.66.1 → v0.67.0 [Sparkle]`，`duo install com.qvacua.VimR --yes` → `extracting … verifyingCodeSignature … installed.`；结果 0.67.0、Team `H96Q2NKTQH`、`codesign --verify --deep --strict` 0、spctl Notarized Developer ID。snapshot 轨与运行中一轮未做。
- 不适用的副本: 没有。≤0.34 的 DSA-only 副本跳过 EdDSA，仍过 Team 闸

## 已知问题
- `<releaseNotesLink>` / `<minimumSystemVersion>` 没有命名空间前缀，不被读取（见更新检测）
- `"168"` 偏好 key 改版后的行为见 Channel 详情
- 行上显示的最新版是 feed 的 `v0.67.0`（带 `v`），装机版本是 `0.67.0`，只是写法不同

## 历史与实测
- 2026-11-11: 两份 appcast 字节相同（1326 字节，都是 v0.67.0 / 20261010.130648）
- 2026-11-11: `appcast_snapshot.xml` 在 qvacua/vimr@245d6ad3（2025-07-15）时是 `SNAPSHOT-20250715.204752`（build 20250715.204752），同一提交的 `appcast.xml` 是 0.55.0（20250713.101600）；0.56.0（2025-07-23）发布后两份又相同
- 2026-11-11: `PrefMiddleware.compatibleVersion` 的历史：2019-03（8d38b09d）到今天都是 `"168"`；3306da68（2023-10-29）改成 `"169"`，e103f67d（2023-11-05）"revert prefs version bump" 改回 `"168"`
- 2026-11-11: release 列表 433 条，其中 132 条非 prerelease；最近 40 条里 VimR stable 约 27 条，`neovim-v…` prerelease 穿插其中
- 2026-11-11: snapshot 解析用临时写入 `defaults write com.qvacua.VimR 168 -dict use-snapshot-update-channel -bool true` 验证，之后 `defaults delete` 并删除空 plist

## 如何复验
```bash
# 包（tar -xf 解出 VimR.app）
https://github.com/qvacua/vimr/releases/download/v0.67.0-20261010.130648/VimR-v0.67.0.tar.bz2
https://github.com/qvacua/vimr/releases/download/v0.66.1-20260920.105849/VimR-v0.66.1.tar.bz2
swift run --package-path application-test channel-verify <v0.66.1>/VimR.app --expect stable
swift run --package-path application-test channel-verify <v0.67.0>/VimR.app --expect stable
```

实测（2026-11-11）:
- v0.66.1: `ChannelBinding  stable — read from this app's own preference`，`detected channel → stable`；`SUFeedURL …/master/appcast.xml`，`winning source Sparkle`，`latest v0.67.0`，download `…/v0.67.0-20261010.130648/VimR-v0.67.0.tar.bz2`；`changelog pane  recipe changelog:com.qvacua.VimR:stable: 20 entries; newest 0.67.0: 2 items, headings []`；`status UPDATE → v0.67.0`
- v0.67.0: 同上，`status up to date`
- v0.66.1 + 临时偏好 `use-snapshot-update-channel = 1`: `ChannelBinding  preview`，`detected channel → preview`，`SUFeedURL …/master/appcast_snapshot.xml`，`status UPDATE → v0.67.0`（snapshot feed 当时与 stable 相同）
- snapshot/20250715.204752（未加 binding 前）: `inferred stable`，`ChannelBinding <none for this app>`，`status unknown (no source answered)`——这就是要加 binding 的原因
