# 欧路词典 (Eudic)

审计 2026-09-01。起因是用户反馈：这一行**没有名字**，点 Relaunch **失败**。
两条都查到了根因，都不在厂商侧。

## 基本信息

- Bundle ID: `com.eusoft.eudic`
- App 名: `Eudic.app`（Finder 里显示「欧路词典」，见下）
- URL scheme: `eudic`
- 官网下载: https://static.eudic.net/pkg/eudicmac.dmg
- 观测版本: `26.9.0`（`CFBundleVersion` = `1229`）
- Team ID: `7L3ARZ2SN3` — QianYan Network，Developer ID，已公证
- 架构: universal（`x86_64 arm64`）
- 自更新机制: **Sparkle 1.27.3**（注意是 1，不是 2）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable** | ✓ | ✗ | — | — | — |

当前生效源：**Sparkle**，走 bundle 里的 `SUFeedURL`，不需要 recipe。

```
duo check com.eusoft.eudic
→ "source":"Sparkle","status":"up-to-date","latestVersion":"26.9.0","latestBuild":"1229"
```

- **Homebrew** — cask `eudic` 存在但 `version "latest"` / `sha256 :no_check`，
  URL 是 `https://static.frdic.com/pkg/eudicmac.dmg?version`（另一个 CDN 主机），
  给不出版本号。
- **MAS / GitHub** — 无。

⚠️ `duo list` 对它显示 `status: unknown` 是**正常的**——`list` 不问任何源。
判断覆盖要用 `duo check`。这一点我一开始读错过，据此以为它没接入。

## Sparkle 配置（实测）

`Info.plist` 里 Sparkle 相关的键只有三个：

```
SUFeedURL          = https://static.eudic.net/pkg/eudic_mac.xml
SUPublicDSAKeyFile = dsa_pub.pem
SUPublicEDKey      = yGcmhcgjoSEMm2w9Yfr7+Kda1rY4x8EwfkmuuaIaph4=
```

**没有 `SUAutomaticallyUpdate`，也没有 `SUEnableAutomaticChecks`**；prefs 里同样没有。
Sparkle 1 默认 `automaticallyDownloadsUpdates` 为 NO，所以它走的是弹框驱动
（`SUUIBasedUpdateDriver`，prefs 里留下 `NSWindow Frame SUUpdateAlert`），
**不是**后台下载、退出时安装。这条对下面的风险判断是关键。

feed 的 UA 是 `EuDic/26.9.0 Sparkle/1.27.3`，最新条目：

```xml
<enclosure url="https://static.eudic.net/pkg/eudicmac.dmg?v=1229"
  sparkle:version="1229" sparkle:shortVersionString="26.9.0"
  length="119209421" sparkle:edSignature="…" sparkle:dsaSignature="…"/>
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
```

`?v=` 是 cache-buster，不是版本选择器——**厂商只发布最新一份 dmg，取不到历史版本**。
（想复现"装机版本落后"的场景只能自己伪造，见下面「复现手法」。）

## 陷阱一：`CFBundleDisplayName` 是空字符串

```xml
<key>CFBundleDisplayName</key>
<string></string>
```

键**存在**，值是空串。真正的名字在本地化文件里：

```
Resources/zh-Hans.lproj/InfoPlist.strings → CFBundleDisplayName = 欧路词典
Resources/en.lproj/InfoPlist.strings      → CFBundleDisplayName = EuDic
Info.plist CFBundleName                   → Eudic
```

`AppScanner` 原来用 `??` 链取名，而 `??` 只跨过**缺失**的键，空串是合法 `String`，
链子当场停死 → `name` 为空 → 行里只有图标和版本，没有名字。

本机 150 个 bundle 里**只有它一个**是这样。已修（`firstUsableName`，判空放在
`stripInvisibleMarks` 的输出上）。DuoUpdater 全程用未本地化的 plist 名，所以它
现在显示 `Eudic` 而不是「欧路词典」——与 WeChat 显示 `WeChat` 一致，是有意的。

## 陷阱二：登录 sheet 会挡住退出，Relaunch 因此静默失败

用户日志：

```
app-restarter: Eudic won't quit (likely a save prompt) — leaving it running
```

根因：**没登录时 Eudic 会在主窗口上挂一个登录 sheet**（465x327 无标题子窗口，
`CGWindowList` 可见）。AppKit 在有 window-modal sheet 时拒绝执行退出，
`AppRestarter` 等满 30 秒后放弃。

分界线比"有没有弹框"细，实测：

| 目标状态 | `terminate()` |
|---|---|
| 无对话框 | 0.2s 退出 |
| `beginSheet` 窗口级 sheet | 32s 不退 |
| `NSApp.runModal(for:)` app 级模态窗口 | 32s 不退 |
| **Sparkle 自己的「软件更新」框** | **2.3s 正常退出** |

最后一行很重要：Sparkle 1 的 `SUUpdateAlert` 是普通顶层窗口（620x402、有标题栏），
**不挡退出**。我一开始把它当成阻塞源，被实测推翻。别把"app 弹了个框"当判据。

本机 macOS 27.0 上 `preventsApplicationTerminationWhenModal` 对 NSWindow / NSPanel /
NSAlert 的窗口**都是 true**，但 accessory app 上裸 `NSAlert.runModal()` 实测仍能正常退出——
属性和现象对不齐，所以**给不出一个干净的谓词**，这也是没有去做"探测阻塞窗口"的原因。

已修的部分是把这件事告诉用户（`.stillRunning` 现在写一条 `installNotes`），
不是去绕过 app 的行为。

## 陷阱三：整部历史塞在最新一条 item 的 description 里

`<description>` CDATA 有 10253 字符，包含：

- 1 个 `<h2>`：`《欧路词典》Mac 26.9.0 更新`
- **34 个 `<h3>`**，一路回溯到 2.5.0
- **0 个 `<li>`**，29 个 `<p>`、154 个 `<br>`

后果：`AppcastHTMLChangelogParser.isStructured` 要求至少一个 `<li>`，
所以 `SparkleAppcastSource` 给不出 `structuredChangelog`，
详情页回落到原始 HTML 渲染——**十六年的更新记录全挂在「26.9.0」这一个标题下**。

`<h3>` 也不是干净的版本列表，这是不该去改通用 parser 的理由：

```
['更新内容', '4.9.0', '4.8.0', '4.7.0', '更新内容', '4.5.0', '更新内容', '4.3.0',
 '更新内容', '4.2.0', '更新内容', '4.1.0', '更新内容', '4.0.0', '3.9.10', …,
 '3.6.0 改进', '3.5.0 改进', …, '2.5.2改进', '2.5.0 改进']
```

34 个里 **7 个是标签「更新内容」**，另有若干带「改进」后缀（`2.5.2改进` 连空格都没有）。
按 `<h3>` 一刀切会产出标题叫「更新内容」的条目。

解法是专用 `ChangelogRecipe`（recipe 优先级高于 `structuredChangelog` 和
`releaseNotesHTML`，见 `WorkbenchWindowView` 的分支顺序）：`source` 指向 appcast 本身，
entry 锚在**含点分数字的标题**上而不是标题标签，body 走到下一个含数字的标题
（因此跨过标签行）或 CDATA 结束。item 用 `.*?` 而不是 `[^<]+`——3.7 之前的段落整行包在
`<b>` 里，无标签捕获会**静默丢掉全部**。产出 29 条，live feed 与 fixture 双向验过。

per-version 段落**没有日期**（feed 只有一个 `<pubDate>`，描述的是最新那版），
所以每条都不带日期，而不是借一个错的。

## 已知风险：Sparkle 1 退出即安装（当前不触发）

`SUAutomaticUpdateDriver.m` 在解压完成时挂 `NSApplicationWillTerminateNotification`，
回调里 `installWithToolAndRelaunch:NO`。即**开了自动下载的 Sparkle 1 app，任何一次退出
（包括 DuoUpdater 发的）都会装它那份**，而 `RestartStandoff` 只覆盖 Sparkle 2——
Sparkle 2 的判据是"有 parked agent 进程"，而 Sparkle 1 根本没有 agent 这个角色，
判据不是缺失而是**不存在**。

对 Eudic 当前**不触发**：如上，它没开自动下载。详见 issue #211。

## 复现手法（给下一个人）

厂商只发布最新 dmg，所以"装机版本落后"必须自己造：

1. `ditto` 一份 `Eudic.app`，`plutil -replace` 把版本改成 `26.8.3` / `1228`，
   `codesign -f -s - --deep` 重签（改 plist 会废掉原签名，不重签起不来）；
2. 放进 `~/Applications/`（**不要动 `/Applications`**）并启动；
3. 把真身 26.9.0 换到同一路径上，制造"磁盘新、进程旧"。

⚠️ 两份 byte-identical 的副本会被 `AppScanner.dedupeIdenticalInstalls` 折叠成一行
（键是 bundleID|channel|marketing|build），所以磁盘那份要给一个**不同的版本号**
才能让两行都活下来。

⚠️ LaunchServices **不跟随**被移走的 bundle：把旧 bundle 移进废纸篓后，
`NSRunningApplication.bundleURL` 和 `lsappinfo` 的 `bundle path` 仍报原路径。
（我一度假设它会跟随，据此推了一条错的根因，实测推翻。）

登录 sheet 不是启动就有，得点主窗口左下角「登录学习账号」叫出来；
Sparkle 的「软件更新」框则会在启动约 4 分钟后自己弹。

## 其它观察

- `LSUIElement = true`，但进程实际以 `.regular`（`activationPolicy = 0`）运行——
  26.9.0 新增了「可以隐藏Docker栏图标」，应是运行时切策略。
- `Contents/PlugIns/SafariExtension_en.appex`；
  `Contents/Frameworks/Sparkle.framework/…/Autoupdate.app` 是 `LSUIElement`+
  `LSBackgroundOnly`，所以 `AppRestarter.isStandaloneNestedApp` 正确地不把它当嵌套 app。
- cask 的 `uninstall.quit` 列了 `com.eusoft.eudic.LightPeek`，但 26.9.0 的 bundle 里
  已经没有这个组件了。
