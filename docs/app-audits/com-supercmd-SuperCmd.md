# SuperCmd

"SuperCmd" 是**两个互不相干的 app**，只是共用一个名字、一个厂商、一个 Team ID。
接入时先分清手上的是哪一个。

| | v2（当前产品） | v2 Beta | v1（已停更） |
|---|---|---|---|
| Bundle ID | `com.supercmd.SuperCmd` | `com.supercmd.SuperCmd.beta` | `com.supercmd.app` |
| 技术栈 | 原生 Swift，Sparkle 2.9.4 | 同左 | Electron + Squirrel（electron-builder） |
| 开源 | **否**（发布仓 README 提到的源码仓 `SuperCmdLabs/supercmd-swift`，GitHub API 对外 404） | 否 | 是，`SuperCmdLabs/SuperCmd` |
| 发布仓 | `SuperCmdLabs/supercmd-v2-releases`（只放 appcast 和 dmg） | 同左 | `SuperCmdLabs/SuperCmd` Releases |
| 更新源 | `appcast.xml` | `appcast-beta.xml` | GitHub Releases |
| 显示名 | `SuperCmd` | `SuperCmd Beta` | `SuperCmd` |
| 收费 | 付费（官网 "Buy now" / "Try for free"，Polar 结账） | 同左 | 免费 |

官网首页 `supercmd.sh` 的下载按钮与 JSON-LD `downloadUrl` 都指向
`SuperCmd-v2-releases/releases/latest`。v1 仍有自己的页面 `supercmd.sh/en/v1`
（标题 "SuperCmd v1 | Open-source macOS Launcher"，描述为 "The open-source Electron version of SuperCmd"，
链到 `SuperCmdLabs/SuperCmd`，给的安装命令是 `brew install --cask supercmdlabs/supercmd/supercmd`，
页顶横幅指向 v2）（2026-09-17）。

## 基本信息
- Bundle ID: `com.supercmd.SuperCmd`（v2）/ `com.supercmd.SuperCmd.beta`（v2 Beta）/ `com.supercmd.app`（v1）
- Team ID: `T7HT4U4666`（三者相同，Developer ID，`spctl` 均为 `Notarized Developer ID`）
- 观测版本: v2 `1.0.7`（build `8`）、v2 Beta `1.0.8-beta`（build `1`）、v1 `1.0.26`（build `1.0.26`），2026-09-17
- 自更新机制: v2 / v2 Beta 为 **Sparkle**（`SUFeedURL` + `SUPublicEDKey`，两者同一把公钥）；v1 为 **Electron（Squirrel.Mac）**，
  `app-update.yml` 只写 `provider: github` / `owner: SuperCmdLabs` / `repo: SuperCmd`
- 架构: 三个包的主程序都是 **arm64 thin**（`lipo -archs`）。v1 另发 x64 的 dmg/zip
- 分发:
  - v2: 发布仓的 GitHub Release（`SuperCmd.dmg`）；Homebrew 第三方 tap `shobhit99/tap/supercmd`
    （官网给的命令；cask `version "1.0.7"`，**没有** `auto_updates`，`depends_on macos: :sequoia`）
  - v1: GitHub Release；Homebrew 第三方 tap `supercmdlabs/supercmd/supercmd`（cask `version "1.0.26"`、`auto_updates true`）
  - 主 homebrew-cask 无收录（`brew info --cask supercmd` 报不存在；2026-09-17 的 `formulae.brew.sh/api/cask.json`
    共 7734 个 cask，token 与 artifacts 里都没有 supercmd）；Mac App Store 无上架
  - 所以 `HomebrewCaskSource` 对三者都不会作答：`HomebrewCaskCatalog` 只读主仓那份 `cask.json`，第三方 tap 的 cask
    根本进不了索引。这与两个 tap cask 有没有 `auto_updates` **无关**——那道闸只作用于索引里的 cask。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                    | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------------|---------|----------|-----|--------|-------------|
| **v2 stable**      | ✓（通用，零 recipe） | —（第三方 tap） | — | — | — |
| **v2 beta**        | ✓（通用，零 recipe） | — | — | — | — |
| **v1 stable**      | — | —（第三方 tap） | — | ✓（仅检测） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: v2 与 v2 Beta 为 **Sparkle**，v1 为 **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| v2 stable | `com.supercmd.SuperCmd` | 独立 | — | 独立 feed `appcast.xml` | ✓ |
| v2 beta   | `com.supercmd.SuperCmd.beta` | 独立 | bundle id / 显示名 `SuperCmd Beta` | 独立 feed `appcast-beta.xml` | ✓ |
| v1 stable | `com.supercmd.app` | 独立 | — | `/releases/latest` + tag 锚 `^X.Y.Z$` | ✓ |

**Pattern A（独立安装）**。beta 那条 feed item 的 `<description>` 自己写明：以独立 app identifier
安装、偏好/历史/扩展数据与 stable 分开、走独立 feed、stable 用户留在 stable（2026-09-16 发布）。
真包核对：`SUFeedURL` 确实指向 `appcast-beta.xml`。

两份 feed 的 item **都不带 `<sparkle:channel>`**，所以不需要 `ChannelBinding`：
`SparkleAppcastSource.allowedChannels` 永远放行默认（无 tag）channel，每个 app 只读自己的 feed。

v1 → v2 **不会自动迁移**：bundle id 不同，v1 的更新器读的是 v1 仓库，而 v1 仓库自 2026-06-20 的 `1.0.26`
之后没有新 release（仓库最后 push 2026-07-11）。所以 v1 的行会一直显示「已是最新 1.0.26」，
DuoUpdater 不会、也没有依据提示用户去装 v2。

## 更新检测

### v2 / v2 Beta — Sparkle，零 recipe
- 端点: `https://raw.githubusercontent.com/SuperCmdLabs/supercmd-v2-releases/main/appcast.xml`、
  `…/main/appcast-beta.xml`（两者都由各自 bundle 的 `SUFeedURL` 声明）
- `feed-discover` 对两个真包都判 `declared`。
- 版本方案: `<sparkle:version>` = `CFBundleVersion`、`<sparkle:shortVersionString>` = `CFBundleShortVersionString`，
  两个真包逐字对上（`8`/`1.0.7`、`1`/`1.0.8-beta`）。
- stable feed 2026-09-17 共 7 条（1.0.1–1.0.7，build 2–8），全部带 `sparkle:edSignature`。
  发布仓 README 写明 `1.0.0` 那个 release 刻意不进 feed：它打包时 `SUPublicEDKey` 还是占位符。
  （README 说 `1.0.2` 也不进，但 2026-09-17 的 feed 里有 1.0.2，build 3——README 与 feed 不一致，以 feed 为准。）
- beta 的 build 号从 `1` 重新开始，与 stable 的 `8` 不在一个序列里。因为 bundle id 不同、feed 不同，
  两者从不比较，无害。
- ⚠️ enclosure URL 的仓库名大小写不一：stable 写 `SuperCmd-v2-releases`，beta 写 `supercmd-v2-releases`。
  GitHub 仓库名不区分大小写，两种都能下载。

### v1 — GitHub Releases
- 规则: `Recipes/com-supercmd-app.swift`，`SuperCmdLabs/SuperCmd`，`versionPattern` `^([0-9]+\.[0-9]+\.[0-9]+)$`
- 为什么要规则: `feed-discover` 判 `review electronProviderNeedsConstruction` —— `provider: github` 不写地址，
  `ElectronManifestSource` 按设计不去拼地址，没有规则时 v1 是 unknown。
- 版本方案: tag `1.0.26` == `CFBundleShortVersionString` == `CFBundleVersion`。2026-09-17 全部 27 个 release
  （`1.0.0`–`1.0.26`）都是裸 `X.Y.Z` tag、`prerelease: false`、无 draft。
- ⚠️ 两条版本线**号码重叠**：`1.0.0`–`1.0.7` 在 v1 和 v2 各有一份。只因为 bundle id 不同才互不干扰，
  所以 v1 这条规则绝不能被抄到 v2 的 id 上——`SupercmdGitHubRuleTests.v2HasNoRecipeOfItsOwn` 钉住了。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | v2/beta 有；v1 没查 | 无 | 不适用 |
| 证据 | v2 与 beta 的 `Sparkle.framework/…/Autoupdate` 含 `BinaryDelta`/`bspatch` 字符串 24 处（Sparkle 2.9.4） | 2026-09-17 两份 appcast 均无 `<sparkle:deltas>`；v1 只有 `.blockmap`（electron-builder 差分下载，不是二进制补丁） | 服务端哪天发 Sparkle delta，`VendorAppcastDeltas` + `DeltaApplier` 现成可用 |

- 按 OS 分轨: 两份 feed 每条都是 `minimumSystemVersion 15.0`，没有 `maximumSystemVersion`；
  v2/beta 包 `LSMinimumSystemVersion=15.0`，v1 包 `12.0`。
  ⚠️ 官网写 "Requires macOS 26 or later"，与 feed、包、tap cask（`:sequoia`）都不一致。
  `SparkleAppcastSource` 读的是 feed 的 15.0。哪个才是真实下限：**未验证**。
- 按设备灰度: 无。feed 是静态文件，谁读都一样。
- 自更新器会不会和我们抢: v2 的 Sparkle 开着 `SUEnableAutomaticChecks`，与其他 Sparkle app 同理。

## Changelog
- v2 / beta: feed 的 `<description>` 内联（stable 是 HTML 分节列表，1.0.7 那条 9647 字符；beta 是纯文本），
  `SparkleAppcastSource` 原生带回，**不需要 recipe**，天然跟随各自的 feed。
- v1: GitHub release 正文（generate-notes 的 `## What's Changed`），`GitHubReleasesSource` 解析成结构化 changelog，不需要 recipe。

## 一键安装
- v2 / beta: 走通用 Sparkle 安装路径（dmg；enclosure 有 EdDSA 签名，Team `T7HT4U4666`）。
  本次对 v2 只核对了检测与包签名，因为观测版本已是最新，**没有真正跑一遍一键升级**。
- v1: **仅检测**。不是因为做不到：1.0.26 的 arm64 dmg 是 Developer ID 签名 + 公证、`codesign --verify --deep --strict` 退 0。
  这条线从 2026-06-20 起没有新 release，所以暂未加 install pattern。
- **读的是**: 轨道最新。三条都是静态 feed / `/releases/latest`，没有按设备分配，与厂商自己的更新器读的是同一份东西。

## 已知问题
- 官网写的最低系统版本（macOS 26）与 feed/包（15.0）不一致，见上。
- v1 用户永远不会被提示 v2 的存在（bundle id 不同）。这是产品层面的迁移问题，不是检测问题。

## 建议下一步
1. 无必做项。v2 stable/beta 通用覆盖，v1 已加 GitHub 检测。
2. 如需要：给 v1 加一键（arm64 dmg，`installAssetPattern` + `installerKind`）。

## 如何复验

```sh
# 身份（dmg 只读挂载即可，不必安装）
plutil -p "<SuperCmd.app>/Contents/Info.plist" | grep -E "CFBundleIdentifier|ShortVersion|CFBundleVersion\"|SUFeedURL"
codesign -dvvv "<SuperCmd.app>" 2>&1 | grep TeamIdentifier

# 检测源（生产代码）
swift run --package-path application-test feed-discover "<SuperCmd.app>"
swift run --package-path application-test channel-verify "<SuperCmd.app>" --expect stable
swift run --package-path application-test channel-verify "<SuperCmd Beta.app>" --expect beta

# v1 的 tag 形状
gh api --paginate "repos/SuperCmdLabs/SuperCmd/releases?per_page=100" -q '.[] | [.tag_name, .prerelease] | @tsv'
```

2026-09-17 的结果。三个 dmg 的来历：beta 是用 `gh release download` 从 `beta-v1.0.8-beta-1` release 直接下的
（25,097,825 字节，与 feed 的 `length` 一致）；`SuperCmd.dmg` 的 sha256 与 v2 tap cask 的 `b39f9227…cceceb` 一致、
大小 21,085,586 字节与 feed 里 1.0.7 的 `length` 一致；`SuperCmd-1.0.26-arm64.dmg` 的 sha256 与 v1 tap cask 的
`33d1fd9c…c45171` 一致:

| 包 | feed-discover | 检测 channel | winning source | latest | status |
|---|---|---|---|---|---|
| v2 `1.0.7 (8)` | `declared` | stable | Sparkle | 1.0.7（history 7 条） | up to date |
| v2 Beta `1.0.8-beta (1)` | `declared` | beta | Sparkle | 1.0.8-beta（history 1 条） | up to date |
| v1 `1.0.26`，**加规则前** | `review electronProviderNeedsConstruction` | stable | `<none>` | `<none>` | unknown |
| v1 `1.0.26`，加规则后 | 同上 | stable | GitHub | 1.0.26 | up to date |
