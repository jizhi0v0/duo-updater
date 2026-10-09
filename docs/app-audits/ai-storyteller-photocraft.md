# storytold「-craft」套件（PhotoCraft 等七个）

七个 app 同一个厂商、同一条发版流水线、同一种产物命名，所以合成一份审计。每个 app 的 recipe
各自一个 family 文件（`Recipes/ai-storyteller-<app>.swift`），共享理由写在
`ai-storyteller-photocraft.swift`。

## 基本信息

| App | 对标 | Bundle ID | 仓库 | 观测版本 |
|-----|------|-----------|------|---------|
| PhotoCraft | Photoshop | `ai.storyteller.photocraft` | `storytold/photocraft` | 0.2.0 |
| VectorCraft | Illustrator | `ai.storyteller.vectorcraft` | `storytold/vectorcraft` | 0.3.1 |
| FilmCraft | Premiere Pro | `ai.storyteller.filmcraft` | `storytold/filmcraft` | 0.2.1 |
| LightCraft | Lightroom | `ai.storyteller.lightcraft` | `storytold/lightcraft` | 0.2.1 |
| PdfCraft（原 PrintCraft，见「PdfCraft 改名」） | Acrobat | `ai.storyteller.pdfcraft`（≤0.2.1: `ai.storyteller.printcraft`） | `storytold/pdfcraft`（原 `storytold/printcraft`） | 0.4.0 |
| EffectCraft | After Effects | `ai.storyteller.effectcraft` | `storytold/effectcraft` | 0.3.1 |
| DesignCraft | InDesign | `ai.storyteller.designcraft` | `storytold/designcraft` | 0.2.1 |

- Team ID: `DJ6XS33FX8`（Learning Machines LLC），七个全部 Developer ID 签名 + 公证
- 观测日期: 2026-10-07
- 自更新机制: 无。Rust/egui 应用，bundle 里没有 `Frameworks/`、没有 `SUFeedURL`。只有 PrintCraft（现 PdfCraft）有
  Help ▸ Check for updates（当时的 `apps/printcraft/src/updates.rs`）：读同一个 `/releases/latest`、只打开
  release 页面，不下载不安装，不会和我们抢
- 分发: 只有 GitHub Releases（另有 Linux / Windows / FreeBSD 产物与 web 版 zip）
- 开源: 是（MIT OR Apache-2.0）。版本方案、渠道、产物命名都读自仓库源码

## PdfCraft 改名（2026-10-08，v0.4.0，#1087）

PrintCraft 在 v0.4.0 改名 PdfCraft，三样一起变：

| | ≤ v0.2.1 | v0.4.0 起 |
|---|---|---|
| 仓库 | `storytold/printcraft` | `storytold/pdfcraft`（同一个 repo id 1398086162；旧名 301 到 `/repositories/1398086162/…`） |
| macOS 资产 | `printcraft-X.Y.Z-macos-universal.dmg` | `pdfcraft-X.Y.Z-macos-universal.dmg` |
| app | `PrintCraft.app`，`ai.storyteller.printcraft` | `PdfCraft.app`，`ai.storyteller.pdfcraft` |

中间没有 0.3.x release。

- 真包实测（2026-10-09，`pdfcraft-0.4.0-macos-universal.dmg`，sha256 与 GitHub `digest` 一致，只读挂载、未运行）:
  `CFBundleIdentifier` `ai.storyteller.pdfcraft`、`CFBundleName`/`CFBundleDisplayName` `PdfCraft`、
  `CFBundleExecutable` `PdfCraft`、short == build == `0.4.0`、自定义键改为 `PdfCraftVersion`；
  `codesign -dv`: Identifier `ai.storyteller.pdfcraft`，`Developer ID Application: Learning Machines LLC (DJ6XS33FX8)`
  ——**Team 不变**；`lipo -archs` `x86_64 arm64`；`stapler validate` 通过。
- settled from source: `apps/pdfcraft/src/main.rs` 的 `migrate_legacy_folders()` 在首次启动时把
  PrintCraft 的设置目录（`eframe::storage_dir("PrintCraft")`）改名成 PdfCraft 的，新目录已存在则不动——
  厂商有意支持从 PrintCraft 原地升级。
- 我们的处理: recipe 改键 `ai.storyteller.pdfcraft`（family 文件、golden 随之改名为
  `ai-storyteller-pdfcraft`），`repo: "pdfcraft"`，dmg 锚只收 `pdfcraft-`（旧名 dmg 里是旧 id，闸 4 不会让它
  替换 PdfCraft 副本，而且没有一个比任何能来问的 PrintCraft 副本更新）。`BundleIDMigration` 登记
  `ai.storyteller.printcraft → ai.storyteller.pdfcraft`（Team `DJ6XS33FX8`，lastFrom 0.2.1，firstTo 0.4.0）：
  旧 id 副本经 `InstalledApp.recipeBundleID` 走新 id 规则（`GitHubReleasesSource` 自 #1087 起也按它查），
  闸 4 放行这一方向，`AppRestarter` 能找到仍在跑的旧 id 进程。
- ⚠️ 原地替换保留磁盘上的路径（`InPlaceSwap.replace(newApp:over:)` 换到已装副本的位置）：一键后是
  `PrintCraft.app` 这个文件名里装着 PdfCraft。Finder 显示的名字仍是 `PrintCraft`（`mdls` 的 `kMDItemDisplayName` 与 Finder `displayed name` 都是 `PrintCraft.app`，2026-10-09 实测）；Dock 未看。手动从 dmg 拖装则会得到
  并排的 `PdfCraft.app`。
- 一键端到端 0.2.1 → 0.4.0（2026-10-09 真机，#1087）:
  - 第一轮，不运行: `duo check` 给 `PrintCraft 0.2.1 → 0.4.0 [GitHub, in-place]`；`duo install /Applications/PrintCraft.app --yes`
    退出 0，backup → download → verifyingSignature → extract → verifyingCodeSignature → install 全过；之后 bundle 为
    `ai.storyteller.pdfcraft` 0.4.0、Team `DJ6XS33FX8`，`spctl -a` 为 `Notarized Developer ID`。
  - 第二轮，0.2.1 运行中: `duo install` `installed`，结尾提示 `duo restart '/Applications/PrintCraft.app'`（改名后旧名已匹配不到，
    提示改给路径）；照抄执行 → `PdfCraft restarted`，新进程是 `Contents/MacOS/PdfCraft`；再 `duo check` 无待更新。
  - 设置迁移: 0.2.1 退出时写 `~/Library/Application Support/PrintCraft/`；0.4.0 首次启动后它被改名为 `PdfCraft/`，旧目录消失。
    若 `PdfCraft/` 已存在则不迁（与源码一致）。
  - `codesign --verify --strict` 报 `resource fork, Finder information, or similar detritus`：厂商 dmg 里的文件自带
    `com.apple.FinderInfo`，同家族没动过的 PhotoCraft/DesignCraft 也一样，与本次改名无关；非 strict 校验和 `spctl` 都通过。
  - 已知缺口: 改名后 `duo backups restore` 按新 id 找不到旧 id 下的备份（`no backup stored for PdfCraft`），另案处理。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |
| **rc**     | —       | —        | —   | ✗      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（七个都由 channel-verify 实测，见「如何复验」）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | 见上表 | 共享 | — | `/releases/latest` + tag 锚 `^vX.Y.Z$` + dmg 名锚 | ✓ |
| rc（`X.Y.Z-rc.N`）| 同 stable | 共享 | `Info.plist` 自定义键 `<App>Version`（未读） | — | ✗ 未接入 |

- settled from source: `.github/workflows/release.yml`（photocraft，`main`）——版本必须形如
  `1.2.3` 或 `1.2.3-rc.1`；带 `-` 的本意是标 prerelease，`gh release create --draft --generate-notes`
  建草稿、人工发布。
- settled from source: `packaging/macos/Info.plist.in` + `package.sh`——`CFBundleShortVersionString`
  与 `CFBundleVersion` 都只写数字 `X.Y.Z`（`@SHORT_VERSION@`），完整版本（含 `-rc.N`）另写进
  `PhotoCraftVersion` 这个自定义键。
- rc 真包实测（2026-10-07，挂载 `photocraft-0.1.1-rc.5-macos-universal.dmg`）: `CFBundleShortVersionString`
  `0.1.1`、`CFBundleVersion` `0.1.1`、`PhotoCraftVersion` `0.1.1-rc.5`，Team `DJ6XS33FX8`——与源码一致。
- **观测与源码意图不一致**: PhotoCraft 的 `v0.1.1-rc.4` / `v0.1.1-rc.5` 在 GitHub 上是
  `prerelease: false`（2026-10-07 API 实测）。所以不能靠 GitHub 的 prerelease 位挡 rc。其余六个仓库
  至今没有 rc tag。

## 更新检测
- 源: `storytold/<app>` GitHub Releases，`/releases/latest`
- 版本方案: tag `vX.Y.Z` == `CFBundleShortVersionString`（七个真包全部一致，见下）
- 注意事项 —— **rc 不带 prerelease 标记**: `/releases/latest` 可能落在 rc 上，而 rc 装好后
  `Info.plist` 里也是裸 `X.Y.Z`。不锚的话 `v0.2.1-rc.1` 会被当成 `0.2.1` 推给 stable 用户，之后正式的
  0.2.1 反而永远不提示。两道锚：
  - dmg 名 `^<app>-X.Y.Z-macos-universal\.dmg$` 容不下 `-rc.N` → rc 作为 latest 时没有匹配资产 →
    `GitHubReleasesSource` 改走列表并跳过它，答出最新的正式版。
  - tag `^v([0-9]+\.[0-9]+\.[0-9]+)$` 是后备：单独靠它时 rc 变成「无答案」，不会变成错误版本。
  - 变异测试（`StorytoldCraftGitHubRuleTests.anUnflaggedReleaseCandidateIsWalkedPast`）：只放松 tag →
    仍答 0.2.0；只放松 dmg → 无答案；两个都放松 → 把 rc 当 0.2.1 推出。
- 注意事项 —— **CLI 产物同名前缀**: 每个 release 另有 `<app>-cli-X.Y.Z-macos-universal.zip`，
  dmg 锚把它排除。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | 没有自更新器（见基本信息） | release 资产只有整包（2026-10-07） | — |

## 按 OS 分轨
- `LSMinimumSystemVersion` = `11.0`（模板里写死，注释说与 `MACOSX_DEPLOYMENT_TARGET` 一致）。
  release 不声明逐版本的 min/max。
- 架构: 只发 universal（`lipo -archs` = `x86_64 arm64`，七个都是），没有 arch 分支。

## Changelog
- 来源: GitHub Release body（GitHub 自动生成的 "What's Changed"，PhotoCraft 0.2.0 另有手写的
  "Upgrade notes"），经 `GitHubMarkdownParser` 结构化
- 结构化（2026-10-07，channel-verify 的 `changelog pane` 行）: ✓ 七个全部 `source structured`。
  PhotoCraft 0.2.0 保留两个小节 `Upgrade notes` / `What's Changed`（54 条）；其余六个只有
  "What's Changed" 一节，解析为无小节的条目列表（6–33 条），"New Contributors" 不计入条目
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（七个）
- 格式: dmg — `<app>-X.Y.Z-macos-universal.dmg`，GitHub 为每个资产发布 sha256 `digest`
- Pattern: `^<app>-[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产，没有按设备灰度）
- 包验（2026-10-07，七个最新版与七个上一版全部挂载）: bundle id 见上表，short == build == tag，
  `Developer ID Application: Learning Machines LLC (DJ6XS33FX8)`，`spctl -a -t exec` accepted /
  Notarized Developer ID，`stapler validate` 通过。
- ⚠️ `codesign --verify --deep --strict` 在**厂商原始 dmg 里的 .app 上**就失败：
  `resource fork, Finder information, or similar detritus not allowed`——包里每个文件都带
  `com.apple.FinderInfo` xattr。不带 `--strict` 通过，Gatekeeper 接受，安装闸通过。这是厂商打包的问题，
  不是安装过程带进来的。
- 端到端（2026-10-07）: 七个上一版装进 `/Applications`（PhotoCraft 0.1.1 并启动）→ `duo check` 七条
  `[GitHub, in-place]` → `duo install … --yes`：backup / download / verifyingSignature / extract /
  verifyingCodeSignature / install，`7 installed, 0 failed` → 装好的版本即上表观测版本、Team 不变、
  `spctl` Notarized；运行中的 PhotoCraft 提示 stale，`duo restart PhotoCraft` 后新进程起来 →
  再 `duo check` 无待更新。

## 已知问题
- rc 轨未接入：`Info.plist` 只写数字版本，装着 rc 的副本会被当成同号 stable（rc `0.2.1` 面前，
  正式 0.2.1 显示为已是最新）。唯一可分辨的信号是自定义键 `<App>Version`，扫描端目前不读。
- 厂商 dmg 带 FinderInfo，严格签名校验失败（见上）。

## 如何复验
```
# GET https://api.github.com/repos/storytold/<app>/releases/latest → 见上表观测版本
# 挂载 <app>-<ver>-macos-universal.dmg → ai.storyteller.<app> / <ver> / Team DJ6XS33FX8 / Notarized
swift run --package-path application-test feed-discover photocraft-0.2.0-macos-universal.dmg
#   → PhotoCraft [ai.storyteller.photocraft] 0.2.0 — no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify photocraft-0.2.0-macos-universal.dmg --expect stable
#   → detected stable, winning source GitHub, latest 0.2.0, status up to date
swift run --package-path application-test channel-verify photocraft-0.1.1-macos-universal.dmg --expect stable
#   → detected stable, winning source GitHub, latest 0.2.0, status UPDATE → 0.2.0
# 其余六个同形：最新版 up to date；上一版（vectorcraft/effectcraft 0.3.0，其余 0.2.0）UPDATE → 最新版
```

## 建议下一步
1. rc 轨：`<App>Version` 带 `-rc.N` 已在 PhotoCraft rc 真包上确认；要接的话需扫描端支持读这个自定义键。
2. 帖子说一个月内要追平 Adobe，发版会很密；`duo verify` 夜扫会盯住 pattern 是否还匹配。
