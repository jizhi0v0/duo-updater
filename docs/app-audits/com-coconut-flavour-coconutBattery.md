# coconutBattery

> 首次审计 2026-08-29；**2026-09-14 复核**（真包、feed、cask、生产代码路径重跑一遍）。
> 两次结论一致的地方不重复标注；只在复核改变了事实的地方写出两个日期。

## 基本信息
- Bundle ID: `com.coconut-flavour.coconutBattery`
- Team ID: `R5SC3K86L5`（Developer ID Application: Christoph Sinai）
- 观测版本: `4.4.0` (build `265`；首次审计时是 `4.3.4` / `224`)
- 自更新机制: Sparkle，**签名 feed**（bundle 带 `SUPublicEDKey`，feed 条目带 `sparkle:edSignature`）
- 架构: universal（`x86_64 arm64`），`LSMinimumSystemVersion` = `12.4`

## 覆盖矩阵

> ✓ = 已接入（generic，无需 registry）  ○ = 可接入(未实现)  ✗ = 不作答  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓ 一键  | ✗ (auto_updates) | — | — | — |
| **beta**     | ○（needs-verify，见下） | — | — | — | — |

当前生效源（`UpdateChecker` 按 `SourceStack.make` 顺序第一个应答的）: **Sparkle**。

## 结论：不需要新 recipe

出发点是 Homebrew cask `coconutbattery` 带 `auto_updates: true`，按
`HomebrewCaskSource.swift` 的 `guard !entry.autoUpdates else { return nil }`，
这个 cask 确实会被跳过。但那只说明 Homebrew 这一路不答，不代表整条优先链都不答。
`SourceStack.make` 的顺序是
MAS → Xcode → **Sparkle** → HomebrewCask → GitHub →（有 license 时 Alcove）→ VendorProbe → Electron，
这个 app 真身带了 `SUFeedURL`，在 Sparkle 这一档（HomebrewCask 之前）就被通用逻辑接住，
不需要任何 VendorProbe/GitHub 注册。

证据链（2026-09-14 复核，从官方下载地址取真实 app，不是从 cask JSON 推断）：

1. `formulae.brew.sh/api/cask/coconutbattery.json`：`version` = `4.4.0,265`，
   `auto_updates` = `true`，`url` =
   `https://www.coconut-flavour.com/downloads/coconutBattery_440_265.zip`，artifact 是 `app`。
   cask 的 `livecheck` 用 `:sparkle` 策略读 `https://coconut-flavour.com/updates/coconutBattery_4.xml`
   （首次审计时读 cask 源码得到，本次未重读 `.rb`）。
2. 下载该 zip（6128408 字节，与 feed 里 enclosure 的 `length` 一致），解包读真实
   `Contents/Info.plist`：
   - `SUFeedURL` = `https://coconut-flavour.com/updates/coconutBattery_4.xml`
   - `SUPublicEDKey` 存在
   - `CFBundleIdentifier` = `com.coconut-flavour.coconutBattery`
   - `CFBundleShortVersionString` = `4.4.0`，`CFBundleVersion` = `265`
   - 无 `_MASReceipt`（这份下载是 Developer ID 副本）
   - `codesign` Team ID = `R5SC3K86L5`；`spctl -a -vv --type execute` → `accepted / source=Notarized Developer ID`
3. `AppScanner` 对**任意**扫描到的 app 通用地读取 `Info.plist` 的 `SUFeedURL`、
   `SUPublicEDKey`，填进 `InstalledApp`（不按 bundle id 注册）。
4. 用一条**临时**测试（跑完即删，未提交）走生产路径：
   `AppScanner(locations: [解包目录]).scan()` + `UpdateChecker(sources: SourceStack.make(githubToken: nil))`，
   再把结果喂给 `UpdatePolicy.canAutoInstall` 和安装闸门：

   ```
   scanned: com.coconut-flavour.coconutBattery 4.4.0/265 mas=false feed=https://coconut-flavour.com/updates/coconutBattery_4.xml edKey=true
   result:  source=Sparkle latest=4.4.0/265 url=https://www.coconut-flavour.com/downloads/coconutBattery_440_265.zip edSig=true status=upToDate canAutoInstall=true
   gate2-4 (SignatureVerifier.verifyInstallArtifact): PASS（下载的 bundle 同时充当"已装副本"传入，Team / bundle id 比较是自己比自己，只实际验到签名有效与架构 / OS 下限）
   ed25519 (SignatureVerifier.verifyEdSignature, 下载的 zip 字节 + bundle 的 SUPublicEDKey + feed 的 edSignature): PASS
   ```

   `source=Sparkle` 是直接证据：优先链在到达 HomebrewCaskSource 之前就被 Sparkle 接住，
   原始 issue 里"因为 auto_updates 被跳过所以落在 .unknown"的前提不成立。

   首次审计（2026-08-29）用的是 `application-test/channel-verify --check`，把 app 临时放进
   `~/Applications` 跑，同样得到 `winning source → Sparkle`。⚠️ 注意 `channel-verify --check`
   用的是**自己手写的一份源列表**（MAS / Sparkle / Homebrew / GitHub / VendorProbe），
   不是 `SourceStack.make`，没有 Xcode / Alcove / Electron 那几档；对这个 app 结论不受影响，
   但它不等于"完整生产链"。本次改用 `SourceStack.make` 本身。

## Channel 详情

同一份 feed 用 `<sparkle:channel>` 标签分轨（Pattern C）。beta 条目两次观测结果不同：

- 2026-08-29：feed 里有一条 `<sparkle:channel>beta</sparkle:channel>`（`4.4.0b`，build `260`，
  2026-08-28）加一条无 channel 标签的 stable 条目。
- 2026-09-14：feed 只剩两条，**都没有 channel 标签**——`4.4.0` / `265`（2026-09-09）和
  `4.3.3` / `218`（2026-06-13）。看起来像那条 beta 转正成了 4.4.0、beta 条目随之撤掉，
  但只有两次快照，**这是推断**，不足以说明这个 vendor 的 beta 条目怎么发、何时撤。

`SparkleAppcastSource` 通用地按"已装版本落在 feed 哪个 item"推断当前 channel，
理论上 beta 用户不需要新代码。但这条**从没在真实 beta 安装上验证过**，而且现在 feed 里
没有 beta 条目可以拿来验，只能标 **needs-verify**。

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `com.coconut-flavour.coconutBattery` | `SUFeedURL`，已装版本在 feed 中命中 channel-less item | ✓（真实 bundle 验证，2026-08-29 与 2026-09-14） |
| beta | 同上（共享） | `<sparkle:channel>beta</sparkle:channel>` | needs-verify（架构上应可行；当前 feed 无 beta 条目） |

## 更新检测
- Appcast: `https://coconut-flavour.com/updates/coconutBattery_4.xml`。
- feed 条目带内联 `<description>`（2026-09-14 观测；未检查 `structuredChangelog` 实际渲染出什么）。
- **一个 vendor 侧现象，两次观测结果不同，如实并列**：
  - 2026-08-29：feed 的 stable 条目是 `4.3.3` / `218`，而同一时刻 cask 与官网给出的当前版本
    已是 `4.3.4` / `224`——feed 落后于真实最新稳定版。
  - 2026-09-14：feed 顶部是 `4.4.0` / `265`，与 cask 一致，**不再落后**；`4.3.4` 从未出现在
    这次抓到的 feed 里（只有 4.4.0 和 4.3.3 两条）。
  - 滞后本身不会误报（4.3.3 比已装的 4.3.4 旧，不推送），代价是停在 4.3.4 之前的用户在那段
    时间里不会被提示升 4.3.4。两次快照不足以说明 vendor 发布 feed 的节奏。

## 一键安装
- **状态: 通用 Sparkle 路径已经提供，无需新代码。**（首次审计写的是"未实现"——那是错的：
  它只看了"没有专属 recipe"，没看 `UpdatePolicy.canAutoInstall` 对 Sparkle 结果的通用分支。）
- 走的是**签名 feed** 分支：bundle 有 `SUPublicEDKey`、条目有 `edSignature`、enclosure 是 zip，
  `canAutoInstall` 为 true（上面探针的输出）。EdDSA 闸在真实下载上通过；code signature 闸只验到
  签名有效，Team / bundle id 是拿下载的 bundle 自己比自己，**没有对一份独立的已装副本量过**。
- 未做的：没有在真机上把一个旧版本真正装回新版本（端到端）。
- 读的是 feed 的最新 stable 条目，也就是 vendor 自己的 Sparkle 更新会推给用户的同一个包；
  这个 feed 没有灰度/按设备分配的迹象。

## coconutBattery Plus（付费版）
coconutBattery Plus **不是独立 app / 独立 bundle id**，是同一个 `coconutBattery.app` 内的授权解锁
（例如 4.2.0 changelog 里的 "Battery capacity can now be displayed in Wh (Plus version)" 就是同一个
二进制里的功能开关）。所以现有这条 Sparkle 检测同时覆盖免费版和 Plus 授权用户。
（转引自 2026-08-29 首次审计，本次未复测。）

## 已知问题
- 无阻塞项。beta channel 未经真实 bundle 验证，标 needs-verify，不算已知缺陷。

## 建议下一步
1. 不需要新增 VendorProbe / GitHub recipe。
2. 如果以后要较真 beta channel：等 feed 里重新出现 `<sparkle:channel>beta</sparkle:channel>` 条目时，
   下载那个包跑 `swift run --package-path application-test channel-verify <path> --expect beta`，
   结果写回本文档。

## 如何复验
```
# GET https://formulae.brew.sh/api/cask/coconutbattery.json → 4.4.0,265, auto_updates=true
# GET https://coconut-flavour.com/updates/coconutBattery_4.xml → 顶部 4.4.0/265，无 sparkle:channel
# 下载 coconutBattery_440_265.zip，ditto -x -k 解包 → com.coconut-flavour.coconutBattery 4.4.0/265，SUFeedURL 同上，有 SUPublicEDKey
# codesign -dvv → TeamIdentifier=R5SC3K86L5；spctl -a -vv --type execute → Notarized Developer ID
# 临时测试：AppScanner(locations: [解包目录]) + UpdateChecker(sources: SourceStack.make(githubToken: nil))
#   → source=Sparkle, canAutoInstall=true；verifyInstallArtifact PASS（自己比自己）；verifyEdSignature PASS
```
