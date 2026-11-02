# OpenCode Desktop

## 基本信息
- Bundle ID: `ai.opencode.desktop`
- Team ID: `5NZ4Q7NXJ4`
- 已验证版本: `1.18.18`（short/build 相同）；2.x 为 `2.2.5`（2026-10-31 实测，见「历史与实测」）
- 自更新机制: 1.x 是 electron-updater 6.8.9 + GitHub Releases（`provider: github`）；
  2.x 换成厂商自己的 generic 更新源 `https://opencode.ai/update/api/latest/desktop/opencode/`

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | —      | ✓           |

当前生效源: **VendorProbe**（厂商的 desktop 更新清单）。cask 为 `auto_updates:true`，Homebrew 不参与检测。
GitHub 那条规则已移除：GitHub 源排在 probe 之前，只要它还能答（1.19.5），probe 永远不会被问到 2.x。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `ai.opencode.desktop` | 清单 `latest-mac.yml` 的 `version:`（arm64 条目 + `hostRequirement`） | ✓ |

## 更新检测
- 源: `https://opencode.ai/update/api/latest/desktop/opencode/latest-mac.yml` —— 2.x 包内
  `app-update.yml` 自己声明的地址（`provider: generic`），也就是 `ElectronManifestSource` 会读的那份清单；
  1.x 包内写的是 `provider: github`，只能解析出 1.19.5，所以对 1.x 安装必须由 probe 提供 2.x。
- 版本取清单自己的 `version:`（不是产物路径里的目录名）。
- 只对 arm64 生效（`hostRequirement`）：DuoUpdater 本体是 arm64 应用，清单里的 x64 产物在本机不可用。

## Changelog
- `ChangelogRecipe`（`Recipes/ai-opencode-desktop.swift`）读 GitHub releases API（`OpencodeRelease.listURL`，
  30 条），格式 `.opencodeReleases`：与 OpenCode CLI 用同一个 `OpencodeRelease.parseNotes`，每条正文读到
  `**Thank you to N community contributors:**` 为止，贡献者名单不进条目。2.x 的说明仍发在这些 release 上。
- 测试 `openCodeDesktopNotesStopAtTheContributorCredits`（v1.18.35 的真实正文）。

## 一键安装
- 状态: ✓，清单里 arm64 的那份 DMG（不是同条目的 zip，也不是 x64）。
- 校验: 同一产物条目的 `sha512:`（electron-updater 的 base64 SHA-512），下载后先对摘要再过签名闸。
- 安全: 2.2.5 的 DMG 已确认 notarized（`spctl`: "Notarized Developer ID"），Team `5NZ4Q7NXJ4`，
  bundle id 与 1.x 相同 —— 所以它是**就地替换**，即 1.x → 2.x 的迁移。

## 自更新器行为（2026-09-16 实测）

它的主进程设置 `autoUpdater.autoInstallOnAppQuit = false`（从 `app.asar` 的
`out/main/index.js` 读出），弹窗文案是 `Update {{version}} downloaded. Restart now?`。
`MacUpdater` 继承 `AppUpdater`，macOS 这条路径上没有别的退出钩子，所以：

- **退出这个 app 不会应用它已下载的更新。** 实测：正常退出后观察 120 秒，
  `/Applications/OpenCode.app` 的版本没有变化，`~/Library/Caches/ai.opencode.desktop.ShipIt/`
  没有被写入。只有它自己弹窗上的 Restart（走 `quitAndInstall`）才会把包交给 Squirrel。
- 所以**不要给它接 Relaunch**：那条路径等的是磁盘被换掉，在这里会坐到超时然后报假失败。
- `~/Library/Caches/ai.opencode.desktop.ShipIt/ShipItState.plist` 可能是很旧的残留，
  指向一个已经不存在的 `update.<随机>/OpenCode.app`。`SelfUpdaterStaging.staged` 的
  `fileExists` 闸会正确地把它判为 nil —— 这不是故障。

## 已下载但未应用的安装包

下载完成后，包落在 electron-updater 自己的缓存里，不在 ShipIt：

```
~/Library/Caches/@opencode-aidesktop-updater/pending/
  opencode-desktop-mac-arm64.zip      ← 真正的包
  update-info.json                    ← {"fileName","sha512","isAdminRightsRequired"}，没有版本号
```

目录名来自 bundle 里的 `Contents/Resources/app-update.yml` 的
`updaterCacheDirName: '@opencode-aidesktop-updater'`。

⚠️ **版本只能从包里读**：`update-info.json` 不带版本，文件名也不带
（`opencode-desktop-mac-arm64.zip`）。读 zip 里顶层 `OpenCode.app/Contents/Info.plist`
即可，别取嵌套的 Helper。

**容器不对称（1.x）**：旧的 GitHub 规则取的是 release 里的 `…-mac-arm64.dmg`，而 electron-updater
在 macOS 上只下 zip。同一版本、同一 Team、都公证过，但容器不同。2.x 起我们改走厂商清单里的
arm64 DMG（带同一产物的 `sha512`），这条不对称也就不再有意义；zip 只属于 app 自己的更新器。

复核方式：清单里的 `sha512` 与 `size` 可以和 `update-info.json` 逐字对照
（2026-09-16 对 v1.18.31 核过，两边一致，size 149629372）。2.x 的 pending 目录名随
`app-update.yml` 变成 `@opencodedesktop-updater`（2026-10-31 从 2.2.5 包里读出）。

机制与闸链见 `docs/engine-notes/self-updater-stash.md`。

## 已知问题
- 无。

## 建议下一步
1. 保持清单 `version:`、arm64 DMG 与 sha512 的 fixture 测试。

## 历史与实测
- 2026-10-31，2.0 换线：`/Applications/OpenCode.app` 是 1.19.4（`app-update.yml` 为 `provider: github`），
  而 2.x 的桌面线已搬到厂商自己的清单：
  `https://opencode.ai/update/api/latest/desktop/opencode/latest-mac.yml` → `version: 2.2.5`
  （arm64 dmg 329,627,154 字节，`sha512: yPqDeFY7…`；zip 298,567,019 字节）。
  GitHub 侧 `releases/latest` 仍是 `v1.19.5`（仓库的 Latest 标记没挪），所以旧规则只可能报 1.19.5。
  下载 arm64 dmg 实测：sha256 `aecc7365fe041798d6fdeee6e82c5aad020e2e0282f9658091bd3255db4789d5`
  （与清单 `sha256` 一致），挂载后 `OpenCode.app` 是 `ai.opencode.desktop` 2.2.5、
  Team `5NZ4Q7NXJ4`、`spctl`: "Notarized Developer ID"，bundle 内只有 Electron helpers，dmg 里也没有
  其它组件 —— 与 1.x 同 bundle id、同 Team，可就地替换。
  1.x 与 2.x 的版本字面量形状不同（CLI 那侧 `--user-agent=opencode/latest/2.2.5/cli`），见
  `docs/engine-notes/opencode-check.md`。
- 2026-10-31，真机 1.x → 2.x（同一台开发机）：`duo check` 报 `OpenCode 1.19.4 → 2.2.5 [Vendor, in-place]`；
  `duo verify --only opencode` ✓（1 条 probe）；`duo verify-install --only opencode` 真下载 329.6 MB、
  17 秒、判 `ai.opencode.desktop / 5NZ4Q7NXJ4` ✓。随后 `duo install /Applications/OpenCode.app`
  （大版本需要它自己的确认）走完 download → verifyingSignature → extracting →
  verifyingCodeSignature → installing，装完为 2.2.5，`codesign --verify --deep --strict` 通过、
  `spctl` 仍 "Notarized Developer ID"。CLI 那条没有跟着升：按设计只给命令。
  `verify/identities.json` 里旧的 `github:anomalyco/opencode:stable` 条目被这次 `verify-install`
  换成了 `vendor:ai.opencode.desktop:stable`（2.2.5，arm64，Team `5NZ4Q7NXJ4`）。
  ⚠️ 这次会话里**没能确认 GUI 能否启动**：从该 shell 里 `open` 1.19.4 和 2.2.5 都会在一秒内退出
  （同一路径下 TextEdit 正常），所以那不是 2.x 的问题证据，需要用户在 Finder 里双击确认。
  回滚物：v1.19.4 的 arm64 dmg 仍在 GitHub release 上（151,566,638 字节），本次装回并验过签名。
  另外实测 `duo install` 这条 CLI 路径**没有**给这次替换留还原点（`duo backups` 里只有 Backdrop），
  跨大版本想要可回滚，得在 app 里点 "Back Up & Update"。
- 2026-10-08，旧 recipe（抓 github.com/anomalyco/opencode/releases 页面、`<li>` 条目）: 页面上 10 个 release
  共 27 条 `@handle: <pull-request title>` 贡献者行混在条目里（如 v1.18.35 2 条改动显示 5 条）。
  改读 API + `.opencodeReleases` 后，这 10 个版本每个只少了贡献者行（5→2、6→3、9→4、4→2、7→3、8→5、
  4→2、4→3、7→5、10→7），没有丢真改动；条目改为 Markdown，行内代码保留反引号，分类标题会显示。
  窗口从页面的 10 个 release 变为 API 的 30 个。
