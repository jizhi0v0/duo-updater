# PicGo

## 基本信息
- App: PicGo — Electron 图床上传工具，常驻菜单栏（托盘图标 + 可选 Dock 图标），内置本地 HTTP 上传服务（默认 `127.0.0.1:36677`）；MIT
- Bundle ID: `com.molunerfinn.picgo`（嵌套 helper 是 Electron 的四个 `PicGo Helper*.app`，`com.molunerfinn.picgo.helper[.GPU|.Plugin|.Renderer]`，都在 `Contents/Frameworks`）
- 仓库: `Molunerfinn/PicGo`（默认分支 `dev`）
- Team ID: `QDG8UZ6TCP`（3.0.3、3.0.2、2.5.3、2.4.2、2.4.2-beta.0 真包一致；`spctl` Notarized Developer ID）。**2.4.1 及更早没有 Team**，见「覆盖清单」
- 观测版本: 3.0.3（`CFBundleVersion` 3.0.3）；上一版 3.0.2；观测日期: 2026-10-22
- 自更新机制: **自研，只提示**。settled from source: `src/main/utils/updateChecker.ts` + `getLatestVersion.ts` on `dev` —— 启动时（`settings.showUpdateTip` 为真）取 `api.github.com/repos/Molunerfinn/PicGo/releases`（失败退到 `release.picgo.app/latest.yml`），semver 比较后弹 `dialog.showMessageBox`，点 Yes 只 `shell.openExternal('https://github.com/Molunerfinn/PicGo/releases/latest')`。不下载、不暂存。`package.json` 依赖里没有 `electron-updater`，3.0.3 的 `app.asar` 里 `grep -c -a -F electron-updater` = 0、`autoUpdater` = 0
- 分发: GitHub Releases（每版 `PicGo-<v>-arm64.dmg` + `PicGo-<v>-x64.dmg`）；Homebrew cask `picgo`（3.0.3，url 指 arm64 dmg，无 `auto_updates`，`depends_on macos >= 12`）；无 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用源，只管 cask 装的副本；本次未实测） | — | ✓ | — |
| **beta**     | —       | —        | —   | ✓（只检测，给最新稳定版） | —           |

当前生效源: **GitHub**（channel-verify 实测，3.0.2 dmg）。`feed-discover` 对 3.0.2 dmg: `review electronProviderNeedsConstruction` —— bundle 里有 electron-builder 写的 `Contents/Resources/app-update.yml`（`provider: github`, `updaterCacheDirName: picgo-updater`），但 app 不读它，`ElectronManifestSource` 也不接 github provider，所以要这条 rule。

## 覆盖清单
- **各版本的 bundle id / Team**（真包，`check-bundle.sh`）:
  | 版本 | 资产 | bundle id | Team | 签名 | 架构 |
  |---|---|---|---|---|---|
  | 3.0.3 | `PicGo-3.0.3-arm64.dmg` | `com.molunerfinn.picgo` | `QDG8UZ6TCP` | Notarized Developer ID | arm64 |
  | 3.0.2 | `PicGo-3.0.2-arm64.dmg` | 同 | `QDG8UZ6TCP` | Notarized Developer ID | arm64 |
  | 2.5.3 | `PicGo-2.5.3-arm64.dmg` | 同 | `QDG8UZ6TCP` | Notarized Developer ID | arm64 |
  | 2.4.2 | `PicGo-2.4.2-arm64.dmg` | 同 | `QDG8UZ6TCP` | Notarized Developer ID | arm64 |
  | 2.4.2-beta.0 | `PicGo-2.4.2-beta.0-arm64.dmg` | 同 | `QDG8UZ6TCP` | Notarized Developer ID | arm64 |
  | 2.4.1 | `PicGo-2.4.1-arm64.dmg` | 同 | 无（`codesign` 验证通过、`TeamIdentifier=not set`，ad-hoc） | — | arm64 |
  | 2.4.0 | `PicGo-2.4.0-arm64.dmg` | 同 | 无（`codesign-verify-exit=1`） | — | arm64 |
  | 2.3.1 | `PicGo-2.3.1-arm64.dmg` | 同 | 无（`codesign-verify-exit=1`） | — | arm64 |
  | 2.3.0-beta.8 | `PicGo-2.3.0-beta.8.dmg` | 同 | 无（`codesign-verify-exit=1`） | — | x86_64 |

  **有改名前的旧 id**：`v1.0.2`–`v1.2.1` 的 `package.json` 里 `build.appId` 是 `org.simulatedgreg.electron-vue`，`v1.3.0` 起才是 `com.molunerfinn.picgo`（`gh api repos/Molunerfinn/PicGo/contents/package.json?ref=<tag>`，实测 `v1.0.0`、`v1.0.1`、`v1.0.2`、`v1.0.3`、`v1.1.0`、`v1.2.0`、`v1.2.1` 是旧 id，`v1.3.0`、`v1.4.0`、`v1.5.0`、`v2.0.0` 是新 id）。旧 id 的包没有读真包，只读到 electron-builder 的配置，见「已知问题」。Team 只有一个，没换过；变化是「从无签名到有签名」，发生在 2.4.1 → 2.4.2-beta.0 之间。
- **其他轨**: beta，**同一个 bundle id**。版本串带 `-beta.N`（真包 `CFBundleShortVersionString` = `2.4.2-beta.0`、`2.3.0-beta.8`），`ReleaseChannel.detect` 的 Electron 点号计数规则（`-beta\.[0-9]+`）判为 `.beta`，stable rule 不服务它（见「Channel 详情」）。最后一个 beta 是 `v2.4.2-beta.0`（2025-12-31），3.x 没有发过 beta
- **版本范围**: v1.0.2–v2.3.0 的 mac 资产是不带架构的 `PicGo-<v>.dmg`（x86_64）、v1.x 还有 `picgo-<v>-mac.zip`；`v2.0.5` 一个 mac 包都没有。都不影响：stable rule 读 `/releases/latest`，只需要最新版有 `-arm64.dmg`。其中 `v1.3.0`–`v2.3.0` 的旧副本照常检测到 3.0.3（bundle id 同为 `com.molunerfinn.picgo`：`v1.3.0`–`v2.0.0` 读 `package.json` 核对过，`v2.2.0`、`v2.3.0` 的 `package.json` 里已没有 `appId`，`v2.0.1`–`v2.2.2` 没有逐版核对，2.3.0-beta.8 起以上表真包为准）；`v1.0.2`–`v1.2.1` 的副本是另一个 bundle id（`org.simulatedgreg.electron-vue`），规则不认，**检测不到**，见「已知问题」。一键见下
- **主机下限**: DuoUpdater 只出 arm64（`App/project.yml` `ARCHS: arm64`），x64 dmg 无需服务；`LSMinimumSystemVersion` 12.0（2.4.1 起），低于我们的部署下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.molunerfinn.picgo` | 共享 | 版本串无后缀 | `/releases/latest` | ✓ |
| beta    | `com.molunerfinn.picgo` | 共享 | 版本串 `-beta.N` → `.beta` | `.beta` rule 读 `/releases/latest` | ✓（只检测） |

- **beta 副本不会被当成 stable。** 版本串带 `-beta.N`，`ReleaseChannel.detect` 判 `.beta`，stable rule 不服务它。加 beta rule 之前，两个真 beta 包 channel-verify `--expect beta` 都是 `winning source <none>`、`status unknown (no source answered)`；加了之后是 `winning source GitHub`、`UPDATE → 3.0.3`、`download` 只是 releases 页（见「历史与实测」）
- 厂商 app 自己怎么分：`settings.checkBetaUpdate`（存在 PicGo 自己的 `data.json` 配置里，`!== false` 即开，**默认开**）。开着时 `getLatestVersion` 取所有非 draft release 的 semver 最大值，所以今天给 beta 副本提示的是 stable 3.0.3
- 9 个 `v2.3.0-beta.N` tag 没标 prerelease（之后的 beta 都标了），所以出现在「非 prerelease 却读不出」里；版本模式故意不收，见「更新检测」
- **beta：✓（只检测）。** 照 SmoothCSV 的做法加了一条 `channel: .beta` 的 GitHub rule：同一个仓库、同样的 tag 模式、读 `/releases/latest`，没有 `installAssetPattern` / `installerKind` / `installedTagPrefix`。beta 副本看到的是最新稳定版 3.0.3，和厂商 `checkBetaUpdate`（默认开）今天给它的提示一致；3.x 没发过 beta，所以不读 prerelease。只检测的理由：非 stable 轨的安装要 channel proof，而两条轨在 release 上没有区别，能区分的只有已装副本的版本号。副本手动换成稳定版后由 stable rule 服务，一键也就有了

## 更新检测
- 源: `Molunerfinn/PicGo` GitHub Releases，`/releases/latest`
- 版本: tag `v3.0.3` → `^v([0-9]+(?:\.[0-9]+)+)$` → `3.0.3`，等于 `CFBundleShortVersionString`（electron-builder 用 `package.json` 的 `version`）
- 对全部 tag 跑模式（2026-10-22，72 个 release，51 个非 prerelease）: 读出 42；读不出的 9 个正好是 `v2.3.0-beta.0`…`v2.3.0-beta.8`。21 个 prerelease 一个都不读。`v4.0.0`、`v3.1` 读得出，`v3.0.4-beta.0`、`v3.0.4-rc.1` 读不出（锚定）
- 安装资产模式 `^PicGo-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`: v2.3.1 起每个 stable release 恰好命中一个；`PicGo-<v>-x64.dmg`、`PicGo-<v>-beta.N-arm64.dmg`、`.blockmap` 都不命中

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`-arm64.dmg` / `-x64.dmg`），rule 只装 arm64。`LSMinimumSystemVersion`: 12.0（3.0.3）。release 不声明 OS 范围

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 有 blockmap，但没人用 | — |
| 证据 | app 不含 electron-updater（上面的 grep）；自研检查只打开网页 | 每版有 `PicGo-<v>-arm64.dmg.blockmap` 和 `latest-mac.yml`（electron-builder 默认产物） | 我们不读 blockmap |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 3.0.2，只弹了「Find new version」对话框，没有下载） | 不需要 |
| 证据 | `updateChecker.ts` 只 `shell.openExternal` 到 release 页，不下载 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 3.0.2 起）: `source structured: 1 entries; newest 3.0.3: 11 items, headings ["Features", "Performance", "Bug Fixes", "Features", "Performance", "Bug Fixes", "Windows", "macOS", "Linux"]; first items ["✨ **Choose the upload configuration per ", "Perf: Fixed the `PicGo Helper (GPU)` pro", "Fix: PicGo launching twice and showing i"]`
- **标题保留了，没被压平。** 重复的三组标题是因为厂商正文是英文一遍、`---`、中文一遍，两半用同样的 `## Features / ## Performance / ## Bug Fixes`；最后的 `Windows / macOS / Linux` 是「国内可下载链接」节的下载链接（5 条），也算进了 11 条（英 3 + 中 3 + 下载 5）
- 丢掉的: 每版 `## Features` 下开头的介绍段落（列表前的段落，同 Harp 记录的 `GitHubMarkdownParser.sectionProse` 取舍）、代码块和表格。真正的改动都写成了列表项，所以面板上有内容
- 跟随 channel: —（beta rule 读的也是稳定版正文）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 3.0.2 → `duo check` `3.0.2 → 3.0.3 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 3.0.3、可执行文件 inode 变、`TeamIdentifier=QDG8UZ6TCP`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 3.0.3 包相同
  - 第二轮（运行中）: 启动 3.0.2，它弹出自己的「Find new version 3.0.3 … do you want to download the latest version?」（No More Notice / No / Yes）。`duo install` 照常换包（`Still running the old code`）；**这个对话框开着时 `duo restart PicGo` 退不掉它**：`still running — likely a save prompt, left it alone`，旧进程留着、磁盘已是 3.0.3。点掉对话框的 No 后再 `duo restart PicGo` → 新进程起来，之后 10 s 磁盘一直是 3.0.3、签名有效
- 格式: dmg（`hdiutil imageinfo`: `Format: UDZO`, UDIF read-only compressed (zlib)），根目录 `PicGo.app` + `Applications` 软链
- 嵌套: 只有 `Contents/Frameworks` 里的四个 Electron helper（`LSUIElement=true`，随主进程起落）；没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent
- 签名: 3.0.2 和 3.0.3 都是 `QDG8UZ6TCP`、Notarized
- 校验: GitHub 资产 `digest`。下载的 `shasum -a 256` 与 API 的 `digest` 相同：3.0.3 `8eaed1a22a01eb3cd2f41e4d3ac5d672b51ac5c56e1b4d7add4688acb9ad2c5b`（160123371 字节），3.0.2 `12e12ca0e6c85fac0a82532ea67e36e46a94b7331f1489bf800569d4bc262772`（159758553 字节）。GitHub 规则不需要逐条配置
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，即厂商自己更新提示打开的那一页）
- 阻塞 / 拒装的副本:
  - **2.4.1 及更早**（ad-hoc 或无签名）: 检测正常（channel-verify 2.4.1 → `UPDATE → 3.0.3`），一键被 Team 闸拒（安装副本无 Team，`SignatureVerifier.verifyTeamIdentifierMatch` 抛 `noTeamIdentifier(which: "installed")`），用户手动更新一次。`.publishedDigestOnly` 不适用：它要求两边都没有 Team，而下载包有 `QDG8UZ6TCP`
  - beta 副本: 有检测（3.0.3），没有一键：beta rule 只检测，`download` 是 releases 页，见「Channel 详情」

## 已知问题
- `v1.0.2`–`v1.2.1` 的副本（旧 bundle id `org.simulatedgreg.electron-vue`）检测不到 3.0.3，也不会被提示。证据：`package.json` 在 `v1.0.2`、`v1.1.0`、`v1.2.0`、`v1.2.1` 的 `build.appId` 都是 `org.simulatedgreg.electron-vue`，`v1.3.0` 改成 `com.molunerfinn.picgo`；这几个版本的 release 只有 `PicGo-<v>.dmg`（`v1.2.0`/`v1.2.1` 另带 `picgo-<v>-mac.zip`）。没有做 `BundleIDMigration`：这个 id 是 electron-vue 脚手架留下的，不是 PicGo 独有。electron-vue 模板 `template/package.json` 的早期提交写死了它，后来才改成提示输入 `{{ appid }}`（默认 `com.example.yourapp`），GitHub 代码搜索 `"org.simulatedgreg.electron-vue" in:file filename:package.json` 命中 258 个文件，分属 `PanJiaChen/electron-vue-admin`、`SmallRuralDog/electron-vue-music` 等互不相干的项目。对这个 id 做迁移，会把别的 electron-vue 应用也当成 PicGo。旧 id 的 `CFBundleIdentifier` 没有读真包（未下载 1.x 的 dmg），只读到 `package.json` 里的 electron-builder 配置
- 启动副作用（读源码得来；2026-10-22 真机核对的已注明）:
  - 首启把 `public/Upload pictures with PicGo.workflow` 复制到 `~/Library/Services/`（`src/main/utils/beforeOpen.ts` `resolveMacWorkFlow`，已存在就跳过）——Finder 右键「服务」菜单项。cask 的 `zap` 也列了这个路径。真机：首启即写出
  - 配置和数据写在 `~/Library/Application Support/picgo/`
  - 登录项: `app.setLoginItemSettings({ openAtLogin: settings.autoStart || false })`（`src/main/lifeCycle/index.ts`），**默认关**；开了也是主 app 本身，不是 helper
  - 启动即开本地 HTTP 服务（`server.startup()`，默认端口 36677）。真机：`lsof` 见 `127.0.0.1:36677 (LISTEN)`
  - 有新版时弹一个 Yes/No 消息框（无父窗口），点 Yes 打开浏览器。真机：启动即弹；它开着时 app 不响应退出，`duo restart` 会如实报「likely a save prompt」并不动它
  - 注册全局快捷键（`shortKeyHandler.init()`）
- 2.4.1 及更早的副本一键被拒，见上

## 如何复验
```
gh api repos/Molunerfinn/PicGo/releases/tags/v3.0.3 -q '.assets[]|.name+" "+(.size|tostring)+" "+.digest'
.claude/skills/coverage-discovery/scripts/check-bundle.sh PicGo-3.0.3-arm64.dmg     # → Team QDG8UZ6TCP, Notarized, arm64
swift run --package-path application-test feed-discover PicGo-3.0.2-arm64.dmg       # → review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify PicGo-3.0.2-arm64.dmg --expect stable
#   detected channel → stable; winning source GitHub; latest 3.0.3;
#   download https://github.com/Molunerfinn/PicGo/releases/download/v3.0.3/PicGo-3.0.3-arm64.dmg; status UPDATE → 3.0.3
swift run --package-path application-test channel-verify PicGo-3.0.3-arm64.dmg --expect stable
#   winning source GitHub; latest 3.0.3; status up to date
swift run --package-path application-test channel-verify PicGo-2.4.0-beta.10-arm64.dmg --expect beta
#   detected channel → beta; winning source GitHub; latest 3.0.3;
#   download https://github.com/Molunerfinn/PicGo/releases; status UPDATE → 3.0.3
swift run --package-path application-test channel-verify PicGo-2.4.1-arm64.dmg --expect stable
#   detected channel → stable; winning source GitHub; status UPDATE → 3.0.3
```

## 历史与实测

### 2026-10-22 —— beta 副本加只检测的 `.beta` rule

- 加 rule 之前（同日接入时）: `PicGo-2.4.2-beta.0-arm64.dmg`、`PicGo-2.3.0-beta.8.dmg` channel-verify `--expect beta` 都是 `detected channel → beta`、`winning source <none>`、`status unknown (no source answered)`
- 厂商行为: `src/main/utils/updateChecker.ts`（`dev`）里 `isCheckBetaUpdate = getConfig('settings.checkBetaUpdate') !== false`，传给 `getLatestVersion`；`/releases/latest` 是 `v3.0.3`（`prerelease: false`）
- 加 rule 之后，`PicGo-2.4.0-beta.10-arm64.dmg`（93119301 字节，sha256 `ddf5a477af295cf9ffbca1a36536089ed144147a3d820a99b7c8e7c1e3e907a5`，与 API `digest` 相同）:
  ```
  short version   2.4.0-beta.10
  detected channel  → beta
  ✓ detection matches --expect beta
  winning source  GitHub
  latest          3.0.3
  download        https://github.com/Molunerfinn/PicGo/releases
  status          UPDATE → 3.0.3
  ```
- 对照 `PicGo-3.0.2-arm64.dmg` `--expect stable`，结果不变: `winning source GitHub`、`latest 3.0.3`、`download https://github.com/Molunerfinn/PicGo/releases/download/v3.0.3/PicGo-3.0.3-arm64.dmg`、`UPDATE → 3.0.3`
