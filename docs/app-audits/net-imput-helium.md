# Helium

## 基本信息
- Bundle ID: `net.imput.helium`
- Team ID: `S4Q33XPHB4` (imput LLC)
- 观测版本: `0.16.2.1`（short == build）
- 自更新机制: **Sparkle**，但 feed 地址写在代码里而不是 Info.plist
  （见下方「⚠️ 2026-08-31 更正」）
- 分发: GitHub Releases (`imputnet/helium-macos`) / Homebrew cask `helium-browser`
  （`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | ✓（兜底） | — |
| **beta**   | ✓       | —        | —   | ✗（`/releases/latest` 不返回 prerelease） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（2026-08-31 起）。
feed 地址由 `SparkleFeedCatalog` 补（包里没有 `SUFeedURL`）。GitHub rule **保留**：
Sparkle 在链上排在 GitHub 前面，正常情况轮不到它，但 feed 挂掉时它仍会应答，
是一层不花钱的兜底。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.imput.helium` | 单一渠道 | — | tag 锚 `^X.Y.Z$`（无 v） | ✓ |

**值得注意的陷阱**：repo 的 prerelease release（如 `0.16.1.1`）用的是
**纯数字 tag**，与 stable 同形——靠 GitHub 的 prerelease 标记区分。我们的
stable rule 走 `/releases/latest`（GitHub 定义上排除 prerelease），所以不会
读串；但任何想按 tag 形状过滤的代码在这里都不可靠。

> ⚠️ 2026-08-31 更正：**不是单渠道，而且不是"自研"更新器。**原结论只看了
> Info.plist 里没有 `SUFeedURL` 就下了判断。真包里实际有的东西：
>
> - `Contents/Frameworks/Helium Framework.framework/Versions/152.0.7977.64/Frameworks/Sparkle.framework`
>   ——Sparkle 本体，只是嵌在 Chromium 的版本化 framework 里，不在 `Contents/Frameworks/` 一层，
>   所以只看那一层会漏；
> - Info.plist 里有 `SUPublicEDKey` / `SUScheduledCheckInterval` / `SUEnableAutomaticChecks`
>   / `SUVerifyUpdateBeforeExtraction` / `SUShowReleaseNotes`——一整套 Sparkle 键，独独没有 `SUFeedURL`；
> - 二进制里有 `https://updates.helium.computer/` 与 `mac/appcast-arm64.xml`，以及
>   `helium-update-channel` 这个偏好键。
>
> 拼起来实测：`https://updates.helium.computer/mac/appcast-arm64.xml` 返回 200，9 条条目，
> 每条 5 个 `<sparkle:deltas>`，**其中 `0.16.1.1` 那条带
> `<sparkle:channel>beta</sparkle:channel>`**。x86_64 有对应的
> `mac/appcast-x86_64.xml`（按架构分 feed，不是按渠道）；试过的
> `appcast-arm64-beta.xml` / `beta/appcast-arm64.xml` 都 404。
>
> 也就是说 Helium **有 beta 轨**，用 `helium-update-channel` 切。这条 feed 我们现在
> 没在用（泛化 Sparkle 源只认 Info.plist 里的 `SUFeedURL`），所以 beta 轨用户会被
> stable 的 GitHub rule 覆盖成"有新版"。改不改、怎么改（给 `ChannelBinding` 加一条
> feedOverride，还是维持 GitHub）是待定项，见「建议下一步」。

## 更新检测
- 源: vendor 自己的 appcast `https://updates.helium.computer/mac/appcast-arm64.xml`
  （按架构分 feed；arm64 是 DuoUpdater 唯一的宿主架构）。兜底仍是
  `imputnet/helium-macos` 的 `/releases/latest`。
- 版本方案: `0.16.2.1` == 包的 short 与 build，feed 的 `sparkle:version` 同构，无陷阱。
- **feed 的 enclosure 是相对路径**（`assets/helium_….dmg`）。Sparkle 自己按 appcast URL
  解析相对地址（`SUAppcastItem.m` 里 `[NSURL URLWithString:… relativeToURL:appcastURL]`，
  enclosure / delta / releaseNotesLink 一视同仁），我们的解析器 2026-08-31 起也这么做。
  在那之前它会解析出一个没有 scheme、谁也拉不动的 URL —— 这就是当初判断"接不了"的真实原因。
  （顺带：RSS 2.0 规范说 enclosure 的 url "must be an http url"，所以偏离规范的是**厂商**，
  但偏离 **Sparkle** 的是我们。）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（内嵌 Sparkle） | 有 | **能**（2026-08-31 起） |
| 证据 | 见上方更正 | vendor appcast 每条 5 个 `<sparkle:deltas>`；同一批补丁也作为 release 资产挂在 GitHub 上 | 接上 feed 后 `RemoteVersion.deltas == 5`（真包实测），`DeltaApplier` 按 `deltaFrom == 装机 build` 选补丁 —— 约 40 MB 对全量 124 MB。走 GitHub 时这里是空的：release 资产不说明哪个 `.delta` 从哪个 build 升上来 |

## Changelog
- 来源: **`ChangelogRecipe`**（2026-09-03 起），读 `imputnet/helium-macos` 的 releases API；
  `ChangelogCatalog` 那条兜底页仍在，recipe 不出条目时照旧落到它
- 跟随 channel: 否
- Recipe 状态: ✓（regex over `.json`，非 `structuredFormat: .gitHubReleases`）
- ⚠️ 换到 Sparkle 是**拿说明换渠道和 delta**：GitHub release 正文原本能直接当 changelog
  用（`structuredChangelog` 1 条），而 vendor 的 appcast 9 条**没有一条**带
  `<description>` 或 `sparkle:releaseNotesLink`。不补这条 catalog 条目，说明面板会
  静默变空。`SparkleFeedCatalogTests.everyCatalogFeedAppHasAChangelogFallback` 从表里推导，
  以后再有 app 进这张表也会被这条卡住。
- **为什么不用共用的 `.gitHubReleases` 解码器**：release 正文是「两个 hash 块 + 两段
  fenced 提交日志」，没有一条 bullet。`GitHubMarkdownParser` 的散文兜底会把
  `md5:` / `sha256:` 那几行当成"变更"，而它跳过的 fence 里才是唯一的真内容。
  所以 recipe 直接抓 fence 里的 `<hash> <subject>` 行，hash 被吃掉不显示。
- **两个已量到的坑**（都由 `duo verify` 打真实端点抓出，fixture 测试当时是绿的）：
  1. `api.github.com` 同一份文档**既发紧凑也发 pretty-printed**（同一天不同请求两种都见过），
     所以 key 与冒号之间必须容忍空白；
  2. 正文换行**两种写法都有**——抽样里每个 stable 版本是 `\r\n`，每个 prerelease 版本是 `\n`。
     只认前者不会报错，只会让那条 release **没有条目**，静默消失。
- prerelease 不进列表（与共用解码器同策略）。这里不是理论问题：厂商会先把一个 build 标成
  prerelease 放一两天，appcast 才跟上（2026-09-03 的 `0.16.4.1` 就是），列出来等于给用户看
  一个他并没有被推送的版本的说明。

## 一键安装
- 状态: **支持**
- 格式: dmg — `helium_{v}_arm64-macos.dmg`（`_x86_64-macos.dmg` 是 Intel 孪生）
- Pattern: `^helium_[0-9.]+_arm64-macos\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，0.16.2.1 挂载）: `net.imput.helium` / `0.16.2.1`，Team
  `S4Q33XPHB4`，`spctl accepted / Notarized Developer ID`

## 已知问题
- 无。delta 差分我们不用，但 release 里仍有一个全量 dmg，不影响一键。

## 如何复验
```
# GET https://api.github.com/repos/imputnet/helium-macos/releases/latest → 0.16.2.1
# 挂载 helium_0.16.2.1_arm64-macos.dmg → net.imput.helium / 0.16.2.1
# channel-verify --check net.imput.helium → winning=GitHub, up to date
```

## 建议下一步
两条原本待办的都做完了（2026-08-31）：

1. ✅ **改走 vendor 自己的 appcast。**新增 `SparkleFeedCatalog`——一张"只给 feed、不声明
   渠道"的表，只在包里没有 `SUFeedURL` 时补位，绝不覆盖 app 自己声明的地址。
   **不能**用现成的 `ChannelBinding.feedOverride`：`AppScanner` 只要解析出一条 binding 就把
   `channelIsAuthoritative` 置真，而 `allowedChannels` 一旦看到它就不再从 feed 反查渠道 ——
   恰好关掉下面第 2 条赖以成立的东西。
2. ✅ **beta 轨不需要读那个 flag。**渠道由 `channel(ofInstalled:)` 拿装机 build 去 feed 里
   反查得出。两个真包实测（`channel-verify`，走的是 AppScanner 的生产路径）：

   | 装的包 | usableItems / releaseHistory | 结论 |
   |---|---|---|
   | 0.16.2.1（默认轨） | 9 条里的 **8** 条 | beta 条目被正确滤掉 |
   | 0.16.1.1（beta 轨） | **9** 条 | 自己那条轨解锁 |

   全程没有读 `Local State`。所以 `helium-update-channel@2` 那个序号稳不稳定不再重要 ——
   我们根本不查它。（那条 flag 的记录留在上面，因为它解释了"为什么设置界面里找不到渠道开关"。）

**仍然没做、也不打算做的**：把 `helium-update-channel` 读成 `ChannelBinding`。上面第 2 条
让它变成纯多余，而它引入的是一个位置型判据。

**一个已知盲区**：`InstalledApp.hasSparkleUpdater` 查的是
`Contents/Frameworks/Sparkle.framework`，而 Helium 的那份嵌在 Chromium framework 里，
所以这个标志对 Helium 为 false。后果是 `SelfUpdaterStaging` 那条"app 自己的更新器已经把
新版暂存好了"的识别对 Helium 不生效。本次没动它——那面旗子还管着别的行为，值得单独评估。
（另注：官网说 Helium 只在 "Helium services" 开启时才自更新，而它默认关闭，所以这条盲区
的实际触发面比看上去小。）
