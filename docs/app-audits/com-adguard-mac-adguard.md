# AdGuard

审计日期 2026-10-16。覆盖 release / beta / nightly 三条轨。

## 基本信息
- Bundle ID: `com.adguard.mac.adguard`（三条轨相同；pkg 落地的 app 名是 `Adguard.app`）
- Team ID: `TC3Q7MAJXF`（release 2.20、beta 2.20 RC 1、nightly 2.20 Nightly 9 三个真包相同）
- 观测版本: release 2.20（`CFBundleVersion` 2626）、beta 2.20 RC 1（2624）、nightly 2.20 Nightly 9（2625）
- 自更新机制: Sparkle 2.9.5。每个构建在 Info.plist 里写死自己那条轨：`AGChannel`（`release` / `beta` / `nightly`）和对应的 `SUFeedURL`：
  - release: `https://static.adtidy.org/mac/release/adguard-release-appcast.xml`
  - beta: `https://static.adtidy.org/mac/beta/adguard-beta-appcast.xml`
  - nightly: `https://static.adtidy.org/mac/nightly/adguard-nightly-appcast.xml`
- 安装包: 三条轨都是 dmg 里只有一个 `AdGuard.pkg`，enclosure 声明 `sparkle:installationType="package"`。
- `LSMinimumSystemVersion` 12.7.6；feed 的 `sparkle:minimumSystemVersion` 也是 12.7.6，没有上限。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **release**  | ✓       | `adguard`，`auto_updates`，退让给 Sparkle | — | — | — |
| **beta**     | ✓       | —（没有 `adguard@beta`） | — | — | — |
| **nightly**  | ✓       | `adguard@nightly`，`auto_updates`，退让给 Sparkle | — | — | — |

当前生效源: 三条轨都是 **Sparkle**（bundle 自己声明的 feed；`feed-discover` 对 release 包是 `declared`）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| release | `com.adguard.mac.adguard` | 共享 | Info.plist `AGChannel` = `release` | 每个构建声明自己的 feed | ✓ |
| beta    | `com.adguard.mac.adguard` | 共享 | `AGChannel` = `beta`；版本串带 `RC n` / `beta n` | 同上 | ✓ |
| nightly | `com.adguard.mac.adguard` | 共享 | `AGChannel` = `nightly`；版本串带 `Nightly n` | 同上 | ✓ |

三条轨是三个单独下载的构建，各自读自己的 feed，每个 feed 只有本轨一个 item、没有 `<sparkle:channel>` 标签，所以检测天然不会跨轨。

- **channel 标签**: `AdGuardChannel`（`ChannelBinding`，SwiftVM 那一类：构建自带、无偏好，不进 `boundBundleIDs`）读 bundle 自己 Info.plist 的 `AGChannel`：`release` → stable，`beta` → beta，`nightly` → nightly，其他值或没有这个键 → nil（交回 `ReleaseChannel.detect()`）。resolve 之后 `channelIsAuthoritative` 为真，`SparkleAppcastSource.allowedChannels` = {无标签, 本轨的 tag}；三个 feed 的唯一 item 都无标签，所以照旧放行。`AdGuardChannelTests` 用真 feed 的 item 形状测了 beta / nightly / release 三种副本都拿到自己 feed 的 item；把 `beta` 映射成 `.stable` 的变异让它变红。加 binding 之前，`channel-verify` 对 beta、nightly 真包都报 `detected channel → stable`。
- **app 内切轨开关**: 2.20 的设置窗口里找不到更新渠道选项（General 页确认没有；窗口里没有 Updates 之类的页），与 Mac 2.0 进 Alpha 时的博客（adguard.com/en/blog/adguard-for-mac-gets-nightly.html）一致：换轨要装对应的构建。adguard.com/en/beta.html 说可以在设置里切渠道，那是对各平台的笼统说法。主程序里虽有 `feedURLStringForUpdater:`、`setAppUpdateChannel:`、`appUpdateChannel` 符号（`strings` 读出），设置里没有入口，所以按「每个构建只读自己的 feed」处理。换轨就是装那条轨的构建，入口是 `adguard.com/en/beta.html` 上的 `agrd.io/mac_beta`、`agrd.io/mac_nightly`：301 到 `static.adtidy.org/mac/{beta,nightly}/AdGuard.dmg`，大小与 feed 里同版本的 dmg 相同（2026-10-16：112021570 / 112521216 字节）。版本页 `adguard.com/en/versions/mac/nightly.html` 的下载按钮给的是 ~1 MB 引导安装器（`com.adguard.mac.adguard-installer` 1.18.52；dmg 里的 `.tag` 记的是下载来源页），它的二进制里只有 `static.adtidy.org/mac/release/AdGuard.dmg` 和 `…/mac/outdated/AdGuard.dmg` 两个下载地址；没运行过它，但按这点看，从版本页装到的是 release。

## 更新检测
- 源: `SparkleAppcastSource`，读 bundle 声明的 feed。
- 每个 feed 一个 item（2026-10-16）：release 2.20 / 2626，beta 2.20 RC 1 / 2624，nightly 2.20 Nightly 9 / 2625。
- 每个 item 只有 `<sparkle:releaseNotesLink>`，不内联说明。
- release item 带 `<sparkle:phasedRolloutInterval>86400</sparkle:phasedRolloutInterval>`（Sparkle 客户端分 7 组、每组隔一天放量）。我们不读这个字段（Core 里没有 `phasedRollout`），见「一键安装 → 读的是」。
- Homebrew 两个 cask 都 `auto_updates true`，`HomebrewCaskSource` 返回 nil，落到 Sparkle。cask 版本落后（`adguard` 2.19.0.2258、`adguard@nightly` 2.20.0.2402），且是四段构建号；它们不参与检测。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | — |
| 证据 | Sparkle.framework 2.9.5 | 三个 feed（2026-10-16）都没有 `<sparkle:deltas>`；`channel-verify` 报 deltas 0 | 无可消费；而且 package 安装不走 delta |

## Changelog
- 来源: recipe，`feedPagePattern`。页面就是 Sparkle 检查解析出的 `releaseNotesLink`：`https://link.adtidy.org/forward.html?app=mac&action=update_release_notes&from=updater&channel=<release|beta|nightly>`。它重定向到 `adguard.com/<lang>/adguard-for-mac/versions.html?channel=<轨>`，语言跟随 Accept-Language。
- 页面是该轨的多版本列表（最新在前，各 10 条），所以 `maxEntries: 10`，不是每页一版。
- 图片: `<img class="md__img">` 用 `imagePattern` 取出，按原位置排在条目之间（2.17 那一条有两张截图）。分节标题 `<h1>`–`<h4 class="md__title">` 用 `headingPattern`。
- 结构化（`channel-verify` 的 `changelog pane` 行，2026-10-16）：
  - release: `recipe changelog:com.adguard.mac.adguard:-: 10 entries; newest 2.20: 49 items, headings ["System permissions for AdGuard", "Other changes", "Changelog", "Improvements", "Fixes", …]`
  - beta: `recipe …: 10 entries; newest 2.20 RC 1: 2 items, headings ["Changelog", "Fixes"]`
  - nightly: `recipe …: 10 entries; newest 2.20.0.2625: 1 items, headings []`
- 加 recipe 之前，pane 嵌入的是该网页本身（无结构，带图）。
- 没用的另一来源: `github.com/AdguardTeam/AdguardForMac` 不是源码仓库（README 自述是公开 bug tracker，仓库只有 `README.md` 和 `.github`），但 Releases 镜像了 release 和 beta（beta 标 `prerelease`，release 名等于 `shortVersionString`，如 `2.20 RC 1`），共 139 条（2026-10-16），没有 nightly，只有英文，正文是 Markdown、带同样的截图，开头有一句「not an open-source project」声明。历史比版本页长得多，但按轨区分要靠 channel 检测；当时 beta / nightly 安装被判成 stable，所以没换。现在有了 `AdGuardChannel`，换不换待用户定（nightly 仍只能用版本页）。
- 跟随 channel: 是。三条轨的链接各自不同，recipe 接受三者，读的就是 bundle 自己 feed 给的那一条。
- 版本串: release、beta 页面的标题版本等于 feed 的 `shortVersionString`（`2.20`、`2.20 RC 1`）；nightly 页面标题是四段构建号（`2.20.0.2625`），bundle 的 `shortVersionString` 是 `2.20 Nightly 9`，页面上没有 nightly 序号，所以 nightly 的条目版本对不上已装版本字符串。

## 一键安装
- 状态: 支持（Sparkle enclosure，dmg 内 pkg，交给系统 Installer）。
- 端到端（#1321，2026-10-15）：release 2.19（未运行，pkg payload 放进 `/Applications`）→ `duo install` → 下载、EdDSA、打开 `AdGuard.pkg`，由人在 Installer 里完成；结果 2.20（2626），Team `TC3Q7MAJXF`，`duo check` 报 up to date。
- 未跑: app 运行中那一轮；beta / nightly 轨的一键。没跑的原因：启动 AdGuard 会装网络扩展和特权 helper，超出审计预授权的范围。
- 格式: dmg → `AdGuard.pkg`（`installationType="package"`）。
- 校验: feed 只有 `sparkle:edSignature`，没有 SHA 摘要字段。
- **读的是**: 轨道最新。release feed 用 Sparkle 分阶段放量（`phasedRolloutInterval` 86400），我们不读这个字段，所以在一次发布的头 7 天里，一键可能装上 AdGuard 还没分给这台机器的构建。可以接受的理由：enclosure 地址（`static.adtidy.org/mac/release/AdGuard-2.20.0.2626.dmg`）不需要任何凭据就能下载，放量只控制 app 自己提示的节奏，不限制分发。没核对 adguard.com 下载页在放量期间给的是不是同一个构建。
- 阻塞: 无。

## 已知问题
- **夜扫覆盖**: `duo verify` 的清单只有手写 recipe，没有通用 Sparkle 这一类。这次加的 changelog recipe 让 AdGuard 的 changelog（经 release feed 解析出的页面）进了 sweep；检测和一键仍不在 sweep 里，坏了也不会报。#1321 修安装时也是这个原因没被发现：AdGuard 当时没有 recipe、没有审计文档。

## 建议下一步
1. app 运行中的一键那一轮，等能接受启动 AdGuard（网络扩展、helper）时再跑。
2. changelog 换成 GitHub Releases `AdguardTeam/AdguardForMac`（release + beta、历史更长，没有 nightly）：有了 binding 之后可以按轨区分，要不要换由用户定。

## 如何复验

```bash
for c in release beta nightly; do curl -s --compressed "https://static.adtidy.org/mac/$c/adguard-$c-appcast.xml" | grep -E "shortVersionString|releaseNotesLink|installationType"; done
curl -sLo nightly.dmg https://static.adtidy.org/mac/nightly/AdGuard-2.20.0.2625.dmg
hdiutil attach -nobrowse -readonly -mountpoint mnt nightly.dmg && pkgutil --expand-full mnt/AdGuard.pkg x && hdiutil detach mnt
plutil -p x/app.pkg/Payload/Adguard.app/Contents/Info.plist | grep -E "AGChannel|SUFeedURL|CFBundleShortVersionString"
swift run --package-path application-test channel-verify x/app.pkg/Payload/Adguard.app
duo verify --only adguard
```

2026-10-16 结果（release 是已安装的 bundle；beta / nightly 是 pkg 展开、未运行的真包）。detected channel 一列是加 `AdGuardChannel` 之后的结果（`ChannelBinding` 行报 `beta` / `nightly` / `stable`）；之前三个都是 `stable`（inferred）。

| 包 | `AGChannel` | 版本 | `SUFeedURL` | 胜出源 / latest | detected channel | changelog pane |
|---|---|---|---|---|---|---|
| release | `release` | 2.20 (2626) | release feed | Sparkle / 2.20，up to date | stable | recipe，10 条，最新 2.20 |
| beta | `beta` | 2.20 RC 1 (2624) | beta feed | Sparkle / 2.20 RC 1，up to date | beta | recipe，10 条，最新 2.20 RC 1 |
| nightly | `nightly` | 2.20 Nightly 9 (2625) | nightly feed | Sparkle / 2.20 Nightly 9，up to date | nightly | recipe，10 条，最新 2.20.0.2625 |

`duo verify --only adguard`：changelog ✓ 1。

## 历史与实测

### 2026-10-16 recipe 首版的实测

- 三条轨的页面（en）都是 10 个 `feed__item`，pattern 全部读出 10/10。beta 页面有不带序号的后缀（`2.17 beta`、`2.16 RC`），初版 pattern 要求后缀带数字，只读出 8/10，而且错过的标题会吞掉下一条；改成序号可选、header 内部只允许空白之后是 10/10。
- 本地化页面 zh_cn / ja / de 也是 10/10：标题分别是 `AdGuard Mac版 2.20`、`AdGuard for Mac 2.20`、`AdGuard für Mac 2.20`，日期标签分别是 `更新日期：`（全角冒号）、`公開日:`、`Veröffentlicht am:`。
- 图片只出现在 2.17（release）和 2.17 beta（beta）两条里，各两张，都在 `cdn.adtidy.org`。
- 变异：去掉 `imagePattern`、或要求后缀带序号，`AdGuardChangelogRecipeTests` 对应的测试变红。
