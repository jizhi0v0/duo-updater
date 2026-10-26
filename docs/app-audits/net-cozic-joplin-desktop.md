# Joplin

## 基本信息
- App: Joplin — 开源笔记应用（Electron），AGPL-3.0
- Bundle ID: `net.cozic.joplin-desktop`
- 仓库: `laurent22/joplin`（默认分支 `dev`，monorepo：桌面、移动端、server、cli、clipper 都在里面）
- Team ID: `A9BXAFS6CT`（Developer ID Application: Laurent Cozic）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.7.21（tag `v3.7.21`，资产 `Joplin-3.7.21-arm64.DMG`）；上一版稳定 3.7.18；预发布 3.7.14；观测日期: 2026-10-26
- 自更新机制: **只提示、不换包**（macOS 上）。settled from source: `packages/app-desktop/checkForUpdates.ts`、`packages/app-desktop/utils/checkForUpdatesUtils.ts`、`packages/app-desktop/app.ts` on `dev`，并在 3.7.21 包的 `app.asar` 里核对过：
  - 启动 5 s 后、之后每 12 h（设置 `autoUpdateEnabled`，默认开）读 `https://objects.joplinusercontent.com/r/releases`。2026-10-26 实测它 302 到 `https://api.github.com/repos/laurent22/joplin/releases`，即本仓库的 release 列表
  - 有新版就弹对话框（Download / Skip this version / Full changelog / Cancel），点 Download 只是在浏览器里打开 dmg 链接（`github.com/laurent22/joplin/releases/download` 换成 `objects.joplinusercontent.com`）。arm64 取 `/arm64\.(dmg|DMG)$/`，否则取无 arch 词的 `.dmg`
  - 包里也带 electron-updater（`Contents/Resources/app-update.yml`: `provider: github`、`owner: laurent22`、`repo: joplin`、`updaterCacheDirName: '@joplinapp-desktop-updater'`；`Contents/Frameworks/Squirrel.framework`），由 `AutoUpdaterService` 驱动、受 `featureFlag.autoUpdaterServiceEnabled` 控制。但 `app.ts` 每次在 Mac 上启动都把这个开关写回 false（注释 "Always disable on Mac for now"；3.7.21 的 `app.asar` 里有 `isMac()&&Co.default.setValue("featureFlag.autoUpdaterServiceEnabled",!1)`），设置界面里也只在 Windows 显示它。所以 macOS 上 electron-updater 不下载、不换包
- 分发: GitHub Releases；Homebrew cask `joplin`（3.7.21，下载的就是 `Joplin-<v>-arm64.DMG`，没有 `auto_updates`）；官网下载页本审计没核。Mac App Store：2026-10-26 `itunes.apple.com/lookup?bundleId=net.cozic.joplin-desktop&entity=macSoftware` 返回 `resultCount 0`，按名字搜 `joplin` 也没有这个 id

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|                | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|----------------|---------|----------|-----|--------|-------------|
| **stable**     | —       | cask 存在（本审计没测 brew 装的副本由哪个源回答） | — | ✓ | — |
| **prerelease** | —       | —        | —   | ○（同 id，靠设置区分，需要 ChannelBinding） | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`；`app-update.yml` 是 `provider: github`，feed-discover 判 `review electronProviderNeedsConstruction`，`ElectronManifestSource` 不回答。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v3.7.21: `net.cozic.joplin-desktop`，Team A9BXAFS6CT，Notarized，arm64，`LSMinimumSystemVersion` 12.0
  - v3.7.18（上一版稳定）: 同 id、同 Team，Notarized
  - v3.7.14（预发布）: 同 id、同 Team，Notarized；Info.plist 与 3.7.18 只差版本号和 `ElectronAsarIntegrity` 的哈希
  - v2.12.15（最早带 arm64 dmg 的稳定版）: 同 id、同 Team，Notarized，`LSMinimumSystemVersion` 10.13
  - v0.10.19（列表里最老的稳定版，2017）: 同 id、同 Team（spctl: Developer ID，未公证），x86_64，`CFBundleVersion` 0.10.19.57
  - 没有改名前的旧 bundle id：`dev` 分支 `packages/app-desktop/package.json` 的 `build.appId` 是 `net.cozic.joplin-desktop`，上面读过的 5 个真包（2017 到 2026）都是这个 id，cask 的 zap 也只列这个 id 及其 `.helper`
- 其他轨: 预发布，与稳定版同 id，见「Channel 详情」。没有 nightly / beta 的独立仓库或独立 bundle id
- 版本范围: 423 个 release，417 个 tag 是 `v<x.y.z>`，全部被 `^v([0-9]+(?:\.[0-9]+)+)$` 读到；另 6 个是 2018 年的 `android-v…`，不匹配。server / cli / ios / clipper / plugin 等只有 tag 没有 release（`gh api repos/laurent22/joplin/tags` 里有 `server-v`、`cli-v`、`ios-v`、`android-v`、`clipper-`、`plugin-generator-v` 等前缀），规则读的是 release，又是锚定的 `^v…$`，读不到它们。当前 `/releases/latest` 是 v3.7.21
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Joplin 3.7.21 `LSMinimumSystemVersion` 12.0，低于我们的下限，不需要 `hostRequirement`。Intel 副本（无 arch 词的 `Joplin-<v>.dmg`，或 2.12 之前只有 x86_64 的版本）跑在 Apple 芯片的 Mac 上时，一键会换成 arm64 包，同 id、同 Team，可以接受

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `net.cozic.joplin-desktop` | 共享 | — | GitHub `/releases/latest` | ✓ |
| prerelease | `net.cozic.joplin-desktop` | 共享 | 设置 `autoUpdate.includePreReleases` | 需要 `ChannelBinding` + `usePrereleases` 规则 | ○（待决定） |

**预发布怎么来的（settled from source: `packages/lib/models/settings/builtInMetadata.ts`、`packages/app-desktop/utils/checkForUpdatesUtils.ts`、`packages/lib/determineBaseAppDirs.ts` on `dev`）:**
- 417 个 `v` release 里 217 个 `prerelease: true`。tag 形状、资产名（`Joplin-<v>-arm64.DMG` 等）、bundle id、Team 都和稳定版一样，包里没有任何区分标记（3.7.14 与 3.7.18 的 Info.plist 对比如上）
- 选择预发布的是应用内设置「Get pre-releases when checking for updates」，键 `autoUpdate.includePreReleases`，默认 false，`storage: SettingStorage.File`、`isGlobal: true`，即写在根 profile 目录的 `settings.json` 里；默认根 profile 目录是 `~/.config/joplin-desktop`（`determineBaseAppDirs.ts`；可被 `--profile` 参数改掉）。这个文件在真机上开关两种状态各写成什么，本审计**没核**
- 打开后，Joplin 自己的检查取 release 列表的第一条（不论是否预发布），否则取第一条非预发布

**本规则对预发布副本的行为（channel-verify 实测 + 推理）:**
- 检测：`ReleaseChannel.detect` 判成 stable（3.7.14 实测 `detected channel → stable`），由 stable 规则回答。实测 3.7.14 → `UPDATE → 3.7.21`。比稳定版新的预发布（例如 3.7.1–3.7.14 发布时稳定版还在 3.6.x）按 `VersionComparator` 读成 up to date，不会被"降级"；它看不到更新的预发布
- 一键：只在稳定版比已装版本新时才给，装的是稳定版，与 Joplin 自己的检查对同一副本的答案一致（它取列表第一条，若那条就是稳定版也会给稳定版）。不需要 `OneClickGate`
- 要真正接上预发布轨：需要一个 `ChannelBinding` 读 `~/.config/joplin-desktop/settings.json` 的 `autoUpdate.includePreReleases`，再加一条 `usePrereleases: true`、`channel: .beta` 的 `GitHubReleaseRule`（同一 pattern；预发布本身是 GitHub release，资产名一样）。`ChannelBinding` 是引擎（`Sources/`）改动，本次没做，见「建议下一步」

## 更新检测
- 源: `laurent22/joplin` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.7.21` → `CFBundleShortVersionString` `3.7.21`、`CFBundleVersion` `3.7.21`（0.10.x 时代 `CFBundleVersion` 多一段，如 `0.10.19.57`，只比 short version，不影响）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`android-v0.10.85`、`server-v3.7.2`、`v4.0.0-rc.1` 都不匹配；`v4.0.0`、`v4.0` 匹配）
- install pattern `^Joplin-[0-9]+(?:\.[0-9]+)+-arm64\.DMG$`。扩展名是大写 `DMG`：所有带 arm64 dmg 的稳定版（v2.12.15 起）都是 `.DMG`，只有 v2.12.3、v2.12.4 等几个 2.12 预发布用过小写 `.dmg`。同一 release 里的 `Joplin-<v>.dmg`（Intel）、`-arm64.pkg`、`.pkg`、`-arm64.zip`、`-mac.zip`、`.blockmap`、`latest-mac*.yml` 都不匹配。引擎按 `pathExtension.lowercased()` 识别 dmg（`ArchiveExtractor.extractApp`），大写扩展名不影响解包
- Homebrew cask 下载的也是 `Joplin-<v>-arm64.DMG`

## 按架构 / 按 OS 分轨
- 每个稳定版分架构发：`Joplin-<v>-arm64.DMG`（arm64）与无 arch 词的 `Joplin-<v>.dmg`（Joplin 自己的检查把它当 x64 用，`checkForUpdatesUtils.ts` 注释 "The x64 assets have no arch suffix"）。规则只装 arm64 那个，与我们的 arm64 下限一致
- `LSMinimumSystemVersion` 12.0（3.7.21、3.7.18）；cask `depends_on macos >= 12`。release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（但 macOS 上关着） | 有 blockmap | 不能 |
| 证据 | 包里有 electron-updater，它按 `.blockmap` 差分下载是 electron-updater 的通用能力（没在 Joplin 上验证）；macOS 上 `AutoUpdaterService` 被 `app.ts` 关掉，实际不跑 | 2026-10-26 v3.7.21 release 带 `Joplin-3.7.21-arm64.dmg.blockmap`、`-arm64.zip.blockmap`、`-mac.zip.blockmap` | blockmap 是 electron-builder 的分块差分，不是 Sparkle `BinaryDelta`；`DeltaApplier` 不读这种格式 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会（macOS） | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | macOS 上只有提示型检查在跑，点 Download 是交给浏览器下载；electron-updater（缓存目录名 `@joplinapp-desktop-updater`）被 `app.ts` 关掉 | — | — |

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 3.7.18 起）: `source structured: 1 entries; newest 3.7.21: 13 items, headings []; first items ["New: Add setting to hide the AI Chat too", "Improved: AI Chat: Persist conversation ", "Improved: Improve how semantic search in"]`
- `headings []` 不是被压平：v3.7.21 的正文本身就是 13 条 `- New: / Improved: / Fixed:` 列表，没有标题；13 条全部保留
- 跟随 channel: 稳定规则只读 `/releases/latest` 一条，pane 只显示最新稳定版的正文
- 局限: Joplin 把一个小版本的大部分改动写在预发布的正文里，进入稳定版时正文往往只剩一两条（v3.7.1 预发布 18 条，v3.7.16 稳定版 1 条）。Joplin 自己的对话框会把同一 `x.y` 下所有 release 的正文拼起来。稳定规则只取 `/releases/latest` 这一条的正文（`GitHubReleasesSource`），所以推断从 3.6.x 升到 3.7.x 的副本在 pane 里看不到预发布里写的 3.7 主要变化（没拿 3.6.x 真包跑过）。完整列表在 `https://joplinapp.org/help/about/changelog/desktop`
- Recipe 状态: 现在不需要；要补齐跨小版本的说明，可以加一个读上面那个页面的 `ChangelogRecipe`（见「建议下一步」）

## 一键安装
- 状态: **支持**
- 端到端: 待主会话（真机：装上一版 → `duo install`）
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Joplin.app` + `Applications` 软链
- 嵌套: `Contents/Frameworks/` 下 4 个 Electron helper（`Joplin Helper.app`、`(GPU)`、`(Plugin)`、`(Renderer)`，`LSUIElement=true`），是主进程的子进程，随主程序退出；另有 `Electron Framework`、`Mantle`、`ReactiveObjC`、`Squirrel` 四个 framework。没有 `Contents/Library`（无 LoginItems / LaunchAgent / 特权 helper）；`app.asar` 里没有 `setLoginItemSettings`、`SMAppService`、`LaunchAgents` 字符串
- 签名: 0.10.19、2.12.15、3.7.14、3.7.18、3.7.21 都是 Team `A9BXAFS6CT`，Team 没换过；2.12.15 起 Notarized
- 校验: GitHub 资产 `digest`。v3.7.21 `Joplin-3.7.21-arm64.DMG` `sha256:7e58db4346240de4cc7b7794d603be06b1a10b981bc5c22e0792080f28e856b7`，下载文件 `shasum -a 256` 相同、208484343 字节等于资产大小；v3.7.18 `sha256:103c9bc884108bc31593060008005411a45c1b2b530eeffca4d5ad262306c6e6`、208470992 字节，同样相符
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Joplin 自己的稳定版检查给的也是这一版）
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 启动 5 s 后会自动检查更新；从 3.7.18 启动会弹「An update is available」对话框。不要点 Download（只是开浏览器）
  - URL scheme `joplin`（`org.joplinapp.x-callback-url`）
  - 首启在 `~/.config/joplin-desktop` 建 profile（数据库、`settings.json`、插件目录），cask 的 zap 另列 `~/Library/Application Support/Joplin`
  - Web Clipper 服务默认不自动启动（`clipperServer.autoStart` 默认 false）
  - 自更新器不暂存，第二轮无法造「暂存了一个比 latest 旧的版本」

## 已知问题
- 预发布副本只看到稳定版视角（比稳定版新时 up to date，看不到更新的预发布）；接预发布轨需要引擎改动，见上
- 跨小版本升级时 changelog pane 只有最新稳定版的一两条，见「Changelog」

## 如何复验
```bash
gh api repos/laurent22/joplin/releases/latest -q '.tag_name, (.assets[] | select(.name|test("arm64\\.DMG$")) | .name+" "+.digest)'
gh release download v3.7.21 --repo laurent22/joplin --pattern 'Joplin-3.7.21-arm64.DMG'
gh release download v3.7.18 --repo laurent22/joplin --pattern 'Joplin-3.7.18-arm64.DMG'
# check-bundle.sh 只认小写扩展名，给它一个小写名的硬链接
ln Joplin-3.7.21-arm64.DMG j21.dmg && .claude/skills/coverage-discovery/scripts/check-bundle.sh j21.dmg   # Team A9BXAFS6CT, Notarized
swift run --package-path application-test channel-verify Joplin-3.7.18-arm64.DMG --expect stable   # GitHub, UPDATE → 3.7.21
swift run --package-path application-test channel-verify Joplin-3.7.21-arm64.DMG --expect stable   # up to date
# 预发布副本
gh release download v3.7.14 --repo laurent22/joplin --pattern 'Joplin-3.7.14-arm64.DMG'
swift run --package-path application-test channel-verify Joplin-3.7.14-arm64.DMG   # detected stable, UPDATE → 3.7.21
# macOS 上关掉 electron-updater 的那行
LC_ALL=C grep -a -o 'isMac()&&[A-Za-z._]*setValue("featureFlag.autoUpdaterServiceEnabled",!1)' /Volumes/Joplin*/Joplin.app/Contents/Resources/app.asar
```

channel-verify 原始输出（2026-10-26）:
```
3.7.18 dmg:
  detected channel  → stable
  ✓ detection matches --expect stable
    winning source  GitHub
    latest          3.7.21
    download        https://github.com/laurent22/joplin/releases/download/v3.7.21/Joplin-3.7.21-arm64.DMG
    changelog pane  source structured: 1 entries; newest 3.7.21: 13 items, headings []; first items ["New: Add setting to hide the AI Chat too", "Improved: AI Chat: Persist conversation ", "Improved: Improve how semantic search in"]
    status          UPDATE → 3.7.21
3.7.21 dmg:
  detected channel  → stable
  ✓ detection matches --expect stable
    winning source  GitHub
    latest          3.7.21
    status          up to date
3.7.14 dmg（预发布）:
  detected channel  → stable
    winning source  GitHub
    latest          3.7.21
    status          UPDATE → 3.7.21
```

## 建议下一步
1. 预发布轨（待用户决定）：`ChannelBinding` 读 `~/.config/joplin-desktop/settings.json` 的 `autoUpdate.includePreReleases`（先在真机上开关一次，看 true / false / 缺省各写成什么），true → `.beta`；再加一条 `usePrereleases: true`、`channel: .beta` 的 `GitHubReleaseRule`，pattern 与稳定规则相同
2. 跨小版本 changelog：`/fragile-recipe Joplin`（ChangelogRecipe，源 `https://joplinapp.org/help/about/changelog/desktop`），让 3.6 → 3.7 这类升级看到预发布里的改动
3. 一键端到端（主会话）：真机装 3.7.18 → `duo install`，两轮
