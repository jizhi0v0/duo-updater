# Obelisk

## 基本信息
- Bundle ID: `com.obelisk.app`
- Team ID: 无（0.2.2 是 ad-hoc 签名：`flags=0x20002(adhoc,linker-signed)`，`TeamIdentifier=not set`）
- 观测版本: `0.2.2`（`CFBundleShortVersionString` == `CFBundleVersion` == tag 去掉 `v`）
- 自更新机制: 0.2.2 及以前**没有**（无 `SUFeedURL`、无 `app-update.yml`）；仓库 main 上已接
  Sparkle（`electron-sparkle-updater`）+ `electron-updater` 兜底，首个带它的版本尚未发布
- 分发: GitHub Releases（`tommy0103/obelisk`）。无 Homebrew cask（`brew search --cask obelisk`
  只命中无关的 `blisk`），无 MAS
- 开源: 是。以下渠道、版本方案、feed 形状均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ○（自动，待首个带 feed 的版本发布） | — | — | ✓（detection-only） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（0.2.2 副本）。带 `SUFeedURL`
的副本出现后，bundle 自己声明的 feed 由 `SparkleAppcastSource` 先应答，不需要 recipe。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.obelisk.app` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道。settled from source: `docs/adr/0015-desktop-sparkle-and-electron-updater.md` on `main`
（"The initial channel is stable"）与 `.github/workflows/release-app.yml`——`-rc` 之类带后缀的
tag 建成 GitHub prerelease，`/releases/latest` 不返回它，规则的锚定 pattern 也不收。Sparkle feed
地址走 `releases/latest/download/`，同样只指向非 prerelease 的 release。

## 更新检测
- 源: `tommy0103/obelisk` GitHub Releases，`/releases/latest`
- 版本方案: settled from source: `release-app.yml` 校验 tag == `v${app/package.json version}`；
  0.2.2 真包 short == build == `0.2.2`
- 仓库的每个 release 都是桌面 app：CLI 发布到 npm，不建 GitHub release（`cli.yml` 里没有发布步骤）
- 之后的 Sparkle 形状（settled from source: `app/scripts/update-release.mjs` 与 `release-app.yml`）:
  - `SUFeedURL` = `https://github.com/tommy0103/obelisk/releases/latest/download/appcast-<arch>.xml`，
    arm64 / x64 各一份，每份只有**一个** `<item>`，无 `<sparkle:channel>`（默认渠道）
  - `<sparkle:minimumSystemVersion>` 取自包的 `LSMinimumSystemVersion`；enclosure 是 zip，带 EdDSA
  - 同一 release 还有合并的 `latest-mac.yml`（electron-updater 兜底用）
  - 2026-10-02 两个 appcast 地址都是 404（latest 还是 v0.2.2，没有这些资产）；仓库已有 `v0.2.3`
    tag 但没有已发布的 release。该 tag 打在 2026-08-13 的 `chore(release): prepare Obelisk v0.2.3`
    上，那一版既没有 `release-app.yml` 也没有 `update-release.mjs`（按 `?ref=v0.2.3` 读都是 404），
    所以**首个带 feed 的版本不会是 0.2.3**；main 上 `app/package.json` 已是 `0.2.4`
- 注意事项: 无设备标识、无灰度；读的是公开 GA

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 0.2.2 无；之后的 Sparkle 2.9.4 有 BinaryDelta 能力 | 无 | 不适用 |
| 证据 | 0.2.2 bundle 只有 `Squirrel.framework`，无更新配置 | `update-release.mjs` 生成的 appcast 不写 `<sparkle:deltas>`（读源码） | — |

## 按 OS 分轨
- 0.2.2 真包 `LSMinimumSystemVersion` = `12.0`；GitHub release 无 OS 窗口字段
- 之后的 appcast 每条带 `sparkle:minimumSystemVersion`（无 max），`SparkleAppcastSource` 现读

## Changelog
- 来源: `ChangelogRecipe`，`api.github.com/repos/tommy0103/obelisk/releases?per_page=40`，
  `.gitHubReleases`
- 为什么要 recipe（不是靠 GitHub 源自带的那一条）: 之后的 appcast 把 release 正文（Markdown）
  原样写进不带 `sparkle:format` 的 `<description>`。按 `update-release.mjs` 的模板、用 v0.2.2 的
  正文生成一份 appcast，喂给生产的 `SparkleAppcastSource.structuredChangelog` → **nil**（解析不出
  条目），pane 只能把一大段原始文本当 HTML 画出来。recipe 比 `structuredChangelog` /
  `releaseNotesHTML` 优先，两个时代都走 GitHub 正文
- `skipSections: ["Downloads", "Included work"]`：0.2.0 起每篇末尾 `## Downloads` 是资产文件名，
  0.2.2 的 `## Included work` 是复述上文的 PR 编号
- 结构化（2026-10-02，生产 `StructuredChangelogDecoder.decode` + `channel-verify` 的 `changelog pane`
  行）: ✓ 4 个条目（0.2.2 / 0.2.1 / 0.2.0 / 0.1.0）全部分节；0.2.2 是 6 个小标题（Highlights、
  Session images、Local file references、Provider and indexing fixes、Runtime and reliability、
  Compatibility）、43 条。去掉 `skipSections` 时同一版是 8 个小标题、51 条（多出的正是 3 条
  Downloads + 5 条 Included work）
- 跟随 channel: 单渠道
- Recipe 状态: 已有

## 一键安装
- 状态: **仅检测**（GitHub 规则不设 `installAssetPattern`）
- 原因: 0.2.2 真包 ad-hoc 签名、无 Team ID，`codesign --verify --deep --strict` 失败（"code has no
  resources but signature indicates they must be present"），`spctl` 拒绝，无 stapled ticket。
  `SignatureVerifier.verifyTeamIdentifierMatch` 对无 Team ID 的已装副本直接抛
  `noTeamIdentifier(which: "installed")`，所以不论下载的包是什么，从这些副本一键都会被拒
- digest-only 路线（`installTrust: .publishedDigestOnly`，#952）也不行，和 MarkText 同类。2026-10-02
  对 0.2.2 真包直接调生产代码：gate 2 `verifyCodeSignature` 抛 `codeSignatureInvalid(-67056)`；
  `verifyDigestOnlyIdentity` 抛 `infoPlistIdentifierMismatch`（签名标识是 `Electron`，不是 bundle id）。
  何况上游发布 workflow 签的是 Developer ID，该路线对「ad-hoc 已装 → 下载带 Team ID」一律拒绝（`teamIdentifierAppeared`）
- **读的是**: 人人可手动下载的 GA（公开 release 资产）
- 之后: `release-app.yml` 要求 Developer ID 签名 + 公证（强制 `forceCodeSigning` / `notarize`，
  并 `grep TeamIdentifier=$APPLE_TEAM_ID`）。这样签出来的副本走 Sparkle 源 + 通用一键（代码签名闸
  + Team 闸）。**未验证**：还没有这样的包发布。ad-hoc 的 0.2.2 换成 Developer ID 版是 Team 变更，
  需要用户手动装一次（ADR-0015 也写明"Existing installations require one manual installation"）。只核对了 0.2.2 的签名，更早的版本没下包

## 已知问题
- 包的 Team ID、Sparkle feed 的实际内容、通用一键在首个带 feed 的版本上**都没验过**，只有源码依据

## 如何复验
```
# GET https://api.github.com/repos/tommy0103/obelisk/releases/latest → v0.2.2
# Obelisk-0.2.2-mac-arm64.dmg sha256 fb23f68c…43ee，与 release 资产的 digest 一致
# 挂载 → com.obelisk.app / 0.2.2 / 0.2.2，arm64，LSMinimumSystemVersion 12.0，无 SUFeedURL，
#        codesign adhoc / TeamIdentifier=not set，spctl rejected
swift run --package-path application-test feed-discover Obelisk-0.2.2-mac-arm64.dmg
#   → no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify Obelisk-0.2.2-mac-arm64.dmg --expect stable
#   → winning source GitHub, latest 0.2.2, status up to date,
#     changelog pane recipe 4 entries, newest 0.2.2: 43 items
# 同一 bundle 拷出后把 short/build 改成 0.2.1（只用于检测）:
swift run --package-path application-test channel-verify <copy>/Obelisk.app --expect stable
#   → winning source GitHub, status UPDATE → 0.2.2
```

## 建议下一步
1. 首个带 `SUFeedURL` 的版本发布后复验：真包 Team ID、`feed-discover` 应为 `declared`、
   appcast 两个架构各一条、通用一键从上一个 Developer ID 版本端到端
