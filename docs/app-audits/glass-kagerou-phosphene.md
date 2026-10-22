# Phosphene

## 基本信息
- App: Phosphene — 视频壁纸。菜单栏 app（`LSUIElement`），把用户的视频（以及 Wallpaper Engine 的 Steam Workshop 壁纸转成的视频）放进
  「系统设置 → 墙纸」，由系统自己的墙纸管线播放。开源（MIT）
- Bundle ID: `glass.kagerou.phosphene`
- 仓库: `kageroumado/phosphene`
- Team ID: `52K336H235`（Developer ID + 公证）。真包 1.0、1.1、1.11.1、1.11.2 全部同一 Team，`codesign --verify --deep --strict` 通过，
  spctl `Notarized Developer ID`
- 观测版本: 1.11.2（tag `v1.11.2`，资产 `Phosphene-1.11.2.dmg`，`CFBundleVersion` 27）；观测日期: 2026-10-22
- 自更新机制: 1.4 起**会自己下载、暂存、换包**（`Phosphene/SilentUpdates.swift`、`Package.resolved` 在 `v1.4` 才首次出现）：内嵌 [Tiptoe](https://github.com/artginzburg/Tiptoe) over
  [mxcl/AppUpdater](https://github.com/mxcl/AppUpdater)，1.4–1.8 锁定 Tiptoe 1.0.0 / AppUpdater 4.1.1，1.11.1 和 1.11.2 锁定 Tiptoe 1.1.0 / AppUpdater 4.2.1（1.9.0、1.10.x、1.11.0 的锁定版本没有读）。
  1.0 没有更新器；1.1–1.3.0 只有通知式检查（`Phosphene/UpdateCheckService.swift`，源码注释：「It never downloads or installs」，只请求 `releases/latest` 并给出 releases 页链接）。
  检查频率：`v1.4`–`v1.11.1` 的 `checkInterval = 60 * 60 * 24`（每天一次），`v1.11.2` 起 `4 * 60 * 60`（每 4 小时；v1.11.2 的 release 说明：「Phosphene checks for updates every four hours」）。
  没有 Sparkle、没有 `SUFeedURL`。细节见「已停放整包」
- 分发: GitHub Releases；Homebrew cask `phosphene`（url 即 GitHub 资产，`auto_updates` 未设，`depends_on macos >= 26`）；
  官网下载链接 `kagerou.glass/get/phosphene` 302 到同一个 GitHub 资产。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（cask 装的副本走 brew） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify：`winning source GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（真包读取）:
  - v1.0（`Phosphene.dmg`）: `glass.kagerou.phosphene`，Team 52K336H235，short `1.0`，universal，二进制里没有 GitHub 更新地址（还没有自更新器）
  - v1.1（`Phosphene-1.1.dmg`）: 同 id、同 Team，short `1.1`，**arm64 only**，二进制已引用 `api.github.com/repos/kageroumado/phosphene/releases/latest`（这是 1.1–1.3.0 的通知式检查的地址，不是下载器；AppUpdater 请求的是 `/releases`）
  - v1.11.1、v1.11.2: 同 id、同 Team，short 与 tag 一致，universal
  - 没有换过 bundle id，也没有换过 Team，安装闸不会拒旧副本。cask 的 zap 列了一个旧的扩展容器
    `glass.kagerou.phosphene.wallpaper-extension`，那是内嵌扩展的 id，不是主 app 的，不影响检测
- 其他轨: 无。19 个 release 全部非 prerelease、非 draft，没有 beta/nightly tag；`SilentUpdates` 没改 AppUpdater 的 `allowPrereleases`（默认 false）
- 同 bundle id 下的其他产品: 无。release 资产每个版本只有 Phosphene 的 dmg（v1.8 的两个资产 GitHub digest 相同，是同一个包的两个名字）
- 主机下限: Phosphene 自己要 macOS 26（`LSMinimumSystemVersion` 26.0，1.0 起都是），高于我们的 15.0，能装上它的机器我们都能跑；无需 `hostRequirement`

## Channel 详情

只有 stable。tag 全是 `vX.Y` / `vX.Y.Z`：v1.0 v1.1 v1.1.1 v1.2 v1.2.1 v1.2.2 v1.3.0 v1.4 v1.4.1 v1.5 v1.6 v1.7 v1.8 v1.9.0 v1.10.0 v1.10.1 v1.11.0 v1.11.1 v1.11.2。

## 更新检测
- 源: `kageroumado/phosphene` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.11.2` → `CFBundleShortVersionString` `1.11.2`、`CFBundleVersion` `27`；两段式 tag（`v1.8`、`v1.0`）的 short 也是两段（1.0、1.1 真包实测）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读全部 19 个 tag；锚定，`v1.12.0-rc.1` 这类不会被读成 1.12.0；下一个大版本 `v2.0` 也能读
- install pattern `^Phosphene-[0-9]+(?:\.[0-9]+)+\.dmg$`。分诊说「v1.0 没有资产」不对：v1.0 有一个 `Phosphene.dmg`（4,363,474 字节），
  只是名字里没版本号、不匹配。规则只装 `/releases/latest` 的资产，所以只有 v1.0 重新成为 latest 才有影响，不扩 pattern。
  v1.8 有两个 digest 相同的资产 `phosphene-1.8.0.dmg` 和 `Phosphene-1.8.dmg`，同理与现在的安装无关
- 实测（2026-10-22，channel-verify，真包）:
  - 1.11.1 → `detected channel stable`，`winning source GitHub`，`latest 1.11.2`，`status UPDATE → 1.11.2`
  - 1.11.2 → `latest 1.11.2`，`status up to date`
  - 1.0 → `latest 1.11.2`，`download …/v1.11.2/Phosphene-1.11.2.dmg`，`status UPDATE → 1.11.2`

## 按架构 / 按 OS 分轨
- 架构: x86_64 arm64（universal；1.1 只有 arm64）。`LSMinimumSystemVersion` 26.0，release 不声明上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | AppUpdater 只下整个 dmg（`prepareUpdate` → `NetworkTransfer.download`） | 每个 release 只有 dmg；channel-verify `deltas 0` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（自动安装默认开） | 2026-10-22 真机运行 1.11.1 约 80 s，没停放（`/Applications/.app-updater-*` 没出现） | ○ 需要引擎加一种停放位，不做 |
| 证据 | 见下，读自 v1.11.2 源码和它锁定的 Tiptoe / AppUpdater 版本 | — | 没有完成记录文件；停放的 dmg 文件名只有 UUID |

怎么停放（源码，未在真机上看）:
- `PhospheneManager` 注册默认值 `autoInstallUpdates = true`、`launchAtLogin = true`；启动时 `SilentUpdates.start(autoInstall:)`。
  每 4 小时、以及打开菜单 / 唤醒后（距上次超过 1 小时）向 `api.github.com/repos/kageroumado/phosphene/releases` 查一次（这是 1.11.2 的行为；1.4–1.11.1 是每天一次，见基本信息）
- 有新版且自动安装开着时，AppUpdater 把 `Phosphene-<version>.dmg` 下到 `$TMPDIR/app-updater-<UUID>/`，校验 Team ID，
  再**拷到 app 旁边**成为隐藏文件 `.app-updater-<UUID>.dmg`（`/Applications` 下），只读挂载到 `$TMPDIR/app-updater-<UUID>/mounted`，
  然后交给 Tiptoe 等「安静时刻」
- Tiptoe 的默认策略（`QuietPolicy.default`）: 无任何输入 120 s 且 app 没有可见窗口才装；等满 48 h 降到 30 s，7 天降到 5 s。
  装法是把 `Phosphene.app` 改名成 `.app-updater-backup-<UUID>.app`、拷入新包、拉起新进程、退出自己，然后删掉备份和那份 dmg
- 待装的那份只存在于进程内存（`TiptoeGitHub.waiting`）；UserDefaults 里只记 `Tiptoe.pendingVersion` 等元数据。退出就丢，
  下次启动再查再下。那份隐藏 dmg 和挂载在退出后是否留下没有核实

和我们的交互:
- **它会和我们抢吗**: app 不运行时不会。运行中时会：我们换完包、用户还没重启前，旧进程手里可能还握着一份准备好的安装。
  它装之前只校验磁盘上那份的 Team / 签名标识 / bundle id（`PreparedInstallation.installAndRelaunch` → `driver.validate`），
  **不比版本**。所以:
  - 握着的是同一版（最常见：它和我们读的是同一个 latest）: 下一个安静时刻它把同版本再装一遍并重启 app，结果无害
  - 握着的是比我们装的旧的一版（新版发布后它要等下一次检查才会再查：1.11.2 起最多 4 小时，1.4–1.11.1 最多约一天）: 它会把我们装的新版换回旧版，重启后再查到新版、再自己升上来。
    厂商在 1.11.2 的说明里承认过同类问题（「Update Now」会装上它一直握着的上一版）
- 上面按 AppUpdater 4.2.1 读的源码；1.4–1.8 锁定的是 4.1.1，那个版本的 `installAndRelaunch` 没有读，是否也不比版本未验证。
- 判断: 这是厂商自己的更新器在它自己的窗口里的行为，结果自愈，不伤数据，不加 `OneClickGate`。真机第二轮专门看它（见「一键安装」）

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: ✓。channel-verify `changelog pane`: `source structured: 1 entries; newest 1.11.2: 3 items, headings []`，
  前三条即正文的三个列表项
- 用生产解析器（`GitHubMarkdownParser.parse`）跑了四个真实正文（临时探针，已删）:
  - 列表式（1.11.2、1.11.1、1.9.0）: 只取列表项；开头的 `**Download:** [Phosphene-x.dmg](…)` 段和 1.11.1 的 `# Phosphene 1.11.1` 标题被丢掉，正好
  - 纯段落式（1.11.0，两个 `##` 小节、没有列表）: 走 prose 那一轮，**两个小节标题都保留成 heading**（`Wallpaper Engine wallpapers`、`A new library window`），
    但开头的 `**Download:**` 链接段和末尾的商标声明也各成一条
- Recipe 状态: 不需要。1.11.0 那种正文多两条杂项，没有加 recipe 去掉

## 一键安装
- 状态: 支持
- 端到端（2026-10-22，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 1.11.1 → `duo check` `1.11.1 → 1.11.2 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.11.2、可执行文件 inode 变、`TeamIdentifier=52K336H235`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.11.2 包相同
  - 第二轮（运行中，先 `defaults write … launchAtLogin -bool false`，自动安装保持默认开）: 启动后 60 s 内它没下载也没停放；`duo install` → `Still running the old code`，`duo restart Phosphene` 后新进程起来，之后 10 s 磁盘一直是 1.11.2、签名有效。「它握着的准备安装在安静时刻再装一遍」这次没造出来
  - 墙纸 `Index.plist` 前后字节相同（Provider 仍是 `default`）；`sfltool dumpbtm`（前后都是 229 条）里没有 phosphene；`~/Library/LaunchAgents` 不变
  - **发现（2026-10-22 复核后更正）**: 墙纸扩展 `PhospheneExtension`[50738] 是 15:38:47 由 WallpaperAgent 从 `/Applications/Phosphene.app/Contents/Extensions/PhospheneExtension.appex` 拉起的（系统日志 `com.apple.extensionkit:launch` 与 `launchd … Successfully spawned PhospheneExtension[50738]`），即**当时装着的 1.11.1**，早于 duo 换包。`replaceItemAt` 交换两个 bundle，旧包在被删前处于 `.duoupdater-staged-Phosphene.app`，所以 `lsof` 对仍映射着的旧二进制显示这个路径。换包后这个扩展进程**继续跑 1.11.1 的代码**（ppid 1，app 退出后仍在），直到它自己退出；`duo restart` 只重启 app，不重启它的扩展。系统随后把扩展登记到 `/Applications/Phosphene.app` 的 1.11.2。之前写的「从 duo 暂存副本拉起、跑的是新版」是错的
- 格式: dmg（ULFO，universal），根目录 `Phosphene.app` + `Applications` 链接 + 背景图
- 校验: GitHub digest 与下载的包一致：1.11.2 `sha256:3d9654302692eaef7c01813061d1a8fff5630d187d1553c7bce429ec5aba6c41`，
  1.11.1 `sha256:d2aef6cf18f031a3c415f1a58d41011e9c8c5599715abeae06285d84a9fe5908`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 嵌套: `Contents/Extensions/PhospheneExtension.appex`（`glass.kagerou.phosphene.extension`，同 Team，ExtensionKit 扩展点 `com.apple.wallpaper`）。
  它不是登录项也不是常驻 agent：由系统墙纸服务加载（`UsageCounting.swift` 注释: 扩展跑在系统的墙纸进程里），README 说 app 退出后照样播放。
  换包后正在播放的扩展是否还跑旧代码、何时换成新的，没有验证；厂商自己的更新器也是同样的整包替换，注释说扩展「keeps playing」
- 其他组件: 无 LaunchAgent、无 helper、无 `Contents/Library/LoginItems`。`main.swift` 有一个「烘焙 Wallpaper Engine 场景」的子进程模式，
  用的是同一个可执行文件，做完就退出
- 阻塞: 无

启动副作用（读自 v1.11.2 源码；2026-10-22 真机核对的已注明）:
- **首次启动就注册登录项**: `launchAtLogin` 默认 true，`syncLaunchAtLogin` 会 `SMAppService.mainApp.register()`（系统可能弹「已添加登录项」通知）。
  启动前 `defaults write glass.kagerou.phosphene launchAtLogin -bool false` 可避免；之后用 `sfltool dumpbtm` 前后比对。真机：预先写了 false，没有登记登录项
- **自动安装默认开**，空闲 120 s 就会自己升级（见上），会把「从 1.11.1 装到 1.11.2」变成它自己装的。
  第一轮（不运行）无关；第二轮要么先 `defaults write glass.kagerou.phosphene autoInstallUpdates -bool false`，要么让它的窗口一直开着
- 墙纸: 不会自己改当前墙纸（`importVideo` 注释: 只导入，选择在系统设置里）。app 装上后系统设置的墙纸面板里大概会出现 Phosphene 一组（README 的截图；装上即出现还是首启后出现，未验证）。真机：当前墙纸没被改。
  菜单里的「Restart Wallpaper Agent」和扩展检测到卡死时会 `killall WallpaperAgent`（`WallpaperPrefsService.swift`、`SpiralRecovery.swift`），测试时别点
- 菜单栏弹出面板会问一次是否参与匿名统计（Digoxin），默认不发
- 没有首启向导窗口；更新后的「What's New」只在它自己升级过（Tiptoe 记了 `justUpdatedTo`）时出现，我们换的包不会触发
- 不往 `~/.claude`、`~/.agents` 写东西（GitHub 代码搜索 `.claude` / `.agents` 无命中）；也不写 LaunchAgents
- 会产生的数据: `~/Library/Preferences/glass.kagerou.phosphene.plist`、`~/Library/Application Support/Phosphene`、
  扩展容器 `~/Library/Containers/glass.kagerou.phosphene.extension`（cask zap 的清单）。真机首启建了偏好、`~/Library/{Caches,HTTPStorages}/glass.kagerou.phosphene` 和扩展容器

推荐的两轮真机步骤:
1. app 不运行: 装 1.11.1 → `duo install glass.kagerou.phosphene` → 磁盘 1.11.2、Team 不变、codesign/spctl 通过、`duo check` up to date
2. app 运行中: 装 1.11.1，先写 `launchAtLogin=false`，保留 `autoInstallUpdates`（默认 true），启动后用 `open phosphene://library` 打开库窗口
   （有可见窗口它就不装），等它下完：`/Applications/.app-updater-*.dmg` 出现、`hdiutil info` 里多一个 `app-updater-*/mounted` 挂载。
   这时它握着的是 1.11.2，与 latest 同版。然后 `duo install` → 1.11.2，关掉库窗口、离开键鼠 2 分钟以上，看旧进程会不会再装一遍
   （进程 PID 变、`.app-updater-backup-*` 闪现），装完磁盘应仍是 1.11.2。
   要造出「握着的版本比 latest 旧」: GitHub 上只有 1.11.2 比 1.11.1 新，没法直接造。可行的办法是只改它读的列表：
   它请求的是 `api.github.com/repos/kageroumado/phosphene/releases`（列表），我们读的是 `/releases/latest`；
   用本机代理把那一个列表 URL 换成去掉 v1.11.2 的版本，让运行中的 1.11.0 握住 1.11.1，再 `duo install` 装 1.11.2，
   看安静时刻后磁盘是不是被换回 1.11.1。这需要本机代理对 api.github.com 做 HTTPS 解密，未试
- 收尾: 退出 app，挪走 `/Applications/Phosphene.app`（和可能留下的 `.app-updater-*`），`hdiutil info` 确认没有残留挂载，删登录项

## 已知问题
- 运行中换包后，旧进程握着的准备安装可能在安静时刻再装一遍（同版本无害；旧版本会短暂降级、随后自愈）。见「已停放整包」
- 换包前已被系统拉起的墙纸扩展，换包后继续跑旧版代码直到它退出（见「一键安装」）；`duo restart` 不重启扩展。厂商自己的更新器同样整包替换，结果相同。不改引擎：换个暂存位置也只是把旧包换到那里
- 1.11.0 那种纯段落正文，changelog 里多一条下载链接和一条商标声明

## 如何复验
```bash
gh release download v1.11.2 --repo kageroumado/phosphene --pattern 'Phosphene-1.11.2.dmg' -D v1.11.2
gh release download v1.11.1 --repo kageroumado/phosphene --pattern 'Phosphene-1.11.1.dmg' -D v1.11.1
.claude/skills/coverage-discovery/scripts/check-bundle.sh v1.11.2/Phosphene-1.11.2.dmg v1.11.1/Phosphene-1.11.1.dmg
swift run --package-path application-test channel-verify v1.11.1/Phosphene-1.11.1.dmg --expect stable   # UPDATE → 1.11.2
swift run --package-path application-test channel-verify v1.11.2/Phosphene-1.11.2.dmg --expect stable   # up to date
# 自更新器: v1.11.2 的 Phosphene/SilentUpdates.swift、PhospheneManager.swift（默认值）；
# Package.resolved 锁定的 Tiptoe a48f105 (1.1.0) 的 Sources/TiptoeGitHub/、mxcl/AppUpdater a2b8989 (4.2.1) 的 AppUpdater.swift
```
