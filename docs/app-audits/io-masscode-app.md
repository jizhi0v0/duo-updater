# massCode

## 基本信息
- App: massCode — 开源代码片段 / 笔记 / HTTP 客户端，Electron（`electron` ^34，`electron-builder` ^25）；AGPL-3.0
- Bundle ID: `io.masscode.app`（helper 是 `io.masscode.app.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: `massCodeIO/massCode`（原 `antonreshetov/massCode`）
- Team ID: `GCU493MNF8`（5.12.0、6.0.0、6.2.1、6.3.1 真包；都 `spctl` Notarized Developer ID）。2.0.0-beta.6 是 `NXRD82TAC2`，未公证
- 观测版本: 6.3.1（2026-10-15 发布）；上一版 6.2.1；观测日期: 2026-10-22
- 自更新机制: **electron-updater**（`provider: github`），在 Mac 上由 Squirrel.Mac 落地。`src/main/updates/index.ts`（v6.3.1）：`autoDownload = false`、`autoInstallOnAppQuit = true`；`update-available` 时若偏好 `updates.autoUpdate` 开着（默认 `true`，`src/main/store/module/preferences.ts`）且大版本相同，就 `downloadUpdate()`，退出时安装；新大版本或偏好关闭时只发通知，菜单里的「检查更新」点更新按钮打开 GitHub releases 页。每 3 小时查一次
- 分发: GitHub Releases；Homebrew cask `masscode`（`url` 指 arm64 dmg，无 `auto_updates`）。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | 现有通用 cask 源 | — | ✓ | — |
| **beta**     | —       | —        | —   | ✓（只检测，给最新稳定版）| — |

当前生效源（channel-verify 实测）: **GitHub**。

`ElectronManifestSource` 接不上：`app-update.yml` 是 `provider: github`，不给地址，按 `ElectronUpdateConfig.manifestURL` 的规则不允许拼。`feed-discover` 对 6.2.1 dmg 的结论是 `review electronProviderNeedsConstruction`（唯一候选是二进制里的 codemirror 文档链接，无关）。

## 覆盖清单
- **bundle id**：v4.0.0、v4.7.1、v5.0.0、v5.12.0、v6.3.1 的 `electron-builder.json`，以及 v2.0.0-beta.1、v3.12.1 的 `config/electron-builder.ts`，`appId` 都是 `io.masscode.app`；真包 2.0.0-beta.6、5.12.0、6.0.0、6.2.1、6.3.1 的 `CFBundleIdentifier` 一致。没有改名前的旧 id。v1.x 不在 GitHub releases 上（tag 从 `v2.0.0-beta.1` 开始），没读
- **Team**：6.0.0 / 6.2.1 / 6.3.1 / 5.12.0 都是 `GCU493MNF8`；2.0.0-beta.6 是 `NXRD82TAC2`。换 Team 发生在 2.x 和 5.12.0 之间（具体哪一版没逐个下包查）。换 Team 之前的副本，安装闸本来就会拒掉；再加上下面的一键门，它们也不会被提供一键
- **beta / 预发布**：
  - `v2.0.0-beta.1`…`beta.6`（2022-04，**没标 prerelease**），`v3.0.0-beta.1`、`v4.0.0-beta.2`、`v4.0.0.beta-1`（标了 prerelease）。版本模式 `^v([0-9]+(?:\.[0-9]+)+)$` 不收这些，所以 72 个 release tag 里读出 66 个（另有 `v4.7.0`、`v6.3.0` 两个 tag 没有 release，`v6.3.0` 比 `v6.3.1` 早 15 分钟打，`v6.3.1` 带了构建修复 #988）
  - 这些 beta 和正式版同一个 id。真包 2.0.0-beta.6、4.0.0-beta.2 的 `CFBundleShortVersionString` 带 `-beta.N`，`ReleaseChannel.detect` 第 4 步（`-beta.<N>`）把它读成 **beta**，stable rule 不服务它（加 beta rule 之前 channel-verify：`winning source <none>`、`status unknown (no source answered)`）
  - **✓（只检测）**：加了一条 `channel: .beta` 的 GitHub rule，同一个仓库、同样的 tag 模式、读 `/releases/latest`，不带 `installAssetPattern` / `installerKind` / `installedTagPrefix`。最后一个 beta 是 2025-07 的 4.0.0-beta.2，之后 5.x、6.x 只发正式版，所以 beta 副本看到的是最新稳定版（今天 6.3.1）。只检测的理由：非 stable 轨的安装要 channel proof，而能区分两条轨的只有已装副本的版本号；而且 beta 都是 4.x 及更早，`^[56]\.` 一键门本来也会挡（4.x 及更早的库 6.x 打不开）。真包结果见「历史与实测」
- **版本范围**：一键只给 5.x / 6.x 副本（下面的 `OneClickGate`）。4.x 及更早的副本保留检测、不给一键
- **主机下限**：DuoUpdater 只出 arm64（`App/project.yml`）。arm64 dmg 的 `LSMinimumSystemVersion` 是 11.0（5.12.0 / 6.x），不构成限制
- **同 id 下的其他产品**：没有。v3 的构建配置里有 `-sponsored` 产物名，6.x 的资产里没有；资产模式锚定 `-arm64\.dmg$`，不会选到

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.masscode.app` | 共享 | 默认 | `/releases/latest` | ✓ |
| beta（2022–2025 的旧 beta） | `io.masscode.app` | 共享 | 版本号 `-beta.N` | `.beta` rule 读 `/releases/latest` | ✓（只检测） |

## 更新检测
- 源: `massCodeIO/massCode` GitHub Releases，`/releases/latest`
- 版本: tag `v6.3.1` → `6.3.1`，等于 `CFBundleShortVersionString` 和 `CFBundleVersion`。锚定：`v7.0.0`、`v6.4` 能读，`v4.0.0-beta.2`、`v4.0.0.beta-1`、`v2.0.0-beta.6` 不读
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；app 自己的「检查更新」也把用户送到 releases 页）
- channel-verify（2026-10-22）:
  - 6.2.1 → `winning source GitHub`、`latest 6.3.1`、`status UPDATE → 6.3.1`
  - 6.3.1 → `status up to date`
  - 5.12.0 → `UPDATE → 6.3.1`（检测正常；一键由门挡住）
  - 4.0.0-beta.2 → `detected channel → beta`、`winning source GitHub`、`UPDATE → 6.3.1`、`download` 是 releases 页（加 beta rule 之后；之前 2.0.0-beta.6 是 `status unknown (no source answered)`）
- **供应链事件**（GHSA-347q-f3qv-xq9w，issue #978）：2026-10-11 有人用维护者泄露的 GitHub token 推了恶意提交、打 `v6.2.0` tag，由**正常的 release 工作流构建、签名、发布**，20:35–约 00:05 UTC 在 releases 上，也经 app 自己的自动更新下发。6.2.0 已撤下（tag 也删了），6.2.1 是从恢复后的代码重建的。这类发布签名和 Team 都是厂商自己的，我们的安装闸（bundle id + Team + 公证）挡不住；GitHub 资产 `digest` 也只证明下到的是发布的那份。这条 rule 读到的就是 app 自己更新器读的同一个 releases，所以暴露面和厂商自带更新器相同，不更大（自带更新器默认自动下载、退出即装；我们的一键要用户点）

## 按架构 / 按 OS 分轨
- 每版两套 Mac 资产：`massCode-<v>-arm64.dmg` / `-arm64-mac.zip` 是 arm64，不带架构后缀的 `massCode-<v>.dmg` / `-mac.zip` 是 x64（`package.json` 的 `build:mac` 是 `electron-builder --mac --x64 --arm64`，两次单架构构建，没有 universal）。arm64 dmg `lipo` = `arm64`（check-bundle `archs=arm64`）
- `latest-mac.yml` 列了全部四个文件，electron-updater 自己按架构挑 zip。没有 OS 范围字段

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 | 不能 |
| 证据 | 依赖 `electron-updater` ^6.8.9 | v6.3.1 资产有 `massCode-6.3.1-arm64-mac.zip.blockmap`（278789 字节）等 blockmap | `DeltaApplier` 只吃 Sparkle binary delta 和 MyGo；没有消费 blockmap 的机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有 blockmap 机制；全量 arm64 dmg 约 279 MB

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（同大版本、偏好默认开） | 真机（2026-10-22）：6.2.1 启动 57 s 后 `~/Library/Caches/masscode-updater/pending/` 有 `massCode-6.3.1-arm64-mac.zip`（269629632 B）+ `update-info.json`，`io.masscode.app.ShipIt` 已武装 | 同版本时 duo 让路给它（见一键安装），没走到读 zip 那一步 |
| 证据 | `src/main/updates/index.ts` v6.3.1 的 `downloadUpdate()`；`app-update.yml` `updaterCacheDirName: masscode-updater` | — | `SelfUpdaterStash` 的 `.electronUpdater(cacheDirectoryName:)` 布局读 `~/Library/Caches/<updaterCacheDirName>/pending/update-info.json` |

- 记录文件与字段: electron-updater 的 `pending/update-info.json`（下载完成后写，`sha512` base64，见 `SelfUpdaterStash` 注释）
- 容器: electron-updater 在 Mac 上只下 zip（`massCode-<v>-arm64-mac.zip`），包根是 `massCode.app`
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`；`SelfUpdaterStash` 的归属闸处理

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 6.2.1 起）: `source structured: 1 entries; newest 6.3.1: 16 items, headings ["Fixes", "What\'s Changed"]; first items ["Fixed Command Palette Recent and navigat", "Fixed records getting duplicate or reass", "Fixed files renamed outside the app losi"]`
- 生产解析器另跑了四个正文（临时测试，已删）：
  - 6.0.0: 27 items，headings `["AI Assistant", "Workflow Improvements", "What's Changed"]`
  - 6.1.0: 19 items，headings `["Workflow Improvements", "Fixes", "What's Changed"]`
  - 6.2.1: 4 items，headings `[]`（「Security Release」一节是纯段落，走 prose 兜底，4 段都在）
  - 6.3.1: 16 items，headings `["Fixes", "What's Changed"]`
- **纯段落的大节被丢掉。** 厂商把主要新功能写成「标题 + 段落」（6.3.1 的 `## Semantic Search`、`## MCP Editing and Organization`；6.0.0 的 `## MCP Integration`、`## Performance`、`## Upgrading to v6`），只要正文里还有列表，解析器就只留列表，这些节连标题一起不显示。6.0.0 的 `AI Assistant` 标题留下了，但下面只剩三条示例提问（原文的引号列表）。`Upgrading to v6`（升级前要迁移库）也因此不在面板里。这是通用解析器的取舍（与 Harp 同一类），没有改；分节标题本身保留、没有被压平
- 跟随 channel: —（beta rule 读的也是稳定版正文）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（5.x / 6.x 副本）**，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）
- 格式: dmg（`hdiutil imageinfo` `Format: UDZO`），根目录 `massCode.app` + `Applications` 软链。模式 `^massCode-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`，kind `.dmg`
- 嵌套: 只有 `Contents/Frameworks` 下四个 Electron helper（`LSUIElement`）和 `Squirrel.framework`；没有 `Contents/Library/LoginItems`、`Contents/Helpers`。`app.asar` 里没有 `setLoginItemSettings` / `openAtLogin` / `LaunchAgents`
- 签名: 6.0.0、6.2.1、6.3.1、5.12.0 都是 `GCU493MNF8`，Notarized Developer ID，`codesign --verify` 通过
- 校验: GitHub 资产 `digest`。6.3.1 `sha256:450c4aa8de921827e47419937dc05136155bc92bfc23a42d629d2971ae1ddec7`、6.2.1 `sha256:a8f2584adac3dcad446bfb1fc1fbde2b9b39dae388fb066776e09f6ba30063cd`，与下载文件的 `shasum -a 256` 相同。`latest-mac.yml` 的 `sha512` 不接（GitHub rule 已带 digest）
- **一键门**（`OneClickGate .installedVersion(pattern: "^[56]\.")`）：
  - v6.0.0 release notes「Upgrading to v6」：v6 只用 Markdown Vault，**去掉了 SQLite 支持和内置迁移**；v4 的 `massCode.db` 要先用 v5.12.0 迁移，v3 的 `db.json` 要先 v4.7.1 再 v5.12.0。4.x 及更早的副本直接换成 6.x，库打不开
  - v5.0.0 release notes：v5 起改成 Markdown Vault，「Upgrading from v4 triggers automatic data migration」，所以 5.x 副本的库就是 v6 能读的格式（v6 notes：「Existing Markdown Vault users can continue using their vault」）
  - 厂商自己的更新器（v5.12.0 和 v6.3.1 都一样）从不自动装新大版本，只通知。DuoUpdater 这边不会额外确认：`UpdateResult.isMajorUpgrade` 对 `GitHub` 源直接返回 false（`licenseNeutralSources`），所以 5.x → 6.x 是普通一键。放进门是按上面两份 release notes 判断 5.x 的库 v6 能读；这是推断，没在真机上用 5.x 的库验证过
  - 下个大版本（7.x）出来时 6.x 副本会被这个门挡住，直到读过 7.0 的 release notes 后把 7 加进模式。宁可挡住（少一次一键）也不放过可能读不了库的跨版本
- 上一版 Team: 6.2.1 与 6.3.1 相同，不存在换 Team 拒装
- **读的是**: 人人可手动下载的 GA
- 端到端:
  - 第一轮（不运行）: 6.2.1 → `duo check` `6.2.1 → 6.3.1 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 6.3.1、可执行文件 inode 变、`TeamIdentifier=GCU493MNF8`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 6.3.1 包相同
  - 第二轮（运行中）: 启动 6.2.1，它自己停放了 6.3.1（见上表）；`duo install --json` → `skipped`，`its own updater already has 6.3.1 staged — quit it to apply, or duo restart`；`duo restart massCode` → `quit — its own updater applied 6.3.1`（ShipIt 14:44:19 开始、14:44:20 装完），之后 10 s 磁盘一直是 6.3.1、签名有效
  - 「暂存了比 latest 旧的版本」那一种没造（要代理改写更新查询）；5.x → 6.x 和 4.x 被门拒都没真机跑

### 启动副作用（2026-10-22 真机核对的已注明）
- 数据目录：`~/Library/Application Support/massCode`（issue #978 给的路径；cask `zap` 写的是小写 `masscode`，以真机为准）、`~/.massCode`、默认 vault `~/massCode`（cask `zap` 的 `rmdir`）。真机：首启建了 `~/Library/Application Support/masscode`（小写，和 cask 一致）、`~/.massCode`、`~/massCode`，以及 `~/Library/{Caches,HTTPStorages}/io.masscode.app`、`io.masscode.app.ShipIt`、`masscode-updater`、偏好 plist；没看到选库对话框。启动前后 `~/.claude/skills`、`~/.agents/skills` 没变，也没有 `.runtime`
- 注册 `masscode://` URL scheme（`electron-builder.json` `protocols`，asar 里有 `setAsDefaultProtocolClient`）；不改其他默认 app
- 不写 `~/.claude` / `~/.agents`：asar 里出现的 `.claude/skills`、`.agents/skills`、`.cursor/mcp.json` 都是打包进来的 Vercel AI SDK 文档文字，不是代码路径。MCP 服务器默认关（v6.0.0 notes）
- 语义搜索模型（约 210 MB）只在用户运行「Turn on semantic search」时下载（v6.3.1 notes）
- 自更新器：默认会自动下载同大版本新版、**退出时由 Squirrel ShipIt 安装**。正在运行、已暂存旧版时，duo 换包后再退出 app，ShipIt 可能把暂存的那版装回去（自更新器碰撞），第二轮要专门看
- 不要装 6.2.0（已撤下）。真机前后可查 `~/Library/Application Support/massCode/.runtime` 不存在（issue #978 的感染标志）

### 推荐的两轮真机步骤
1. **不运行**: `ditto` 6.2.1 进 `/Applications`，不启动 → `duo check massCode`（期望 `6.2.1 → 6.3.1 [GitHub]`）→ `duo install massCode --yes --json` → 版本、inode、`codesign --verify --deep --strict`、`spctl -a -vv`、Team、`diff -r` 对厂商 6.3.1 bundle、`duo backups`
2. **运行中，自更新器暂存旧版**: 先记 `T0`。要让暂存的那份**比 6.3.1 旧**，可以装 6.0.0 启动，同时让它的更新检查看到 6.1.0（例如用 Surge 把 electron-updater 对 `github.com/massCodeIO/massCode/releases…` 的最新版查询改写到 v6.1.0；electron-updater GitHubProvider 具体请求哪条 URL 没核，先看 Surge 请求日志确认）。等 `~/Library/Caches/masscode-updater/pending/update-info.json` 出现、内容是 6.1.0 → 取消改写 → `duo install massCode --yes --json` → `duo restart massCode` → 之后约 10 s 轮询磁盘版本；再正常退出 app，确认 ShipIt 没把 6.1.0 装回去。最后 `find ~/Library/Caches ~/Library/"Application Support" -type f -size +8M -newermt "@$T0"` 记已停放整包第 2 栏。改写造不出来的话，退而求其次：装 6.2.1 启动、让它暂存 6.3.1，再 `duo install`，期望日志 `local stash hit`、`bytesDownloaded: 0`
3. 一键门（可选）：`ditto` 5.12.0 进去 → `duo check` 应显示 6.3.1、可一键（GitHub 源不走大版本确认）；4.x 副本 `duo install` 应被拒并给出门的 reason

## 已知问题
- changelog 面板丢掉纯段落的功能节，见 Changelog
- 供应链事件说明这个仓库的 release 曾被冒名发布并签名，见更新检测

## 如何复验
```
gh release view v6.3.1 -R massCodeIO/massCode --json assets -q '.assets[]|.name+" "+.digest'
.claude/skills/coverage-discovery/scripts/check-bundle.sh massCode-6.3.1-arm64.dmg     # → io.masscode.app, GCU493MNF8, Notarized
swift run --package-path application-test feed-discover massCode-6.2.1-arm64.dmg        # → electronProviderNeedsConstruction
swift run --package-path application-test channel-verify massCode-6.2.1-arm64.dmg --expect stable   # → GitHub, UPDATE → 6.3.1
swift run --package-path application-test channel-verify massCode-6.3.1-arm64.dmg --expect stable   # → up to date
swift run --package-path application-test channel-verify massCode-4.0.0-beta.2-arm64.dmg --expect beta   # → GitHub, UPDATE → 6.3.1, download 是 releases 页
```

## 历史与实测

### 2026-10-22 —— beta 副本加只检测的 `.beta` rule

- 加 rule 之前（同日接入时）: `massCode-2.0.0-beta.6-arm64.dmg` channel-verify `--expect beta` 是 `winning source <none>`、`status unknown (no source answered)`
- `gh api` 核对: 带 `beta` 的 release 只有 `v2.0.0-beta.1`…`beta.6`（2022-04，`prerelease: false`）、`v3.0.0-beta.1`（2022-08）、`v4.0.0.beta-1`（2025-07-03）、`v4.0.0-beta.2`（2025-07-04），后三个 `prerelease: true`；之后只有正式版，`/releases/latest` 是 `v6.3.1`
- 加 rule 之后，`massCode-4.0.0-beta.2-arm64.dmg`（158638834 字节，sha256 `48561ffb5f305bc8a609f46bf4aec2444bd1dbd879876d3a6ff8629fb4d8787f`，与 API `digest` 相同）:
  ```
  short version   4.0.0-beta.2
  detected channel  → beta
  ✓ detection matches --expect beta
  winning source  GitHub
  latest          6.3.1
  download        https://github.com/massCodeIO/massCode/releases
  status          UPDATE → 6.3.1
  ```
- 对照 `massCode-6.2.1-arm64.dmg` `--expect stable`，结果不变: `winning source GitHub`、`latest 6.3.1`、`download https://github.com/massCodeIO/massCode/releases/download/v6.3.1/massCode-6.3.1-arm64.dmg`、`UPDATE → 6.3.1`

## 建议下一步
1. 7.0 发布时读它的 release notes，决定是否把 7 加进一键门
