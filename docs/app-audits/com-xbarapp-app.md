# xbar

## 基本信息
- App: xbar — 把任意脚本输出放进菜单栏（BitBar 的 2.x 重写），Go + Wails，MIT 开源
- Bundle ID: `com.xbarapp.app`（v2.0.40-beta 起；更早见「覆盖清单」）
- 仓库: `matryer/xbar`（默认分支 `main`，最后一次 push 2024-09-10）；官网 `https://xbarapp.com/`
- Team ID: `N3H5B92L5N`（Developer ID Application: Mat Ryer；v2.1.0-beta 起签名 + 公证）
- 观测版本: v2.1.7-beta（`CFBundleShortVersionString` 与 `CFBundleVersion` 都是 `v2.1.7-beta`，带 `v`）；观测日期: 2026-10-16
- 架构: universal（`lipo` = x86_64 arm64，v2.1.0-beta 起；v2.0.x 只有 x86_64）
- `LSMinimumSystemVersion` = `10.13.0`
- 自更新机制: 自研（`pkg/update`），读 GitHub `/releases/latest`，下载 zip 原地替换后重启；菜单里有「Update Automatically」开关
- 分发: GitHub Releases（每个 release 一个 dmg + 一个 zip；v2.1.4 及更早另有 `.tar.gz`）；Homebrew cask `xbar`
  （`2.1.7-beta`，非 `auto_updates`，下载地址就是 GitHub 的 dmg）；没有 MAS

## 覆盖清单（Coverage checklist）

| 副本组 | 处理 | 依据 |
|---|---|---|
| `com.xbarapp.app`，v2.1.0-beta 起（签名 `N3H5B92L5N`） | 规则覆盖，检测 + 一键 | 实测 v2.1.0 / v2.1.5 / v2.1.6 / v2.1.7 四个 dmg：id 与 Team 相同 |
| `com.xbarapp.app`，v2.0.40–v2.0.42-beta | 规则覆盖，**只检测**：一键被 Team 闸拒绝 | 实测 v2.0.40 / .41 / .42 的 bundle：`code object is not signed at all`，无 Team 可比 |
| v2.0.4–v2.0.39-beta | **不覆盖** | 实测 v2.0.5 / .10 / .16 / .24 / .33 / .34 / .37 / .39：`CFBundleIdentifier` 是 `xbar.v<版本>`，逐版不同、未签名。规则要一个固定 bundle id，无法匹配。它们自己的更新器也升不上来：v2.0.39-beta 的 `app/app.go` 读 `/releases/latest`、只取 `.tar.gz` 资产（`strings.HasSuffix(asset.Name, ".tar.gz")`），而 latest `v2.1.7-beta` 只有 `.dmg` / `.zip`（2026-10-16 `gh api` 实测），所以这些副本是**搁浅的缺口**。能补的路是 `BundleIDMigration` 逐 id 登记（v2.0.4.beta 到 v2.0.39-beta 共 32 个 release，`recipeBundleID` 不查 Team，可得检测；未签名，一键仍被 Team 闸拒）；但这张表按「有 Team 的改名」设计（`teamID` 必填），未签名的 32 个 id 进表要先定怎么填，暂不做 |
| BitBar（`com.matryer.BitBar`，同一仓库的 v1.x tag 与 `BitBar*.zip`） | **不覆盖**：另一个产品 | 实测 BitBar v1.9.2（Team `B3T8QSC4HG`）与 v1.10.1（无 Team）：bundle id、Team、app 名都和 xbar 不同；xbar 不是 BitBar 的原地更新（装成另一个 `xbar.app`）。BitBar 内置 Sparkle 指向 `https://bitbarapp.com/feeds/bitbar`，该域名 2026-10-16 已不解析（`dig` 无结果）。Homebrew `bitbar` cask 已于 2026-01-05 停用 |
| beta / nightly 等其他轨 | 不存在 | 见下「Channel 详情」 |
| 宿主下限 | 无限制 | `10.13.0` 低于 DuoUpdater 自己的下限 |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（cask 元数据，brew 安装的副本） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，dmg 副本）。triage 的 `feed-discover` 结论是 `—`（无 Sparkle、无
electron-builder 配置、无 MyGo feed）：xbar 的更新器在 Go 代码里直接调 GitHub API，bundle 里没有可声明的 feed。

## Channel 详情

只有一条轨，settled from source: `app/app.go` 与 `pkg/update/update.go` on `main`。

- `checkForUpdates` 把 `LatestReleaseGitHubEndpoint` 写死为 `https://api.github.com/repos/matryer/xbar/releases/latest`，
  没有任何设置切换端点或接收 pre-release。
- 所有 2.x release 的 tag 都是 `vX.Y.Z-beta`（首个写成 `v2.0.4.beta`），**都没有标 prerelease**，`/releases/latest`
  当前返回 `v2.1.7-beta`。`-beta` 是这条唯一轨道的名字，不是渠道。
- `app/package.sh` 用 `git describe --tags` 生成版本，`sed` 写进 `CFBundleShortVersionString`，所以安装副本读
  `v2.1.7-beta`。`ReleaseChannel.detect()` 对 `v2.1.6-beta` / `v2.1.7-beta` 都判 `stable`（channel-verify）。
- 仓库里标 prerelease 的只有 BitBar 时代的 `v2.0.0-betaN`、`v1.10.x` 等，属于另一个产品。

## 更新检测
- 源: `matryer/xbar` GitHub Releases，`/releases/latest`
- `versionPattern`: `^v?([0-9]+(?:\.[0-9]+)+(?:[-.]beta)?)$`，**保留 `-beta` 后缀**。默认 pattern 会把远端读成
  `2.1.7`，而 `VersionComparator` 让 `2.1.7` > `v2.1.7-beta`（数字段胜过文字段），永远显示假更新。
  保留后缀后 `2.1.7-beta` 与 `v2.1.7-beta` 相等（`v` 前缀被 tokenizer 去掉）。
- 读的范围: 所有 2.x tag（`v2.0.4.beta`、`v2.0.5-beta`…`v2.1.7-beta`）、将来不带后缀的 `v2.2.0` / `v3.0.0`；
  拒绝 `-rc.1`、`-beta.2`、`-betaN`。`v2.1.7` 若发布，会比 `v2.1.7-beta` 新，方向正确。
- 一个历史 release（v2.0.27-beta）的资产名是 `xbar.v2.0.27-beta-17-g014c4684.dmg`（`git describe` 带了提交数），
  安装副本的版本也会是这个串；它在 `/releases/latest` 之外，不影响检测。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `pkg/update/update.go`：只下载整 zip 解压替换 | release 资产只有 dmg / zip（/ tar.gz） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（运行中一轮实测，未见下载） | 不能 |
| 证据 | `downloadAndReplaceApp`：`os.CreateTemp("", "*-xbar.vX.zip")` 下到 `$TMPDIR` 随机名，下载完立即把旧 app 改名 `.previous`、解压替换、删旧 | — | 没有完成记录、随机文件名、下载即应用，`SelfUpdaterStash` 无布局可读 |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-16，channel-verify `changelog pane`）: `source structured: 1 entries; newest 2.1.7-beta: 4 items,
  headings []; first items ["Increased plugin timeout from 1 minute t", "Update readme to add /usr/bin/env exampl",
  "Fix links to the writing plugins guide a"]`
- `headings []`：正文只有 GitHub 自动生成的 `## What's Changed`（通用标题，按设计丢弃，不出现在条目里）和
  `## New Contributors`（丢弃），不是被压平。v2.1.6-beta 的正文只有一条无标题列表项
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（v2.1.0-beta 起的安装）**；v2.0.40–v2.0.42 只检测（未签名）
- 格式: dmg（`create-dmg` 生成，无 SLA；`spctl -a -t install` = `Notarized Developer ID`）。选 dmg 不选 zip：
  dmg 已 staple，且从 v2.0.x 起每个 release 都有 dmg
- Pattern: `^xbar\.v[0-9][0-9A-Za-z.-]*\.dmg$`, kind `.dmg`；不匹配 `.zip` / `.tar.gz`
- 嵌套: 无 LoginItems / Helpers / 嵌套 app。「Start at Login」走 Wails `mac.StartAtLogin`（登录项指向 app 路径，
  原地替换后路径不变）
- Team: v2.1.6-beta 与 v2.1.7-beta 都是 `N3H5B92L5N`，`codesign --verify --deep --strict` 通过（v2.1.7）
- 校验: 无。GitHub 对这两个 release 的资产不给 `digest`（2021 年上传，早于 GitHub 加 digest），只靠 Team 闸
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，与 app 自己的更新器、Homebrew cask 同一个 dmg）
- 真机端到端（2026-10-16，集成分支 `make cli`）：v2.1.6-beta → v2.1.7-beta，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 阻塞: 无（v2.0.40–v2.0.42 的副本需手动更新一次）

## 已知问题
- **与 xbar 自更新器的碰撞（2026-10-16 实测，无害）。** 设置在 `~/Library/Application Support/xbar/xbar.config.json` 的 `autoupdate`
  （默认没有这个文件，即关闭）；启动 10 s 后第一次检查（`app.go`：`time.Sleep(10 * time.Second)`）。写入 `{"autoupdate": true}`、启动 v2.1.6-beta、
  在第 9 s 起 `duo install`：16:38:54–57 装上 v2.1.7-beta（备份 v2.1.6-beta）。之后 2 分钟里 xbar 自己没有留下任何动作（无 `.previous`、`$TMPDIR` 无 zip、
  进程没换）；它是否真的跑了检查查不到（不写系统日志）。结束状态：包是 v2.1.7-beta、签名完好，运行中的进程映射的是被换走的旧二进制
  （`lsof` 路径为已不存在的 `/Applications/.duoupdater-staged-xbar.app/…`），`duo restart` 后新进程映射当前 inode
- 自更新器默认关闭时：v2.1.6-beta 运行中 `duo install --yes` → `installed.` + `Still running the old code`；`duo restart` 后跑新版，
  Team `N3H5B92L5N`、`codesign --strict` 0、Notarized；登录项前后无差异
- **上游停更。** 最后一个 release 是 2021-10-29 的 v2.1.7-beta，所以每台装最新版的副本都只会是 up to date。

## 建议下一步
1. （已做）不运行、运行中两轮都跑过，见已知问题。
2. 若上游发布不带 `-beta` 的 tag，复查 `/releases/latest` 是否指向它、pattern 读出的版本是否正确。

## 如何复验
```
swift run --package-path application-test channel-verify <xbar.v2.1.6-beta.dmg> --expect stable   # → stable，winning source GitHub，UPDATE → 2.1.7-beta
swift run --package-path application-test channel-verify <xbar.v2.1.7-beta.dmg> --expect stable   # → stable，up to date
codesign -dvv <v2.1.6 / v2.1.7 xbar.app>          # → TeamIdentifier=N3H5B92L5N
spctl -a -vv -t install <xbar.v2.1.7-beta.dmg>    # → accepted, Notarized Developer ID
codesign -dvv <v2.0.42 xbar.app>                  # → code object is not signed at all
PlistBuddy -c 'Print :CFBundleIdentifier' <v2.0.39 xbar.app>/Contents/Info.plist   # → xbar.v2.0.39-beta
```
