# FSNotes

## 基本信息
- App: FSNotes — 纯文本 / Markdown 笔记 app，MIT 许可
- Bundle ID: `co.fluder.FSNotes`（iOS 版是另一个 id `co.fluder.mobile.FSNotes-iOS`，settled from source: `FSNotes.xcodeproj/project.pbxproj` on `master`）
- 仓库: `glushchenko/fsnotes`（默认分支 `master`）
- Team ID: `866P6MTE92`（provisioning profile 的 TeamName: Oleksandr Hlushchenko）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 7.3.6（tag `v7.3.6`，资产 `FSNotes_v7.3.6.zip`，`CFBundleVersion` 724）；上一版 7.3.5（722）；观测日期: 2026-10-22
- 自更新机制: **无**。包里没有 `SUFeedURL`、没有 `Contents/Frameworks`（无 Sparkle）、没有嵌套 app / XPC / appex；主二进制 `strings` 里没有 sparkle / appcast / `api.github.com` / `releases/latest`；仓库代码搜索 `Sparkle`、`SMAppService` 均 0 条
- 分发: GitHub Releases（每版一个 `FSNotes_<version>.zip`）、Homebrew cask `fsnotes`（无 `auto_updates`，URL 指向同一个 GitHub 资产）、Mac App Store（id 1277179284，同一个 bundle id，付费）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用） | ✓（通用） | ✓ | —           |

当前生效源: **GitHub**（直接下载的副本，channel-verify 实测）。brew 装的副本由 `HomebrewCaskSource` 先答（cask 无 `auto_updates`）；MAS 副本由 `MacAppStoreSource` 答，且 GitHub 源对它直接跳过（见下）。`feed-discover` 对 7.3.6 zip: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（读真包）:
  - 7.3.6、7.3.5、7.3.4、6.10.2、4.10.2、1.4：全部 `co.fluder.FSNotes`、Team `866P6MTE92`。1.4（2018）只有 x86_64 且早于公证，其余 universal、Notarized。没有改名前的旧 id，不需要 `BundleIDMigration`
- 其他轨: 只有 GitHub 上标了 `prerelease` 的 beta（`7.0.0b1`…`7.0.0b6`，`dev` 分支；更早的 `6.0.0beta*`、`5beta*`），没有独立 bundle id，app 里也没有切 beta 的开关（包里没有任何更新器）。stable rule 读 `/releases/latest`，GitHub 算它时排除 prerelease；版本模式锚定，`7.0.0b6` 也读不出。**装了 beta 的副本在对应正式版出来时不会被提示**：beta 带的是正式版的版本号（`7.0.0b1`、`7.0.0b6` 的 `project.pbxproj` 里 `MARKETING_VERSION = 7.0.0`，`Info.plist` 的 `CFBundleShortVersionString` 取 `$(MARKETING_VERSION)`，只有构建号 684 → 700 → 702 在变），所以 `v7.0.0` 成为 `/releases/latest` 后，`7.0.0b6` 这份副本读作 7.0.0，与 7.0.0 相比是「已是最新」，要等下一个点版本（`v7.1.0`）才会被提示。构建号不参与比较（见「更新检测」）。记在「已知问题」
- Mac App Store 副本: 同一个 bundle id。MAS 副本带 `Contents/_MASReceipt/receipt`，`AppScanner` 记 `isMASApp`，`GitHubReleasesSource` 开头 `guard !app.isMASApp` 直接跳过，所以 GitHub 规则既不检测也不一键 MAS 副本。GitHub zip 里没有 `_MASReceipt`（7.3.6 包实测）。MAS 版 Team：项目 Release 配置是 `CODE_SIGN_IDENTITY = "3rd Party Mac Developer Application"`、`DEVELOPMENT_TEAM = 866P6MTE92`、`PROVISIONING_PROFILE_SPECIFIER = "MAS Distribution"`（settled from source: `project.pbxproj` on `master`），即与 GitHub 版同一个 Team。**MAS 二进制本身没有读**（付费，未下载），这一点只来自源码
- iCloud: GitHub 版签了 iCloud 容器 `iCloud.co.fluder.fsnotes`（`CloudDocuments`）、KVS `866P6MTE92.co.fluder.fsnotes`，和 MAS 版共用（同一个 Team 下才能共用容器）。换包不动容器
- 版本范围、主机下限: 7.x `LSMinimumSystemVersion` 12.4，6.10.2 是 10.14。DuoUpdater 本身是 macOS 15 / arm64（`App/project.yml`），都在厂商下限之上，不需要 `hostRequirement`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `co.fluder.FSNotes` | — | 默认 | `/releases/latest` | ✓ |
| beta    | `co.fluder.FSNotes` | 共享 | 无（只有 GitHub `prerelease` 标记） | — | — 不单独接：没有应用内开关，beta 只在大版本前出几版。装了 beta 的副本在对应正式版出来时读作「已是最新」，见「已知问题」 |

## 更新检测
- 源: `glushchenko/fsnotes` GitHub Releases，`/releases/latest`
- 版本方案: tag `v7.3.6` → `CFBundleShortVersionString` `7.3.6`；`CFBundleVersion` 是递增构建号，不参与比较
- `versionPattern` `^v?([0-9]+(?:\.[0-9]+)+)$`
- **待审项「有 tag 读不出」→ 放宽到 `^v?`。** 分诊脚本只看了第一页 100 条（89 条非 prerelease），读出 14 条。全量（2026-10-22，`gh api …/releases --paginate`）342 个 release、298 条非 prerelease：
  - 读不出的 `6.10.2`、`6.9.x`… 是 v7 之前的同一个产品：都在 `master`，资产都是 `FSNotes_<version>.zip`，6.10.2 / 4.10.2 / 1.4 真包都是 `co.fluder.FSNotes`、Team `866P6MTE92`。厂商从 v7.0.0 起才统一带 `v`，之前只有 `v6.6.0`、`v3` 带
  - 用 `^v?` 后 298 条读出 287 条。剩下 11 条读不出的是 `6.2.5r`、`5`、`4.9.7b2`、`4.9.0b444`、`4.8.4_build442`、`4.8.3_build438`、`4.7.2beta1`、`v3`、`FSNotes`、`1.1.9b62`、`1.1.9b61`，都是 2023 年以前、带后缀或单段的 tag，不扩
  - 读得出的 prerelease 数字 tag（`4.9.3`、`4.9.0`、`4.8.2`、`4.0.21`、`4.0.6`、`3.9.0`）被 `/releases/latest` 和列表回退的 `stableOnly` 排除
  - 下一版: `v8.0.0` → 8.0.0、`8.0` → 8.0；`v7.4.0-rc.1`、`7.4.0b1` 不匹配
  - 对检测本身：stable rule 只读 `/releases/latest`（今天是 `v7.3.6`），所以这条放宽只影响资产缺失时的列表回退与历史条目，以及厂商以后再去掉 `v` 的情况
- install pattern `^FSNotes_v?[0-9]+(?:\.[0-9]+)+\.zip$`

## 按架构 / 按 OS 分轨
- 架构: universal（`lipo -archs` = `x86_64 arm64`）；`LSMinimumSystemVersion`: 12.4（7.x）。release 不声明 OS 范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 包里没有任何更新器（见「自更新机制」） | 每个 release 只有一个 zip 资产 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 7.3.5 约 10 s，没有停放任何东西） | 不需要 |
| 证据 | 没有更新器，不下载新版 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 7.3.5 起）: `source structured: 1 entries; newest 7.3.6: 1 items, headings []; first items ["Fixes and improvements"]`。7.3.6 正文就是一行 `- Fixes and improvements`，不是被压平
- 较长正文用生产解析器跑过（临时测试调 `GitHubMarkdownParser.parse`，跑完删掉）:
  - 7.3.5（4 条列表）: `items=4 headings=[]`，四条原样保留（`#2005` 这种行尾 issue 号保留）
  - 7.0.0（`##` 分组 + `###` 小节，94 行）: `items=49`，`headings=["Search & Navigation", "UI/UX", "Editing", "Statistics", "Links & Files", "Git Integration", "Tags", "URL Schemes", "Clipboard", "Critical", "UI/Visual", "Settings & Behavior", "iOS", "Performance", "macOS", "Won't Fix"]`。`###` 小节都保留；只有一层的 `## New Features` / `## Bug Fixes` 不单独成标题（小节标题已经在）；末尾 `## Key Improvements` 的有序列表（`1.`…`5.`）和 `## Acknowledgments` 的一段话被丢掉；条目里的 `(#1761)` 被去掉。解析器未改
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 7.3.5 → `duo check` `7.3.5 → 7.3.6 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 7.3.6、可执行文件 inode 变、`TeamIdentifier=866P6MTE92`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 7.3.6 包相同
  - 第二轮（运行中）: 启动 7.3.5（主窗口直接打开到「FSNotes › Welcome › 1. Introduction」，没有弹存储目录面板），`duo install` 后提示 `Still running the old code`；`duo restart FSNotes` 后新进程起来，之后 10 s 磁盘一直是 7.3.6、签名有效
- 格式: zip（`compression method=store`），根目录就是 `FSNotes.app`
- **待审项「v7.3.4 没有 mac 资产」→ 不成立。** v7.3.4 的资产是 `FSNotes_7.3.4.zip`（名字里没有 `v`，tag 有），真包 `co.fluder.FSNotes` 7.3.4（719）、Team `866P6MTE92`、Notarized，是普通 Mac 版；分诊草稿的 `^FSNotes_v…` 没匹配上而已。install pattern 已改成 `v?`
- 嵌套 / 常驻组件: 无（没有 LoginItems / Helpers / XPC / LaunchAgent）。app 是 sandboxed（`com.apple.security.app-sandbox`）
- 签名: 7.3.4、7.3.5、7.3.6 都是 Team `866P6MTE92`、Notarized Developer ID；上一版与最新版 Team 相同，旧副本不会被安装闸拒
- 校验: GitHub 资产 `digest`。v7.3.6 `sha256:5de97f63df2f91533fd26fc98588cdaea29dc1ef4612a6164d6cc3468c457c56`、v7.3.5 `sha256:c7b64db673acd38d4a3df32000afff143df095716b5fd661ae1d57277a10bafc`，与下载的 zip `shasum -a 256` 相同，大小 16860055 / 16855446 等于 Content-Length
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Homebrew cask 的 URL 也是这个资产。仓库 README 推的是 App Store，GitHub zip 是公开的免费构建）
- 启动副作用（来自源码 `FSNotes/AppDelegate.swift` on `master`；2026-10-22 真机核对的已注明）:
  - 首启若没有存储目录（`UserDefaultsManagement.storagePath == nil`），弹 `NSOpenPanel`「Please select default storage directory」并直接 `return`，不开主窗口
  - `CLOUD_RELATED_BLOCK` 编译时会在 iCloud 容器里建 `Documents` 目录（`~/Library/Mobile Documents/iCloud~co~fluder~fsnotes/`）。**真机：首启在这里写了 `Documents/Welcome/` 9 篇示例笔记（`.textbundle`）和 `Documents/Trash/`，会同步到用户的 iCloud Drive**；默认存储就是 iCloud，所以没弹存储目录面板
  - 从 MAS 换过来且默认存储在 iCloud Drive 时会弹「是否搬旧库」的 `NSAlert`（`checkStorageChanges`）
  - 没有登录项 / LaunchAgent / root helper / 默认 app 注册；不写 `~/.claude` / `~/.agents`（二进制与源码均无此路径）
  - 数据在 `~/Library/Containers/co.fluder.FSNotes`（cask 的 zap 也只列它和 `Application Scripts`）
- 阻塞: 无

## 已知问题
- 装了 beta 的副本（`7.0.0bN` 这类）在同号正式版成为 `/releases/latest` 时被判「已是最新」，不会被提示换成正式版，要等下一个点版本。原因：beta 与正式版共用同一个 `MARKETING_VERSION`，beta 无渠道信号，版本比较只看营销版本号、构建号不参与。证据（`gh api repos/glushchenko/fsnotes/contents/FSNotes.xcodeproj/project.pbxproj?ref=<tag>`，macOS target）：`7.0.0b1` 为 `MARKETING_VERSION = 7.0.0` / `CURRENT_PROJECT_VERSION = 684`，`7.0.0b6` 为 7.0.0 / 700，`v7.0.0` 为 7.0.0 / 702。窗口：`v7.0.0` 发布于 2026-01-19，`v7.1.0` 发布于 2026-01-31，这段时间里 `7.0.0b6` 副本读作 7.0.0。下一轮 `8.0.0bN` 对 `v8.0.0` 会重演。规则没改：beta 副本与正式版共用 bundle id，包内没有可区分的信号。
- MAS 版二进制的 Team 只从项目配置读到，没有拿真 MAS 包核对
- 7.0.0 这类长正文末尾的有序列表和致谢段落在面板里不显示（通用解析器行为）

## 如何复验
```bash
gh api 'repos/glushchenko/fsnotes/releases?per_page=100' --paginate -q '.[]|[.tag_name,.prerelease]|@tsv'
gh release download v7.3.5 --repo glushchenko/fsnotes --pattern 'FSNotes_v7.3.5.zip'
gh release download v7.3.4 --repo glushchenko/fsnotes --pattern 'FSNotes_7.3.4.zip'
.claude/skills/coverage-discovery/scripts/check-bundle.sh FSNotes_v7.3.5.zip      # → co.fluder.FSNotes, 866P6MTE92, Notarized
swift run --package-path application-test feed-discover FSNotes_v7.3.6.zip         # → no Sparkle / electron / MyGo
ditto -x -k FSNotes_v7.3.5.zip x535 && swift run --package-path application-test channel-verify x535/FSNotes.app --expect stable   # → GitHub, UPDATE → 7.3.6
ditto -x -k FSNotes_v7.3.6.zip x536 && swift run --package-path application-test channel-verify x536/FSNotes.app --expect stable   # → up to date
```
channel-verify 实测（2026-10-22）: 7.3.5 → `winning source GitHub`、`latest 7.3.6`、`status UPDATE → 7.3.6`；7.3.6 → `up to date`；6.10.2（旧 tag 方案）→ `UPDATE → 7.3.6`。三次 `detected channel → stable`。

## 建议下一步
无。厂商发下一个版本时复查资产名（`FSNotes_<v>.zip` / `FSNotes_v<v>.zip`）和 Team。
