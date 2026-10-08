# OpenChamber

审计 2026-10-08（重审；2026-08-17 那版只核对了一个真包的 bundle 身份，没在新旧两个包上跑生产检测，
没看 GitHub 上的 prerelease、没看 changelog 面板，也没跑一键）。

## 基本信息
- Bundle ID: `dev.openchamber.desktop`（stable 与 `v2-preview` 测试构建共用，见下）
- Team ID: `5J7WJGPA2Q` — Developer ID Application: Bohdan Tryapitsyn（2.1.0、2.1.1、2.0.0-preview.8
  三个真包相同，均 `Notarized Developer ID`）
- 观测版本: stable `2.1.1`（short = build = `2.1.1`）、上一版 `2.1.0`；测试构建 `2.0.0-preview.8`。
  `LSMinimumSystemVersion` 12.0；arm64 与 x64 分开发包（arm64 dmg `lipo -archs` = `arm64`）
- 自更新机制: electron-updater，`app-update.yml` 为 `provider: github`、`owner: openchamber`、
  `repo: openchamber`。源码里 `autoDownload = false`、`autoInstallOnAppQuit = false`、
  `allowPrerelease = false`（`packages/electron/main.mjs` 的 `setupAutoUpdater`；2.1.1 的 `app.asar`
  里同一段逐字存在）
- Homebrew: cask `openchamber`，`auto_updates: true`，版本 `2.1.1`，URL 就是 GitHub 的 arm64 dmg（2026-10-08）
- 开源: `openchamber/openchamber`（默认分支 `main`）。包里带 OpenCode CLI（`Contents/Resources/opencode-cli/`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | ✓ 一键 | — |
| **preview**（`v2-preview` 滚动构建） | — | — | — | ✗ 不跟（见下） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`GitHubReleasesSource`，规则在
`Recipes/dev-openchamber-desktop.swift`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `dev.openchamber.desktop` | 共享 | — | tag `vX.Y.Z`（规则 `^v([0-9]+(?:\.[0-9]+)+)$`） | ✓ |
| preview | `dev.openchamber.desktop` | 共享 | 只有版本串 `2.0.0-preview.8`；`ReleaseChannel.detect()` 不认这个形状，判为 stable | 无：tag `v2-preview` 不匹配规则 | 不跟，见下 |

**GitHub release 列表（2026-10-08，`gh api repos/openchamber/openchamber/releases`，最近 40 条）:**
只有一条 prerelease：`v2-preview`（2026-09-14 建，8 个资产）。正文原话是 OpenCode v2 上的测试构建，
"Not a release: files here are replaced on every build, and this build does not update itself to a
stable version"，当前构建 `2.0.0-preview.8`（分支 `opencode-v2-refactoring`）。其余 39 条都是
`vX.Y.Z` 正式版，2026-09-23 起是 2.x。

**这条轨是什么（settled from source + 真包）:**

- 不是应用内可切的渠道：`main` 上 `allowPrerelease` 写死 `false`，`updater-channel.mjs` 只在
  Windows arm64 返回 `latest-arm64`，其余平台不设 channel。源码里没有 beta/nightly 开关，
  preview 构建的 asar 里同一段也是 `allowPrerelease = false`。
- preview 包与 stable 同 bundle id、同 Team、同 `app-update.yml`（github provider）。
- **duo 对 preview 包的实测**：`channel-verify` → `detected channel → stable`，`winning source GitHub`，
  `status UPDATE → 2.1.1`。也就是 duo 会把 stable 2.1.1 推给 preview 用户。按 semver 2.1.1 > 2.0.0-preview.8，
  而且 v2 已在 2.0.0 正式发布，所以这次推送内容上不算错。
- preview 自己的更新器会不会也推 2.1.1：**推断会**，未验证。asar 里 electron-updater 的 GitHub
  provider 在 `allowPrerelease = false` 时读 `/releases/latest`（现在是 v2.1.1），版本比较也是 2.1.1 更大。
  正文那句「不会更新到 stable」写于 stable 还是 1.23.x 的时候，那时 stable 确实更旧。没启动 app 验证。
- 缺口（不只是这个 app）：`2.0.0-preview.8` 这种 `-<word>.<N>` 形状，`ReleaseChannel.detect()` 的版本尾
  词表（`nightly` / `snapshot` / `dev`，以及 `-beta.N`）不收 `preview`。见「建议下一步」。

## 更新检测
- 源: `GitHubReleasesSource`，`openchamber/openchamber`，tag 与 Info.plist 的 short / build 同构（`v2.1.1` ↔ `2.1.1`）
- `feed-discover`（2.1.1）: `review    electronProviderNeedsConstruction`（github provider 的 `app-update.yml`，
  不是可直接抓的 `*-mac.yml` 地址），所以由 GitHub 规则覆盖是对的
- 资产（v2.1.1，25 个）: mac 有 `OpenChamber-2.1.1-mac-{arm64,x64}.{dmg,zip}` 各带 `.blockmap`，另有
  `latest-mac.yml`、`latest-arm64.yml`、Windows / Linux / Android / VSIX / web tgz。规则的资产正则
  `^OpenChamber-[0-9.]+-mac-(?:arm64|x64)\.dmg$` 只吃 mac dmg，按本机架构选
- `latest-mac.yml`（v2.1.1）: 4 个文件（两架构 × zip/dmg），各带 `sha512`，`releaseDate '2026-10-05T00:05:41.256Z'`，
  **没有** `stagingPercentage`、没有系统版本字段
- 发版频率高：2026-09-23（v2.0.0）到 10-04（v2.1.1）共 7 个版本

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 的 blockmap 差分下载） | 有 blockmap | 不能 |
| 证据 | `main.mjs` 没设 `disableDifferentialDownload`，electron-updater 默认开差分 | v2.1.1 资产里每个 mac dmg / zip 都有 `.blockmap` | `DeltaApplier` 只吃 Sparkle binary delta；GitHub 路径整包下载 dmg |

- 格式: electron-builder blockmap（分块差分，不是补丁文件）
- 阻塞项: 没有可消费的现成机制；包 250–275 MB，整包下载可接受

**Phase 3⅞ 其余几行：**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 按设备灰度 | electron-updater 支持 `stagingPercentage` | 否：v2.1.1 / v2.1.0 的 `latest-mac.yml` 都没有 | 不需要 |
| 按架构 / 按 OS 分轨 | — | 按架构：arm64 / x64 两个 dmg；OS 下限 12.0 只在包里 | 规则按本机架构选资产 |
| 自更新器会不会和我们抢 | 弱：`autoDownload = false`、`autoInstallOnAppQuit = false`，要用户点才下载、装 | — | 第二轮未跑 |

## Changelog
- 来源: GitHub release 正文（Markdown）
- 结构化: `changelog pane  source structured: 1 entries; newest 2.1.1: 99 items, headings ["New", "Improvements", "Fixes", "SDK", "Misc"]; first items ["**GitLab:** connect gitlab.com or your o", "**References:** the composer has one pic", "Repositories: each repository has one id"]`
  （2.1.0 与 2.1.1 两个包同一行）
- 判断: 正文是 5 个 `###` 分节、99 个列表项，用生产解析器（`GitHubMarkdownParser.parse`，临时测试，已删）
  逐块看过：5 个 heading + 99 条 note，没有段落被丢。条目里的 `**…**` 原样保留，面板按 `syntax` 渲染内联
  标记（读 `WorkbenchWindowView.noteRow` 得出，没在 UI 里看）
- 只有 1 entry：面板只显示最新一版，跨多版升级时中间版本的说明不在面板里（`release history 1 entries`）
- 跟随 channel: 否（preview 正文是固定一段说明，不在规则范围内）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（GitHub 规则带 `installAssetPattern` + `installerKind: .dmg`）
- 端到端（2026-10-08，第一轮，不启动）: 2.1.0 → `duo check` `update 2.1.1`、`source GitHub`；`duo install /Applications/OpenChamber.app --yes --json` → `installed`、`route vendor`、`bytesDownloaded 263945458`（GitHub dmg），约 55 s。装后 2.1.1，strict 通过，`Notarized Developer ID`，Team `5J7WJGPA2Q`；与厂商 2.1.1 dmg 逐文件比 SHA-256，1400 个文件、14 个软链接全部相同
- 格式: dmg（arm64 263,945,458 B / x64 273,688,915 B，v2.1.1）
- 校验: GitHub 资产 `digest`。下载的 SHA-256 与 digest 相等：2.1.1 arm64 `b9851a84…c21a`、2.1.0 arm64
  `e16f04d0…cbf8`、preview arm64 `e99618cc…097b`。另有 `latest-mac.yml` 的 `sha512`，GitHub 路径用不到
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest` 指向的正式版；没有按设备分配）
- Team: 2.1.0、2.1.1、preview 同为 `5J7WJGPA2Q`，`codesign --verify --deep --strict` 均退出 0
- 嵌套: `check-bundle.sh` 只列出 4 个 Electron helper（`LSUIElement`）；没有 `Contents/Library`、
  `Contents/Helpers`、LoginItems。`Contents/Resources/opencode-cli/opencode` 是 sidecar，app 退出时
  `performConfirmedQuit` → `shutdownBackgroundServices` 结束它（源码），SIGTERM 也走同一条路
- 阻塞: 无已知。**注意（源码读出，未实测）**：macOS 上退出要确认——`before-quit` 在有已启用 / 运行中的
  定时任务或有活动 tunnel 时弹「Quit OpenChamber?」对话框，默认按钮是 Cancel。duo 对运行中的副本发退出时，
  如果碰上这种状态，app 不会退

## 已知问题
- preview 构建被判为 stable，duo 推 stable 2.1.1（实测）；当前内容上无害，形状上是渠道检测缺口
- 运行中且有定时任务 / tunnel 时，退出会被确认框拦下（源码，未实测），会影响一键第二轮
- 面板只有最新一版的说明

## 建议下一步
1. 一键第一轮已过（见「一键安装」）；第二轮（app 运行中）未跑。第二轮注意上面的退出确认框
2. `ReleaseChannel.detect()` 的版本尾词表考虑收 `preview`（带点号计数 `-preview.N`），先按该处注释的要求
   在 `verify/baseline.json` 全部版本与真包版本上回放，确认零误判再改。OpenChamber 当下改不改都一样（preview
   比 stable 旧），价值在下一个用同形状发 preview 的 app
3. 不需要 changelog recipe

## 如何复验

2026-10-08。包都从 GitHub release 资产下载（`curl -fL --retry 5 -C -`），各放一个空目录；dmg 只读挂载、
`ditto` 拷出 .app，不安装、不启动。

```bash
gh api "repos/openchamber/openchamber/releases?per_page=40" -q '.[] | [.tag_name, .prerelease, .published_at] | @tsv'
gh api repos/openchamber/openchamber/releases/tags/v2-preview -q '.body'
curl -fL -o OpenChamber-2.1.1-mac-arm64.dmg \
  https://github.com/openchamber/openchamber/releases/download/v2.1.1/OpenChamber-2.1.1-mac-arm64.dmg
curl -fL -o OpenChamber-2.1.0-mac-arm64.dmg \
  https://github.com/openchamber/openchamber/releases/download/v2.1.0/OpenChamber-2.1.0-mac-arm64.dmg
curl -fL -o OpenChamber-2.0.0-preview.8-mac-arm64.dmg \
  https://github.com/openchamber/openchamber/releases/download/v2-preview/OpenChamber-2.0.0-preview.8-mac-arm64.dmg
swift run --package-path application-test channel-verify <OpenChamber.app>   # 三个包各跑一次
swift run --package-path application-test feed-discover <OpenChamber.app>
.claude/skills/coverage-discovery/scripts/check-bundle.sh OpenChamber-2.1.1-mac-arm64.dmg
cat <OpenChamber.app>/Contents/Resources/app-update.yml
```

| 包 | short / build | Team | detected | winning | status | changelog pane |
|---|---|---|---|---|---|---|
| 2.1.0 arm64 | 2.1.0 / 2.1.0 | 5J7WJGPA2Q | stable | GitHub | **UPDATE → 2.1.1** | source structured: 1 entries; 99 items, 5 headings |
| 2.1.1 arm64 | 2.1.1 / 2.1.1 | 5J7WJGPA2Q | stable | GitHub | **up to date** | 同上 |
| 2.0.0-preview.8 arm64 | 2.0.0-preview.8 / 同 | 5J7WJGPA2Q | stable | GitHub | UPDATE → 2.1.1 | 同上 |

三个包 `codesign --verify --deep --strict` 退出 0，`spctl` `accepted`（`source=Notarized Developer ID`），
下载 SHA-256 与 GitHub 资产 digest 相等。`download` 一栏三个包都是
`https://github.com/openchamber/openchamber/releases/download/v2.1.1/OpenChamber-2.1.1-mac-arm64.dmg`。

**一键端到端预备（第一轮已用它跑通）:** 上一版用 `v2.1.0` 的 arm64 dmg（上表第一行），解包出的 `OpenChamber.app`
就是要 `ditto` 进 `/Applications` 的那个。预期 `duo check` 报 update 2.1.1，`duo install --yes --json`
走 `route vendor`（GitHub dmg），先比 digest `b9851a84…c21a` 再过 Team 闸。

## 重审更正（相对 2026-08-17 版）
- 原文「Homebrew ✗」：cask 是有的（`openchamber`），只是 `auto_updates: true`，`HomebrewCaskSource` 让位
- 原文只写 stable 一行：GitHub 上有 `v2-preview` prerelease，同 bundle id，duo 判为 stable 并推 stable（上文）
- 原文「GitHub release body 内联」：现在有面板实测行，结构化、分节保留
- 原文「一键 ✓」没有端到端证据；本次第一轮端到端已跑通（见「一键安装」）
- 「已验证版本」改为「观测版本」
