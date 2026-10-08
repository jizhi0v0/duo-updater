# IINA

> 审计日期 2026-10-08 · 模式 REPORT（复审）· 结论：**stable/beta 两 channel，共享 bundle id，`IINAChannel` 读 `receiveBetaUpdate` 做 Sparkle feed-swap；对源码和真实包都核对过。检测 ✓（两轨）· 一键走通用 Sparkle 安装路径，第一轮端到端 ✓（delta） · changelog 结构化 ✓（`feedPagePattern` recipe，两轨都读 feed 给的那一页）**
>
> 本文替换 2026-06-04 那版。旧版只核对了 bundle 身份，结论「仅 Sparkle stable、无需改代码」，但 2026-06-07 代码已加了 beta `ChannelBinding`，旧文没跟上；旧文里的各项错误见文末「旧版结论勘误」。

## 基本信息
- Bundle ID: `com.colliderli.iina`（stable 与 beta **共用**）
- Team ID: `67CQ77V27R`（1.4.4、1.5.0、1.5.0-beta2 三个真实 dmg 一致，`codesign -dvv`）
- 观测版本: stable `1.5.0`（`CFBundleVersion` 180，2026-10-03 发布）；上一版 stable `1.4.4`（168）；beta 轨最新 beta `1.5.0-beta2`（172）。2026-10-08 时 beta feed 的头条就是 stable 1.5.0（见下）。
- 自更新机制: Sparkle 2（1.5.0 内置 Sparkle 2.9.6，1.4.4 内置 2.9.1）。开源：`github.com/iina/iina`，默认分支 `develop`。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓(feed-swap: `appcast.xml`) | ✗(cask `auto_updates`) | — | — | — |
| **beta**     | ✓(feed-swap: `appcast-beta.xml`) | — | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **SparkleAppcastSource**。`SourceStack.make` 里 `HomebrewCaskSource` 排在 Sparkle 前面，但 cask `iina` 是 `auto_updates: true`，它不应答；没有 MAS 版本，没有 VendorProbe/GitHub 规则。Feed 地址由 `ChannelBinding` → `IINAChannel` 的 `feedOverride` 决定（stable 时也给出 `appcast.xml`，与 Info.plist `SUFeedURL` 相同）。

## Channel 详情（Pattern B — 共享 bundle id，偏好切换 feed）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.colliderli.iina` | 共享 | `receiveBetaUpdate` 为 false 或缺失 | feed-swap → `https://www.iina.io/appcast.xml` | ✓ |
| beta    | `com.colliderli.iina` | 共享 | `receiveBetaUpdate` 为 true | feed-swap → `https://www.iina.io/appcast-beta.xml` | ✓ |

### 切换机制：settled from source（`iina/iina`，tag `v1.4.4` / `v1.5.0-beta2` / `v1.5.0` 与 `develop` 一致）

- `iina/AppData.swift`：`appcastLink = "https://www.iina.io/appcast.xml"`，`appcastBetaLink = "https://www.iina.io/appcast-beta.xml"`。
- `iina/AppDelegate.swift`：`SPUUpdaterDelegate.feedURLString(for:)` 返回 `Preference.bool(for: .receiveBetaUpdate) ? AppData.appcastBetaLink : AppData.appcastLink`；启动时还调用 `updaterController.updater.clearFeedURLFromUserDefaults()`，所以 Sparkle 自己缓存的 feed 地址不参与。
- `iina/Preference.swift`：键名 `Key("receiveBetaUpdate")`，注册默认值 `false`；读取走 `UserDefaults.standard.bool(forKey:)`。
- `iina/SettingsPageGeneral.swift`（1.5.0 新设置窗口）：「检查更新」开关的详情视图里 `SettingsItem.Switch().bindTo(.receiveBetaUpdate)`。
- 包未沙盒（主程序 entitlements 只有 `cs.allow-unsigned-executable-memory` 和 `cs.disable-library-validation`），所以 `UserDefaults.standard` 落在 `~/Library/Preferences/com.colliderli.iina.plist`，`CFPreferencesCopyAppValue("receiveBetaUpdate", "com.colliderli.iina")` 读的就是这一份。

`IINAChannel` 的三个假设逐条对上：键名 `receiveBetaUpdate` ✓；true → beta feed、false/缺失 → stable feed ✓（与 IINA 注册的默认值 false 一致）；两个 URL 逐字相同 ✓。一处语义差：IINA 用 `UserDefaults.bool(forKey:)`，字符串 `"YES"`/`"1"` 也算 true；`IINAChannel` 只认 `NSNumber`，字符串值会读成 stable。IINA 自己的设置界面写的是 Bool，这条路径上不会出现字符串；只有手工 `defaults write … -string YES` 才会让两边分歧，且分歧方向是保守的（落回 stable）。

### 版本后缀与 binding 的关系

beta 包的 `CFBundleShortVersionString` 是字面的 `1.5.0-beta2`，`ReleaseChannel.detect()` 单看它会推断为 **beta**；但 `ChannelBinding` 永远覆盖推断：偏好为 false/缺失时判为 stable，于是 beta 包读 stable feed。这和 IINA 自己的行为一致——开关关着时，它的 Sparkle 也只读 `appcast.xml`，所以装了 beta 却没开开关的拷贝会在下一个 stable（build 号更大）出来时被带回 stable，在此之前显示为「已最新」（拷贝领先于 feed，见 `SparkleMarketingDowngradeTests.aCopyAheadOfItsFeedKeepsItsUpToDateRow`）。

## 更新检测
- 源: `SparkleAppcastSource`（`feed-discover` 对三个包都判 `declared`）
- 端点: stable `https://www.iina.io/appcast.xml`，beta `https://www.iina.io/appcast-beta.xml`；包下载在 `https://dl-portal.iina.io/IINA.v<版本>.dmg`（302 到 `dl.iina.io`）。
- 两份 feed 的形状（2026-10-08 08:19 UTC 抓取，均 HTTP 200）：
  - `appcast.xml` 42 个条目，`appcast-beta.xml` 44 个条目；**两份都没有任何 `<sparkle:channel>` 标签**，全是默认渠道条目，所以 channel 过滤不会把任何条目挡掉，`NEEDS BINDING` 的形状不适用。
  - beta feed = stable feed 的全部条目 + `1.5.0-beta2`（172）+ `1.5.0-beta1`（170），排在 1.4.4 与 1.5.0 之间；即 beta 是 stable 的超集，不是平行轨。旧的 `1.4.0-beta1`（GitHub 上有）在 beta feed 里已经没有了。
  - 头条：两份都是 `1.5.0`（`sparkle:version` 180）。
  - `minimumSystemVersion`：1.5.0 = `11`，1.5.0-beta2 = `12`，1.5.0-beta1 = `11`，1.4.x = `10.15`，更早的 10.13/10.11/10.10；**没有** `maximumSystemVersion`、`hardwareRequirements`、`phasedRolloutInterval`、`criticalUpdate`。包本身是 universal（`x86_64 arm64`），`LSMinimumSystemVersion` 与 feed 一致（1.4.4 = 10.15，1.5.0 = 11，beta2 = 12）。
  - 说明：每个条目一条 `<sparkle:releaseNotesLink xml:lang="en">https://www.iina.io/release-note/<版本>.html`，**没有** `<description>` 内联。
- 注意事项:
  - `1.4.2` 出过两个 build（163、164），marketing 版本相同，下载名一个是 `IINA.v1.4.2.dmg`、一个是 `IINA.v1.4.2-build164.dmg`。`UpdateChecker.evaluate` 两侧都有 build 号时按 build 比，所以 163 → 164 能被报出来；feed 给 build 164 的说明链接也按 build 命名（`1.4.2-build164.html`），但这一页站点上不存在（2026-10-08 HTTP 404，见「历史与实测」）。
  - beta 的 marketing 串带 `-beta2` 后缀，同样靠 build 号（172 < 180）比较，不依赖解析后缀。
  - Homebrew cask `iina` 声明 `depends_on macos >= 12`，比 app 自己的 `LSMinimumSystemVersion` 11 高；cask 是 `auto_updates`，不参与检测，只是元数据差异。
  - 没有 `iina@beta` 之类的 cask（`brew search --cask iina` 只有 `iina` 和无关的 `iina+`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（第一轮端到端走的就是 `IINA180-168.delta`，68369402 字节） |
| 证据 | 1.5.0 包内 `Sparkle.framework/Versions/B/Autoupdate` 的 strings 含 `BinaryDelta`、`SUBinaryDeltaCommon.m`、`/usr/bin/bspatch` | 2026-10-08 两份 feed：stable 42 条里 16 条带 `<sparkle:deltas>`；1.5.0 带 `deltaFrom` 172/170/168/167/164 五个 patch（`IINA180-168.delta` 68,369,402 B，`IINA180-172.delta` 6,264,954 B，整包 113,048,935 B） | `channel-verify` 对 1.4.4 打印 `deltas 5`，即 `SparkleAppcastSource` 已把 patch 列表带进 `RemoteVersion`；应用靠 `DeltaApplier`（Sparkle `BinaryDelta`） |

- 格式: Sparkle binary delta（EdDSA 签名，同时还带旧的 DSA 签名）
- 阻塞项: 无。注意 168 → 180 的 patch 有 68 MB，省得不多；172 → 180（beta2 → 1.5.0）只有 6 MB。

## 按设备灰度 / 按 OS 分轨 / 自更新器

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | Sparkle 2 支持 `phasedRolloutInterval` | 否：两份 feed 都没有该元素（2026-10-08） | 不适用 |
| 按架构 / 按 OS 分轨 | Sparkle 支持 min/max 与 `hardwareRequirements` | 只有逐条 `minimumSystemVersion`（见上）；没有上限、没有架构分轨，包是 universal | 能：`SparkleAppcastSource.usableItems` 解析 min/max 与 `hardwareRequirements`；10.15 的 Mac 会停在 1.4.4，beta2 只给 12+ |
| 自更新器会不会和我们抢 | 会：IINA 自带 Sparkle，用户可开自动检查/自动下载 | 没测 | 端到端第二轮（运行中 + 自更新器已暂存）未跑 |

## Changelog
- 来源: 每个 feed 条目自己的 `releaseNotesLink`（feed 无内联说明），经 `ChangelogRecipe`（`feedPagePattern`）结构化
- 结构化 ✓: `changelog pane  recipe changelog:com.colliderli.iina:-: 1 entries; newest 1.5.0: 76 items, headings ["New", "Bug Fixes", "Improvements", "Updates", "Plugin API", "Deprecation Notice"]; first items ["IINA 1.5.0 introduces the biggest interf", "Added a new Settings window #6016.", "Added a confirmation prompt when deletin"]`（`channel-verify` 原文，真实 1.4.4 dmg，binding 为 stable；加 recipe 之前同一命令是 `web page https://www.iina.io/release-note/1.5.0.html, no structure`）
- 页面形状：一页一个版本，`<h2>IINA <版本></h2>`，可选一段 `<p>` 引言，然后若干 `<h3>` 分节（1.5.0：New / Bug Fixes / Improvements / Updates / Plugin API；1.4.4 只有 Bug Fixes），每节一个 `<ul class="fl">`，条目是 `<li class="n|f|e|p|u">`，子项是嵌套的普通 `<ul><li>`；末尾常有 `<p><strong>Deprecation Notice</strong><br>…</p>`（旧页是 `<b>`），recipe 把粗体引语当分节标题。较旧的页在后面接着放前几版（更多 `<h2>`），recipe 只取第一个 `<h2>` 到下一个 `<h2>`。
- 跟随 channel: 是（每个条目自己的 `releaseNotesLink` 指向自己版本的页，beta 条目指向 `1.5.0-beta2.html`；recipe 读的就是 feed 为这份拷贝选中的那一页）
- Recipe 状态: ✓（`Recipes/com-colliderli-iina.swift`，测试 `IINAChangelogRecipeTests`）。形状与 Mac Mouse Fix 相同，走 `feedPagePattern`（`^https://www\.iina\.io/release-note/[^/?#]+\.html$`），`source` 是 `appcast.xml`，只给 `duo verify` 用。
- 已知缺口: feed 里按 build 命名的说明链接（`1.4.2-build164.html` 等 6 个）站点上是 404，这类条目当头条时 recipe 解析不出东西，面板退回嵌入那一页（与加 recipe 之前相同）。今天两份 feed 在任何 macOS 上解析出的头条都不是这类条目。

## 一键安装
- 状态: 支持（通用 Sparkle 路径，第一轮端到端 ✓）
- 端到端（2026-10-08，第一轮：未运行）: 1.4.4 (168) → `duo install --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 68369402`，17 s。之后版本 1.5.0 (180)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `67CQ77V27R`；和厂商新版包里的 app 逐文件比对（SHA-256 + 符号链接 + 目录，1168 行）完全一致。68369402 字节就是 `IINA180-168.delta`，走的是 delta。第二轮（运行中、app 自己的更新器已暂存）未跑。
- 格式: dmg（`IINA.v<版本>.dmg`，内含 `IINA.app` 与 `Applications` 软链）
- 校验: feed 每个 enclosure 带 `sparkle:edSignature`，包内 `SUPublicEDKey` 在 1.4.4 / 1.5.0-beta2 / 1.5.0 三个包里相同；生产 `SignatureVerifier.verifyEdSignature` 对三个真实 dmg 均通过，翻一个字节即拒（「如何复验」第 5 节）。这是 Sparkle 自带的校验，不需要也没有另接 `checksumPattern`。另外三个 dmg 的 SHA-256 与 GitHub release 资产的 `digest` 逐一相等（下载自 `dl-portal.iina.io`，与 GitHub 资产是同一份字节）。
- Team ID：上一版 1.4.4 与最新 1.5.0、beta2 都是 `67CQ77V27R`，`SignatureVerifier` 的 Team 精确匹配不会挡住老拷贝。三个包 `codesign --verify --deep --strict` 退出 0，`spctl` 为 `Notarized Developer ID`。
- 嵌套组件：`check-bundle.sh` 在 `Contents/` 下 4 层内没有嵌套 `.app`；包里只有 Safari 扩展 `Contents/PlugIns/OpenInIINA.appex`（`com.colliderli.iina.OpenInIINA`，`com.apple.Safari.extension`，不是常驻进程）和 Sparkle 自带的 `Updater.app` / `Installer.xpc` / `Downloader.xpc`（Sparkle 自己的安装流程用，不常驻）。没有 LoginItem 或常驻 helper，不需要因为 helper 扣一键。
- **读的是**: 人人可手动下载的 GA——feed 没有 `phasedRolloutInterval`，IINA 自己的 Sparkle 对同一个 feed 也会拿到同一个头条；stable 包和 beta 包都是 GitHub Releases 上公开挂出的资产（beta 标 `prerelease`），字节相同。
- 阻塞: 无已知阻塞；第二轮（自更新器碰撞）未跑。

## 已知问题
- `IINAChannel.readReceiveBeta()` 只认 `NSNumber`，IINA 的 `UserDefaults.bool(forKey:)` 也认字符串；手工写入字符串值时两边会分歧（落回 stable，保守方向）。正常使用不会出现。
- 2026-06-07 加 binding 时没有同步更新本审计文档（本次补上）。

## 建议下一步
1. 结构化 changelog：已完成（见「Changelog」与「历史与实测」）。
2. 一键：第一轮已跑通（见「一键安装」）。还没跑的是第二轮：让 IINA 的 Sparkle 先暂存一个更旧的包，再 `duo install` + `duo restart`。
3. 可选：`IINAChannel.readReceiveBeta()` 改为与 `UserDefaults.bool(forKey:)` 同语义（也接受 `"YES"`/`"true"`/`"1"` 字符串），并加单测。不急。
4. README 索引：IINA 现有两个 channel，应从「Sparkle-covered」移到「Multi-channel families」。

## 如何复验

所有命令在仓库根目录运行；包下载到一个新的临时目录（下文 `$D`）。观测日期 2026-10-08。

### 1. 源码（切换机制）

```sh
for t in v1.4.4 v1.5.0-beta2 v1.5.0 develop; do
  curl -sSfL "https://raw.githubusercontent.com/iina/iina/$t/iina/AppDelegate.swift" | grep -n -A1 "feedURLString"
  curl -sSfL "https://raw.githubusercontent.com/iina/iina/$t/iina/AppData.swift" | grep -n "appcast"
done
```

四个 ref 都是 `Preference.bool(for: .receiveBetaUpdate) ? AppData.appcastBetaLink : AppData.appcastLink`，两个链接与 `IINAChannel.stableFeed` / `betaFeed` 逐字相同。

### 2. 真实包身份

```sh
D=$(mktemp -d)
for v in 1.4.4 1.5.0 1.5.0-beta2; do curl -sSL -o "$D/IINA.v$v.dmg" "https://dl-portal.iina.io/IINA.v$v.dmg"; done
shasum -a 256 "$D"/*.dmg
gh api "repos/iina/iina/releases?per_page=4" -q '.[] | .assets[] | "\(.name)\t\(.size)\t\(.digest)"'
.claude/skills/coverage-discovery/scripts/check-bundle.sh "$D"/IINA.v1.4.4.dmg "$D"/IINA.v1.5.0.dmg "$D"/IINA.v1.5.0-beta2.dmg
```

| 包 | 大小 (B) | SHA-256（= GitHub `digest`） | short / build | `LSMinimumSystemVersion` | Team | verify / spctl |
|---|---|---|---|---|---|---|
| 1.4.4 | 109,301,417 | `dd0fc0bd…37beb1` | 1.4.4 / 168 | 10.15 | `67CQ77V27R` | 0 / Notarized Developer ID |
| 1.5.0 | 113,048,935 | `8fad5047…a20dc7` | 1.5.0 / 180 | 11 | `67CQ77V27R` | 0 / Notarized Developer ID |
| 1.5.0-beta2 | 111,625,519 | `4d16f571…a31a95` | 1.5.0-beta2 / 172 | 12 | `67CQ77V27R` | 0 / Notarized Developer ID |

三个包的 `SUFeedURL` 都是 `https://www.iina.io/appcast.xml`（beta 包也一样——beta 只靠运行时换 feed），`SUPublicEDKey` 相同；`archs=x86_64 arm64`；无嵌套 `.app`。

### 3. `feed-discover`

```sh
swift run --package-path application-test feed-discover "$D/IINA.v1.5.0.dmg"
```

三个包都是：

```
IINA  [com.colliderli.iina]  1.5.0 (180)
   declared  https://www.iina.io/appcast.xml
      (Info.plist names it; SparkleAppcastSource already resolves this app)
```

（1.4.4 显示 `1.4.4 (168)`，beta2 显示 `1.5.0-beta2 (172)`，结论同为 `declared`。）

### 4. `channel-verify`（stable 轨：binding 读到 `receiveBetaUpdate` 为 false/缺失）

`channel-verify` 的路径模式会调用真实的 `ChannelBinding.resolve`，即读当前用户 IINA 偏好域里的值；它没有模拟偏好的参数，所以它只能复验 binding 当时给出的那一轨。下表是 binding 判为 stable（`receiveBetaUpdate` 为 false 或缺失）时的结果；beta 一轨见第 5 节。

```sh
swift run --package-path application-test channel-verify "$D/IINA.v1.4.4.dmg"
```

| 包 | inferred | ChannelBinding | detected | winning source | latest | status |
|---|---|---|---|---|---|---|
| 1.4.4 | stable | stable | stable | Sparkle | 1.5.0 | `UPDATE → 1.5.0` |
| 1.5.0 | stable | stable | stable | Sparkle | 1.5.0 | `up to date` |
| 1.5.0-beta2 | **beta**（版本后缀） | stable | stable | Sparkle | 1.5.0 | `UPDATE → 1.5.0` |

三次共有的行：`SUFeedURL https://www.iina.io/appcast.xml`、`download https://dl-portal.iina.io/IINA.v1.5.0.dmg`、`release notes 0 chars inline, changelogURL https://www.iina.io/release-note/1.5.0.html`、`changelog pane  web page https://www.iina.io/release-note/1.5.0.html, no structure`（加 changelog recipe 之前；之后的输出见「历史与实测」）、`release history 42 entries`、`deltas 5`；退出码均为 0。

### 5. beta 轨（binding 为 `receiveBetaUpdate = true`）

没有改 IINA 的偏好域。改用一个临时 Swift 测试（跑完已删除）：用 `IINAChannel.resolve(receiveBeta:)` 的真实结果构造 `InstalledApp`（`sparkleFeedURL = feedOverride`、`releaseChannel`、`channelIsAuthoritative: true`、包里的 `SUPublicEDKey`），再交给 `UpdateChecker(sources: SourceStack.make(githubToken: nil), …).check`——与 `channel-verify` 路径模式构造 `chainApp` 的方式相同，只是 binding 的值是注入的而不是读出来的。

实时 feed（2026-10-08），两种偏好值 × 三个真实包的 short/build：

| `receiveBetaUpdate` | channel / feed | 观测 1.4.4 (168) | 观测 1.5.0-beta2 (172) | 观测 1.5.0 (180) | release history |
|---|---|---|---|---|---|
| true | beta / `appcast-beta.xml` | `updateAvailable 1.5.0` | `updateAvailable 1.5.0` | `upToDate` | 44 条，头 4 条 `1.5.0, 1.5.0-beta2, 1.5.0-beta1, 1.4.4` |
| false | stable / `appcast.xml` | `updateAvailable 1.5.0` | `updateAvailable 1.5.0` | `upToDate` | 42 条，头 4 条 `1.5.0, 1.4.4, 1.4.3, 1.4.2` |

六次的 winning source 都是 Sparkle，下载地址 `https://dl-portal.iina.io/IINA.v1.5.0.dmg`，`deltas 5`。beta 那一行说明 binding 确实换到了 beta feed，且 beta 条目没被 channel 过滤挡掉（44 条全在历史里）。

今天 beta feed 的头条恰好是 stable 1.5.0，所以上表看不出「beta 轨会被报 beta」。补一组离线判定：把同一份 beta feed 去掉 build 180（还原 1.5.0 发布前的形状），交给生产 `SparkleAppcastParser.parse` + `SparkleAppcastSource.bestItem`，观测 1.4.4、binding 为 beta：

| 宿主 macOS | 选中的条目 |
|---|---|
| 27.0 | `1.5.0-beta2` (172) |
| 12.0 | `1.5.0-beta2` (172) |
| 11.7 | `1.5.0-beta1` (170)——beta2 要求 12 |
| 10.15.7 | `1.4.4` (168)，即没有可报的更新——两个 beta 都要求 11+ |

（完整 beta feed 在 10.15.7 上同样只到 1.4.4，1.5.0 要求 11。）解析出的 44 个条目全部没有 `<sparkle:channel>`。

同一个临时测试还用生产 `SignatureVerifier.verifyEdSignature` 对三个真实 dmg 做了 EdDSA 校验（签名取自 feed 对应条目，公钥取自包内 `SUPublicEDKey`）：1.5.0 / 1.5.0-beta2 / 1.4.4 均通过；每个文件翻转中间一个字节后均抛 `edSignatureInvalid`。

### 6. Feed 形状

```sh
curl -sS "https://www.iina.io/appcast.xml" -o "$D/appcast.xml"
curl -sS "https://www.iina.io/appcast-beta.xml" -o "$D/appcast-beta.xml"
grep -c "<item>" "$D"/appcast*.xml                       # appcast-beta.xml:44, appcast.xml:42
grep -c "sparkle:channel" "$D"/appcast*.xml              # 0 / 0
grep -ciE "maximumSystemVersion|hardwareRequirements|phasedRolloutInterval" "$D"/appcast*.xml   # 0 / 0
```

## 旧版结论勘误

2026-06-04 版的下列说法不成立或已过期：
- 「覆盖矩阵只有 stable」：IINA 有 beta 轨（`appcast-beta.xml`），代码自 2026-06-07 起已用 `IINAChannel` 接入。
- 「当前生效源: Sparkle for installed direct app with `SUFeedURL`」：生效的 feed 地址来自 `ChannelBinding` 的 `feedOverride`，不只是 Info.plist。
- 「一键安装：Sparkle path only / 阻塞：无」：当时没有任何端到端或真实包证据。现在第一轮端到端已跑通（1.4.4 → 1.5.0，delta）。
- 「Changelog: Sparkle/appcast-provided notes only」：feed 没有内联说明，面板显示的是 web page，没有结构。
- 「建议下一步：No code change」：缺一条 changelog recipe。
- 自更新机制写成「Sparkle / Homebrew cask `auto_updates`」：cask 的 `auto_updates` 不是更新机制，只是让 `HomebrewCaskSource` 不应答。

## 历史与实测

### Recipes/com-colliderli-iina.swift — ChangelogRecipe（`feedPagePattern`，每版一页），2026-10-08

- 抓取：两份 feed（`appcast.xml` 42 条、`appcast-beta.xml` 44 条），每条一个 `<sparkle:releaseNotesLink xml:lang="en">`，没有 `<description>`；去重后 40 个不同链接，逐个用浏览器 UA GET。
- 链接与 pattern：38 个在 `/release-note/` 下，匹配 `feedPagePattern`。2 个不匹配：1.3.0 build 131 和 130 的链接是 `https://www.iina.io/IINA.v1.3.0.html` 和 `https://www.iina.io/IINA.v1.3.0-build130.html`，不在 `/release-note/` 下，且都是 404。这两个条目已被同为 1.3.0 的 build 132（链接 `release-note/1.3.0.html`）取代，不会成为任何宿主的头条。
- 页面是否存在：38 个匹配的链接里 32 个 200、6 个 404。404 的全是按 build 命名的页：`1.4.2-build164`、`1.3.2-build134`、`0.0.14-build47`、`0.0.15-build63/64/65`；按 build 命名且存在的只有 `0.0.15-build68.html`。404 是 nginx 默认页，没有 `<h2>`，recipe 解析为空，面板退回嵌入。
  - 所以「有按 build 的说明页，`{version}` 模板会读错」这个前提不成立：`1.4.2-build164.html` 不存在，`{version}` 拼出的 `1.4.2.html` 反倒是 200。选 `feedPagePattern` 的理由是 feed 本来就给出页面地址、随 channel 变化（参考文档对 link-only feed 的约定），不是 build 页。
- 版本一致：32 个存在的页面用生产 `ChangelogExtractor` 跑（临时 Swift 测试，跑完已删），每页条目的版本都等于该条目的 `sparkle:shortVersionString`（含 `1.5.0-beta1`、`1.5.0-beta2`）。用 Python 按同一正则再跑一遍，只有 `0.0.15-build68.html` 不同：该页第一个 `<h2>0.0.15 Build 68</h2>` 下只有裸文本和 `<br>`，没有 `<li>`/`<p>`。生产提取器跳过没有条目的块，取到下一个 `<h2>0.0.15</h2>`（build 62 的说明，34 条），版本串碰巧相同。该条目（min 10.10）已被 0.0.15.1 取代，不会成为头条。
- 头条：生产 `SparkleAppcastSource.probeReleaseNotesLink`（`duo verify` 的路径）对两份 feed 都解析到 `https://www.iina.io/release-note/1.5.0.html`，recipe 接受。按 `minimumSystemVersion` 手算各宿主的头条页：≥ 11 → `1.5.0`，10.15 → `1.4.4`，10.13 → `1.3.5`，10.11 → `1.3.1`，10.10 → `0.0.15.1`；这五页都是 200，生产解析出 76 / 2 / 24 / 23 / 2 条。
- 生产解析结果：1.5.0 共 76 条，分节 New / Bug Fixes / Improvements / Updates / Plugin API / Deprecation Notice；1.5.0-beta2 共 24 条，分节 New / Bug Fixes / Improvements / Plugin API / Deprecation Notice；1.4.4 共 2 条（引言 + 1 条），分节 Bug Fixes。
- 写的时候踩到一个坑：Deprecation Notice 的分节标题和它的条目最初都从同一个 `<p>` 开始匹配。位置相同时排序没有定义，第一次跑测试时条目排到了标题前面。现在条目的匹配从 `<p>` 之后开始。`IINAChangelogRecipeTests.theDeprecationNoticeIsASectionNotARepeatedLine` 对两种变异各红过一次（标题与条目同位置；普通 `<p>` 分支也吃下这段说明）。
- `channel-verify`（真实 1.4.4 dmg，SHA-256 `dd0fc0bd…37beb1`，binding 为 stable）：
  - 加 recipe 前：`changelog pane  web page https://www.iina.io/release-note/1.5.0.html, no structure`
  - 加 recipe 后：`changelog pane  recipe changelog:com.colliderli.iina:-: 1 entries; newest 1.5.0: 76 items, headings ["New", "Bug Fixes", "Improvements", "Updates", "Plugin API", "Deprecation Notice"]; first items ["IINA 1.5.0 introduces the biggest interf", "Added a new Settings window #6016.", "Added a confirmation prompt when deletin"]`
- beta 轨没用 `channel-verify` 复验：它读当前用户的偏好，不改偏好就只能走 stable 一轨。beta 页由 fixture 测试（1.5.0-beta2 整页原文）和上面对全部页面的生产提取覆盖。

```sh
curl -sS -o /dev/null -w "%{http_code} %{url_effective}\n" -A "Mozilla/5.0 (Macintosh)" "https://www.iina.io/release-note/1.4.2-build164.html"   # 404
curl -sS -o /dev/null -w "%{http_code} %{url_effective}\n" -A "Mozilla/5.0 (Macintosh)" "https://www.iina.io/release-note/1.4.2.html"            # 200
curl -sSfL -o "$D/IINA.v1.4.4.dmg" "https://dl-portal.iina.io/IINA.v1.4.4.dmg"
swift run --package-path application-test channel-verify "$D/IINA.v1.4.4.dmg"
```
