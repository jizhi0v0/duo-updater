# magpie

> 审计日期 2026-10-06 · 模式 INVESTIGATE → 已接入 · 结论：**单轨，GitHub releases（`yetone/magpie-releases`）检测 + 一键 zip + changelog recipe**；macOS 上几条安装途径最后都是同一个 bundle

## 基本信息
- Bundle ID: `com.yetone.magpie`（`.app` 名是小写的 `magpie.app`）
- Team ID: `LY7MVTUDZG`（Developer ID Application，已公证；`spctl` accepted / Notarized Developer ID）
- 观测版本: 0.1.1084（`CFBundleShortVersionString` == `CFBundleVersion` == tag 去掉 `v`），`LSMinimumSystemVersion` 12.0，arm64 / amd64 各一个单架构包
- 自更新机制: 自研（Go，`internal/update`），读 `https://usemagpie.ai/api/latest`，没有 Sparkle、没有 `SUFeedURL`
- 开源：源码 `yetone/magpie`（MIT），签名构建发在 `yetone/magpie-releases`。下面「来自源码」的结论都出自 `main` 分支，2026-10-06 读取

## 安装途径（macOS）

| 途径 | 落地 | duo 能否管 |
|---|---|---|
| `curl -fsSL https://usemagpie.ai/install.sh \| sh` | 下 `magpie-darwin-<arch>.zip`（对照站点给的 SHA-256），`ditto` 解到 `/Applications/magpie.app`（`/Applications` 不可写时改放 `~/Applications`），再把 `~/.local/bin/magpie` 软链到包内 `Contents/MacOS/magpie` | 能。duo 原地换包，软链指向的路径不变，换完照样能用 |
| 官网下载 `magpie-darwin-<arch>.dmg` | dmg 里就是同一个 `magpie.app`（挂载 v0.1.1084 核对：同 bundle id、同版本、同 Team） | 能，同上 |
| 纯终端版 `magpie-cli-darwin-<arch>` | 裸二进制，没有 bundle | 不管。非 brew 的独立 CLI 二进制不在 duo 范围内 |
| `go install github.com/yetone/magpie@latest` | 从源码编出的裸二进制，版本是 `dev` / `git describe`，magpie 自己也不给它自更新（`update.Released`） | 不管 |
| Homebrew | 源码里有 `update.Homebrew`（看路径是否含 `/Cellar/magpie/`），但 2026-10-06 `brew info magpie` 报 "No available formula"、`brew search` 无 cask | 目前不存在 |
| Docker（`ghcr.io/yetone/magpie`） | 服务器上跑的 | 不适用 |

所以对 duo 来说只有一个对象：`magpie.app`，不管它是从 install.sh 还是 dmg 来的。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | ✓      | ○（`usemagpie.ai/api/latest`，没用） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHubReleasesSource**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.yetone.magpie` | — | — | — | ✓ |

只有一条轨（来自源码）：`update.Newer` 支持 `-pre` 后缀，但 release 列表最近 40 条 `prerelease` 全是 false、tag 全是 `v0.1.N`；app 里没有渠道开关。

## 更新检测
- 源: `GitHubReleaseRule`（`Recipes/com-yetone-magpie.swift`），`yetone/magpie-releases` 的 `/releases/latest`
- tag 形如 `v0.1.1084`，版本模式 `^v([0-9]+\.[0-9]+\.[0-9]+)$`（锚定，`-rc` 之类不会被读成正式版）
- 为什么不用 `usemagpie.ai/api/latest`：它和 GitHub 给的是同一批资产（URL 就指向 GitHub release），GitHub 这条路顺带带 release 正文和资产 digest，不需要另写 VendorProbe
- 注意事项:
  - **发版极频繁**：2026-10-06 一天内 v0.1.1075 → v0.1.1084 共 10 个版本。magpie 默认每 6 小时自查一次（Settings 里的间隔，来自源码 `internal/gui/update.go` 的注释），所以一台开着 magpie 的机器在 duo 眼里经常落后几个版本
  - 每个 release 都带 `magpie-darwin-arm64.zip` / `-amd64.zip`（最近 40 条无一缺失）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | 来自源码：`update.Stage` 只下整包 zip、校验 SHA-256 后 `ditto` 解开 | 2026-10-06 的 release 资产与 `/api/latest` 都只有整包 | — |

## Changelog
- 来源: `ChangelogRecipe`（`.gitHubReleases`），`https://api.github.com/repos/yetone/magpie-releases/releases?per_page=40`，`skipSections: ["Install"]`
- 跟随 channel: 不适用（单轨）
- Recipe 状态: 已有
- release 正文的形状：英文的 `## Features` / `## Bug Fixes` / `## Improvements`，然后 `### Install`（每个平台一行下载文件名），然后一行 `<!-- lang:zh -->`，下面是**整份中文翻译，标题仍是英文的** `## Features` 等。magpie 自己的更新器显示时取 marker 以上（`internal/update/notes.go` 的 `InLang`）并删掉 Install 一节（`StripInstall`）
- 不处理时，生产 `GitHubMarkdownParser` 对 v0.1.1084 解析出 21 条：8 条英文变更 + 5 条下载说明 + 8 条中文重复。处理：
  - `GitHubMarkdownParser.firstLanguage` 在整行 `<!-- lang:xx -->` 处截断（`parserGeneration` 8 → 9）。因为中文副本的标题与英文一模一样，`skipSections` 区分不了，只能按 marker 切
  - recipe 的 `skipSections: ["Install"]` 去掉下载说明
- 结果（2026-10-06，生产解码器跑最近 40 条真实 release）：40 条全部解析，0 条含中文、0 条含下载文件名；v0.1.1084 为 8 条、标题 Features / Bug Fixes / Improvements。只有一个小节的版本（如 v0.1.1082）按解析器的既有规则不显示标题
- 官网另有 `https://usemagpie.ai/api/notes?upto=&after=&lang=`（magpie 自己的「更新了什么」用它）。不带 `lang` 时它给的也是中英整份；带 `lang=zh` 时 v0.1.1084 只回了一节「安装」——没选它
- recipe 取不到时，面板退回 GitHub 规则带的内联说明：它也经过 `firstLanguage`，但不跳过 Install，会多出 5 条下载说明

## 一键安装
- 状态: 支持。app 不在运行时，0.1.1080 → 0.1.1084 在真机上跑通。app 在运行、且自己已暂存了更新时，按暂存的版本分两种（与 Sparkle 同一套规则，`UpdatePolicy.clearsStagedBuild`）：暂存的就是最新版 → duo 不装，交给 Relaunch；暂存的比最新旧 → 先清掉暂存（`MagpieStagingClearance`）再装。两种都在真机上跑通，见「如何复验」
- 格式: zip（`magpie-darwin-arm64.zip` / `magpie-darwin-amd64.zip`，按本机架构挑）。不用 dmg：zip 就是 magpie 自己的更新器和 install.sh 用的那份，内容是同一个 bundle
- **读的是**: 人人可手动下载的 GA。没有灰度参数；官网下载、install.sh、app 自更新读的都是同一个 latest release
- Team 闸：v0.1.983（amd64）、v0.1.1080、v0.1.1084（arm64）三个包都是 `LY7MVTUDZG`
- 阻塞: 无

## 已知问题
- **（已处理）app 自己暂存的更新会在退出时把 duo 装的包换掉（2026-10-06 真机复现，过程见「如何复验」）**。magpie 的更新器发现新版本后，把 zip 解到包旁边的 `.magpie-update/app/magpie.app`（`/Applications` 不可写时放进它的系统缓存），状态记在内存里；app 退出时 `OnShutdown` 调 `updates.install(false)`，把当前包改名为 `.magpie-update/app/old.app`、把暂存的那份移进来、再删掉整个 `.magpie-update`（`internal/gui/app.go`、`internal/update/update.go` 的 `Install`）。这一步不比较版本，「已被别人换过」的判断（`replaced()`）只对非 bundle 的二进制生效。所以：magpie 在运行且已暂存 v0.1.N 时，duo 换上更新的 v0.1.M，然后为 Relaunch 退出 magpie → magpie 把 v0.1.N 换回来，duo 装的那份被当作 `old.app` 删掉，duo 随后又显示有更新。发版频率越高（一天十个），暂存的那份比 latest 旧的可能性越大。这与 `docs/engine-notes/self-updater-stash.md` 记录的 Squirrel / Sparkle 暂存冲突是同一类，只是暂存位置和触发方式不同。现在由 `SelfUpdaterStaging.magpieStaged` 识别（暂存目录里有 `app/magpie.app`、没有未完成的 zip、且 magpie 正在运行），暂存旧于最新时由 `MagpieStagingClearance` 把 `.magpie-update` 整个改名移开再删掉；magpie 退出时自己的换包在第一步 rename 就失败（`no such file or directory`），磁盘上保持 duo 装的版本
- 不在运行时换包不受影响：暂存状态只在 magpie 进程的内存里，新进程启动时不会去用旧的 `.magpie-update`，`Stage` 每次开始前会先删掉这个目录（来自源码）。真机上不运行时的一键结果正常（见「如何复验」）
- 只认 `/Applications` 可写时、暂存在包旁边的那种。不可写时 magpie 暂存在它的系统缓存里、退出时要管理员密码才换，这种布局没读（未验证）
- 暂存检测要求 magpie 在运行（判断依据是有进程的可执行文件在这个包里）。duo 换包之后，运行中的旧进程的可执行路径会跟着旧包移走，所以换包后到重启前，`duo check` 不再看得到这份暂存。这不影响结果：清理发生在换包之前

## 建议下一步
1. 菜单栏 app 的一键 + Relaunch 在这两种情况下没单独跑过；按代码它和 CLI 走同一个 `UpdatePolicy` 与 `StagedBuildClearance`（未验证）

## 如何复验

```bash
# 资产与 tag
gh api repos/yetone/magpie-releases/releases/latest -q '.tag_name, [.assets[].name]'
# 真包身份（zip 与 dmg）
curl -fsSLO https://github.com/yetone/magpie-releases/releases/download/v0.1.1084/magpie-darwin-arm64.zip
ditto -x -k magpie-darwin-arm64.zip x
plutil -p x/magpie.app/Contents/Info.plist | grep -E 'Identifier"|Version|Minimum'
codesign -dvvv x/magpie.app 2>&1 | grep TeamIdentifier
spctl -a -vv x/magpie.app
# 生产检测链，对一个旧版真包（不需要安装）
curl -fsSLO https://github.com/yetone/magpie-releases/releases/download/v0.1.1080/magpie-darwin-arm64.zip
swift run --package-path application-test channel-verify <解开的 magpie.app>
# 解析器与规则
swift test --package-path DuoUpdaterCore --filter MagpieCoverageTests
```

一键，app 不在运行（`ditto` 一份 0.1.1080 到 `/Applications`，不启动）：

```bash
duo check magpie                   # magpie  0.1.1080  →  0.1.1084  [GitHub, in-place]
duo install magpie --yes --json
```

2026-10-06：`{"applied":true,"bytesDownloaded":16801343,"outcome":"installed","route":"vendor"}`，约 8.7 秒。换装后 short / build 都是 0.1.1084、inode 变了、`codesign --verify --deep --strict` 通过、Team 仍为 `LY7MVTUDZG`、`spctl` accepted / Notarized Developer ID；`diff -r` 与厂商 0.1.1084 zip 里的 `magpie.app` 完全一致；`duo backups` 留有 0.1.1080 的回滚点；之后 `duo check` 判为最新。

一键，app 在运行、已暂存一个比 latest 旧的版本：让运行中的 0.1.1080 去读一个本地 feed（magpie 自带的测试开关 `MAGPIE_UPDATE_FEED`），feed 写的是真实的 v0.1.1082 release（资产 URL 与 SHA-256 取自 GitHub，和 release 里的 `SHA256SUMS` 一致）。

```bash
MAGPIE_UPDATE_FEED=http://127.0.0.1:<port>/latest /Applications/magpie.app/Contents/MacOS/magpie &
# 等 /Applications/.magpie-update/app/magpie.app 出现（0.1.1082）
duo install magpie --yes --json
duo restart magpie
```

2026-10-06：启动约 12 秒后，`/Applications/.magpie-update/app/magpie.app` 出现，版本 0.1.1082。`duo install` 约 9 秒，`installed` / `applied`，磁盘上是 0.1.1084，magpie 进程没被动。`duo restart` 报 `magpie  restarted`、退出码 0，约 3 秒后磁盘上变成 **0.1.1082**（inode 与 duo 装的那份不同），`.magpie-update` 被清空，duo 装的 0.1.1084 没了。`duo check` 又显示 `0.1.1082 → 0.1.1084`。重启后的 magpie（这次读的是真 feed）随即自己又暂存了 0.1.1084，退出时换上。另外，这个暂存构建也会在普通的 SIGTERM 退出时换上：第一次试的时候直接 `kill -TERM`，磁盘从 0.1.1080 变成了 0.1.1082。

改动之后（同一天，`make cli` 之后的 duo）：

- **暂存的旧于最新**：同样让运行中的 0.1.1080 经本地 feed 暂存 0.1.1082，这时 latest 已是 0.1.1085。`duo install` 约 7 秒，`installed`，日志 `cleared magpie staging: magpie had 0.1.1082 staged`；`.magpie-update` 不见了，也没有留下改名后的目录。`duo restart` 之后磁盘仍是 0.1.1085（新进程），magpie 自己的日志是 `update: rename /Applications/magpie.app /Applications/.magpie-update/app/old.app: no such file or directory`。
- **暂存的就是最新**：0.1.1080 正常打开（读真 feed），约十几秒后暂存 0.1.1085。`duo install` 回 `skipped`：`its own updater already has 0.1.1085 staged — quit it to apply, or duo restart`，磁盘不动；`duo restart` 后磁盘是 0.1.1085，没有再下载，`codesign --verify --deep --strict` 通过，`duo check` 判为最新。`duo check` 那一行仍显示 `[GitHub, in-place]`，不显示 Relaunch。

2026-10-06 的身份与解析结果：
- zip 与 dmg 内的 bundle 都是 `com.yetone.magpie`、short 0.1.1084 / build 0.1.1084、`LSMinimumSystemVersion` 12.0、Team `LY7MVTUDZG`、Notarized Developer ID；arm64 包为单架构 arm64，amd64 包为单架构 x86_64
- `feed-discover` 对 v0.1.1080 真包：`no Sparkle and no electron-builder update config`
- `channel-verify` 对 v0.1.1080 真包：channel stable；winning source GitHub；latest 0.1.1084；download `…/v0.1.1084/magpie-darwin-arm64.zip`；changelog pane 走 recipe，40 条，最新 0.1.1084 为 8 条、标题 ["Features", "Bug Fixes", "Improvements"]；status `UPDATE → 0.1.1084`
- 变异：去掉 `parse` 里的 `firstLanguage` 调用，`notesAreTheEnglishChangesOnly` 与 `bothCutsAreLoadBearing` 变红；把 recipe 的 `skipSections` 清空，`notesAreTheEnglishChangesOnly` 变红；恢复后全绿
