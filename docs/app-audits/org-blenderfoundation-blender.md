# Blender

## 基本信息
- Bundle ID: `org.blenderfoundation.blender`（正式版、beta、RC、alpha 四种构建相同）
- Team ID: `68UA947AUU`（Stichting Blender Foundation；5.2.2 正式版、5.2.0 beta、5.2.1 RC、5.3.0 alpha 四个 arm64 dmg 均验于 2026-09-25）
- 观测版本: 5.2.2 / 5.2.0 / 5.2.1 / 5.3.0 —— `CFBundleShortVersionString` 与 `CFBundleVersion` 相同，**都不带周期**；`LSMinimumSystemVersion` 5.2.x 为 11.2、5.3.0 alpha 为 13.0；仅 arm64
- 自更新机制: 无（bundle 里没有 `SUFeedURL`、没有 Sparkle）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | — | ✓ | — | — | ✓ 下载页 |
| **alpha**    | — | — | — | — | ✓ builder |
| **beta**     | — | — | — | — | ✓ builder（周期外关闭） |
| **rc**       | — | — | — | — | ✓ builder（周期外关闭） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: brew 装的拷贝是 **Homebrew**；直接下载的拷贝是 **Vendor**（`channel-verify` 实测，见「如何复验」）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.blenderfoundation.blender` | 共享 | 主程序里没有周期字面量对 | 下载页 / Homebrew cask | ✓ |
| alpha   | 同上 | 共享 | 主程序：`" Alpha"`/`" a"` + 分支 `main` | builder JSON `risk_id: alpha` | ✓ |
| beta    | 同上 | 共享 | 主程序：`" Beta"`/`" b"` + 分支 `blender-vX.Y-release` | builder JSON `risk_id: beta` | ✓ |
| rc      | 同上 | 共享 | 主程序：`" Release Candidate"`/`" RC"` + 分支 `blender-vX.Y-release` | builder JSON `risk_id: candidate` | ✓ |

**检测信号只在主程序里**（`BlenderBuildInfo`）。Info.plist 四种构建一模一样（`CFBundleGetInfoString` 只有版本和日期），所以 `ReleaseChannel.detect` 的所有规则都会把它们读成 stable。源码（`source/blender/blenkernel/intern/blender.cc` 的 `blender_version_init()`）拿 `BLENDER_VERSION_CYCLE` 和字面量比，编译器折叠后只留下选中的那一对，紧挨着它格式化用的两个格式串。四个真实主程序里，`%d.%01d.%d%s%s\0%d.%01d.%d%s` 之前的字符串依次是：

    正式版 5.2.2   .crash.txt · " LTS"
    beta 5.2.0     .crash.txt · " Beta" · " b" · " LTS"
    RC 5.2.1       .crash.txt · " Release Candidate" · " RC" · " LTS"
    alpha 5.3.0    .crash.txt · " Alpha" · " a"

单独的 `" Alpha"` 四个构建里都有（别处用到的），所以只认「格式串前紧挨的一对」。`buildinfo.c` 的全局变量给出日期、UTC 时间、12 位 commit、分支；alpha 从 `main` 出，beta/RC/正式版都从 `blender-vX.Y-release` 出，所以分支只分得出 alpha。同周期但不在该轨分支上的构建（实验分支、PR 构建、本地编译）不给 commit，比较结果是「无法判断」，不会被提示换成 `main` 的最新构建。

所有 stable 线（最新版与各 LTS）共用一个 bundle id：4.5 LTS 的拷贝会被提示升到当前正式版（与 Homebrew `blender` cask 一致），4 → 5 由大版本门标出。

## 更新检测
- 源: `VendorProbeSource`（直接下载）、`HomebrewCaskSource`（brew 装的正式版）
- **stable** 端点: `https://www.blender.org/download/`，取 macOS 按钮的链接 `/download/release/Blender<major.minor>/blender-<version>-macos-arm64.dmg/`（页面上唯一的 macOS 链接，出现两处：页头按钮与平台菜单）。读的是：人人可手动下载的 GA。
- **alpha / beta / rc** 端点: `https://builder.blender.org/download/daily/?format=json&v=1`（约 80 KB，每个分支 × 平台 × 文件类型只列**最新一个**构建；更早的在 `/download/daily/archive/?format=json&v=1`，约 100 天，**不按时间排序**，也不含当前构建）。按 `{"url"` 切成条目，取 `risk_id` / 分支 / `darwin` / `arm64` / `dmg` 都对得上的条目里 `version` 最高的那个；`hash` 是 commit（`headBuildPattern`），`file_mtime` 是上传时间（`publishedAtPattern`）。读的是：该轨的最新构建，builder 页面上人人可下。
- **比较**: 同一轨所有构建的 `version` 都一样（每个 5.3 alpha 都是 5.3.0），只能按 commit 比。列表只给最新那个，所以用 `BuildLineage.head`：已装 commit 等于它就是最新，否则落后于它。`UpdateChecker.evaluate` 在上面加两道闸：已装的 marketing 版本更高时不提示（RC 轨可能同时列着 4.5 LTS 和 5.2 的 candidate，按版本取最高后仍可能低于已装的）；该构建的上传时间早于已装拷贝的构建时间时不提示（列表滞后于 builder 页面）。
- **周期外**: beta/RC 只在发布周期里存在几周。列表里还有正常形状的 alpha 条目、却没有该轨条目时，`trackClosedPattern` 判为「轨道关闭」，不算失败；列表形状变了则两者都不匹配，照常报 recipe 失败。
- `hostRequirement`: 全部仅 arm64。5.0 起 Blender 不再出 Intel dmg，builder 条目也只读 `darwin`/`arm64`。
- 注意事项:
  - Homebrew 的 livecheck 说下载页在 Cloudflare 后面、它抓不到，所以改读 `download.blender.org/release/`；那个目录是两级（每个 minor 一个子目录），单 URL 的 probe 跟不下去。2026-09-25 连续 5 次 GET 都是 200（`server: cloudflare`, `cf-cache-status: DYNAMIC`），被挑战时 probe 退回 unknown，不会误报。
  - 下载页上 Windows-arm 那栏的 checksum 链接指向 `blender-5.2.1.sha256`，而按钮已是 5.2.2——页面局部会滞后，所以不接 checksum，只靠 Team ID 签名闸。builder 发布的 `.sha256` 是 hex，`checksumPattern` 要 base64 SHA-512，同样不接。
  - builder 列表里有陈旧条目（2024 年的 `4.2.0` Windows alpha 还在），按版本取最高会压过它们。
  - 正式版的 `file_mtime` 会晚于构建时间很多（5.2.2 构建于 09-15，文件上传时间 09-25），所以上传时间只作防护，身份一律看 commit。
  - 读主程序的代价：约 350 MB 的主程序冷读约 270–290 ms（debug 构建，从挂载的 dmg 读），之后按 executable 的 size+mtime 缓存，0.3 ms。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | bundle 无 Sparkle / 自更新器 | 下载页与 builder 列表都只有完整 dmg | 无可消费的补丁 |

## Changelog
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有，`sourceTemplate` 按目标版本的 major.minor 取页：`https://developer.blender.org/docs/release_notes/{majorMinor}/`（有可提供的更新时取它的版本，否则取已装版本）。LTS 页（标题与 "was released on" 句都带 `LTS`、没有 Corrective Releases 小节）同样解析；开发中的 minor（"is currently in Alpha/Beta"）解析为零条，回落到嵌入网页。
- `duo verify` 的覆盖：模板 recipe 需要一个版本才能取页；有了 vendor probe 之后，版本可以取自 probe 的结果。

## 一键安装
- 状态: 支持（直接下载的拷贝，四条轨）；brew 装的走 Homebrew
- 格式: dmg，Blender.app 自包含（bundle 外无 helper / launch item），所以 `.dmg` 而不是 `.pkg`
- stable URL: 下载页的链接是感谢页不是文件；由同一个链接的两个捕获拼出 `https://download.blender.org/release/Blender{major.minor}/blender-{version}-macos-arm64.dmg`（HEAD 200，`application/octet-stream`，346286611 字节）
- alpha/beta/rc URL: 条目自己的 `url`，`https://cdn.builder.blender.org/download/daily/blender-<ver>-<alpha|beta|candidate>+<main|vNN>.<commit>-darwin.arm64-release.dmg`；channel proof 锚在文件名里的 `-alpha+main.` / `-beta+vNN.` / `-candidate+vNN.`，beta/RC 轨永远不会装到正式版。
- **读的是**: stable 是人人可手动下载的 GA；alpha/beta/rc 是 builder 页面上该轨的最新构建（人人可下，没有灰度）
- 阻塞: 无；尚未在一个旧版拷贝上真跑过一次一键安装（见「如何复验」）

## 已知问题
- dev-docs 没有「只列已发布版本」的索引（导航把开发中的 minor 排在最前），所以不走 `indexLinkPattern`，改走按 major.minor 的模板。开发中的 minor（alpha 用户的 5.3）解析为零条，回落到嵌入网页。
- beta 用户在 beta 结束后不会被提示去装 RC 或正式版：每条轨只读自己的构建，跨轨由用户自己决定（`ChannelArtifactProof` 的原则）。
- 周期检测依赖编译器把周期字面量对放在格式串前面。布局变了时，读不到那对就当正式版：预发布拷贝会落到 stable 轨，读成「无更新」而不是被提示降级。

## 建议下一步
1. 在一个旧版拷贝上真跑一次一键安装（stable 用下载页，alpha 用 builder）。
2. 下一个 beta 周期（5.3 按发布说明 2026-09-30 后进 beta）开始后，用 `duo verify --only blender` 看 beta 轨从「关闭」变成 ✓。

## 如何复验

    swift run --package-path application-test channel-verify <blender dmg> --expect <stable|alpha|beta|rc>
    duo verify --only blender

2026-09-25，四个真实 arm64 dmg，`channel-verify`（生产的 `BlenderBuildInfo` + `VendorProbeSource` + `UpdateChecker.check()`）：

    dmg                                   周期     分支                   commit        构建时间(UTC)         判定     结果
    blender-5.2.2-macos-arm64             release  blender-v5.2-release   d13f752e3b9c  2026-09-15 01:49:19  stable   下载页 5.2.2，up to date，winning source Vendor
    5.3.0-alpha+main.425ab43ad645         alpha    main                   425ab43ad645  2026-09-25 01:35:56  alpha    builder 头 425ab43ad645，up to date
    5.2.0-beta+v52.4481d59ccf4e           beta     blender-v5.2-release   4481d59ccf4e  2026-07-08 01:34:43  beta     beta 轨关闭（当天无 beta 条目）
    5.2.1-candidate+v52.5adcd79a574f      rc       blender-v5.2-release   5adcd79a574f  2026-08-24 01:31:02  rc       rc 轨关闭（当天无 candidate 条目）

同一天在只有 Info.plist + 按真实布局写的主程序字节的桩 bundle 上（打真实 builder 列表）：commit `3bcf2d172c1f`、构建于 09-24 → `UPDATE 5.3.0 (3bcf2d172c1f) → 5.3.0 (425ab43ad645)`，下载 builder CDN 的 dmg；另一个 commit、构建于头的上传时间之后 → up to date。`duo verify --only blender`：stable ✓、alpha ✓、beta 与 rc 为 `-`（"no current build on the … track"）、changelog ✓。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-blenderfoundation-blender.swift — ChangelogRecipe（钉在一个版本上的发布说明页）

转引自 recipe 注释，未复测。整段原文。括号里的 "(5.3 Alpha, 5.2 Beta)" 与 "the latest RELEASED minor" 迁移时都已不成立：5.2 LTS 已发布，`source` 仍钉在 5.1（见下面的更正）。代码里去掉了括号里的版本，并把 "version-pinned to the latest RELEASED minor; bump it when a new Blender ships" 改成 "version-pinned to a RELEASED minor"，另加一句警告：只把钉的版本改到 5.2 解析出 0 条、面板静默退回内嵌网页；recipe 改好之前，5.2 用户看到的是 5.1 的说明。原句没写日期，引入它们的提交是 `599e8dde`（2026-06-04）；其余原样，重新折行。

Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
clean per-version notes page (the blender.org/download marketing pages are
sprawling splash pages with no parseable block). Each page is an <h1>
"Blender 5.1 Release Notes", a <p>"Blender 5.1 was released on DATE."</p>,
then module-section <ul>s and Compatibility/Bugfixes lists up to the
"Corrective Releases" heading. We surface a COARSE summary (changed-module
list + compat/bugfix bullets). Requiring the literal "was released on" is a
GUARD: the dev-docs nav lists in-development versions first (5.3 Alpha,
5.2 Beta) whose intros read "is currently in Alpha/Beta" and so DON'T
match — yielding zero entries (safe embed fallback) rather than a partial
changelog. URL is version-pinned to the latest RELEASED minor; bump it when
a new Blender ships (same as the old Warp/Ghostty version-pins) — Blender
exposes no released-only index to follow.

更正 2026-09-14（13:59–14:01 UTC，只读 GET，Safari UA，不跟随重定向）：`developer.blender.org/docs/release_notes/5.2/` 200，`<h1>` 是 "Blender 5.2 LTS Release Notes"，正文 "was released on July 14, 2026"；`/5.3/` 的 `<h1>` 是 "Blender 5.3 Release Notes"，正文 "Blender 5.3 is currently in"；`/docs/release_notes/` 的导航依次列 5.3、5.2 LTS、4.5 LTS、5.1、5.0。recipe 的 `source` 仍是 `/5.1/`（`Recipes/org-blenderfoundation-blender.swift:27`）。只把钉的版本改成 5.2 会得到 0 条，原因有三处，都是在 13:59 UTC 取回的 5.2 页上用本地 Python 按 recipe 的 `entryPattern` 复算的：(1) `<h1>` 是 "Blender 5.2 LTS Release Notes"，而 pattern 要求 `Blender\s+<version>\s+Release Notes`；(2) 引言是 `<p>Blender 5.2 LTS was released on July 14, 2026.`，而 pattern 要求 `Blender\s+[\d.]+\s+was released on`；(3) 页上没有 `id="corrective-releases"` 的 `<h2>`（5.1 那页有 1 个，5.2 那页 0 个；5.2 的 `<h2>` 只有 `compatibility` 与 `bugfixes`），而 body 的 lookahead 要求它。

### Recipes/org-blenderfoundation-blender.swift — ChangelogRecipe 从钉 `/5.1/` 改为 `{majorMinor}` 模板

2026-09-14，只读 GET，Safari UA。在上面「更正」之外补两处代码事实：版本窗口（`minimumAppVersion` / `belowAppVersion`）两个都没设，所以 `ChangelogRecipeSelection` 对任何版本都选中这条 recipe，5.2 用户看到 5.1 的说明时没有任何警告；`verify/baseline.json` 记着 `lastGoodVersion` 5.1，而 `Verify.sweepChangelog` 的 lag 检查要一个版本来比，Blender 没有 vendor/GitHub 源，版本只能来自扫描到的 Blender 拷贝，所以只在装了 Blender 的机器上才会触发。

逐页取回的结构（`<h1>` / 发布句 / `<h2 id>`）：

    5.1  "Blender 5.1 Release Notes"      "Blender 5.1 was released on March 17, 2026."       compatibility, bugfixes, corrective-releases
    5.2  "Blender 5.2 LTS Release Notes"  "Blender 5.2 LTS was released on July 14, 2026."    compatibility, bugfixes
    5.0  "Blender 5.0 Release Notes"      "Blender 5.0 was released on November 18, 2025."    compatibility, bugfixes, corrective-releases
    4.5  "Blender 4.5 LTS Release Notes"  "Blender 4.5 LTS was released on July 15, 2025."    compatibility, bugfixes
    4.2  "Blender 4.2 LTS Release Notes"  "Blender 4.2 LTS was released on July 16, 2024."    compatibility
    5.3  "Blender 5.3 Release Notes"      "Blender 5.3 is currently in Alpha until September 30, 2026."  compatibility

旧 `entryPattern` 在这些页上用 Python 复算：5.1、5.0 各 1 条，5.2、4.5、4.2、5.3 都是 0 条。上面「更正」列的三处原因缺一个都不行：前两处加上可选的 `LTS` 仍是 0 条，lookahead 再接受 `</article>` 才是 1 条。所以旧注释那句 "has to be bumped by hand" 照做，结果是静默的零条回落。LTS 页的修复列表在单独的 LTS 页上（5.2 页正文指向 `blender.org/download/lts/5-2/`），这就是它没有 Corrective Releases 小节的原因。

新 recipe 走生产路径 `ChangelogService.loadDiagnostic`（15:24 UTC，打真实页面）：

    5.2.1  → /5.2/  1 条  5.2  July 14, 2026      24 项
    5.1.2  → /5.1/  1 条  5.1  March 17, 2026     24 项
    5.0.1  → /5.0/  1 条  5.0  November 18, 2025  31 项
    4.5.3  → /4.5/  1 条  4.5  July 15, 2025      22 项
    4.2.14 → /4.2/  1 条  4.2  July 16, 2024      15 项
    5.3.0  → /5.3/  0 条
    (无版本) → source /5.2/  1 条  5.2

`BlenderChangelogRecipeTests` 的 5.1、5.2、5.3 fixture 是这次取回页面的 `<h1>` … `</article>` 切片。

### Recipes/org-blenderfoundation-blender.swift — VendorProbeRecipe（下载页）

2026-09-25，只读 GET，Safari UA。`www.blender.org/download/` 200（71471 字节，未压缩），macOS 链接两处，都是 `/download/release/Blender5.2/blender-5.2.2-macos-arm64.dmg/`，`versionPattern` 取出 `5.2.2`，与 5.2.2 dmg 的 `CFBundleShortVersionString` 相同。`download.blender.org/release/` 的目录列表最高到 `Blender5.2/`；`Blender5.0/`、`Blender5.2/` 只有 `-macos-arm64.dmg`，`Blender4.5/` 最高 `blender-4.5.14-macos-{arm64,x64}.dmg`。Homebrew `blender` 与 `blender@lts` cask 当时都是 5.2.2，`auto_updates` 未设。`BlenderProbeRecipeTests` 的 fixture 是这次取回页面的两段原文切片。

### Recipes/org-blenderfoundation-blender.swift — alpha / beta / rc（builder 列表）与 `BlenderBuildInfo`

2026-09-25，只读 GET，Safari UA。`builder.blender.org/download/daily/?format=json&v=1` 200，81139 字节，131 个对象，4 空格缩进，字段顺序固定（`url, app, version, risk_id, branch, patch, hash, platform, architecture, bitness, file_mtime, file_name, file_size, file_extension, release_cycle`）。`darwin`/`arm64`/`dmg` 的条目：4.2.23、4.3.2、4.4.3、4.5.14、5.0.1、5.1.2、5.2.2 为 `stable`，5.3.0 为 `alpha`（`main`，`425ab43ad645`，`file_mtime` 1790305104）；没有 `beta` 或 `candidate`。列表第一个对象是 2024 年的 `4.2.0` Windows arm64 alpha。`/download/daily/archive/?format=json&v=1` 200，1162454 字节，1856 个对象，最早 2026-06-18，`file_mtime` 不单调；其中 `darwin`/`arm64`/`dmg` 有 85 个 alpha、19 个 beta（v52）、5 个 v52 candidate、4 个 v45 candidate、2 个 v42 candidate，不含当前的 `425ab43ad645` 和 `d13f752e3b9c`。

构建时间与上传时间：alpha `425ab43ad645` 构建 01:35:56、上传 02:58:24；beta `4481d59ccf4e` 01:34:43 / 02:40:54；RC `5adcd79a574f` 01:31:02 / 02:37:35（都是 UTC，间隔约 1 小时，说明主程序里的构建时间是 UTC）。正式版 `d13f752e3b9c` 构建于 09-15 01:49:19，列表里的 `file_mtime` 却是 09-25 02:35:40。archive 里 4.5.13 candidate（`bf319e10923f`）上传于 08-24 01:46:32，晚于 5.2.1 RC `5adcd79a574f` 的构建时间 01:31:02——只靠时间闸挡不住跨线降级，marketing 闸才挡得住（`BlenderBuilderTrackTests.aCandidateOfAnOlderLineIsNeverOffered`）。

主程序字节（四个 dmg 挂载后用 mmap 读）：`\0%d.%01d.%d%s%s\0` 各出现一次，前面紧挨的字符串见上文「Channel 详情」；`\0 Beta\0` 只在 beta 里、`\0 Release Candidate\0` 只在 RC 里，`\0 Alpha\0` 四个都有（alpha 里紧挨格式串，其余在别处）。`buildinfo.c` 的布局：`<date>\0<time>\0<commit>\0` + 7 字节对齐填充 + 8 字节 `build_commit_timestamp`（5.2.2 为 `3e 0f a8 6a 00 00 00 00`）+ `<branch>\0Darwin\0Release`；`\0Darwin\0` 在 5.2.2 里只出现一次。最初按「相邻字符串」往回读，被那 8 字节整数挡住，读不出 commit——所以现在先取 `Darwin` 前的分支，再在分支前 96 字节里找 `date\0time\0commit\0`。

新守卫的变异验证（每条改掉后跑 `BlenderBuilderTrackTests` + `BlenderBuildInfoTests`）：去掉 marketing 闸、去掉时间闸、去掉 `unlistedIsOlder`、去掉 lineage 分支里的「vendor 为空 → unknown」、去掉 alpha 的 `main` 分支检查、去掉 `" LTS"` 跳过、让 probe 不把 head 放进 `version`——七条都有测试变红，恢复后全绿。
