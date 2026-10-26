# AppFlowy

## 基本信息
- App: AppFlowy — 开源的笔记 / 数据库 / 工作区 app（Flutter 前端 + Rust 后端），AGPL-3.0
- Bundle ID: `com.appflowy.appflowy.flutter`（0.2.0 起；0.0.x–0.1.6 是 `com.appflowy.macos`，见覆盖清单）
- 仓库: `AppFlowy-IO/AppFlowy`（默认分支 `main`；`main` 最后一次提交 2026-06-26，此后的 0.13.x / 0.14.x 发布不是从公开的 `main` 构建的，见「自更新机制」）
- Team ID: `VHB67HRSZG`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 0.14.11（tag `0.14.11`，资产 `AppFlowy-0.14.11-macos-arm64.dmg` / `-macos-universal.dmg`）；上一版 0.14.10；观测日期: 2026-10-26
- 自更新机制: **分两段，都不会就地换包和我们抢**
  - **0.14.10 起（含 0.14.11）**: 包里没有 `Sparkle.framework`、没有 `auto_updater_macos.framework`、没有 `SUFeedURL`。Rust 可执行文件里有 `/api/desktop-update`、`invalid desktop-update Cloud URL` 和 `[UpdateCompat] candidate= … server=`；Dart 侧有 `_openDownload`、`[AutoUpdate] could not open download:`。英文文案 `autoUpdate.downloadInstructions` = "Download the installer, then open it to update AppFlowy."，`serverTooOldDescription` = "Version {newVersion} is available, but this workspace's server (version {serverVersion}) doesn't support it yet…"。即：问它连着的 AppFlowy Cloud 服务器有没有新版，再按服务器版本决定提示还是暂停（"Update paused"），提示时让用户自己去下安装包。可执行文件里拼下载地址用的是 `https://github.com/AppFlowy-IO/AppFlowy/releases/download/` + `aarch64` / `x86_64`。`/api/desktop-update` 的请求参数没在公开源码里（`AppFlowy-IO/AppFlowy-Cloud` 的 `main` 里搜不到这个路由），对 `beta.appflowy.cloud/api/desktop-update` 直接 GET 回 400，没继续猜参数
  - **0.14.8 及更早（真包核过 0.13.2、0.14.5、0.14.7、0.14.8）**: 带 `Sparkle.framework` 2.8.1 + `auto_updater_macos.framework`，`SUPublicEDKey` = `Bs++IOmOwYmNTjMMC2jMqLNldP+mndDp/LwujCg2/kw=`，Info.plist 没有 `SUFeedURL`。settled from source: `frontend/appflowy_flutter/lib/startup/tasks/auto_update_task.dart` 与 `lib/shared/version_checker/version_checker.dart` on `main`：feed 在代码里设，`https://github.com/AppFlowy-IO/AppFlowy/releases/latest/download/appcast-{os}-{arch}.xml`（`macos-arm64` / `macos-x86_64`），并 `setScheduledCheckInterval(0)` 关掉定时检查——只在用户点「Update」时让 Sparkle 检查和安装
  - 0.14.11 这个 release **没有** `appcast-macos-*.xml` 资产（只有 `desktop-update.json` = `{"version": "0.14.11", "minimum_server_version": "0.19.10"}`），所以 2026-10-26 上面那个 `latest/download` 地址两种架构都回 404：0.14.8 及更早的副本自己的更新器眼下看不到任何版本
- 分发: GitHub Releases（每版 arm64 / universal / x86_64 三个 dmg，加 arm64 / universal zip）；Homebrew cask `appflowy`（0.14.11，装 `-macos-universal.zip`，没有 `auto_updates`，`depends_on macos >= 12`）；官网下载页（`appflowy.com/download`）是前端渲染，curl 拿到的 HTML 里没有安装包链接，没核它指向哪里；App Store 上同 bundle id 的是 iOS/iPadOS 版（`itunes.apple.com/lookup` 返回 trackId 6457261352，0.14.10）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✗（feed 在代码里且 0.14.10 起不再带 Sparkle） | cask 无 `auto_updates`：Caskroom 里有它（brew 装的）的副本由 `HomebrewCaskSource` 先回答，其余副本落到 GitHub | 商店副本（iPad 版）走 MAS 源 | ✓ | —（`/api/desktop-update` 参数未知） |

当前生效源: **GitHub**（channel-verify 实测 0.13.2 / 0.14.10 / 0.14.11 三个真包都是 `winning source GitHub`，见「如何复验」）。没有 `SUFeedURL`、没有 `app-update.yml`、没有 MyGo feed。

**为什么不走通用 Sparkle 源 / `SparkleFeedCatalog`**: `feed-discover` 对 0.13.2 报 `review feedUnparseable`（候选 `https://github.com/AppFlowy-IO/AppFlowy/releases/latest/download/appcast-`，即模板里的 `{os}-{arch}`），对 0.14.11 报「no Sparkle, no electron-builder update config and no MyGo feed」。就算按架构写一条 catalog，那个地址 2026-10-26 回 404，且 0.14.10 起的包不再读它；GitHub 规则对新旧副本都答得出，应当是 GitHub 赢。

## 覆盖清单
- 各版本的 bundle id / Team（读真包）:
  - 0.14.11 arm64 / universal: `com.appflowy.appflowy.flutter`，Team VHB67HRSZG，Notarized
  - 0.14.10 arm64 / universal: 同上
  - 0.14.8、0.14.7、0.14.5、0.13.2 arm64: 同 id、同 Team（这几版带 Sparkle）
  - 0.4.1 universal（scaffold 读的列表里最老的一版）: 同 id、同 Team
  - 0.3.0、0.3.2 x86_64: 同 id、Team VHB67HRSZG —— Team 从 0.3.0 开始
  - 0.2.0、0.2.8、0.2.9 x86_64: `com.appflowy.appflowy.flutter`，**ad-hoc**（`TeamIdentifier=not set`）
  - 0.0.2、0.0.9、0.1.0、0.1.6 x86_64: **`com.appflowy.macos`**，ad-hoc —— 改名在 0.2.0（2023-06-08）
- 其他轨: 没有 beta / nightly 轨。153 个 release 里 3 个标了 `prerelease`（0.6.0、0.9.0、0.12.3），资产名与正式版同形，各自后面紧跟正式版（0.6.1、0.9.1、0.12.4），是单个版本被标记，不是一条轨；`/releases/latest` 跳过它们。2022 年的 `0.0.4_beta.N`、`0.0.5_beta.N` 只有 x86_64 zip、旧 id，`versionPattern` 读不出（锚定），不会被当成稳定版。cask 没有 `@beta` / `@nightly` 变体
- 版本范围: tag 没有 `v`，`^([0-9]+(?:\.[0-9]+)+)$` 读得出所有正式 tag（含四段 `0.6.7.2`、`0.3.9.1`）；scaffold 实测 97/97。0.14.9 没有 release（列表从 0.14.8 跳到 0.14.10）
- 资产名: 0.3.3 起 `AppFlowy-<v>-macos-<arch>.dmg`（0.3.2 及以前是 `AppFlowy_<v>_macos-…`），arm64 资产从 0.8.5 开始；0.14.8 **只有** arm64 dmg/zip，没有 universal 和 x86_64。所以 install pattern 只取 `-macos-arm64\.dmg`：0.8.5 → 0.14.11 的每个正式 release 恰好一个匹配、文件名里的版本与 tag 相同（全表脚本核过），也是厂商自己 arm64 appcast 的 enclosure。DuoUpdater 只跑在 arm64 上，用不到 universal / x86_64
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；AppFlowy `LSMinimumSystemVersion` 12.0，不需要 `hostRequirement`
- 缺口 1 —— 旧 id `com.appflowy.macos`（0.0.x–0.1.6）: 不接。`BundleIDMigration` 要求两个 id 同一个 Team，而这些版本是 ad-hoc、没有 Team；而且只有 x86_64 构建，是 2023 年 6 月以前的版本。它们在列表里显示为没有更新源
- 缺口 2 —— 0.2.x（新 id、ad-hoc）: 检测有，一键被 Team 闸拒（装着的副本没有 Team）。`.publishedDigestOnly` 不适用：新版本有 Team，走的是正常 Developer ID 闸。用户手动装一次之后就能一键
- 商店副本: 同 id 的 iPad 版装在 Apple 芯片 Mac 上是商店副本，按 receipt 识别，GitHub 源不应答（引擎已有的结构性闸，不是本 rule 的事；本次没有商店副本可测）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.appflowy.appflowy.flutter` | — | — | GitHub `/releases/latest` | ✓ |

只有一条轨（见覆盖清单「其他轨」）。

## 更新检测
- 源: `AppFlowy-IO/AppFlowy` GitHub Releases，`/releases/latest`
- 版本方案: tag `0.14.11` → `CFBundleShortVersionString` `0.14.11`、`CFBundleVersion` `0.14.11`。旧 appcast 里 `sparkle:version` 写的是 `2`，不影响我们（GitHub 规则只比 short version）
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`（锚定：`0.0.5_beta.2`、`1.0.0-rc.1` 不匹配）
- install pattern `^AppFlowy-[0-9]+(?:\.[0-9]+)+-macos-arm64\.dmg$`。同一个 release 里另外的 universal / x86_64 dmg、两个 macOS zip、Android / Linux / Windows 包、`desktop-update.json`、`appcast-*.xml` 都不匹配
- **读的是**: 轨道最新的 GA，人人可手动下载；AppFlowy 自己的新版更新器把用户带去下载的也是同一个 release 的资产。厂商没有灰度
- 注意: AppFlowy 自己的更新器会按「这个工作区的服务器版本」暂停更新（见已知问题），我们的规则看不到服务器版本

## 按架构 / 按 OS 分轨
- 每版 arm64（`archs=arm64`，约 116 MB）、universal（`x86_64 arm64`，约 225 MB）、x86_64 三个 dmg；一键装 arm64 dmg。手动装了 universal dmg / zip 的副本会被换成 arm64 版（brew 装的副本由 `HomebrewCaskSource` 回答，不走这条规则），在 arm64 主机上无影响（厂商自己的 Sparkle 在 arm64 上也是装 arm64 dmg）
- `LSMinimumSystemVersion` 12.0；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 0.14.8 及更早有（Sparkle 2.8.1 自带 BinaryDelta）；0.14.10 起无 | 无 | — |
| 证据 | 0.14.10 / 0.14.11 包里没有 Sparkle；旧包 `Frameworks/Sparkle.framework` 2.8.1 | 2026-10-26 读 0.14.10 的 `appcast-macos-arm64.xml`：一个 item，只有整包 enclosure，没有 `<sparkle:deltas>`；0.14.11 没有 appcast | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 0.14.10 起不会；0.14.8 及更早只在用户点「Update」后由 Sparkle 下载 | 没查（真机第二轮由主会话做） | 不需要 / ○ |
| 证据 | 新版只打开下载链接（`downloadInstructions` 文案、`_openDownload`），安装包由浏览器下到用户的下载目录；旧版 Sparkle 定时检查被关（`setScheduledCheckInterval(0)`），且 feed 目前 404 | — | `SelfUpdaterStash` 只读 electron-updater 与 Cindy 的布局，不读 Sparkle 缓存；旧版 feed 404，眼下也不会有暂存 |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，三个包同一行）: `source structured: 1 entries; newest 0.14.11: 12 items, headings ["New Features", "Improvements", "Bug Fixes", "⚠️ Action Required"]; first items ["**Relative-date comparisons** — Added To", "**YouTube captions** — Added direct impo", "**Missing row pages** — Added a "Create "]`
- 标题保留、没被压平：正文 `#### New Features` 3 条 + `#### Improvements` 3 条 + `#### Bug Fixes` 5 条 + `#### ⚠️ Action Required` 1 条 = 12；最上面的 `### 🚀 v0.14.11` 只是版本号，没有条目
- 「Action Required」那一节写的就是自托管服务器要 AppFlowy Cloud v0.19.10 以上，会原样出现在 changelog 里
- 跟随 channel: 只有一条轨
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Team VHB67HRSZG 的副本，即 0.3.0 及以后）
- 端到端: **待主会话**（真机从上一版装到最新版）
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `AppFlowy.app` + `Applications` 软链 + `.background`
- 嵌套 / 常驻组件: 无。`Contents/` 下只有 `Frameworks`（Flutter 插件、Firebase、mpv 等 `.framework`，没有 `.app`）、`MacOS/AppFlowy`、`Resources`、`_CodeSignature`；没有 LoginItems / Helpers / XPCServices / LaunchAgent / 系统扩展；可执行文件里没有 `SMAppService`、`LaunchAgents`、`.claude/`、`.agents/`、`.codex/` 字符串（`grep -c` = 0）
- 签名: 0.3.0 → 0.14.11 读过的包都是 Team `VHB67HRSZG`、Notarized，Team 没换过；0.2.x 及更早是 ad-hoc（见覆盖清单）
- 校验: GitHub 资产 `digest`。0.14.11 arm64 dmg `sha256:968d6859adba1ea8720edd57b1cff7cd705d691ba1c265d1f6599f2b15514ea5`（116110311 字节）、universal dmg `sha256:50da706a87bdbd44a128001ab4cc1bba96fa6e105ff299cdf9fd248869fb9774`（225569716 字节）；0.14.10 arm64 dmg `sha256:21f98db612c735b84fcf315b8fb5f4cb6460c7558eca1b73fe407bfab638e286`、universal `sha256:817548f9eab169db155fb0ea978f9d896d74e84d3f5805fb7fcea5444a371711`。四个下载文件的 `shasum -a 256` 与之相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 阻塞: 无
- 主会话真机要注意（来自包内容与源码，均未在真机上观察）:
  - entitlements: 非沙盒，`files.absolute-path.read-write` 临时例外 `/`、麦克风、屏幕录制、`network.server`。首启可能请求通知权限（`flutter_local_notifications`、Firebase Messaging）；会议转写功能才要麦克风 / 屏幕录制，不点就不弹
  - 首启大概率先出登录 / 选本地或云端工作区的界面（推断，未验证）；不要登录。数据在 `~/Library/Application Support/com.appflowy.appflowy.flutter`（cask `zap` 列出的路径）
  - URL scheme `appflowy-flutter`、`appflowy-picker`
  - 从 0.14.10 启动不会自己换包；它若提示新版，只会打开下载链接
  - 想测「运行中、自己的更新器已暂存」那一轮只能用 0.14.8 及更早的 Sparkle 副本，而它们的 feed 现在 404，造不出暂存

## 已知问题
- **客户端与服务器版本绑定**: 包里内嵌的 `desktop_server_compatibility.json` 写明 0.14.9 起的客户端要 AppFlowy Cloud 0.19.10 以上（0.14.6 → 0.19.0、0.14.4 → 0.18.9 …）。AppFlowy 自己的更新器在工作区服务器太旧时会暂停更新（"Update paused"）；我们的 GitHub 规则看不到服务器版本，会照常提示并一键安装。连官方 AppFlowy Cloud 的用户不受影响；连自托管旧服务器的用户装上新版后，按厂商文案是 "Requires server {requiredServerVersion} or later. Some features may be unavailable."——不是装不上，是部分功能不可用（文案推断，未在真机验证）。release 正文的 「⚠️ Action Required」 一节也写了这条，会出现在 changelog 里
- 旧 id `com.appflowy.macos`（0.0.x–0.1.6，ad-hoc、只有 x86_64）没有接，原因见覆盖清单
- 0.2.x 副本（ad-hoc）一键被 Team 闸拒，需手动装一次
- 0.14.8 及更早副本自己的 Sparkle feed 目前 404（0.14.11 没发 appcast），它们只能靠我们或手动更新

## 如何复验
```bash
gh release view 0.14.11 -R AppFlowy-IO/AppFlowy --json assets -q '.assets[]|select(.name|test("macos"))|.name+" "+.digest'
gh release download 0.14.11 -R AppFlowy-IO/AppFlowy -p 'AppFlowy-0.14.11-macos-arm64.dmg'
gh release download 0.14.10 -R AppFlowy-IO/AppFlowy -p 'AppFlowy-0.14.10-macos-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh AppFlowy-0.14.10-macos-arm64.dmg   # Team VHB67HRSZG, Notarized, SUFeedURL none
swift run --package-path application-test feed-discover AppFlowy-0.14.11-macos-arm64.dmg      # no Sparkle, no electron-builder, no MyGo
swift run --package-path application-test channel-verify AppFlowy-0.14.10-macos-arm64.dmg --expect stable   # GitHub, UPDATE → 0.14.11
swift run --package-path application-test channel-verify AppFlowy-0.14.11-macos-arm64.dmg --expect stable   # up to date
curl -sSIL -o /dev/null -w '%{http_code}\n' https://github.com/AppFlowy-IO/AppFlowy/releases/latest/download/appcast-macos-arm64.xml   # 2026-10-26: 404
```

channel-verify 原始输出（2026-10-26，节选）:
```
0.14.10 arm64 dmg:
  detected channel  → stable
  ✓ detection matches --expect stable
    SUFeedURL       <none>
    winning source  GitHub
    latest          0.14.11
    download        https://github.com/AppFlowy-IO/AppFlowy/releases/download/0.14.11/AppFlowy-0.14.11-macos-arm64.dmg
    changelog pane  source structured: 1 entries; newest 0.14.11: 12 items, headings ["New Features", "Improvements", "Bug Fixes", "⚠️ Action Required"]; …
    status          UPDATE → 0.14.11
0.14.10 universal dmg:  winning source GitHub; latest 0.14.11; download …-macos-arm64.dmg; status UPDATE → 0.14.11
0.14.11 arm64 dmg:      winning source GitHub; latest 0.14.11; status up to date
0.14.11 universal dmg:  winning source GitHub; latest 0.14.11; status up to date
0.13.2 arm64 dmg (带 Sparkle): SUFeedURL <none>; winning source GitHub; latest 0.14.11; status UPDATE → 0.14.11
```

## 建议下一步
1. 真机一键（主会话）: 装 0.14.10 → `duo install`，看换成 0.14.11 arm64、Team 不变、`codesign` / `spctl` 通过
2. 自托管服务器的版本绑定要不要管（待用户决定）: 要像厂商那样「服务器太旧就不推」，得读 AppFlowy 本地存的当前服务器地址并问它的 `/api/server-info`，是引擎改动（新的 scan-time 读取或 `OneClickGate` 条件），本次没做
3. 若厂商以后在 release 里恢复 `appcast-macos-*.xml`，0.14.8 及更早副本的 Sparkle 会重新可用；那仍是用户点了才装，不影响本规则
