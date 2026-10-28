# Rclone UI

## 基本信息
- Bundle ID: `com.rclone.ui`（1.x 为 `com.stray.app`，见「旧 bundle id」）
- 仓库: `rclone/rclone-ui`（原 `rclone-ui/rclone-ui`，旧地址重定向过来）；Apache-2.0
- Team ID: `8FT82R3S6A`（FF Vision SRL）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.7.5（tag `v3.7.5`，资产 `Rclone.UI_aarch64.dmg`）；观测日期: 2026-10-28
- 自更新机制: tauri-plugin-updater，读 `https://github.com/rclone-ui/rclone-ui/releases/latest/download/latest.json`（源码 `src-tauri/tauri.conf.json`，1.9.3 的可执行文件里也是这个地址）
- 分发: GitHub Releases；Homebrew cask `rclone-ui`（`auto_updates true`，`HomebrewCaskSource` 让给别的源）；没有 MAS 版

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（auto_updates） | — | ✓     | —           |

当前生效源: **GitHub**（channel-verify 实测 `winning source  GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（都读自真包）:
  - v3.7.5、v3.7.4、v2.2.0、v2.0.0: `com.rclone.ui`，Team 8FT82R3S6A，notarized
  - v1.9.3、v1.9.0、v1.4.0、v1.0.2: `com.stray.app`，同一 Team，notarized → `BundleIDMigration`
  - v0.9.4、v0.9.5 也发了 dmg（`Rclone.UI_0.9.x_aarch64.dmg`）；0.9.5 读过：`com.stray.app`，同一 Team，notarized，同样走 `BundleIDMigration`（0.9.4 没读）
- 其他轨: 2.7.x 有 6 个 prerelease（v2.7.6–v2.7.24，2025-10-24 至 2025-11-01），同一个 bundle id、同一个资产名；之后再没有 prerelease，稳定版早已超过它们。装着这些 beta 的副本按 stable 检测，会收到更新的稳定版，不会降级
- 同仓库的另一产品: `cloud-v0.1.0` / `cloud-latest` 是 Rclone Cloud（命令行，没有 dmg），`versionPattern` 读不出它的 tag
- 主机下限: 资产只取 `aarch64`，和 `App/project.yml` 的 arm64 一致；`LSMinimumSystemVersion` 10.13，低于我们的下限

## 旧 bundle id
1.0.2、1.4.0、1.9.0、1.9.3 的 dmg 都是 `com.stray.app`，2.0.0 起是 `com.rclone.ui`，同一个 Team。1.9.3 自带的 Tauri 更新器读的是现在指向 3.x 的同一份 `latest.json`，所以厂商自己就把 1.x 当普通更新升到 2.x 以上。2.0.0 的发布说明把改 id 列为 breaking，提醒先备份配置。Tauri 的数据目录跟着 id 走（`~/Library/Application Support/com.stray.app/`），2.0.0 起的代码里没有迁移旧目录的逻辑（v1.9.3 源码 `lib/rclone/common.ts` `getConfigPath`、`lib/store.ts`）。留在旧目录、换包后看不到的有：应用里新建的配置（`configs/<id>/rclone.conf`，含 remote 的凭据）、`store.json` 里的 license key、定时任务、加密配置的密码。只有「Default config」在 rclone 自己的默认路径，不受影响。文件不会被删，只是 3.x 不读。厂商自己的 1.9.3 更新器弹框也没有任何提醒。WhatCable、Cork 改名时设置也会重置，按普通改名登记；这里目前同样登记为：`BundleIDMigration(from: "com.stray.app", to: "com.rclone.ui", lastFromVersion: "1.9.3", firstToVersion: "2.0.0")`，不标 `isRewrite`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.rclone.ui` | — | — | — | ✓ |

源码里没有 beta 开关：`tauri.conf.json` 只配了一个 updater 端点。

## 更新检测
- 源: `rclone/rclone-ui` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.7.5` → `CFBundleShortVersionString` `3.7.5`、`CFBundleVersion` `3.7.5`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`，能读 91 个稳定 tag 里的 89 个，读不出的两个就是 `cloud-…`
- install pattern `^Rclone\.UI_aarch64\.dmg$`；同一发布里还有 `Rclone.UI_x64.dmg`（Intel）和给 Tauri 更新器用的 `Rclone.UI_aarch64.app.tar.gz`，都不选
- 1.9.1 及更早的 dmg 名带版本号（`Rclone.UI_1.9.0_aarch64.dmg`），1.9.2 起是固定名；规则只读 `/releases/latest`，不需要匹配旧名
- channel-verify（2026-10-28）:
  - 3.7.4 dmg: `detected channel → stable`，`winning source GitHub`，`latest 3.7.5`，`status UPDATE → 3.7.5`
  - 3.7.5 dmg: 同上，`status up to date`

## 按架构 / 按 OS 分轨
- 架构: arm64 资产单独发；`LSMinimumSystemVersion`: 10.13；发布正文和 `latest.json` 都没写 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | tauri-plugin-updater 只下整包 `.app.tar.gz` 并验 minisign 签名 | v3.7.5 的 26 个资产里没有补丁文件 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | — |
| 证据 | 源码 `main.ts` `installUpdate`: 启动时先弹框问，点 Update 后 `downloadAndInstall()` 下完立刻原地替换，再 `relaunch()` | 第二轮启动 3.7.4 后，`~/Library/Caches`、`Application Support`、`Containers` 下没有新的 >8 MB 文件 | 没有可拿的 |

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: `changelog pane  source structured: 1 entries; newest 3.7.5: 2 items, headings []; first items ["Bug squashing & improvements.", "**See the assets to download this versio"]`
- 内容: 厂商每个版本的正文几乎都是同一段（"Bug squashing & improvements." 加下载表），读过的 3.7.0、3.7.5 都是这样，所以面板结构化了，但没有实质的更新内容可显示。这是厂商没写，不是解析问题；2.0.0 这类大版本正文有真实条目
- 跟随 channel: 只有 stable
- Recipe 状态: 不需要（没有别的地方发更详细的说明）

## 一键安装
- 状态: 支持
- 端到端（2026-10-28，macOS 27.2 虚拟机里，用本分支构建的 `duo`）:
  - 第一轮（不运行）: 3.7.4 → `duo install 'Rclone UI' --yes --json` → `outcome installed`，`bytesDownloaded 23926396`，10.6 s；装完 3.7.5，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted（Notarized Developer ID，8FT82R3S6A），和厂商 dmg 里的 bundle `diff -r` 相同，`duo check` 显示 up to date
  - 第二轮（运行中）: 3.7.4 启动后，`duo install` 8 s 装好 3.7.5，`duo restart` 后磁盘上 10 s 内一直是 3.7.5，没有被换回去；但见「已知问题」里 rclone 守护进程那一条
- 格式: .dmg
- 嵌套 / 常驻组件: bundle 里没有嵌套 app；运行时会起一个 `rclone rcd`，二进制在 `~/Library/Application Support/com.rclone.ui/rclone-versions/<版本>/rclone`，不在 bundle 里，换 bundle 不影响它的代码
- 校验: GitHub digest，3.7.5 `sha256:f2f315d8…1f481d`、3.7.4 `sha256:e16925fe…1e74` 都和下载的包一致
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

## 已知问题
- **用系统的退出事件关掉应用时，`rclone rcd` 不会跟着退出。** 应用自己菜单里的退出走 `CLOSE_APP`，会先杀守护进程；但 `tell application id "com.rclone.ui" to quit` 这种 AppleEvent 退出、或 ⌘Q 退出后（Dock 的「退出」没测），`rclone rcd` 变成孤儿进程（ppid 1），继续监听 127.0.0.1:5572。2026-10-28 在虚拟机里用 3.7.5 测了三次：`duo restart`、直接发 AppleEvent、⌘Q，结果一样。根因是 `src-tauri/src/lib.rs` 里 `app.run` 的退出回调是空的，git 历史里看不出是有意的。之后新启动的 Rclone UI 会弹「Rclone Already Running」，有 Exit UI / Close Rclone 两个按钮，点 Close Rclone 后正常运行。厂商自己的更新器不会碰到这个问题，因为它在启动时、守护进程还没起来之前就更新完并重启了。所以运行中一键更新后，用户要多点一次 Close Rclone；不运行时一键更新不受影响。
- 首次启动时，应用会通过 `osascript … with administrator privileges` 请求管理员密码，要把 `rclone` 链接到 `/usr/local/bin`。这和一键更新无关；取消后应用照常运行。

## 建议下一步
1. 运行中一键更新后的「Rclone Already Running」弹框：已向上游提修复 [rclone/rclone-ui#253](https://github.com/rclone/rclone-ui/pull/253)（`RunEvent::Exit` 时结束守护进程；虚拟机里 AppleEvent、⌘Q、`duo restart`、托盘 Quit 都验过）。合进去并发版后复测一次运行中一键，把上面那条已知问题标成从哪个版本起修好。2026-10-28 定的是走上游修复，我们这边先不加「退出前先结束子进程」的机制
2. 厂商以后要是在发布正文里写了真实的更新内容，面板会自动显示，不需要 recipe

## 如何复验
```bash
gh release download v3.7.5 --repo rclone/rclone-ui --pattern 'Rclone.UI_aarch64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Rclone.UI_aarch64.dmg
swift run --package-path application-test channel-verify Rclone.UI_aarch64.dmg --expect stable
# 旧 bundle id：v1.9.3 是 com.stray.app，v2.0.0 是 com.rclone.ui
gh release download v1.9.3 --repo rclone/rclone-ui --pattern 'Rclone.UI_aarch64.dmg'
# 守护进程变孤儿：先启动应用，等 rclone rcd 起来，再执行
osascript -e 'tell application id "com.rclone.ui" to quit'; sleep 5; ps -axo pid,ppid,command | grep 'rclone rcd'
```
