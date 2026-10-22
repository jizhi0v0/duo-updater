# Bdash

## 基本信息
- App: Bdash — 开源 SQL 客户端（Electron，「Simple SQL Client for lightweight data analysis」），带一个可选的 MCP server；MIT
- Bundle ID: `io.bdash`（`electron-builder.yml` 的 `appId`；1.17.1、1.35.3、1.35.4 三个真包一致）
- 仓库: `bdash-app/bdash`
- Team ID: `4GERXBURZN`（1.35.4、1.35.3、1.17.1 都是；`spctl` 均为 `Notarized Developer ID`）
- 观测版本: 1.35.4（`CFBundleVersion` 1.35.4）；上一版 1.35.3；观测日期: 2026-10-22（两版都是当天发的）
- 自更新机制: **无下载能力，只提示**。`src/main/updateChecker.ts` 读 `https://api.github.com/repos/bdash-app/bdash/releases/latest` 比版本；`src/main/menu.ts` 的「Check for Updates...」只弹框，按「Open Download Page」用 `shell.openExternal` 开网页（1.35.4 起，PR #365；之前是在弹框里写一行 URL）。只在点菜单时跑，启动不检查
- 分发: GitHub Releases（每版 universal dmg + universal zip + blockmap + Windows/Linux 包）；Homebrew cask `bdash`（下载 GitHub 的 `-universal-mac.zip`，无 `auto_updates`，`depends_on macos >= 12`，2026-10-22 还停在 1.35.3）；无 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用 cask 路径） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测 `winning source  GitHub`）。

`feed-discover` 对 1.35.3 dmg:
```
Bdash  [io.bdash]  1.35.3
   review    electronProviderNeedsConstruction
```
包里有 `Contents/Resources/app-update.yml`（`provider: github`、`updaterCacheDirName: bdash-updater`），通用 electron 源从 github provider 拼不出 manifest 地址，所以要一条 GitHubReleaseRule（同 `com-plexo-app`）。

## 覆盖清单
- **bundle id**: 只有 `io.bdash`。1.17.1（x86_64，2024-10）、1.35.3、1.35.4 真包一致；`appId: io.bdash` 写在 `electron-builder.yml`。没有改名前的旧 id，没有同仓库的其他产品
- **轨道**: 只有 stable。69 个非 prerelease 的 release；prerelease 只有 2016–2017 的 `1.0.0-beta1`…`1.0.0-rc2`（11 个，都标了 prerelease）。没有 nightly / beta 发版脚本
- **版本范围 / Team**: 1.17.1、1.35.3、1.35.4 都是 Team `4GERXBURZN`、公证通过。公证从 2020-05-06（`scripts/notarize.js` 首个提交「Notarization for macOS」）开始；更老的 1.x 副本未下载核对（未验证），它们若没签名/没公证，安装闸会拒其一键，检测不受影响
- **主机下限**: 1.35.x `LSMinimumSystemVersion` 12.0，1.17.1 是 10.11.0；都低于 DuoUpdater 自身的下限，不需要 `hostRequirement`
- **架构**: 1.19.1 起出 universal（`Bdash-<v>-universal.dmg`），之前是 x86_64 单架构 `Bdash-<v>.dmg`。只装最新版，所以老副本也拿 universal 包，不需要架构门控
- **版本模式**: 见「更新检测」，69/69 非 prerelease tag 都读得出

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.bdash` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `bdash-app/bdash` GitHub Releases，`/releases/latest`（2026-10-22 指向 `v1.35.4`）
- 版本: tag `v1.35.4` → `^v?([0-9]+(?:\.[0-9]+)+)$` → `1.35.4`，等于 `CFBundleShortVersionString`（`package.json` 的 `version`）
- **待审「有 tag 读不出」的结论: 放宽到 `^v?`。** 分诊时 `^v…` 读出 62/67，读不出的是 `1.2.2`、`1.2.1`、`1.2.0`、`1.1.0`、`1.0.0`。这五个是同一个产品 2017 年的正式版（资产 `Bdash-1.2.2-macOS.zip`、`Bdash-Setup-1.2.2.exe` 等，同一仓库、同名 app），只是当时 tag 不带 `v`；`v1.3.0`（2018-05）起统一带 `v`。不是 mobile / nightly / 别的产品。放宽后实测：
  ```
  stable 69 read 69 []
  prerelease matched: []
  v2.0.0 2.0.0
  v1.36 1.36
  v1.36.0-rc.1 None
  v1.36.0-beta.1 None
  ```
  （python `re` 跑同一个 pattern；69 = 今天的非 prerelease 数，分诊时 67，之后多了 v1.35.3、v1.35.4。）实际上只读 `/releases/latest`，这五个老 tag 不会再成为 latest，放宽对今天的检测是惰性的，只为了模式描述的就是这个产品的全部 tag
- 资产: `^Bdash-[0-9]+(?:\.[0-9]+)+-universal\.dmg$`，只命中 dmg，不命中 `-universal-mac.zip`、`.blockmap`、1.18.0 及更早的 `Bdash-<v>.dmg`
- channel-verify（2026-10-22，真包）:
  - 1.35.3 → `winning source  GitHub` · `latest 1.35.4` · `download https://github.com/bdash-app/bdash/releases/download/v1.35.4/Bdash-1.35.4-universal.dmg` · `status UPDATE → 1.35.4`
  - 1.17.1 → 同上，`status UPDATE → 1.35.4`
  - 1.35.4 → `status up to date`

## 按架构 / 按 OS 分轨
- 一个 universal dmg（`lipo`: `x86_64 arm64`）；release 不声明 OS 范围，Info.plist `LSMinimumSystemVersion` 12.0

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 有 blockmap（electron-builder 差分下载用） | 不消费 |
| 证据 | app.asar（13937 条）里没有 `electron-updater`，二进制里没有 `autoUpdater.` / `quitAndInstall`；`package.json` 依赖没有 electron-updater | 每版有 `*.dmg.blockmap`、`*-mac.zip.blockmap`、`latest-mac.yml` | 没有客户端会用它；我们下整包 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 1.35.3，没有更新器） | 不需要 |
| 证据 | 自带的「更新」只开网页，不下载（`menu.ts`）；`app-update.yml` 的 `updaterCacheDirName: bdash-updater` 没有代码读 | — | — |

SelfUpdaterStash 不适用：没有暂存。

## Changelog
- 来源: GitHub Release body（GitHub 自动生成的 `## What's Changed` + `* … by @x in <PR>` + `**Full Changelog**`），经 `GitHubMarkdownParser`
- channel-verify `changelog pane`（从 1.35.3 起）: `source structured: 1 entries; newest 1.35.4: 2 items, headings []; first items ["bump v1.35.3", "Make the update download page accessible"]`
- 生产解析器逐条（临时探针测试直接调 `GitHubMarkdownParser.parse`，用完已删）:
  ```
  PROBE v1.35.4 entries=1
  PROBE   item: bump v1.35.3
  PROBE   item: Make the update download page accessible from the notification dialog
  PROBE v1.35.0 entries=1
  PROBE   item: Add query ID and update notification badge to query list
  PROBE   item: Use native title bar on macOS
  PROBE v1.30.1 entries=1
  PROBE   item: Query results table rows highlight on hover.
  PROBE   item: Dark mode
  PROBE   item: Add required field validation for datasource creation
  PROBE   item: Fix query status not persisting when switching between queries
  PROBE   item: Update layout splitter color for dark theme
  ```
  `by @user in <url>` 署名被去掉，`Full Changelog` 链接不进条目。唯一的标题 `What's Changed` 不保留（`content` 为空），条目平铺——这个标题只是 GitHub 的通用标签，平铺不丢信息
- 厂商的 bump PR（「bump v1.35.3」）会作为一条出现，这是厂商正文本身的内容
- channel-verify 的 `release history 1 entries`：GitHub 源只读 latest，从 1.17.1 起也只显示 1.35.4 一条
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（`.developerID` + dmg），真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
  - 第一轮（不运行）: 1.35.3 → `duo check` `1.35.3 → 1.35.4 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 1.35.4、可执行文件 inode 变、`TeamIdentifier=4GERXBURZN`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 1.35.4 包相同
  - 第二轮（运行中）: 启动 1.35.3（一个主窗口），`duo install` 后提示 `Still running the old code`；`duo restart Bdash` 后新进程起来，之后 10 s 磁盘一直是 1.35.4、签名有效
- 格式: dmg，`hdiutil imageinfo` `Format: UDZO`；根目录 `Bdash.app` + `Applications -> /Applications` 软链 + 背景图
- 嵌套: 只有 Electron 的四个 Helper（`io.bdash.helper`、`.GPU`、`.Plugin`、`.Renderer`，都 `LSUIElement`），无 `Contents/Library`（无 LoginItems / LaunchAgents / LaunchServices）。app.asar 里没有 `openAtLogin` / `setLoginItemSettings` / `LaunchAgents` / `setAsDefaultProtocolClient`；Info.plist 无 `CFBundleURLTypes`
- 签名: 1.35.3、1.35.4（以及 1.17.1）`TeamIdentifier=4GERXBURZN`、`codesign --verify` exit 0、`spctl` Notarized Developer ID；hardened runtime，entitlements `allow-jit`、`allow-unsigned-executable-memory`、`disable-library-validation`
- 校验: GitHub 资产 `digest`。v1.35.4 dmg `sha256:75be2be37c29e5ccc4160e905cb9acbef8de392016339fcb8078a4f644e505df`（256334401 字节），v1.35.3 dmg `sha256:869d5f458861c3c9694edabc3fccf5913f8d80d42ad5b99a39f1ff9658b34f06`（243704665 字节）；`gh release download` 后 `shasum -a 256` 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，app 自己的「Check for Updates...」也读这个端点）
- 启动副作用（来自源码/包内容；2026-10-22 真机核对的已注明）:
  - 首次启动写 `~/.bdash/bdash.sqlite3`（`src/mcp/src/database.ts` 的默认路径；cask `zap` 也列了 `~/.bdash`）、`~/Library/Application Support/Bdash`、`~/Library/Logs/Bdash`、`~/Library/Preferences/io.bdash.plist`。真机：首启这四处都建了
  - 不自动往 `~/.claude` / `~/.agents` 写东西：设置页的「MCP Server」只显示一段 JSON 和「Copy」按钮（`Setting.tsx`，`clipboard.writeText`）；app.asar 里的 `.agents` 两处命中是 `follow-redirects` 的 `this._options.agents`，不是路径
  - **MCP server 进程**：用户若照 README 把 `node /Applications/Bdash.app/Contents/Resources/mcp/server.js` 配进 Claude Code，那个 node 进程由 MCP 客户端启动、不是 Bdash 的进程，换包后它还在跑旧文件里的代码，直到客户端重启它（我的推断，未验证；duo 的「运行中」判断是否把它算进去也未验证）
  - 无登录项、无 LaunchAgent、无 root helper、不改默认 app

## 已知问题
- MCP server 进程见上
- 1.17.1 之前的老副本的 Team / 公证未逐个下载核对

## 建议下一步
1. 下一个正式版出来后复查 `/releases/latest` 指向它、资产名仍是 `Bdash-<v>-universal.dmg`。

## 如何复验
```
gh release view v1.35.4 -R bdash-app/bdash --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Bdash-1.35.3-universal.dmg     # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Bdash-1.35.3-universal.dmg --expect stable   # → GitHub，UPDATE → 1.35.4
swift run --package-path application-test channel-verify Bdash-1.35.4-universal.dmg --expect stable   # → up to date
.claude/skills/coverage-discovery/scripts/check-bundle.sh Bdash-1.35.4-universal.dmg   # → io.bdash, 4GERXBURZN, Notarized
```
