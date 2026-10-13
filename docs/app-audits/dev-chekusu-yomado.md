# yomado

## 基本信息
- App: yomado（夜窗）— 给视觉 agent 开虚拟显示器的菜单栏 app（`LSUIElement`），Objective-C，MIT 开源
- Bundle ID: `dev.chekusu.yomado`
- 仓库: `chekusu/yomado`（默认分支 `main`）；官网 `https://yomado.app/` 只链到 GitHub 仓库，下载就是 GitHub Releases
- Team ID: `FKSR2JD63B`（CHEKUSU INC.，Developer ID + 公证，ticket 已 staple）——**从 v0.3.3 起**。
  v0.3.1、v0.3.2 是 ad-hoc 签名（`TeamIdentifier=not set`，`spctl` rejected，没有 ticket）
- 观测版本: 0.3.3（`CFBundleVersion` 9）；0.3.2（8）、0.3.1（7）；观测日期: 2026-10-13
- 自更新机制: 只提醒，不下载。`app/UpdateChecker.m` 在用户点「检查更新…」时读
  `api.github.com/repos/chekusu/yomado/releases?per_page=100`（包括 prerelease），取最高 SemVer tag，
  弹窗只给 release 页链接；头文件注释写明 "never downloads/installs an update"
- 分发: 只有 GitHub Releases。没有 Homebrew cask（`brew search --cask yomado` 无结果），没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 给出 `no Sparkle and no electron-builder update config`。

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
- 每个 release 一个 `Yomado-v<ver>.zip`，`Yomado` 与 `YomadoWatchdog` 都只有 arm64（`lipo -archs`），release 正文写明
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
- Pattern: `^Yomado-v[0-9]+\.[0-9]+\.[0-9]+\.zip$`, kind `.zip`；不匹配 `Yomado-source-v*.zip` / `yomado-source-v*.zip`
  与 `yomado-v*-SHA256SUMS.txt`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 0.3.3 = `0902b848…fdd8c3ec`、0.3.2 = `7e64ba9e…a95bef48`、
  0.3.1 = `44655ddb…2f035b2c`，三个都与各自 `digest` 和 release 附带的 `SHA256SUMS.txt` 相同
- **读的是**: 人人可手动下载的版本（GitHub release 列表上最新的那个；厂商只有这一个下载入口，app 自己的检查器读的也是它）
- Team 闸: 0.3.1/0.3.2 是 ad-hoc 签名，`SignatureVerifier.verifyTeamIdentifierMatch` 读不到已装副本的 Team，
  拒绝（`noTeamIdentifier(installed)`），磁盘上的旧副本不动。这些副本要手动更新一次到 0.3.3。
  也不适合 `.publishedDigestOnly`：那条路只给两边都没有 Team 的 app，而 0.3.3 起有 Team
- 端到端: **未跑**（本次是并行审计，`duo install` 的串行实跑留给协调者）。可跑的路径: 0.3.2 → 0.3.3 应得到
  Team 闸拒绝；0.3.3 → 下一版要等下一个签名 release
- 阻塞: 0.3.1/0.3.2 的副本要手动更新一次

## 已知问题
- 运行中替换: duo 在 app 运行时也会换包，不会退出 app，运行中的进程留在旧代码上。退出时
  `applicationShouldTerminate` 会先把各虚拟屏里的窗口送回、关虚拟屏，有操作进行中时会取消退出——这是厂商要求
  「装新版前先保存工作、把窗口送回」的原因，release 正文写了。duo 不替用户退出，这一步仍是用户的
- 换包后、重启前，旧进程如果再拉起 watchdog，会从磁盘上的新 bundle 启动新版 `YomadoWatchdog`（路径取自
  `NSBundle.mainBundle.bundlePath`）。v0.3.1…v0.3.3 之间 `app/Watchdog.m` 没有改动，目前没有版本错配；未实测
- 从 ad-hoc 版换成签名版时，厂商说明可能要重新授予辅助功能权限。0.3.3 起签名身份不变就不再有这个问题

## 建议下一步
1. 协调者串行跑端到端: 0.3.2 → `duo install --yes` 应被 Team 闸拒绝且旧副本不动；下一个签名版发布后跑 0.3.3 → 新版
   （不运行；运行中 + `duo restart`），补进本文件
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
