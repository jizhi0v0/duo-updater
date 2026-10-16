# Zettlr

## 基本信息
- App: Zettlr — Electron 写的 Markdown / 学术写作编辑器，GPL-3.0 开源
- Bundle ID: `com.zettlr.app`（1.0.0 起；0.x 是 `com.zettlr.www`，见「覆盖清单」）
- 仓库: `Zettlr/Zettlr`（默认分支 `develop`）；官网 `https://www.zettlr.com/`；Homebrew cask `zettlr`
- Team ID: `QS52BN8W68`（Developer ID Application: Hendrik Erz；dmg 公证）
- 观测版本: 4.8.0（`CFBundleVersion` 同为 `4.8.0`）；观测日期: 2026-10-16
- 自更新机制: 自研，只提示、不换包。settled from source: `source/app/service-providers/updates/index.ts` on `develop`
  - 请求 `https://zettlr.com/api/releases/latest?accept-beta=<checkForBeta>`，UA `Zettlr/<ver> (Macintosh; …; <arch>)`。
    这个端点回的是 GitHub release 的副本（`tag_name`、`prerelease`、`body`、`assets`），2026-10-16 两种 `accept-beta`
    都回 `v4.8.0`（当时最新的 release 是正式版）
  - 有更新时弹窗，用户在更新窗口点下载后把 dmg 存进 `~/Downloads/<资产名>`，按 release 的 `SHA256SUMS.txt` 校验，
    然后 `shell.openPath` 打开 dmg 并退出 app，由用户自己拖进 Applications。不替换 bundle
  - 版本比较用 `semver.lt`（build metadata 不参与比较）
- 分发: GitHub Releases（每个 release 一个 `-arm64.dmg`、一个 `-x64.dmg`）；nightly 另放在 `nightly.zettlr.com`；没有 MAS
- `feed-discover`: 无 Sparkle、无 electron-builder update config、无 MyGo feed

## 覆盖清单（Coverage checklist）

| 组 | 结论 | 证据 |
|---|---|---|
| bundle id | `com.zettlr.app`（1.0.0 至今）✓；`com.zettlr.www`（0.x，最后一版 0.20.0）✓ 仅检测 | `package.json` `appId` 在 v1.0.0 已是 `com.zettlr.app`，v0.20.0 是 `com.zettlr.www`；真包 0.20.0 的 Info.plist 是 `com.zettlr.www` |
| beta 轨 | ✓ 接入（同 bundle id，偏好 `checkForBeta`） | 见「Channel 详情」 |
| nightly 轨 | ✗ 只能识别、不能提供更新（Pattern D） | 见「Channel 详情」 |
| 版本区间 | 1.0.0 起 bundle id 不变；4.7.0、4.8.0、4.0.0-beta.5 三个真包 Team 都是 `QS52BN8W68`、都是 Notarized Developer ID | `codesign -dvv`、`spctl -a -vv` |
| 宿主下限 | `LSMinimumSystemVersion` = `12.0`（三个真包相同），低于 DuoUpdater 自己的部署下限，不需要 `hostRequirement` | PlistBuddy |
| 架构 | arm64 / x64 各一个 dmg，install pattern 都匹配，由资产选择器按文件名挑 | `lipo -archs` arm64 包 = `arm64` |

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | —        | —   | ✓      | —           |
| **beta**    | —       | —        | —   | ✓      | —           |
| **nightly** | —       | —        | —   | ✗      | ✗           |

当前生效源: **GitHub**（channel-verify 实测）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.zettlr.app` | 共享 | — | `/releases/latest`，tag `^v([0-9]+(?:\.[0-9]+)+)$` | ✓ |
| beta    | `com.zettlr.app` | 共享 | `config.json` 的 `checkForBeta` = `true`（`ZettlrChannel`）；或版本串 `-beta.N`（`ReleaseChannel.detect` 通用规则） | 读整份 release 列表，tag 接受正式版与 `-beta[.N]` | ✓ |
| nightly | `com.zettlr.app` | 共享 | 版本串 `<x.y.z>+nightly`（`ReleaseChannel.detect` 0.91 步） | 无规则 | ✗ |

**beta**（settled from source）：
- 开关是 Preferences ▸ Advanced ▸ Beta releases ▸ "Notify me about beta releases"（`source/win-preferences/schema/advanced.ts`），
  模型是顶层的 `checkForBeta`，默认 `false`（`get-config-template.ts`）。配置文件是 Electron `userData` 下的 `config.json`
  （`service-providers/config/index.ts`），`productName` 为 `Zettlr`，所以默认路径是 `~/Library/Application Support/Zettlr/config.json`；
  用 `--data-dir` 启动的副本例外，那种副本读不到偏好，按版本串判断
- app 把它作为 `accept-beta` 发给端点，端点据此把 prerelease 也算进去，回最新的那个，正式版或 beta 都可能。所以 beta 规则
  读整份列表，tag 两种形状都收；beta 构建的 Info.plist 带后缀（真包 4.0.0-beta.5 = `4.0.0-beta.5`），pattern 保留后缀
- `ZettlrChannel` 只对勾选的状态回答 `.beta`，其余回 nil，让 `detect()` 继续按版本串判断（CotEditor 的形状）。
  真机写入已观测（2026-10-16，4.8.0）：勾选后顶层 `checkForBeta` `false` → `true`，见「建议下一步」第 2 条
- 首个 beta 不带编号（`v4.0.0-beta`、`v3.1.0-beta`），通用规则把裸 `-beta` 读成 stable。这种副本没勾选时被推下一个正式版，
  与 app 自己的行为一致（`checkForBeta` 关时端点只回正式版）
- 最后一个 beta 是 `v4.0.0-beta.5`（2025-12-19），之后 4.x 都是正式版

**nightly**（settled from source + 真包）：
- `.github/workflows/build.yml` 每周一从 `develop` 构建，版本 = `package.json` 版本 + `+nightly`，上传到 `nightly.zettlr.com`。
  2026-10-16 该页只列一组文件 `Zettlr-4.8.0+nightly-*`；arm64 dmg `Last-Modified: Mon, 12 Oct 2026 13:02:23 GMT`，
  Info.plist 两个版本字段都是 `4.8.0+nightly`，Team `QS52BN8W68`、Notarized
- 每周的 nightly 版本串一样，没有可排序的东西，nightly → nightly 无法提供（Pattern D）
- 修掉的问题：原先 `4.8.0+nightly` 被读成 stable，`VersionComparator` 把 `4.8.0` 排在它前面，于是 nightly 副本被推 4.8.0 正式版，
  也就是它的代码已经越过的那一版。app 自己不会这样推（semver 忽略 build metadata）。现在 `ReleaseChannel.detect` 对
  `com.zettlr.app` 的 `…+nightly` 判为 `.nightly`，没有规则服务它，状态为 unknown，不推任何东西
- 代价：nightly 副本也不会被推下一个正式版（app 自己会推）。nightly 与正式版共用 `config.json`，勾了 beta 时
  binding 本会判 beta、让 beta 规则推同号正式版；`ZettlrChannel.resolve(checkForBeta:bundleStrings:)` 遇到 `detect` 判 nightly 的版本串就不作答，
  nightly 仍是 unknown（`ZettlrChannelTests.theBindingDeclinesForANightlyBuild`）

## 更新检测
- 源: `Zettlr/Zettlr` GitHub Releases。stable 读 `/releases/latest`；beta 读列表（`usePrereleases`，`listPageSize` 默认 20，
  深度下限 1：2026-10-16 最新 20 个 release 全部匹配）
- 版本: stable `^v([0-9]+(?:\.[0-9]+)+)$`；beta `^v([0-9]+(?:\.[0-9]+)+(?:-beta(?:\.[0-9]+)?)?)$`。181 个 release 里：
  正式版 tag 都是 `vX.Y.Z`，只有 2018 年的 `v.0.9.0` 读不出（0.x，旧 bundle id）；prerelease 都打了 prerelease 标记，
  形状是 `-beta`、`-beta.N`，2020 年还有 `-alpha[.N]` 和不带 `v` 的 `1.8.0-beta.N`，两个 pattern 都不收
- `zettlr.com/api/releases/latest` 没有用：内容就是 GitHub 的同一个 release，GitHub 规则还能拿到资产 digest 与历史
- 旧 id `com.zettlr.www`：同仓库、仅检测（无 install pattern）。0.20.0 真包 x86_64、`spctl` = `no usable signature`，
  没有 Team 可核，下载回来又是另一个 bundle id，只能手动替换一次

## 按架构 / 按 OS 分轨
- release 不声明 OS 上下限。4.8.0 的说明里写了下一版会升 Electron、放弃旧系统（文中列出 macOS 12），届时
  `LSMinimumSystemVersion` 预计变化，仍低于 DuoUpdater 的下限，不影响规则（推理，未验证）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 更新器只下载整个 dmg（源码） | 4.8.0 资产只有完整包、Linux/Windows 包与 `SHA256SUMS.txt` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（用户点下载后） | 没观测到（见证据） | ○ |
| 证据 | `_downloadAppUpdate` 写到 `app.getPath('downloads')/<资产名>`（源码） | 2026-10-16 运行中一轮：启动时日志 `[Update Provider] Checking https://zettlr.com/api/releases/latest`，但这时 bundle 已被 duo 换成 4.8.0，旧进程开不了更新窗口（见已知问题），没走到下载 | `SelfUpdaterStash` 不读这种布局 |

- 记录文件与字段: 无。完成与否只在内存里（`size_downloaded == size_total`）；退出时只删没下完的文件；
  校验用 release 的 `SHA256SUMS.txt`（SHA-256 hex），也只在内存里比对
- 容器: dmg，包根是 `Zettlr.app`
- 两份副本会不会共用这个目录: 会，`~/Downloads` 是用户的公共目录，文件名只带版本和架构
- 没有完成记录，要接只能按文件名 + 大小 + 对 `SHA256SUMS.txt` 校验来认，价值低，没做

## Changelog
- 来源: GitHub Release body，经 `ChangelogRecipe`（`structuredFormat: .gitHubReleases`，stable / beta 各一条，beta 带
  `includesPromotedStable`）；补的是更新栏里的历史条目，被推的那一版 GitHub 源本身也能渲染
- 结构化（2026-10-16，channel-verify `changelog pane`，4.7.0 包）: `recipe changelog:com.zettlr.app:stable: 20 entries;
  newest 4.8.0: 32 items, headings ["Deprecation Note: Dropping Support for OS Versions in Next Release",
  "GUI and Functionality", "Under the Hood"]; first items ["Ubuntu 17.04 or earlier", "macOS 12 (Monterey)",
  "**Feature**: Admonitions are here! Zettl"]`
- 4.0.0-beta.5 包: `recipe changelog:com.zettlr.app:beta: 20 entries`，最新条目同上
- 已知损失: 4.8.0 body 的 `## Admonitions` 一节全是散文（无列表项），不进 headings；前面的引言段与捐赠提示也不进条目
- 跟随 channel: 是（stable / beta 两条 recipe）
- Recipe 状态: 已有

## 一键安装
- 状态: **支持**（stable、beta；按 Team 闸）。`com.zettlr.www` 仅检测
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：4.7.0 → 4.8.0（含 `verifyingSignature`），`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（公证）。嵌套的四个 `Zettlr Helper*.app`（GPU / Plugin / Renderer / 无后缀，`LSUIElement=true`）是
  Electron 的子进程，随主进程退出，不是常驻 agent；bundle 内没有 LoginItems / LaunchAgents
- Pattern: stable `^Zettlr-[0-9]+(?:\.[0-9]+)+-(?:arm64|x64)\.dmg$`；beta 另收 `-beta[.N]`。不匹配 AppImage/deb/rpm/exe 与 `SHA256SUMS.txt`
- 校验: GitHub 资产 `digest`（#1019 起自动传）。下载后 `shasum -a 256`：4.8.0 arm64 = `3144b951…46b7d3f5`、
  4.7.0 arm64 = `e03e3701…7ed8f8`、4.0.0-beta.5 arm64 = `3f6ccfe5…8da4cf3`，与各自 `digest`、`SHA256SUMS.txt` 都相同
- Team: 上一版 4.7.0 与 4.8.0 同为 `QS52BN8W68`，旧副本一键不会被 Team 闸挡
- **读的是**: 人人可手动下载的 GA（stable 读 `/releases/latest`；beta 读 GitHub 上公开的 prerelease；2026-10-16 `zettlr.com/download` 的静态 HTML 里唯一的下载链接是 GitHub releases 页）
- 阻塞: 无
- 自更新器碰撞: 无。app 的更新器从不替换 bundle，只打开 dmg

## 已知问题
- nightly 副本显示 unknown，不推更新（见 Channel 详情）
- 运行中被换包的旧进程开不了新窗口：4.7.0 运行中 duo 装上 4.8.0 后，旧进程的主窗口一片空白，Help → Check for updates 弹 “Could not open window — Could not open main Window: ERR_FAILED (-2) loading 'file:///Applications/Zettlr.app/Contents/Resources/app.asar/.webpack/renderer/main_window/index.html?…'”（窗口从磁盘上的新 `app.asar` 加载）。`duo restart` 后恢复。任何原地换包（包括手动拖拽）都会这样，duo 的 `Still running the old code` 提示就是为此
- 首启向导（“Hello!” Skip / Start setup）和更新后的 “Update complete!” 页开着时，app 不响应 AppleScript `quit`（返回 0 但不退），也不响应 SIGTERM；向导开着时 `duo restart` 报 `still running — likely a save prompt`。原因没查

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：4.7.0 运行中，`duo install --yes` → `installed.` 并提示 `Still running the old code: Zettlr`；首启向导开着时 `duo restart` 退不掉 app；用户点 Skip 后旧进程开窗失败（见已知问题），再 `duo restart` → `restarted`，主进程与 Helper 都映射 4.8.0 的二进制，app 显示 “Update complete! … v4.8.0”。Team `QS52BN8W68`、`codesign --strict` 0、Notarized。新增 `~/Library/Application Support/Zettlr`、`~/Library/Preferences/com.zettlr.app.plist`、`~/Documents/Zettlr Tutorial`，登录项前后无差异
2. （已做）2026-10-16 真机 4.8.0：勾选 Settings ▸ Advanced ▸ “Notify me about beta releases” 后 `~/Library/Application Support/Zettlr/config.json` 的 `checkForBeta` `false` → `true`（同时变的只有教程打开的 `openDirectory` / `app.openWorkspaces`）；`channel-verify --check com.zettlr.app` → `detected channel → beta`、`latest → 4.8.0`、`up to date`

## 如何复验
```
swift run --package-path application-test channel-verify Zettlr-4.7.0-arm64.dmg --expect stable
#   → detected stable，winning source GitHub，latest 4.8.0，UPDATE → 4.8.0
swift run --package-path application-test channel-verify Zettlr-4.8.0-arm64.dmg --expect stable
#   → detected stable，latest 4.8.0，up to date
swift run --package-path application-test channel-verify Zettlr-4.0.0-beta.5-arm64.dmg --expect beta
#   → short 4.0.0-beta.5，detected beta，latest 4.8.0，UPDATE → 4.8.0
swift run --package-path application-test channel-verify 'Zettlr-4.8.0+nightly-arm64.dmg' --expect nightly
#   → detected nightly，winning source <none>，unknown (no source answered)
swift run --package-path application-test channel-verify Zettlr-macos-x64-0.20.0.dmg --expect stable
#   → bundle com.zettlr.www，detected stable，latest 4.8.0，download = releases 页（仅检测）
codesign -dvv Zettlr.app   # → TeamIdentifier=QS52BN8W68（4.7.0 / 4.8.0 / 4.0.0-beta.5 / 4.8.0+nightly）
spctl -a -vv Zettlr.app    # → accepted, source=Notarized Developer ID
```
