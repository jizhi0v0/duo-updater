# Heynote

## 基本信息
- App: Heynote — 给开发者用的草稿本（Electron），MIT
- Bundle ID: `com.heynote.app`
- 仓库: `heyman/heynote`（默认分支 `main`，没归档；README 顶部没有停更/终止的说法）
- Team ID: `VY5Y3H438S`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 2.9.1（tag `v2.9.1`，资产 `Heynote_2.9.1_universal.dmg`）；上一版 2.9.0；beta 2.9.1-beta、2.9.0-beta.6；观测日期: 2026-10-26
- 自更新机制: **electron-updater**，`Contents/Resources/app-update.yml` = `owner: heyman` / `repo: heynote` / `provider: github` / `updaterCacheDirName: heynote-updater`。settled from source: `electron/main/auto-update.js` on `main`（见「自更新器」）
- 分发: GitHub Releases（每版 universal / arm64 / x64 各一个 dmg 和 zip，外加 `latest-mac.yml`）；Homebrew cask `heynote`（`auto_updates true`，2.9.1，按机器架构装 `_arm64.dmg` / `_x64.dmg`，`depends_on macos >= 12`；没有 `heynote@beta`）；App Store 没有（`itunes.apple.com/lookup?bundleId=com.heynote.app` resultCount 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓（`-beta.N` 副本；不带编号的 `-beta` 副本读成 stable，见下） | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`；`feed-discover` 对 2.9.1 dmg 的结论是 `review electronProviderNeedsConstruction`（`provider: github` 没给 `ElectronManifestSource` 能直接读的地址），所以要 GitHub rule；cask 是 `auto_updates`，`HomebrewCaskSource` 让位。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v2.9.1 universal: `com.heynote.app`，Team VY5Y3H438S，Notarized，`CFBundleShortVersionString` = `CFBundleVersion` = 2.9.1
  - v2.9.0 universal: 同 id、同 Team，2.9.0
  - v2.9.1-beta / v2.9.0-beta.6 universal: 同 id、同 Team，版本字段原样带 `-beta` / `-beta.6`
  - v1.0.2 arm64（release 列表里最老的一版）: 同 id、同 Team，Notarized，`LSMinimumSystemVersion` 10.13
  - `electron-builder.json5` 的 `appId` 是 `com.heynote.app`；没有改名前的旧 bundle id
- 其他轨: beta（同 id，见「Channel 详情」）。没有 nightly，没有另一个仓库
- 版本范围: 2026-10-26 共 109 个 release，53 个正式版 tag 全是 `vX.Y.Z`（stable `versionPattern` 53/53 读得出），56 个 prerelease 全是 `vX.Y.Z-beta` 或 `vX.Y.Z-beta.N`，都标了 `prerelease: true`（beta `versionPattern` 109/109 读得出）。universal dmg 从 v1.2.1 起每个 release 都有；v1.2.0 及更早只有 arm64 / x64，这些副本照样由 stable rule 回答，一键装的是最新版的 universal dmg
- 架构: universal 与 arm64 是不是只差架构 —— 在 2.9.1 上比过：两个 bundle 的文件列表只差 `v8_context_snapshot.x86_64.bin`，主可执行文件 `x86_64 arm64` 对 `arm64`，`app.asar` 1914 个条目的路径、大小、integrity 哈希逐条相同（整个文件哈希不同，只是头部），`app-update.yml` 和 Info.plist 除 `ElectronAsarIntegrity` 外一致。所以挑 universal 不会换成另一个产品
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Heynote `LSMinimumSystemVersion` 12.0，在下限之下，不需要 `hostRequirement`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.heynote.app` | 共享 | 版本号纯数字 | GitHub `/releases/latest` | ✓ |
| beta    | `com.heynote.app` | 共享 | 版本号 `-beta.N`（`ReleaseChannel.detect` 第 4 步） | `.beta` rule 读 release 列表，收 stable 和 beta tag | ✓（`-beta.N` 副本） |

**beta 怎么来的（settled from source: `electron/main/auto-update.js`、`electron/config.js`、`src/components/UpdateStatusItem.vue` on `main`）:**
- 设置里的开关存为 `settings.allowBetaVersions`（`electron-store`，`name: "config"`，即 `userData` 下的 `config.json`；`userData` 的具体目录没在真机上核），默认 `false`
- 每次检查前 `autoUpdater.allowPrerelease = CONFIG.get("settings.allowBetaVersions")`，并且 `autoUpdater.allowDowngrade = true`。所以厂商按**开关**而不是按已装版本决定轨道：开着时 electron-updater 取 release 列表里最新的一个（stable 或 beta），关着时取 `/releases/latest`
- beta 和正式版同一个仓库、同一个 bundle id、同一个 Team，资产名带版本（`Heynote_2.9.1-beta_universal.dmg`），每个 prerelease 也带一个 `latest-mac.yml`（文件名与正式版的相同，各在自己的 release 下）

**我们怎么处理:**
- `-beta.N` 副本（如 2.9.0-beta.6）: `ReleaseChannel.detect` 读成 beta，stable rule 拒；`.beta` rule（`usePrereleases`，`versionPattern` `^v([0-9]+\.[0-9]+\.[0-9]+(?:-beta(?:\.[0-9]+)?)?)$`）读列表、取最新一个，stable 和 beta 都收，和 Zettlr 的 beta rule 同形。2.9.0-beta.6 实测 → 2.9.1（毕业到正式版，正是厂商开着开关时会给的）。一键装 universal dmg；channel proof 是 `.recipeAnchor` 锚 `usePrereleases` 和 `versionPattern`（不能用 artifact proof：beta rule 合法地会解到正式版资产）
- **不带编号的 `-beta` 副本（2.9.1-beta、2.9.0-beta、2.8.0-beta …，56 个 prerelease 里 23 个是这个形状）读成 stable**：第 4 步只认 `-beta.N`。它们由 stable rule 回答：同一个 base 的正式版发了就提示升级（2.9.1-beta 实测 → 2.9.1），这和厂商一致；但在下一个正式版之前，它们看不到后续的 `-beta.N`（例如装着 2.10.0-beta 时 2.10.0-beta.2 发布，stable rule 给的 2.9.1 比它旧，行上是 up to date）。不会被推错版本，只是少提示。要补上，需要在 `ReleaseChannel.detect` 里按 bundle id 加一个分支认 `-beta` 不带编号的形状（CotEditor 的 0.9 那种），这是引擎改动，本次没做 → 「建议下一步」
- **开着 beta 开关的正式版副本读成 stable**：我们只给正式版，厂商自己会给 beta。方向是安全的（不会给没要 beta 的人推 beta）。要补上需要一个 `ChannelBinding` 读 `config.json` 的 `settings.allowBetaVersions`（引擎改动，没做）

## 更新检测
- 源: `heyman/heynote` GitHub Releases。stable rule 读 `/releases/latest`；beta rule 读 release 列表（默认 `listPageSize` 20；109 个 release 全部匹配，首个命中在第 0 位，`GitHubListPageSizeTests` 记的下限是 1）
- 版本方案: tag `v2.9.1` → `CFBundleShortVersionString` `2.9.1`、`CFBundleVersion` `2.9.1`；beta 包两个字段都原样带后缀
- stable `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定：`v2.9.1-beta`、`v2.9.0-beta.6` 不匹配；`v3.0.0`、`v3.0` 匹配）
- stable install pattern `^Heynote_[0-9]+(?:\.[0-9]+)+_universal\.dmg$`；beta install pattern 在版本段后多一个可选的 `-beta(\.N)?`。同 release 里的 `_arm64` / `_x64` dmg、zip、`.blockmap`、`latest*.yml`、`.exe` / `.snap` / `.AppImage` 都不匹配
- `latest-mac.yml`（v2.9.1）列了 6 个文件，`releaseDate` 2026-06-24（release 本身 2026-07-15 发布）；它不是我们的源，只供参考

## 按架构 / 按 OS 分轨
- 每个 release 有 universal（`x86_64 arm64`）、arm64、x64 三份 dmg 和 zip；rule 装 universal。`LSMinimumSystemVersion` 12.0；release 不声明 OS 上限
- electron-updater 在 mac 上下载 zip，按本机架构挑：arm64 机器挑名字带 `arm64` 的 zip（2.9.1 `app.asar` 里打包的 `MacUpdater` 代码：`uname -a` 含 ARM 或 `process.arch === "arm64"` 时只留 URL 含 `arm64` 的文件，再 `findFile(…, "zip")`）。所以本机若是 universal 副本，让厂商自己更新后会变成 arm64 副本；brew 装的本来就是 arm64 / x64 副本。我们一键装 universal，功能上等价（上面比过，只差架构）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 的 blockmap 差分下载） | 有 `.blockmap` | 不需要 |
| 证据 | `app.asar` 的 `dist-electron/main/index.js` 里打包了 electron-updater（含 `MacUpdater`、`DownloadedUpdateHelper`） | v2.9.1 每个 dmg / zip 旁都有 `.blockmap`（2026-10-26 `gh api releases/latest`） | blockmap 是按块复用旧 zip 的下载优化，不是 Sparkle 二进制补丁；我们整包下载 dmg，有 GitHub `digest` 校验 |

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 2026-10-26 运行中一轮：2.9.0 启动后约 36 s（21:20:06 起运行，21:20:42 前）它的 electron-updater 在 `~/Library/Caches/heynote-updater/pending/` 停放了 `Heynote_2.9.1_arm64.zip` 和 `update-info.json` | 能，且 duo 让路（见一键安装） |
| 证据 | 默认 `autoInstallUpdates` true → `autoDownload` 和 `autoInstallOnAppQuit` 都开；下载落在 `~/Library/Caches/heynote-updater/pending/`，完成后写 `update-info.json`，再交给 Squirrel.Mac（ShipIt）退出时装 | — | `SelfUpdaterStash` 读 `app-update.yml` 的 `updaterCacheDirName`（这里是 `heynote-updater`）下的 `pending/update-info.json`，不需要按 app 加东西 |

- 记录文件与字段: `update-info.json`（electron-updater 的 `DownloadedUpdateHelper.setDownloadedFile`，下载完成后才写；摘要是 sha512 base64，读自 2.9.1 `app.asar` 里打包的代码）
- 容器: zip，包根是 `Heynote.app`；arm64 机器上会是 `Heynote_<v>_arm64.zip`（见上）
- 两份副本会不会共用这个目录: 会（缓存目录名不带路径），`SelfUpdaterStash` 的「唯一认领者」闸处理这种情况

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 2.9.0 起）: `source structured: 1 entries; newest 2.9.1: 4 items, headings ["What\'s Changed", "Merged PRs"]; first items ["Fix issue with the Heynote window ending", "Fix so that library search works better ", "Fix restoring windows from disconnected "]`
- 标题保留、没被压平。v2.9.1 正文 `## What's Changed` 2 条 + `## Merged PRs` 2 条 = 4；`**Full Changelog**` 按设计丢掉
- v2.9.0 的正文是 `### <功能名>` 下面整段文字（Sidebar、Search、Archive Scratch），再加 `### Other changes` 列表。纯段落的小节解析器多半会丢（massCode 见过同样的形状）；这一版的 pane 输出没核（channel-verify 只显示最新一条），未验证
- 跟随 channel: beta rule 读的也是 GitHub 正文；beta 的正文同样是 `## What's Changed` 列表
- 厂商另有 `heynote.com/docs/changelog/`，没接
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（stable 副本，和 `-beta.N` 副本）；stable 副本真机两轮通过（2026-10-26，本分支 `make cli` 的 duo）
- 端到端（stable 副本；`-beta.N` 副本没在真机上跑）:
  - 第一轮（不运行，2.9.0 从没启动过）: 2.9.0 universal → `duo install` → 2.9.1 universal（x86_64 arm64）、`TeamIdentifier=VY5Y3H438S`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 2.9.0 从 21:20:06 起运行，它的 electron-updater 在 21:20:42 前停放了 `Heynote_2.9.1_arm64.zip` 和 `update-info.json`。`duo install` → `Skipping: Heynote — its own updater already has 2.9.1 staged`（不重复安装）；`duo restart Heynote` → `quit — its own updater applied 2.9.1`，盘上 2.9.1、`codesign` 0，21:21:01 重新拉起。注意换完的 2.9.1 只剩 arm64（厂商更新器下的是 arm64 zip），不再是 universal
  - 终态: 2.9.1（arm64），未运行
- 格式: dmg（`hdiutil imageinfo` 退出码 0），根目录 `Heynote.app`
- 嵌套: `Contents/Frameworks/Heynote Helper.app`、`Heynote Helper (GPU).app`、`(Plugin).app`、`(Renderer).app`，都是 Electron 自己的子进程（`LSUIElement`），随主进程退出；没有 `Contents/Library/LoginItems`、LaunchAgent、root helper、系统扩展
- 签名: 1.0.2、2.9.0、2.9.0-beta.6、2.9.1-beta、2.9.1 都是 Team `VY5Y3H438S`、Notarized Developer ID，Team 没换过
- 校验: GitHub 资产 `digest`。v2.9.1 universal dmg `sha256:4b7525892769a2710fec66d95c96d3eb082634fb139d6df0f744d3347a65d23f`，下载文件 `shasum -a 256` 相同，215742574 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（stable rule 读 `/releases/latest`）；beta rule 读的是 release 列表里最新的一个，即厂商开着 beta 开关时自己会装的那一版，同样人人可从 releases 页手动下载
- 阻塞: 无
- 真机前的注意点（来自源码 / 包内容；除第一条的暂存部分外均未在真机上观察，暂存部分 2026-10-26 实测见上面的「端到端」）:
  - 首启就检查更新（`settings.autoUpdate` 默认 true，立即一次，之后每 8 h），默认**自动下载、退出时安装**。从 2.9.0 启动后会很快往 `~/Library/Caches/heynote-updater/pending/` 下 2.9.1 的 zip，并交给 ShipIt；退出时 ShipIt 会把 2.9.1 装进去。所以第一轮（不运行）要在 2.9.0 从没启动过的状态下做，第二轮会撞上它自己的暂存（同版本；实测 `duo install` 报的是 `Skipping … already has 2.9.1 staged`，不是预想的 `local stash hit`）
  - `allowDowngrade` 是 true：开着 beta 开关的副本关掉开关后，厂商会把它降到 `/releases/latest`；关着开关的 beta 副本同理
  - 首启会调 `app.setLoginItemSettings({openAtLogin: false})`（`settings.openAtLogin` 默认 false，`ready` 时总会调一次），不会加登录项；Dock 图标默认显示（`showInDock` true，关掉时 `app.dock.hide()`）；全局快捷键默认关（`enableGlobalHotkey` false）；菜单栏图标默认关
  - Info.plist 没有 `CFBundleURLTypes`、`CFBundleDocumentTypes`，不抢默认打开方式、不注册 URL scheme
  - 数据写在 Electron `userData`（`config.json`；`bufferPath` 为空（默认）时笔记库也在 `userData` 下的子目录，1.x 的 `buffer.txt` 由新版首启自己迁移并留备份）和 `~/Library/Logs`（electron-log）；`main.js` 里没有 `~/.claude`、`~/.codex`、`~/.agents`、`LaunchAgents` 字符串（推断不写别的工具的配置，未在真机验证）
  - Info.plist 声明了摄像头、麦克风、蓝牙的用途说明（Electron 模板默认），首启不一定会弹

## 已知问题
- 不带编号的 `-beta` 副本读成 stable：在下一个正式版之前看不到后续 beta（不会被推错版本）。需要引擎改动
- 开着 beta 开关的正式版副本只被提示正式版；厂商自己会给 beta。需要 `ChannelBinding`（引擎改动）
- v2.9.0 那种纯段落的功能小节在 changelog 里可能被丢（未验证）

## 如何复验
```bash
gh release download v2.9.1 -R heyman/heynote -p 'Heynote_2.9.1_universal.dmg'
gh release download v2.9.0 -R heyman/heynote -p 'Heynote_2.9.0_universal.dmg'
gh release download v2.9.0-beta.6 -R heyman/heynote -p 'Heynote_2.9.0-beta.6_universal.dmg'
gh release download v2.9.1-beta -R heyman/heynote -p 'Heynote_2.9.1-beta_universal.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Heynote_2.9.0_universal.dmg   # com.heynote.app, Team VY5Y3H438S, Notarized
swift run --package-path application-test feed-discover Heynote_2.9.1_universal.dmg      # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Heynote_2.9.0_universal.dmg --expect stable        # GitHub, UPDATE → 2.9.1
swift run --package-path application-test channel-verify Heynote_2.9.1_universal.dmg --expect stable        # up to date
swift run --package-path application-test channel-verify Heynote_2.9.0-beta.6_universal.dmg --expect beta   # GitHub, UPDATE → 2.9.1
swift run --package-path application-test channel-verify Heynote_2.9.1-beta_universal.dmg                   # 读成 stable, UPDATE → 2.9.1
```

channel-verify 原始输出（2026-10-26）:
```
2.9.0 dmg:        detected channel → stable; winning source GitHub; latest 2.9.1;
                  download https://github.com/heyman/heynote/releases/download/v2.9.1/Heynote_2.9.1_universal.dmg;
                  status UPDATE → 2.9.1
2.9.1 dmg:        winning source GitHub; latest 2.9.1; status up to date
2.9.0-beta.6 dmg: detected channel → beta; winning source GitHub; latest 2.9.1; release history 20 entries;
                  download …/v2.9.1/Heynote_2.9.1_universal.dmg; status UPDATE → 2.9.1
2.9.1-beta dmg:   detected channel → stable; winning source GitHub; latest 2.9.1; status UPDATE → 2.9.1
```

## 建议下一步
1. （已做，2026-10-26，两轮结果见「一键安装」）
2. 不带编号的 `-beta` 副本: `ReleaseChannel.detect` 按 bundle id `com.heynote.app` 认 `[0-9]+(\.[0-9]+)+-beta(\.[0-9]+)?` 为 beta（CotEditor 0.9 的形状），之后 beta rule 自然接上（引擎改动，需要决定）
3. 开着 beta 开关的正式版副本: `ChannelBinding` 读 `userData/config.json` 的 `settings.allowBetaVersions`（先在真机上拨开关确认文件路径和写法，引擎改动，需要决定）
