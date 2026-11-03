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

## Beta

- 「Beta」是**客户端级**开关，不是 per-app：Settings → Updates 的原文是
  「Get beta versions of Setapp and installed apps」，「This setting will apply to future
  updates of Setapp and installed apps」，存成 `AllowBetaInternalUpdates`（0/1）。
- **公开目录里没有 beta**：`versions[].attributes` 只有
  `archive_url / build_number / marketing_version / min_os_version / release_date / size /
  supported_apple_silicon / supported_architectures / supported_languages`；给
  `store/api/v8/en` 加 `?beta=1`、`?include_beta=true` 或 `X-Setapp-Beta` 之类的猜测都返回
  同一份稳定目录。
- Beta 版确实存在，而且只有客户端在开关打开时才取到：清掉 `Apps.sqlite` 后重新拉取，
  关 Beta = 1073 行里 0 行 `ZISBETA=1`；开 Beta = 15 行 beta，例如
  Bartender 7.0.3 (700010) / 7.1.0 (700013)、Dropshare 6.16、Soulver 4.0、AirBuddy 3.1、
  PopClip 2023.7.0、Usage 2.16.4、BetterTouchTool 6.557。
- 所以 DuoUpdater 读公开目录时永远只看到稳定版：Beta 用户如果 Setapp 里已有更新的 beta，
  我们读不到——这是刻意的（不把 beta 当稳定版塞给所有人），要写进结果里。

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
