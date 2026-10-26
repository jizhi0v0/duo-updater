# AltTab

## 基本信息
- App: AltTab — 开源窗口切换器（`lwouis/alt-tab-macos`，默认分支 `master`），菜单栏常驻（`LSUIElement=true`）。v11.0.0 起加了付费的 AltTab Pro（14 天试用，过期后免费功能照常可用）
- Bundle ID: `com.lwouis.alt-tab-macos`
- 仓库: `lwouis/alt-tab-macos`
- Team ID: `QXD7GW8FHY`（Developer ID Application: Louis Pontoise）；`codesign --verify --deep --strict` 通过；spctl: accepted / Notarized Developer ID（11.10.1、11.10.0 真包）
- 观测版本: 11.10.1（tag `v11.10.1`，资产 `AltTab-11.10.1.zip`，`CFBundleShortVersionString` = `CFBundleVersion` = 11.10.1）；上一版 11.10.0；观测日期: 2026-10-26
- 自更新机制: **Sparkle 2，feed 在代码里设**。settled from source: `src/vendors/SparkleDelegate.swift` 的 `feedURLString(for:)` 返回 `Endpoints.appcastUrl`，`src/api/Endpoints.swift` 里是 `"https://\(domain)/appcast.xml"`，`domain` 读 Info.plist 自定义键 `Domain`（= `alt-tab.app`）。所以二进制里没有完整的 feed 字面量（`strings` 只有 `/appcast`、`feedURLStringForUpdater:`），Info.plist 也没有 `SUFeedURL`。`SUPublicEDKey` = `2e9SQOBoaKElchSa/4QDli/nvYkyuDNfynfzBF6vJK4=`，`SUEnableAutomaticChecks=true`，`SUScheduledCheckInterval=604800`
- 分发: GitHub Releases（每版一个 `AltTab-<version>.zip`，外加 `AltTab.app.dSYM.zip`、`Sparkle.framework.dSYM.zip` 两个调试符号包）；Homebrew cask `alt-tab`（11.10.1，`url` 就是 GitHub 资产，sha256 `aa353197…f594c` 与 GitHub digest 一致，**`auto_updates: true`**）；没有 MAS 版（iTunes lookup 按 bundle id 0 结果）；官网 `alt-tab.app/download` 的下载链接也是同一个 GitHub zip
- 厂商近况: 活跃，2026-10 发了 5 个版本；仓库未归档

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓（只对声明了 `SUFeedURL` 的 ≤10.12.0 副本；11.x 见下） | —（`auto_updates: true`，`HomebrewCaskSource` 让路） | — | ✓（11.x 副本，本次接入） | — |

当前生效源（`SourceStack` 中第一个应答的）:
- **11.0.0 起的副本: GitHub**（channel-verify 实测，见下）
- **3.0.0–10.12.0 的副本: Sparkle**（自己的 `SUFeedURL`；用改了版本号和 `SUFeedURL` 的替身包实测，见下）
- 1.x–2.3.4 的副本: GitHub（没有 Sparkle，见覆盖清单）

### 为什么 11.x 走 GitHub 而不加 `sparkleFeeds` 补位
- 通用 Sparkle 源**不覆盖** 11.x：`AppScanner` 只读 `SUFeedURL`；`feed-discover` 对 11.10.0 真包给 `review noCandidate`（地址是运行时拼的，二进制里找不到候选）
- 两个 feed 内容相同（2026-10-26 实测）：`https://alt-tab.app/appcast.xml` 与旧版声明的 `https://raw.githubusercontent.com/lwouis/alt-tab-macos/master/appcast.xml` 逐字节相同（`cmp`）。前者 Cloudflare、`cache-control: public, max-age=0, must-revalidate`
- appcast 与 GitHub 等价：295 个 `<item>`，版本集合 = tag 里 3.0.0 起的全部版本（`comm` 两边差集只有 3.0.0 之前的 tag），每个 enclosure 都是 `github.com/lwouis/alt-tab-macos/releases/download/v<ver>/AltTab-<ver>.zip`。没有 `<sparkle:channel>`、`<sparkle:deltas>`、`phasedRolloutInterval`、`criticalUpdate`。appcast 由 `scripts/update_appcast.sh` 在 semantic-release 里生成并提交到 `master`（`release.config.js`），和 GitHub release 同一次 CI；11.10.1 的 item `pubDate` 21:56:58，release `published_at` 21:57:28
- 代码里能按许可分发，但服务端现在不分：`feedParameters` 带 `version`/`macos`/`arch`/`lang`/`tier`（`trial`/`pro`/`proExpired`/`trialExpired`/空）和试用天数 `day`；`src/pro/license/LicenseCookie.swift` 还在 alt-tab.app 域上写 `license` cookie，注释说是「so Sparkle's appcast request can be tailored per tier」。实测 6 组参数（含 `tier=pro`、`tier=trialExpired`、`version=9.0.0`、x86_64/macOS 12）× 3 种 cookie（`license=pro` / `proExpired` / 空），响应体全部与无参数请求逐字节相同。两条路线都拿不到 app 自己的 cookie，所以将来真按许可分发时两者一样看不到
- 实测加 `sparkleFeeds` 补位的效果（临时改动，已撤回）：11.10.0 真包 `winning source Sparkle`、`latest 11.10.1`、同一个下载 URL，但 `changelog pane  web page https://alt-tab.app/changelog-bare, no structure`（`releaseNotesLink` 是一个 277 KB、含全部版本的 HTML 页）。GitHub 路线是结构化的。检测和下载都一样，只有 changelog 变差，所以 11.x 选 GitHub；同时不加补位，免得 Sparkle 排在前面把这条 rule 变成看着活着、实际不跑的 rule
- 一旦加了补位，这条 rule 就不再被问到；反过来也一样。两者只留一个

## 覆盖清单
- 各版本的 bundle id / Team（真包读了 11.10.1、11.10.0，scaffold 读了 11.0.0；更早的 release 已从 GitHub 删除，资产 URL 返回 404，只能读源码）:
  - v11.10.1 / v11.10.0 / v11.0.0（真包）: `com.lwouis.alt-tab-macos`，Team `QXD7GW8FHY`，版本等于 tag
  - v1.0.0–v2.3.4（源码 `project.pbxproj`）: 同一个 `PRODUCT_BUNDLE_IDENTIFIER`，`CODE_SIGN_IDENTITY = "-"`（ad-hoc），Info.plist 无 Sparkle 键 → 只有 GitHub rule 能检测它们；一键被 Team 闸拒（已装副本无 Team）。这些是 2019–2020 的版本
  - v3.0.0–v10.12.0（源码 `config/base.xcconfig`、`config/release.xcconfig`、`Info.plist`）: 同一 bundle id，签名身份 `Developer ID Application: Louis Pontoise (QXD7GW8FHY)`，`SUPublicEDKey` 与 11.x 相同。`SUFeedURL`：v3.0.0–v10.11.0 是 raw.githubusercontent `master/appcast.xml`，v10.12.0 是 `https://alt-tab.app/appcast.xml`，v11.0.0 起删掉。这组由通用 Sparkle 源回答（见下），不经这条 rule
  - 没有改名、没有别的产品共用这个 id
- 其他轨: 无。22 个 release 都不是 prerelease；355 个 tag 除一个 `untagged-19c8fc4a79be90a01a97`（draft 残留，`versionPattern` 不匹配）外都是 `vX.Y.Z`；semantic-release 只发 `master`，appcast 无 channel，源码没有 beta 开关（`allowedChannels` / `prerelease` 在 app 代码里 0 命中）。cask 只有 `alt-tab`，没有 `@beta`
- 许可状态（Pro / Pro Lifetime / 试用 / 试用过期 / Pro 过期 / 未开始试用）: rule 对每种状态给的都是 `/releases/latest`，与厂商 appcast 对所有 tier 的回答相同（上面实测）。`LicenseManager.versionLimitedVariants` 在 v11.10.1 是空字典，所以现在升级不会让任何许可变成 `.proExpired`。官网写明普通 Pro 只含「当前大版本」的更新、Pro Lifetime 含以后所有大版本，见已知问题
- 版本范围、主机下限: DuoUpdater 是 arm64、macOS 15.0；AltTab 11.x universal、`LSMinimumSystemVersion` 12.0（appcast 的 `minimumSystemVersion` 也是 12.0），无需门控
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$` 读全部 22 个 release 的 tag；`v12.0.0`、`v12.0` 可读，`v11.10.2-beta.1`、无 `v` 的 `11.10.1`、`untagged-…` 不匹配（Python `re` 核对）。install pattern 匹配 `AltTab-11.10.1.zip`、`AltTab-12.0.0.zip`，不匹配两个 `*.dSYM.zip`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.lwouis.alt-tab-macos` | — | 默认 | 11.x: GitHub `/releases/latest`；≤10.12.0: 自己声明的 Sparkle feed | ✓ |

## 更新检测
- 源: `lwouis/alt-tab-macos` GitHub Releases，`/releases/latest`（11.x）；通用 `SparkleAppcastSource`（≤10.12.0）
- 版本方案: tag `v11.10.1` → `CFBundleShortVersionString` `11.10.1`、`CFBundleVersion` `11.10.1`
- install pattern `^AltTab-[0-9]+(?:\.[0-9]+)+\.zip$`，kind `.zip`
- channel-verify（2026-10-26）:
  - 11.10.0 真包: `detected channel → stable`、`SUFeedURL <none>`、`winning source GitHub`、`latest 11.10.1`、`status UPDATE → 11.10.1`
  - 11.10.1 真包: `winning source GitHub`、`latest 11.10.1`、`status up to date`
  - ≤10.12.0 替身（11.10.0 真包改成 `10.11.0` + raw.githubusercontent `SUFeedURL`，另一份改成 `10.12.0` + alt-tab.app `SUFeedURL`）: 两份都是 `winning source Sparkle`、`latest 11.10.1`、下载 URL 同上、`release history 295 entries`、`status UPDATE → 11.10.1`。替身只证明「声明了这个地址的副本由 Sparkle 回答」，真的 10.x 包已无处下载
- Sparkle 签名: 用 `SUPublicEDKey` 验 appcast 里 11.10.1 的 `sparkle:edSignature`，对下载的 `AltTab-11.10.1.zip` 有效；同一签名对 11.10.0 的 zip 无效（反向对照）

## 按架构 / 按 OS 分轨
- 架构: 一个 universal zip（`lipo -archs` = `x86_64 arm64`）；`LSMinimumSystemVersion`: 12.0。appcast 每个 item 都有 `minimumSystemVersion`（10.12 / 10.13 / 10.14.4 / 12.0），无上限；与 GitHub 资产无分轨

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | — |
| 证据 | `Sparkle.framework/Versions/A/Autoupdate` 的 strings 有 10 处 `BinaryDelta`/`SUBinaryDelta` | 2026-10-26 的 appcast（295 项）没有 `<sparkle:deltas>`；release 只有整包 zip | 没有补丁可用 |

- 格式: Sparkle binary delta（客户端能力），厂商没发

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（仅当用户把更新策略设为自动安装） | 真机（2026-10-26）：按默认策略 `autoCheck` 运行 11.10.0，什么都没停放 | 不能（○） |
| 证据 | 源码：默认 `updatePolicy` = `autoCheck`（每周检查、弹框问）；选「自动安装」时 `automaticallyDownloadsUpdates = true`，Sparkle 下载后停放、退出时装（`src/events/PreferencesEvents.swift`） | — | `SelfUpdaterStash` 只读 electron-updater 和 Cindy 的布局，没有 Sparkle 的；`SelfUpdaterStaging.sparkleStagedBundle` 会发现停放的 Sparkle 安装器（app 带 `Sparkle.framework` 即可，不看 `SUFeedURL`） |

- 记录文件与字段: Sparkle 2 自身的缓存布局（`~/Library/Caches/com.lwouis.alt-tab-macos/org.sparkle-project.Sparkle/`），未在真机上看
- 容器: zip，包根是 `AltTab.app`
- 两份副本会不会共用这个目录: 会，Sparkle 的缓存只按 bundle id 分（`SelfUpdaterStaging` 里记的已知限制）

## Changelog
- 来源: 11.x 是 GitHub Release body（semantic-release 生成，`### Bug Fixes` / `### Features` / `### Performance Improvements` 分节），经 `GitHubMarkdownParser`；≤10.12.0 由 Sparkle 回答，是 `releaseNotesLink` 网页
- 结构化（2026-10-26，channel-verify `changelog pane`，从 11.10.0 起）: `source structured: 1 entries; newest 11.10.1: 2 items, headings []; first items ["keep shortcuts when upgrading from befor", "shortcuts fire without hold keys (closes"]`
  - 11.10.1 的正文只有一个 `### Bug Fixes` 和两条；只有一个标题时解析器按设计不显示它（`GitHubMarkdownParser` 要求同一正文里至少 2 个标题），两条都保留，没有压平
  - 11.10.0 那样有三个分节的正文，按同一规则标题应保留；**未实测**（pane 只显示最新一条）
- ≤10.12.0 的副本（替身实测）: `web page https://alt-tab.app/changelog-bare, no structure`。**不是结构化**：Sparkle 赢，而 feed 不内联说明，只给网页链接
- 跟随 channel: —（单轨）
- Recipe 状态: 11.x 不需要；≤10.12.0 要结构化需要一个 `ChangelogRecipe`（见建议下一步）

## 一键安装
- 状态: 支持（11.x 副本经 GitHub rule；3.0.0–10.12.0 副本经通用 Sparkle 源，EdDSA + 同一 Team；1.x–2.x 的 ad-hoc 副本被 Team 闸拒）
- 端到端（2026-10-26，本分支 `make cli` 的 duo，两轮通过）:
  - 第一轮（不运行）: 11.10.0 → `duo install`（`extracting` `verifyingCodeSignature` `installing` `installed`）→ 11.10.1、`TeamIdentifier=QXD7GW8FHY`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 11.10.0 用 `open -g` 启动（19:01:19），Sparkle 默认 `autoCheck`、没有停放任何东西。第一次 `duo install` 报 `the app scan did not finish within 20.0 seconds and was abandoned`（当时负载 160，三个 agent 在跑 `make test`）；重试 → 运行中就地装好，提示 `Still running the old code: AltTab — duo restart AltTab`。`duo restart AltTab` → `AltTab restarted`，新进程 19:02:28 起，磁盘 11.10.1，`codesign` 0
  - 这一轮没有写 `~/Library/LaunchAgents/com.lwouis.alt-tab-macos.plist`（`~/Library/LaunchAgents` 里没有 alt-tab 的 plist）。终态: 11.10.1，未运行
- 格式: .zip，根目录就是 `AltTab.app`
- 嵌套 / 常驻组件: 无 helper、无 LoginItems、无 XPC 服务；`Contents/Frameworks` 里只有 `Sparkle.framework`（自带 `Updater.app`、`Autoupdate`）和 `CrashReporter.framework`
- 校验: GitHub digest `sha256:aa353197537ccfd378dd4a7ff43030561ce7c62267dd0b31b385691b0e7f594c`，与下载的包一致（`shasum -a 256`）；上一版 11.10.0 的 Team 也是 `QXD7GW8FHY`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）。厂商自己的 appcast 不做灰度、对所有 tier 回答相同，所以这也就是厂商分配给每台机器的版本

### 真机注意事项（从 v11.10.1 源码读出）
- 首次启动要辅助功能和屏幕录制权限（`AccessibilityPermission`、`ScreenRecordingPermission`），会弹系统框
- 「登录时启动」默认开（`startAtLogin` 默认 `true`）：启动 2 秒后写 `~/Library/LaunchAgents/com.lwouis.alt-tab-macos.plist`（`Program` = 当前可执行文件的绝对路径、`RunAtLoad`、没有 `KeepAlive`），并会删掉旧式 `LSSharedFileList` 登录项。原位换包路径不变，退出时 launchd 不会把它拉起来。真机跑完要记得这个文件是 app 写的
- Sparkle 在启动 30 秒后才 `startUpdater()`；默认策略只检查不下载
- 注册了 URL scheme `com.lwouis.alt-tab-macos`（许可激活回调用）
- 偏好: `~/Library/Preferences/com.lwouis.alt-tab-macos.plist`、`com.lwouis.alt-tab-macos.license.plist`、`com.lwouis.alt-tab-macos.usage.plist`；许可密钥在钥匙串；cookie 在 `~/Library/HTTPStorages/com.lwouis.alt-tab-macos.binarycookies`（cask 的 `zap` 列表）
- Info.plist 里有 AppCenter 崩溃上报的配置；授权完成、第一次可用时开始 14 天 Pro 试用（`src/pro/license/LicenseManagerSpecs.md`）

## 已知问题
- **下一个大版本（v12）要重审**：官网定价页写普通 Pro 是「Updates for the current major version」，Pro Lifetime 是「Every future update, forever」。代码里留了 `versionLimitedVariants`（变体 → 最高版本，超过就 `.proExpired`）和按 tier 定制 appcast 的 cookie，现在都没启用。v12 发布时如果厂商对普通 Pro 用户不推 v12，这条 rule 照样会推，装上后 Pro 功能失效。届时用 `Cookie: license=pro` 和 `tier=pro` 重抓 appcast 对比；如果不同，需要按许可状态门控一键（许可在钥匙串和 `com.lwouis.alt-tab-macos.license.plist` 里，现在没有能读它的机制）
- 10.x → 11.x 跨越了免费 → Pro 的改变（搜索、额外样式、自动尺寸、更多快捷键在试用期后要 Pro）。这些副本走的是厂商自己声明的 Sparkle feed，由通用 Sparkle 源回答，推的就是厂商 appcast 推的版本，不经这条 rule
- ≤10.12.0 副本的 changelog 是网页，不是结构化的（见 Changelog）
- GitHub 删掉了 v11.0.0 之前的 release，appcast 里 10.x 及更早的 enclosure 都 404；只影响历史，不影响最新版

## 如何复验
```bash
gh api repos/lwouis/alt-tab-macos/releases/latest -q '.tag_name, (.assets[] | "\(.name)\t\(.size)\t\(.digest)")'
gh release download v11.10.1 --repo lwouis/alt-tab-macos --pattern 'AltTab-11.10.1.zip' --dir v11.10.1
gh release download v11.10.0 --repo lwouis/alt-tab-macos --pattern 'AltTab-11.10.0.zip' --dir v11.10.0
.claude/skills/coverage-discovery/scripts/check-bundle.sh v11.10.1/AltTab-11.10.1.zip   # Team QXD7GW8FHY, SUFeedURL=<none>, updater sparkle-framework
ditto -x -k v11.10.0/AltTab-11.10.0.zip x0 && ditto -x -k v11.10.1/AltTab-11.10.1.zip x1
swift run --package-path application-test feed-discover x0/AltTab.app                       # → review noCandidate
swift run --package-path application-test channel-verify x0/AltTab.app --expect stable      # → GitHub，UPDATE → 11.10.1
swift run --package-path application-test channel-verify x1/AltTab.app --expect stable      # → GitHub，up to date
# feed 在代码里拼出来：
gh api "repos/lwouis/alt-tab-macos/contents/src/api/Endpoints.swift?ref=v11.10.1" -q .content | base64 -d | grep appcastUrl
plutil -p x1/AltTab.app/Contents/Info.plist | grep -E '"Domain"|SUPublicEDKey'
# 两个 feed 相同，参数和 cookie 不改变响应：
curl -sS https://alt-tab.app/appcast.xml -o a.xml
curl -sS https://raw.githubusercontent.com/lwouis/alt-tab-macos/master/appcast.xml | cmp - a.xml
curl -sS -H 'Cookie: license=pro' 'https://alt-tab.app/appcast.xml?version=11.10.0&macos=26.0.0&arch=arm64&lang=en&tier=pro' | cmp - a.xml
# 旧版声明的 feed：
gh api "repos/lwouis/alt-tab-macos/contents/Info.plist?ref=v10.11.0" -q .content | base64 -d | grep -A1 SUFeedURL
gh api "repos/lwouis/alt-tab-macos/contents/Info.plist?ref=v10.12.0" -q .content | base64 -d | grep -A1 SUFeedURL
gh api "repos/lwouis/alt-tab-macos/contents/Info.plist?ref=v11.0.0" -q .content | base64 -d | grep -c SUFeedURL   # 0
```

## 建议下一步
1. （可选）把 AltTab 的更新策略设成自动安装再跑运行中一轮，看 Sparkle 停放的包和我们的换包会不会互相覆盖；2026-10-26 那轮用的是默认 `autoCheck`，没造出这种情形
2. 待用户决定: ≤10.12.0 副本的 changelog 要不要结构化。做法是加一个读 `api.github.com/repos/lwouis/alt-tab-macos/releases` 的 `ChangelogRecipe`（`mode: .json`、`structuredFormat: .gitHubReleases`，CotEditor 的写法）。它会排在 pane 的第一位，11.x 副本也会改成看它
3. v12 发布时按「已知问题」第一条重审
