# Channel 覆盖账本

多 channel（beta/dev/canary/nightly/preview/esr/…）的覆盖全景。

> **重建 2026-06-04**（`channel-discovery` skill 试跑产出）。原文件被手动删除后从
> **代码这个权威源头**重新生成。
> - **§1 已覆盖** = 直接从 `VendorProbeRecipe.swift` / `GitHubReleasesSource.swift` /
>   `*Channel.swift` 提取，是当前真实状态（非记忆）。
> - **§2 TODO / §3 死轨** = 结转自删除前的同日调查（2026-06-04 web 搜索 + 实测）；
>   死轨是**已否决项，不要重新调查**（`channel-discovery` 安全规则 4）。
>
> 落地任一条仍须按 `fragile-recipe` 在**真实响应**上验证，多 channel 须 `channel-verify`
> 真机跑绿才算 ✓（见 `app-audit` Phase 3¾）。两类注册位：
> **probe** = `VendorProbeRecipe`（带 `channel:`，源拒跨 channel）；
> **changelog** = `ChangelogRecipe`；**binding** = `ChannelBinding` + `<App>Channel.swift`。

---

## §1 已覆盖（从代码提取，权威）

- **Yaak**（2026-09-06）：stable/beta 共享 `app.yaak.desktop`，真包保留 `-beta.N` 后缀，GitHub 两轨及结构化日志已接；stable 一键升级实测通过。见 [审计](docs/app-audits/app-yaak-desktop.md)。


### Pattern A — 独立 bundle id（各 channel 自带身份，最干净）

| Family | 非 stable channel → bundle id | 源 |
|---|---|---|
| **Chrome** | beta `com.google.Chrome.beta` · dev `.dev` · canary `.canary` | VendorProbe |
| **Edge** | beta `com.microsoft.edgemac.Beta` · dev `.Dev` | VendorProbe（canary 受阻，见 §2） |
| **Firefox** | dev-edition `org.mozilla.firefoxdeveloperedition`（RemotingName `firefox-dev`）· nightly `org.mozilla.nightly` | VendorProbe |
| **Thunderbird** | beta `org.mozilla.thunderbirdbeta` · nightly `org.mozilla.thunderbird-daily` | VendorProbe |
| **Warp** | preview `dev.warp.Warp-Preview` · dev `dev.warp.Warp-Dev` | VendorProbe |
| **Signal** | beta `org.whispersystems.signal-desktop-beta`（显示名 "Signal Beta"）| VendorProbe |
| **Element** | nightly `im.riot.nightly`（2026-06-04 修了误写的 `io.element.nightly`）| VendorProbe |
| **Discord** | ptb `com.hnc.DiscordPTB` · canary `com.hnc.DiscordCanary` | VendorProbe |
| **HBuilderX** | alpha `io.dcloud.HBuilderXAlpha` | VendorProbe |
| **Zed** | preview `dev.zed.Zed-Preview`（`channel: .preview`，2026-06-04 修 channel-gate 回归）| GitHub |
| **Termius** | beta `com.termius-beta.mac`（issue #91，2026-08-27）| VendorProbe |

### Pattern A\* — 共享 bundle id，但 Mozilla `RemotingName` 可检测

Firefox/Thunderbird 的 beta/esr 与 stable **共用 bundle id**，靠 `Contents/Resources/
application.ini` 的 `RemotingName`（baked per-channel）区分——`ReleaseChannel.detect()`
的最高优先信号。版本号的 `b`/`esr` 后缀在安装版被剥掉，**不能**用来检测。

| channel | bundle id | RemotingName |
|---|---|---|
| Firefox beta | `org.mozilla.firefox`（共享）| `firefox-beta` |
| Firefox esr | `org.mozilla.firefox`（共享）| `firefox-esr` |
| Thunderbird esr | `org.mozilla.thunderbird`（共享）| `thunderbird-esr` |

### Pattern A\* — 共享 bundle id，但 app 自带文件里写着渠道（非 ChannelBinding）

`RemotingName` 的同构做法：渠道烤进 bundle 里一个不用启动就能读的文件，
`AppScanner` 在扫描时读出来。与 Pattern B/C 的区别是**这不是用户偏好，是构建产物**。

| App | 磁盘 bundle id | 登记 id | 读的文件 → 信号 |
|---|---|---|---|
| **微信开发者工具** | 2.02 `com.github.Electron`（Electron 出厂默认，三渠道相同）/ 2.01 `com.tencent.webplusdevtools` | `com.tencent.wechatdevtools` | `Resources/app.asar.unpacked/package.json`（2.01 是 `package.nw/`）→ `versionType` 0/1/2 = stable/rc/nightly |

Info.plist 在 2.02 上**完全不可用**（版本是 Electron 的 `36.6.0`），所以这个 app 的
版本号也一起从 `package.json` 取。三渠道共用一个 `config.json` 端点，各自锚 `"id"`。

### Pattern B/C — 共享 bundle id + app 内开关写的本地信号（ChannelBinding）

这就是"app 内切换渠道"已做成的 6 个。每个读一个具体偏好/凭证：

| App | bundle id（共享）| 读的信号 | 门控方式 |
|---|---|---|---|
| **Fork** | `com.DanPristupov.Fork` | `applicationUpdateChannel` | feed-swap（`feed.xml` ↔ `feed-stable.xml`）|
| **Surge** | `com.nssurge.surge-mac` | `IncludeBetaBuilds` | feed-swap（`appcast-signed.xml` ↔ `-beta.xml`）|
| **TablePlus** | `com.tinyapp.TablePlus` | `IsReceiveBetaBuild` | header 注入（`X-Tiny-Beta-Update`）|
| **DuoPaste** | `io.duopaste.daemon` | `sparkleIncludePrereleases` | channel-tag |
| **OrbStack** | `dev.kdrag0n.MacVirt` | `updates_optinChannel`(=`beta`) | channel-tag |
| **CleanShot X** | `pl.maketheweb.cleanshotx` | `activationKey` | license-keyed legit feed（`legit.maketheweb.io/api/v1/appcast`）|

### Pattern B/C 续 — Tailscale（2026-06-06 接 unstable）

- **Tailscale** `io.tailscale.ipn.macsys` — stable + unstable 两轨都接。unstable 经
  `TailscaleChannel` 读 UserDefaults `UnstableUpdatesEnabled`(Bool)→ `.unstable`(新增
  枚举)，channel 门控路由到 `pkgs.tailscale.com/unstable` probe。`pkgs.tailscale.com/rc`
  **404**（无第三消费轨，已否决）。stable/unstable changelog 共用 tailscale.com/changelog。

### Pattern B/C 续 — CapCut（2026-08-27 接 beta）

- **CapCut** `com.lemon.lvoverseas` — 「Version update」窗口里的 **"Get early access to
  beta features"** 复选框。信号**不在 UserDefaults 也不在沙盒容器里**：CapCut 是沙盒 app
  （域在 `~/Library/Containers/com.lemon.lvoverseas/Data/Library/Preferences/`），但两个
  plist 都没有这个键；Qt 把它写进容器外的 INI —— `~/Movies/CapCut/User Data/Config/
  updateInfo` 的 `[General] joinBeta=true`。同目录 `globalSetting` 的 `enableAutoUpdate`
  是**另一组**单选（自动装 vs 只通知），不是渠道，别读错。
- 装机侧还有一个只读的构建标记：`Contents/Resources/PackageConfig.plist` →
  `Channel Name`（stable 装机实测 `capcutpc_0`，beta 包名里是 `capcutpc_beta`）；
  CapCut 自己把它抄进同目录的 `channel` 文件（`tea_channel=capcutpc_0`），所以不用
  找 bundle 路径也能读到。**只在 `joinBeta` 完全没记录时**才用它兜底 —— binding 是
  authoritative、会顶掉 `ReleaseChannel.detect()`，而 detect() 对 CapCut **不是**空
  操作（beta 版本号带 `-betaN`，step 4 本来就判 `.beta`）；没记录就答 stable 会把一台
  从没开过更新窗口的 beta 机器降级成 stable 并藏掉它的更新。`joinBeta=false`（用户显式
  退出）仍然答 stable。
- 门控方式 = channel-gated VendorProbe（无 feed-swap：CapCut 内嵌 Sparkle 只负责装，
  没有 `SUFeedURL`，更新决策来自 ByteDance Settings SDK 的 `update_reminder.*`）。
  两轨同一个匿名端点：`editor-api.capcutapi.com/service/settings/v3/`
  （`aid=359289&device_platform=mac&channel=capcutpc_0&version_code=9.99`，四个参数缺一
  就没有 `update_reminder`）。stable 读 `lastest_stable_url`、beta 读 `lastest_url`，
  版本从包名的 `CapCut_9_3_0_4490_capcutpc_0_…` 里按段抽再用 `.` 拼。
- 三个坑记在 `VendorProbeRecipe.swift` 的注释里：`update_url` 是**按设备灰度**的选择
  （本机缓存里是 stable、匿名请求里是 beta，两轨都不能读它）；`lastest_sync_url` 是同一
  对象里**第三个** `capcutpc_beta` 包且 build 更旧；`version_code` 会选灰度桶（实测
  `1.0.0` 落到旧桶、`10.0.0` 直接没有 `update_reminder`）。
- **两轨版本字段是反的**（挂载真包量的）：stable 的 short=version=`9.3.0`；beta 的
  short=`9.3.4531`（没有任何 channel 词）、version=`9.4.0-beta4`。两个后果：
  (a) `detect()` 拿的是 short，对 beta 装机**判不出 beta**，所以 `CapCutChannel` 是唯一信号；
  (b) beta 配方必须 `versionIsBuild: true`，否则 `9.4.0-beta4` 比 `9.3.4531` 永远更新，
  正在跑 beta4 的人会被无限劝装 beta4。
- **两轨一键都已接**：`kind: .dmg`，`hostRequirement` = arm64（实测 `lipo` 只有 arm64，
  厂商只发一份产物），Team `22MMUN2RN5` + notarized（两个真实 dmg 都核过，beta 轨还跑过
  一次生产 `vendorDownloadPassesSignatureGate`：真下载 1.24 GB、真解包、真过闸），
  dmg 里只有 `CapCut.app` + `/Applications` 软链，无 pkg / 无 launch item（brew cask
  的 `{"app": ["CapCut.app"]}` + 只 `quit` 的 uninstall 是第二证人）。厂商只给 MD5，
  `checksumPattern` 吃 base64 SHA-512，故未武装 checksum，Team 闸兜底。每次 ~1.24 GB。
- `ChannelProofRegistry` 已登记 beta：`.artifact(#"_capcutpc_beta_"#)` —— token 是从
  beta dmg 自己的 `PackageConfig.plist` 读的，不是照文件名习惯推的。
- 同 bundle id 还有一份 **MAS 副本（adamId 1500855883，版本 19.2.0）**，版本方案完全不同；
  两边不串全靠 `_MASReceipt`（`VendorProbeSource` 拒 MAS、`MacAppStoreSource` 拒非 MAS）。

### Pattern A 续 — VS Code Insiders（2026-06-06 接）

- **VS Code Insiders** `com.microsoft.VSCodeInsiders`（显示名 "Code - Insiders" → detect
  读独立词 "Insiders" → `.preview`）。probe 走 `update.code.visualstudio.com/.../insider/
  latest`，**版本必须连 `-insider` 后缀一起抽**(`1.124.0-insider`，否则永远幽灵更新)；
  `name` 仅月度 minor 跳号(每日构建只换 commit hash，Info.plist 不暴露)→ 月度粒度，
  Insiders 本就每日自更新。一键 = zip 就地换(同 stable)。本机已装、harness ✓。

### Android Studio Preview — Canary + Beta（2026-06-06 接，§2 旧条已落地）

- **Android Studio** Canary/Beta 与 Stable **全部共享** `com.google.android.studio`、
  CFBundleName 全是 "Android Studio"、marketing 版截断成 "2026.1"——唯一 channel 信号是
  **bundle 文件名**(brew-cask 重命名 "… Preview Canary/Beta"，Stable 留 "Android Studio")。
  `ReleaseChannel.detect` step 0.5 对该 id 专属读文件名(canary>beta>preview 优先，绕开
  channelWord 把 preview 排在 beta 前的坑)；裸 dmg "Android Studio Preview.app" → `.preview`
  → 无配方 → 安全跳过(不会被误推 stable)。两条 VendorProbe 走官方 releases-list JSON
  (`jb.gg/android-studio-releases-list.json`)，**比 `build` 字段**(`AI-261.…`，与装机
  CFBundleVersion 逐字符相同；marketing 截断无法比)`versionIsBuild:true`；Beta 轨当前发 RC，
  故接受 channel `Beta|RC`、文件名 `beta|rc`。修了原 §284 错注释(曾称 Canary 被跳过，实为
  误判 .stable 的潜在跨轨覆盖 bug)。两轨本机已装、harness ✓。

---

## §2 TODO — Pattern A 未覆盖（可做，独立 bundle id）

> 候选已于 **2026-06-04 用 `brew info --cask` 实测复核**（时效性：cask 名/版本会变）。

- [x] **VS Code — Insiders** ✓（2026-06-06 接，见 §1）。bundle id 实测为
      `com.microsoft.VSCodeInsiders`（如预期）；版本带 `-insider` 后缀是关键陷阱。
- [x] **Android Studio — Canary + Beta** ✓（2026-06-06 接，见 §1）。实测 bundle id 是
      **共享的 `com.google.android.studio`**（非旧记的 `-EAP`），改用 bundle 文件名检测 +
      releases-list JSON 的 `build` 字段比对。
- [ ] ~~**Edge — Canary**~~ · `com.microsoft.edgemac.Canary` —— **受阻**：
      `edgeupdates.microsoft.com/api/products?view=enterprise` 只列 Stable/Beta/Dev，
      不含 Canary（Canary 走 EdgeUpdate/Omaha，无公开企业 JSON）。暂搁。

### 2026-06-06 渠道扫描新增 — Pattern A

- [x] **Brave Browser — Beta** · `com.brave.Browser.beta`（独立 app：`Brave Browser Beta.app`）
      Sparkle feed `updates.bravesoftware.com/sparkle/Brave-Browser/beta/appcast.xml`，
      版本号 `1.92.x`，已验证 brew cask `brave-browser@beta` 存在。
      VendorProbe 已接入（`channel: .beta`，`sparkle:shortVersionString` attribute 提取 4-part 版本）。
- [x] **Brave Browser — Nightly** · `com.brave.Browser.nightly`（独立 app：`Brave Browser Nightly.app`）
      Sparkle feed `updates.bravesoftware.com/sparkle/Brave-Browser/nightly/appcast.xml`，
      版本号 `1.93.x`，已验证 brew cask `brave-browser@nightly` 存在。
      VendorProbe 已接入（`channel: .nightly`，同 Beta 模式）。
- [x] **Vivaldi — Snapshot** · `com.vivaldi.Vivaldi.snapshot`（独立 app：`Vivaldi Snapshot.app`）
      Sparkle feed `update.vivaldi.com/update/1.0/snapshot/mac/appcast.xml`，
      已验证 brew cask `vivaldi@snapshot` 存在。
      VendorProbe 已接入（`channel: .preview`，`ReleaseChannel` 新增 `snapshot` → `.preview` 映射）。
      测试通过。

---

## §2b TODO — Pattern B/C 候选（app 内切换，需真机验证信号）

- **CotEditor**（2026-09-06）：已补隐藏 Sparkle 地址及 stable/beta 结构化日志，stable 一键升级实测通过。仍需接入 `checksUpdatesForBeta || Bundle.main.version.isPrerelease`，对应 feed 标签 `prerelease`；当前依赖 feed 中已知 build 推断，旧 beta 被裁掉后退回 stable。见 [审计](docs/app-audits/com-coteditor-CotEditor.md)。


> 以下 app 有明确 in-app channel toggle，但切换后是否留下可读的本地信号（defaults/plist）
> 仍需真机 diff 确认。不要直接标为 detectable。

- [x] **IINA** · `com.colliderli.iina` — Preferences → General → **"Receive beta updates"**
      checkbox。源码确认 UserDefaults key 为 `receiveBetaUpdate`（Bool，默认 false）。
      真机验证：切换后 `defaults read com.colliderli.iina receiveBetaUpdate` 返回 `1`。
      已接入 `IINAChannel`（feed-swap：stable `appcast.xml` ↔ beta `appcast-beta.xml`），
      注册到 `ChannelBinding`，测试通过。

- [x] **Carbon Copy Cloner** · `com.bombich.ccc` — Settings → Software Update →
      **"Inform me of beta releases"** checkbox。**已接入（2026-08-29，见
      `docs/app-audits/com-bombich-ccc.md`）**——此前记为"阻塞，需人工抓包"，实际
      不需要：`download_ccc.php?v=latestbeta`（**无连字符**，之前只试过 `?v=beta` 和
      `?v=latest-beta`）就直接 302 到真实 beta 构件
      （`ccc-7.1.7-b7.8389.zip`），跟 stable 同构。真机验证过下载并展开的真实 zip
      （`CFBundleShortVersionString="7.1.7-b7"`，Team `L4F2DED5Q7`，与 stable 一致，
      已公证）。channel 信号是版本串的短 `-b<N>` 后缀，`ReleaseChannel.detect()` 新增
      按 bundle id 限定的 step 0.8。两 channel 均仅检测，未接一键（装机带特权
      helper/LaunchDaemon/XPC，一键是独立范围决策）。

- [ ] **WhatCable** · `uk.whatcable.whatcable` — Settings → **"Receive beta updates"**
      checkbox。**版本检测这一半已经不需要它**：beta 包的
      `CFBundleShortVersionString` 原样带 `-beta.8`（实测 v1.5.0-beta.8 的
      Info.plist），`ReleaseChannel.detect()` 第 4 步就判成 `.beta`，两条 GitHub rule
      已于 2026-09-06 接入（见 `docs/app-audits/uk-whatcable-whatcable.md`）。
      **剩下的缺口是一格，但有两条路走进去**：(1) 跑 **stable** 构建却把开关打开的用户，
      厂商自己的更新器会给他 beta，我们只给 stable；(2) 更要紧的是，跑 beta 的副本一旦接受
      我们提供的「毕业版」stable，`detect` 就判它 `.stable`，从此由 stable rule 服务——
      **是 DuoUpdater 自己把他送进第 (1) 格的**。（厂商的更新器会把他带回去，所以不是死路，
      但那是靠别人的软件兜底。）UserDefaults key 是 `receiveBetaUpdates`
      （app 源码 `Sources/WhatCable/App/AppSettings.swift`，注释自陈关掉时
      "keeps hitting releases/latest, which GitHub never returns a pre-release from"）
      —— **未做真机 diff 确认落盘行为**，按本节规矩不得直接当作 detectable。
      补法是一个 `ChannelBinding`，形状同 `IINAChannel`。

- [ ] **Docker Desktop — nightly** · `com.docker.docker` — UI 的更新设置代码里存在受
      feature flag 控制的 `useNightlyBuildUpdates`；观测 stable bundle 只给出 `channelID=main`，
      backend 使用 `desktop.docker.com/mac/main/arm64/appcast.json`。尚未取得真实 nightly
      构件，也未验证开关落盘后的本地信号和 endpoint，故暂不登记为 detectable。不要从嵌套
      `Docker Desktop.app` 的 Squirrel 推断渠道：实际更新器是外层
      `com.docker.backend.updater`（见 `docs/app-audits/com-docker-docker.md`）。

---

## §2c 扫描 2026-08-27（CapCut 落地后复扫）

**方法**（复现用，别凭记忆重列一遍）：

1. 已覆盖集从**代码**再生成，不信本账本 —— `python3` 配对 `VendorProbeRecipe.swift` /
   `GitHubReleasesSource.swift` 里的 `bundleID:`→`channel:`，加 `*Channel.swift` 的
   `bundleID`。结果：VendorProbe 116 个 id / 32 个带非 stable channel；GitHub 67 / 4；
   ChannelBinding 12 个 app。
2. 本机 138 个 app 逐个读 `Info.plist` 取 bundle id，减去已覆盖 → 121 个候选池。
3. Homebrew **全量** cask API（7712 条）里找 `@beta|@nightly|@dev|@canary|@preview|
   @insiders|@alpha|@rc|@snapshot` 变体（129 个 base），与本机安装交集 → 16 个。
4. **本机 preferences 全扫**（`~/Library/Preferences` + 沙盒容器 + Application Support，
   顶层键与嵌套键两遍）找已经写下渠道信号的域。

### 最重要的是一条阴性结论

**第 4 步在未覆盖的 app 里一个新的 B/C 信号都没扫到。** 命中的只有已覆盖的
`com.netease.uuremote`（`channel=gwqd`）和自家 `ClaudeUsageMenuBar`（见下）。
其余全是误报（`previewCorner`、`ImagePreviewTranslate*`、`KeyboardShortcuts_togglePreview`
这类 UI 键）。

意思是：**这台机器上「app 内拨开关 + 已留下可读信号」这口井基本打干了**。剩下的缺口不是
「还没找」，是「必须先装一份 beta 包才能回答」。

### ClaudeUsageMenuBar —— 查了，不是缺口

`com.jizhi0v0.claude-usage.menubar`，prefs 里有 `sparkleIncludePrereleases=true`
（DuoPaste 同款键），appcast 20 条 item **全部**带 `<sparkle:channel>beta</sparkle:channel>`、
零条无标签，装机版本 `0.3.384-beta.1440+fd58749`。

一度以为是缺口（`ReleaseChannel.detect()` 对 `-beta.NNNN+sha` 这种形状故意不判 beta，
所以会读成 stable）。**实测推翻**：`duo check --json` 显示 `source: Sparkle` /
`status: up-to-date` / latest == installed —— `SparkleAppcastSource` 会从**装机构建反推**
`<sparkle:channel>`，beta 条目没被滤掉。**不需要 ChannelBinding，勿重开。**

### Pattern A 未覆盖 —— 两个（`termius@beta` 已接，见 §1；VSCodium Insiders 已接，
见 issue #92、`docs/app-audits/com-vscodium-VSCodiumInsiders.md`）

| cask 变体 | 装出来的 app | 本机 stable |
|---|---|---|
| `postman@canary` | `PostmanCanary.app` | Postman 12.25.6 |
| `db-browser-for-sqlite@nightly` | `DB Browser for SQLite Nightly.app` | 3.13.1 |

→ 各自 `/app-audit`，但**都得先装一份对应渠道的包**才能拿到 bundle id 和版本方案，
否则只是猜。两个都不急。

### 同 bundle id + `@channel` cask —— 七个（渠道在**下载时**选，不是 app 内切）

`keepassxc`(@beta/@snapshot)、`keka@beta`、`kitty@nightly`、`telegram-desktop@beta`、
`utm@beta`、`vlc@nightly`、`freelens@nightly` —— cask 装出来是**同名 app**。

对检测而言，关键问题不是「有没有开关」，而是**「装上非 stable 包之后，bundle 里有没有
渠道标记」**（CapCut 的 `PackageConfig.plist` → `Channel Name` 就是这种标记，而它的
`CFBundleShortVersionString` 反而**不带**任何 channel 词）。这个问题**只有拿到真包才能
回答**，凭 cask 元数据答不了。

> 注意 `vlc@nightly`：VLC 的 stable 已在 VendorProbe 覆盖（`org.videolan.vlc`），
> nightly 是否同 id 未查。

### 2026-08-27 当天补完：九个非 stable 包全部下载实测

上面那句「只有拿到真包才能回答」当天就做了 —— 九个包全下下来挂载读了 `Info.plist`、
`codesign`、`spctl`，然后删掉。**结论和从 cask 元数据猜的很不一样**，逐条记下来。

| App | 非 stable 包 | bundle id | 本地渠道标记 | 签名 | 判定 |
|---|---|---|---|---|---|
| **Termius Beta** | `com.termius-beta.mac` 9.43.1 | **独立** | `CFBundleName`="Termius Beta" | Team `6KN952WR85` 公证 | **A，可接** |
| **VSCodium Insiders** | `com.vscodium.VSCodiumInsiders` 1.126.04518-insider | **独立** | app 名 + 版本后缀 | Team `VC39D2VNQ7` 公证 | **A，可接** |
| **DB Browser nightly** | 同 id 3.13.99 | 同 | **只有 app 文件名** `DB Browser for SQLite Nightly.app`（`CFBundleName` 仍是 "DB Browser for SQLite"）| Team `88DD6Y8X83` 公证 | **A-ish**，靠文件名，`detect()` 已有自己的 step 0.6（issue #94；不是复用 Android Studio 的 step 0.5）|
| **Freelens nightly** | 同 id `2.0.0-0-nightly-2026-08-26` | 同 | **版本串带 `nightly`** | Team `TFR6NT55MB` 公证 | 可接，但要给 `detect()` 加规则 |
| **VLC nightly** | 同 id `4.0.0-dev` | 同 | 版本串带 `-dev` | **未签名**（`TeamIdentifier=not set`）| 检测可做，**一键不可**（Team 闸必拒）→ 立项 #95，`docs/app-audits/org-videolan-vlc.md` |
| **KeePassXC snapshot** | 同 id `2.8.0-snapshot` | 同 | 版本串带 `-snapshot` | **无可用签名** | 同上；且该 URL 只有 x86_64（已核实无 arm64 替代路径）→ 立项 #95，`docs/app-audits/org-keepassxc-keepassxc.md` |
| **UTM beta** | 同 id 5.0.5 / build 124 | 同 | **本地无**；已安装版本的 exact GitHub release 有权威 `prerelease` 位 | Team `WDNLXAD4W8` 公证 | **已接**：远端判轨 + 线锚定候选 + 一键 + 分轨 changelog |
| **kitty nightly** | 同 id 0.48.2 | 同 | **无，版本与 stable 完全相同** | Team `NTY7FVCEKP` 公证 | **D** |
| **Postman Canary** | — | — | — | — | **死轨**：cask `disabled: true`，版本停在 `11.2.14-canary240621-0734`（2024-06），stable 已 12.25.6 |

**三个 cask 是假线索，别再当候选**：

- `keepassxc@beta` → 指向的就是 **stable 那个包**（2.7.12），退化成 stable 的别名。
  真正的预发轨是 `keepassxc@snapshot`（2.8.0）。
- `keka@beta` → 同样指向 stable 的 `Keka-1.6.7.dmg`。
- `telegram-desktop@beta` → 那是 **`Telegram Desktop.app`（tdesktop 7.1.2）**，和本机装的
  `ru.keepcoder.Telegram` 12.9（TelegramSwift）**是两个客户端**。后者的 `telegram` cask
  没有任何 `@beta` 变体。上一轮把它们配成一对是错的。

**另注**：VS Code Insiders（`com.microsoft.VSCodeInsiders`）**早已覆盖**，别和
VSCodium Insiders 混。两者 cask 分别是 `visual-studio-code@insiders` 和 `vscodium@insiders`。

### 从这九个包里学到的通则

**「同 bundle id」不等于「不可判」，得看标记落在哪一层**，实测出现了四种：

1. **独立 bundle id**（Termius、VSCodium Insiders）—— 最干净，detect 免费。
2. **只有 app 文件名带**（DB Browser）—— `CFBundleName` 不带，所以 `channelWord` 抓不到；
   要走 `detect()` step 0.5 那种按 bundle id 专属读文件名的路子。
3. **版本串带**（Freelens `nightly` / VLC `-dev` / KeePassXC `-snapshot`）—— 现有
   `detect()` step 4 只认 `esr` / `bN` / `aN` / `-betaN`，这三种**一个都不匹配**，
   要加规则才判得出来。
4. **什么都不带**（kitty）—— 真 Pattern D。UTM 曾归在这里，但 2026-09-03 找到一个不靠
   版本号猜测的远端证据：用已安装的纯数字版本查 exact GitHub release，再读上游权威
   `prerelease` 位。exact tag 不存在或应答不再带该字段就 fail closed。

   ⚠️ **但 `prerelease` 位只用来判"这份拷贝是什么"，不能用来决定"该给它什么"。** UTM 的
   预览不是平行轨，是每条线的前半段：131 条 release 里 78 条是 prerelease，`v4.7.0…v4.7.3`
   是 Beta 而 `v4.7.4`/`v4.7.5` 转正。把预览装机限制成"只收 prerelease"会在每次转正时静默
   断供 —— 按真实历史复算出现过 **14 次**，最长约 7.5 个月、错过 4 个正式版；而"取全局最新"
   又会把 `v4.7.3` 的用户推到还没转正的 `v5.0.5`。正确的候选是
   `max(装机大版本线的最新 release, 全局最新正式版)`。细节见 `docs/app-audits/com-utmapp-UTM.md`。

还有一条和一键有关：**公证与否和渠道无关，必须逐包验**。同样是 nightly，Freelens/kitty/
DB Browser 是 Developer ID 公证的，VLC 和 KeePassXC **完全没签名** —— 后两者就算接了检测，
`VendorInstaller` 的 Team 闸也必然拒绝，只能是 detection-only。

### 排序建议

1. **Termius Beta** —— 已接（issue #91，2026-08-27，`docs/app-audits/com-termius-dmg-mac.md`）。
   当时这里写「stable 本身也还没覆盖（`com.termius.mac` 不在任何 registry 里）」是
   **错的**：`com.termius.mac` 是 MAS 沙盒购买副本，装机验证 `MacAppStoreSource`
   通用覆盖，不需要 registry；真正的官网 dmg stable 是 `com.termius-dmg.mac`，
   2026-08-16 已经在 `VendorProbeRecipe` 里注册，只是当时没人把两个 bundle id
   对上号。**VSCodium Insiders** —— 独立 id、已公证，已接（issue #92，2026-08-27，
   `docs/app-audits/com-vscodium-VSCodiumInsiders.md`）。
2. **DB Browser nightly** —— 需要文件名检测，有 Android Studio 的现成范式（`detect()`
   已有自己的 step 0.6，见上）。
3. **Freelens / VLC / KeePassXC** —— `detect()` 的版本串规则已加（issue #93 已解决）；
   VLC/KeePassXC 尚未接 recipe，且后两者只能检测不能一键（未签名，见 issue #95）。
4. **UTM** —— 已接（2026-09-03）：exact-release 远端判轨、线锚定候选、stable/beta 一键和分轨 changelog。
   **kitty** 仍归入 §3 死轨，本地无信号，也没有可按已安装版本反查的固定 nightly release。

---

## §3 死轨 — Pattern D / 不可行（已否决，**勿重开**）

同 stable bundle id 会就地覆盖、或纯应用内/服务端 opt-in 无本地痕迹、或已停产。

- ✗ **Sublime Text — Dev** · 同 `com.sublimetext.4`，license 门控，就地替换 stable
- ✗ **Sublime Merge — Dev** · 同 `com.sublimemerge`，同上
- ✗ **Slack — Beta** · 同 `com.tinyspeck.slackmacgap`，应用内 opt-in，无独立下载（beta 有独立 changelog 但无法区分安装）
- ✗ **MS Office（Word/Excel/…）— Insider Slow/Fast** · 与 Production 同 bundle id，MAU 内部 ring 切换，无独立端点
- ✗ **MS Teams — Public Preview** · 应用内开关，非独立构建
- ✗ **Obsidian — Insider** · 付费 Catalyst 早鸟，无独立 macOS 自更新 feed
- ✗ **Dropbox — Beta** · 论坛分发，口径混乱
- ✗ **Bartender — Test Builds** · 同 feed
- ✗ **Plex — Beta** · Plex Pass 应用内，非独立下载
- ✗ **Audacity 4 预览** · 尚未成轨
- ✗ **Edge — Extended Stable** · 只是更慢的 stable，不单独成轨
- ✗ **MacUpdater** · 2026-01-01 已停更
- ✗ **Zen Browser — Twilight(nightly)** · 同 `app.zen-browser.zen`，twilight 是 prerelease tag，stable rule 已用 `usePrereleases:false` 排除；无检测信号
- ✗ **Ghostty — Tip(nightly)** · 同 `com.mitchellh.ghostty`，tip 滚动 tag 的 dmg 与 stable 同名同 id，无检测信号
- ✗ **JetBrains Toolbox — EAP** · 同 `com.jetbrains.toolbox`，无独立 EAP cask，无检测信号
- ✗ **Cursor — Nightly** · 同 `com.todesktop.230313mzl4w4u92`，无独立 nightly 下载/信号
- ✗ **LM Studio — Beta** · 同 `ai.elementlabs.lmstudio`，版本 API 无 channel 参数
- ✗ **DBeaver — Early Access** · 同 `org.jkiss.dbeaver.core.product`，EA 共享 id、标签格式同 stable
- ✗ **Beekeeper Studio — Beta** · 同 `io.beekeeperstudio.desktop`，同 repo prerelease，stable rule 已排除
- ✗ **Insomnia — Beta/Alpha** · 同 `com.insomnia.app`（共享 id）。真机验证 2026-06-06：beta 构建 `CFBundleShortVersionString` **保留** `13.0.0-beta.0` 后缀（无 Mozilla 式剥离），但 `ReleaseChannel.detect()` **不解析版本后缀** → 检测为 `.stable`。所以 `channel: .beta` rule 永远不会被 channel gate 选中。**前置依赖**：先教 `detect()` 识别 `com.insomnia.app` 的 `-beta.N`/`-alpha.N` 后缀，beta channel 才可接（GitHub prerelease tag + `Insomnia.Core-<ver>-beta.N.dmg` 资产已就绪）
- ✗ **Postman — Canary** · 已停产（cask `postman@canary` 2025-11-15 disabled）
- ✗ **RustDesk — Nightly** · 同 `com.carriez.rustdesk`，同 repo prerelease，stable rule 已排除
- ✗ **1Password — Beta** · 同 `com.1password.1password`，cask 装同名同 id；vendor API 仅服务 NIGHTLY 且需 auth
- ✅ **Raycast — v2** · **更正 2026-08-27**：旧判断「Beta(v2) 应用内 opt-in、无独立下载」已经过期。
  v2 于 2026-08-25 转正（GA 2.0.6.0），**不是 channel 问题**：Raycast 现在开着两条 train，
  归属由**机器**而非用户偏好决定 —— v2 要求 macOS Tahoe + Apple Silicon
  （https://www.raycast.com/new），v1（`releases.raycast.com`，universal）继续为其余机器发版。
  所以两条都是 `channel: .stable` 的 VendorProbe recipe，用新增的 `hostRequirement`
  （`minimumSystemVersion: "26.0"` + `architectures: [.arm64]`）而非 `channel` 区分，
  `variant: "v2"` 保住 v1 的 recipeID/verify 基线。
  **关键实测（2026-08-27）**：两个端点都**不做门控** —— 把 UA 换成 Intel / Sequoia / 浏览器，
  `x.raycast-releases.com` 一律 200 返回 2.0.6.0。所以闸必须记在 recipe 里，不能指望 vendor。
  另：`?version=` 参数只在客户端**落后**时回 200，已是最新则回 **204 No Content**（且只收 4 段版本号，
  v1 的 3 段会 400），所以 probe 一律**不带** `version`。
- ✗ **VLC — Nightly** · 同 `org.videolan.vlc`，nightlies 滚动构建无版本语义，不可区分
  **更正 2026-08-27（§2c）**：这条判断已过期——版本串其实带 `-dev`（`4.0.0-dev`），
  `detect()` 现在能认出这种形状（#93 已解决），只是仓库尚未为它接一条 recipe。
  真正永久挡住的不是检测，是签名：nightly 完全未走 Developer ID
  （`TeamIdentifier=not set`），一键永远过不了 `VendorInstaller` 的 Team 闸。
  见 issue #95、`docs/app-audits/org-videolan-vlc.md`。
- ✗ **Blender — Daily/Alpha/Beta** · 同 bundle id，builder.blender.org 滚动构建，无检测信号
- ✅ **Figma — Beta** · 已接入（**更正旧判断：不是**应用内 flag）。独立 app：bundle `com.figma.DesktopBeta`、"Figma Beta.app"、独立端点 `desktop.figma.com/mac-arm/beta/`。Pattern A，VendorProbe(`channel: .beta`) + 一键安装（Team T8RA8NE3B7，2026-06-06 真机验证）
- ✗ **GitHub Desktop — Beta** · 同 `com.github.GitHubClient`，beta tag 是 prerelease，stable rule 已排除
- ✅ **Longbridge Desktop — Preview** · 已接入。**更正 2026-08-25 那版"已停更"的判断**：那条结论是
  从本机一个旧的 `0.15.0-preview.0` 包倒推的，没打端点；实际 2026-08-26 复核时 preview 轨道是活的。
  独立 bundle `com.longbridge.app.desktop.preview`（"Longbridge Preview.app"），靠 `.preview`
  后缀走 `ReleaseChannel.detect` 规则 2。Pattern A：VendorProbe(`channel: .preview`) + changelog +
  arm64 一键安装，ChannelProof 锚 `/longbridge-desktop/preview/`。
  真机验证 0.19.0-preview.1（75,399,519 B）：arm64、Team 45NG8MW7WK（**与 stable 同一个**，
  满足 VendorInstaller 签名闸）、spctl 判为 Notarized Developer ID。
  两条轨道的 version pattern 互不匹配（stable 的数字后必须紧跟引号，preview 的必须带 `-preview.N`），
  所以就算 bundle id 之外的隔离全失效，跨轨也是 fail-closed。
  **站点状态（下架 ≠ 停产，值得盯）**：`/desktop/release-notes/preview/` 返回 200 但版本列表被清空
  （stable 索引有 48 条链接，preview 零条），`/desktop/preview/` 是 404，`/desktop/` 下载页只挂 stable。
  每版说明页、CDN 清单、DMG 直链都还在。另外 preview 的 asset **不带 `sha256`**（stable 带），
  是清单降级维护的信号。若 preview 真的停产，表现会是 `latest.json` 长期不动 —— 由夜间 `duo verify`
  全量扫描的版本停滞告警兜底，不需要提前拆 recipe。

### 2026-06-06 渠道扫描确认 — 单 channel / 无 detectable beta

以下 app 经 web 搜索（官网、GitHub、brew cask）**确认无独立 beta/nightly 渠道**，
也**无 app 内可切换的 channel toggle**（或 toggle 不存在/无本地信号）。归入单 channel，
不单独成轨。

- [x] **Alfred** · 已修正（2026-06-07）：Alfred 实际有 **Pre-releases** 开关（v5.5 起）。
  信号：UserDefaults `prereleases` 存于 `~/Library/Application Support/Alfred/Alfred.alfredpreferences/
  preferences/local/<hash>/update/prefs.plist`，值 `1`（Bool）→ `.beta`（Pre-release）。
  已接入 `AlfredChannel`（feed-swap：`general.xml` ↔ `prerelease.xml`），注册到 `ChannelBinding`，
  测试通过。官网“无 beta”是**旧判断**，已更新。
- ✗ **Arc** · 无 beta/preview 渠道，Dia 是另一独立产品，非 Arc 的 channel
- ✗ **HandBrake** · 开源 GitHub 仅有 snapshots（`HandBrake-snapshots`），无独立 bundle id，
  无 app 内 toggle，snapshot 与 stable 同构建
- ✗ **Keka** · 开源 GitHub 有 dev pre-release（`v1.5.2-dev.r5614`），但无独立 bundle id，
  无 app 内 channel toggle
- ✗ **Lark** · 无 beta 渠道，官网仅 stable
- ✗ **MonitorControl** · 开源 GitHub releases，无 beta 渠道
- ✗ **OBS Studio** · 开源 GitHub releases，有 RC/Beta tag（pre-release），但无独立 bundle id，
  无 app 内 toggle；RC 构建是发布流程的一部分，非独立 channel
- ✗ **Orion** · 无 beta 渠道，官网仅 stable + 各平台 release notes
- ✗ **Proxyman** · 无 beta 渠道，官网仅 stable，changelog 随 stable 走
- ✗ **Rectangle** · 开源 GitHub releases，无 beta 渠道（Pro 是付费 tier，非 channel）
- ✗ **Shottr** · 无 beta 渠道，官网仅 stable
- ✗ **The Unarchiver** · 无 beta 渠道，官网仅 stable
- ✗ **Mirage Client** · 网站不可达（`mirageclient.com` transport error），无法确认
- ✗ **Mirage Host** · 网站 "Coming Soon"（`miragehost.com`），无可用信息

> **IntelliJ IDEA — EAP**：检测已由 ToolboxSource/VendorProbe(`channel: .preview`)覆盖，
> stable changelog 已接。EAP changelog **确认不接**（2026-06-06 复核）：每个 EAP build 的
> JetBrains data-services `whatsnew` 是样板占位（"… EAP N is out! … refer to the release
> notes" + 每 build 不同的 YouTrack 文章链接），无结构化 `<li>` 变更条目；真正变更在
> per-build YouTrack 文章里，而 ChangelogRecipe.source 是固定 URL，架构追不了。EAP probe
> 已设 `changelogURL: jetbrains.com/idea/whatsnew/`，WebView 已兜底，故无需结构化 recipe。

### Warp 死轨（JSON 仍列但已停更，recipe 已删）

`releases.warp.dev/channel_versions.json` 列 5 轨，但 beta（2024-12 停）、canary
（2022-09 停）早废。`dev.warp.Warp-Beta` / `-Canary` 两个 recipe **已删**——探测只会
拿到数年前的 latest，比干净的 unknown 更糟。bundle-id 后缀仍会给这类安装打 channel 标签
（UI 用），只是没版本源。活跃 3 轨（stable/preview/dev）已接 ✓。

---

## 已全覆盖的单 channel app（存档参考）

只有 stable、无其它轨需接的：Claude / Codex / ChatWise / Ollama / Conductor / opencode /
CleanShot(单轨部分) / Shottr / AppCleaner / Unarchiver / ImageOptim / Pearcleaner /
Stats / MacsFanControl / Calibre / Notion / JetBrains Air / LibreWolf / Plex / Dropbox /
Orion / VS Code(stable) / Cursor / Figma / Slack / 1Password / Sublime（Text/Merge）/
RustDesk / GitHub Desktop / DBeaver / Beekeeper / Insomnia / Macs Fan Control / Alcove /
Arc / HandBrake / Keka / Lark / MonitorControl / OBS Studio / Proxyman / Rectangle /
The Unarchiver 等。

> Alfred 已移出（见 §2  Pattern B/C 接入）。

### 2026-06-07 ChangelogRecipe 批量补全

**已接入结构化 ChangelogRecipe（5 个）：**

| App | bundle id | 源 | 备注 |
|---|---|---|---|
| **Bartender 6** | `com.macbartender.Bartender6` | `macbartender.com/Bartender6/release_notes/` | Next.js 页面，`<h2>` 含 `<!-- -->` 注释；多 section `<h3>` + `<ul>` |
| **Shottr** | `cc.ffitch.shottr` | `shottr.cc/newversion.html` | 静态页面，`<h1>`/`<h3>` 标题 + `<b>` section + `<ul>` |
| **Orion stable** | `com.kagi.kagimacOS` | `orionbrowser.com/updates/orion-release-notes` | 与 RC 同页，stable 条目排除 `RC`/`Beta`（`Orion \d+` 不匹配 `Orion RC…`）|
| **The Unarchiver** | `com.macpaw.site.theunarchiver` | `updates.devmate.com/releasenotes/147/…` | DevMate 页面，`<h2>` + `<strong>` section + `<ul>`，`<hr />` 分隔 |
| **Plex Desktop** | `tv.plex.desktop` | `forums.plex.tv/…/446435.rss` | Discourse RSS feed，`<item>` 内 `<p>Version X.Y.Z…` + `<ul>` |

**确认不可解析、fallback webview（6 个）：**

| App | 原因 |
|---|---|
| **Arc** | `resources.arc.net` 403；blog 无结构化版本内容 |
| **Lark** | `larksuite.com/hc/…` 纯客户端 JS 渲染，无静态 HTML |
| **Mirage** | 仓库 `github.com/EthanLipnik/MirageKit` 0 releases；网站不可达 |
| **Dropbox** | `dropbox.com/release-notes` 按月份/功能组织，无按版本号结构 |
| **Discord** | `discord.com/blog` 混合内容（Patch Notes 与其他文章混排），无专用结构化页面 |
| **Vivaldi** | `vivaldi.com/blog/desktop` 博客列表（Desktop Releases / Updates / Snapshots 混排），非结构化 changelog |

> 所有 5 个新增 recipe 均通过 `ChangelogExtractorTests` fixture 验证（共 73 个测试全部通过）。
> 加上此前已接的 6 个 GitHub releases 型（HandBrake / IINA / Keka / MonitorControl / OBS / Rectangle）
> 及 4 个新增 recipe（Sublime Merge / Brave / Proxyman / Alfred），本次批次 22 个已扫描 app
> 全部完成接入判定。

### 2026-06-07 续 — Changelog 数据结构 section 结构化

- `Changelog.Entry` 新增 `sections: [Section]?` 字段，`Section` 含 `title` + `items`。
- `items` 自动由 `sections` 扁平化，保持向后兼容（旧测试/代码无需重写）。
- `ChangelogRecipe` 新增 `sectionPattern: String?` 字段：当设置时，`ChangelogExtractor`
  先用 `sectionPattern` 把 `body` 拆分为 section，再在每 section 内运行 `itemPatterns`。
  section 匹配需提供 `sectionTitle` 和 `sectionBody` 捕获组。
- `ChangelogEntryView` 已按 `sections` 分节渲染：有 `sections` 时按 section 分组显示
  （section 标题加粗），无 `sections` 时回退到 flat items。
- **已接入 `sectionPattern` 的 recipe（5 个）：**
  - **Bartender 6** — `<h3>` section 分隔（Fixes / New / Top Shelf）
  - **Orion stable** — `<h3>` section 分隔（Improvements and bug fixes / WebKit…）
  - **Orion RC** — `<h3>` section 分隔（Features / Improvements and bug fixes）
  - **The Unarchiver** — `<p><strong>…</strong></p>` section 分隔（Fixed / New）
  - **Shottr** — `<b>` section 分隔（Improvements / Bug Fixes / New Features）
- `swift test` 共 316 个测试全部通过。
