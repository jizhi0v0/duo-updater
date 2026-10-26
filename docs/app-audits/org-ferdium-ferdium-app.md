# Ferdium

## 基本信息
- App: Ferdium — 把多个消息 / 网页服务装进一个窗口的 Electron app（Ferdi 的分支），Apache-2.0
- Bundle ID: `org.ferdium.ferdium-app`（helper 是 `org.ferdium.ferdium-app.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: `ferdium/ferdium-app`（默认分支 `develop`；没有归档，2026-10-23 仍有推送）
- Team ID: `55E9FPJ93P`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 7.2.3（tag `v7.2.3`，资产 `Ferdium-mac-7.2.3-arm64.dmg`）；上一版 7.2.2；nightly 7.2.4-nightly.3；观测日期: 2026-10-26
- 自更新机制: **electron-updater**（`provider: github`，`package.json` v7.2.3 锁 `electron-updater` 6.3.9），在 Mac 上由 Squirrel.Mac 落地。settled from source: `src/electron/ipc-api/autoUpdate.ts`、`src/stores/AppStore.ts`、`src/config.ts` on `develop`：
  - 偏好 `automaticUpdates`（默认 `true`）开着时，启动 30 s 后查一次，之后每 `CHECK_INTERVAL`（1 h）查一次
  - `autoDownload` 保持 electron-updater 默认的 `true`（只有 snap 关掉），所以查到就自己下载
  - `autoInstallOnAppQuit = false`：只有用户在 Ferdium 里点安装（`quitAndInstall`）才交给 Squirrel 装，退出时不装（shipped `app.asar` 里的 `MacUpdater.quitAndInstall` 证实：没点安装时 Squirrel 根本没被喂）
  - 偏好 `beta`（默认 `false`）→ `autoUpdater.allowPrerelease`，见「Channel 详情」
- 分发: GitHub Releases；Homebrew cask `ferdium`（`auto_updates`，7.2.3）和 `ferdium@nightly`（`auto_updates`，7.2.4-nightly.3，两者 `conflicts_with`）；App Store 没有（`itunes.apple.com/lookup?bundleId=org.ferdium.ferdium-app` `resultCount` 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **nightly** | —       | —（`ferdium@nightly` 也是 `auto_updates`） | — | 读成 stable，只检测（一键被 `OneClickGate` 挡）；nightly 轨本身 ○ | — |
| **beta**（2022–2023 的旧 beta） | — | — | — | ✓（只检测，给最新稳定版） | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。没有 `SUFeedURL`、没有 MyGo feed；`app-update.yml` 是 `provider: github`（`owner: ferdium`、`repo: ferdium-app`、`updaterCacheDirName: ferdium-updater`），不给地址，`feed-discover` 对 7.2.3 dmg 的结论是 `review electronProviderNeedsConstruction`，`ElectronManifestSource` 接不上。

## 覆盖清单
- 各版本的 bundle id / Team（读真包，`check-bundle.sh`）:
  - v7.2.3、v7.2.2、v6.7.4、v6.0.0（最早的正式版）: `org.ferdium.ferdium-app`，Team 55E9FPJ93P，Notarized
  - nightly v7.2.4-nightly.3、v7.2.3-nightly.3，beta v6.4.1-beta.2: 同 id、同 Team，Notarized
  - 最早的 release `v6.0.0-nightly.7`（2022-04-22）的 `electron-builder.yml` `appId` 已经是 `org.ferdium.ferdium-app`，`v6.0.0-beta.1` 同样；没有改名前的旧 id
  - Homebrew 两个 cask 的 `uninstall quit` 和 `zap` 写的是 `com.ferdium.ferdium-app`：仓库源码里搜不到这个 id（GitHub code search `"com.ferdium"` 在 `ferdium/ferdium-app` 0 条，只出现在 `ferdium/homebrew-ferdium` 的 cask 里），没有真包用过它，不需要 `BundleIDMigration`
  - 前身 Ferdi（`ferdium/ferdi`，已归档，最后一版 v5.8.1，2022-04-13）是另一个产品：它的 `MIGRATION.md` 要求用户导出 / 导入配置数据，不是换包就能接上的改名，所以不做 `BundleIDMigration`；Ferdi 的 bundle id 没读（未验证）
- 其他轨: nightly 和旧 beta，见「Channel 详情」。394 个 release：33 个正式版 `vX.Y.Z`、351 个 `vX.Y.Z-nightly.N`、10 个 `vX.Y.Z-beta.N`，后两类都标了 `prerelease: true`。没有单独的 nightly 仓库（`ferdium/ferdium-app-nightlies` 404；`ferdium` org 下 13 个仓库里没有）
- 版本范围: `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$` 读出 33 个正式 tag 中的 33 个；`v8.0.0` 能读，`v7.3.0-rc.1`、`-nightly.N`、`-beta.N` 不读。33 个正式版里 31 个恰好一个 `Ferdium-mac-<v>-arm64.dmg`；v6.5.0、v6.5.1 没有任何 Mac 资产（v6.5.1 说明：macOS 上的问题没修好，暂停发 Mac 包），`/releases/latest` 现在不会落到它们上
- 主机下限: DuoUpdater 自身 macOS 15、arm64（`App/project.yml`）；Ferdium 7.2.x `LSMinimumSystemVersion` 12.0，7.2.4-nightly.3 是 13.0.0，都在下限之下，不需要 `hostRequirement`
- 同 id 下的其他产品: 没有（同一个仓库只出 Ferdium）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.ferdium.ferdium-app` | 共享 | 版本号纯数字 | `/releases/latest` | ✓ |
| nightly | `org.ferdium.ferdium-app` | 共享 | 版本号 `-nightly.N`（`ReleaseChannel.detect` 不认，读成 stable） | `OneClickGate` 挡一键 | 只检测 stable；nightly 轨 ○ |
| beta（旧） | `org.ferdium.ferdium-app` | 共享 | 版本号 `-beta.N`（`detect` 第 4 步读成 beta） | `.beta` rule 读 `/releases/latest`，不带安装 | ✓（只检测） |

**nightly 怎么来的（settled from source: `.github/workflows/builds.yml` on `develop`）:** 定时任务在 `develop` 上 `pnpm version prerelease --preid=nightly`，快进到 `nightly` 分支后构建并发布到同一个仓库，标 prerelease。所以 nightly 版本号是 `<下一版>-nightly.<N>`（7.2.3 发布后是 `7.2.4-nightly.1`、`.3` …），`CFBundleShortVersionString` = `CFBundleVersion` = 这个字符串（真包核过）。资产名 `Ferdium-mac-7.2.4-nightly.3-arm64.dmg`，与正式版不同名，install pattern 不会选到。

**厂商自己的更新器怎么对待各轨**（shipped `app.asar` 里 electron-updater `GitHubProvider` 的 `allowPrerelease` 分支，与 electron-updater 源码一致）:
- `beta` 偏好关（默认）: 读 `/releases/latest`，只给比自己新的正式版。nightly 副本也一样：只有正式版比它新时才换到正式版
- `beta` 偏好开、自己是正式版: 取 releases.atom 第一条，也就是最新的 release，不论是不是 nightly，于是被带上 nightly
- `beta` 偏好开、自己是 nightly: 取 releases.atom 里第一条同为 `nightly` 的 tag，留在 nightly 轨
- `beta` 偏好存在 Ferdium 的设置里（`settings.app.get('beta')`）；具体文件路径没在真机上核

**我们对 nightly 副本做了什么:**
- 检测: `ReleaseChannel.detect` 第 4 步只认 `-beta.N`、`-preview.N` 这类点号计数，以及 dash 分隔的 `-nightly`；`7.2.4-nightly.3` 这种点号计数的 nightly 一步都不中，读成 stable（channel-verify 实测 `inferred stable`）。于是 stable rule 回答：比最新正式版新的 nightly 显示 up to date（7.2.4-nightly.3 对 7.2.3），比它旧的显示有更新（7.2.3-nightly.3 → 7.2.3）。这与 `beta` 关时厂商自己的答案一致；`beta` 开时厂商给的是更新的 nightly，我们这一行看不到
- 一键: `OneClickGate` `.installedVersion(pattern: ^[0-9]+(?:\.[0-9]+)+$)`，nightly 和 beta 的版本形状不放行（`ferdiumOneClickIsForStableCopiesOnly`；把模式改成 `.*` 时该测试失败、改回后通过）。不挡的话，7.2.3-nightly.3 副本会被一键换成正式版 7.2.3，离开 nightly 轨；与 Hyper canary、Readest nightly 同一种处理
- 真正接 nightly（检测 nightly 轨、一键装 nightly）需要 `ReleaseChannel.detect` 认 `-nightly.N`（引擎改动），或 `ChannelBinding` 读 `beta` 偏好（引擎改动），再加 `.nightly` GitHub rule 读 prerelease 列表、配 `ChannelProofRegistry` 条目。本次没做，见「建议下一步」

**旧 beta:** `v6.0.0-beta.1` … `v6.4.1-beta.2`（2022–2023），之后预发布只用 nightly。真包 6.4.1-beta.2 读成 beta；加 `.beta` rule 之前 channel-verify 是 `winning source <none>`、`status unknown (no source answered)`，加之后是 `GitHub`、`UPDATE → 7.2.3`、`download` 是 releases 页（只检测）。

## 更新检测
- 源: `ferdium/ferdium-app` GitHub Releases，`/releases/latest`
- 版本方案: tag `v7.2.3` → `CFBundleShortVersionString` `7.2.3`、`CFBundleVersion` `7.2.3`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（锚定）
- install pattern `^Ferdium-mac-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`。同一个 release 里没被选的 Mac 资产：`Ferdium-mac-7.2.3-x64.dmg`、`Ferdium-mac-bundle-7.2.3-{arm64,x64}.zip`（electron-updater 自己下的 zip）和各自的 `.blockmap`；还有 Windows / Linux 包
- 两条 rule 都读 `/releases/latest`，GitHub 不会把它指向 prerelease
- **读的是**: 人人可手动下载的 GA（`/releases/latest`；Ferdium 自己的更新器在 `beta` 关时读的也是它）

## 按架构 / 按 OS 分轨
- 每版两套单架构 Mac 资产（arm64 / x64），没有 universal。选 arm64 dmg（check-bundle `archs=arm64`）
- `LSMinimumSystemVersion` 12.0（7.2.x），7.2.4-nightly.3 是 13.0.0；release 不声明 OS 上限。`latest-mac.yml` 只列文件、`sha512`、`size`，没有 OS 字段

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分下载） | 有 | 不能 |
| 证据 | shipped `app.asar` 里有 `DifferentialDownloader`（25 处）、`blockmap`（14 处） | v7.2.3 资产有 `Ferdium-mac-bundle-7.2.3-arm64.zip.blockmap`（167289 字节）等 | `DeltaApplier` 只吃 Sparkle binary delta 和 MyGo；没有消费 blockmap 的机制 |

- 格式: electron-builder blockmap（按块差分下载，不是二进制补丁）
- 阻塞项: 没有 blockmap 机制；全量 arm64 dmg 约 168 MB

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（`automaticUpdates` 默认开、`autoDownload` 开） | 没查（真机第二轮待主会话） | ○（布局已有，端到端待主会话） |
| 证据 | `autoUpdate.ts`；`app-update.yml` `updaterCacheDirName: ferdium-updater`；shipped asar 的 `getAppCacheDir()` 在 darwin 返回 `~/Library/Caches` | — | `SelfUpdaterStash` 的 `.electronUpdater(cacheDirectoryName:)` 读 `~/Library/Caches/<updaterCacheDirName>/pending/update-info.json` |

- 记录文件与字段: electron-updater 的 `pending/update-info.json`（下载完成后写，`sha512` base64，见 `SelfUpdaterStash` 注释；shipped asar 里有 `"update-info.json"`）
- 容器: electron-updater 在 Mac 上下 zip（`Ferdium-mac-bundle-<v>-arm64.zip`），包根应为 `Ferdium.app`（没解开核）
- 两份副本会不会共用这个目录: 会，目录名只按 `updaterCacheDirName`（7.2.4-nightly.3 与 7.2.3 的 `app-update.yml` 逐字相同，都是 `ferdium-updater`）；`SelfUpdaterStash` 的归属闸处理

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 7.2.2 起）: `source structured: 1 entries; newest 7.2.3: 15 items, headings ["Important Changes", "Other Changes", "Addition", "Other changes"]; first items ["macOS 11 Big Sur is no longer supported.", "Linux/Wayland: Electron now defaults to ", "perf: reduce blocking work when switchin"]`
- 条目全在：正文列表 2 + 3 + 4 + 3 + 3 = 15；`## New Contributors` 和 `**Full Changelog**` 按设计丢掉
- 标题部分保留：`### ⚠️ Breaking Changes (from \`7.2.0\`)` 这个标题没出现在 headings 里（两条 breaking 条目还在，排在最前），两级结构也被压成一级——`## App Changes` / `## Recipe Changes` 不显示，于是出现 "Other Changes" 和 "Other changes" 两个看起来重复的节。这是通用解析器的取舍，没改
- 跟随 channel: nightly 副本读成 stable，看到的是正式版正文；beta rule 读的也是正式版正文
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（stable 副本）**；nightly / beta 副本被 `OneClickGate` 挡，只检测
- 端到端: 待主会话
- 格式: dmg（`hdiutil imageinfo`: `Format: UDZO`），根目录 `Ferdium.app` + `Applications` 软链
- 嵌套: 只有 `Contents/Frameworks` 下四个 Electron helper（`LSUIElement=true`，随主进程退出）；没有 `Contents/Library`（无 LoginItems / LaunchServices）、没有 `Contents/Helpers`。`app.asar` 里没有 `setLoginItemSettings` / `openAtLogin` / `SMAppService`
- 签名: 6.0.0、6.4.1-beta.2、7.2.2、7.2.3-nightly.3、7.2.3、7.2.4-nightly.3 都是 Team `55E9FPJ93P`、Notarized Developer ID；上一版与最新版同 Team，不存在换 Team 拒装
- 校验: GitHub 资产 `digest`。v7.2.3 arm64 dmg `sha256:478842403c103837b3ba3bae4b9b86df1fb4f8f1da41dc642440ac1fdd51b5b0`，下载文件 `shasum -a 256` 相同、167567454 字节等于资产大小（与 cask `sha256` 也相同）。v7.2.2 及更早的正式版资产 GitHub 不给 digest（v6.x 是 `null`），装旧版不涉及。`latest-mac.yml` 的 `sha512` 不接（GitHub rule 已带 digest）
- **读的是**: 人人可手动下载的 GA
- 阻塞: 无
- 主会话真机要注意（来自源码 / 包内容，均未在真机上观察）:
  - 启动 30 s 后自己查更新并自动下载到 `~/Library/Caches/ferdium-updater/pending/`；从 7.2.2 启动会下 7.2.3 的 zip。不点 Ferdium 里的安装按钮就不会装（退出也不装），所以第二轮可以期望 `duo install` 读到同版本的停放包（`local stash hit`、`bytesDownloaded: 0`）
  - 碰撞只在用户点 Ferdium 自己的安装时可能发生：duo 换包后，还在跑的旧进程若点了安装，会把 `pending/` 里那份交给 Squirrel（ShipIt）装上；若那份比 duo 装的旧就是降级。第二轮要专门看 duo 换包后、旧进程退出前的这段
  - 首启应会出现登录 / 无账号使用的欢迎界面（推断，未核），不要登录
  - 注册 `ferdium://` URL scheme（启动时 `setAsDefaultProtocolClient`）
  - 「开机启动」偏好 `autoLaunchOnStart` 默认关；开了会通过 `auto-launch` 包用 AppleScript 让 System Events 加登录项（可能弹「自动化」授权框），不要开
  - 数据目录（cask `zap`）: `~/Library/Application Support/Ferdium`、`~/Library/Logs/Ferdium`、`~/Library/Caches/ferdium-updater`、`org.ferdium.ferdium-app.ShipIt` 等
  - 不写 `~/.claude` / `~/.agents`（asar strings 无，推断）

## 已知问题
- nightly 副本读成 stable：比最新正式版旧的 nightly 会看到「有更新 → 正式版」，比它新的显示 up to date；看不到更新的 nightly；一键被挡。接 nightly 需要引擎改动，见上
- changelog 面板丢掉 `⚠️ Breaking Changes` 标题、两级标题压成一级，见 Changelog

## 如何复验
```bash
gh release view v7.2.3 -R ferdium/ferdium-app --json assets -q '.assets[]|select(.name|test("mac.*arm64.dmg$"))|.name+" "+.digest'
gh release download v7.2.3 -R ferdium/ferdium-app -p 'Ferdium-mac-7.2.3-arm64.dmg'
gh release download v7.2.2 -R ferdium/ferdium-app -p 'Ferdium-mac-7.2.2-arm64.dmg'
gh release download v7.2.4-nightly.3 -R ferdium/ferdium-app -p 'Ferdium-mac-7.2.4-nightly.3-arm64.dmg'
gh release download v7.2.3-nightly.3 -R ferdium/ferdium-app -p 'Ferdium-mac-7.2.3-nightly.3-arm64.dmg'
gh release download v6.4.1-beta.2 -R ferdium/ferdium-app -p 'Ferdium-mac-6.4.1-beta.2-arm64.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Ferdium-mac-7.2.2-arm64.dmg     # org.ferdium.ferdium-app, 55E9FPJ93P, Notarized
swift run --package-path application-test feed-discover Ferdium-mac-7.2.3-arm64.dmg        # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Ferdium-mac-7.2.2-arm64.dmg --expect stable
swift run --package-path application-test channel-verify Ferdium-mac-7.2.3-arm64.dmg --expect stable
swift run --package-path application-test channel-verify Ferdium-mac-7.2.4-nightly.3-arm64.dmg
swift run --package-path application-test channel-verify Ferdium-mac-7.2.3-nightly.3-arm64.dmg
swift run --package-path application-test channel-verify Ferdium-mac-6.4.1-beta.2-arm64.dmg --expect beta
swift test --package-path DuoUpdaterCore --filter ferdiumOneClickIsForStableCopiesOnly
```

channel-verify 原始输出（2026-10-26）:
```
7.2.2 dmg:            detected channel → stable; winning source GitHub; latest 7.2.3;
                      download https://github.com/ferdium/ferdium-app/releases/download/v7.2.3/Ferdium-mac-7.2.3-arm64.dmg;
                      status UPDATE → 7.2.3
7.2.3 dmg:            detected channel → stable; winning source GitHub; latest 7.2.3; status up to date
7.2.4-nightly.3 dmg:  inferred stable; winning source GitHub; latest 7.2.3; status up to date
7.2.3-nightly.3 dmg:  inferred stable; winning source GitHub; latest 7.2.3; status UPDATE → 7.2.3（一键由 OneClickGate 挡）
6.4.1-beta.2 dmg:     detected channel → beta; winning source GitHub; latest 7.2.3;
                      download https://github.com/ferdium/ferdium-app/releases; status UPDATE → 7.2.3
6.0.0 dmg:            detected channel → stable; winning source GitHub; latest 7.2.3; status UPDATE → 7.2.3
```

## 建议下一步
1. 主会话真机两轮（上一版 7.2.2 → 7.2.3），结果写回「一键安装」和「已停放整包」第 2 栏，并把 README 行改成 ✓
2. nightly 轨（需要决定是否做引擎改动）: `ReleaseChannel.detect` 认点号计数的 `-nightly.N`（会改变所有这种版本号副本的判定，需按该处注释的方法重放 baseline），或 `ChannelBinding` 读 Ferdium 的 `beta` 偏好；再加 `.nightly` GitHub rule（`usePrereleases`，tag `^v([0-9]+(?:\.[0-9]+)+-nightly\.[0-9]+)$`，资产 `Ferdium-mac-<v>-nightly.<N>-arm64.dmg`）和 `ChannelProofRegistry` 条目
