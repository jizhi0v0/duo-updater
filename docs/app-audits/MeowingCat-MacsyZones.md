# MacsyZones

## 基本信息
- App: MacsyZones — macOS 上的 FancyZones 式窗口管理器（拖窗口吸附到自定义布局分区）；GPL-3.0
- Bundle ID: `MeowingCat.MacsyZones`
- 仓库: `rohanrhu/MacsyZones`（默认分支 `main`；读源码时 `main` 头是 2026-09-15 的 `2d5ce44a`，与 v3.1.1 发布同日）
- Team ID: `59CP56H446`（Developer ID Application: Emin Oguzhan Eroglu）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.1.1（tag `v3.1.1`，资产 `MacsyZones.zip`，`CFBundleVersion` 1）；上一版 3.1（tag `v3.1`）；观测日期: 2026-10-22
- 自更新机制: **自研，启动即自动更新**（详见「自更新器」一节）。没有 Sparkle / electron-updater / Squirrel / Tauri
- 分发: GitHub Releases（每版一个 zip）；Homebrew cask `macsyzones`（`auto_updates true`，url 指向同一个 GitHub 资产）；官网 macsyzones.com 指向下载。MAS 没有：`itunes.apple.com/lookup?bundleId=MeowingCat.MacsyZones` → `resultCount 0`（源码里有 `#if !APPSTORE` 和一个 `MacsyZonesAppStore` scheme，但没有上架的商店版可查）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（`auto_updates`，退让） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测 `winning source GitHub`）。`feed-discover` 对 3.1 的 app: `no Sparkle, no electron-builder update config and no MyGo feed`。cask 是 `auto_updates true`，`HomebrewCaskSource` 不应答，落到 GitHub 规则。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh` + `codesign -dvv`）:
  - v3.1.1、v3.1、v3.0.4、v2.2.9、v1.9.3、v1.6: `MeowingCat.MacsyZones`，Team `59CP56H446`，spctl Notarized Developer ID，universal（x86_64 arm64）
  - v1.1（最老的 release）: 同 bundle id、同 Team，但签的是 `Apple Development` 证书，`spctl -a -t exec` → `CSSMERR_TP_CERT_REVOKED`。Team 相同，安装闸（按 Team 比对）不会拒它
  - 结论：**Team 从没换过**，上一版 3.1 与最新 3.1.1 同为 `59CP56H446`；没有改名前的旧 bundle id
- 其他轨: 无。41 个 release 全部 `prerelease=false`、`draft=false`；仓库没有 beta / nightly 的 tag、分支或发版脚本；cask 只有 `macsyzones` 一个（`brew search --cask macsyzones` 另一个结果 `macstroke` 是别的 app）
- 版本范围: `LSMinimumSystemVersion` 3.1 起是 14.0，3.0.4 及更早是 11.5。DuoUpdater 自己的下限是 macOS 15.0、只出 arm64（`App/project.yml`），两者都在其上，不需要 `hostRequirement`
- 自更新器出现的版本: v1.1 的可执行文件里没有 `releases/latest`，v1.6 起有（`strings`）。没自更新器的老副本同样由这条规则检测、一键

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `MeowingCat.MacsyZones` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `rohanrhu/MacsyZones` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.1.1` → `3.1.1` = `CFBundleShortVersionString`；两段的 tag（`v3.1`、`v2.2`、`v1.1`）同样等于 bundle 的短版本（3.1 包里就是 `3.1`）。`CFBundleVersion` 基本是常量 1（v1.6 是 3），不参与比较
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：41/41 个 tag 读得出；`v4.0` 读得出，`v3.2.0-rc.1`、`v3.2-beta` 不读（锚定）
- 读的和 app 自己的更新器是同一个端点（`Updater.swift` `checkLatestRelease`），两边对「最新版」的判断一致

## 自更新器（待审项结论）

settled from source: `MacsyZones/Updater.swift`、`MacsyZones/App.swift`、`MacsyZones/UserData.swift` on `main`（`Updater.swift` 与 tag `v3.1` 的同名文件 `diff` 无差异；3.1 / 3.1.1 / 3.0.4 二进制里都有下面引用的字符串）。

- **什么时候跑**: `applicationDidFinishLaunching` → `checkUpdateState()` → `appUpdater.checkForUpdates()`，**每次启动都跑、不问用户、没有开关**。运行中不再定时检查，只有菜单里的「Check for Updates」按钮手动触发
- **怎么判断**: 匿名请求 `https://api.github.com/repos/rohanrhu/MacsyZones/releases/latest`，`tag_name` 去掉 `v` 后与自己的 `CFBundleShortVersionString` 比，较新才动；取 `assets.first` 的 `browser_download_url`
- **下载 / 暂存**: `URLSession.downloadTask` 下到系统临时文件，回调里立即 `ditto -xk --extattr` 解到 `$TMPDIR/<UUID>/MacsyZones.app`，读出目标版本写进 `~/Library/Application Support/MeowingCat.MacsyZones/UpdateState.json`（`attemptedVersion` / `targetVersion`）
- **换包**: 写 `$TMPDIR/<UUID>/update.sh` 并 `nohup` 后台跑：`sleep 2` → 去 quarantine → `rm -rf <app 所在目录>/MacsyZones.app` → `ditto` 新包过去 → 去 quarantine → `open` → 删临时目录。同时弹 `NSAlert`「An update will now start. The app will restart automatically.」（floating、`runModal`），点 OK 后 `restartApp()` 并退出
- **不校验签名**: 换包前不查签名、Team 或摘要（脚本里没有 `codesign` / `spctl`），这是厂商的行为，与我们无关，记录在此
- **会不会停放**: 不会。解出来的 app 只在 `$TMPDIR/<UUID>/` 存在约 2–3 秒就被脚本拷走并删掉；没有「下完了、等下次启动再装」的状态
- **失败记录**: 下次启动若 `attemptedVersion == 当前版本 && targetVersion != 当前版本`，弹「Update Failed / Auto-update was unsuccessful.」对话框，且这次**不检查更新**；当前版本 ≥ `targetVersion` 时清掉记录

**和我们会不会冲突**（推断，未在真机上验证）:
- 两边只会装 `/releases/latest`，目标版本相同；自更新器只往更新的版本走，不会把 duo 装好的新版退回去
- app 运行中只在启动那一刻检查。duo 换包后 `duo restart` 起来的是最新版，它查到自己就是 latest，不会再动
- 真正的竞态窗口只有一个：旧版刚启动、自更新器正在下载/换包（约 7 MB 下载 + 2 s `sleep`）的同时 duo 也在换包。两边都是「删旧放新」，交错时可能出现 `rm -rf` 删掉 duo 刚放好的包再由脚本放回同版本，或脚本 `ditto` 到一半时 duo 读包。结果版本相同，但中间可能有一瞬没有 app。duo 的一键由用户点触发，碰上这个几秒窗口的概率低；不加门控
- 自更新器用的是匿名 GitHub API（每 IP 60 次/小时），和我们无 token 时的配额是同一个池子。量很小（每次启动一次），不单独处理

## 按架构 / 按 OS 分轨
- 架构: universal（`lipo -archs` = `x86_64 arm64`），一个资产
- `LSMinimumSystemVersion`: 3.1 起 14.0（3.0.4 及更早 11.5）；release 正文不声明 OS 范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `Updater.swift` 只下整个 zip | 每个 release 只有一个 `MacsyZones.zip`（`/releases?per_page=100` 资产列表） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 3.1 约 40 s，没有自更新，也没有停放） | 不需要 |
| 证据 | 源码：下载回调里立刻解压并由 `update.sh` 换包，临时目录随即删除 | — | — |

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，3.1 → 3.1.1）: `source structured: 1 entries; newest 3.1.1: 18 items, headings []; first items ["[Optional "Zone layouts only" for Quick ", "[Re-engineer Layout Switcher](https://gi", "[Fix layout switcher option can't be tur"]`
- **标题被压平，且混进了更早版本的条目。** 厂商的正文是累积式的：每发一版就在顶上加一节，下面保留之前各版的节（`### Changelog v3.1.1`、`### What's new with v3.1`、`### What's new with v3.0.4`、`### Changelog v3.0.3` … `## What's new with MacsyZones v3.0?`，最后是 GitHub 自动生成的 `## What's Changed`）。用生产解析器跑 v3.1.1 正文（临时测试调 `GitHubMarkdownParser.parse(body:version:"3.1.1")`，跑完删掉）：18 条、`content` 0 块。第 1 条是 3.1.1 真正的改动，第 2–5 条属于 3.0.4，6–7 属于 3.0.3，8 属于 3.0.2，9–10 属于 3.0.1，11–13 属于 3.0，14–18（`What's Changed` 的 5 个 PR）属于 3.1；`> ` 引用块里「since v2.0」的 6 条没被收进去。
  - 原因：这些节标题都带版本号，`isVersionLikeHeading` 让它们不成为 `.heading` 块（设计如此）；`withoutEarlierReleases` 只认四种措辞（`Changes in version X`、`vX Changes`、`Notes from X`、`Everything from X`），`Changelog vX` / `What's new with vX` 不在其中，所以较早版本的节没有被剥掉
  - 这是通用解析器的取舍，不是这条 rule 能改的；要修得改引擎（见「建议下一步」）
- 跟随 channel: —（单轨）
- Recipe 状态: 暂不加（`ChangelogRecipe` 能否按「本版本那一节」切片没有验证；首选是解析器认这两种措辞）

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 3.1 → `duo check` `3.1 → 3.1.1 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 3.1.1、可执行文件 inode 变、`TeamIdentifier=59CP56H446`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 3.1.1 包相同
  - 第二轮（运行中）: 启动 3.1，**20 s 内它没有自更新**（磁盘一直是 3.1、进程不变、没有 `update.sh`，`UpdateState.json` 为 `{}`）。本机没给它辅助功能权限，界面停在一个无标题的面板上；源码说的「启动即检查」是不是要先过辅助功能这一步，没核实。随后 `duo install` → `Still running the old code`，`duo restart MacsyZones` → 新进程起来，没有「already running」告警，之后 10 s 磁盘一直是 3.1.1、签名有效
  - 自更新器和 duo 同时换包的竞态（见上「和我们会不会冲突」）这次没造出来
- 格式: zip（`ditto -x -k` 后根目录就是 `MacsyZones.app`）。Pattern `^MacsyZones(?:-[0-9.]+)?\.zip$`（v1.5 的资产叫 `MacsyZones-1.5.zip`），kind `.zip`
- 嵌套 / 常驻组件: 无。`Contents/` 下只有 `MacOS/MacsyZones`、`Resources/`（图标、`Assets.car`、`README.md`）、签名；没有 LoginItems / Helpers / XPC / LaunchAgent。app 本身是 `LSUIElement` 菜单栏常驻进程，entitlements 为空（不沙盒）
- 登录项: 菜单里的「Start at login」开关调 `SMAppService.mainApp.register()`，登记的是 app 本身，不是单独的 helper；默认关（状态读 `SMAppService.mainApp.status`，源码里没有自动 register 的地方）
- 签名: 3.1、3.1.1 都是 `TeamIdentifier=59CP56H446`、Notarized Developer ID、hardened runtime（`flags=0x10000(runtime)`）
- 校验: GitHub 资产 `digest`。v3.1.1 `sha256:6db860035ba72aaa7ea5eab0e37350687f3a69a243b4c87829168edb30281665`、v3.1 `sha256:d3f83f69d6827821e9da6e22b4a9ffe213f3231b73ba7b200ae635bd50276904`，下载文件 `shasum -a 256` 与之相同，大小 7291746 / 7288728 字节等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，也是 app 自己的更新器读的那一个）
- 阻塞: 无

## 已知问题
- changelog 面板把历次版本的条目都算在最新版名下，见上
- 启动副作用（读源码；2026-10-22 真机核对的已注明）:
  - 没有辅助功能权限时弹 `AccessibilityDialog`（自绘 NSPanel，引导去系统设置授权，授权后要重启 app）；有权限且没完成过引导时弹 Onboarding 窗口
  - 已有一个实例在跑时，新实例弹 critical `NSAlert`「MacsyZones is already running」（`.screenSaver` 级别、所有 Space）后退出。duo 重启若在旧进程退干净之前拉起新进程，会撞上它
  - 全局鼠标 / 快捷键监听：拖动任意窗口会出现布局分区覆盖层和吸附
  - 数据写在 `~/Library/Application Support/MeowingCat.MacsyZones/`（`UserLayouts.json`、`UpdateState.json` 等）。Homebrew cask 的 `zap` 写的是 `~/Library/Application Support/MacsyZones` 和 `com.macsyzones.MacsyZones.plist`，和源码不一致（厂商 cask 的问题，不影响我们）
  - 源码里没有写 `~/.claude` / `~/.agents` 的地方
  - 真机：首启建了 `~/Library/Application Support/MeowingCat.MacsyZones/`（`AppSettings.json`、`UserLayouts.json`、`UpdateState.json`、`SpaceLayoutPreferences.json`）、`~/Library/Caches/MeowingCat.MacsyZones`、`~/Library/HTTPStorages/MeowingCat.MacsyZones`

## 如何复验
```bash
gh api "repos/rohanrhu/MacsyZones/releases?per_page=100" -q '.[]|.tag_name+" "+(.prerelease|tostring)+" "+([.assets[]|.name+":"+(.digest//"none")]|join(","))'
gh release download v3.1 --repo rohanrhu/MacsyZones --pattern 'MacsyZones.zip' --dir v3.1
gh release download v3.1.1 --repo rohanrhu/MacsyZones --pattern 'MacsyZones.zip' --dir v3.1.1
.claude/skills/coverage-discovery/scripts/check-bundle.sh v3.1/MacsyZones.zip     # → MeowingCat.MacsyZones, 3.1, Team 59CP56H446, Notarized
.claude/skills/coverage-discovery/scripts/check-bundle.sh v3.1.1/MacsyZones.zip   # → 3.1.1, 同 Team
ditto -x -k v3.1/MacsyZones.zip v3.1/x && ditto -x -k v3.1.1/MacsyZones.zip v3.1.1/x
swift run --package-path application-test feed-discover v3.1/x/MacsyZones.app                     # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify v3.1/x/MacsyZones.app --expect stable    # → GitHub，UPDATE → 3.1.1
swift run --package-path application-test channel-verify v3.1.1/x/MacsyZones.app --expect stable  # → up to date
```

## 建议下一步
1. 解析器（引擎改动，待定）：让 `GitHubMarkdownParser.withoutEarlierReleases` 认 `Changelog vX` 和 `What's new with vX` 这两种措辞，较早版本的节就会被剥掉，3.1.1 只剩自己那一条。注意该函数的注释明确把 `What's new in 2.0` 列为「不是信号」，加这两种措辞前要先扫一遍现有 GitHub 规则的正文，确认没有误伤。
