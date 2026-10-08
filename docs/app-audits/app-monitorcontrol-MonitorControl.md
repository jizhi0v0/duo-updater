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
| **beta**     | ○（厂商未发过） | — | — | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**。bundle 自带 `SUFeedURL`，通用
`SparkleAppcastSource` 直接读，无 recipe、无 `ChannelBinding`。

- Homebrew —：cask `monitorcontrol`（2026-10-08 为 4.4.0）`auto_updates: true`，`HomebrewCaskSource` 退让。
- MAS —：App Store 上的「MonitorControl Lite」是另一个产品（`app.monitorcontrol.MonitorControlLite`），不是本 bundle 的分发渠道。
- GitHub —：appcast 的 enclosure 本来就指向 GitHub release 资产，不需要第二条源。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.monitorcontrol.MonitorControl` | 共享 | — | feed 里无 tag 的 item（Sparkle 默认 channel） | ✓ |
| beta    | `app.monitorcontrol.MonitorControl` | 共享 | CFPrefs `isBetaChannel`（Bool，无 UI） | `<sparkle:channel>beta</sparkle:channel>` | ○ 未接：feed 里从未有过 beta item |

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
**duo 今天并不跟随这个开关**（没有 binding）；厂商一旦发第一条 beta item，开了 `isBetaChannel` 的
副本 app 自己会收到、duo 不会提示——与 OBS 那类缺口同形，只是现在为空。

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
- 结构化（2026-10-08，`channel-verify` 的 `changelog pane` 行，4.4.0 与 4.3.3 两次一致）:
  `web page https://monitorcontrol.app/changelog.html?tag=v4.4.0, no structure` —— **没有结构化 changelog**，
  pane 退到网页。网页在 pane 里是否真的渲染出正文（取决于 JS 与匿名 GitHub API 配额）**未验证**。
- 跟随 channel: 不适用（只有一条轨在发）
- Recipe 状态: **需要**（○）。GitHub release 正文是 Markdown，带 `## What's Changed` 小节
  （v4.4.0、v4.3.2 实测），与 Waku（`Recipes/sh-waku.swift`）同形：Sparkle 检测 + `.gitHubReleases`
  `ChangelogRecipe` 读 `api.github.com/repos/MonitorControl/MonitorControl/releases?per_page=40`。
  小标题在 pane 里保留成标题还是被压平，要加上 recipe 后再看 `changelog pane` 行——**未验证**。

## 一键安装
- 状态: 走 Sparkle 通用一键路径（enclosure = GitHub release 的 `MonitorControl.<v>.dmg`，带 `sparkle:edSignature`；4.3.3 与 4.4.0 的 `SUPublicEDKey` 相同）
- 端到端: 未跑（由协调会话串行执行）
- 格式: dmg
- 校验: feed 只发 EdDSA 签名，不发 SHA 摘要；无可接的摘要字段。Team 闸：4.3.3 → 4.4.0 同为 `299YSU96J7`，不会被拒。
- **读的是**: 人人可手动下载的 GA——enclosure 就是 GitHub Releases 页上公开的 dmg，feed 无 `phasedRolloutInterval`。
- 嵌套 app: `Contents/Library/LoginItems/MonitorControlHelper.app`（`app.monitorcontrol.MonitorControlHelper`，
  `LSBackgroundOnly` true）。源码 `MonitorControlHelper/main.swift`：主 app 没在跑就 `launchApplication`
  主 app，然后立刻 `terminate`——登录启动器，不常驻，不阻挡一键（同 OpenInTerminal 的情形）。
- 阻塞: 无（端到端结果待协调会话补）

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
- **beta 缺口 / 重开条件**：feed 出现第一条 `<sparkle:channel>beta</sparkle:channel>` item 时，需要一条
  读 `isBetaChannel` 的 `ChannelBinding`，见「建议下一步」。

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
  `changelog pane  web page https://monitorcontrol.app/changelog.html?tag=v4.4.0, no structure`。
- check-bundle：4.4.0 `codesign-verify-exit=0`、4.3.3 `codesign-verify-exit=1`（FinderInfo，见上），
  两者 `spctl source=Notarized Developer ID`，nested 只有 `MonitorControlHelper.app`（`LSBackgroundOnly=true`）。
- feed：`appcast2.xml` 3 条 item，channel / deltas / phasedRolloutInterval / maximumSystemVersion /
  hardwareRequirements 均为 0；`github-pages` 分支该文件 4 个历史版本（`1dee334e39` `871a7129c3`
  `dba06df90b` `6c67dd621e`）channel tag 均为 0。

## 建议下一步
1. 加结构化 changelog: `/fragile-recipe MonitorControl`（ChangelogRecipe，`structuredFormat: .gitHubReleases`，
   source `https://api.github.com/repos/MonitorControl/MonitorControl/releases?per_page=40`，`mode: .json`，
   照 `Recipes/sh-waku.swift`）。加完跑 channel-verify 看 `changelog pane` 是否为 recipe、`## What's Changed`
   是否作为标题保留。
2. beta：现在不做。重开条件是 feed 出现第一条 `beta` item；届时加 `MonitorControlChannel`：读 CFPrefs
   `app.monitorcontrol.MonitorControl` 的 `isBetaChannel`（true → `.beta` + `sparkleChannelNames: ["beta"]`，
   否则 `.stable`），注册进 `ChannelBinding.resolver(for:)`，并以那个真实 beta 构建登记 binding proof。
3. 一键端到端由协调会话串行跑（4.3.3 → 4.4.0）。
