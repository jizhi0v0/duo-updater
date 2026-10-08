# OpenCode Desktop

## 基本信息
- Bundle ID: `ai.opencode.desktop`
- Team ID: `5NZ4Q7NXJ4`
- 已验证版本: `1.18.18`（short/build 相同）
- 自更新机制: electron-builder / electron-updater 6.8.9 / GitHub Releases

## 覆盖矩阵

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✗        | —   | ✓      | —           |

当前生效源: **GitHub**。cask 为 `auto_updates:true`，Homebrew 不参与检测。

## Channel 详情

| Channel | Bundle ID | 检测信号 | 状态 |
|---------|-----------|----------|------|
| stable | `ai.opencode.desktop` | GitHub stable tag `vX.Y.Z` | ✓ |

## 更新检测
- 源: `anomalyco/opencode` GitHub Releases。
- tag `v1.18.18` 与真实包 short/build `1.18.18` 同构。

## Changelog
- `ChangelogRecipe`（`Recipes/ai-opencode-desktop.swift`）读 GitHub releases API（`OpencodeRelease.listURL`，
  30 条），格式 `.opencodeReleases`：与 OpenCode CLI 用同一个 `OpencodeRelease.parseNotes`，每条正文读到
  `**Thank you to N community contributors:**` 为止，贡献者名单不进条目。
- 测试 `openCodeDesktopNotesStopAtTheContributorCredits`（v1.18.35 的真实正文）。

## 一键安装
- 状态: ✓，host-native arm64/x64 DMG。
- 安全: arm64 DMG 已确认 notarized，Team `5NZ4Q7NXJ4`。

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

**格式不对称**：我们这条 `GitHubReleaseRule` 取的是 `…-mac-arm64.dmg`，而 electron-updater
在 macOS 上只下 zip。同一版本、同一 Team、都公证过，但容器不同 —— 所以路线自带的
`expectedSHA512` / `nestedArchivePath` 描述的是 dmg，不能套到这份 zip 上。

复核方式：`latest-mac.yml` 是每个 release 的资产，里面的 `sha512` 与 `size` 可以和
`update-info.json` 逐字对照（2026-09-16 对 v1.18.31 核过，两边一致，size 149629372）。

机制与闸链见 `docs/engine-notes/self-updater-stash.md`。

## 已知问题
- 无。

## 建议下一步
1. 保持 GitHub tag 与资产文件名 fixture 测试。

## 历史与实测
- 2026-10-08，旧 recipe（抓 github.com/anomalyco/opencode/releases 页面、`<li>` 条目）: 页面上 10 个 release
  共 27 条 `@handle: <pull-request title>` 贡献者行混在条目里（如 v1.18.35 2 条改动显示 5 条）。
  改读 API + `.opencodeReleases` 后，这 10 个版本每个只少了贡献者行（5→2、6→3、9→4、4→2、7→3、8→5、
  4→2、4→3、7→5、10→7），没有丢真改动；条目改为 Markdown，行内代码保留反引号，分类标题会显示。
  窗口从页面的 10 个 release 变为 API 的 30 个。
