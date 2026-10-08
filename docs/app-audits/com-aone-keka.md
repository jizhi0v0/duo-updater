# Keka

审计 2026-10-08（重审；取代 2026-06-04 那版只核了 bundle 身份、且下载中断、Team / 版本都标 needs-verify 的记录）。

## 基本信息
- Bundle ID: `com.aone.keka`（stable、dev 预发布包、Mac App Store 版同一个 id）
- Team ID: `4FG648TM2A` — Developer ID Application: Jorge Garcia Armero。1.6.8、1.6.7、
  1.5.2-dev r5614、1.5.2-dev r5608 四个真包相同，均 `spctl` 判 Notarized Developer ID
- 观测版本: stable `1.6.8`（build `5748`）· 上一版 `1.6.7`（build `5729`）· dev 预发布
  `1.5.2-dev`（build `5614` / `5608`，两个包的 short 都是 `1.5.2-dev`）；
  `LSMinimumSystemVersion` 10.10；`lipo -archs` = `x86_64 arm64`（通用包）
- 自更新机制: Sparkle（`Contents/Frameworks/Sparkle.framework`，framework 版本
  `2.0.0-5-g382b24bb`，build 2008，厂商自带的 2.0.0 分支）。`SUFeedURL = https://u.keka.io`
  （302 到 `keka.xml`），`SUPublicEDKey` + `SUPublicDSAKeyFile`，`SUEnableDownloaderService` /
  `SUEnableInstallerLauncherService` = true，`SUEnableSystemProfiling` = false
- 沙盒: 主 app 有 `com.apple.security.app-sandbox`，偏好落在
  `~/Library/Containers/com.aone.keka/…`
- `Info.plist` 里 `LSUIElement = true`（主 app 本身，不是 helper）
- 嵌套: `Contents/PlugIns/KekaFinderIntegration.appex`（`com.apple.FinderSync` 扩展）；
  Sparkle 自带的 `Updater.app` 和两个 XPC 服务。没有 `Contents/Library/LoginItems`、没有
  `Contents/Helpers`
- 分发: GitHub Releases（`aonez/Keka`，每版 dmg + zip + 8 个 `.delta`）· 官网 keka.io ·
  Mac App Store（id `470158793`，同 bundle id，付费，2026-10-08 lookup 为 1.6.8）·
  Homebrew cask `keka` 与 `keka@beta`（都 `auto_updates true`，互相 `conflicts_with`）
- 源码: **不公开**。`aonez/Keka` 仓库只有 README、翻译、wiki 素材、issue 模板和 release，
  没有 app 源码；1a-00 能读到的只有 release 列表和 wiki（`Hidden-configuration` 页列出的隐藏
  偏好里没有任何更新/渠道相关的键）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —（`auto_updates`，让位） | ✓（通用，本次未用真 store 副本复验） | — | — |
| **dev（预发布）** | ✓ 只到 stable（与 Keka 自己的更新器一致） | —（`keka@beta` 同样 `auto_updates`） | — | ✗ 不接（见 Channel 详情） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（Developer ID 副本；
`channel-verify` 实测 `winning source Sparkle`）。Store 副本由 `MacAppStoreSource` 应答——
它是唯一 `answersAppStoreCopies` 的源，Store 副本上即使带 `SUFeedURL` 也轮不到 Sparkle。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.aone.keka` | 共享 | — | 唯一 feed 的唯一条目（无 `<sparkle:channel>`） | ✓ |
| dev     | `com.aone.keka` | 共享 | `CFBundleShortVersionString` 后缀 `-dev`（两个真 dev 包都推断为 `dev`） | 无：dev 包读的是**同一个** `SUFeedURL`，只会被推到 stable | ✓（dev→stable）；dev→更新的 dev ✗ |

Keka 的 dev 轨是**手动下载**的 GitHub prerelease（`v1.5.2-dev.r5614`、`v1.5.2-dev.r5608`、
`v1.4.0-dev.r5423` …，`prerelease: true`），不是应用内开关。依据：

- 两个 dev 真包的 `SUFeedURL` 都是 `https://u.keka.io`，与 stable 包一字不差。
- 主二进制实现的 Sparkle delegate 方法只有 `updater:didFindValidUpdate:`、
  `updater:willDownloadUpdate:withRequest:`、`updater:willInstallUpdate:`、
  `updater:willInstallUpdateOnQuit:immediateInstallationBlock:`、`updater:didAbortWithError:`、
  `updater:failedToDownloadUpdate:error:`（`otool -ov` 的 method list，imp 非零）。
  `feedURLStringForUpdater:` / `allowedChannelsForUpdater:` / `feedParametersForUpdater:` 只出现在
  Sparkle 协议声明里（imp `0x0`），Keka 没实现；二进制里也没有 `setFeedURL` 字样。
- 偏好面板（`preferences.nib` / `preferences.strings`）里与更新有关的只有「Automatically check for
  updates」和「Automatically install new updates」，没有 beta / 渠道开关。
- 2025-06-20 的 Wayback 快照（r5608 已发、r5614 未发的窗口）里 `keka.xml` 只有 1.5.1 一条 stable。
- 官网 `#beta` 段落 2026-10-08 显示「There is no beta available at the moment.」

所以 Keka 自己的更新器对 dev 副本做的事，就是把它推到下一个 stable；duo 对 1.5.2-dev r5614 的实测
`UPDATE → 1.6.8` 与之一致。没有渠道偏好可读，也就不需要 `ChannelBinding`（`resolver(for:)` 里本来也
没有这个 id）。

**一个 feed 存在但没有已发布的包去读它**：`https://u.keka.io/keka-beta.xml`（2026-10-08 HTTP 200，
`last-modified: Wed, 11 Jun 2025`），1 条未打 tag 的 item：`1.5.2-dev`（`5608`），带 inline
`<description>`（「This is a development version, use it at your own risk.」+ 两个链接）。r5614 发布后它
没有更新过。我们看过的四个包里没有一个指向它。上游 Sparkle 2.x 的 `SUHost -objectForKey:` 会让宿主
user defaults 里的 `SUFeedURL` 覆盖 `Info.plist`，那么理论上可以手动改偏好让副本读这个 feed，
但 Keka 的文档没写这条路。Keka 用的是自带的 2.0.0 分支，这个分支的行为**没有反汇编确认（未验证）**。
duo 只读 `Info.plist` 里的 `SUFeedURL`（`BundleFacts`），不读这个覆盖。

## 更新检测
- 源: `SparkleAppcastSource`（通用，不需要 recipe；`feed-discover` 判 `declared`）
- 端点: `https://u.keka.io` → 302 `keka.xml`。Apache 上的静态文件（`etag` + `last-modified:
  Thu, 24 Sep 2026 06:42:14 GMT`，`cache-control: max-age=172800`）。带 dev 版 UA 请求，拿到的
  字节和默认 UA 完全相同（`cmp` 无差异）
- feed 结构（2026-10-08）: **1 个 `<item>`**，0 个带 `<sparkle:channel>`、1 个不带；
  enclosure 是 `Keka-1.6.8.zip`（`length` 32824728，`sparkle:version` 5748，带 `edSignature` +
  `dsaSignature`）；`<sparkle:deltas>` 8 个；没有 `phasedRolloutInterval`；`minimumSystemVersion`
  10.10，没有 `maximumSystemVersion`，没有 `hardwareRequirements`，没有 `criticalUpdate`；
  没有 `<description>`，也没有 markdown 说明，只有 `sparkle:releaseNotesLink`
  （`https://u.keka.io/changelog.php`）和 `sparkle:fullReleaseNotesLink`（`https://changelog.keka.io`）
- 版本方案: feed 的 `shortVersionString` 等于包里的 `CFBundleShortVersionString`，
  `sparkle:version` 等于 `CFBundleVersion`（1.6.8 / 5748 两边都对上）。dev 包的 short 是
  `1.5.2-dev`，跨好几个 build 不变，build（5608 → 5614）才区分
- feed 只留最新一条；`channel-verify` 报 `release history 0 entries`（pubDate 写成
  `24 Sep 2026`，没有时间和时区；为什么是 0 而不是 1 没有深查）
- 1.6.6（build 5727）只发了 dmg、没有 zip，也不在 1.6.8 的 delta 来源里；同一天就发了 1.6.7。
  落在 1.6.6 的副本拿全量 zip
- Homebrew: `keka` / `keka@beta` 两个 cask 都 `auto_updates true`，`HomebrewCaskSource` 让位。
  `keka@beta` 2026-10-08 指向的也是 stable 1.6.8 的 dmg（livecheck 正则同时接受 `-beta` / `-dev`）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能 |
| 证据 | `Sparkle.framework/Versions/B/Autoupdate` 里有 12 处 `BinaryDelta` / `deltaFrom` 字样 | 2026-10-08 `keka.xml` 唯一条目带 8 个 `.delta`，`deltaFrom` = 5613, 5638, 5665, 5695, 5699, 5707, 5715, 5729（1.5.2 … 1.6.7，每个都有 `edSignature`） | `VendorAppcastDeltas` + `DeltaApplier`；`channel-verify` 对 1.6.7 报 `deltas 8`。1.6.7→1.6.8 的补丁 1870034 字节，全量 zip 32824728 字节 |

- 格式: Sparkle binary delta
- 阻塞: 无。1.6.6（5727）没有对应补丁，走全量

## Changelog
- 来源: **GitHub releases API**（`api.github.com/repos/aonez/Keka/releases?per_page=40`），
  `ChangelogRecipe` `structuredFormat: .gitHubReleases`，`maxEntries: 20`，
  `tagPattern: ^v([0-9]+(?:\.[0-9]+){1,3})$`。feed 自己只有 `releaseNotesLink`，面板不再嵌它
- 结构化: **有，保留厂商分节**。1.6.8 真包 `channel-verify` 原文：
  `changelog pane  recipe changelog:com.aone.keka:-: 20 entries; newest 1.6.8: 10 items, headings ["Fixes", "Formats", "Translations"]; first items ["Fixed custom task counter in the Dock no", "Fixed password encoding detection in pla", "Fixed non tarball ZSTD extraction with v"]`
  （接入前是 `web page https://u.keka.io/changelog.php, no structure`）
- 为什么不用 `changelog.keka.io`：它是 feed 的 `fullReleaseNotesLink`，同样的条目、带日期，但每版是一个
  平铺的 `<ul>`，没有分节；GitHub 正文把同样的条目放在 `## Fixes` / `## Formats` / `## Translations` /
  `## Features` 下面，生产解析器把它们保留成标题。实测对比见「历史与实测」
- 正文开头两行推广（Keka for iOS、Mastodon / X）和一句话概述不是列表项，解析器不收
- dev / beta / rc 是同一列表里的 prerelease，`.gitHubReleases` 只取稳定版；`v1.2.0-dev.3742` 是
  `prerelease: false` 的 dev 包，靠 `tagPattern` 挡掉。stable 副本看不到任何 dev 条目
- hot-fix 版的正文会在 `# Changes in version X.Y.Z` 下重述上一版（1.6.7 带 1.6.6、1.6.3 带 1.6.2）。
  `GitHubMarkdownParser` 在 X 比本版旧时整节丢掉，所以 hot-fix 条目只剩它自己的修复（1.6.7 显示 1 条，
  与官网一致）。被重述的那一版自己的条目照常存在
- 跟随 channel: 否。dev 副本读的也是 stable feed，面板显示稳定版的历史
- Recipe 状态: ✓（`Recipes/com-aone-keka.swift`，测试 `KekaChangelogRecipeTests`）。匿名请求受 GitHub
  60 次/小时限流，配了 token 时 `ChangelogService` 会带上

## 一键安装
- 状态: 预计支持（通用 Sparkle 路线，无需 recipe；端到端未跑）
- 端到端: 未跑（本轮未执行，原因与 app 本身无关）
- 格式: zip（feed enclosure），顶层只有 `Keka.app`；GitHub 同版另有 dmg（cask 用的那个）
- 校验: feed 带 `sparkle:edSignature`（EdDSA），通用路线按 bundle 的 `SUPublicEDKey` 验签。feed
  里没有 SHA 摘要；GitHub asset 的 `digest` 与真实下载一致：1.6.8 zip
  `sha256:9878b94156fdd1c7e83f0e1a8a8e2114e057070f628569c705637c2f800a2f28`，1.6.7 zip
  `sha256:2773d444027f9d3d0a3b4cae7d5f045ed287dcf66d356cedcd56aa8a88248d5a`，字节数也与 feed /
  API 的 size 相同。旧审计说的「下载卡在 21 MB」这次没有复现
- Team: 1.6.7 与 1.6.8 都是 `4FG648TM2A`，上一版的副本过得了 Team 闸
- **读的是**: 人人可手动下载的 GA。feed 是静态文件，只有一条，和 GitHub release、官网 dmg、
  Store 版同一天、同一版本；没有按设备灰度
- 阻塞: 无。需要端到端时注意：
  - `KekaFinderIntegration.appex` 是 FinderSync 扩展，启用后由系统常驻拉起。换 bundle 之后，旧
    扩展进程可能继续跑旧代码，直到系统重新拉起它；Keka 自己的 Sparkle 更新也有同样的问题。
    这一点**未实测**
  - 主 app 的 `LSUIElement = true`，启动后的激活策略、`duo restart` 的行为都要在端到端里看一眼
  - Keka 偏好里有「Automatically install new updates」（Sparkle 退出时安装），所以要跑第 2 轮
    （app 在跑、它自己的更新器已就绪）

## 已知问题
- changelog 的 hot-fix 条目会带上一版的重述条目（见 Changelog）。
- `keka-beta.xml` 停在 2025-06-11 的 r5608，晚于它的 r5614 不在里面；没有已发布的包指向它。
- 改了 user defaults `SUFeedURL` 的副本，Keka 自己读覆盖后的地址，duo 读 `Info.plist` 的地址，
  两边会看到不同的 feed。这是所有 Sparkle app 都有的通用差异，不只是 Keka；Keka 也没文档化这条路。

## 建议下一步
1. 不需要检测或一键相关的代码。下一步跑一次端到端：先装 1.6.7（不启动）再
   `duo install`，然后在 app 运行、自动安装已就绪的状态下再跑一轮；看补丁路线（预期用
   `1.6.7r5729-1.6.8r5748.delta`）、FinderSync 扩展、`duo restart`。
2. 结构化 changelog：已做（GitHub releases，保留分节），见 Changelog。
3. dev 轨：不接。厂商的更新器不分发 dev 构建，没有偏好可读。`CHANNEL_COVERAGE_TODO.md` 可记一行
   「Keka dev = 手动 GitHub prerelease，dev 副本被推到 stable，与厂商一致」。是否支持 user defaults 的
   `SUFeedURL` 覆盖是通用 Sparkle 的问题，需要的话单独立项，不放在 Keka 下面。

## 如何复验

```bash
W=$(mktemp -d); cd "$W"
# 1. feed（注意 u.keka.io 302 到 keka.xml）
curl -sSL "https://u.keka.io" -o keka.xml
curl -sS "https://u.keka.io/keka-beta.xml"
grep -c '<item>' keka.xml; grep -c 'sparkle:channel' keka.xml; grep -c deltaFrom keka.xml

# 2. 真包（GitHub asset，sha256 对 API 的 digest）
gh api repos/aonez/Keka/releases/tags/v1.6.8 -q '.assets[] | "\(.name) \(.size) \(.digest)"'
curl -sSL -o Keka-1.6.8.zip "https://github.com/aonez/Keka/releases/download/v1.6.8/Keka-1.6.8.zip"
curl -sSL -o Keka-1.6.7.zip "https://github.com/aonez/Keka/releases/download/v1.6.7/Keka-1.6.7.zip"
curl -sSL -o Keka-1.5.2-dev.r5614.zip "https://github.com/aonez/Keka/releases/download/v1.5.2-dev.r5614/Keka-1.5.2-dev.r5614.zip"
shasum -a 256 Keka-*.zip
for z in Keka-*.zip; do mkdir -p "x/${z%.zip}"; ditto -x -k "$z" "x/${z%.zip}"; done

# 3. 身份、签名、嵌套（以下在仓库根目录执行）
cd <repo>
.claude/skills/coverage-discovery/scripts/check-bundle.sh "$W/Keka-1.6.8.zip"
codesign -dvv "$W/x/Keka-1.6.7/Keka.app" 2>&1 | grep TeamIdentifier
otool -ov "$W/x/Keka-1.6.8/Keka.app/Contents/MacOS/Keka" | grep -B1 -E 'name .*(ForUpdater|updater:)'

# 4. 生产判定（channel-verify 吃 .app / .dmg，不吃 zip，所以用解出来的 .app）
swift run --package-path application-test feed-discover "$W/Keka-1.6.8.zip"
swift run --package-path application-test channel-verify "$W/x/Keka-1.6.7/Keka.app"
swift run --package-path application-test channel-verify "$W/x/Keka-1.6.8/Keka.app"
swift run --package-path application-test channel-verify "$W/x/Keka-1.5.2-dev.r5614/Keka.app"
```

2026-10-08 结果：

| 包 | short / build | Team | `feed-discover` | detected channel | winning source | status | changelog pane |
|---|---|---|---|---|---|---|---|
| Keka-1.6.8.zip | 1.6.8 / 5748 | `4FG648TM2A` | `declared  https://u.keka.io` | stable | Sparkle | up to date | `web page https://u.keka.io/changelog.php, no structure` |
| Keka-1.6.7.zip | 1.6.7 / 5729 | `4FG648TM2A` | — | stable | Sparkle | `UPDATE → 1.6.8`（`deltas 8`） | 同上 |
| Keka-1.5.2-dev.r5614.zip | 1.5.2-dev / 5614 | `4FG648TM2A` | — | dev（版本后缀推断） | Sparkle | `UPDATE → 1.6.8` | 同上 |
| Keka-1.5.2-dev.r5608.zip | 1.5.2-dev / 5608 | `4FG648TM2A` | — | （只核了身份与 `SUFeedURL`） | — | — | — |

`check-bundle.sh`：1.6.8 与 1.6.7 都是 `codesign-verify-exit=0`、`spctl source=Notarized Developer ID`，
没有列出嵌套 app。四个包的 `SUFeedURL` 都是 `https://u.keka.io`。

上表的 changelog pane 一列是接入 recipe 之前的结果；接入后的那一行见 Changelog 一节。

## 历史与实测

### Recipes/com-aone-keka.swift — changelog（GitHub releases）

2026-10-08 接入时的实测：

- 两个候选源都在临时 Swift 测试里跑了生产路径（`ChangelogService.parse`），输入是当天抓的原始响应：
  - `api.github.com/repos/aonez/Keka/releases?per_page=40`（40 条，31 稳定、9 prerelease）按本 recipe
    解出 **20 条**，全部是稳定版（1.6.8 … 1.4.1）。19 条带分节标题，1.4.3 只有一个 `## Changes`，
    不到解析器「≥2 个标题」的门槛，平铺显示。1.6.8：10 条，`Fixes` / `Formats` / `Translations`。
  - `changelog.keka.io` 用审计里那条正则（`entryPattern` + `<li>` 条目）解出 40 条（`maxEntries` 上限），
    条目和日期都对，但 `content` 为空，没有任何标题。1.6.7 是 1 条、1.6.3 是 1 条。
  - 比了最新 12 个版本（1.6.8 … 1.5.0）：同版本条目数一致（如 1.6.8 10/10、1.6.6 8/8、1.6.2 13/13），只有
    1.6.7（9 对 1）和 1.6.3（14 对 1）不同，原因是 GitHub 正文的 `# Changes in version …` 重述。更早的没比。
  - 解析器改为丢掉重述上一版的节之后（`Changelog.parserGeneration` 11）：1.6.7 9 → 1 条、1.6.3 14 → 1 条，
    与 changelog.keka.io 一致。
- 选 GitHub 的理由：要求是保留厂商的分节标题，只有 GitHub 正文有；代价是上面两条 hot-fix 的重述和 GitHub 限流。
- 列表里的非稳定条目：第 1 页有 9 个 prerelease（`v1.5.2-dev.r5614` … `v1.2.62-beta.1`），全部 `prerelease: true`。
  第 3 页有 `v1.2.0-dev.3742`（2019-12-20）是 `prerelease: false`，还有 `dev-test-builds`（`prerelease: true`，
  正文是测试包清单）。`tagPattern` 是为前者加的；不设它时生产解码器会把 `1.2.0-dev.3742` 当稳定版收进来
  （`KekaChangelogRecipeTests` 里有这条对照）。
- 变异验证：把 `tagPattern` 改成 `nil`，`KekaChangelogRecipeTests` 的两条用例变红（条目列表多出
  `1.2.0-dev.3742`），还原后三条全绿。
- 真包：GitHub asset `Keka-1.6.8.zip`（sha256 `9878b941…0a2f28`，与审计记录一致）解包后跑 `channel-verify`，
  changelog pane 一行见 Changelog 一节。
