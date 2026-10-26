# Witsy

## 基本信息
- Bundle ID: `com.nabocorp.witsy`
- 仓库: `Kochava-Studios/witsy`（2026-04 前是 `nbonamy/witsy`；那个名字现在是另一个几乎空的仓库，2026-04-14 建、无 release，GitHub 不再重定向）
- Team ID: `TP8BYQ64C4`（Developer ID Application: Sporty Apps）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.5.2（tag `v3.5.2`，资产 `Witsy-3.5.2-darwin-arm64.dmg`）；观测日期: 2026-10-26
- 自更新机制: Electron `autoUpdater`（Squirrel.Mac）+ update.electronjs.org；已发布的每个版本都指向旧仓库名，现在 404（见「更新检测」）
- 分发: GitHub Releases；Homebrew cask `witsy`（`auto_updates true`，URL 指向同一个 arm64 dmg）；官网 witsyai.com 链到 GitHub。不上 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗（`auto_updates true`，`HomebrewCaskSource` 让路） | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓（只检测，给最新稳定版） | — |

当前生效源: **GitHub**（channel-verify 实测：3.5.1 / 3.5.2 / 2.0.0-beta1 / 2.0.0-rc1 都是 `winning source GitHub`）

## 覆盖清单
- 各版本的 bundle id / Team（读真包）:
  - v3.5.2（arm64 dmg 与 x64 dmg）: `com.nabocorp.witsy`，Team TP8BYQ64C4
  - v3.5.1（`Witsy-3.5.1-darwin-arm64.dmg`）: 同 id、同 Team，版本与 tag 一致
  - v1.35.1（`Witsy-1.35.1-darwin-arm64.dmg`，脚本读的列表里最老的稳定版）: 同 id、同 Team
  - v1.4.2（`Witsy-darwin-arm64-1.4.2.zip`，2024-04，GitHub 上最老的 release）: 同 id、同 Team
  - 没有改过名的旧 bundle id；cask 也只有 `witsy` 一个
- 其他轨: GitHub 上 17 个 release 标了 prerelease。
  - `v2.0.0-beta1`（2025-03-04）: 包里版本 `2.0.0-beta1`，`ReleaseChannel.detect` 读成 beta → `.beta` 只检测 rule 给最新稳定版
  - `v2.0.0-rc1`（2025-03-07）: 包里版本 `2.0.0-rc1`，读成 stable → stable rule 给 3.5.2，可一键
  - 其余（`v3.4.1`、`v3.0.1`、`v3.0.0`、`v2.7.0`、`v2.6.x`、`v2.4.x`、`v2.1.x`、`v1.38.0`、`v1.37.0`）都是纯数字 tag、纯数字版本，和稳定版同形；装了它们的副本读成 stable，按版本号比较拿到 3.5.2。`/releases/latest` 跳过它们
  - App 里没有渠道开关：更新地址在 `src/main/autoupdate.ts` 写死，没有 beta/prerelease 选项（settled from source: `src/main/autoupdate.ts` @ v3.5.2，读的是包内 sourcemap 的 `sourcesContent`）
- 架构: 每个 release 分 `-darwin-arm64` 和 `-darwin-x64` 两份（dmg + zip），没有 universal。两份 3.5.2 dmg 比过：Info.plist 只差 `ElectronAsarIntegrity` 的哈希；`app.asar` 56992 个文件，只差三个原生模块的架构目录（`autolib/prebuilds/darwin-*`、`onnxruntime-node/bin/napi-v3/darwin/*` 两个），其余逐字节相同（含 `main-Ci6h9ZRh.js`）。所以两份只差 CPU 架构，不是两个产品
- 版本范围、主机下限: 1.4.2 起 `LSMinimumSystemVersion` 10.15，3.5.2 是 12.0，都低于 DuoUpdater 的 15.0 / arm64，不需要 `hostRequirement`
- 版本方案: 全部 169 个 release 里 152 个非 prerelease tag（83 + 69，两页）都是 `v<数字点分>`，`versionPattern` 全部读得到；`v2.0.0-beta1` / `v2.0.0-rc1` 被锚定的 pattern 挡掉

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.nabocorp.witsy` | — | — | — | ✓ |
| beta（2.0.0-beta1 副本） | `com.nabocorp.witsy` | 共享 | 版本后缀 `-beta1` | 只检测，给最新稳定版 | ✓ |

## 更新检测
- 源: `Kochava-Studios/witsy` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.5.2` → `CFBundleShortVersionString` `3.5.2`、`CFBundleVersion` `1445`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^Witsy-[0-9]+(?:\.[0-9]+)+-darwin-arm64\.dmg$`（只 arm64：DuoUpdater 只跑 arm64；同 release 的 arm64 zip、x64 dmg/zip 不用）
- `feed-discover` 3.5.2 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`（没有 `app-update.yml`，`Contents/Frameworks/Squirrel.framework` 在）
- **自己的更新器已断（2026-10-26 实测）**: 3.5.2 的 `main-Ci6h9ZRh.js` 里 feed 是
  `https://update.electronjs.org/nbonamy/witsy/${process.platform}-${process.arch}/${version}`。
  - `curl https://update.electronjs.org/nbonamy/witsy/darwin-arm64/3.5.1` → HTTP 404 `No updates found (needs asset matching .*-(mac|darwin|osx).*.zip in public repository)`；`.../3.5.2` 同样 404
  - `curl https://update.electronjs.org/Kochava-Studios/witsy/darwin-arm64/3.5.1` → HTTP 200，`name` 3.5.2，`url` `.../v3.5.2/Witsy-3.5.2-darwin-arm64.zip`，`notes` 只是一个指向仓库 CHANGELOG.md 的相对 Markdown 链接
  - 仓库 `main` 的 `src/main/autoupdate.ts` 已改成 `Kochava-Studios`（commit `e40a1b39` "chore: relocation"，2026-04-08），但之后还没发版。所以现有副本都不会自己更新，GitHub rule 是它们唯一的更新提示
- 注意事项: Homebrew cask `auto_updates true`，`HomebrewCaskSource` 返回 nil，不和 GitHub 抢

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（arm64 / x64），无 universal；rule 只装 arm64。x64 副本（Apple silicon 上跑在 Rosetta 下）一键会换成 arm64 版，同一个 app
- `LSMinimumSystemVersion`: 3.5.2 为 12.0（1.4.2 为 10.15）；Release 和 update.electronjs.org 都不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Squirrel.Mac 只下整包 zip（`autoupdate.ts` 只用 Electron `autoUpdater`） | update.electronjs.org 对 Kochava-Studios 的应答只有一个整包 zip 的 `url`（2026-10-26，`darwin-arm64/3.5.1`） | 没有补丁可吃 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（Squirrel.Mac），但已发布版本的 feed 404，现在不会下载 | 2026-10-26 运行中一轮没有记录到停放（该轮结果里没有 ShipIt 目录的观察） | ○ |
| 证据 | `autoupdate.ts`: `update-available` 后自动下载，`update-downloaded` 只亮托盘图标；Squirrel.Mac 停放在 `~/Library/Caches/com.nabocorp.witsy.ShipIt/`（Squirrel.Mac 的通用布局，未在本 app 上实测） | — | `SelfUpdaterStash` 目前只读 electron-updater 和 Cindy 两种布局，不读 ShipIt |

- 记录文件与字段: Squirrel.Mac 的 `ShipItState.plist`（未在本 app 上实测）
- 容器: zip，包根是 `Witsy.app`
- 两份副本会不会共用这个目录: 会（按 bundle id 命名的缓存目录）

## Changelog
- 来源: recipe（`raw.githubusercontent.com/Kochava-Studios/witsy/main/CHANGELOG.md`，Keep a Changelog）。GitHub release 正文从 v3.2.1 起都只有一个指向 CHANGELOG.md 的相对 Markdown 链接，不能用
- 结构化: `changelog pane  recipe changelog:com.nabocorp.witsy:-: 31 entries; newest 3.5.2: 8 items, headings ["Added", "Fixed"]; first items ["Search text inside chat (Cmd+F/Ctrl+F)", "Navigation inside the chat during search", "LM Studio Embedding model support (https"]` — 分节保留；只有 `- N/A` 的节（3.5.2 的 Changed / Removed）连标题一起略掉
- 覆盖: 文件从 2.10.0 开始；`## [3.6.0] - WIP` 因为日期不是 `yyyy-MM-dd` 被跳过；`## [2.12.5 / 2.12.6]` 一个括号两个版本，被跳过；2.10.0 之前的版本没有条目
- 跟随 channel: 只有一条线
- Recipe 状态: 已有

## 一键安装
- 状态: 支持（arm64 dmg）
- 端到端（2026-10-26，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 3.5.1 → `duo install` → 3.5.2，Team `TP8BYQ64C4` ✓
  - 第二轮（运行中）: 换包在位完成 ✓；`duo restart` → `still running — likely a save prompt`，**这个提示在此处不对**：真因是 Witsy 的 `keepRunning` 默认（`before-quit` 里 `preventDefault()`），没有窗口也没有提示框。它还忽略了 SIGTERM，测试进程最后用 SIGKILL 结束
  - `/usr/local/bin` 不可写，所以没有建 `witsy` 软链；kill 之后本机端口 8090 已释放
  - 终态: 3.5.2，未运行
- 格式: .dmg（`hdiutil imageinfo` 退出码 0）
- 嵌套 / 常驻组件: `Contents/Frameworks/Witsy Helper{, (GPU), (Plugin), (Renderer)}.app`，都是 Electron 子进程宿主（`com.nabocorp.witsy.helper`，`LSUIElement`），随主进程退出；没有 LoginItems / LaunchAgents / 系统扩展
- 校验: GitHub digest `sha256:e9c8e371362c43b41812b17f7280807a5feb3cb9a4829ca0909824639ca23205`，与下载的 3.5.2 arm64 dmg 一致；3.5.1 arm64 dmg `fc13389287a09e17970a24ec72467e926f4001acc65d96af08e53706eadc7e4c` 也与 digest 一致
- Team: 1.4.2、1.35.1、3.5.1、3.5.2 都是 TP8BYQ64C4，Team 闸不会拒旧副本
- 跨大版本: Witsy 自己的更新器（搬仓库前）就是 update.electronjs.org 给的最新版，不分大版本，一键与之一致；没有加 `OneClickGate`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 退出: 默认 `general.keepRunning = true`（`defaults/settings.json` @ v3.5.2），`before-quit` 里 `preventDefault()`，只关窗口、留在托盘。真机（2026-10-26）上 `duo restart` 没能让它退出，SIGTERM 也被忽略，最后用 SIGKILL

## 已知问题
- 已发布版本的自更新器指向 `nbonamy/witsy`，update.electronjs.org 回 404；下一版（源码已改名）发布前，现有副本靠不了自己更新
- 默认「关窗不退出」（`keepRunning`）：2026-10-26 真机上 `duo restart` 让不动它，只报 `still running — likely a save prompt, left it alone`。这句话对 keep-running 的 app 有误导（没有保存提示，是 app 自己拒绝退出）；SIGTERM 也被忽略，只有 SIGKILL 能结束
- 首次启动会碰的、在自己 Application Support 之外的东西（读 3.5.2 包内 sourcemap 的 `src/main.ts` 等，未运行验证）:
  - `/usr/local/bin/witsy`: 每次启动 `checkAndInstallCLI(false)` 尝试把它软链到 `Witsy.app/Contents/Resources/cli/bin/witsy`；目录不可写就静默放弃（不提权、不弹框）。若该路径已有别的文件且目录可写，会先 `unlink` 再建链接。提权版只在设置里手动「重试」时走（`osascript ... with administrator privileges`）
  - 全局快捷键（`globalShortcut`，默认值来自 `defaults/settings.json`）: ⌃Space、⌃⌥Space、⌘⇧P、⌃⇧⌥Space、⌃⌥⌘Space、⌘⌥N；⌃Space 是系统默认的输入法切换键
  - 本机 HTTP 服务 `127.0.0.1:8090`（`enableHttpEndpoints` 默认开）
  - `systemPreferences.setUserDefault('NSDisabledDictationMenuItem', true)`，写在自己的 defaults 域
  - `new Notification()` 会触发通知权限询问
  - 不在 `/Applications` 里运行会弹框并退出
  - 登录项只在用户打开设置开关时写（`app.setLoginItemSettings`）；没有写 `~/.claude*`、其他工具的 MCP 配置或 LaunchAgents 的代码（在 main 进程源码里搜 `homedir` / `claude` / `mcp.json` / `LaunchAgents` / `setAsDefaultProtocolClient` 无命中）；Info.plist 没有 `CFBundleURLTypes`

## 如何复验
```bash
gh release download v3.5.2 --repo Kochava-Studios/witsy --pattern 'Witsy-3.5.2-darwin-arm64.dmg'
gh release download v3.5.1 --repo Kochava-Studios/witsy --pattern 'Witsy-3.5.1-darwin-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Witsy-3.5.2-darwin-arm64.dmg
swift run --package-path application-test channel-verify Witsy-3.5.1-darwin-arm64.dmg --expect stable
swift run --package-path application-test channel-verify Witsy-3.5.2-darwin-arm64.dmg --expect stable
curl -sS -w '\n%{http_code}\n' https://update.electronjs.org/nbonamy/witsy/darwin-arm64/3.5.1
```

2026-10-26 结果:
- 3.5.1: `detected channel → stable`，`winning source GitHub`，`latest 3.5.2`，`download .../v3.5.2/Witsy-3.5.2-darwin-arm64.dmg`，`status UPDATE → 3.5.2`
- 3.5.2: `detected channel → stable`，`winning source GitHub`，`status up to date`
- 2.0.0-beta1（只放了真包 Info.plist 的 bundle，plist 从 release zip 里按 range 读出）: `inferred beta`，`winning source GitHub`，`latest 3.5.2`，`download .../releases`（只检测），`status UPDATE → 3.5.2`
- 2.0.0-rc1（同上）: `inferred stable`，`download .../v3.5.2/Witsy-3.5.2-darwin-arm64.dmg`，`status UPDATE → 3.5.2`

## 建议下一步
1. （已做，2026-10-26）真机一键两轮见「一键安装」；`keepRunning` 下 duo 让不动它，`likely a save prompt` 的措辞对这类 app 不准，是否改待定
2. 下一版（feed 改成 Kochava-Studios）发布后，复查运行中一轮: Squirrel.Mac 会自己下载并在退出时换包，看会不会和 duo 抢
