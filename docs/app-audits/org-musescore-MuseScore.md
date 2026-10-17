# MuseScore Studio 4

审计 2026-10-16。

## 基本信息
- App: MuseScore Studio（乐谱编辑，GPL-3.0 开源，Qt 应用），仓库 `musescore/MuseScore`
- Bundle ID（全部在真包上读到）:

  | 构建 | `.app` 名 | `CFBundleIdentifier` | short / build | Team | 架构 |
  |---|---|---|---|---|---|
  | 3.6.2 stable | `MuseScore 3.app` | `org.musescore.MuseScore` | `3.6.2.548020600` / 同 | 6EPAF2X3PR | x86_64 |
  | 4.0.0 stable | `MuseScore 4.app` | `org.musescore.MuseScore` | `4.0.0` / `223472200` | 6EPAF2X3PR | x86_64 |
  | 4.2.1 stable | `MuseScore 4.app` | `org.musescore.MuseScore` | `4.2.1` / `240230937` | 6EPAF2X3PR | x86_64 |
  | 4.7.4 stable（上一版） | `MuseScore 4.app` | `org.musescore.MuseScore` | `4.7.4` / `260706075` | 6EPAF2X3PR | x86_64 arm64 |
  | 4.7.5 stable（最新） | `MuseScore 4.app` | `org.musescore.MuseScore` | `4.7.5` / `260831071` | 6EPAF2X3PR | x86_64 arm64 |
  | 4.6.0 beta（GitHub prerelease，Testing 构建） | `MuseScore 4.6.0.252411647 Testing.app` | `org.musescore.MuseScore` | `4.6.0` / `252411647` | 6EPAF2X3PR | x86_64 arm64 |
  | 4.7 nightly（osuosl，2026-10-16） | `MuseScore 4.7.5.261016040 Nightly.app` | `org.musescore.MuseScore` | `4.7.5` / `261016040` | 6EPAF2X3PR | — |
  | main nightly（5.0 开发中） | `MuseScore 5.0.0.261016031 Nightly.app` | `org.musescore.MuseScoreStudio5Development` | `5.0.0` / `261016031` | 6EPAF2X3PR | — |

  所有 stable / beta 包 `spctl -a -t exec` = `accepted, source=Notarized Developer ID`；dmg 都没有 SLA
- 自更新机制: 自研（muse 框架 `update` 模块），**没有 Sparkle**（Info.plist 无 `SUFeedURL`）。读
  `src/app/configs/update.cfg` 里的 `updates.musescore.org/feed/latest.xml`（打开 `application/allowUpdateOnPreRelease`
  时读 `latest.test.xml`）。这些 feed 由 `.github/workflows/update_release_info.yml` 从 GitHub release 生成后推到 S3。
  2026-10-16 用 `MuseScore/4.7.5` 与 `Mozilla/5.0` 两个 UA 请求 `latest.xml` / `latest.test.xml` / `all.xml` 都是 nginx 404，
  app 真正的请求头没抓（未验证）。厂商另有 MuseHub 安装器负责更新，不在本 app 内
- 分发: GitHub Releases（每版一个 universal dmg，4.3.0 起名 `MuseScore-Studio-<x.y.z>.<build>.dmg`，之前
  `MuseScore-<x.y.z>.<build>.dmg`，4.0 是 `MuseScore-4.0.0.dmg`）；musescore.org 下载页指向 MuseHub；nightly 和
  testing 构建放在 `ftp.osuosl.org/pub/musescore-nightlies/macos/4x/{nightly,testing,stable}/`
- Homebrew: `musescore` cask → 4.7.5，下载地址就是 GitHub release 资产（sha256 相同），**`auto_updates: true`**，所以
  `HomebrewCaskSource` 让位；没有 `musescore@3` / `@nightly` / `@beta`（API 404）
- MAS: 无（iTunes 搜索没有 `org.musescore.*`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **4.x stable** | — | 让位（auto_updates） | — | ✓ 一键 | ✗（feed 404） |
| **4.x Testing（prerelease）** | — | — | — | 读成 stable，推最新 stable（见下） | — |
| **4.x Nightly** | — | — | — | 读成 nightly，没有规则，unknown | — |
| **3.x（同 bundle id）** | — | — | — | ⚠️ 被 4.x 规则命中（缺口） | — |
| **5.x**（`org.musescore.MuseScoreStudio5*`） | — | — | — | — 还没发布 | — |

当前生效源（channel-verify 实测）: **GitHub**。接入前 4.7.4 是 `status unknown (no source answered)`。

## Coverage checklist

| 一组副本 | 结论 | 依据 |
|---|---|---|
| 4.0–4.7 stable | ✓ GitHub 规则（检测 + 一键） | 4.0.0 / 4.2.1 / 4.7.4 → `UPDATE → 4.7.5`；4.7.5 → `up to date`（实测） |
| 3.x，同 id `org.musescore.MuseScore` | 只检测：提示 4.x，不给一键（`OneClickGate` `.installedVersion("^4\\.")`） | 3.6.2 真包 channel-verify `UPDATE → 4.7.5`；真机（2026-10-16，集成分支 `make cli`）`duo check` → `3.6.2.548020600 → 4.7.5 [GitHub]`，`duo install` → `detection only for this copy — MuseScore 4 installs beside MuseScore 3, not over it; download it from musescore.org`，`MuseScore 3.app` 原样 |
| 4.x Testing（GitHub prerelease） | 读成 stable，被推最新 stable；没有 beta 规则 | 4.6.0 beta 真包 `detected stable`、`UPDATE → 4.7.5`（实测） |
| 4.x Nightly | 读成 nightly，没有 nightly 规则，不推 | 4.7 nightly 真包 `detected nightly`、`unknown`（实测；`.app` 文件名里的 Nightly 一词） |
| 5.x | 另一个 bundle id，不在本规则内 | main nightly 真包 id = `org.musescore.MuseScoreStudio5Development`（实测）；main 的 `version.cmake` 写 `org.musescore.${MuseScoreStudio}${MAJOR}`（源码） |
| 旧 Team | 无变化 | 3.6.2 / 4.0.0 / 4.2.1 / 4.7.4 / 4.7.5 / beta / nightly 全是 6EPAF2X3PR（实测） |
| 宿主下限 | 不影响 | 4.7.x `LSMinimumSystemVersion` 10.15.4，低于我们的部署目标 |

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `org.musescore.MuseScore` | — | — | GitHub `/releases/latest` | ✓ |
| testing（alpha / beta / rc） | 共享 | `.app` 文件名 `… Testing.app`；版本是裸 `4.6.0` | 编译开关 `MUSESCORE_ALLOW_UPDATE_ON_PRERELEASE` 决定 `allowUpdateOnPreRelease` 默认值（源码） | ✗ 未接（见下） |
| nightly | 共享 | `.app` 文件名 `… Nightly.app` | osuosl 目录，不在 GitHub | ✗ 未接，读成 nightly 不推 |

Settled from source（`v4.7.5` tag）:
- `buildscripts/ci/macos/package.sh`: `APP_NAME` 按 `BUILD_MODE` 取 `MuseScore <major>`（stable）、`MuseScore <ver> Testing`、
  `MuseScore <ver> Nightly`、`MuseScore <ver> Development`；bundle id 不随模式变（`version.cmake` 里
  `MUSE_APP_GUI_IDENTIFIER = org.musescore.MuseScore`）。
- `src/framework/update/internal/updateconfiguration.cpp`: 偏好键 `application/allowUpdateOnPreRelease`，默认值由编译开关决定。
  存在哪个文件没查（没在运行中的 app 上读过）。

**为什么 testing 没接 beta 规则:** 版本是裸 `4.6.0`，对应的 tag 是 `v4.6.0-beta`，`installedTagPrefix` 那套按 tag 反查
（UTM 的做法）拿 `v4.6.0` 会查到正式版。`ReleaseChannel.detect` 不认 `Testing` 这个词，要认得加一条按 bundle id 的文件名规则
（DB Browser 的写法），是引擎改动，本次没做。现在最新 prerelease 是 2025-09 的 `v4.6.0-beta`，早于 stable 4.7.5，所以
testing 副本被推 stable 是往前走。

## 更新检测
- 源: `musescore/MuseScore` GitHub Releases，`/releases/latest`（排除 prerelease）
- 版本: `^v(4(?:\.[0-9]+)+)$`。读得到历史上全部 4.x 正式 tag，包括两段的 `v4.0`、`v4.5`；拒绝 `v4.0_rc`、`v4.6.0-beta`、
  `v4.2.0-beta.2`（这些也都标了 prerelease）
- **主版本钉在 4**（`GitHubNextMajorTests.majorIsTheProduct` 豁免）: 5.x 是另一个 bundle id（main nightly 实测），
  5.0 成为 `/releases/latest` 后，4.x 副本仍要拿到 4.x 的补丁版。届时版本模式拒 5.x tag、资产模式找不到 4.x dmg，
  源回落到 stable 列表找最新 4.x。5.0 发布时复查：如果正式版仍用 `org.musescore.MuseScore`，就放开

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有 Sparkle；muse update 模块下整包 | 每个 release 只有完整 dmg | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`（GitHub 规则自带）
- 结构化（2026-10-16，channel-verify `changelog pane`，4.7.4 包）: `source structured: 1 entries; newest 4.7.5: 3 items,
  headings []; first items ["This update adds some new fretboard diag", "To learn more, see the full announcement",
  "And don't forget to check out the [4.7 r"]`。唯一的标题 `### MuseScore Studio 4.7.5 is now available!` 是版本标题，没有被压成条目
- 补丁版的 body 都是几行摘要加 musescore.org 公告链接（4.7.1–4.7.5 是 399–650 字符）；大版本（4.7.0、4.6.0、4.5）有分节
- 只有最新一条（`release history 1 entries`）：从 4.6.x 升上来的人看不到 4.7.0 的分节说明。要看历史得另加
  `ChangelogRecipe(.gitHubReleases)`（Audacity 的写法），本次没加
- Recipe 状态: 不需要（可选增强见上）

## 一键安装
- 状态: **支持**（Team 闸 + GitHub `digest`）
- 格式: dmg，universal（4.7.x `lipo` = x86_64 arm64），公证；没有 SLA
- Pattern: `^MuseScore(?:-Studio)?-4\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\.dmg$`, kind `.dmg`；不匹配 nightly 资产
  （`MuseScore-Studio-Nightly-…`）
- 校验: 下载后 `shasum -a 256` 与 GitHub `digest` 一致：4.7.5 = `5a8cc269…de6473a`，4.7.4 = `e3596e27…b016fac`
- bundle 内容: 没有嵌套 `.app`、没有 `LSUIElement`、没有 LaunchAgents / LoginItems / XPC；`Contents/PlugIns` 里只有一个
  QuickLook 预览扩展（`com.apple.quicklook.preview`）和 Qt 插件目录。换 bundle 后系统重新登记扩展，没有常驻进程
- 上一版 Team: 4.7.4 = 6EPAF2X3PR，与 4.7.5 相同（实测），闸不会拒
- **读的是**: GitHub `/releases/latest` 的资产，与 Homebrew cask 下载的是同一个文件（sha256 相同）
- 真机端到端（2026-10-16，集成分支 `make cli`）：4.7.4 → 4.7.5（含 `verifyingSignature`；`duo` 里显示名是 MuseScore Studio），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 阻塞: 无（3.x 的问题见「已知问题」）

## 已知问题
- **MuseScore 3 副本：提示 4.x、不给一键（2026-10-16 已处理）**: 3.x 与 4.x 同 bundle id，厂商让它们以 `MuseScore 3.app` /
  `MuseScore 4.app` 并存（4 改了排版引擎，旧谱子在 4 里不保证一样，见 handbook「Upgrading from earlier versions」）。3.6.2 自己的两个更新源
  （`update.musescore.org/update_mac_stable.xml` → `4.0.0`，3.x Sparkle appcast → `4.0.1`，2026-10-16 curl）也提示 4.0，说装 4 不会删 3；
  3.x 不再发版（3.6.2 是最后一版，2021-02-08）。所以检测照旧推 4.7.5；一键由 recipe 的 `oneClickGates`（已装版本 `^4\.`）挡掉，
  `UpdatePolicy.canAutoInstall` 判 false，`InstallCoordinator.perform` 再拦，CLI 给出原因（见上表真机行）。
  手动拖 `MuseScore 4.app` 进 `/Applications` 时 Finder 只按文件名判断冲突，两者名字不同，不会提示覆盖
- Testing 构建读成 stable（见「Channel 详情」）
- 厂商 feed `updates.musescore.org/feed/*.xml` 对两个 UA 都 404，没有抓 app 的真实请求
- app 自己的 “Install update” 不会和一键互相覆盖：它把 dmg 下到 `~/Library/Application Support/MuseScore/MuseScore4/update/MuseScore-Studio-<ver>.dmg`，提示 “needs to close to complete the installation” → Close 后退出 app、挂载 dmg 打开拖拽窗口，不替换 bundle、不重启（运行中一轮实测）
- 首启 “Getting started” 向导和更新提示框开着时 app 拒绝退出（AppleScript `quit` 返回 -128），`duo restart` 报 `still running — likely a save prompt`，属于预期

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：4.7.4 运行中、自带更新提示框开着，`duo install --yes` → `installed.` 并提示 `Still running the old code: MuseScore Studio`；之后在旧进程里点 “Install update”：下载 4.7.5 dmg、退出、只挂载 dmg（见已知问题），bundle inode 不变、`codesign --strict` 0。4.7.5 启动后首启向导开着，`duo restart` 退不掉 app（见已知问题）。Team `6EPAF2X3PR`、Notarized。新增 `~/Library/{Application Scripts/…QuickLookPreviewExtension, Application Support/MuseScore, Caches/MuseScore, Containers/…QuickLookPreviewExtension, Preferences/org.musescore.MuseScore(4).plist}`、`~/Documents/MuseScore4`；登录项多了 3 条（“MuseScore 4” app、“MuseScore 4 - background tasks”、QuickLook 扩展），app 进废纸篓后下一次 `sfltool dumpbtm` 里都没了
2. 决定 3.x：给 GitHub 规则加已装版本窗口（`^4\.`），或者接受被推 4.x
3. 5.0 正式版出来后复查 bundle id，加 5.x 规则；如果没换 id，放开主版本
4. 可选：加 `ChangelogRecipe(.gitHubReleases)` 给历史说明

## 如何复验
2026-10-16。包从 GitHub release 资产下载（cask 指向的就是它），每个包放各自的空目录；`hdiutil attach -readonly -nobrowse`
挂载检查，不安装、不启动。

```
gh api "repos/musescore/MuseScore/releases?per_page=100" --jq '.[] | [.tag_name, .prerelease] | @tsv'
B=https://github.com/musescore/MuseScore/releases/download
curl -fLO $B/v4.7.4/MuseScore-Studio-4.7.4.260706075.dmg
curl -fLO $B/v4.7.5/MuseScore-Studio-4.7.5.260831071.dmg
swift run --package-path application-test channel-verify MuseScore-Studio-4.7.4.260706075.dmg --expect stable
swift run --package-path application-test channel-verify MuseScore-Studio-4.7.5.260831071.dmg --expect stable
```

channel-verify 摘录（2026-10-16）:

```
4.7.4   detected stable   winning source GitHub   latest 4.7.5   status UPDATE → 4.7.5
4.7.5   detected stable   winning source GitHub   latest 4.7.5   status up to date
4.2.1   detected stable   winning source GitHub   latest 4.7.5   status UPDATE → 4.7.5
4.0.0   detected stable   winning source GitHub   latest 4.7.5   status UPDATE → 4.7.5
4.6.0 beta (Testing)   detected stable   winning source GitHub   status UPDATE → 4.7.5
3.6.2   detected stable   winning source GitHub   status UPDATE → 4.7.5      ← 缺口
4.7 nightly   detected nightly   winning source <none>   status unknown
main nightly (…MuseScoreStudio5Development)   detected nightly   status unknown
```

| 包 | 大小 | SHA-256 |
|---|---|---|
| `MuseScore-Studio-4.7.5.260831071.dmg` | 207,816,651 | `5a8cc26994d3f346d3e7d88c6a1583959e990ee9346b00d7b1d3f9498de6473a`（= GitHub digest = cask） |
| `MuseScore-Studio-4.7.4.260706075.dmg` | 204,826,761 | `e3596e27da0806a3384cab67d52f8478ad21ed2bd6fc96d7cb874d840b016fac`（= GitHub digest） |
| `MuseScore-Studio-4.6.0.252411647.dmg`（beta） | 176,279,316 | `63896c66e486584bd6ea79f2bdd0fe44b84647eb51380911abbb311d99ac1d7d`（= GitHub digest） |
| `MuseScore-4.2.1.240230937.dmg` | 138,281,276 | `c694c8002472faca507386ae9a44d44a37d08581d769e0ecf13f55bf783afd0e`（GitHub 无 digest） |
| `MuseScore-4.0.0.dmg` | 177,731,630 | `f5649524565d0392051f6291dc925c4dfb08200fda1a71d73cb46fe203328e1c`（GitHub 无 digest） |
| `MuseScore-3.6.2.548020600.dmg` | 127,047,529 | `9477247e14d3ac3cda1b095b9d9e70d0ed6030f6d19ab9a0013206318e75ee5d`（GitHub 无 digest） |

## 审计记录
- 2026-10-16: 首版。GitHub 规则（检测 + 一键），主版本钉 4；3.x 同 id 记为缺口；testing / nightly 在真包上量过。
