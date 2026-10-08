# MonitorControl

## 基本信息
- Bundle ID: `app.monitorcontrol.MonitorControl`
- Team ID: `299YSU96J7`（Developer ID Application: Istvan Toth），4.4.0 与 4.3.3 两个真包一致，`spctl` 均为 Notarized Developer ID
- 观测版本: 4.4.0（`CFBundleVersion` 7152），取自官方 v4.4.0 release 资产 `MonitorControl.4.4.0.dmg`，只读挂载读取；另取 4.3.3（7123）作落后一版的对照，取 4.2.0（7048）看旧身份（见「已知问题」）
- 自更新机制: Sparkle 2.1.0（Info.plist 带 `SUFeedURL`、`SUPublicEDKey`）
- 架构 / OS: universal（x86_64 + arm64）；`LSMinimumSystemVersion` 10.14；`LSUIElement` true（菜单栏 app）
- 开源: `MonitorControl/MonitorControl`；下面的 channel 与 changelog 结论 settled from source（`main` 与 `develop` 两个分支，以及放 feed 的 `github-pages` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |
| **beta**     | ✓（`MonitorControlChannel`；厂商还没发过 beta） | — | — | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。bundle 自带 `SUFeedURL`，通用
`SparkleAppcastSource` 直接读，检测不用 recipe；`isBetaChannel` 开着时由 `MonitorControlChannel` 判为 beta（changelog 有 recipe，见「Changelog」）。

- Homebrew —：cask `monitorcontrol`（2026-10-08 为 4.4.0）`auto_updates: true`，`HomebrewCaskSource` 退让。
- MAS —：App Store 上的「MonitorControl Lite」是另一个产品（`app.monitorcontrol.MonitorControlLite`），不是本 bundle 的分发渠道。
- GitHub —：appcast 的 enclosure 本来就指向 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.monitorcontrol.MonitorControl` | 共享 | — | feed 里无 tag 的 item（Sparkle 默认 channel） | ✓ |
| beta    | `app.monitorcontrol.MonitorControl` | 共享 | CFPrefs `isBetaChannel`（Bool，无 UI） | `<sparkle:channel>beta</sparkle:channel>` | ✓ `MonitorControlChannel`（feed 里还没有过 beta item） |

**app 有 beta 轨的客户端开关，只是没有 UI。** settled from source（`main` 与 `develop` 内容相同）：

1. `MonitorControl/Support/UpdaterDelegate.swift`：
   `allowedChannels(for:)` 在 `prefs.bool(forKey: PrefKey.isBetaChannel.rawValue)` 为 true 时返回
   `["beta"]`，否则返回空集。`prefs` 是 `UserDefaults.standard`（`main.swift`），app 没有沙盒
   （`MonitorControl.entitlements` 只有 `allow-jit`），所以存储是
   `~/Library/Preferences/app.monitorcontrol.MonitorControl.plist` 的 `isBetaChannel`。
2. `MonitorControl/Enums/PrefKey.swift`：`case isBetaChannel // This is not added to Settings yet as it will be needed in the future only.`
   ——设置界面里没有这个开关，只能 `defaults write` 打开。
3. Sparkle 文档（<https://sparkle-project.org/documentation/publishing/>）：没有 tag 的 item 在默认
   channel；`allowedChannels` 是在默认 channel **之外**再加的；更新器不能把自己排除在默认 channel 外。
   所以 `isBetaChannel` 打开时，app 自己看到的是「无 tag item + beta item」。

**为什么 beta 现在不需要接。** feed 从来没发过 beta item（2026-10-08 实测，见「如何复验」）：

- 线上 `appcast2.xml` 3 条 item，`<sparkle:channel>` 0 个；`github-pages` 分支上这个文件的全部
  4 个历史版本（2024-10-02 起）同样 0 个。
- 旧 feed `appcast.xml` 里唯一的 `sparkle:channel` 在一条 XML 注释里
  （`TODO: Use correct channels once setting is present. (after 4.0.0 release)`）；当年的
  4.0.0-beta1/-beta2/-rc1 是以**无 tag** item 发给所有人的，而那是旧身份的 feed（见「已知问题」）。
- GitHub releases 里 `prerelease=true` 的只有 v4.0.0-beta1、v4.0.0-beta2（2021），都早于当前身份。

因此 `isBetaChannel` 开或关，app 今天拿到的是同一组 item，duo 读无 tag item 的结果与 app 一致。
2026-10-08 起 duo 跟随这个开关（`MonitorControlChannel`）：`isBetaChannel` 为 true → `.beta`，放行无标签条目 + `beta`，和 app 自己的 `allowedChannels` 一致；false 或读不到 → nil，交回已装 build 推断。厂商发第一条 beta item 时，开了开关的拷贝会和 app 自己一样收到它。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://monitorcontrol.app/appcast2.xml`（Info.plist 声明；GitHub Pages 托管，内容与
  `github-pages` 分支 `docs/appcast2.xml` 逐字节相同，`cache-control: max-age=600`）
- 版本方案: `sparkle:version` = `CFBundleVersion`（7152），`sparkle:shortVersionString` =
  `CFBundleShortVersionString`（4.4.0），不需要 `versionIsBuild`。
- feed 形状（2026-10-08）: 3 条 item（4.4.0 / 4.3.3 / 4.3.2），全部无 `<sparkle:channel>`；
  无 `<sparkle:deltas>`；无 `phasedRolloutInterval`；每条 `minimumSystemVersion` 10.14，
  **没有** `maximumSystemVersion`，没有 `hardwareRequirements`；release notes 只有
  `<sparkle:releaseNotesLink>`，无 `<description>`。
- 注意事项: 无灰度、无 WAF；enclosure 的 `length` 与真实下载字节数一致（4.4.0：20391423；4.3.3：20788084）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 无可消费 |
| 证据 | 4.4.0 包内 `Sparkle.framework/Versions/B/Autoupdate` 含 `BinaryDelta`、`SUBinaryDeltaUnarchiver`、`sparkle:deltaFrom` | 2026-10-08 feed 3 条均无 `<sparkle:deltas>`；channel-verify `deltas 0` | 服务端不发；发了也是 Sparkle binary delta，`DeltaApplier` 现成可用 |

- 格式: Sparkle binary delta（客户端能力）
- 阻塞项: 厂商不发

## Changelog
- 来源: `<sparkle:releaseNotesLink>` → `https://monitorcontrol.app/changelog.html?tag=v<version>`。
  这页本身是空壳：页内 JS 用 `tag` 参数请求
  `api.github.com/repos/MonitorControl/MonitorControl/releases/tags/<tag>`，再用 `marked` 渲染 `body`
  （`github-pages` 分支 `docs/changelog.html`）。真正的内容就是 GitHub release 正文。
- recipe: `Recipes/app-monitorcontrol-MonitorControl.swift`，读同一批正文的列表
  `https://api.github.com/repos/MonitorControl/MonitorControl/releases?per_page=40`，`mode: .json`，
  `structuredFormat: .gitHubReleases`，无 channel（只读 `prerelease: false`）。
  - `tagPattern: ^v([0-9]+(?:\.[0-9]+)+)$`：版本 = tag 去掉 `v` = `CFBundleShortVersionString`（4.4.0）。
    这里是过滤器不是 monorepo 拆分：`v4.0.0-rc1` 在 GitHub 上是 `prerelease: false`，没有它会作为
    稳定版条目出现。
  - `skipSections`: `Thanks to all our translators`（4.0.0 的译者名单）、`Notes`（每版末尾的致谢 /
    「有问题开 issue」/「帮忙翻译」）、`Installation`（1.x 的安装说明）。New Contributors 与
    Full Changelog 由 `GitHubMarkdownParser` 对所有 app 统一丢掉。
  - 4.2.0 及更早（旧身份 `me.guillaumeb.MonitorControl`）**保留**：同一仓库、同一产品，身份变化是换签名
    （厂商 v4.3.2 说明里写明），属于这个 app 的历史。这个 recipe 按新 bundle id 注册，不会给旧身份的副本用。
- 结构化（2026-10-08，`channel-verify MonitorControl.4.4.0.dmg` 的 `changelog pane` 行）:
  `recipe changelog:app.monitorcontrol.MonitorControl:-: 22 entries; newest 4.4.0: 4 items, headings []; first items ["Restored the traditional OSD for macOS 2", "Fixed app Settings appearing on every in", "Fixed custom keyboard shortcut recording"]`
  —— 结构化 ✓。`## What's Changed` 不保留成标题：一个正文里只有它一个标题，低于
  `GitHubMarkdownParser` 的「≥2 个标题才渲染」门槛，被丢掉（不并进条目）；条目就是下面的列表，
  前后的介绍段落与 BetterDisplay 推荐不进条目。4.2.0 及更早有两个以上分类小标题的版本，小标题照常渲染。
- 跟随 channel: 不适用（只有一条轨在发）
- Recipe 状态: ✓ 已接入

## 一键安装
- 状态: 走 Sparkle 通用一键路径（enclosure = GitHub release 的 `MonitorControl.<v>.dmg`，带 `sparkle:edSignature`；4.3.3 与 4.4.0 的 `SUPublicEDKey` 相同）
- 端到端（2026-10-08，第一轮：未运行）: 4.3.3 (7123) → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 20391423`，13 s。之后版本 4.4.0 (7152)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `299YSU96J7`；和厂商新版包里的 app 逐文件比对（SHA-256 + 符号链接 + 目录，527 行）完全一致。上一版 4.3.3 自身过不了严格校验（见下），换装后的 4.4.0 能过。第二轮（运行中、app 自己的更新器已暂存）未跑。
- 格式: dmg
- 校验: feed 只发 EdDSA 签名，不发 SHA 摘要；无可接的摘要字段。Team 闸：4.3.3 → 4.4.0 同为 `299YSU96J7`，不会被拒。
- **读的是**: 人人可手动下载的 GA——enclosure 就是 GitHub Releases 页上公开的 dmg，feed 无 `phasedRolloutInterval`。
- 嵌套 app: `Contents/Library/LoginItems/MonitorControlHelper.app`（`app.monitorcontrol.MonitorControlHelper`，
  `LSBackgroundOnly` true）。源码 `MonitorControlHelper/main.swift`：主 app 没在跑就 `launchApplication`
  主 app，然后立刻 `terminate`——登录启动器，不常驻，不阻挡一键（同 OpenInTerminal 的情形）。
- 阻塞: 无（第一轮端到端已跑通，第二轮未跑）

## 已知问题
- **4.2.0 及更早是另一个身份，duo 与厂商都会报「已是最新」。** 4.2.0 真包：bundle id
  `me.guillaumeb.MonitorControl`、Team `CYC8C8R4K9`（Joni Van Roost）、另一把 `SUPublicEDKey`、
  `SUFeedURL` 为 `https://monitorcontrol.app/appcast.xml`；那份 feed 停在 4.2.0。channel-verify 对 4.2.0
  报 `latest 4.2.0`、`status up to date`。厂商在 v4.3.2 的 release 说明里明说 4.2.0 不会自动升级、要手动下载
  （签名变更）。即便 duo 能识别到新版，Team 闸也会拒掉跨 Team 的一键，且 bundle id 不同。这里只记录，
  没有动代码。
- **4.3.3 包本身过不了 `codesign --verify --deep --strict`**：dmg 里 `Sparkle.framework/…/Updater.app` 带
  `com.apple.FinderInfo` xattr（`resource fork, Finder information, or similar detritus not allowed`）。
  `spctl` 仍为 Notarized，4.4.0 包干净（exit 0）。影响的是「装上一版做端到端」时上一版本身的严格校验，
  不影响 duo 装 4.4.0 的校验对象。
- **beta**：`MonitorControlChannel` 已接上，但 feed 里还没有 beta item，真实的 beta 包验证要等厂商发第一条。

## 如何复验

```sh
# 真包（官方 release 资产）
curl -sSLO "https://github.com/MonitorControl/MonitorControl/releases/download/v4.4.0/MonitorControl.4.4.0.dmg"
curl -sSLO "https://github.com/MonitorControl/MonitorControl/releases/download/v4.3.3/MonitorControl.4.3.3.dmg"
swift run --package-path application-test feed-discover MonitorControl.4.4.0.dmg
swift run --package-path application-test channel-verify MonitorControl.4.4.0.dmg --expect stable
swift run --package-path application-test channel-verify MonitorControl.4.3.3.dmg --expect stable
.claude/skills/coverage-discovery/scripts/check-bundle.sh MonitorControl.4.4.0.dmg MonitorControl.4.3.3.dmg
# feed：channel tag / delta / OS 边界
curl -sS https://monitorcontrol.app/appcast2.xml | grep -c '<item>'
curl -sS https://monitorcontrol.app/appcast2.xml | grep -cE 'sparkle:channel|sparkle:deltas|phasedRolloutInterval|maximumSystemVersion|hardwareRequirements'
# 源码里的 beta 开关
gh api "repos/MonitorControl/MonitorControl/contents/MonitorControl/Support/UpdaterDelegate.swift?ref=main" -q .content | base64 -d
```

2026-10-08 实测：

| 包 | bundle id | 版本 (build) | Team | feed-discover | channel-verify |
|---|---|---|---|---|---|
| 4.4.0 | `app.monitorcontrol.MonitorControl` | 4.4.0 (7152) | `299YSU96J7` | `declared  https://monitorcontrol.app/appcast2.xml` | detected stable、winning source Sparkle、latest 4.4.0、`status up to date` |
| 4.3.3 | `app.monitorcontrol.MonitorControl` | 4.3.3 (7123) | `299YSU96J7` | `declared  https://monitorcontrol.app/appcast2.xml` | detected stable、winning source Sparkle、`status UPDATE → 4.4.0`，download `…/releases/download/v4.4.0/MonitorControl.4.4.0.dmg` |
| 4.2.0（旧身份） | `me.guillaumeb.MonitorControl` | 4.2.0 (7048) | `CYC8C8R4K9` | `declared  https://monitorcontrol.app/appcast.xml` | latest 4.2.0、`status up to date`（见「已知问题」） |

- 两个当前身份的包：`release history 3 entries`、`deltas 0`、`ChannelBinding <none for this app>`、
  `changelog pane  web page https://monitorcontrol.app/changelog.html?tag=v4.4.0, no structure`（加 changelog
  recipe 之前；之后见「Changelog」）。
- check-bundle：4.4.0 `codesign-verify-exit=0`、4.3.3 `codesign-verify-exit=1`（FinderInfo，见上），
  两者 `spctl source=Notarized Developer ID`，nested 只有 `MonitorControlHelper.app`（`LSBackgroundOnly=true`）。
- feed：`appcast2.xml` 3 条 item，channel / deltas / phasedRolloutInterval / maximumSystemVersion /
  hardwareRequirements 均为 0；`github-pages` 分支该文件 4 个历史版本（`1dee334e39` `871a7129c3`
  `dba06df90b` `6c67dd621e`）channel tag 均为 0。

## 建议下一步
1. 结构化 changelog: 已做（见「Changelog」）。
2. beta：`MonitorControlChannel` 已接（2026-10-08）。标签由 `.beta` 推出（`beta`），不是手写的，所以不需要 binding proof。厂商发第一条 beta item 时，拿真实 beta 包跑一遍 `channel-verify`。真实路径（`defaults write … isBetaChannel -bool true`，验完删除）：`ChannelBinding  beta — read from this app's own preference`，`detected channel → beta`，4.4.0 `up to date`（feed 里没有 beta item）；去掉这个键后是 `<none for this app>`、stable。
3. 一键：第一轮端到端已跑通（4.3.3 → 4.4.0）；第二轮未跑。

## 历史与实测

### Recipes/app-monitorcontrol-MonitorControl.swift — ChangelogRecipe（2026-10-08 接入时）

**真实响应。** `GET https://api.github.com/repos/MonitorControl/MonitorControl/releases?per_page=40`
（匿名，浏览器 UA）：143605 字节，27 个 release；`per_page=100` 返回同样的 27 个，所以 40 一页装得下全部。
`prerelease: true` 只有 `v4.0.0-beta1`、`v4.0.0-beta2`；`draft` 0 个。`v4.0.0-rc1` 是 `prerelease: false`。
tag 全是 `v<版本>`（`v1.0`、`v1.1`、`v1.2` 两段，其余三段）。正文里的 `#` 标题：v4.4.0、v4.3.3、v4.3.2
各只有一个 `## What's Changed`；v4.2.0、v4.1.0 是 GitHub 生成格式（`## What's Changed` + `###` 分类 +
`## New Contributors` + `**Full Changelog**`）；v4.0.x / v3.x 是手写 `###` 分类 + `### Notes`；
v1.x / v2.x 是 `### What's new` / `### Bug fixes`，v1.0–v1.4.0 带 `### Installation`。

**生产解码器。** 一次性 Swift 测试（跑完已删）把上面的响应原样喂给
`StructuredChangelogDecoder.decode(format: .gitHubReleases, channel: nil, maxEntries: 40, …)`：

| 配置 | 条目数 | 与最终配置的差别 |
|---|---|---|
| 不加 `tagPattern` / `skipSections` | 25 | 多出 `4.0.0-rc1`（73 条，几乎是 4.0.0 的复本）、`1.1`、`1.0`（各 1 条，就是安装说明） |
| 最终配置 | 22 | — |

最终配置的 22 条：4.4.0（4 条，无标题）、4.3.3（4）、4.3.2（12）、4.2.0（15，标题 Improvements /
Translations & other）、4.1.0（18）、4.0.2（4）、4.0.1（11）、4.0.0（63）、3.1.1（2）、3.1.0（2）、
3.0.0（46），以及 2.1.0 到 1.2 共 11 条。被 `skipSections` 去掉的内容（逐版看过）：4.0.0 的
`Thanks to all our translators` 是 9 行「语言 - thanks to @…」；`Notes` 在所有稳定版里都是致谢、
「有问题开 issue」「帮忙翻译见 #637」一类（3.1.0 另有一句「v4.0.0 在开发中」）；`Installation` 全是
「打开 .dmg 拖进 Applications」。

v4.3.2 的一条是厂商原文两行粘在一起（`Added Japanese translation - @shsw228- Updated Russian translation - @ghostiam`），
照原样显示。

**真实路径。** `swift run --package-path application-test channel-verify MonitorControl.4.4.0.dmg`
（官方 v4.4.0 release 资产，20391423 字节），同一个包前后各跑一次：

- 不注册本 family：`changelog pane  web page https://monitorcontrol.app/changelog.html?tag=v4.4.0, no structure`
- 注册后：`changelog pane  recipe changelog:app.monitorcontrol.MonitorControl:-: 22 entries; newest 4.4.0: 4 items, headings []; first items ["Restored the traditional OSD for macOS 2", "Fixed app Settings appearing on every in", "Fixed custom keyboard shortcut recording"]`

两次其余各行相同：winning source Sparkle、latest 4.4.0、`status up to date`。
