# yomado

## 基本信息
- App: yomado（夜窗）— 给视觉 agent 开虚拟显示器的菜单栏 app（`LSUIElement`），Objective-C，MIT 开源
- Bundle ID: `dev.chekusu.yomado`
- 仓库: `chekusu/yomado`（默认分支 `main`）；官网 `https://yomado.app/` 只链到 GitHub 仓库，下载就是 GitHub Releases
- Team ID: `FKSR2JD63B`（CHEKUSU INC.，Developer ID + 公证，ticket 已 staple）——**从 v0.3.3 起**。
  v0.3.1、v0.3.2 是 ad-hoc 签名（`TeamIdentifier=not set`，`spctl` rejected，没有 ticket）
- 观测版本: 0.3.3（`CFBundleVersion` 9）；0.3.2（8）、0.3.1（7）；观测日期: 2026-10-13
- 自更新机制（0.3.5 及以前）: 只提醒，不下载。`app/UpdateChecker.m` 在用户点「检查更新…」时读
  `api.github.com/repos/chekusu/yomado/releases?per_page=100`（包括 prerelease），取最高 SemVer tag，
  弹窗只给 release 页链接；头文件注释写明 "never downloads/installs an update"
- 自更新机制（0.3.6 起）: 内嵌 Sparkle（`Contents/Frameworks/Sparkle.framework`），`SUFeedURL` =
  `https://raw.githubusercontent.com/chekusu/yomado/main/appcast.xml`，有 `SUPublicEDKey`；feed 的 enclosure 指向同一个 GitHub 资产
- 分发: 只有 GitHub Releases。没有 Homebrew cask（`brew search --cask yomado` 无结果），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓（0.3.6 起） | —        | —   | ✓      | —           |

当前生效源: 0.3.5 及以前的副本是 **GitHub**（没有 `SUFeedURL`）；0.3.6 起的副本是 **Sparkle**（自带 feed）。两者 channel-verify 实测见「历史与实测」2026-10-19。

## Channel 详情

只有一条轨，settled from source: `app/UpdateChecker.m` on `main`。

- **每个 release 都标了 prerelease**（v0.3.1–v0.3.3 三个全是），`/releases/latest` 返回 404。这不是 stable 之外的
  beta 轨：app 没有任何渠道开关，自带的检查器对所有 release 一视同仁取最高版本，注释写的理由是
  "includes experimental releases because yomado is currently experimental"。所以规则 `usePrereleases: true`
  读列表，channel 仍是 `.stable`（Cua Driver 同一形态的先例）
- 版本: tag `vX.Y.Z` 与 `Info.plist` 的 `CFBundleShortVersionString` 一致（三个真包核对过）。没有发布脚本盖章：
  `Info.plist` 是仓库里手写的，`build.sh` 原样拷贝；仓库也没有 `.github/workflows`，release 是手动发的
  （流程见仓库 `docs/distribution.md`）
- 检查器接受带 SemVer 预发布后缀的 tag（`v0.4.0-beta.1` 这类），但到 2026-10-13 一个都没有。规则的
  `^v([0-9]+\.[0-9]+\.[0-9]+)$` 有意不读这类 tag：出现时 duo 不会推它，装着它的副本比较结果为已是最新，不会被推回旧版

## 更新检测
- 源: `chekusu/yomado` GitHub Releases，列表接口（`usePrereleases`，`listPageSize` 默认 20）。页深下限
  （`GitHubListPageSizeTests`）: 2026-10-13 共 3 个 release，全部匹配，首个命中在第 0 行、间隔 0，下限 1
- 版本: `^v([0-9]+\.[0-9]+\.[0-9]+)$`，与 `CFBundleShortVersionString` 一致
- 实测（2026-10-13，channel-verify）: 0.3.1 → `UPDATE → 0.3.3`；0.3.2 → `UPDATE → 0.3.3`；0.3.3 → `up to date`

## 按架构 / 按 OS 分轨
- 每个 release 一个 app zip（0.3.5 及以前 `Yomado-v<ver>.zip`，0.3.6 起 `Yomado.zip`），`Yomado` 与 `YomadoWatchdog` 都只有 arm64（`lipo -archs`），release 正文写明
  不含 Intel。资产名不带架构标记，Intel 机器由安装时 gate 5（读主执行文件的 slice）拒绝；不需要
  `architectureRequirement`（那是给主执行文件仍是 universal 的情形）
- `LSMinimumSystemVersion` = `14.0`（三个版本相同）；release 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 检查器只读 release 列表、不下载（源码） | 三个 release 的资产只有 app zip、source zip、SHA256SUMS | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-13，channel-verify `changelog pane`，从 0.3.2 与 0.3.1 看都一样）:
  `source structured: 1 entries; newest 0.3.3: 4 items, headings []; first items ["Signed by **CHEKUSU INC.** with Develope",
  "**Apple notarization accepted**, with th", "Uses a transparent monochrome night-wind"]`
- `headings []` 不是被压平：厂商的正文本来就没有小标题，0.3.3 的改动就是这 4 条 bullet。正文里的段落（介绍、下载说明、
  「装新版前先保存工作」）不进条目
- ⚠️ v0.3.1、v0.3.2 的正文全是段落、没有 bullet，解析出 0 条，所以 pane 从 0.3.1 看也只有 0.3.3 一条。
  这些版本的说明只能点 release 页看
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（v0.3.3 及以后的副本）**；v0.3.1、v0.3.2 的副本只检测
- 格式: zip（`ditto -c -k --keepParent` 打包的已 staple app）。zip 里每个文件都带一个 `._*` AppleDouble 条目，
  `ArchiveExtractor` 用 `ditto -x -k` 解包时会把它们并回扩展属性（内容只有 `com.apple.provenance`），解出的 app
  `codesign --verify --deep --strict` 退 0、`spctl` 给 `Notarized Developer ID`、`stapler validate` 通过。
  用 `unzip` 解包则会把 `._*` 留成 bundle 里的文件，签名报 "a sealed resource is missing or invalid"——不是本链路
- 嵌套: `Contents/MacOS/YomadoWatchdog` 是普通可执行文件，不是嵌套 app、不是 LoginItem/LaunchAgent。app 用
  `NSTask` 按需拉起它并传入自己的 PID；父进程正常退出写 `end` 后它退出，父进程消失时它恢复物理屏后退出。不常驻
- Pattern: `^Yomado(?:-v[0-9]+\.[0-9]+\.[0-9]+)?\.zip$`, kind `.zip`（0.3.5 及以前叫 `Yomado-v<ver>.zip`，0.3.6 起叫 `Yomado.zip`）；不匹配 `Yomado-source-v*.zip` / `yomado-source-v*.zip`
  与 `yomado-v*-SHA256SUMS.txt`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 0.3.3 = `0902b848…fdd8c3ec`、0.3.2 = `7e64ba9e…a95bef48`、
  0.3.1 = `44655ddb…2f035b2c`，三个都与各自 `digest` 和 release 附带的 `SHA256SUMS.txt` 相同
- **读的是**: 人人可手动下载的版本（GitHub release 列表上最新的那个；厂商只有这一个下载入口，app 自己的检查器读的也是它）
- Team 闸: 0.3.1/0.3.2 是 ad-hoc 签名，`SignatureVerifier.verifyTeamIdentifierMatch` 读不到已装副本的 Team，
  拒绝（`noTeamIdentifier(installed)`），磁盘上的旧副本不动。这些副本要手动更新一次到 0.3.3。
  也不适合 `.publishedDigestOnly`：那条路只给两边都没有 Team 的 app，而 0.3.3 起有 Team
- 端到端（2026-10-13）: 0.3.2（ad-hoc）→ 0.3.3 的拒绝路径跑过。`duo check` 给出 0.3.2 → 0.3.3，`duo install`
  走到 `verifyingCodeSignature` 后失败，原因 `Could not read a Team Identifier from the installed app.`；旧副本
  仍是 0.3.2，主二进制 sha256 前后一致。没有启动 app。**接受路径未跑**：0.3.3 是第一个签名版，要等下一个签名
  release 才有「旧签名版 → 新版」可跑
- 阻塞: 0.3.1/0.3.2 的副本要手动更新一次

## 已知问题
- 运行中替换: duo 在 app 运行时也会换包，不会退出 app，运行中的进程留在旧代码上。退出时
  `applicationShouldTerminate` 会先把各虚拟屏里的窗口送回、关虚拟屏，有操作进行中时会取消退出——这是厂商要求
  「装新版前先保存工作、把窗口送回」的原因，release 正文写了。duo 不替用户退出，这一步仍是用户的
- 换包后、重启前，旧进程如果再拉起 watchdog，会从磁盘上的新 bundle 启动新版 `YomadoWatchdog`（路径取自
  `NSBundle.mainBundle.bundlePath`）。v0.3.1…v0.3.3 之间 `app/Watchdog.m` 没有改动，目前没有版本错配；未实测
- 从 ad-hoc 版换成签名版时，厂商说明可能要重新授予辅助功能权限。0.3.3 起签名身份不变就不再有这个问题

## 建议下一步
1. 下一个签名版发布后跑 0.3.3 → 新版的端到端（不运行；运行中 + `duo restart`），补进本文件
2. 厂商第一次发带后缀的 tag 或第一次发非 prerelease 的 release 时复查: 前者决定是否放宽 `versionPattern`，后者不影响
   本规则（列表接口两种都读）

## 如何复验
```
swift run --package-path application-test feed-discover <Yomado-v0.3.3.zip>   # → no Sparkle and no electron-builder update config
gh api repos/chekusu/yomado/releases/latest                                   # → 404（全是 prerelease）
ditto -x -k <Yomado-v0.3.2.zip> <dir>
swift run --package-path application-test channel-verify <dir>/Yomado.app --expect stable
#   → detected stable，winning source GitHub，latest 0.3.3，UPDATE → 0.3.3
#     download https://github.com/chekusu/yomado/releases/download/v0.3.3/Yomado-v0.3.3.zip
ditto -x -k <Yomado-v0.3.3.zip> <dir>
swift run --package-path application-test channel-verify <dir>/Yomado.app --expect stable   # → up to date
codesign -dvv <0.3.3 Yomado.app>    # → TeamIdentifier=FKSR2JD63B, flags=0x10000(runtime)
codesign -dvv <0.3.2 Yomado.app>    # → Signature=adhoc, TeamIdentifier=not set
spctl -a -vv -t exec <0.3.3 Yomado.app>   # → accepted, source=Notarized Developer ID
```

## 历史与实测

### Recipes/dev-chekusu-yomado.swift — app zip 改名为 `Yomado.zip`（2026-10-19 实测，#1430）

夜扫报 `installAssetMissing`：v0.3.7 没有匹配 `^Yomado-v…\.zip$` 的资产，规则停在 0.3.5。`gh api repos/chekusu/yomado/releases`：

- v0.3.7（2026-10-17）: `yomado-v0.3.7-SHA256SUMS.txt`、`Yomado.zip`；v0.3.6（2026-10-16）: `Yomado.zip`；v0.3.5: `Yomado-source-v0.3.5.zip`、`yomado-v0.3.5-SHA256SUMS.txt`、`Yomado-v0.3.5.zip`。
  三个都不再是 prerelease（`prerelease=false`），规则读列表接口，不受影响。
- 下载 v0.3.7 `Yomado.zip`（2,684,825 B），`shasum -a 256` = `e88406ae…3476f4b8`，与 SHA256SUMS 一致；`ditto -x -k` 解出 `Yomado.app`：
  `dev.chekusu.yomado` 0.3.7（build 13），`TeamIdentifier=FKSR2JD63B`，`spctl` accepted / Notarized Developer ID，主执行文件 arm64。
  `SUFeedURL` = `https://raw.githubusercontent.com/chekusu/yomado/main/appcast.xml`，`SUPublicEDKey` = `knahaNLE…ILgZI=`，带 `Sparkle.framework`。
  v0.3.6 的 `Yomado.zip` 同样有这个 `SUFeedURL`、同一 Team；v0.3.5 没有 `SUFeedURL`。
- appcast 只有一项：0.3.7（`sparkle:version` 13），enclosure = GitHub 上的 `v0.3.7/Yomado.zip`，`length` 2684825，带 `edSignature`。
- 修法：资产 pattern 改成 `^Yomado(?:-v[0-9]+\.[0-9]+\.[0-9]+)?\.zip$`（`Yomado-source-v0.3.5.zip`、SHA256SUMS 仍不匹配）。
- `channel-verify`（本分支构建）：0.3.5 副本 → winning source GitHub、latest 0.3.7、download `…/v0.3.7/Yomado.zip`、`UPDATE → 0.3.7`；
  0.3.7 副本 → winning source Sparkle、latest 0.3.7、`up to date`。一键安装（GitHub zip 路径）没有端到端跑。


### 2026-10-28 — #1489：verify-install 报 `identityChanged: Sparkle key none → knahaNLE…`

- 原因：0.3.6 起内嵌 Sparkle，下载包里第一次带 `SUPublicEDKey`；`verify/identities.json` 记录的
  是 0.3.5（无 key），所以每轮都报 `none → key`（到 10-26 已连续 31 轮）。这是采用 Sparkle，不是换 key。
- 核对：厂商仓库 `chekusu/yomado` main 分支 `Info.plist` 的 `SUPublicEDKey` 是
  `knahaNLEg7QIZhGkGZwA3Insu4D+B8SdZPzyPbILgZI=`，与扫描读到的一字不差；该 key 由厂商提交
  `525184d5`（2026-10-15，"Add signed in-app updates with guarded workspace restart"）引入。
- 处理：同 Lokii/OpenLogi（#1456），把这个 key 记进 `verify/identities.json` 的
  `github:chekusu/yomado:stable`，Team `FKSR2JD63B` 不变。
