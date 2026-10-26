# Lunatask

## 基本信息
- App: Lunatask — 任务 / 习惯 / 日记一体的效率 app，Electron 桌面版。`lunatask/lunatask` 是只放 release 的仓库（没有源码），release 正文只有一行指向 `lunatask.app/releases/<v>` 的链接
- Bundle ID: `com.mikekreeki.tasks`（v0.4.0、v1.5.0、v2.1.28、v2.1.29 真包相同；App Store 上同 id，见覆盖清单）
- Team ID: `24KNYM7WQY`；四个真包 `codesign --verify --deep --strict` 都通过，spctl: Notarized Developer ID
- 观测版本: 2.1.29（tag `v2.1.29`，资产 `Lunatask-2.1.29-universal.dmg`，`CFBundleVersion` 也是 2.1.29）；上一版 2.1.28；观测日期: 2026-10-26
- 自更新机制: **electron-updater**（`package.json` 依赖 `^5.3.0`），Mac 上经 Squirrel.Mac 落地。`Contents/Resources/app-update.yml`（2.1.29 真包）: `owner: lunatask`、`repo: lunatask`、`provider: github`、`updaterCacheDirName: '@lunataskelectron-updater'`。读的是 2.1.29 的 `app.asar` 里的 `build/AutoUpdater.js` / `Main.js`:
  - `autoDownload = false`；只在启动时查一次（`Main.checkForUpdatesOnLaunch`，商店版 / 开发版跳过），另有菜单「检查更新」
  - 有新版时弹框问 `Yes!` / `No, remind me later`；点 Yes 才 `downloadUpdate()`；下载完再弹一次框，然后 `quitAndInstall()`
  - `AutoUpdater.beta = false` 是常量，整个 `build/` 里没有别处给它赋值 → 实际只有 stable 一条轨
  - 0.4.0 的 `app-update.yml` 指向 `mikekreeki/tasks-releases`，该仓库现在重定向到 `lunatask/lunatask`（`gh api repos/mikekreeki/tasks-releases` 回 `lunatask/lunatask`），所以老副本的自更新器也读同一处
- 分发: GitHub Releases（每版 universal dmg + `-universal-mac.zip` + Windows / Linux 包 + `latest*.yml`）；Homebrew cask `lunatask`（2.1.29，`url` 即 GitHub 的 v2.1.29 dmg，`auto_updates` 未设，`depends_on macos >= 12`）；App Store `id1583719331`（见覆盖清单）；官网 lunatask.app
- 厂商近况: v2.1.29 发布于 2026-06-10，之后桌面版没有新 release；`lunatask.app/releases` 最新条目是 2.1.29 和移动端的 2.36.0，没有停止维护的说法

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源，只管 brew 装的副本；本次未单独验证） | ✓（通用 App Store 源，只管商店副本；本次未单独验证，见已知问题） | ✓ | — |

当前生效源（非 brew、非商店的副本）: **GitHub**（channel-verify 实测，见下）。

## 覆盖清单
- bundle id：v0.4.0（列表里最老的有资产的 release）、v1.5.0、v2.1.28、v2.1.29 真包都是 `com.mikekreeki.tasks`，没有改名。v0.1.0–v0.3.0 三个 release 没有资产，无包可读
- 版本范围 / 签名（逐个读真包，`check-bundle.sh`）:
  - v2.1.29、v2.1.28: universal（`x86_64 arm64`），`LSMinimumSystemVersion` 12.0，Team `24KNYM7WQY`，公证
  - v1.5.0: 只有 x86_64，`LSMinimumSystemVersion` 10.11.0，同 Team，公证；资产名 `Lunatask-1.5.0.dmg`（没有 `-universal`）。channel-verify: `UPDATE → 2.1.29`
  - v0.4.0: x86_64，10.10.0，同 Team，公证
  - 资产名从 v1.5.1 起是 `Lunatask-<v>-universal.dmg`，之前是 `Lunatask-<v>.dmg`。rule 只装最新版，所以 pattern 只收 universal 名字；老的 x86_64 副本一键换成 universal，同 Team，门放行
  - Team 自 v0.4.0 起没变，所以「上一版 Team 不同、门拒所有旧副本」的情况不存在
- **App Store（同 bundle id）**: `id1583719331` 是 universal purchase，同一个 trackId 下有两份构建（2026-10-26 读 iTunes lookup）:
  - `lookup?id=1583719331&entity=desktopSoftware` → `version 2.1.29`、`minimumOsVersion 12.0`、`supportedDevices ["MacDesktop-MacDesktop"]`、`currentVersionReleaseDate 2026-06-11`、`fileSizeBytes 147176237`。这是 Mac 原生构建，版本线和 GitHub 一致（比 GitHub 的 v2.1.29 晚一天）
  - `lookup?bundleId=com.mikekreeki.tasks`（带不带 `entity=macSoftware` 都一样）→ `version 2.36.1`、`minimumOsVersion 16.4`、131 个设备，这是 iPhone/iPad 构建
  - 商品页（`apps.apple.com` 的 id1583719331）的系统要求写着「Mac: Requires macOS 12.0 or later」，版本历史里既有 2.1.x 也有 2.36.1。页面上的「Designed for iPad. Not verified for macOS.」出现 4 次，全是「你可能也喜欢」里别的 app（Yoodoo id1621279084、Timestripe id1644320094）的卡片，不是 Lunatask 自己的
  - 2.1.29 的 `app.asar` 里有 `BuildInfo.isMacAppStore` 分支（商店版跳过自更新检查）和 `InAppPurchase.js`（`electron.inAppPurchase`），所以商店的 Mac 构建很可能就是同一份 Electron 代码的 MAS 构建。**商店包没有实测**（只能经 App Store 安装），iPad 构建的 `WrappedBundle` 标记也**没有在真包上实测**
  - 两种商店副本都不会走到这条规则: 引擎判 `isMASApp = !isTestFlight && (isiOSAppOnMac || hasReceipt)`（`Scan/AppScanner.swift:646`；`isiOSAppOnMac` 就是 `WrappedBundle` 存在，`:528`）。`UpdateChecker` 只把 `isMASApp` 的副本交给 `answersAppStoreCopies` 为真的源（`Engine/UpdateChecker.swift:168` 的 `apps(_:visibleTo:)`、检查循环 `:387` 的 `if app.isMASApp, !source.answersAppStoreCopies { continue }`）；`answersAppStoreCopies` 默认 false（`Sources/UpdateSource.swift:95`），只有 `MacAppStoreSource` 为 true（`Sources/MacAppStoreSource.swift:14`）；`GitHubReleasesSource` 里另有 `guard !app.isMASApp`（`Sources/GitHubReleasesSource.swift:819`）。TestFlight 副本在 `UpdateChecker.swift:236` 就交给 TestFlight，也不问别的源。所以一键不会拿 Developer ID 包盖掉商店副本，不需要 `OneClickGate`。与 LocalSend、Equinox 同一情形
- 其他轨: 118 个 release 全部不是 prerelease（`gh api …/releases --paginate`），tag 全部匹配 `^v[0-9]+(\.[0-9]+)+$`；自更新器的 beta 开关是写死的 false（见基本信息）；Homebrew 没有 `lunatask@beta` 之类的变体。单轨
- 主机下限: DuoUpdater 是 arm64、macOS 15.0（`App/project.yml`）；Lunatask 2.1.x 是 universal、`LSMinimumSystemVersion` 12.0，无需架构 / OS 门控

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mikekreeki.tasks` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `lunatask/lunatask` GitHub Releases，`/releases/latest`
- 版本方案: tag `v2.1.29` → `CFBundleShortVersionString` `2.1.29`、`CFBundleVersion` `2.1.29`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`。模式核对（Python `re`，同一正则）: 全部 118 个 tag 都匹配；`v2.2.0`、`v3.0`、`v3.0.0` 可读；`v2.1.30-beta.1`、`v3.0.0-rc.1`、无 `v` 的 `2.1.30`、`v3` 不匹配
- install pattern `^Lunatask-[0-9]+(?:\.[0-9]+)+-universal\.dmg$`，kind `.dmg`；同一 release 里的 `-universal-mac.zip`（electron-updater 用的那份）、`.blockmap`、Windows / Linux 包都不匹配
- channel-verify（2026-10-26，真 dmg）:
  - 2.1.28: `detected channel → stable`、`winning source GitHub`、`latest 2.1.29`、`status UPDATE → 2.1.29`
  - 2.1.29: `winning source GitHub`、`latest 2.1.29`、`status up to date`
  - 1.5.0（x86_64）: `winning source GitHub`、`latest 2.1.29`、`status UPDATE → 2.1.29`

## 按架构 / 按 OS 分轨
- 1.5.1 起一个 universal dmg（`lipo -archs` = `x86_64 arm64`）；`LSMinimumSystemVersion` 12.0。`latest-mac.yml` 没有系统版本上下限字段

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 未核（electron-updater 5.x 在 Mac 上是否用 blockmap 做差分下载，没读它的源码） | 每版发 `-universal-mac.zip.blockmap` 和 `.dmg.blockmap` | 不消费：我们装整个 dmg |
| 证据 | — | v2.1.29 资产列表 | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 只在用户点了「Yes!」之后（`autoDownload = false`） | 没跑（真机轮次留给主会话） | 引擎通用的 `SelfUpdaterStash` `.electronUpdater` 布局按 `app-update.yml` 的 `updaterCacheDirName` 读 `~/Library/Caches/@lunataskelectron-updater/pending/update-info.json`，不需要 recipe 写什么 |
| 证据 | `AutoUpdater.js`（2.1.29 asar） | — | `Sources/SelfUpdaterStash.swift:81`、`Sources/ElectronManifest.swift:41` |

## Changelog
- 来源: GitHub Release body，经 `GitHubReleasesSource`
- 结构化（2026-10-26，channel-verify `changelog pane`）: `raw inline notes, 36 chars, no structure`
- **不是结构化的**：每个 release 的正文只有一行 `https://lunatask.app/releases/<v>`（v2.1.29 实测），没有可解析的条目。真正的说明在 `lunatask.app/releases/<v>`，要结构化得另写 ChangelogRecipe，不在本次范围
- 跟随 channel: —（单轨）
- Recipe 状态: 没写（单独的活）

## 一键安装
- 状态: 支持
- 端到端: 待主会话
- 格式: dmg，`Lunatask.app` 在根目录；pattern `^Lunatask-[0-9]+(?:\.[0-9]+)+-universal\.dmg$`，kind `.dmg`
- 签名: Team `24KNYM7WQY`，Notarized Developer ID；v0.4.0 起同 Team
- 校验: GitHub digest `sha256:93dedebb249e12250c798738d50599b60a14d1adcc60a2cf0714ef2d6c1ec2e9`，与下载的 2.1.29 dmg 一致（2.1.28 的 `sha256:907439536974ffd7a414d0855db163766fb3697cf7841c2b1bb37f7755f44b4e` 也一致）
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 嵌套 / 常驻组件: 只有 Electron 自己的四个 helper（`Contents/Frameworks/Lunatask Helper{, (GPU), (Renderer), (Plugin)}.app`，`LSUIElement=true`），随主进程退出；没有 `Contents/Library/LoginItems`、没有 LaunchAgent / daemon。「登录时打开」是设置项，经 `app.setLoginItemSettings({openAtLogin})` 注册的是主 app 本身（`IPC.js`）
- 和自更新器的碰撞: 只有用户点过「Yes!」、自更新器已经下好或正在下时才有可能。下好以后它会立刻弹框然后 `quitAndInstall()`；electron-updater 默认 `autoInstallOnAppQuit = true`，`AutoUpdater.js` 没改它（**按 electron-updater 默认值推断，未验证**），所以已暂存的那版在退出时也会被 ShipIt 装上。引擎对 electron-updater 暂存的通用处理（同版本让路 / 读暂存）不需要 recipe 配置

### 真机注意事项（从 2.1.29 的 `app.asar` 读出）
- **不在 /Applications 就弹「Move to Applications folder?」**（`utils.js` 的 `enforceMacOSAppLocation`，`app.isInApplicationsFolder()` 为假时 `showMessageBoxSync`，选 Quit 就退出）。真机轮次要装在 `/Applications`；`~/Applications` 是否算数取决于 Electron 的 `isInApplicationsFolder` 实现，**未验证**
- **关窗口只隐藏、不退出**: `mainWindow.on('close')` 在 `allowQuitting === false` 时 `preventDefault`；`before-quit` 把它置 true，所以 Cmd-Q / 正常的退出请求能退
- 启动即查更新（有新版就弹「Lunatask Found Updates」框）。从 2.1.28 启动会弹这个框，真机上要么点「No, remind me later」，要么就是第二轮要的暂存
- 首次启动: 注册 `lunatask://` URL scheme（`setAsDefaultProtocolClient('lunatask')`，Info.plist 的 `CFBundleURLTypes` 也声明了）；`app.removeAsDefaultProtocolClient('file')`；登录时起一个 `127.0.0.1` 随机端口的 OAuth 回调 HTTP server（`OAuthServer.js`，只在登录流程里）；Sentry 上报
- 数据: `~/Library/Application Support/@lunatask`、`~/Library/Logs/@lunatask`、`~/Library/Preferences/com.mikekreeki.tasks.plist`（cask `zap`）；自更新缓存 `~/Library/Caches/@lunataskelectron-updater`
- 不是网络 / 代理类 app：2.1.29 的 entitlements 只有 `cs.allow-jit` 和 `cs.allow-dyld-environment-variables`，`Contents/` 下没有 `PlugIns`、`Library`（没有 Network Extension、系统扩展或 helper 工具）

## 已知问题
- Changelog 不结构化（release 正文只有链接），见 Changelog
- 商店副本的检测走 `MacAppStoreSource`：`entity=macSoftware` 的 lookup 对这个 id 回的是 iOS 构建（`kind software`、2.36.1），Mac 构建是 2.1.29。代码走「iOS-on-Mac 但 Mac 构建另有版本线」的分支去抓商品页（`Sources/MacAppStoreSource.swift:207-211`），能不能读出 2.1.29 **没有实测**；读错的话商店副本会看到假的 2.36.1 更新。不影响这条 GitHub rule

## 如何复验
```bash
gh api repos/lunatask/lunatask/releases --paginate -q '.[]|.tag_name+" "+(.prerelease|tostring)'
gh release download v2.1.29 --repo lunatask/lunatask --pattern 'Lunatask-2.1.29-universal.dmg'
gh release download v2.1.28 --repo lunatask/lunatask --pattern 'Lunatask-2.1.28-universal.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Lunatask-2.1.29-universal.dmg Lunatask-2.1.28-universal.dmg
swift run --package-path application-test channel-verify Lunatask-2.1.28-universal.dmg --expect stable   # → GitHub，UPDATE → 2.1.29
swift run --package-path application-test channel-verify Lunatask-2.1.29-universal.dmg --expect stable   # → up to date
curl -s 'https://itunes.apple.com/lookup?id=1583719331&entity=desktopSoftware&country=us'               # Mac 构建 2.1.29
curl -s 'https://itunes.apple.com/lookup?bundleId=com.mikekreeki.tasks&entity=macSoftware&country=us'   # iOS 构建 2.36.1
```

## 建议下一步
1. 真机一键（主会话）：从 2.1.28 装到 2.1.29，不运行一轮 + 运行中一轮（运行中那轮注意上面的「Move to Applications」和更新提示框）
2. 另开：`lunatask.app/releases/<v>` 的 ChangelogRecipe
3. 另开：有商店副本时核 `MacAppStoreSource` 对这个 universal purchase 读出的版本
