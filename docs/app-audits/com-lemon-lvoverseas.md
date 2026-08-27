# CapCut

审计 2026-08-27。

## 基本信息

- Bundle ID: `com.lemon.lvoverseas`
- App 名: `CapCut.app`（2.1 GB）
- URL scheme: `capcut`
- 官网 / 下载页: https://www.capcut.com/tools/desktop-video-editor
- 观测版本: stable `9.3.0` / beta `9.4.0-beta4`
- Team ID: `22MMUN2RN5` — BYTEDANCE PTE. LTD.，`spctl -t install` 判定
  "Notarized Developer ID"（**两个渠道的真实 dmg 都验过**）
- 架构: **arm64 only**（`lipo -archs` 对启动器 / `libVECreator.dylib` /
  `CapCut Helper.app` 全部只有 `arm64`）。`LSMinimumSystemVersion` 写着 `10.14`，
  那是没跟着更新的残留，不代表支持 Intel。
- 自更新机制: **内嵌 Sparkle，但决策不走 appcast**

Qt 应用（`QtQuick` / `QtQml` 一票 framework + `libmmkv` + CEF），不是 Electron。

### 和 Sparkle 的关系（说清楚边界）

`Contents/Frameworks/` 里是**原版 `Sparkle.framework` 2.7.0（build 2044）**，
Versions/B（Sparkle 2.x 布局），带 `Autoupdate` / `Updater.app` / `XPCServices`，
`Info.plist` 有 `SUEnableInstallerLauncherService`，
而且 `libVECreator.dylib` 里**确实实现了 `SPUUpdaterDelegate` 的方法**：
`feedURLStringForUpdater:`、`allowedChannelsForUpdater:`、
`bestValidUpdateInAppcast:forUpdater:`。

但它**没有 `SUFeedURL`**，而且同一个 `MacUpdater` 类里同时有：

- 字面量 `sparkle:version` / `enclosure` / `length` —— 这是**用字典手搓 `SUAppcastItem`** 的形状；
- `initWithAppcastItem:secondaryAppcastItem:downloadBookmarkData:downloadToken:` ——
  即把**自己已经下好的文件**包成 `SPUDownloadedUpdate` 交给 Sparkle；
- 自己的下载器（`[UpdatingModel] download update`、`update.dmg`、
  `update_disk_space_setting.md5_check_switch` 自校验 md5）。

**已确证**：没有 `SUFeedURL`，所以 `SparkleAppcastSource` 对它永远不应答；
"更新到哪个版本" 由 `updatecontroller.cpp` 从 `update_reminder.*` 算出来。

**未确证（我的推断，标出来）**：`feedURLStringForUpdater:` 到底是返回一个真 URL、
返回一个本地写出来的 appcast（`file://`），还是干脆是个空实现 —— 只看字符串分辨不了。
所以「Sparkle 只当安装器」是推断，不是事实。要坐实得挂调试器或抓包。
对配方没有影响（无论哪种都没有我们能读的 appcast URL），但别把推断当结论往下传。

## 那个 3.6 MB 的 dmg 是安装器不是包

`CapCut_<id>_installer.dmg` 里是 `CapCut-Downloader.app`（`com.lemon.ccdownloader`）。
官网下载按钮发的是这个 stub，文件名里的数字是一次投放的 delivery id
（`POST /lv/v1/common/create_delivery_content` 返回的同形状 id），不是版本号。
真包 1.24 GB，在 `sf16-web-tos-buz.capcutstatic.com`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | ✗ | ✗ | — | — | ✓ 一键 |
| **beta** | ✗ | — | — | — | ✓ 一键 |

当前生效源：**VendorProbe**。`duo check --check com.lemon.lvoverseas`：

```
  CapCut  9.3.0  →  9.4.0-beta4  [Vendor]
```

其余四条源为什么不答：

- **Sparkle** — bundle 里没有 `SUFeedURL`，没有 feed 可读。
- **Homebrew** — cask `capcut` 存在且**没有** `auto_updates`，所以只要 app 真的从
  Caskroom 装的，`HomebrewCaskSource` 会答。本机不是（`brew list --cask` 无 capcut，
  provenance 闸不过），所以让位给 VendorProbe。**注意 cask 的版本是 `9.3.0.4490`
  （带 build），装机 `CFBundleShortVersionString` 是 `9.3.0`** —— 一台 brew 装的
  CapCut 有幽灵更新的形状，但那是既有行为，与本次改动无关。
- **MAS** — 见下面「同 id 两种分发」。
- **GitHub** — 无公开发布仓库。

### 同 id 两种分发（重要）

`itunes.apple.com/lookup?bundleId=com.lemon.lvoverseas&entity=macSoftware` 返回
**1 条**：`CapCut: Photo & Video Editor`，adamId `1500855883`，版本 **`19.2.0`**。

也就是说 App Store 上那份和 Developer ID 这份**共用 bundle id，版本方案完全不同**
（19.2.0 vs 9.3.0）。两边不串是靠两道既有闸，各自只认自己的：

- `VendorProbeSource.latestVersion(for:)` —— `guard !app.isMASApp`，商店副本永不进配方；
- `MacAppStoreSource.latestVersion(for:)` —— `guard app.isMASApp`，非商店副本永不进 MAS。

判据是 `Contents/_MASReceipt`（本机这份没有）。任何一道闸松了，一个方向是永久幽灵
更新（19.2.0 > 9.3.0），另一个方向是用 Developer ID 包覆盖掉商店副本、连带毁掉它的
收据和 entitlement。加任何新源之前先看这一条。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.lemon.lvoverseas` | 共享 | `joinBeta` / `tea_channel` | ChannelBinding | ✓ 一键 |
| beta | `com.lemon.lvoverseas` | 共享 | 同上 | ChannelBinding | ✓ 一键 |

Pattern B/C（app 内切换）。开关在 app 自己的「Version update」窗口里，叫
**"Get early access to beta features"**（`en.po` 的 `pc_version_update_checkbox`）。

### 开关落在哪：三个都不是

1. **不在 UserDefaults。** CapCut 是沙盒 app，域在
   `~/Library/Containers/com.lemon.lvoverseas/Data/Library/Preferences/`，
   那里两个 plist（`com.lemon.lvoverseas.plist` / `com.capcut.CapCut.plist`）都没有这个键。
2. **不在 `PackageConfig.plist`。** 那个是构建标记，不是用户选择。
3. **在容器外的 INI**：

   ```ini
   # ~/Movies/CapCut/User Data/Config/updateInfo
   [General]
   joinBeta=true
   need_show_automatic_updates_popup=false
   ```

同目录 `globalSetting` 里的 `enableAutoUpdate` 是**另一组**单选（截图里的
「Automatic updates」vs「Get notified about updates」），决定 CapCut 自己装不装，
不是渠道，别读错。

`~/Movies` 不是 TCC 三个受控用户目录（Desktop/Documents/Downloads）之一，也不走
`~/Library/Containers/<别人>/Data` 那道 App-Data 闸。但两次读都只在终端进程里验过，
GUI 上下文没验 —— 这是记忆里咬过两次的盲区，`CapCutChannel` 顶部注释里标了。

### 装机侧构建标记

`Contents/Resources/PackageConfig.plist`：

| | 值 |
|---|---|
| stable 装机 | `Channel Name = capcutpc_0` |
| beta dmg 挂载后 | `Channel Name = capcutpc_beta` |

CapCut 启动时把它抄进 `~/Movies/CapCut/User Data/Config/channel`
（`tea_channel=capcutpc_0`），所以不用 bundle 路径也能读到。
`CapCutChannel` **只在 `joinBeta` 完全没记录时**用它兜底 —— 理由见下一节。

### 为什么「没记录」不能当成 stable

`updateInfo` 是**打开更新窗口才写**的文件。而 `ChannelBinding` 是 authoritative，
它的答案会**顶掉** `ReleaseChannel.detect()`。

关键是 detect() 对 CapCut 帮不上忙，这条是挂载真包量出来的：

| dmg | `CFBundleShortVersionString` | `CFBundleVersion` | `Channel Name` |
|---|---|---|---|
| `CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg` | `9.3.0` | `9.3.0` | `capcutpc_0` |
| `CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg` | `9.3.4531` | `9.4.0-beta4` | `capcutpc_beta` |

`AppScanner` 喂给 `detect()` 的是 **short** version，beta 那份是 `9.3.4531` ——
**没有任何 channel 词**，`-betaN` 规则根本不触发。bundle id、app 名、app 文件名两轨也
完全一样。所以 `CapCutChannel` 不是「最好的信号」，它是**唯一的信号**；没记录时答
stable 会把一台装了 beta、没开过更新窗口的机器打成 Stable，然后用 stable 配方报一个
比它正在跑的还旧的版本，永远。

三态：`joinBeta=true`→beta；`joinBeta=false`（用户显式退出）→stable；
**没记录**→镜像 `tea_channel`。不认识的值（拼写变了）算「没记录」，不算显式退出。

没覆盖的角落：一份**从没启动过**的 beta 包两个文件都没有，会读成 stable 直到首次运行。
补它要读 bundle 里的 `PackageConfig.plist`，而 `ChannelBinding.resolve(bundleID:)`
拿不到 app 路径。

## 更新检测

端点是从二进制里还原的，不是猜的：

- `libSettings.dylib` 的 `SettingsRequest.cpp` 里有 query 拼接串
  `?device_platform=&channel=&aid=&version_code=&rom_version=&iid=&did=…`；
- `libVECreator.dylib` 里有 app id `359289`；
- `~/Movies/CapCut/User Data/Config/channel` 给出 channel token。

```
https://editor-api.capcutapi.com/service/settings/v3/
    ?aid=359289&device_platform=mac&channel=capcutpc_0&version_code=9.99
```

匿名可打，不需要 did/iid，不需要 mssdk 签名。返回 ~400 KB 配置，其中：

```json
"update_reminder": {
  "lastest_stable_url":  "…/CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg",
  "lastest_url":         "…/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg",
  "lastest_sync_url":    "…/CapCut_9_3_5-beta1_4468_capcutpc_beta_creatortool.dmg",
  "update_url":          "…/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg",
  "lastest_stable_version": 590592, "lastest_version": 590848,
  "lastest_beta_number": "4", …
}
```

### 三个坑

**1. `update_url` 是按设备灰度的选择，两轨都不能读。** 同一个 key，本机 CapCut 缓存
（`~/Movies/CapCut/User Data/MMKV/settings_json`）里是 **stable 9.3.0**，匿名请求里是
**beta 9.4.0-beta4**。`lastest_*` 两轨字段在两份里逐字节相同 —— 这也是「匿名探测拿到的
是不是和 app 同一个世界」的两证人核对。

**2. `lastest_sync_url` 是同一对象里第三个 `capcutpc_beta` 包，且 build 更旧**
（4468 < 4531），在 JSON 里还排在 `lastest_url` 前面。beta pattern 必须锚 key。

**3. `version_code` 是必填，而且它选灰度桶。** 其余参数固定，实测：

| version_code | 结果 |
|---|---|
| `0.0.1` · `8.0.0` · `9.0.0` · `9.3.0` · `9.4.0` · `9.5.0` · `9.9` · `9.99` | beta = 9.4.0-beta4（当前桶）|
| `1.0.0` · `2.0.0` · `5.9.0` | beta = 9.3.5-beta1（旧桶）|
| `9` · `10.0.0` · `99.9.9` · `9.999.999` · 空 · `x` | 没有 `update_reminder` |

stable 字段在**所有能应答的取值下都是 9.3.0**，所以只有 beta 轨暴露在这条上。
配方钉 `9.99`：它高于厂商发过的任何 9.x，所以留在最新桶而不会老化进旧桶（旧桶是唯一
**静默**错的方向）；掉出窗口（CapCut 进 10.x，或厂商收窄区间）则是 pattern 匹配不到 →
`versionPatternNoMatch`，`duo verify` 会报。

**两段而不是三段也是承重的**：`RecipeSanity` 会对「抽出的版本逐字出现在请求 URL 里」
报警（那是 pattern 匹配到 query 而不是 body 的迹象）。CapCut 版本恒为三段，所以两段的
`version_code` 结构上不可能等于任何一个答案。

**钉 `9.99` 的另一个副作用，记下来**：它拿到的配置和真实版本**不是一个世界**——
`version_code=9.3.0` 返回 383 个顶层 settings 键，`9.99` 返回 **777** 个
（多出来的里就有 `mac_update_enable`）。我们只读 `update_reminder` 的两个 URL 字段，
而那两个字段在两种取值下**逐字节相同**（复核过两次），所以当前无害；但这说明 9.99 落在
一个「未来/内部」桶而不是普通客户端桶，任何以后想从这个响应里多读字段的改动，都必须
重新核对该字段在真实 version_code 下是否一致。

### 版本方案：两轨字段是反的

```
stable → versionIsBuild: false   (short = version = 9.3.0)
beta   → versionIsBuild: true    (short = 9.3.4531, version = 9.4.0-beta4)
```

版本从**包名**抽（`lastest_*_version` 是 nibble-packed 整数，`590592 = 0x090300`，
正则解不动），每段一个 capture group，`extractVersion` 用 `.` 拼回去；`_4490_` build
计数器匹配掉不要。

beta 那条如果照抄 stable 用 `versionIsBuild: false`，引擎会拿 `9.4.0-beta4` 去比
beta 装机的 marketing `9.3.4531` —— 第二段 4 > 3 —— **正在跑着 beta4 的用户会被永远
劝装 beta4**。改成比 `CFBundleVersion` 才相等。

stable pattern 的第三段止于数字（Canva 那条教训）：万一预发被误推进
`lastest_stable_url`，一个都不匹配、降级 unknown，而不是把预发当正式版报。

## 增量更新（delta / diff patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | **有** | **无** | **不能（缺管道，非缺机制）** |
| 证据 | `libVECreator` 字符串 + 内嵌 Sparkle 2.7.0 的 `Autoupdate` | 2026-08-27 打真实端点，4 个 version_code 全无 | `DeltaApplier` 现成，缺「从 JSON 取补丁 URL」 |

- 格式：**极可能是 Sparkle binary delta**（推断，见下，未见过真补丁）
- 阻塞项：①厂商不发 ②钉死的 `version_code=9.99` 匹配不到 from→to 映射 ③取 URL 的管道

三层展开：

**1. CapCut 自己有完整的增量路径**（`libVECreator.dylib` 实测字符串）：

| 证据 | 含义 |
|---|---|
| `UpdatingModel::startRunUpdateDiffPatch` | 打补丁的入口 |
| `update.delta` / `/update.delta`（与 `update.dmg` 并列） | 补丁产物文件名 |
| `cfg.diff_url=%s` / `cfg.diff_md5=%s` | 每个 release 可带补丁 URL + md5 |
| `diff_update.enable` / `.enable_fallback_try` / `.fallback_try_count` | 灰度开关 + 失败回退整包 |
| `diff_update.package_version_mapping` | **补丁按 from→to 版本映射** |
| Sparkle 侧 `installerDidFailToApplyDeltaUpdate` | 失败回调 |

> **`diff_url` / `diff_md5` 是哪来的，说清楚**：它们是**二进制里的日志格式串**
> —— `libVECreator.dylib` 中 `updatecontroller.cpp` 的字符串池里有
> `(%s:%d,%s) cfg.diff_url=%s` 和 `cfg.diff_md5=%s`，紧挨着 `cfg.url=%s` /
> `cfg.version=%X`，即 CapCut 在打印自己 `ReminderUpdateCfg` 结构体的字段。
> **不是从任何响应里看到的**，是客户端「有这个能力」的证据，不是「服务端在发」的证据。
>
> 而且我原来那句「`update_reminder` 里没有 `diff_url`」**找错了地方**：二进制里
> 登记的 `update_reminder.*` 键一个带 diff/patch/delta 的都没有，它本来就不会出现在
> 那里。真正的来源应该是另一个顶层键 `diff_update`（二进制里有
> `diff_update.enable` / `.enable_fallback_try` / `.fallback_try_count` /
> `.package_version_mapping`，旁边还有 `macos` 和 `download_md5`）。

**2. 但端点现在一个补丁都不发 —— 这条换成不依赖我猜结构的证据。**
2026-08-27，`version_code` = 9.2.0 / 9.3.0 / 9.3.5 / 9.99 各打一次：

- 响应的 settings 是**扁平非点号**结构（383 个顶层键里含 `.` 的为 **0**），所以二进制里的
  `diff_update.enable` 对应的是顶层 `diff_update` 对象 —— 查这个键是对的；
- 顶层 **`diff_update` 不存在**；
- 对**整个原始响应体**暴力扫一遍：所有匹配 diff/delta/patch 的键全是无关的
  （`draft_size_diff`、`material_template_diff`、`update_download_material_patch_diff`、
  `effectab_enable_metal_flip_patch`、网络 `dispatch_*`…），没有一个是 app 更新补丁；
- 响应体里**没有任何 `.delta` / `.patch` / `.diff` 结尾的 URL**。

即厂商当前对谁都发整包。

**3. 格式极可能就是 Sparkle 的，也就是我们已经能施加的那种。**
CapCut 内嵌的是**原版 Sparkle 2.7.0（build 2044）**，它的 `Autoupdate` 里带着完整的
delta applier：

```
BinaryDelta · SUBinaryDeltaUnarchiver · SUBinaryDeltaCommon.m · /usr/bin/bspatch
sparkle:deltaFrom · sparkle:deltaFromSparkleExecutableSize
"This patch version (%u.%u) is too old and potentially unsafe to apply…"
```

而 `libVECreator` 这边实现了 Sparkle 自己的 `installerDidFailToApplyDeltaUpdate`
回调，并且用 `initWithAppcastItem:secondaryAppcastItem:downloadBookmarkData:downloadToken:`
构造更新 —— **`secondaryAppcastItem` 就是 Sparkle 的 delta 槽位**。

我们这边 `DeltaApplier` 直接 ship 并调用 Sparkle 的 `BinaryDelta` 可执行文件
（格式 v3，Sparkle 2.1 起），所以**施加器是现成的、对得上的**。

> **标注：这是推断不是实证。** 端点当前一个 `.delta` 都不发，所以没有任何一个真补丁被
> 检查过。要坐实得等厂商开灰度、或抓到一个 `diff_url`。
> （我第一版把这条写成了「格式不是 Sparkle 的、要接是新机制」，是错的 —— 那是没查
> Sparkle framework 就下的结论。）

**4. 真正卡住的是我们的请求，不是格式。** 两条：

- 缺的是**管道不是机制**：`VendorAppcastDeltas` 只会从 appcast 的 `<sparkle:deltas>`
  里取补丁 URL，而 CapCut 会把它放在 JSON 的 `diff_url`（配 `diff_md5`）。
  要接是「多一个取 URL 的来源」，不是重写 applier。
- **`package_version_mapping` 是按 from→to 键的，而配方钉的 `version_code=9.99`
  是个不存在的版本** —— 这个请求永远匹配不到任何补丁映射。这是我钉假版本号的代价，
  当时只权衡了「灰度桶 + `RecipeSanity` 不误报」，没想到它同时把增量这条路堵死了。
  今天不损失（反正没补丁），但要恢复得让请求带**装机真实版本**，而现在没有任何 recipe
  字段能把装机版本塞进 URL。

结论：现在**不接**增量，代价是每次 1.24 GB 整包。真要接，顺序是
①等厂商真的发 `diff_url` → ②解决「把装机版本送上 wire」→ ③给取补丁 URL 加一条 JSON 来源。
施加和验证都不用新写（补丁产出的 bundle 照样过签名/Team/bundle id 三道闸）。

## Changelog

**没有接。** `update_reminder` 里确实带 `lastest_stable_update_content` /
`lastest_update_content`，但三轨内容完全一样、且是一句套话
（"Fixed some known issues and improved the trimming experience."）。
capcut.com 也没有桌面端 release notes 页：`/release-notes`、`/whats-new`、
`/support/release-notes` 全部 502。所以 `changelogURL` 留空，UI 显示 "no release notes"。

## 一键安装

- 状态：**两轨都已启用**，`kind: .dmg`。
- 产物：各自 `update_reminder` key 里的绝对 URL，主机钉死
  `sf16-web-tos-buz.capcutstatic.com`，文件名钉死自己的 `capcutpc_<token>`。
- **为什么 `.dmg` 而不是 `.pkg`**：两个真 dmg 挂载后都只有 `CapCut.app` +
  `Applications` 软链 + 背景图，没有 pkg、没有
  `LaunchDaemons`/`LaunchAgents`/`PrivilegedHelperTools`，本机跑过 CapCut 也没有任何
  launch item。Homebrew cask 独立佐证：`artifacts` 是 `{"app": ["CapCut.app"]}`，
  `uninstall` 只有 `quit`，`zap` 只清用户数据。换 bundle 就是完整更新。
- **cask 还是 stable URL 的第二个证人**：它指向的就是配方从 settings blob 里解出来的
  同一个 `…CapCut_9_3_0_4490_capcutpc_0_creatortool.dmg`。
- **没有 checksum 闸**：厂商给的是 `*_url_md5`（MD5），`checksumPattern` 吃的是
  base64 SHA-512，喂不进去。强制闸只剩 Team ID —— 但那本来就是必过的那道。
- 强制闸（`VendorInstaller`）：Developer ID 签名 + Team `22MMUN2RN5` + bundle id 一致。
  两个渠道的真实 dmg 都已核对（`codesign` + `spctl -t install`），并且**生产路径实跑过**
  （见下）。
- **`hostRequirement` = Apple silicon**：`lipo -archs` 对启动器、`libVECreator.dylib`、
  `CapCut Helper.app` 一律只报 `arm64`，而厂商只发一个 dmg。厂商 schema 里其实有
  `lastest_stable_cpu_architecture` / `lastest_cpu_architecture`（在二进制字符串池里），
  但响应里不带 —— 即当前一份产物发给所有人。不加这道闸的话，一台装着旧 CapCut 的 Intel
  Mac 会被永久报「有更新」，然后拿到一个 `SignatureVerifier` 架构闸只可能拒绝的一键。
  **历史上有没有过 Intel 轨，本次没有查实**；真出现了就照 Raycast 那种双端点拆法改。
- **成本**：每次安装 ~1.24 GB 下载。registry 的实网签名闸测试
  （`vendorDownloadPassesSignatureGate`）跑的是一份小产物白名单，加这条不会把 1 GB
  塞进 `make test`。

### 生产路径实跑

把 `com.lemon.lvoverseas` 临时加进 `vendorDownloadPassesSignatureGate` 的白名单跑了一次
（跑完已还原）。本机 `joinBeta=true`，所以走的是 beta 轨：

```
=== signature-gate check: CapCut (com.lemon.lvoverseas) ===
download: https://sf16-web-tos-buz.capcutstatic.com/obj/capcut-web-buz-sg/packages/CapCut_9_4_0-beta4_4531_capcutpc_beta_creatortool.dmg  [dmg]
Team ID  installed: 22MMUN2RN5  downloaded: 22MMUN2RN5
✅ gate passed — would swap safely (no swap performed)
```

即：生产 downloader 真的下了 1.24 GB、真的挂载解包、`SignatureVerifier` 真的过闸。
stable 轨没走这条 harness（本机 channel 解析成 beta），但同一 Team、同一形状，
`codesign` / `spctl` 已单独核过。

### Channel proof

`ChannelProofKey("com.lemon.lvoverseas", .beta)` → `.artifact(#"_capcutpc_beta_"#)`。

不是从文件名习惯推的：`capcutpc_beta` 是挂载 beta dmg 后从它自己的
`Contents/Resources/PackageConfig.plist` → `Channel Name` 读出来的厂商 token。

## 已知问题 / 取舍

- **我们会比 CapCut 自己的灰度更早给 beta。** `joinBeta` 是用户的 opt-in，而厂商在
  `update_url` 上还做了按设备灰度。本机 2026-08-27 `joinBeta=true`、CapCut 自己说
  "You are using the latest version"（它拿到的 `update_url` 是 stable 9.3.0），而
  beta 轨最新是 9.4.0-beta4。配方读的是轨道最新而不是按设备的选择 —— 这是「beta 渠道」
  的诚实读法，也是不把本机 ByteDance device id 发出去的唯一读法。
- **`downloadURL`（手动兜底）两轨都指向官网桌面页，而那页只发 stable stub。**
  一键接上之后它退化成兜底而不是主路径；替代方案 `nil` 会回落到 `recipe.url`，等于把
  ~400 KB 内部 settings blob 放到用户可见链接后面。厂商没有任何公开 beta 下载入口。
- **beta 的 marketing 版本 `9.3.4531` 会显示在行里**，因为那就是 bundle 自报的。
- 一份从没启动过的 beta 包会被读成 stable，见上。

## 建议下一步

1. CapCut 进 10.x 时 `version_code=9.99` 会掉出窗口 —— 那天 `duo verify` 会报
   `versionPatternNoMatch`，改成新的两段值即可。
2. 若哪天出现可核实的桌面端 release notes 页，补 `changelogURL`。
3. 若要给 brew 装的 CapCut 修那个 `9.3.0.4490` vs `9.3.0` 的幽灵形状，那是
   `HomebrewCaskSource` 的事，不是这条配方的事。
