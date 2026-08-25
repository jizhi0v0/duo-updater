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

> 以下 app 有明确 in-app channel toggle，但切换后是否留下可读的本地信号（defaults/plist）
> 仍需真机 diff 确认。不要直接标为 detectable。

- [x] **IINA** · `com.colliderli.iina` — Preferences → General → **"Receive beta updates"**
      checkbox。源码确认 UserDefaults key 为 `receiveBetaUpdate`（Bool，默认 false）。
      真机验证：切换后 `defaults read com.colliderli.iina receiveBetaUpdate` 返回 `1`。
      已接入 `IINAChannel`（feed-swap：stable `appcast.xml` ↔ beta `appcast-beta.xml`），
      注册到 `ChannelBinding`，测试通过。

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
- ✗ **Raycast — Beta(v2)** · 应用内 opt-in，无独立下载/bundle id
- ✗ **VLC — Nightly** · 同 `org.videolan.vlc`，nightlies 滚动构建无版本语义，不可区分
- ✗ **Blender — Daily/Alpha/Beta** · 同 bundle id，builder.blender.org 滚动构建，无检测信号
- ✅ **Figma — Beta** · 已接入（**更正旧判断：不是**应用内 flag）。独立 app：bundle `com.figma.DesktopBeta`、"Figma Beta.app"、独立端点 `desktop.figma.com/mac-arm/beta/`。Pattern A，VendorProbe(`channel: .beta`) + 一键安装（Team T8RA8NE3B7，2026-06-06 真机验证）
- ✗ **GitHub Desktop — Beta** · 同 `com.github.GitHubClient`，beta tag 是 prerelease，stable rule 已排除
- ✗ **Longbridge Desktop — Preview** · 已停更，不再接入。2026-08-25 实包验证旧
  `0.15.0-preview.0` 是独立 `com.longbridge.app.desktop.preview`，可准确检测为 `.preview`；
  stable `com.longbridge.app.desktop` 已接 VendorProbe + changelog + arm64 一键安装，二者不会串轨。

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
