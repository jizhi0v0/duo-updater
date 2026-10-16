# Krita

审计 2026-10-16（首次接入）。

## 基本信息
- Bundle ID: `org.krita`（5.x、6.x 两条线、Krita Plus / Next 夜构建、4.4.8 都是这个 id）。Mac App Store 版是另一个 id
  `org.kde.krita`（付费，2026-10-16 iTunes lookup 版本 `5.3.2`），按收据走通用的 `MacAppStoreSource`（没跑），本文的 recipe 不碰它
- Team ID: `DL93766A3G`（Developer ID Application: IVAN YOSSI SANTA MARIA GONZALEZ）— 5.2.16、5.3.3、5.3.4、5.3.4.1、6.0.3、
  6.0.4.1 六个真包相同，`spctl` 均 `Notarized Developer ID`。4.4.8 与 Krita Plus 夜构建是 `5433B4KXM8`（K Desktop Environment e.V.）
- 观测版本: 5.x 线 `5.3.4.1`（`CFBundleShortVersionString` = `CFBundleVersion` = `5.3.4`，`CFBundleLongVersionString` = `5.3.4.1`），
  上一版 `5.3.3`；6.x 线 `6.0.4.1`（短版本 `6.0.4`），上一版 `6.0.3`。全部 universal（`x86_64 arm64`）；
  `LSMinimumSystemVersion` 5.3.4 起 `10.15`（5.3.3 是 `10.14`），6.x `12`
- 自更新机制: **无**。应用内只有「检查更新」：读 krita.org 新闻 RSS，取第一条 `Official Release` 分类的标题里的版本号，
  有新版就给下载页链接，不下载不替换（settled from source: `libs/ui/utils/KisManualUpdater.cpp` on `master`，
  `invent.kde.org/graphics/krita`）。2026-10-16 抓到的 feed 里 `<item>` 都没有 `<category>`，按源码这条检查找不到任何发布
  （**推断**，没在 app 里点过）
- 开源: `invent.kde.org/graphics/krita`（KDE GitLab，不是 GitHub；GitHub 镜像不发 release 资产）
- Homebrew: cask `krita`，`auto_updates` 未声明，URL `https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-signed.dmg`，
  版本 `5.3.4.1`（2026-10-16 formulae API）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **5.x（推荐线）** | — | ✓（仅 brew 装的拷贝；热修复版见「已知问题」） | ✓ 通用源（`org.kde.krita`，另一个 app，没跑） | — | ✓ 一键（`download-page`） |
| **6.x（Qt 6，实验）** | — | —（没有 cask） | — | — | ✓ 一键（`krita6`） |
| **nightly（Plus / Next）** | — | — | — | — | ✗ 分不出来（见下） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: brew 装的拷贝 → **Homebrew**（`HomebrewCaskSource`，`SourceStack` 里排在
VendorProbe 前）；官网 dmg 直装的拷贝 → **VendorProbe**。接入前直装拷贝没有任何源应答（包里没有 `SUFeedURL`、
`app-update.yml`、MyGo feed）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| 5.x 推荐线 | `org.krita` | 共享 | 主版本号不是 6 | `installedVersionPattern` `^(?!6\.)` | ✓ |
| 6.x 线 | `org.krita` | 共享 | 主版本号 6 | `installedVersionPattern` `^6\.` | ✓ |
| nightly | `org.krita` | 共享 | 只在 `CFBundleLongVersionString`（`5.3.5-prealpha`），duo 不读这个键 | — | ✗ |

**两条线是厂商同时发布的两个正式版本**（一份源码按 Qt 5 / Qt 6 构建）。5.3.0 的发布文写明 6 是「rather experimental」、
正式工作用 5.3，并预计 6 在年底前成为主版本；之后每篇发布文都重复「5.3.x suitable for productive work; 6.0.x … more experimental」。
下载页 `krita.org/en/download/` 只链 5.x 的 dmg。两条线都是 `channel: .stable`，按装机主版本分给两条 recipe（CCC 的做法），
5.x 拷贝不会被推到 6.x，6.x 拷贝也不会被拿 5.x 版本号比成「已是最新」。下载页换成 6.x 之后，5.x 拷贝会被推下载页给的版本，
这是厂商推荐的方向。

**nightly（实测）:** `cdn.kde.org/ci-builds/graphics/krita/krita-6.0/macos-universal-qt5/krita-5.3.5-prealpha-0ddbd23.dmg`
（Krita Plus，2026-10-16）是 `org.krita`，`CFBundleShortVersionString` = `CFBundleVersion` = `5.3.5`，没有后缀；只有
`CFBundleLongVersionString` = `5.3.5-prealpha` 标出是夜构建。Team 是 `5433B4KXM8`（与正式版不同），`spctl` Notarized。
`ReleaseChannel.detect()` 读不到任何信号，判 `stable`。今天的行为（`channel-verify` 实测）：5.3.5 夜构建对 5.3.4 报「已是最新」。
等正式 5.3.6 出来会推给它；一键时 Team 闸（装机 `5433B4KXM8` ≠ 下载 `DL93766A3G`）拒装（读 `SignatureVerifier.verifyTeamIdentifierMatch` 得出，没跑）。
Krita Next（`master/macos-universal/krita-6.1.0-prealpha-*.dmg`）没下载，按同一构建流程**推断**形状相同。

## 更新检测
- 5.x：`https://krita.org/en/download/`（静态 HTML，28 KB）。页上唯一一个 macOS dmg 链接
  `https://download.kde.org/stable/krita/5.3.4.1/krita-5.3.4.1-signed.dmg`，版本和安装地址都从这同一个链接读
- 6.x：`https://krita.org/en/index.xml`（app 自己请求的 `/en/feed/` 301 到这里）。每篇发布文同时链两条线的 dmg；
  取 `stable/krita/6.*` 下版本最高的 dmg（按链接自己写的版本比，与文档顺序无关）。feed 只保留最新 20 篇
- **版本方案**: KDE 的热修复版是四段（`5.3.4.1`），包里短版本和 build 都只有三段（`5.3.4`），四段只在 `CFBundleLongVersionString`。
  两条 recipe 都只取前三段：读四段会让热修复后的拷贝永远比 `5.3.4.1` 小。代价：同一个三段版本之间的热修复（5.3.4 → 5.3.4.1）不推
- 历史版本形状: `download.kde.org/Attic/krita/` 与 `stable/krita/` 的全部目录名都是 `x.y.z` 或 `x.y.z.w`（另有
  `-beta.N` / `-rc.N` / `-prealpha` / `-HDR` / `-android` 后缀的目录）。正式 dmg 链接都在 `stable/` 下；beta 在 `unstable/`，
  两条 pattern 都不收
- 已知局限: 6.x 的热修复只有在厂商写了发布文时才出现在 feed（5.3.2.1 / 6.0.2.1 有，5.3.4.1 / 6.0.4.1 没有）

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 包里没有 Sparkle / 任何更新框架；更新检查只比版本号（`KisManualUpdater.cpp`） | 每个版本目录只有完整 dmg / AppImage / exe / apk | — |

- 格式: —
- 阻塞项: —

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | 否（读公开 RSS） | 否（下载页、feed 无参数） | — |
| 按架构 / 按 OS 分轨 | 架构否（universal）；OS 由包内 `LSMinimumSystemVersion` 定（5.x 10.15、6.x 12） | 端点不声明 OS 范围 | 两个下限都低于 DuoUpdater 自己的 15.0，不需要 `hostRequirement` |
| 自更新器会不会和我们抢 | 否：只提示、给链接 | — | — |
| 已停放整包 | 不会（不下载） | 无 | — |

## Changelog
- 来源: `ChangelogRecipe` 读 `https://krita.org/en/index.xml` 的发布文，正文实体转义（`&lt;li&gt;`），只取第一个下载标题之前的 `<li>`
- 两条 recipe 用 `belowAppVersion` / `minimumAppVersion` `"6"` 拼成整段：5.x 用标题里的版本号，6.x 用同一篇文章里 6.x 下载标题的版本号
  （同一篇发布文，条目相同，版本号各是各的）
- 结构化（`channel-verify` 原文）:
  - 5.3.3 / 5.3.4.1: `changelog pane  recipe changelog:org.krita:-:<6: 4 entries; newest 5.3.4: 18 items, headings []; first items ["Don't allow to record images that are to", "Fix recorder export when some frames are", "Disable long-press on canvas widgets (Bu"]`
  - 6.0.3 / 6.0.4.1: `changelog pane  recipe changelog:org.krita:-:6+: 4 entries; newest 6.0.4: 18 items, headings []; first items […同上]`
- 生产解析器（`ChangelogExtractor`，Python 同正则回放 2026-10-16 feed）: 5.x 7 篇发布文中 4 篇有条目（5.3.4 18、5.3.3 33、5.3.2 31、5.3.1 8）；
  5.3.0（「What's New」是段落）、5.3.2.1（热修复只有下载）、5.2.16（改动写在段落里）0 条，被丢掉。没有分类标题（发布文本身只有一个「Changelog」标题）
- 跟随 channel: 是（两条线各一条 recipe）
- Recipe 状态: ✓

## 一键安装
- 状态: 支持（两条线都是 dmg，Team 闸）
- 端到端: 真机端到端：待主会话执行
- 格式: dmg（universal，只含 `krita.app`；无 SLA，挂载即见）。`download.kde.org` 302 到镜像
- 校验: 厂商只发 md5（版本目录的「Details」），`checksumFormat` 不支持，没接；完整性靠 Team 闸
- **读的是**: 人人可手动下载的 GA（下载页 / 发布文里的公开链接，无分桶）
- Team: 5.2.16 起到 5.3.4.1、6.0.3、6.0.4.1 全是 `DL93766A3G`；4.4.8 是 `5433B4KXM8`，4.x 拷贝一键会被 Team 闸拒（检测照常，需要手动更新一次）。
  换 Team 发生在 4.4.8 与 5.2.16 之间，具体哪一版没测
- 嵌套: `Contents/PlugIns/krita-preview.appex`、`krita-thumbnailer.appex`（Quick Look）和 `Contents/Library/Spotlight/kritaspotlight.mdimporter`，
  都是系统按需拉起，没有常驻 helper、LoginItems、LaunchAgent
- 6.x 的一键从 feed 取链接，热修复没有发布文时装的是基础版（6.0.3 → 6.0.4，不是 6.0.4.1；两者报的版本相同）
- 阻塞: 无

## 已知问题
- brew 装的拷贝在热修复版上会一直报有更新：cask 版本 `5.3.4.1`，包里 `5.3.4`；`VersionComparator.isNewer("5.3.4.1", than: "5.3.4")` = `true`（实测）。
  `HomebrewCaskSource` 直接拿 cask 版本比，这个结论读代码得出，没跑 brew 拷贝
- 夜构建（Plus / Next）被当成 stable，见「Channel 详情」
- 同一三段版本内的热修复不推（包里看不出来）

## 建议下一步
1. 让扫描读 `CFBundleLongVersionString`（仅对 `org.krita`）：既能把 `-prealpha` 判成 nightly，也能看见热修复的第四段。是 Swift 改动，不是 recipe 字段
2. brew 拷贝的热修复误报：要么 `HomebrewCaskSource` 对这类 cask 截到包里的段数，要么同上读长版本号
3. 年底 6 成为主版本、下载页换成 6.x 时复查两条 recipe 是否还要分开

## 如何复验

```sh
swift run --package-path application-test channel-verify <挂载后的 krita.app> --expect stable
```

2026-10-16 实测（包都从 `download.kde.org` 下载、只读挂载）:

| 包 | bundle id / 短版本 | detected | VendorProbe verdict | 下载地址 |
|---|---|---|---|---|
| `stable/krita/5.3.3/krita-5.3.3-signed.dmg` | `org.krita` / 5.3.3 | stable | `UPDATE 5.3.3 → 5.3.4` | `…/5.3.4.1/krita-5.3.4.1-signed.dmg` |
| `stable/krita/5.3.4.1/krita-5.3.4.1-signed.dmg` | `org.krita` / 5.3.4 | stable | `up to date` | 同上 |
| `stable/krita/6.0.3/krita-6.0.3-signed.dmg` | `org.krita` / 6.0.3 | stable | `UPDATE 6.0.3 → 6.0.4` | `…/6.0.4/krita-6.0.4-signed.dmg` |
| `stable/krita/6.0.4.1/krita-6.0.4.1-signed.dmg` | `org.krita` / 6.0.4 | stable | `up to date` | 同上 |
| Krita Plus `krita-5.3.5-prealpha-0ddbd23.dmg` | `org.krita` / 5.3.5 | stable | `up to date`（5.3.4 < 5.3.5） | — |

四个正式包的 `winning source` 都是 `Vendor`。

## 历史与实测

- 2026-10-16: `krita.org/en/download/` 只链 `5.3.4.1` 的 dmg；feed 20 篇，其中发布文 8 篇（含 Android-only 的 5.3.1.1，标题不是
  「Released!」，不收）；feed 里 6.x dmg 链接 6.0.0–6.0.4 与 6.0.2.1，最高 6.0.4。`stable/krita/` 目录只留 5.3.2.1 起的版本，
  更早的在 `Attic/`（feed 里 6.0.0 / 6.0.1 的链接指向已移走的目录，最高版本不受影响）
- 2026-10-16: 5.3.4.1 包 `CFBundleLongVersionString` `5.3.4.1`、短版本 `5.3.4`；6.0.4.1 包 `6.0.4.1` / `6.0.4`；5.2.16 `5.2.16`；
  4.4.8 `CFBundleVersion` 为空串
