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
| **beta**     | —       | —        | —   | ○      | —           |

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

  没有改名前的旧 id。Team 只有一个，没换过；变化是「从无签名到有签名」，发生在 2.4.1 → 2.4.2-beta.0 之间。
- **其他轨**: beta，**同一个 bundle id**。版本串带 `-beta.N`（真包 `CFBundleShortVersionString` = `2.4.2-beta.0`、`2.3.0-beta.8`），`ReleaseChannel.detect` 的 Electron 点号计数规则（`-beta\.[0-9]+`）判为 `.beta`，stable rule 不服务它（见「Channel 详情」）。最后一个 beta 是 `v2.4.2-beta.0`（2025-12-31），3.x 没有发过 beta
- **版本范围**: v1.0.2–v2.3.0 的 mac 资产是不带架构的 `PicGo-<v>.dmg`（x86_64）、v1.x 还有 `picgo-<v>-mac.zip`；`v2.0.5` 一个 mac 包都没有。都不影响：stable rule 读 `/releases/latest`，只需要最新版有 `-arm64.dmg`。这些旧副本照常检测到 3.0.3；一键见下
- **主机下限**: DuoUpdater 只出 arm64（`App/project.yml` `ARCHS: arm64`），x64 dmg 无需服务；`LSMinimumSystemVersion` 12.0（2.4.1 起），低于我们的部署下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.molunerfinn.picgo` | 共享 | 版本串无后缀 | `/releases/latest` | ✓ |
| beta    | `com.molunerfinn.picgo` | 共享 | 版本串 `-beta.N` → `.beta` | 无 rule，GitHub 源跳过 | ○ |

- **beta 副本不会被当成 stable。** 两个真 beta 包 channel-verify `--expect beta` 都是 `detected channel → beta`、`winning source <none>`、`status unknown (no source answered)`（原始输出见「如何复验」）。不需要 `OneClickGate`：gate 是「有检测、只扣一键」的场景，而 beta 副本根本拿不到 stable 的 offer
- 厂商 app 自己怎么分：`settings.checkBetaUpdate`（存在 PicGo 自己的 `data.json` 配置里，`!== false` 即开，**默认开**）。开着时 `getLatestVersion` 取所有非 draft release 的 semver 最大值，所以今天给 beta 副本提示的是 stable 3.0.3
- 9 个 `v2.3.0-beta.N` tag 没标 prerelease（之后的 beta 都标了），所以出现在「非 prerelease 却读不出」里；版本模式故意不收，见「更新检测」
- **beta 是缺口 ○，不是被挡掉。** 可以照 CotEditor / SwitchHosts 的做法加一条 `.beta` rule（`usePrereleases: true`，版本模式同时收 `-beta.N` 和纯数字 tag，再加 `githubChannelProofs`），让 beta 副本也拿到 3.0.3，和厂商自己的提示一致。本次没做，交主会话决定

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
| 结论 | 不会 | 没查（真机第二轮待主会话） | 不需要 |
| 证据 | `updateChecker.ts` 只 `shell.openExternal` 到 release 页，不下载 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 3.0.2 起）: `source structured: 1 entries; newest 3.0.3: 11 items, headings ["Features", "Performance", "Bug Fixes", "Features", "Performance", "Bug Fixes", "Windows", "macOS", "Linux"]; first items ["✨ **Choose the upload configuration per ", "Perf: Fixed the `PicGo Helper (GPU)` pro", "Fix: PicGo launching twice and showing i"]`
- **标题保留了，没被压平。** 重复的三组标题是因为厂商正文是英文一遍、`---`、中文一遍，两半用同样的 `## Features / ## Performance / ## Bug Fixes`；最后的 `Windows / macOS / Linux` 是「国内可下载链接」节的下载链接（5 条），也算进了 11 条（英 3 + 中 3 + 下载 5）
- 丢掉的: 每版 `## Features` 下开头的介绍段落（列表前的段落，同 Harp 记录的 `GitHubMarkdownParser.sectionProse` 取舍）、代码块和表格。真正的改动都写成了列表项，所以面板上有内容
- 跟随 channel: —（beta 无 rule）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（rule 已写；真机端到端**未跑**，待主会话）
- 端到端: 未跑——按分工由主会话做
- 格式: dmg（`hdiutil imageinfo`: `Format: UDZO`, UDIF read-only compressed (zlib)），根目录 `PicGo.app` + `Applications` 软链
- 嵌套: 只有 `Contents/Frameworks` 里的四个 Electron helper（`LSUIElement=true`，随主进程起落）；没有 `Contents/Library/LoginItems`、`Contents/Helpers`、LaunchAgent
- 签名: 3.0.2 和 3.0.3 都是 `QDG8UZ6TCP`、Notarized
- 校验: GitHub 资产 `digest`。下载的 `shasum -a 256` 与 API 的 `digest` 相同：3.0.3 `8eaed1a22a01eb3cd2f41e4d3ac5d672b51ac5c56e1b4d7add4688acb9ad2c5b`（160123371 字节），3.0.2 `12e12ca0e6c85fac0a82532ea67e36e46a94b7331f1489bf800569d4bc262772`（159758553 字节）。GitHub 规则不需要逐条配置
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，即厂商自己更新提示打开的那一页）
- 阻塞 / 拒装的副本:
  - **2.4.1 及更早**（ad-hoc 或无签名）: 检测正常（channel-verify 2.4.1 → `UPDATE → 3.0.3`），一键被 Team 闸拒（安装副本无 Team，`SignatureVerifier.verifyTeamIdentifierMatch` 抛 `noTeamIdentifier(which: "installed")`），用户手动更新一次。`.publishedDigestOnly` 不适用：它要求两边都没有 Team，而下载包有 `QDG8UZ6TCP`
  - beta 副本: 没有 offer，见上

## 已知问题
- 启动副作用（读源码得来，真机未观测）:
  - 首启把 `public/Upload pictures with PicGo.workflow` 复制到 `~/Library/Services/`（`src/main/utils/beforeOpen.ts` `resolveMacWorkFlow`，已存在就跳过）——Finder 右键「服务」菜单项。cask 的 `zap` 也列了这个路径
  - 配置和数据写在 `~/Library/Application Support/picgo/`
  - 登录项: `app.setLoginItemSettings({ openAtLogin: settings.autoStart || false })`（`src/main/lifeCycle/index.ts`），**默认关**；开了也是主 app 本身，不是 helper
  - 启动即开本地 HTTP 服务（`server.startup()`，默认端口 36677）
  - 有新版时弹一个 Yes/No 消息框（无父窗口），点 Yes 打开浏览器
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
swift run --package-path application-test channel-verify PicGo-2.4.2-beta.0-arm64.dmg --expect beta
#   short version 2.4.2-beta.0; detected channel → beta; winning source <none>; status unknown (no source answered)
swift run --package-path application-test channel-verify PicGo-2.3.0-beta.8.dmg --expect beta
#   short version 2.3.0-beta.8; detected channel → beta; winning source <none>; status unknown (no source answered)
swift run --package-path application-test channel-verify PicGo-2.4.1-arm64.dmg --expect stable
#   detected channel → stable; winning source GitHub; status UPDATE → 3.0.3
```

## 建议下一步
1. 真机端到端（主会话）：3.0.2 → 3.0.3，不运行 + 运行中 + `duo restart`。
2. 决定是否给 beta 副本加 `.beta` rule（CotEditor / SwitchHosts 式，收 `-beta.N` 和纯数字 tag，加 channel proof）。不加的话 beta 副本一直显示「未知」。
