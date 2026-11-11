# Shotcut

## 基本信息
- App: Shotcut — Qt/MLT 开源视频编辑器（`mltframework/shotcut`，GPL-3.0，仓库未归档）
- Bundle ID: `com.Meltytech.Shotcut`
- Team ID: `Y6RX44QG2G`（Developer ID Application: Meltytech, LLC）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 26.9.28（tag `v26.9.27`，资产 `shotcut-macos-26.9.28.dmg`，210616938 字节）；同 tag 的原包 26.9.27；上一个正式版 26.8.1；prerelease 26.10.30（tag `v26.10.30`）；2026-11-11
- 自更新机制: 只通知。`MainWindow` 读 `https://check.shotcut.org/version.json`（`{"version_number":26927,"version_string":"26.9.27","url":"https://shotcut.org/blog/new-release-26.9.27/"}`），版本更高时在状态栏放一个链接，点击 `onUpgradeTriggered` → `Util::openUrl(m_upgradeUrl)` 打开网页；不下载、不停放、不安装（读自 `src/mainwindow.cpp`，tag `v26.9.27` 与 `v26.10.30` 相同）。没有 Sparkle、没有 `SUFeedURL`
- 分发: GitHub Releases（每个 release 一个签名 dmg，多数还带 `shotcut-macos-unsigned-<v>.dmg`）；Homebrew cask `shotcut`（`26.9.28,26.9.27`，`auto_updates: true`，url 指向 `v26.9.27/shotcut-macos-26.9.28.dmg`）；没有 App Store 版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（auto_updates，brew 让位） | — | ✓ 一键 universal dmg | — |
| **beta**   | —       | —        | —   | ✓ 一键 universal dmg（按精确 tag 的 `prerelease` 位证出） | — |

当前生效源: **GitHub**（`channel-verify` 实测，见「如何复验」）

## 覆盖清单
- 真包（都读自 dmg，只读挂载）:
  - `shotcut-macos-26.9.28.dmg`（tag `v26.9.27` 的重打包）: `com.Meltytech.Shotcut`，Team Y6RX44QG2G，Notarized，`CFBundleShortVersionString` = `CFBundleVersion` = 26.9.28，universal（x86_64 arm64），`LSMinimumSystemVersion` 12.0.0
  - `shotcut-macos-26.9.27.dmg`（同 tag 原包）: 同 id、同 Team、Notarized，两个版本键都是 26.9.27
  - `shotcut-macos-26.8.1.dmg`（上一个正式版）: 同 id、同 Team、Notarized，26.8.1 / 26.8.1
  - `shotcut-macos-26.10.30.dmg`（prerelease）: 同 id、同 Team、Notarized，26.10.30 / 26.10.30
  - `shotcut-macos-250816.dmg`（v25.08.16，旧命名）: 同 id、同 Team、Notarized，**short 25.08，build 25.08.16**
  - `shotcut-macos-240428.dmg`（v24.04.28，列表里最老的正式版）: 同 id、同 Team、Notarized，**short 24.04，build 24.04.28**，`LSMinimumSystemVersion` 11.0.0
- Bundle id: 从 24.04 到 26.10 一直是 `com.Meltytech.Shotcut`，没有改名，也没有别的版本
- 其他轨: prerelease（GitHub 标 `prerelease: true`，网站叫 beta）与正式版同 tag 形状、同资产名、同 id，包里版本纯数字，没有本地标记
- 版本范围与 tag/包版本的关系（GitHub 最新 40 个 release）:
  - 25.08.16 及以前: 资产名 `YYMMDD`，包的 short 是 `YY.MM`、build 是 `YY.MM.DD`。这些副本读成 24.04 / 25.08 之类，低于任何新版，会被推最新版
  - 25.10 起: 资产名、tag、两个版本键一致（`v26.8.1` ↔ `shotcut-macos-26.8.1.dmg` ↔ 26.8.1），**除了重打包**
  - 重打包（旧 tag 下加一个新版本号的 dmg）: `v26.9.27` 加 26.9.28（正式版，就是现在的最新版）；`v26.6.1`（prerelease）加 26.5.29；`v26.1.16`（prerelease）加 26.1.30（随后另有正式 `v26.1.30`）；`v25.10.9`（prerelease）加 25.10.28；`v25.12.2`（prerelease）加 `-resigned`；`v25.03.13`、`v25.01.03`（prerelease，旧命名）各加一个更晚日期的包；`v24.09.13`（正式版）带的是 240919
  - 结论: tag 不能当作安装版本，资产名才是；rule 的报出版本读资产名（`assetVersionPattern`）
- 主机下限: dmg 是 universal，我们的 arm64 主机直接用；`LSMinimumSystemVersion` 12.0.0，低于我们的 macOS 15 下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.Meltytech.Shotcut` | — | `CFBundleShortVersionString` 纯数字 | `/releases/latest`（GitHub 排除 prerelease） | ✓ |
| beta    | 同 id | 共享 | 无本地信号；`installedTagPrefix: "v"` 查 `v<版本>` 的 `prerelease` 位 | `/releases` 最新一条（不分轨） | ✓ |

## 更新检测
- 源: `mltframework/shotcut` GitHub Releases：stable 读 `/releases/latest`，beta 读 `/releases` 列表
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读 `v26.9.27`、`v25.08.16`，不读带后缀的 tag
- `installAssetPattern` `^shotcut-macos-[0-9]+(?:\.[0-9]+)+\.dmg$`：同 release 的 `shotcut-macos-unsigned-*.dmg`、`-resigned`、旧 `YYMMDD` 名、Linux/Windows 包都不匹配。`v26.9.27` 下两个 dmg 都匹配，`installableAsset` 按整个文件名的版本取最高的 26.9.28
- `assetVersionPattern` `^shotcut-macos-([0-9]+(?:\.[0-9]+)+)\.dmg$`（本 PR 新增的 `GitHubReleaseRule` 字段）：报出的版本读自被选中的那个资产名，所以 `v26.9.27` 报 26.9.28。只改报出版本；选哪个 release、跳过无资产的 release、历史和 tag 查询仍按 tag。资产名读不出时退回 tag 版本
- 不读 `version.json`：它写的是 26.9.27（厂商自己的更新提示从没告诉 26.9.27 用户有 26.9.28），而且只有正式版
- 判定（真包 `channel-verify`，见「如何复验」）: 26.9.27 → 26.9.28；26.8.1 → 26.9.28；26.9.28 up to date

## 按架构 / 按 OS 分轨
- 每个 release 只有一个签名 dmg，universal；没有按架构或 OS 分的轨。`version.json` 不带系统范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 更新检查只读 `version.json` 并打开网页（`src/mainwindow.cpp`） | `version.json` 只有版本号和网页链接；release 资产只有整包 | 整包下载 dmg，用 GitHub `digest` 校验 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | — |
| 证据 | `onUpgradeTriggered` 只调 `Util::openUrl`，没有下载代码 | 没有 | 没有可拿的 |

## Changelog
- 来源: GitHub release 正文，由 GitHub rule 自己带出（`GitHubMarkdownParser`，面板「source structured」）。没有另加 `ChangelogRecipe`：那类配方按 tag 给条目编号（26.9.27），而这条 rule 报的是 26.9.28，两者对不上
- 结构: 正文是 `## What's Changed` 加一行指向网站的说明和 36 条 `- …`，结尾 `**Full Changelog**`。面板实测 1 条目、36 items、`headings []`：唯一的 `What's Changed` 标题不单独显示，条目带 `**粗体**` 的菜单/滤镜名。厂商在 GitHub 正文里本来就没有分节，这是能拿到的全部结构
- shotcut.org 的博客页（`/blog/new-release-26.9.27/`）分节更细（Security Notice / New Look / Audio Enhancements / Timeline Enhancements / Other Changes / Fixes），但每个版本一页、要从版本拼地址，也不提 26.9.28 重打包，而且是带配图和说明文字的文章；GitHub 正文是同一版本的完整条目列表，随 rule 的同一次请求到手，所以用 GitHub
- 跟随 channel: 各轨读自己那条 release 的正文；beta 副本拿到的是它被推的那个 release（下一个 prerelease 或其后的正式版）的正文

## 一键安装
- 状态: 支持（universal dmg，Team 闸 + GitHub digest）
- 资产: `https://github.com/mltframework/shotcut/releases/download/v26.9.27/shotcut-macos-26.9.28.dmg`，`sha256:0e4c95ad41f26d96c442642e03e0c107bf98abfceea78724e2b05aa704ef79c6`（与下载文件一致）
- 端到端: ✓ 第一轮（2026-11-11，本机，未运行）：/Applications 放同 tag 的原版 26.9.27，`duo check` 报 `26.9.27 → 26.9.28`，`duo install com.Meltytech.Shotcut --yes` → `verifyingSignature … verifyingCodeSignature … installed.`；结果 26.9.28、Team `Y6RX44QG2G`、`codesign --verify --deep --strict` 0、spctl Notarized Developer ID；之后 `duo check` 报 up to date（重打包的版本从资产名读出，实测）。运行中一轮未做。
- 端到端（beta）: ✓（2026-11-11，本机，未运行）：/Applications 放 prerelease 26.9.6（digest 一致），`duo check` 报 `26.9.6 → 26.10.30`（stable rule 只会给 26.9.28），
  `duo install com.Meltytech.Shotcut --yes` → `verifyingSignature … verifyingCodeSignature … installed.`；结果 26.10.30、Team `Y6RX44QG2G`、
  `codesign --verify --deep --strict` 0、spctl Notarized Developer ID；之后 `duo check` up to date
- 旧副本: 24.04 起所有正式版同 id、同 Team，一键闸都能放行

## 已知问题
- **prerelease 副本没有本地标记**：beta rule 用 `installedTagPrefix: "v"` 查副本版本对应的精确 tag，GitHub 标 prerelease 的归 beta，
  拿最新的 release（不分 prerelease / 正式版）。Shotcut 版本号是日期，之后的正式版一直比之前的 prerelease 高（26.9.6 → 26.9.27、
  26.7.16 → 26.8.1、26.6.1 → 26.6.25、26.4.6 → 26.4.30、26.2.16 → 26.2.26、26.1.16 → 26.1.30、25.12.2 → 25.12.30），所以 beta 副本
  会被推到下一个 prerelease 或其后的正式版，装上正式版后它的 tag 证出 stable，回到 stable rule
- 证不出的副本走 stable rule：重打包的版本没有自己的 tag（26.9.28 在 `v26.9.27` 下；prerelease `v26.6.1` 下的 26.5.29 同理），
  旧命名（short `25.08`）也拼不出 tag。方向安全：stable rule 只推更高的正式版
- 重打包若改到 prerelease 的 tag 下（像 `v26.6.1` 的 26.5.29），对 stable rule 没有影响：`/releases/latest` 不返回 prerelease
- 旧命名时代（≤ 25.08.16）的副本 short 只有 `YY.MM`，在面板里显示为 24.04 / 25.08，比较仍正确

## 如何复验
```bash
# 真包（只读挂载）
curl -L -o /tmp/sc.dmg https://github.com/mltframework/shotcut/releases/download/v26.9.27/shotcut-macos-26.9.28.dmg
hdiutil attach -readonly -nobrowse /tmp/sc.dmg
codesign -dv --verbose=4 /Volumes/Shotcut/Shotcut.app; spctl --assess --type execute -vv /Volumes/Shotcut/Shotcut.app
# 规则（真包，不安装）
swift run --package-path application-test channel-verify <dmg> --expect stable
```

实测（2026-11-11，本机）:

| 包 | short / build | 检测轨道 | 源 | latest | status |
|---|---|---|---|---|---|
| 26.9.27（tag `v26.9.27` 原包） | 26.9.27 / 26.9.27 | stable | GitHub | 26.9.28 | UPDATE → 26.9.28 |
| 26.9.28（同 tag 重打包，最新） | 26.9.28 / 26.9.28 | stable | GitHub | 26.9.28 | up to date |
| 26.8.1（上一个正式版） | 26.8.1 / 26.8.1 | stable | GitHub | 26.9.28 | UPDATE → 26.9.28 |
| 26.10.30（prerelease） | 26.10.30 / 26.10.30 | stable（本地）→ beta rule 作答 | GitHub | 26.10.30 | up to date |

前三个包的 `download` 都是 `https://github.com/mltframework/shotcut/releases/download/v26.9.27/shotcut-macos-26.9.28.dmg`；`changelog pane  source structured: 1 entries; newest 26.9.28: 36 items, headings []; first items ["Fixed security flaws in upgrade and Whis", "Fixed **Mask: Draw (Glaxnimate)** filter", "Fixed using **Size, Position & Rotate** "]`

## 建议下一步
- 运行中一轮（stable 与 beta）未做

## 历史与实测
- 2026-11-11 接入。scaffold 在 `v26.9.27` 停下（tag 里没有与包版本 26.9.28 相同的版本），rule 手写；为重打包新增 `GitHubReleaseRule.assetVersionPattern`
- 下载哈希与 GitHub `digest` 全部一致: 26.9.28 `0e4c95ad…79c6`、26.9.27 `629b056b…2548`、26.8.1 `7bab10bd…5657`、26.10.30 `efcb8836…e8aef7`、250816 `f81f839a…4c1`；240428 的资产没有 `digest`（2025-06 前上传），本地 sha256 `391f65ee…997d`
- 2026-11-11 接 beta rule。`channel-verify` 26.10.30 真包：latest 26.10.30、download `v26.10.30/shotcut-macos-26.10.30.dmg`、
  changelog 42 items（接之前 latest 26.9.28）；26.9.27 / 26.9.28 真包结果不变。最新 100 个 release 的 tag 全部符合规则，列表深度下限 1
