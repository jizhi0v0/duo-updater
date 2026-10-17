# Jellyfin Server

开源媒体服务器 Jellyfin 的 macOS 包装（`Jellyfin.app`，源码 `jellyfin/jellyfin-server-macos`）：
一个 `LSUIElement` 菜单栏启动器，把包内的 `jellyfin` 服务端作为自己的子进程拉起。
Homebrew cask `jellyfin`。

## 基本信息
- Bundle ID: `Jellyfin.Server`（10.7.7、10.8.0、10.11.11、12.0-rc7、12.1、12.2 真包全部相同；源码工程自 2020 年起就是这个 id）
- Team ID: `6YC6EAV7ES`（Developer ID Application: Anthony Lavado；上述六个包全部相同）
- 观测版本: short `12.2`, build `12.2`（2026-10-16，arm64 dmg）
- 自更新机制: 无（启动器源码 `AppDelegate.swift` / `ActionManager.swift` 里没有任何更新检查）
- 开源: 是，启动器 `jellyfin/jellyfin-server-macos`，服务端 `jellyfin/jellyfin`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓ 仅 brew 装的副本（cask 无 `auto_updates`） | — | ✗ 无 macOS asset | ✓ 检测 + 一键 |
| **rc**       | —       | —        | —   | —      | ○（rc 副本读作 stable，见 Channel 详情） |
| **unstable** | —       | —        | —   | —      | — 只发 tar.xz 服务端目录，不是 .app |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**（`channel-verify` 全链 `winning source Vendor`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `Jellyfin.Server` | — | — | `latest-stable/arm64/` 索引 | ✓ |
| rc      | `Jellyfin.Server` | 共享 | 版本串 `12.0-rc7`（`detect()` 目前读作 stable） | `preview/v<ver>-rcN/` 目录，无 latest 别名 | ○ |
| unstable | — | — | — | `unstable/<日期号>/`，只有 tar.xz | — |

- 厂商文件树（`repo.jellyfin.org/files/server/macos/`）：`stable/`、`latest-stable/`（= `latest/`）、`preview/`、`unstable/`、`latest-unstable/`。
- rc：真包 `jellyfin_12.0-rc7-arm64.dmg` 是 `Jellyfin.Server`、Team `6YC6EAV7ES`、版本 `12.0-rc7`。`channel-verify` 读作 stable，
  stable recipe 给它终版（`UPDATE 12.0-rc7 → 12.2`），所以 rc 用户在终版发布后会被带回 stable。
  缺口在 rc 窗口期：装着下一大版本 rc 的副本不会被推下一个 rc（`VersionComparator`：`12.2` 不比 `13.0-rc1` 新，测试钉住，不会降级）。
  接 preview 轨要在 `detect()` 加一条只限这个 bundle id 的 `-rcN` 规则，再写一条在 rc 与终版之间取高的 probe；`preview/` 没有 latest 别名，rc 目录在终版后也不删。
  未做，记在 `CHANNEL_COVERAGE_TODO.md`。
- unstable：`jellyfin_2026101212-arm64.tar.xz` 解开是 `jellyfin/` 服务端目录（`tar -tJf` 里 0 个 `.app/` 路径），不是本 app 的可装副本。
- 版本方案：服务端在 12.0 去掉了前导 `10.`（rc7 发布说明原话：`10.11.x` -> `[10.]12.x` = `12.x`），所以 `10.11.11` 之后直接是 `12.0`，两段式。
  `VersionComparator.isNewer("12.2", than: "10.11.11")` 为真，测试钉住。

## 更新检测
- 源: `VendorProbeRecipe`（`Recipes/Jellyfin-Server.swift`），`.responseBody`
- 端点: `https://repo.jellyfin.org/files/server/macos/latest-stable/arm64/`（nginx 目录索引，只放当前一版的 dmg + tar.xz）
- 版本: `href="jellyfin_([0-9]+(?:\.[0-9]+)+)-arm64\.dmg"`。文件名版本 = `CFBundleShortVersionString` = `CFBundleVersion`，不需要 `versionIsBuild`。
  rc（`-rc7-arm64.dmg`）、unstable（纯日期号、tar.xz）、amd64 dmg、tar.xz 都匹配不上；三段式 `10.11.11` 和下一大版本 `13.0` 都能读（测试钉住）。
- GitHub: `jellyfin/jellyfin` 的 release 只有说明、0 个 asset（`gh api …/releases` 列出的 30 条全部 `assets` 为空），GitHub 规则拿不到 macOS 包，所以不走 GitHub 源。
- Homebrew cask `jellyfin`：`auto_updates` 未设（`brew info --json=v2` 为 `None`），版本 `12.2`，URL 即本 recipe 读的 arm64 dmg。
  `HomebrewCaskSource` 只应答 Caskroom 里有这个 cask 的副本（brew 装的）；从官网 dmg 装的副本落到本 recipe。
- 按架构: 厂商分 `arm64/`、`amd64/` 两个 dmg。arm64 dmg 里启动器是 universal，`jellyfin` 服务端只有 arm64。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），所以固定读 arm64。
- 按 OS: 包内 `LSMinimumSystemVersion` = `12.0`（cask `depends_on macos >= 12`），低于本项目的宿主下限，不设 `hostRequirement`。索引不写任何系统版本。
- **读的是**: 轨道最新——也就是下载页和 cask 给所有人的那一个文件，厂商不按机器分配。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 启动器源码（`AppDelegate.swift`、`ActionManager.swift`）没有任何更新逻辑 | 目录里只有整包 dmg 和 tar.xz | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（运行中一轮实测） | — |
| 证据 | 没有自更新器（源码） | — | — |

## Changelog
- 来源: recipe，`api.github.com/repos/jellyfin/jellyfin/releases?per_page=40`，`.gitHubReleases`（只取非 prerelease）
- 结构化: `recipe changelog:Jellyfin.Server:-: 20 entries; newest 12.2: 51 items, headings []; first items ["Replace custom item display preferences ", "Use hvc1 for Dolby Vision profile 8 [PR ", "Make the OwnerId and ExtraType/OwnerId i"]`
  - 51 条正好是发布说明自己写的 `## Changelog (51)`。开头的宣传段被丢掉，不算条目。
  - `headings []`：12.2 只有一个分类标题 `### 📈 General Changes`（`Changelog (51)` 含数字，按 `GitHubMarkdownParser.isVersionLikeHeading` 不算分类），
    低于 `qualifyingHeadings` 的两个门槛，所以不显示——标题被丢掉，不是被压进条目。12.0 这种多分节的版本（`Server` / `Web` / `Security` …）会保留标题。
- 跟随 channel: 否（只有 stable 一条；rc 是 GitHub prerelease，被跳过）
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（Team-ID 闸）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：12.1 → 12.2，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（ULFO，无 SLA：`hdiutil imageinfo` 报 `Software License Agreement: false`）
- URL: `.versionTemplate("https://repo.jellyfin.org/files/server/macos/stable/v{version}/arm64/jellyfin_{version}-arm64.dmg")`——用比较过的版本号拼不可变的按版本目录，
  不用会随下一版移动的 `latest-stable/` 别名。文件服务器 302 到地理镜像（如 `sfo1.mirror.jellyfin.org`）。
- 校验: 不接。`stable/`、`latest-stable/` 目录里只有 dmg 和 tar.xz，没有摘要文件（`.sha256sum` 只在 `archive/` 下的老版本里有）。
- Team: 12.2 与上一版 12.1 都是 `6YC6EAV7ES`、`spctl` `Notarized Developer ID`；更早的 10.11.11、10.8.0、10.7.7 也是同一个 Team，所以旧副本不会被 Team 闸拒。
- **读的是**: 轨道最新（同时是下载页、cask 人人可手动下载的那个文件）。
- 运行中的服务（读源码得出，未在真机上量）:
  - 主 app 本身是 `LSUIElement` 菜单栏程序，没有嵌套 .app；`Contents/Resources/LaunchAtLogin_LaunchAtLogin.bundle` 是资源包，不是 helper。
  - 服务端 `Contents/MacOS/jellyfin` 是启动器用 `Process` 拉起的子进程，不是 `NSRunningApplication`。
    `applicationWillTerminate` 里 `jellyfinProcess.terminate()` + `waitUntilExit()`，所以优雅退出启动器（`AppRestarter` 用 `terminate()`）会先停服务端。
  - 换包之后、重启之前，旧服务端继续从被挪开的旧 bundle 跑；`duo restart` 退出旧启动器（连带停旧服务端）后起新包，新启动器拉起新服务端。
  - 登录启动：macOS 13+ 走 `sindresorhus/LaunchAtLogin` 包（包内没有 `Contents/Library/LoginItems` helper，`find` 无嵌套 .app）；
    macOS 12 写 `~/Library/LaunchAgents/Jellyfin.Server.plist`，`ProgramArguments` 是包内 `Contents/MacOS/Jellyfin Server` 的路径（`Helpers.swift` `getLaunchAgentPlist`）。
    原地换包后路径不变。
- 阻塞: 无

## 已知问题
- 大版本升级会迁移服务端数据库（`~/.local/share/jellyfin` 或 `~/Library/Application Support/jellyfin`），这是厂商行为，手动更新也一样，厂商每份说明都要求升级前完整备份。
  DuoUpdater 的备份只备份 app bundle，不备份服务端数据；迁移后回滚到旧 bundle，旧服务端可能遇到新库。
- rc 窗口期 rc 副本不会被推下一个 rc（见 Channel 详情）。

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：12.1 运行中（启动器 + 服务端子进程 `MacOS/jellyfin` 监听 `*:8096`，`/System/Info/Public` 报 `12.1.0`），`duo install --yes` → `installed.` 并提示 `Still running the old code: Jellyfin Server`，换包后旧服务端继续应答 12.1.0；`duo restart` → `restarted`：旧服务端进程退出，新启动器与新服务端都映射 12.2 的二进制，8096 由新服务端监听，`/System/Info/Public` 报 `12.2.0`。Team `6YC6EAV7ES`、`codesign --strict` 0、Notarized。新增 `~/.aspnet`（DataProtection-Keys）、`~/Library/Application Support/jellyfin`、`~/Library/Preferences/Jellyfin.Server.plist`，登录项前后无差异
2. 想接 rc 轨时：`ReleaseChannel.detect()` 加一条 `Jellyfin.Server` 限定的 `^[0-9]+(\.[0-9]+)+-rc[0-9]+$` 规则，probe 读 `preview/` 目录取最高 rc，再和 stable 取高。

## 如何复验

```bash
# 1. 端点
curl -sS https://repo.jellyfin.org/files/server/macos/latest-stable/arm64/

# 2. 生产检测 + changelog（不安装，只读挂载）
swift run --package-path application-test channel-verify jellyfin_12.1-arm64.dmg --expect stable
swift run --package-path application-test channel-verify jellyfin_12.2-arm64.dmg --expect stable

# 3. 签名
codesign -dvv /Volumes/…/Jellyfin.app 2>&1 | grep -E "^Identifier|TeamIdentifier"
spctl -a -vv /Volumes/…/Jellyfin.app
```

2026-10-16 实测:
- `channel-verify jellyfin_12.1-arm64.dmg --expect stable`: `detected channel → stable`、`VendorProbe ✓`、`latest 12.2`、
  `download https://repo.jellyfin.org/files/server/macos/stable/v12.2/arm64/jellyfin_12.2-arm64.dmg`、`verdict UPDATE 12.1 → 12.2`；
  全链 `winning source Vendor`、`status UPDATE → 12.2`。
- `channel-verify jellyfin_12.2-arm64.dmg --expect stable`: `verdict up to date`、`status up to date`。
- `channel-verify jellyfin_12.0-rc7-arm64.dmg`: `detected channel → stable`、`verdict UPDATE 12.0-rc7 → 12.2`。
- 包: 12.2 arm64 dmg 164,659,012 bytes，SHA-256 `f6a4d13c1783667bc9c6c6de1bcec5d8c9537e5143ba44cda899cdf1cff83bc3`；
  12.1 arm64 dmg 164,656,871 bytes，SHA-256 `0665f45616463ed22c6c2ea71c9be3827454308848a574073ef60f025d0939da`。
  两者 `Jellyfin.Server`、Team `6YC6EAV7ES`、`spctl` accepted `Notarized Developer ID`。

## 历史与实测

### 2026-10-16 · 接入

- 下载的老包：`archive/server/macos/stable/10.7.7/installer/Jellyfin_10.7.7.dmg`、`…/10.8.0/installer/jellyfin_10.8.0.dmg`、
  `files/server/macos/stable/v10.11.11/arm64/jellyfin_10.11.11-arm64.dmg`：bundle id 都是 `Jellyfin.Server`，Team 都是 `6YC6EAV7ES`，都没有 SLA。
- 启动器工程 `project.pbxproj` 的 `PRODUCT_BUNDLE_IDENTIFIER` 在 2020-05 的 `d250c87f` 与 2022-08 重写的 `5975c833` 都是 `Jellyfin.Server`；
  工程里的 `MARKETING_VERSION`（2.4.0）不是包里的版本，包里的版本由打包时写入，等于服务端版本。
- 下载 URL 不带 `-L` 时 curl 拿到 0 字节：文件服务器回 302 到镜像，正文为空。
