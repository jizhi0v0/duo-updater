# DaisyDisk

> 首次审计 2026-08-29；**2026-09-14 复核**（真包、feed、iTunes lookup、生产代码路径重跑一遍）。
> 复核推翻了首次审计"一键安装未实现"的说法，其余结论不变。

## 基本信息
- Bundle ID（官网直装）: `com.daisydiskapp.DaisyDiskStandAlone`
- Bundle ID（Mac App Store）: `com.daisydiskapp.DaisyDisk`（独立 bundle id，非同一份构建）
- Team ID: `4CBU3JHV97`（Developer ID Application: Software Ambience Corp.）
- 观测版本（直装，2026-08-29 与 2026-09-14 两次下载核对）: short `4.34.2`，build `4.34.2`
- MAS 版本（iTunes lookup，2026-08-29 与 2026-09-14）: `4.34.1`（`currentVersionReleaseDate` 2026-07-05）
- 自更新机制: 直装版 Sparkle，**无 EdDSA 的 feed**（bundle 没有 `SUPublicEDKey`，只有 `SUPublicDSAKeyFile`；
  feed 条目只带 `sparkle:dsaSignature`）；MAS 版由 App Store 负责
- 架构: universal（`x86_64 arm64`），`LSMinimumSystemVersion` = `10.13`

## 覆盖矩阵

> ✓ = 已接入（经既有通用机制，无需专属 recipe）  ○ = 可接入(未实现)  ✗ = 不作答  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable（直装）** | ✓ 一键 | ✗（auto_updates）| — | — | —（不需要） |
| **stable（MAS）**  | — | —  | ✓ | — | — |

当前生效源: 直装版 **Sparkle**（`SourceStack.make` 里排在 HomebrewCask 之前，先应答）；
MAS 版 **App Store**（`MacAppStoreSource`，通用逻辑）。商店副本只有声明了
`answersAppStoreCopies` 的源会作答，目前只有 `MacAppStoreSource`，由
`SourceStorePolicyTests.exactlyOneSourceAnswersStoreCopies` 从注册表推导钉住。

## 结论：不需要新代码

任务给出的前提是 Homebrew cask `daisydisk` 标了 `auto_updates: true`，`HomebrewCaskSource` 因此跳过它
（`guard !entry.autoUpdates else { return nil }`），据此推断这个 app 会落到 `.unknown`、需要专属
`VendorProbeRecipe`。**这个前提漏了 `SourceStack.make` 里排在 Homebrew 前面的 `SparkleAppcastSource`
——而 DaisyDisk 直装版真的带着一个能用的 `SUFeedURL`。**

证据链：

1. **Homebrew cask 本身就点名这是个 Sparkle app。** cask 源码的
   `livecheck do url "https://daisydiskapp.com/downloads/appcastFeed.php"; strategy :sparkle end`
   （首次审计读 `.rb` 得到）；2026-09-14 的 `formulae.brew.sh/api/cask/daisydisk.json`：
   `version` = `4.34.2`，`auto_updates` = `true`，`url` = `https://daisydiskapp.com/download/DaisyDisk.zip`。
2. **appcast 是干净的单轨 Sparkle feed。** 2026-09-14 拉取该 URL，内容与 2026-08-29 的抓取**逐字节相同**
   （即回归测试里的 fixture）：5 个 `<item>`，最新一条 `Version 4.34.2`，
   `sparkle:version="4.34.2"`，`sparkle:shortVersionString="4.34.2"`，
   `enclosure url="https://daisydiskapp.com//download/DaisyDisk.zip"`，`pubDate 2026-07-10`。
   **通篇没有 `<sparkle:channel>` 标签**——只有 stable 一条轨道，不需要 `ChannelBinding`。
3. **下载 `https://daisydiskapp.com/download/DaisyDisk.zip` 解包验证（2026-09-14）：**
   - `CFBundleIdentifier` = `com.daisydiskapp.DaisyDiskStandAlone`
   - `CFBundleShortVersionString` = `CFBundleVersion` = `4.34.2`（与 feed 最新条目同构）
   - `SUFeedURL` = `https://daisydiskapp.com/downloads/appcastFeed.php`（与第 2 步的 URL 一致）
   - 无 `SUPublicEDKey`；无 `_MASReceipt`（这份下载是 Developer ID 副本）
   - `codesign`: `TeamIdentifier=4CBU3JHV97`；`spctl -a -vv --type execute`: `accepted / source=Notarized Developer ID`
   - zip 大小 7982277 字节，与 enclosure 的 `length="7982277"` 一致
4. **`AppScanner` 读 `SUFeedURL` 是通用逻辑，`SparkleAppcastSource.latestVersion` 同样通用**
   （`guard let feedURL = app.sparkleFeedURL`），都不查按 bundle id 登记的白名单。
5. **临时测试走生产路径（跑完即删，未提交）**：
   `AppScanner(locations: [解包目录]).scan()` + `UpdateChecker(sources: SourceStack.make(githubToken: nil))`：
   ```
   scanned: com.daisydiskapp.DaisyDiskStandAlone 4.34.2/4.34.2 mas=false feed=https://daisydiskapp.com/downloads/appcastFeed.php edKey=false
   result:  source=Sparkle latest=4.34.2/4.34.2 url=https://daisydiskapp.com//download/DaisyDisk.zip edSig=false status=upToDate canAutoInstall=true
   gate2-4 (SignatureVerifier.verifyInstallArtifact): PASS（下载的 bundle 同时充当"已装副本"传入，Team / bundle id 比较是自己比自己，只实际验到签名有效与架构 / OS 下限）
   ```
6. **MAS 版是独立 bundle id、独立构建**（Pattern A）。adamId `411643860`（首次审计经 `mas search` 得到）；
   2026-09-14 iTunes lookup 该 id 返回 `bundleId: com.daisydiskapp.DaisyDisk`（没有 `StandAlone` 后缀）、
   `version: 4.34.1`、`sellerName: Software Ambience Corp.`。`MacAppStoreSource.latestVersion` 按已装
   bundle 自带的 id 查 iTunes lookup（`guard app.isMASApp, let bundleID = app.bundleID`），不需要登记。

因此：**直装版和 MAS 版都已被现有通用机制覆盖，零代码改动。** 补了一条回归测试钉住这个结论
（`DuoUpdaterCore/Tests/DuoUpdaterCoreTests/DaisyDiskCoverageTests.swift`，fixture 是第 2 步的真实
appcast 原文），防止改动通用 Sparkle 管线时把这个 app 静默带回 `.unknown`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable（直装） | `com.daisydiskapp.DaisyDiskStandAlone` | 独立 | `SUFeedURL` | ✓（通用机制） |
| stable（MAS）  | `com.daisydiskapp.DaisyDisk`            | 独立 | MAS receipt | ✓（通用机制） |

未发现 beta/preview 等非 stable 轨道——官网、appcast、cask 都只有一条线。

## 更新检测
- Appcast: `https://daisydiskapp.com/downloads/appcastFeed.php`（与 cask 的 livecheck URL 相同）。
- 下载: `https://daisydiskapp.com/download/DaisyDisk.zip`——固定、不带版本号的 URL，与 appcast 最新条目
  的 enclosure 一致（feed 里多一个 `/`）。没有灰度/分轨的迹象。
- feed 与真实包的 short/build 同构，无版本方案陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | appcast 5 条里没有任何 `<sparkle:deltas>` | 不适用——服务端未见下发 |

## Changelog
- Sparkle item 只带 `<sparkle:releaseNotesLink>`，不带 `<description>` / `<sparkle:releaseNotes>` 内联正文，
  所以 `SparkleAppcastSource.structuredChangelog` 对这份 feed 返回 nil（读代码得出：没有任何 item 产出
  notes 时返回 nil），走既有的链接 / web view 兜底路径。
- 链接页面（如 `https://daisydiskapp.com/releases/main/macos/br5`，2026-09-14 复查）结构规整：
  `<article><h2>Version X</h2><time datetime=YYYY-MM-DD>…</time>…` 重复排列（页首依次是 4.34.2、4.34.1、4.34）。
  **可以做一个 ChangelogRecipe 转成原生 changelog，未实现**——需要时跑 `/fragile-recipe DaisyDisk`。

## 一键安装
- **状态: 通用 Sparkle 路径已经提供，无需新代码。**（首次审计写的是"未实现"——那是错的：它只看了
  "没有专属 recipe"，没看 `UpdatePolicy.canAutoInstall` 对 Sparkle 结果的通用分支。）
- 走的是**无 EdDSA 公钥**的分支（代码注释里叫 unsigned feed，这里 feed 其实带旧式 DSA 签名）：bundle 没有 `SUPublicEDKey`，所以不做 EdDSA；enclosure 是 zip，
  `canAutoInstall` 为 true。信任由 code signature + 同 Team + 同 bundle id 闸承担
  （`SparkleInstaller` 注释里写的 Fork 那种情况）。第 5 步只验到真实下载的签名有效；**下载与一份独立的
  已装副本之间 Team / bundle id 是否一致没有量过**——而这条分支的信任恰恰全靠它。
  feed 里的 `dsaSignature` 我们不校验。
- 未做的：没有在真机上把一个旧版本真正装回新版本（端到端）。

## 已知问题
- 无。

## 建议下一步
1. 若需要 changelog 原生渲染：`/fragile-recipe DaisyDisk`（ChangelogRecipe，source 同上页面）。
2. 若要确认一键安装端到端可用：降到一个旧的官方版本（feed 里的 `DaisyDisk_4_24.zip` 2026-09-14 仍可下载：HEAD 200，长度 9854383 与 enclosure 一致），让引擎装回 4.34.2。

## 如何复验
```
# GET https://daisydiskapp.com/downloads/appcastFeed.php → 与 DaisyDiskCoverageTests 的 fixture 逐字节比对
# 下载 https://daisydiskapp.com/download/DaisyDisk.zip，ditto -x -k 解包 → com.daisydiskapp.DaisyDiskStandAlone 4.34.2/4.34.2，无 SUPublicEDKey
# codesign -dvv → TeamIdentifier=4CBU3JHV97；spctl -a -vv --type execute → Notarized Developer ID
# GET https://itunes.apple.com/lookup?id=411643860 → com.daisydiskapp.DaisyDisk 4.34.1
# swift test --filter DaisyDiskCoverageTests（DuoUpdaterCore）
# 临时测试同 coconutBattery 那份：→ source=Sparkle, canAutoInstall=true；verifyInstallArtifact PASS（自己比自己，Team 闸未真正比对）
```
