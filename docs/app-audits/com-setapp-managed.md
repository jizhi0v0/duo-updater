# Setapp editions — the channel Setapp ships, and why the vendor's feed answers wrong

不是某个 app 的审计，是**一类副本**：Setapp 分发的那一版。它们和直营版同源同版本，
但签名标识、更新路径、订阅状态都归 Setapp 管，所以单独记一份。

## 分发与渠道

- Setapp 版用独立 bundle id，后缀 `-setapp` 是 Setapp 的硬性规定，不是厂商习惯：
  [Set an app bundle ID](https://docs.setapp.com/docs/set-an-app-bundle-id)
  给的形状是 `<domain>.<companyName>.<appName>-setapp`。
- 观测样本（2026-11-03）：AlDente Pro 直营 1.40.1 / 119 与 Setapp 1.40.1 / 119
  是同一版不同行；Bartender、CleanShot X、CleanMyMac、Downie、Paste、iStat Menus
  同样以 `-setapp` 落地。
- Setapp 自己的发版节奏独立于厂商 feed：它的目录里给的是「Setapp 渠道当前发到哪一版」，
  可以领先、落后或中间多一次构建号。读厂商 feed 猜 Setapp 渠道的版本是错的方向。

## 包里没有 Sparkle

同一个 1.40.1 (119)，直营包与 Setapp 包的差别（2026-11-03 逐项核对）：

| | 直营 | Setapp 版 |
|---|---|---|
| `Sparkle.framework` | 2.7.0 | **没有** |
| `SPUUpdater` 符号 | 42 | **0** |
| `SUFeedURL` | 厂商 feed | **同一个厂商 feed（残留，没人读）** |
| `setappPublicKey.pem` / `Setapp_*.bundle` | 无 | 有 |
| `NSUpdateSecurityPolicy` | 无 | 允许 `com.setapp.DesktopClient.SetappAgent` |

`NSUpdateSecurityPolicy` 是 Setapp 官方要求加的那段（
[Allow Setapp to update your app on macOS 13+](https://docs.setapp.com/docs/allow-setapp-to-update-your-app-on-macos-13)），
意思是「Setapp 的 agent 被授权更新这个包」。

结论：**Setapp 版里 Sparkle 是被剥掉的**，`SUFeedURL` 只是 Info.plist 里的一段死配置；
唯一会去读它的是我们自己的通用 Sparkle 源。这就是那个错配的来历：
Setapp 副本被按厂商 feed 报出版本，下载直营 DMG，安装时 gate 4 拒绝——
`Bundle identifier mismatch: installed "…-setapp" vs downloaded "…-pro"`。
0.5.18 之前 Setapp 副本根本没被扫到；一层目录扫描（#1763）把
`/Applications/Setapp/…` 带进视野之后才暴露。

## 渠道数据：Setapp 的公开目录

客户端启动时请求：

```
GET https://store.setapp.com/store/api/v8/en
accept: application/vnd.api+json
```

- **无鉴权**：没有 `Authorization` 头，只有 Cloudflare 的 cookie；条件请求会 304。
- JSON:API，约 3 MB；`data.relationships.vendors[].relationships.applications[]` 下每个 app 带
  `attributes`（`bundle_id`、`name`、`public_id`、`slugs`）和 `relationships.versions[]`
  （`marketing_version`、`build_number`、`release_date`、`min_os_version`、`archive_url`）。
- `public_id` 是 uuid，深链要它；客户端 CoreData 里那个数字 `ZIDENTIFIER` 不是。
- 2026-11-03 的 468 条 `bundle_id` **全部**带 `-setapp` 后缀；匹配仍按 id 建索引，不作后缀假设。
- 目录的刷新时机与客户端同步：客户端关着时它不刷新（实测退出后 6 分钟内没有任何
  update check，版本未动；重新打开立刻检查并更新）。所以「Setapp 有没有新版」以这个
  公开接口为准，不以客户端本地缓存为准。

## 订阅状态

客户端把账号状态写在 `com.setapp.DesktopClient` 的 `known_customers` 里：

```
subscriptionState            trial | paid
subscriptionStartDate        <date>
subscriptionExpirationDate   <date>
gracePeriodExpirationDate    <date>
```

- 3.58.0 写的是 **NSDate**（`plutil -p` 不带引号）；旧写法里出现过同形状的字符串，
  解析要两种都收。只认字符串会把一个有效试用判成过期。
- 宽限期 14 天是 Setapp 的规定（[Grace period](https://support.setapp.com/hc/en-us/articles/115004305069-Grace-period)）：
  付款失败时账号继续可用，更新照常下发，所以到 `gracePeriodExpirationDate` 之前都按「有效」。
- 订阅结束后 Setapp 不再下发更新，app 也会停止打开（Setapp 的取消条款）。这时候
  「有新版」仍然是真的，但装不了——只显示版本、不给更新动作（Surge / TablePlus 同一模型）。

## 更新归 Setapp，不归我们

- 没有「安装接口」可调；安装是 agent 本地流程：取 `archive_url` 的 zip → 解包 → 替换，
  中间有授权检查、确认框、取消 token。
- 深链实测（2026-11-03，agent 日志）：

  | 链接 | 结果 |
  |---|---|
  | `setapp://install/<数字 id>` | `URL is not a valid install-from-URL link`，agent 直接拒绝 |
  | `setapp://install?app_id=<public_id>` | 有效；打开该 app 的页面，已装时只问「要不要打开」 |
  | `setapp://launch/<数字 id>` | 已装则启动，未装则打开它的页面 |

  没有触发更新的深链。
- 打开方式有讲究（2026-11-03 实测）：把同一个链接用
  `NSWorkspace.open(_:withApplicationAt: /Applications/Setapp.app)` 交给客户端，只会把 Setapp
  激活到首页；换成普通的 `NSWorkspace.open(url)`（交给 LaunchServices、由注册了 scheme 的
  agent 处理），才会落到该 app。点「Open App」时会去启动目标 app——若包的签名被改过
  （例如手改了版本号），这一步会报 `The application "…" can't be opened.`。
- MCP（`SetappMCPServer.framework`，stdio bridge + 本机 HTTP 端点）有一整套工具：
  `list_available_apps`、`find_apps`、`get_app_offer`、`open_purchase`、`check_access`、
  `install_app`、`launch_app`、`get_app_guide`。其中 `install_app` 的描述是
  「Installs the app on this Mac through Setapp … Setapp also asks the user to confirm the
  installation. Returns when it is finished.」——它也没有进度，取消在 Setapp 那边。
  这套东西被 GrowthBook 开关 `PLATECO-12287` 挡着（生产为 `false`、无灰度规则），
  当前不可用。
- 因此 DuoUpdater 对 Setapp 副本只做两件事：报 Setapp 渠道的版本（有效时），
  给一个打开页面/启动的入口。**不做一键更新**，也不假装有进度或取消。

## 后台触发与自动更新开关

- 静默拉起能触发检查：Setapp 退出、把一个被管理的 app 改成低于目录版本，然后
  `open -g -a /Applications/Setapp.app`（不抢焦点）——15 秒内该 app 被替换。
- 同一操作在 Setapp 的「Install automatically」关闭时**什么都不做**（版本不变）。
- 开关存在自己的偏好里，键按账号哈希前缀：

```
defaults read com.setapp.DesktopClient
"<hash>-ForbiddenAutomaticAppsRefresh" = 1    ← 关闭
（键不存在）                                    ← 开启
```

  agent 每次检查也会打 `automaticAllowed=0/1`。

### Refresh 时触发的复验（2026-11-04）

在 vmpal「macOS VM 1」、Setapp 3.58.0 (163) 上复验，目标是 refresh 时读取
Setapp 自己的「Install automatically」，开启才后台启动，让 Setapp 安装。

- 真实待更新副本 Paste 7.0.4；没有改 Info.plist 模拟旧版本。
- 界面开关已勾选，`ForbiddenAutomaticAppsRefresh` 键不存在，但最初 agent 日志仍报
  `automaticAllowed=0`、`update was not allowed`，Paste 未更新。这说明仅从客户端
  偏好推断 agent 当下会安装，并非充分保证；这次不一致的原因尚未确定。
- 在界面将自动安装关闭再开启，确认关闭时写入 `<hash>-ForbiddenAutomaticAppsRefresh=1`，
  开启时删除该键；最终恢复为开启。随后退出主客户端并执行
  `open -g -a /Applications/Setapp.app`，约 8 秒内 Paste 变为 7.0.5 / 29895801，
  日志为 `automaticAllowed=1`；Downie 也有 `Successfully updated app`。
  **冷启动触发安装成立，不需要先跳转 Updates 页面。** `-g` 不抢焦点，但窗口仍可能在后方显示。
- `setapp://updates` 经默认 scheme handler 交给 agent，被明确拒绝为
  `URL is not a valid install-from-URL link`。显式交给主客户端也没有切换页面。
- 主客户端注册的是 `setappDiscovery` scheme。
  `setappDiscovery://updates`、`setappDiscovery://check-for-updates` 均有客户端接收日志，
  但没有观察到新的更新检查；后一条调用后 `LastAppsRefreshDate` 仍是上次冷启动的时间。
  这些候选不能当成可用的更新入口，也不能据此断言所有可能的 Updates 深链都不存在。
- 产品代码已接入 refresh：完成检查后，存在未忽略、状态为 `updateAvailable` 的 Setapp
  offer，且 DuoUpdater 和 Setapp 两个开关都允许时，后台启动尚未运行的客户端。
  稳定版和 Beta 均使用源已完成的渠道、订阅和系统兼容性判断；不会因锁定版本或检查错误启动。
  popover 按钮固定显示 `Setapp`。客户端已经运行时，如何主动触发检查仍待验证，故跳过。
- 使用与产品相同的 `NSWorkspace.openApplication` 参数在 VM 复验：
  `activates=false` 时，`frontBefore=com.apple.Terminal`、`active=false`、
  `frontAfter=com.apple.Terminal`。**不要设置 `hides=true`**：同一探针反而得到
  `active=true`、`frontAfter=com.setapp.DesktopClient`。此处后台指不抢焦点，窗口可能在后方显示。
- 检查 3.58.0 主客户端实际 URL handler 的 12 个 host：`launch`、`install`、
  `system/sign_in`、`renew_subscription`、`start_trial`、`open_preferences`、
  `open_collection`、`open_whats_new_setapp`、`open_whats_new_one_app`、
  `open_whats_new_all_apps`、`open_blog_article`、`open`，没有 Updates host。
  Agent 的 URL handler 依次尝试 install、launch、sign-in、renew-subscription。
  `refreshApps` 则是其内部 proactor 动作名，不能据此拼成可用深链。

### 可见窗口复验：不等于完全静默（2026-11-04）

用户完全退出主客户端后，确认只剩 Agent、Launcher、Assistant 等后台进程。
保持 Terminal 非全屏，启动前后都截图，不用前台窗口遮住整个桌面：

- 先备份完整的 Paste.app（原版 7.0.5），将测试副本 Info.plist 改为
  `CFBundleShortVersionString=7.0.4`、`CFBundleVersion=1`，不启动改过签名的副本。
- VM 当地时间 05:33:29，使用与当前产品相同的 `NSWorkspace.openApplication`、
  `activates=false`（不设 `hides`）启动 Setapp。
- 探针输出 `frontBefore=com.apple.Terminal`、`hidden=false active=false`、
  `frontAfter=com.apple.Terminal`。启动后截图**明确出现 Setapp 主窗口，位于 Terminal 后方**。
- 05:33:48 读取 Paste 为 7.0.5 / 29895801，`codesign --verify` 成功：
  Setapp 已用官方包替换测试副本，无须把修改过 Info.plist 的包留在安装位置。

结论：**后台启动可自动更新，也不抢焦点，但会显示主窗口，不能称作“完全静默”**。
此前前台应用保持不变的探针只证明焦点，不能作为“没有显示窗口”的证据。
当前自动 refresh 实现也有这个限制；尚未验证出无窗口、无闪现的启动方式。

### TestFlight 的独立隐藏实例参数复验（2026-11-04）

同一 VM、Setapp 3.58.0 (163)，用与 `AppRestarter.launchSeparateInstance` 相同的整组参数：
`activates=false`、`hides=true`、`createsNewApplicationInstance=true`、
`addsToRecentItems=false`。每轮把已备份的 Paste 测试副本重新标为 7.0.4 / 1，
测试后均由 Setapp 更新回官方 7.0.5 / 29895801，`codesign --verify` 通过。

| 场景 | 进程与界面结果 | 更新结果 |
|---|---|---|
| 主客户端未运行 | 启动 PID 61891，`hidden=false active=true`；窗口可见，前台从 Finder 变为 Setapp | 成功 |
| 主客户端 PID 61891 已运行 | 确实创建 PID 61972；新实例 `hidden=false active=true`，抢到前台；原 PID 61891 存活、变为 inactive | 成功 |

探针从调用启动之前开始，循环采样前台进程和新实例的屏幕普通层窗口，等待 20 秒。
第一轮 309 次采样，295 次前台属于 Setapp、294 次检测到新实例可见窗口；
第二轮 315 次采样，302 次前台属于新实例、302 次检测到新实例可见窗口。
调用前后的截图也能看到主窗口，第二轮 Dock 出现两个 Setapp 图标。

**结论：Setapp 可以启动独立实例并触发更新，但不遵守这组隐藏/不激活参数的预期效果；
不能把 TestFlight 的完全静默机制直接套用到 Setapp。** 原实例没有被退出或替换，
但丢失了前台焦点。探针按 TestFlight 同类的“可见或 active 则不退出”规则留下测试实例，
没有以 bundle ID 批量退出客户端。此次仅验证和记录，没有将这组参数接入产品。

### 自有静默参数、安装入口与延迟隐藏复验（2026-11-04）

继续在同一 VM 使用 Setapp 3.58.0 (163)，并用 DuoShot 录制整个 VM 窗口。
Terminal 保持非全屏，观察其后方的 Setapp 窗口；每轮把 Paste 的版本标为
7.0.4 / 1，不启动该测试副本，以恢复至 7.0.5 / 29895801 且签名有效作为更新成功标准。
这些实验未接入产品。

| 方法 | 界面结果 | 更新结果 |
|---|---|---|
| TestFlight 整组启动参数，再加 Setapp 自有 `-silentLaunch` | 未观察到主窗口；主进程快速退出，日志为 `Did silent launch` | 未更新 |
| `-silentLaunch -userInteractionForbidden -installApps 98` | 未观察到主窗口，快速退出 | 未更新 |
| 去掉 `-silentLaunch`，用 `-userInteractionForbidden -installApps` | 未观察到主窗口；确实进入 vendor 的 CommandLineService | 分别传数字 ID、bundle ID、公开 UUID 均未更新；前两者返回 `com.setapp.default-error-domain` / `-401003` |
| 普通不激活启动，仅加 `-userInteractionForbidden` | 主窗口仍显示在 Terminal 后方 | 成功 |
| 普通不激活启动，返回后立即 `NSRunningApplication.hide()` | 返回 false，主窗口随后显示 | 成功 |
| 普通不激活启动，返回后等 1 秒再 `hide()` | 窗口短暂出现后隐藏 | 成功 |

`-silentLaunch` 与 `-userInteractionForbidden` 是从 Setapp 自己的
SetappInterface.framework 导出的启动常量读取的参数。前者不是普通 GUI 启动的
“隐藏窗口”修饰符：本次执行直接走静默启动分支并退出，没有触发普通启动的应用更新。
后者在入口处用于控制安装后台组件时是否允许交互，不能据此推断整个 GUI 都不显示。
`-installApps` 的失败只说明这些调用未成功，不能证明该内部入口在所有条件下不可用。

延迟隐藏的有效录屏 `/tmp/setapp-hidelater-valid.mp4`：
2.487 秒的帧明确显示 Terminal 后方出现 Setapp 主窗口，2.995 秒的帧已隐藏；
菜单栏一直显示 Terminal。探针 344 次采样中 15 次检测到新实例可见窗口，
随后持续 hidden，20 秒观察结束时只退出本次启动且仍隐藏的 PID 62706。
测试后 Paste 为官方 7.0.5 / 29895801，`codesign --verify` 成功；Setapp 主客户端已退出。
另一次延迟隐藏录屏碰上锁屏，排除其界面结论。解锁后探针报告的前台进程仍为
loginwindow，与录屏上的 Terminal 菜单栏不一致，因此本轮焦点判断以录屏为准。

其他本地证据：`/tmp/setapp-silentlaunch-cold.mp4`、
`/tmp/setapp-nointeraction-valid.mp4`，以及同名前缀的探针日志。

**结论：本次没有验证出“无窗口且能自动更新”的启动方式。延迟隐藏可更新但有闪窗；
普通后台启动可更新但窗口会留在后方。这是当前 Setapp 版本在这些入口下的实测行为，
不能归因成某个 UI 框架必然不支持，也不能断言不存在其他可用机制。**
产品仍采用已有的普通后台启动路径，遇到用户已经运行 Setapp 时跳过；
未加入独立实例、延迟隐藏或退出用户现有进程的行为。

### 检测更新忙碌状态：活动会话，而非数据库时间（2026-11-04）

为确定退出时机，使用独立 Swift 探针监听跨进程通知，每 250 ms 读取数据库文件属性、
Paste 的实际版本；第二个探针还只读 Setapp 偏好中包含 `ActiveRefreshSession_` 的键。
以下记录接入自动退出前的调查；最终实现与验证见后面的“自动 refresh 生命周期”。

- `Apps.sqlite` 是目录数据，没有下载/安装任务进度表；另查
  `SetappVersions.sqlite`（客户端发版）、`apollo_db.sqlite`（Apollo records）、
  Agent 的 `Cache.db`（URL cache），均未找到可直接使用的任务表。
- 无需更新的对照：Paste 已为官方 7.0.5 / 29895801，后台启动后未发生安装，
  `Apps.sqlite-wal` 仍由 32768 字节变为 2286632 字节并更新 mtime；主 SQLite 文件 mtime
  保持不变。**主文件 mtime、WAL mtime/大小均不能作为安装忙碌或完成的判断。**
- SetappInterface 的 `AFXAppsRefreshSynchronizer` 用偏好保存活动会话：
  `ActiveRefreshSession_-reason_internal<UUID>`（前面还可能带环境/账号前缀），
  值为开始日期；结束时删除。外部 `UserDefaults(suiteName: "com.setapp.DesktopClient")`
  可实际读到从空 → 一个 → 两个 → 一个 → 空的变化，无需加载厂商 framework。
- 同时收到分布式通知 `com.setapp.apps-refresh-will-start` 与
  `com.setapp.apps-refresh-did-end`；`userInfo` 中
  `com.setapp.apps-refresh-process-id` 是**会话 UUID，不是操作系统 PID**。
  启动前开始监听并按 UUID 维护集合，不能收到任意一次 did-end 就认为整个更新结束。
- 去掉 Paste 专属下载缓存、再次触发自动更新的时间线（探针起点为 0 秒）：
  3.883 秒第一个会话开始，4.348 秒第二个开始，5.961 秒第一个结束；
  7.905 秒实际版本恢复官方 7.0.5 / 29895801，7.916 秒收到
  `com.setapp.app-vendor-instances-installed`，7.929 秒第二个会话结束，
  8.136 秒偏好中的活动会话归零。安装成功且签名有效。
  另一轮无下载缓存也得到同样的“第二个会话在安装完成后结束”的顺序。
- 会话包括检查目录、下载和安装，所以它是保守的“Setapp 正忙”信号，
  不是单个应用的百分比进度，也不能证明 did-end 就一定更新成功（失败也会结束）。
  应以应用包版本达到预期作为成功依据。
- 二进制中有旧的 `com.setapp.app-updater.progress-status` 通知及 `appID`、
  `progress`、`status` 字段；但本次缓存更新和两轮无缓存自动更新均未收到该通知，
  不能凭符号存在就采用它。现代 Agent 的日志确有
  `ApplicationManagementInterface.ProgressInfo(progressValue:state:appInstance:)`
  经 IPCCore `UpdateEntityRequest(storageKey: "AppKey", key: "appsData", ...)` 发送，
  尚未验证外部进程可读取该 IPC 状态；不将其描述成现成可用的进度接口。
- 厂商自身会把超过 300 秒的会话日期视为过期（`activeRefreshSessionsWithReason:`），
  所以“键消失/过期”不能单独证明一次很慢的下载已完成。这些也是厂商内部协议，
  后续版本变动或漏通知时须保守处理，不能直接强制结束客户端。

建议退出策略：已知无更新则不启动；只管理本次启动的客户端，用户使用后放弃自动退出；
活动会话未结束时不按 30 秒强行退出，全部会话结束后等待 30 秒无新活动再正常请求退出。
应用实际更新完成可以重置这段空闲时间，同一应用同一目标只记一次；
若观察始终不收敛，停止自动管理并保留客户端，避免无限计时或误杀下载。

本地证据：`/tmp/setapp-progress-control.log`、`/tmp/setapp-progress-update.log`、
`/tmp/setapp-progress-download.log`、`/tmp/setapp-progress-sessions.log`；
探针源文件 `/tmp/setapp-progress-probe.swift`、`/tmp/setapp-progress-sessions-probe.swift`。

### 自动 refresh 生命周期（2026-11-04）

`SetappBackgroundUpdates` 已接入检查结束的自动触发路径，手动点击行按钮仍属于用户操作。
DuoUpdater 开关默认开启，但关闭任一侧自动更新开关、不存在可用 offer、已忽略、订阅 hold、
客户端已运行，均不自动启动；启动前再次读取应用包版本，避免旧结果触发多余启动。
Beta/stable 检测继续读取 Setapp 的 beta 开关所选目录。

- 普通不激活启动，不传 `hides`、不创建第二实例、不跳转未验证的 Updates 深链。
- 启动前注册会话和工作区监听；绑定返回的 `NSRunningApplication`、PID、启动日期和路径。
  若启动日期早于请求或身份不确定，保留客户端。
- 同时读取活动会话日期并按 UUID 配对通知；全部会话结束后空闲 30 秒才正常请求退出。
  目标版本实际落盘会重新计时，每个路径只计一次，反复读到同一版本不会无限延期。
- 用户激活会永久结束本轮管理；原进程退出、更换 PID/启动时间或出现其他客户端实例，
  立即放弃管理，不把计时器转交给新进程。退出前还会再次验证身份和使用状态。
- 无会话证据且目标未完成时，30 秒后只停止管理；状态不可读、格式异常、过期会话，
  或总观察时间达到 10 分钟，同样保留客户端。不强制退出，不重试被拒绝的退出请求，
  不退出 SetappAgent、Launcher 或 Assistant。

验证使用直接链接当前 Core 库的原生测试程序执行生产控制器，普通退出轮：
VM Setapp 3.58.0 (163)，Paste 从测试标记 7.0.4 / 1 更新回官方 7.0.5 / 29895801；
PID 63303 于上海时间 22:37:52 启动管理，22:38:26 正常退出请求成功，后续进程列表为空。
无更新轮直接返回 `managing=false`，没有启动客户端。

用户接手轮使用 LaunchServices 启动同一 Core 测试程序进入桌面会话：第 8 秒模拟打开
Setapp，第 9 秒 `front=com.setapp.DesktopClient`、PID 63524 active=true、管理已停止；
第 10 秒切回 Terminal 后至第 45 秒，仍是同一 PID 且未被关闭。
退出重开轮：原 PID 63577 在第 8 秒正常退出，第 9 秒管理停止；第 10 秒重新打开
得到 PID 63604，至第 45 秒仍保持运行，计时器没有转交给它。
先前锁屏下的激活尝试没有实际激活客户端，不计为用户接手验证。

40 项 Setapp Core 测试与 326 项应用测试通过，Debug 应用构建通过；
本地化键/占位符、off-pool、版本比较、macOS 15 back-deployment 检查通过。
本地证据包括 `/tmp/setapp-lifecycle-normal.log`、
`/tmp/setapp-lifecycle-adopt-gui-host.log`、`/tmp/setapp-lifecycle-replace-gui-host.log`、
`/tmp/setapp-lifecycle-no-update.log` 与 `/tmp/setapp-lifecycle-existing-pending.log`。

## Beta

- 「Beta」是**客户端级**开关，不是 per-app：Settings → Updates 的原文是
  「Get beta versions of Setapp and installed apps」，「This setting will apply to future
  updates of Setapp and installed apps」，存成 `AllowBetaInternalUpdates`（0/1）。
- **beta 是第二个公开目录，不是参数**（2026-11-04 实测）：客户端（`SetappAgent`）自己的
  URL 缓存里有两个请求——
  `https://store.setapp.com/store/api/v8/en` 和 `https://store.setapp.com/store/api/v8/beta/en`。
  后一个**无需任何凭据**（只带 `accept: application/vnd.api+json`）就返回 3.06 MB：
  325 个 vendor、1076 条版本，其中 15 条带 `beta: true`（Bartender 7.0.3/700010、
  7.1.0/700013、Dropshare 6.16、Soulver 4.0、AirBuddy 3.1、PopClip 2023.7.0、Usage 2.16.4、
  BetterTouchTool 6.557 等）。
- ⚠️ **beta 目录不是稳定目录的超集**（同一天按 bundle id + 版本 + 构建逐条比对：
  stable 1074 条、beta 1076 条；beta-only 14 条，**stable-only 也有 12 条**）。有 beta 的
  app，beta 目录用 beta 行**替换**它当前的稳定行：WiFi Signal 4.4.8 (49) → 4.4.9 (50) beta、
  Dropshare 6.15 (6266) → 6.16 (6282) beta、KeyKey 3.0 (131) → 3.0.3 (137) beta。
  所以**不能总是读 beta 再过滤 beta 行**：Beta 关的用户会因此看不到这 12 个稳定版
  （Dropshare 6.15 会从有更新变成查无此版本）。开关关读 `/en`、开读 `/beta/en`，
  两个目录各自缓存；beta 目录只在「已装副本比稳定目录新」时旁读一次，用来认领
  「这是 beta 副本」。
- 之前的「公开目录里没有 beta」只对 `/store/api/v8/en` 成立；`?beta=1`、`?include_beta=true`、
  `X-Setapp-Beta` 这些猜测当然都无效——路径本身才是开关。
- 客户端的行为与此一致：开关关时只拉稳定目录（`Apps.sqlite` 里 1073 行、0 行
  `ZISBETA=1`）；开关开时拉 beta 目录（15 行 `ZISBETA=1`）。
- 所以 DuoUpdater 在开关打开时读 beta 目录、关时读稳定目录：beta 用户可以正常比较版本，
  稳定用户永远不会被塞 beta。版本行用 `(Setapp Beta)` 标出目录里 `beta: true` 的已装版。

## 如何复验

```bash
# 渠道版本：公开目录，无需客户端在跑
curl -s -H 'accept: application/vnd.api+json' \
  https://store.setapp.com/store/api/v8/en | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); ...'   # 找 bundle_id 的 versions[0]

# 订阅状态（NSDate；defaults 会显示成带引号的字符串）
defaults read com.setapp.DesktopClient known_customers

# 深链是否被接受/它做了什么
open 'setapp://install/<数字 id>'
log show --last 2m --info --predicate 'process == "SetappAgent" AND eventMessage CONTAINS "InstallAppFromURL"'

# 客户端关掉后它是否还在后台检查
open -a Setapp && log show --last 5m --predicate 'process == "SetappAgent" AND eventMessage CONTAINS "update conditions"'
```

代码侧：`SetappCatalog`（目录解析/缓存）、`SetappSubscription`（账号状态）、
`SetappCatalogSource`（`SourceStack` 里排在 Sparkle 之前）。验证问句：
「一个 `-setapp` 副本不再落到 `SparkleAppcastSource`」，以及「订阅无效时版本被 hold 而不是被 offer」。
