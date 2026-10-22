# Simple Comic

## 基本信息
- App: Simple Comic — 漫画压缩包（cbz/cbr/cb7/cbt、PDF、图片目录）阅读器，Dancing Tortoise 原作的社区维护版
- Bundle ID: `com.ToWatchList.SimpleComic`
- 仓库: `MaddTheSane/Simple-Comic`
- Team ID: `3D9SMH4RWM`（Developer ID Application: Nicholas Vance；1.9.8、1.9.9 两版相同，`spctl` Notarized Developer ID）
- 观测版本: 1.9.9（`CFBundleVersion` 360，2025-01-20 发布）；上一版 1.9.8（355）；观测日期: 2026-10-22
- 自更新机制: **无**。`feed-discover` 对 1.9.8: `no Sparkle, no electron-builder update config and no MyGo feed`；两版 Info.plist 无 `SUFeedURL`，`Contents/Frameworks` 只有 UniversalDetector / WebPMac / XADMaster / `libswift_Concurrency.dylib`；主二进制 `strings` 里 `sparkle|SUFeed|appcast|SMAppService|SMLoginItem|LaunchAgents|LSSetDefault|checkForUpdates` 0 条命中
- 分发: GitHub Releases（每版一个 zip）、Homebrew cask `simple-comic`（url 就是 GitHub 资产，无 `auto_updates`）、Mac App Store（id 1497435571，同 bundle id，seller「Nicholas Vance」，商店版本 1.9.9）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用 cask 源） | ✓（通用 MAS 源） | ✓ | — |

当前生效源（非商店副本，channel-verify 实测）: **GitHub**。商店副本由 MAS 源负责：`GitHubReleasesSource` 对 `isMASApp` 直接返回 nil（`guard !app.isMASApp`），`isMASApp` 来自 bundle 里的 `_MASReceipt`（`AppScanner`：`isMAS = !isTestFlight && (isiOSAppOnMac || hasReceipt)`）。GitHub zip 解开后没有 `_MASReceipt`（`find … -name _MASReceipt` 无结果），所以 GitHub/cask 副本走 GitHub 规则，商店副本不会被这条规则碰到。

## 覆盖清单
- **bundle id**：1.9.8、1.9.9 真包都是 `com.ToWatchList.SimpleComic`。更早的 release 没下真包；1.9.x 的 release 正文、tag 和分支名都是同一条产品线，没有改名的线索。商店版同 id，按上面的 `isMASApp` 闸分开。
- **其他轨**：没有。所有 release 都不是 prerelease，没有 beta/nightly 的 tag。tag 前缀 `App-Store-` 不是另一个产品或轨道：厂商按「跟商店同步发的那一版」命名每个 release，GitHub 资产本身是 Developer ID 公证包（见上）。
- **版本范围**：Team 在 1.9.8 → 1.9.9 没变。`LSMinimumSystemVersion` 1.9.8 是 10.14.6、1.9.9 是 11.5，都低于我们的宿主下限（`App/project.yml` macOS 15.0、arm64），不需要 OS 门控。
- **商店版 Team**：**未验证**。本次没有商店包可读（iTunes lookup 只给 seller 名，不给 Team ID）。推断：商店 seller 与 Developer ID 证书持有人都是「Nicholas Vance」，同一个个人开发者账号只有一个 Team ID，所以很可能也是 `3D9SMH4RWM`。这不影响一键：商店副本根本不进 GitHub 规则。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.ToWatchList.SimpleComic` | 与 MAS 共享 id | `_MASReceipt` | `isMASApp` 闸 | ✓ |

## 更新检测
- 源: `MaddTheSane/Simple-Comic` GitHub Releases，`/releases/latest`（2026-10-22 指向 `App-Store-1.9.9`）
- 版本: `^(?:App-Store-)?([0-9]+(?:\.[0-9]+)+)$`。10 个 release 的 tag 全部读得出：`App-Store-1.8.8`…`App-Store-1.9.9` 九个，加上没有前缀的 `1.9.1`。
  - 分诊的「有 tag 读不出：1.9.1」：`1.9.1` 是同一个产品——release 名「App Store 1.9.1」，`target_commitish` 是 `App-Store-1.9.1` 分支，资产 `Simple.Comic.app.zip`，`App-Store-1.9.2` 的 Full Changelog 从 `1.9.1...App-Store-1.9.2` 比起。所以前缀改为可选，而不是有意不收。仓库另有一个 tag `v1.8`，没有对应 release，规则只读 release，不受影响。
  - 锚定：`App-Store-2.0`、`App-Store-2.0.0`、`2.0.0` 读得出；`App-Store-2.0.0-beta`、`App-Store-2.0.0-rc.1`、`2.0.0b1` 不读（Python `re` 跑过同一个正则）。
- 资产: `^Simple\.Comic(?:\.app)?(?:\.[0-9]+(?:\.[0-9]+)+)?\.zip$`。历史资产名换过四种：`Simple.Comic.<v>.zip`（1.9.4/1.9.5/1.9.8/1.9.9）、`Simple.Comic.zip`（1.9.7）、`Simple.Comic.app.zip`（1.9.1/1.9.2/1.9.6）、`Simple.Comic.app.<v>.zip`（1.9.3），全部匹配；`Source code.zip`、`.dmg`、`.zip.sha256` 不匹配。
  - 分诊的「不少 release 没有 mac 资产」**不成立**：脚手架只认 `Simple.Comic.<v>.zip`，所以把 1.9.7/1.9.6/1.9.3/1.9.2 报成没有 macOS 包；实际上 10 个 release 里 9 个各有一个 zip，只有 `App-Store-1.8.8` 一个资产都没有。
  - `/releases/latest` 指向的 release 没有匹配资产时：引擎回落到 `/releases?per_page=20`、去掉 prerelease/draft 后往回走，最多跳过 `maxReleasesWithoutMacOSAsset` 个没资产的 release（`GitHubReleasesSource.resolve`）。按现在的资产 pattern，只有 1.8.8 会被跳过；下一版若再换资产名（第五种），会表现为停在旧版本并记 `no release carries an asset matching` 错误日志，而不是装错东西。
- 注意事项: 1.9.9 之后（2025-01）没有新 release。

## 按架构 / 按 OS 分轨
- 架构: universal（`x86_64 arm64`，两版相同），单一 zip。
- `LSMinimumSystemVersion`: 10.14.6（1.9.8）/ 11.5（1.9.9），低于宿主下限。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 无更新器（见基本信息） | 每个 release 只有一个整包 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | 无更新器、二进制无下载更新的代码线索 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify 从 1.9.8 起）: `source structured: 1 entries; newest 1.9.9: 3 items, headings []; first items ["fix: in the about box set the colors of ", "Prevent page index from wrapping", "If Simple App has a book on a spinning h"]`
- 生产解析器逐版跑过（临时测试调 `GitHubMarkdownParser.parse`，跑完已删）：
  - 1.9.9：3 条 PR 标题，`by @user in <url>` 后缀已去掉；`## New Contributors`、`**Full Changelog**` 当作样板跳过；开头那句「Also live in the Mac App Store」（列表前的段落）被丢掉。正文唯一的小标题是 GitHub 自动生成的 `## What's Changed`，没有被保留成分节，也没有被压平进条目——没有可保留的厂商分节。
  - 1.9.8：4 条，`- ` 列表的 3 条改动说明 + `* ` 的一条 PR 标题「App-Store-1.9.8 - Bump build version and build numbers」（厂商自己的版本号 PR，原样显示）。
  - 1.9.2–1.9.7 都有条目；`1.9.1`、`App-Store-1.8.8` 正文为空 → nil。
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（规则已接；真机端到端待主会话）**
- 格式: zip（`ditto` 解开后根目录就是 `Simple Comic.app`），kind `.zip`，universal
- 嵌套: `Contents/PlugIns/QuickComic Preview.appex`、`QuickComic Thumbnailer.appex`（Quick Look 扩展）和 `Contents/Library/QuickLook/QuickComic.qlgenerator`；没有 `LoginItems` / `Helpers` / LaunchAgent / XPC 服务，没有常驻进程
- 签名: 1.9.8、1.9.9 都是 `TeamIdentifier=3D9SMH4RWM`，`codesign --verify` exit 0，`spctl` Notarized Developer ID。Team 未换，旧副本的一键不会被 Team 闸拒
- 校验: 资产没有 GitHub `digest`（1.9.9 上传于 2025-01，早于 GitHub 2025-06 开始给资产算摘要），只靠 Team-ID 闸。本次下载的 sha256：1.9.8 `4346ad5fe036ce7f37831d9a7e1e4ee4a1cd3f2fae64b92ca9a0cd028f95d545`（14392463 字节），1.9.9 `34fa1777c0643d145b8e8ba90b6c6eeb096b21c3beb34728c9df97dad9a1f1ac`（14392270 字节），大小等于资产 `size`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，cask 也指向它）
- 端到端: **未跑**，由主会话真机验证。真机时注意：
  - 文档类型：Info.plist 对 cbz/cbr/cb7/cbt 声明 `LSHandlerRank = Default`（读自 1.9.9 Info.plist）。放进 `/Applications` 后 LaunchServices 登记它，若机器上没有别的漫画阅读器，这几类文件的默认打开方式会变成 Simple Comic；zip/rar/pdf/图片只是 `Alternate`，不会抢
  - Quick Look：两个 appex 会随 app 登记给 pluginkit，cbz/cbr 的预览和缩略图会由它接管（推断自 bundle 结构，未实测）
  - 没有登录项、LaunchAgent、root helper、自更新器；首启向导/模态框未知（没启动过）。二进制里没有 `~/.claude` / `~/.agents` 相关字符串（未专门取证，`strings` 只查了上面那组关键词）
- 阻塞: 无

## 已知问题
- 无

## 如何复验
```
gh api repos/MaddTheSane/Simple-Comic/releases --jq '.[]|[.tag_name,([.assets[].name]|join(","))]|@tsv'
curl -LO https://github.com/MaddTheSane/Simple-Comic/releases/download/App-Store-1.9.8/Simple.Comic.1.9.8.zip
.claude/skills/coverage-discovery/scripts/check-bundle.sh Simple.Comic.1.9.8.zip   # → 3D9SMH4RWM, Notarized Developer ID
ditto -x -k Simple.Comic.1.9.8.zip x1.9.8
swift run --package-path application-test feed-discover "x1.9.8/Simple Comic.app"  # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify "x1.9.8/Simple Comic.app" --expect stable  # → GitHub, UPDATE → 1.9.9
swift run --package-path application-test channel-verify "x1.9.9/Simple Comic.app" --expect stable  # → up to date
```

## 建议下一步
1. 主会话真机两轮（不运行 / 运行中）跑一键 1.9.8 → 1.9.9，结果写进上面「端到端」和 README 那一行。
2. 下一个 release 出来后核对资产名仍被 pattern 接住（这个仓库换过四次资产名）。
