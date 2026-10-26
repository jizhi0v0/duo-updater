# Kap

## 基本信息
- App: Kap — 开源录屏工具（Electron），MIT
- Bundle ID: `com.wulkano.kap`（helper 是 `com.wulkano.kap.helper{,.GPU,.Renderer,.Plugin}`，都在 `Contents/Frameworks`）
- 仓库: `wulkano/kap`（GitHub 上显示为 `wulkano/Kap`，资产 URL 用大写；默认分支 `main`；没有 archived）
- Team ID: `2KEEHXF6R6`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 3.6.0（tag `v3.6.0`，资产 `Kap-3.6.0-arm64.dmg`，build 3.6.0.1846）；上一版 3.5.5；观测日期: 2026-10-26
- 自更新机制: **electron-updater 4.6.1**（`provider: github`，`updaterCacheDirName: kap-updater`），在 Mac 上由 Squirrel.Mac 落地。settled from source: `main/index.ts` on `v3.6.0`：启动时查一次、之后每小时查一次（`setInterval(checkForUpdates, 1 h)`），没改 electron-updater 的默认值，所以 `autoDownload = true`、`autoInstallOnAppQuit = true`（`app.asar` 里 `AppUpdater.js` 核过），即发现新版就自己下、退出时装，不问用户
- 分发: GitHub Releases；官网 getkap.co 的「Apple silicon」下载链接 `https://getkap.co/api/download/arm64` 302 到同一个 GitHub 资产（2026-10-26 实测）；Homebrew cask `kap`（3.6.0，`auto_updates: true`，url 指 arm64 dmg）。没有 MAS
- **发版节奏: 已停滞。** 最新 release v3.6.0 发布于 2022-10-27；之后 `main` 上只有一个提交（2024-02-14「Update CircleCI config」）。README 和官网首页没有 sunset / discontinued / no longer maintained 之类的说法，仓库没有 archived，cask 也没标 `deprecated` / `disabled`。按 app-audit Phase 0½，这不是产品终止（没有终止日期），只记在「已知问题」，不加 `sunsets`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | ✓ | — |
| **beta**（`com.wulkano.kap-beta`，2019 年后停发） | — | — | — | ○（待用户决定） | — |

当前生效源（channel-verify 实测）: **GitHub**。

`ElectronManifestSource` 接不上：`app-update.yml` 是 `provider: github`，不给地址。`feed-discover` 对 3.6.0 dmg 的结论是 `review    electronProviderNeedsConstruction`。cask 是 `auto_updates: true`，`HomebrewCaskSource` 让位。

## 覆盖清单
- **bundle id**（读 `package.json` 的 `build.appId` 和真包）：v0.1.0、v1.0.1、v2.0.0、v2.2.0、v3.0.0、v3.6.0 的 `appId` 都是 `com.wulkano.kap`；真包 0.1.0、2.2.0、3.5.5、3.6.0 的 `CFBundleIdentifier` 一致。没有改名前的旧 id
- **Team**：真包 0.1.0（Developer ID，2016 年还没公证）、2.2.0、3.5.5、3.6.0（后三个 Notarized Developer ID）都是 `2KEEHXF6R6`，没换过 Team，旧副本不会被 Team 闸拒
- **beta 轨（另一个 bundle id）**：`v2.0.0-beta.*`、`v2.1.0-beta.1`、`v2.2.0-beta.1`、`v3.0.0-beta.1`…`beta.6` 都标了 prerelease，产品名 `Kap Beta`，`appId` 是 `com.wulkano.kap-beta`（`package.json`）。真包 `kap-beta-3.0.0-beta.6.dmg`：`com.wulkano.kap-beta`、`3.0.0-beta.6`、x86_64、Team `2KEEHXF6R6`、spctl 只到 Developer ID（未公证）。最后一个 beta 是 2019-07-09，同年 11 月 3.0.0 正式版后再没发过 beta。channel-verify 对这个包：`inferred beta`、`winning source <none>`、`status unknown (no source answered)`。**没接**，见「待用户决定」
- **dev 构建**：README 写着 `https://kap-artifacts.now.sh/<branch>` 可下 CI 构建（「unsupported」）。2026-10-26 这个地址 308 到 `kap-artifacts.vercel.app/main`，后者回 `Response code 401 (Unauthorized)`，拿不到包，所以没读真包。推断（未验证）：它是同一个 `package.json` 打出来的，id 是 `com.wulkano.kap`、版本号是当时 `package.json` 的版本；`main` 自 3.6.0 起没改过版本号，这样的副本读成 3.6.0，与最新版相同，不会被提供更新；更早的 dev 副本会被提供 3.6.0 正式版，后者包含它之前的所有改动
- **版本范围**：`versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$` 读得出全部 29 个非 prerelease tag（v0.1.0 … v3.6.0），锚定后不收 `-beta.N`；下一个大版本 `v4.0.0` 也能读。arm64 dmg 从 v3.5.0 才有（v3.5.0 叫 `Kap-3.5.0-arm64.dmg`，v3.5.1 起同名规则）；v3.4.x 及更早只有 Intel 包。这只在 `/releases/latest` 指向那些版本时才有影响，今天指向 v3.6.0
- **主机下限**：DuoUpdater 只出 arm64（`App/project.yml` `ARCHS: arm64`）；Kap arm64 包 `LSMinimumSystemVersion` 10.12.0，不构成限制。Intel 副本（3.4.x 及更早，或 x64 dmg）在 arm64 主机上一键换成 arm64 包：同 id、同 Team，闸放行
- **同 id 下的其他产品**：没有。资产模式锚定 `-arm64\.dmg$`，不会选到 x64 dmg 或 zip

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.wulkano.kap` | — | 默认 | GitHub `/releases/latest` | ✓ |
| beta    | `com.wulkano.kap-beta` | 独立（pattern A） | bundle id；版本 `-beta.N`、名字 `Kap Beta` | — | ○ 待用户决定（轨道 2019 年停发） |

## 更新检测
- 源: `wulkano/kap` GitHub Releases，`/releases/latest`
- 版本方案: tag `v3.6.0` → `CFBundleShortVersionString` `3.6.0`，`CFBundleVersion` `3.6.0.1846`（electron-builder 加的构建号，不参与比较）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`
- install pattern `^Kap-[0-9]+(?:\.[0-9]+)+-arm64\.dmg$`；同一个 release 里另有 `Kap-3.6.0-x64.dmg`、`Kap-3.6.0-arm64-mac.zip`、`Kap-3.6.0-mac.zip`（x64）、各自的 `.blockmap` 和 `latest-mac.yml`，都不匹配
- `latest-mac.yml`（v3.6.0）`releaseDate` 2022-10-27T18:15:12Z，列出四个包的 sha512 和大小，没有 `stagingPercentage`
- **读的是**: 人人可手动下载的 GA。Kap 自己的更新器（github provider，非 prerelease 版本不开 `allowPrerelease`）读的也是这一版

## 按架构 / 按 OS 分轨
- 分架构资产：arm64 dmg/zip 与 x64 dmg/zip。electron-updater 4.6.1 `MacUpdater.doDownloadUpdate`：arm64 Mac（含 Rosetta 下的 x64 副本）且有 arm64 文件时只取 URL 含 `arm64` 的文件，再取其中的 zip；所以 Kap 自己在 Apple silicon 上会装 `Kap-<v>-arm64-mac.zip`
- `LSMinimumSystemVersion` 10.12.0（3.5.5、3.6.0），0.1.0 是 10.9.0；release 和 `latest-mac.yml` 都不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无（Mac 上） | 有 `.blockmap`，但 Mac 用不上 | — |
| 证据 | electron-updater 4.6.1 `MacUpdater.doDownloadUpdate` 直接 `httpExecutor.download` 整个 zip（`app.asar` 里核过），没有走 blockmap 差分；差分下载只在 Windows/Linux 的 updater 里 | v3.6.0 每个包都带 `.blockmap`（electron-builder 默认产物），`latest-mac.yml` 里没有 delta / patch 字段 | 没有可消费的 Mac 增量 |

- 格式: electron-builder blockmap（Mac 上不用）
- 阻塞项: 无

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏来自 Phase 4 第二轮的前后 diff，不来自源码。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 真机实测（2026-10-26）：3.5.5 运行约 30 s 内 Squirrel/ShipIt 已暂存 3.6.0；electron-updater 的 pending 目录在 `~/Library/Application Support/Caches/kap-updater/pending`，不是 `~/Library/Caches/kap-updater` | 第二轮 `duo install` 认出「它自己的更新器已暂存 3.6.0」而跳过，没有出现 `local stash hit` |
| 证据 | electron-updater 4.6.1 `DownloadedUpdateHelper`（`app.asar` 里核过）：`cacheDirForPendingUpdate` = `<cacheDir>/pending`，`setDownloadedFile` 在下载完成后写 `update-info.json`（`fileName`、`sha512`、`isAdminRightsRequired`）；`cacheDir` = `~/Library/Application Support/Caches/` + `app-update.yml` 的 `updaterCacheDirName`（`kap-updater`；4.x 的路径，5 起才改成 `~/Library/Caches/`，真机实测见上一行）。随后由本地 HTTP 代理喂给 Squirrel.Mac，ShipIt 在退出时装 | — | 不能：`SelfUpdaterStash` 的 electron-updater 布局只在 `~/Library/Caches/<updaterCacheDirName>/` 下找，看不到 Kap 的 4.x 目录；运行中一轮 duo 是靠 ShipIt 暂存判断让路的 |

- 记录文件与字段: `update-info.json`，下载完成并核过 sha512 后才写；`sha512` 是 base64 SHA-512（electron-builder 格式），描述的是 zip
- 容器: zip（`Kap-<v>-arm64-mac.zip`），包根是 `Kap.app`
- 两份副本会不会共用这个目录: 会。目录名只来自 `updaterCacheDirName`，不分安装路径；duo 不读这个目录，所以不涉及

## Changelog
- 来源: GitHub release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 3.5.5 起）: `source structured: 1 entries; newest 3.6.0: 1 items, headings []; first items ["You can now pause/resume a recording. (t"]`
- `headings []` 不是被压平：v3.6.0 正文本身没有标题，只有一个列表项（加一行缩进的补充说明）和 compare 链接，所以 1 条、无分节是如实的
- 跟随 channel: 只有 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-26，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 3.5.5 → `duo install com.wulkano.kap --yes`（`downloading` `extracting` `verifyingCodeSignature` `installing` `installed`）→ 3.6.0、`TeamIdentifier=2KEEHXF6R6`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted（Notarized Developer ID）
  - 第二轮（运行中）: 3.5.5 用 `open -g` 启动（18:43:24），约 30 s 内 Kap 自己的 Squirrel/ShipIt 已暂存 3.6.0（ShipIt 18:43:56 `Detected this as an install request`；`ShipItState` 的 `updateBundleURL` 指向 `~/Library/Caches/com.wulkano.kap.ShipIt/update.v07HMdr/Kap.app`；electron-updater 的 pending 在 `~/Library/Application Support/Caches/kap-updater/pending`，不是原先推断的 `~/Library/Caches/kap-updater`）。`duo install` → `Skipping: Kap — its own updater already has 3.6.0 staged — quit it to apply, or duo restart`（没有重复安装）。`duo restart`（非 TTY，宽限约 5 s）→ `still running — likely a save prompt, left 3.6.0 staged`：Kap 5 s 内没退出，屏幕上也没有提示框（截图）。手动发 AppleEvent 退出后 Kap 退出，ShipIt 18:49:15 `Installation completed successfully`，磁盘 3.6.0、Team 不变、`codesign` 0
  - Kap 的退出处理不稳定（菜单栏 Electron app）: 18:50:17 起的另一个进程上，第二次 AppleEvent 退出 60 s 内被忽略，最后 `kill -TERM`；谁在 18:50:17 把 Kap 重新拉起来的没查清（CLI 已退出，日志没留）
  - 终态: 3.6.0，未运行。副作用: `~/Library/Application Support/Kap`（Crashpad、Sentry）、`~/Library/Caches/com.wulkano.kap`（含 `.ShipIt`）、`~/Library/Application Support/Caches/kap-updater`；3.5.5 运行时系统弹过「App Update Required … component that will not open in macOS 28」通知
- 格式: dmg（`hdiutil imageinfo`: `UDZO`），根目录 `Kap.app` + `Applications` 软链
- 嵌套 / 常驻组件: `Contents/Frameworks/Kap Helper.app`、`Kap Helper (GPU).app`、`Kap Helper (Renderer).app`、`Kap Helper (Plugin).app`，都是 `LSUIElement=true` 的 Electron 子进程，随主进程退出；没有 `Contents/Library`（LoginItems / LaunchServices）、没有 LaunchAgent / daemon。另有 `Squirrel.framework`、`Mantle.framework`、`ReactiveObjC.framework`（Squirrel.Mac 及其依赖）
- 签名: 0.1.0、2.2.0、3.5.5、3.6.0 都是 Team `2KEEHXF6R6`，Team 没换过
- 校验: GitHub 资产 `digest` 为 null（2022 年上传，早于 GitHub 加 digest），规则没有摘要可用，只靠 Team 闸。`latest-mac.yml` 里的 sha512 与真实下载相符：`Kap-3.6.0-arm64.dmg`（124651995 字节）的 base64 SHA-512 = `PoOY2UerBPN0qD7FPXZUEWtYHYsfJHByTJXc6wC6TPWzx+zTbNsQdxhbO+eDD9RPS+fs72ZFSGXF7Rw5Dgp2fA==`，`Kap-3.5.5-arm64.dmg` = `m0AGWdm6hVV3+CH75CpIiccWa+z7r8zCgrkiPcaRcf4XZVtJi6bIMiuiRUqdfGg7DN4l578x2jHDJIvTojO2Qw==`，都等于 yml 里对应 dmg 的值。`GitHubReleaseRule` 不读 `latest-mac.yml`，接上它是引擎改动，本次没做
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，也是官网下载链接指向的那一版）
- 阻塞: 无
- 真机前的注意点（来自源码 / 包内容；2026-10-26 实测见上面的「端到端」，与此不符处以实测为准）:
  - 启动即查更新且自动下载：从 3.5.5 启动后，它会把 `Kap-3.6.0-arm64-mac.zip`（119687412 字节）下好，再交给 Squirrel（ShipIt 缓存），**退出时自己装**。实测 pending 目录是 `~/Library/Application Support/Caches/kap-updater/pending`，第二轮 `duo install` 走的是「已暂存、跳过」分支；ShipIt 退出时装的也是 3.6.0，同版本覆盖
  - 想造「暂存了一个比 latest 旧的版本」：没有比 3.6.0 新的 release，Kap 只会暂存 3.6.0；electron-updater 4.6.1 的 `ElectronAppAdapter.appUpdateConfigPath` 在打包后的 app 里只读 `Contents/Resources/app-update.yml`（`dev-app-update.yml` 只在未打包时读，`app.asar` 里核过），Kap 也没调 `setFeedURL`，改 yml 会破签名，所以在发布包上没有现成钩子能造出更旧的暂存
  - `electron-util` 的 `enforceMacOSAppLocation()`：不在 `/Applications` 时弹框要求挪过去，装在 `/Applications` 不会弹
  - 首启 `ensureScreenCapturePermissions()` 会触发录屏权限（TCC）；`recordAudio` 开着时还要麦克风
  - 启动后会打开录制选区窗口（cropper）
  - 菜单栏 app（`app.dock.hide()`），无 Dock 图标
  - 默认 `allowAnalytics: true` → Sentry 崩溃上报开着（`main/utils/sentry.ts`，DSN 指向 sentry.io）；Insight 统计在 3.6.0 里已注释掉
  - 注册 URL scheme `kap`（`setAsDefaultProtocolClient`），文档类型 mp4 / mov，`LSHandlerRank` `Alternate`
  - 偏好里的「开机启动」走 Electron `setLoginItemSettings`（`openAtLogin`），登记的是主 app 自身，不是另一个 helper；默认不开
  - 插件装在 `~/Library/Application Support/Kap/plugins`（`app.getPath('userData')`），启动时会检查已装插件的更新

## 已知问题
- **发版停滞**：最后一个 release 是 2022-10-27 的 3.6.0，此后四年没有新版，`main` 只有一个 CI 配置提交（2024-02-14）。没有任何厂商页面宣布停止维护，不算产品终止。实际效果：所有 3.6.0 副本永远显示 up to date，规则只对更旧的副本有用
- beta 轨（`com.wulkano.kap-beta`）没接，见下
- GitHub digest 没有，一键只靠 Team 闸（`latest-mac.yml` 的 sha512 可用，但规则不读）

## 待用户决定
- **Kap Beta（`com.wulkano.kap-beta`）副本**：今天没有任何源回答（channel-verify `unknown`）。轨道 2019-07 后停发，3.0.0 正式版取代了它。可选：(a) 不接，保持 unknown；(b) 加一条 `channel: .beta`、只检测的 GitHub rule（`bundleID: "com.wulkano.kap-beta"`，不带 install 字段），让这些副本看到最新稳定版 3.6.0——但那是另一个 bundle id 的 `Kap.app`，用户要自己装正式版，旧的 `Kap Beta.app` 不会被替换。不能用 `BundleIDMigration`：Kap Beta 是与正式版并存的独立 app，不是改名，迁移会把 `Kap Beta.app` 原地换成正式版 bundle。本次按 (a) 处理

## 如何复验
```bash
gh release download v3.6.0 --repo wulkano/kap --pattern 'Kap-3.6.0-arm64.dmg'
gh release download v3.5.5 --repo wulkano/kap --pattern 'Kap-3.5.5-arm64.dmg'
gh release download v3.0.0-beta.6 --repo wulkano/kap --pattern 'kap-beta-3.0.0-beta.6.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Kap-3.6.0-arm64.dmg Kap-3.5.5-arm64.dmg   # Team 2KEEHXF6R6, Notarized
swift run --package-path application-test feed-discover Kap-3.6.0-arm64.dmg                         # review electronProviderNeedsConstruction
swift run --package-path application-test channel-verify Kap-3.5.5-arm64.dmg --expect stable         # GitHub, UPDATE → 3.6.0
swift run --package-path application-test channel-verify Kap-3.6.0-arm64.dmg --expect stable         # up to date
swift run --package-path application-test channel-verify kap-beta-3.0.0-beta.6.dmg                    # inferred beta, no source
curl -sSL https://github.com/wulkano/kap/releases/download/v3.6.0/latest-mac.yml                     # sha512 of each package
openssl dgst -sha512 -binary Kap-3.6.0-arm64.dmg | base64                                          # equals the yml's arm64 dmg entry
```

channel-verify 原始输出（2026-10-26）:
```
3.5.5 dmg: detected channel → stable; winning source GitHub; latest 3.6.0;
  download https://github.com/wulkano/Kap/releases/download/v3.6.0/Kap-3.6.0-arm64.dmg;
  changelog pane source structured: 1 entries; newest 3.6.0: 1 items, headings []; first items ["You can now pause/resume a recording. (t"]
  status UPDATE → 3.6.0
3.6.0 dmg: detected channel → stable; winning source GitHub; latest 3.6.0; status up to date
3.0.0-beta.6 dmg (com.wulkano.kap-beta): inferred beta; winning source <none>; status unknown (no source answered)
```

## 建议下一步
1. （可选）`SelfUpdaterStash` 只读 electron-updater 5 起的 `~/Library/Caches/` 目录；Kap、Tad 这类 4.x 应用停放在 `~/Library/Application Support/Caches/`，要复用就得多看这个位置（引擎改动）。现在 duo 靠 ShipIt 暂存判断让路，不会重复安装
2. Kap Beta 副本：按「待用户决定」里的选择处理
3. （引擎，可选）让 GitHub rule 读 release 里的 `latest-mac.yml` sha512，给没有 GitHub digest 的老 Electron release 补上摘要校验
