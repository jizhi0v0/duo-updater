# Open Screen Sharing

## 基本信息
- App: Open Screen Sharing — 基于 Apple VNC 私有协议的屏幕共享客户端（另支持 RDP），GPL-3.0 开源；同一仓库还出 iOS 版（App Store / 侧载 ipa）
- Bundle ID: `io.nekohasekai.screensharing`；装成 `/Applications/Screen Sharing.app`（显示名与系统自带的 Screen Sharing 相同，bundle id 不同）
- 仓库: `nekohasekai/open-screen-sharing`（默认分支 `main`）
- Team ID: `P8XK3KHB48`（Developer ID Application / Installer: Metamerism LLC；app 与 pkg 都公证）
- 观测版本: 1.0.1（`CFBundleVersion` 26）；上一版 1.0.0（24）；观测日期: 2026-10-17
- 自更新机制: 自研（`OpenScreenSharing/Update/`）。读 GitHub API 的 release，下载 `metadata.json` 比 `build` 与本机 `CFBundleVersion`，下载 pkg 后经 `AuthorizationExecuteWithPrivileges` 跑 `/usr/sbin/installer`
- 分发: GitHub Releases（macOS 只有 `OpenScreenSharing.pkg`）。没有 Homebrew cask（README roadmap 里「Publish to Homebrew」未勾）；Mac App Store 上只有 iOS 版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | —        | —   | ✓      | —           |
| **nightly** | —       | —        | —   | ✗      | ○           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 1.0.1 bundle: `no Sparkle, no electron-builder update config and no MyGo feed`。

## Channel 详情

两条轨，settled from source: `OpenScreenSharing/Update/UpdateChecker.swift`、`UpdateManager.swift`、`.github/workflows/{build,release}.yml` on `main`。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.nekohasekai.screensharing` | 共享 | 默认 | `/releases/latest` | ✓ |
| nightly | 同上 | 共享 | 偏好 `updateTrack`（见下） | 固定 tag `nightly` 的 pre-release + `metadata.json` 的 `build` | ○ |

- `UpdateTrack` 只有 `stable` / `nightly`。stable 读 `api.github.com/repos/…/releases/latest`，nightly 读 `…/releases/tags/nightly`。
- 每次 build 把 nightly release 整个覆盖，`build` 号 +1；`CFBundleShortVersionString` 只在作者提交「Bump x.y.z」时变。所以 nightly 的版本序是 `CFBundleVersion`，营销版本对它没有区分力。
- 正式版由 `release.yml` 手动触发：下载当时 nightly 的 pkg / ipa / `metadata.json`，原样发成 `v<version>`。正式版与发版那一刻的 nightly 是同一份字节（2026-10-17：`v1.0.1` 与 `nightly` 的 pkg 都是 sha256 `f5ea7f2b…a88439`，`metadata.json` 都是 `{"version":"1.0.1","build":26}`）。
- 选轨偏好不在 CFPreferences：`PreferenceStore` 是 GRDB，库在 app group 容器 `~/Library/Group Containers/P8XK3KHB48.io.nekohasekai.screensharing/Screen Sharing.sqlite`，表 `preferences(name, data)`，`data` 是 JSON 编码。键 `updateTrack`，值 `"stable"` / `"nightly"`，缺省 stable。2026-10-17 读到该表里有 `checksForUpdatesAutomatically = false`（首启弹框选「Don't Check」写的），证实了表名与 JSON 编码；`updateTrack` 没有在 app 里拨过，`"nightly"` 这个值是按源码 `Codable` 推的，**未在真 app 上取证**。
- bundle 里没有任何字段区分 nightly 构建与正式构建（两者字节相同）。

**nightly 为什么没接（○，不是 ✗）：**
1. GitHub 规则读不了：tag 固定叫 `nightly`，`versionPattern` 读不出版本；版本得从 `metadata.json` 的 `build` 读，再和 `CFBundleVersion` 比，要用 `VendorProbeRecipe`（`versionIsBuild`，`displayVersionPattern` 读 `version`，install 指向 `releases/download/nightly/OpenScreenSharing.pkg`）加一条 `ChannelProofRegistry` 证明。
2. 渠道要靠新写一个读 SQLite 的 `ChannelBinding`。库在别的 Team 的 group 容器里，很可能和 CotEditor 的容器 plist 一样要完全磁盘访问（`FullDiskAccessNeeds` 闸），**未实测**。
3. 未接之前的行为：nightly 副本按 stable 规则判。它的营销版本从不落后于最新正式版（正式版就是更早的某个 nightly），所以只会被报「已是最新」，不会被降级；代价是 nightly 副本看不到新的 nightly 构建。

## 更新检测
- 源: `nekohasekai/open-screen-sharing` GitHub Releases，`/releases/latest`
- 版本: tag `v1.0.1` → `^v([0-9]+(?:\.[0-9]+)+)$` → `1.0.1`，等于 `CFBundleShortVersionString`。`nightly` tag 不匹配
- app 自己比的是 `build` 与 `CFBundleVersion`；正式版之间营销版本单调递增（每次发版前有「Bump」提交），两种比法给同样结论

## 按架构 / 按 OS 分轨
- 一个 pkg，`Distribution` 声明 `hostArchitectures="arm64,x86_64"`
- `LSMinimumSystemVersion` = `14.0`，`PackageInfo` `minimumSystemVersion="14.0"`（1.0.0 / 1.0.1 相同）；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `UpdateChecker.swift` 只下整个 pkg | 两个正式版与 nightly 的资产只有 pkg / ipa / altstore.json / icon.png / metadata.json | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会自动停放 | 无 | 不能（也不需要） |
| 证据 | `UpdateManager.install(_:)` 里下载与安装连在一起，只在用户点了更新框里的安装后发生；下到 group 容器 `Library/Caches/Updates/Screen Sharing <build>.pkg` 后立刻交给 installer | 第二轮启动 1.0.0 后按 T0 diff `~/Library/{Caches,Application Support,Containers,Group Containers}` 下 >8 MB 的新文件：没有属于本 app 的 | `SelfUpdaterStash` 没有这个布局；pkg 不是包根为 app 的归档 |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`。正文是 `release.yml` 用 `git log --format='* %s'` 生成的提交标题列表
- 结构化（2026-10-17，channel-verify `changelog pane`，从 1.0.0 起）: `source structured: 1 entries; newest 1.0.1: 1 items, headings []; first items ["Fixes and improvements"]`。没有小节标题是厂商正文本来就没有，不是被压平
- 跟随 channel: stable 只读正式版正文；nightly 未接
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（系统 Installer 路线，和 XQuartz 一样：下载官方 pkg 交给 macOS，管理员密码由 Installer 自己要）
- 格式: 组件 pkg，无 `Scripts`。`PackageInfo`: `install-location="/Applications"`、`relocatable="false"`、`<bundle path="./Screen Sharing.app" id="io.nekohasekai.screensharing">`；Bom 里以 `.app` 结尾的只有 `./Screen Sharing.app`。没有 LoginItems / Helpers / LaunchAgent
- 架构: pkg 路线没有架构闸，夜扫的 `pkgarch` 也只读 vendor recipe。手量：`Distribution` `hostArchitectures="arm64,x86_64"`，payload 可执行文件 `lipo -archs` = `x86_64 arm64`（1.0.0、1.0.1）；和 XQuartz 一起钉在 `PackageArchitectureProbeTests.thePkgRouteIsExactlyWhatTheDocsSayItIs`
- 签名: pkg `Developer ID Installer: Metamerism LLC (P8XK3KHB48)`，1.0.0 与 1.0.1 相同，都公证；app `TeamIdentifier=P8XK3KHB48`
- Pattern: `^OpenScreenSharing\.pkg$`, kind `.pkg`；不匹配同 release 的 `.ipa`、`altstore.json`、`metadata.json`、`icon.png`
- 校验: GitHub 资产 `digest`。duo 下载到的 pkg `shasum -a 256` = `f5ea7f2b53ce20426825f02e21aae4f98a961489f1ac90e72864a6d216a88439`，等于 v1.0.1 资产的 `digest`；11718841 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 的 macOS 下载链接就是 `releases/latest/download/OpenScreenSharing.pkg`）
- 端到端（2026-10-17，`make cli` 后的 `duo`）:
  - 第一轮（不运行）: 把 1.0.0 pkg 的 payload `ditto` 进 `/Applications` → `duo check` `1.0.0 → 1.0.1 [GitHub, in-place]` → `duo install --yes --json` → `outcome: openedInstaller`、`route: installer`、`bytesDownloaded: 11718841` → 人在 Installer 里输管理员密码完成 → 1.0.1（26），可执行文件 inode 变、属主变 root，`codesign --verify --deep --strict` 通过，`spctl` `accepted / Notarized Developer ID`，Team `P8XK3KHB48`，`diff -r` 与厂商 pkg payload 完全相同，`pkgutil --pkg-info` 有回执，`duo check` 报 up to date
  - 第二轮（运行中）: 再放 1.0.0 并启动 → `duo install` 同样 `openedInstaller` → Installer 完成，进程不需要先退出，磁盘 1.0.1 且与厂商 payload 相同 → `duo restart`：第一次 33 s 后报「still running — likely a save prompt」，原因是首启的「Check for Updates Automatically?」弹框拦下退出；点「Don't Check」后再 `duo restart` 1.7 s 完成，新进程启动时间在安装之后，之后 10 s 磁盘一直是 1.0.1
- 阻塞: 无。pkg 路线每次都要人输管理员密码（系统 Installer 的行为）

## 已知问题
- **首启弹框挡退出。** 第一次启动会弹「Check for Updates Automatically?」，不回答之前 app 不肯退出，`duo restart` 只能报 still running。回答一次后不再出现。
- **装完属主是 root。** pkg 由 installer 以 root 装，之后 `/Applications/Screen Sharing.app` 内容归 root。不影响下一次 pkg 更新；只影响「不经 Installer 换 bundle」的操作。
- **nightly 副本看不到新 nightly。** 见「Channel 详情」。

## 建议下一步
1. 接 nightly 轨：在真 app 设置里把更新轨切到 Nightly，读 group 容器库确认 `updateTrack` 写成 `"nightly"`、切回后写什么；量 DuoUpdater（无 FDA）读这个库会不会被 TCC 拒。然后 `ChannelBinding`（读 SQLite，按需走 `FullDiskAccessNeeds` 闸）+ `VendorProbeRecipe`（`releases/download/nightly/metadata.json`，`"build":([0-9]+)`，`versionIsBuild`，`displayVersionPattern` 读 `version`，install 同目录 pkg）+ `ChannelProofRegistry` 条目。登记在 `CHANNEL_COVERAGE_TODO.md` §2b。
2. 下一个正式版出来后复查 `/releases/latest` 指向它、版本模式读得出。

## 如何复验
```
gh release view v1.0.1 -R nekohasekai/open-screen-sharing --json assets -q '.assets[]|.name+" "+.digest'
pkgutil --check-signature OpenScreenSharing.pkg                              # → Developer ID Installer: Metamerism LLC (P8XK3KHB48), notarized
pkgutil --expand-full OpenScreenSharing.pkg x && cat x/component.pkg/PackageInfo   # → install-location /Applications, bundle io.nekohasekai.screensharing
swift run --package-path application-test feed-discover "x/component.pkg/Payload/Screen Sharing.app"   # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify "<1.0.0 payload>/Screen Sharing.app"          # → stable，winning source GitHub，UPDATE → 1.0.1
swift run --package-path application-test channel-verify "<1.0.1 payload>/Screen Sharing.app"          # → up to date
```
