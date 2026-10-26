# Mailspring

## 基本信息
- Bundle ID: `com.mailspring.mailspring`
- 仓库: `Foundry376/Mailspring`（Electron；同步引擎在 `Foundry376/Mailspring-Sync`）
- Team ID: `X9RJ36K9D4`（Developer ID Application: Ben Gotow）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.26.2（tag `1.26.2`，资产 `Mailspring-AppleSilicon.zip`）；观测日期: 2026-10-26
- 自更新机制: Electron 自带 `autoUpdater`（Squirrel.Mac + ShipIt），不是 electron-updater，包里没有 `app-update.yml`。`src/browser/autoupdate-manager.js`（1.26.2 `app.asar`）：feed 是 `https://updates.getmailspring.com/check/<platform>/<arch>/<version>/<identity id 或 anonymous>/stable`，`channel` 写死 `stable`；在 macOS 上 `process.arch === 'x64'` 且 CPU 型号以 `Apple ` 开头时把 arch 改报成 `arm64`。启动即查一次、之后每 30 分钟查一次（已有下好的更新时跳过）。Electron 文档：`checkForUpdates()` 有更新时自动下载，下好的更新在下次启动时应用（https://www.electronjs.org/docs/latest/api/auto-updater）
- 分发: GitHub Releases；Homebrew cask `mailspring`（`auto_updates true`，url 就是本仓库的 `Mailspring-AppleSilicon.zip`，`depends_on macos >= 13`）；官网下载页 `getmailspring.com/download`；Mac App Store 没有（iTunes lookup `bundleId=com.mailspring.mailspring` resultCount 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗（`auto_updates true`，`HomebrewCaskSource` 让路） | — | ✓ | ○（不需要，见下） |

当前生效源: **GitHub**（channel-verify 实测 `winning source  GitHub`）

厂商更新服务器没有做成 VendorProbe：它返回的下载地址就是本仓库的 release 资产（见「更新检测」），GitHub 规则读到的是同一份字节，还多了 changelog 和资产 digest。

## 覆盖清单
- 各版本的 bundle id / Team（读真包）:
  - 1.26.2 AppleSilicon zip: `com.mailspring.mailspring`，Team X9RJ36K9D4，arm64
  - 1.26.2 `Mailspring.zip`: 同 id、同 Team，x86_64，Notarized；Info.plist 与 arm64 版只差 `ElectronAsarIntegrity` 的 hash
  - 1.26.1 AppleSilicon zip: 同 id、同 Team，arm64，Notarized
  - 1.10.3 `Mailspring.zip`（AppleSilicon zip 出现前最后一版）: 同 id、同 Team，x86_64
  - 1.0.12 `Mailspring.zip`（最老的带 mac 资产的稳定版；1.0.9–1.0.11 没有资产，scaffold 报的 1.0.3 也没有 mac 资产）: 同 id、同 Team，x86_64
  - 没有改过名：所有读过的包都是 `com.mailspring.mailspring`，不需要 `BundleIDMigration`（前身 Nylas Mail 是另一个产品、另一个 id，不在本规则范围）
- 其他轨: 没有。GitHub 上 86 个 release 没有一个标 prerelease；更新服务器只接受 `stable`（`…/1.26.1/anonymous/beta`、`/nightly` 都是 HTTP 400 `Invalid request params input`）；`env=staging` 只换主机 `updates-staging.getmailspring.com`，是厂商内部用的（2026-10-26 探测时 TLS 握手失败，没深究），偏好设置里没有切换入口，不是用户可选的轨
- 同一 bundle id 下的两份构建: 每个 release 同时有 arm64 的 `Mailspring-AppleSilicon.zip`（1.10.4 起）和 x86_64 的 `Mailspring.zip`，区别就是可执行文件的架构（`file Contents/MacOS/Mailspring`：`arm64` / `x86_64`），版本号相同。这是按架构分包，不是两个产品：DuoUpdater 只跑在 arm64 上（`App/project.yml` `ARCHS: arm64`），Apple silicon 上的 Intel 副本走 Rosetta，厂商自己的更新器也会把它换成 arm64 包（见上面的 arch 改报）。所以规则对所有副本都装 arm64 zip，不加闸
- 版本范围: `versionPattern` 读得了 86 个稳定 tag 里的全部 86 个，带锚点，`1.27.0-beta` 这类 tag 读不进来；下一个大版本 `2.0.0` 也读得了
- 主机下限: `LSMinimumSystemVersion` 13.0（cask 同）；低于 DuoUpdater 自己的部署目标，不用写进规则

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mailspring.mailspring` | — | — | — | ✓ |

唯一的轨。证据见「覆盖清单 / 其他轨」。

## 更新检测
- 源: `Foundry376/Mailspring` GitHub Releases，`/releases/latest`
- 版本方案: tag `1.26.2` → `CFBundleShortVersionString` `1.26.2`、`CFBundleVersion` `1.26.2`
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^Mailspring-AppleSilicon\.zip$`（资产名不带版本号；x86_64 的 `Mailspring.zip`、Linux 包、Windows 包都被排除）
- 厂商服务器与 GitHub 对比（2026-10-26，`id` 用 `anonymous`）:
  - `check/darwin/arm64/1.26.1/anonymous/stable` → 200 `{"url":"https://github.com/Foundry376/Mailspring/releases/download/1.26.2/Mailspring-AppleSilicon.zip","name":"Mailspring 1.26.2-4de23b01","version":"1.26.2-4de23b01",…}`
  - `check/darwin/x64/1.26.1/anonymous/stable` → 200，url 是同一 release 的 `Mailspring.zip`
  - `check/darwin/arm64/1.20.0/anonymous/stable` → 同样直接给 1.26.2
  - `…/1.26.2/…` → 204（已是最新）
  - 结论：厂商更新器下载的就是 GitHub 上这个资产，字节相同；它报的 `version` 多一个提交后缀（`-4de23b01`），我们不读这个
- 读的是: 轨道最新 = 人人可手动下载的 GA。没看到灰度：anonymous id 下 1.20.0 和 1.26.1 都直接给最新版；带真实 identity id 的请求没测（未验证）

## 按架构 / 按 OS 分轨
- 架构: 分架构资产。`Mailspring-AppleSilicon.zip` = arm64，`Mailspring.zip` = x86_64；没有 universal 包。`app.asar.unpacked/mailsync` 本身是 universal（x86_64 + arm64），主程序和 `Squirrel.framework` 是单架构
- `LSMinimumSystemVersion`: 13.0；更新服务器的响应里没有系统版本上下限字段

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Squirrel.Mac 只下整包 zip；包里没有 Sparkle、没有 electron-updater 的 blockmap 逻辑 | 2026-10-26 `check/darwin/{arm64,x64}/1.26.1/anonymous/stable` 响应只有 `url/name/version/pub_date/notes` 五个字段，没有补丁地址；release 资产里 mac 只有两个整包 zip | 不需要 |

- 格式: 无
- 阻塞项: 无

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 2026-10-26 运行中一轮：启动约 45 s 内 ShipIt 停放了完整的 1.26.2 `Mailspring.app`（`~/Library/Caches/com.mailspring.mailspring.ShipIt/update.*/`，`ShipItState.plist` 指向 `/Applications/Mailspring.app`） | ○（duo 不复用，改为让路，见一键安装） |
| 证据 | `autoupdate-manager.js`：启动和每 30 分钟 `checkForUpdates()`，Electron 文档说有更新就自动下载；`update-downloaded` 后进入 `update-available` 状态等用户点安装或下次启动 | — | `SelfUpdaterStaging` 按通用的 `~/Library/Caches/<bundleID>.ShipIt/` 布局认出「已暂存」并改成提示重启；`SelfUpdaterStash` 读的布局里没有 Squirrel.Mac 原生 autoUpdater 这种（它只认 electron-updater 的 `pending/` 和 Cindy 的 hotfix） |

- 记录文件与字段: 按引擎对 Squirrel.Mac 的已知布局（`SelfUpdaterDownload` 注释），应是 `~/Library/Caches/com.mailspring.mailspring.ShipIt/ShipItState.plist` + `update.<随机>/Mailspring.app`；2026-10-26 运行中一轮实测如此（`update.SYmMU7m/Mailspring.app`，`ShipItState.plist` 的 `targetBundleURL` 是 `/Applications/Mailspring.app/`）
- 容器: 解开的 `.app`（Squirrel.Mac 下载 zip 后解包）；2026-10-26 实测是完整的 1.26.2 `Mailspring.app`
- 两份副本会不会共用这个目录: 会，目录按 bundle id 命名

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: `changelog pane  source structured: 1 entries; newest 1.26.2: 5 items, headings []; first items ["Fixed emails that declare a dark color s", "Fixed the Back and Close buttons in acco", "The MCP server's `reply_to_thread` tool "]`
  - 结构化 ✓，但不完整：1.26.2 正文是 `## 1.26.2 (10/22/2026)` + 两段说明（这是一个证书安全补丁版）+ 纯文本行 `Bug Fixes:` + 5 条列表。5 条列表都保留了；`Bug Fixes:` 不是 Markdown 标题，没有成为 heading；前面两段安全说明不是列表项，被丢掉了
- 跟随 channel: 只有一个轨
- Recipe 状态: 不需要（列表是正文的主体；丢掉的段落在 changelog 链接 `releases/tag/1.26.2` 里能看到）

## 一键安装
- 状态: 支持；真机两轮通过（2026-10-26）
- 端到端（2026-10-26，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 1.26.1 → `duo install` → 1.26.2、`TeamIdentifier=X9RJ36K9D4`、`codesign` 退出 0、`spctl` Notarized Developer ID。全程没启动过 Mailspring
  - 第二轮（运行中）: 先备份 `com.apple.dock`，再从 `/Applications` 启动 1.26.1。约 45 s 内它自己的 ShipIt 停放了 1.26.2。`duo install` → `Skipping: Mailspring — its own updater already has 1.26.2 staged — quit it to apply, or \`duo restart\``（不重复安装）；`duo restart Mailspring` → `quit — its own updater applied 1.26.2`，盘上 1.26.2、`codesign` 0，重新启动在 1.26.2 上。退出后没有残留的 `mailsync` 进程
  - Dock: 启动前后 `persistent-apps` / `persistent-others` 完全相同，这次没有往 Dock 加图标（源码里的 `oneTimeAddToDock` 没触发，原因没查）
  - 终态: 1.26.2，未运行
- 格式: .zip（`ditto -x -k` 后根目录就是 `Mailspring.app`）
- 签名: 1.0.12、1.10.3、1.26.1、1.26.2（arm64 和 x86_64）都是 Team `X9RJ36K9D4`，Team 没换过；1.26.1 / 1.26.2 spctl `Notarized Developer ID`
- 嵌套 / 常驻组件:
  - `Contents/Frameworks` 下四个标准 Electron helper（`com.mailspring.mailspring.helper`，`LSUIElement=true`），都是主进程的子进程，随主进程退出
  - `Squirrel.framework`（带 `ShipIt`），没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent / LaunchDaemon
  - 同步引擎 `Contents/Resources/app.asar.unpacked/mailsync`：每个账户一个子进程，`child_process.spawn` 不带 `detached`，stdin 接主进程（`src/mailsync-process.js`）。主进程退出时 `kill()` 它；即使主进程被强杀，`Mailspring-Sync` 的 `MailSync/main.cpp` 在 stdin 断开超过 30 s 后 `std::exit(141)`（只有 `--orphan` 才允许脱离父进程，app 不传）。所以换包后旧 `mailsync` 只会和旧主进程一起跑到重启为止，`duo restart` 把它们一起换掉，不需要 `loginItemAgentRestarts` 或 `OneClickGate`
  - 登录项: 「开机启动」用 `app.setLoginItemSettings({openAtLogin})`，登录项就是主 app 本身（`src/system-start-service.js`，顺手删旧的 `~/Library/LaunchAgents/com.mailspring.plist`）；换包后路径不变
- 校验: GitHub 资产 `digest`。1.26.2 `sha256:4ca6a0d995e51583c2dc4c43bdccfb4a96ed61867f0e8e18486954ba55f83dce`，与下载的包一致（180022208 字节）；1.26.1 `sha256:de4491669a6d13aab36428c21021335b1a3f0d8fa82e77a5540960f7a2dd0c1f`，`shasum -a 256` 相同（180004093 字节）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`），也是厂商更新服务器给 anonymous 请求的同一个资产
- 自更新器会不会和我们抢: 会。运行中的副本每 30 分钟自己下载新版，下次启动（或用户点了更新）时 ShipIt 换包。引擎对 ShipIt 有通用处理（`SelfUpdaterStaging`、`StagedRelaunch` 的 `.shipIt`）。和 massCode 一样，duo 换包后 ShipIt 会不会把它自己暂存的旧版装回去，这条还没验：2026-10-26 运行中一轮 ShipIt 暂存的就是最新版，duo 让路、没有换包，所以这种情况没出现
- 阻塞: 无

## 已知问题
- 首次从 `/Applications` 启动（`addedToDock` 没设过）时，`oneTimeAddToDock` 会执行 `defaults write com.apple.dock persistent-apps -array-add …` 然后 `pkill Dock`，往用户的 Dock 里加一个图标；不在 `/Applications` 时则弹「Move to Applications?」框（`askedAboutAppMove` 只问一次）。这是 app 自己的行为，与一键安装无关，但真机验证前要先备份 Dock 设置
- `mailspring:` URL scheme 由 app 启动时注册为默认处理者（`setAsDefaultProtocolClient('mailspring')`）；`mailto:` 只在用户在偏好设置里选了才设
- 内置 MCP server（`internal_packages/mcp-server`）只有用户在偏好设置里点「Add to Claude Desktop」才写 `~/Library/Application Support/Claude/claude_desktop_config.json`；启动时只会刷新已存在、且是它自己写的那一项（而且 app 要在 `/Applications`）。不写 `~/.claude`
- 厂商服务器的 `version` 是 `1.26.2-4de23b01`，带提交后缀，和 bundle 里的 `1.26.2` 不同；以后如果要改成读厂商服务器，要截掉后缀

## 如何复验
```bash
gh release download 1.26.2 --repo Foundry376/Mailspring --pattern 'Mailspring-AppleSilicon.zip'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Mailspring-AppleSilicon.zip
ditto -x -k Mailspring-AppleSilicon.zip x && swift run --package-path application-test channel-verify x/Mailspring.app --expect stable
curl -sS https://updates.getmailspring.com/check/darwin/arm64/1.26.1/anonymous/stable
```

2026-10-26 结果:
- 1.26.1: `detected channel  → stable`；`winning source  GitHub`；`latest 1.26.2`；`download https://github.com/Foundry376/Mailspring/releases/download/1.26.2/Mailspring-AppleSilicon.zip`；`status UPDATE → 1.26.2`
- 1.26.2: `detected channel  → stable`；`winning source  GitHub`；`status up to date`
- 两者 `changelog pane` 同上
- `feed-discover` 1.26.2: `no Sparkle, no electron-builder update config and no MyGo feed`

## 建议下一步
1. 真机看到 ShipIt 停放了整包、duo 没有复用（让路给它）。如果想省下这次下载，`SelfUpdaterStash` 可以加 Squirrel.Mac 原生 autoUpdater 的布局（Swift 改动，不是 recipe 字段）
