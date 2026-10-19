# Memoh Desktop

## 基本信息
- Bundle ID: `ai.memoh.desktop`
- Team ID: `P9R669C27U`（`Developer ID Application: Shenzhen Moerin Technology Co., Ltd.`）
- 观测版本: `2026.10.19-1`（2026-10-19；short == build，后缀一并带着；2026-09-16 接入时为 `2026.9.16-1`）
- 自更新机制: electron-updater，generic provider（`desktopresource.memoh.ai`）
- 开源: `felinics/Memoh`（AGPL-3.0），桌面端在 `apps/desktop/`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✗      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。
`ElectronManifestSource` 排在它后面，而且对这个 bundle 本来就解析不出东西（见下）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `ai.memoh.desktop` | 单一渠道 | — | — | ✓ |

单渠道。厂商 CDN 上只有 `latest-mac.yml`；`1-mac.yml`、`beta-mac.yml`、`alpha-mac.yml` 均 404（2026-09-16）。

## 更新检测
- 源: `https://desktopresource.memoh.ai/latest-mac.yml`。memoh.ai 的下载页（`desktopDownloads` 模块）
  读的就是这个文件，再挑 `-mac-arm64` 那条。
- **为什么不是 `ElectronManifestSource`**（settled from source: `apps/desktop/src/main/updates.ts` on `main`）:
  - 包内 `Contents/Resources/app-update.yml` 写的是 `provider: generic`、`url: https://desktopresource.memoh.ai`、
    **`channel: 1`** —— electron-builder 把版本号里的 `-1` 当成 semver prerelease，写成了渠道名。
    通用源照着它去拿 `1-mac.yml`，404；`feed-discover` 的结论是 `review electronManifestUnreachable`。
  - app 自己不读那个文件：`configureAutoUpdater()` 调 `autoUpdater.setFeedURL({ provider: 'generic', url })`，
    不带 channel，所以它真正请求的是 `latest-mac.yml`，也就是 recipe 读的那一份。
- **GitHub 不可行**: `felinics/Memoh` 的 release 从 v0.17.0 起只附源码包，桌面安装包不再发到那里
  （`apps/desktop/README.md`：OSS Release workflow 刻意不构建桌面安装包，交给下游分发）。而且 OSS tag
  是 `v0.20.0` 这种编号，和桌面版的 `2026.9.16-1` 不是同一个命名空间。
- **版本方案**: `YYYY.M.D-N`，日期加当天的构建序号。feed 的 `version`、`CFBundleShortVersionString`、
  `CFBundleVersion` 三者是同一个串。`VersionComparator` 把 `-` 当分隔符，`-N` 按第四段比较；
  `2026.9.16-0` → `2026.9.16-1` 报更新，这一点已在真实生产链上验过（见「如何复验」）。
  **不要剥掉后缀**：已装那一侧带着它，剥掉之后探针会永远落后一个构建。
  正则只收纯数字的后缀，厂商哪天发 `-beta.1` 这类后缀，探针会落空（unknown），不会被当成 stable。
- 按 OS 分轨: feed 不带 `minimumSystemVersion` / `maximumSystemVersion`；包的 `LSMinimumSystemVersion`
  是 `12.0`，低于 DuoUpdater 自己的下限，不需要 `hostRequirement`。
- 灰度: manifest 里没有 `stagingPercentage`，所有安装读的是同一份文件。

## 旧副本：OSS 仓库 GitHub release 里的 Mac 安装包（0.x）
v0.17.0 之前，`felinics/Memoh`（原 `memohai/Memoh`）的 GitHub release 附带 Mac 安装包，和厂商 CDN 的构建
**同一个 bundle id、同一个 Team**，但版本号是 `0.x`。2026-10-19 下载各家族的 arm64 dmg 挂载核对:

| 资产 | app | 版本 | Team | 自带 server | 包内 `app-update.yml` | 编进去的服务地址 |
|---|---|---|---|---|---|---|
| `Memoh-0.16.0-mac-arm64.dmg`（`Memoh-<v>-*.dmg`，0.10.0–0.16.0） | `Memoh.app` | `0.16.0` | P9R669C27U | 无 | `provider: github`、`memohai/Memoh` | `localhost:18080`（自托管） |
| `Memoh-Local-0.13.0-mac-arm64.dmg`（0.10.0–0.14.0） | `Memoh Local.app` | `0.13.0` | P9R669C27U | `Resources/server/memoh-server` | 同上 | `127.0.0.1`（本地 server） |
| `Memoh-Desktop-0.9.0-mac-arm64.dmg`（0.8.0–0.10.0-alpha.1） | `Memoh.app` | `0.9.0` | P9R669C27U | `Resources/server/memoh-server` | 同上 | `127.0.0.1:18731` |
| `Memoh_0.7.0_aarch64.dmg`（`Memoh_<v>_*.dmg`，0.6.0-beta.1–0.7.1；0.7.3 另有 `Memoh-0.7.3*` 与 `latest-mac.yml`） | `Memoh.app`（13 MB，非 Electron） | `0.7.0` | P9R669C27U | — | 无 | 没查 |

四个的 `CFBundleIdentifier` 都是 `ai.memoh.desktop`，`codesign --verify --deep --strict` 都退 0。
同一批 release 里的 `memoh_<v>_darwin_*.tar.gz` 是命令行二进制，不是 app。家族与范围按 API 的资产列表归类（2026-10-19）；
每家族只挂载了一个代表包，其余没下，但全部是 `0.x`，门控都挡得住。
厂商 CDN 的日期构建都不带 server：2026.9.16-1（接入时的第一版）、2026.9.27-1、2026.10.5-1、2026.10.19-1
四个 arm64 zip 解包核对，`Contents/Resources/server` 不存在、bundle 里没有 `memoh-server*`，`app.asar` 都编进
`https://app.memoh.net`（Memoh Cloud），short == build == 日期串，Team 都是 `P9R669C27U`。
全部日期构建（2026-10-19）: CDN 没有索引，按文件名逐日 HEAD `Memoh-<日期>-N-mac-arm64.zip`——2026-07-28
（下游分发 felinics/Memoh#873 合入）到 2026-09-15 试 N=1–3，2026-09-16 到 2026-10-19 试 N=1–5，另对有过 `-2`/`-3`
的日子补试 4–5——找到 29 个（`2026.8.5-2` … `2026.10.19-1`，没有 `-4` 及以上）。用 HTTP Range 只读每个 zip 的目录和
`Info.plist`：29 个都是 `ai.memoh.desktop`，short == build == 文件名里的日期串，zip 里只有 `Memoh.app`，没有
`Resources/server` 或 `memoh-server*` 条目（609 或 611 项）。方法核对：远程读 2026.10.19-1 得 611 项，与本地
`unzip -Z1` 相同；过滤条件在 Memoh Local 0.13.0 真包的 `Resources/server/memoh-server` 上命中。上游 `cc7ff7b4`
与 `v0.22.0` 的 `electron-builder.yml` 都没有 `extraResources`，与此一致。

- **它们自己的更新器拿不到更新**: 0.9–0.16 的 updater 读 GitHub，而 v0.17.0 起 GitHub release 不再附 Mac 安装包
  （settled from source：felinics/Memoh#873「no longer publish prebuilt Desktop installers」，下游分发自己签名发布）。
- **带 server 的是另一个产品**: `apps/desktop/README.md` 写明桌面端「does not start or package a local server」，
  本地版在 felinics/Memoh#748（「remove sqlite and local desktop」，2026-07-07）删掉。把 2026 构建一键装到
  `Memoh Local.app` 或 0.9.0 上，会把本地安装悄悄换成云端客户端。
- **处理**: `oneClickGates` 只放行 `CFBundleShortVersionString` 匹配 `^20[0-9]{2}\.` 的副本（厂商的日期构建）。
  `0.x` 副本照常检测、显示 CDN 最新版，但不给一键，提示去 memoh.ai 手动下载。0.10–0.16 的纯客户端
  理论上可以一键（2026 构建有 `ConnectServer` 换服务地址），但升级后自托管地址是否保留没验证，所以一并挡住。
  单测 `OneClickGateTests.memohOneClickIsForTheVendorsDatedBuildsOnly`；变异把 pattern 放宽成 `^[0-9]`，5 个 0.x/1.0 用例变红。
  真机（2026-10-19，`duo` 用本分支构建）: 真的 `Memoh 0.16.0` 与 `Memoh Local 0.13.0` 分别放进 `/Applications`，
  `duo check` 照常显示 `→ 2026.10.19-1 [Vendor]`（不带 `in-place`），`duo install --yes --json` 都是 `skipped`，
  原因「detection only for this copy — a Memoh build from GitHub, which may run its own local server; …」，版本与 inode 不变。
- 从源码本地构建的副本也是 `0.x`（不设 `MEMOH_DESKTOP_VERSION` 时取 `apps/desktop/package.json`，现在是 `0.22.0`；
  `appId` 默认 `ai.memoh.desktop`），同样只检测。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 的 blockmap 差分） | 无 | 不能 |
| 证据 | electron-updater 依赖 | `latest-mac.yml` 只有两个 zip 条目，未列 blockmap（2026-09-16） | 不是 Sparkle delta，没有现成机制 |

## Changelog
- 来源: recipe —— `felinics/Memoh` 的 GitHub releases（`.gitHubReleases`，`per_page=20`，`maxEntries: 10`）。
- **为什么 OSS 的 release notes 就是桌面版的**（settled from source: `apps/desktop/scripts/build-env.mjs` on `main`）:
  桌面包是 OSS 源码树原样构建，下游只用 `MEMOH_DESKTOP_VERSION` → `-c.extraMetadata.version` 改了
  `app.asar` 顶层 `package.json` 的版本。包内的 `node_modules/@memohai/runtime/package.json` 没被改写，
  `2026.9.27-1` 的包里它写的是 **`0.20.0`**（2026-10-05 解包核对），即构建所用的 OSS 版本。
- **编号对不上，按 tag 原样显示**: 条目版本是 `v0.20.0`、`v0.19.0`……（`tagPattern`
  `^(v[0-9]+(?:\.[0-9]+){2})$` 把 `v` 留在捕获组里）。feed 不说某个桌面构建对应哪个 OSS 版本，
  所以没有条目能挂到 `2026.x` 版本号下。留着 `v`，`duo verify` 的落后/领先检查（要求首字符是数字）就不会把
  `0.20` 和 `2026.9` 当同一套编号比，否则每次扫描都会报「落后一整个版本」。`Changelog.carries` 会去掉 `v`，
  所以磁盘缓存一直把这页当 provisional、6 小时重读一次，和 Raycast / Toolbox 编号更粗的情况同一方向。
  两处都有测试钉住（`MemohChangelogRecipeTests`、`BaselineTests.upstreamTaggedChangelogIsNotComparedToADateNumberedApp`）。
- 语义上的出入: 桌面构建可能比它所基于的 OSS 版本多出 tag 之后 main 上的提交（`v0.20.0` tag 于 2026-09-15，
  `2026.9.27-1` 构建于 2026-09-27，main 上的版本号仍是 `0.20.0`），这部分改动在下一个 OSS release 之前没有 notes。
- 结构化: `recipe changelog:ai.memoh.desktop:-: 10 entries; newest v0.20.0: 108 items, headings ["🚀 Features", "🐞 Bug Fixes"]`
  （2026-10-05，`channel-verify` 对真包）。`&nbsp;` 填充的 `###` 标题保留为分节；`- **desktop**:` 这类作用域分组
  并进子条目（`**desktop**: 后台自动更新与侧栏更新入口`）；`by @… in …` 署名和 commit 链接被裁掉；
  `#####` 的 compare 链接页脚不成条目。预发布（`v0.9.0-beta.N` 等）被稳定渠道过滤掉。
- 跟随 channel: 单渠道，不涉及。
- Recipe 状态: 已有。

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会 | 有 | 能（已接） |
| 证据 | electron-updater，`autoDownload` 开（`updates.ts`） | 2026-10-19：2026.10.5-1 启动约 15 s 后 `~/Library/Caches/@memohaidesktop-updater/pending/` 有 `Memoh-2026.10.19-1-mac-arm64.zip`（134040328 B，= feed）和 `update-info.json`（`fileName`、`sha512` = feed 的 arm64 值）；下载中是 `temp-` 前缀 | `SelfUpdaterStash` 读 electron-updater 的 `pending/update-info.json`（目录名取包内 `updaterCacheDirName`）；端到端 `bytesDownloaded: 0` |

## 一键安装
- 状态: **支持**（仅厂商日期构建；`0.x` 的 GitHub 构建只检测，见上）
- 格式: zip —— `Memoh-{ver}-mac-arm64.zip`，相对路径，解析到 `https://desktopresource.memoh.ai/`
- **读的是**: 人人可手动下载的 GA（memoh.ai 下载页给的就是同一个文件），无灰度
- 端到端（2026-10-19，真机，Apple silicon，`duo` 用 `origin/main` 构建）:
  - 不运行: 2026.10.5-1（CDN 下载，Team P9R669C27U）放进 `/Applications` → `duo check`
    `2026.10.5-1 → 2026.10.19-1 [Vendor, in-place]` → `duo install --yes --json` `installed`（route vendor，
    134040328 B，19 s）→ short `2026.10.19-1`、inode 变、`--deep --strict` 0、`spctl` accepted / Notarized Developer ID、
    与厂商 zip 解出的 bundle 逐文件 sha256 + 符号链接清单一致（287 项）；`duo check` up to date
  - 运行中、自更新器已暂存: 重装 2026.10.5-1 并启动，等它把 2026.10.19-1 下完（见「已停放整包」）→ `duo install`
    `installed`、`bytesDownloaded: 0`（用的是停放的 zip）→ `duo restart Memoh` → 之后 12 s 内磁盘版本一直是
    `2026.10.19-1`。**局限**: 停放的是和 duo 装的同一版本，自更新器若把换上去的版本换回来也看不出来，这一轮证明不了没有碰撞
- **校验和**: feed 里 arm64 条目的 base64 sha512，锚在 `url: Memoh-…-mac-arm64.zip` 那一行后面。
  x64 条目紧挨着它，`path:` / 顶层 `sha512:` 指的也是 x64，所以不能取首个 `sha512:`。
  今天的 feed 里 arm64 恰好排第一，朴素写法碰巧也对，所以测试里另有一份把两条对调的 fixture 钉住锚点。
- 包验（2026-09-16，完整下载 `Memoh-2026.9.16-1-mac-arm64.zip`，133,932,953 B）:
  sha512 与 feed 的 arm64 条目逐字节一致；解出 `Memoh.app`，`codesign --verify --deep --strict` 通过；
  `spctl` 为 `accepted` / `Notarized Developer ID`；Team `P9R669C27U`；主二进制 arm64；
  `Contents/Library` 不存在，bundle 内没有 LaunchAgents/LaunchDaemons —— 自包含，`kind: .zip` 正确。
- 自更新器会不会抢（settled from source: `apps/desktop/src/main/updates.ts` on `main`）: app 开着
  `autoDownload`，后台下完即把 manifest 存成 `pending`。`autoInstallOnAppQuit = false` 只是关掉了
  electron-updater 自带的退出安装，app 自己接管了退出边界：`installDesktopUpdateOnQuit()` 在
  `autoUpdate` 开着（默认开）且已下载时，**每次正常退出都会交给 Squirrel 安装**；此外启动时
  `recoverDesktopUpdate()` 会对上次没装上的 `pending` 再装一次（`currentVersion >= pending` 时直接清掉）。
  用户在 About 页或 footer 点重启是第三条路径。暂存走 Squirrel/ShipIt，由通用的
  `SelfUpdaterStaging`（`~/Library/Caches/<bundleID>.ShipIt/`）识别，不是这条 recipe 独有的问题。

## 已知问题
- 厂商若不再把渠道写进 bundle（或改发 `1-mac.yml`），通用的 `ElectronManifestSource` 就能接住。
  到那时这条 recipe 可以退役，前提是先确认一键安装仍然选中 arm64。
- 老的 GitHub 构建（≤ v0.16.0）也是 `ai.memoh.desktop`，已核对并用 `oneClickGates` 挡住一键（见「旧副本」）。
  它们的检测会显示 CDN 的 2026 版本；对本地版用户来说那是后继产品，不是同一个东西的新版，只能提示。
- 0.10–0.16 纯客户端升到 2026 构建后，原来连的自托管地址是否保留没验证；验过之后可以考虑为它们放开一键。

## 如何复验
```
# GET https://desktopresource.memoh.ai/latest-mac.yml → version: "2026.9.16-1"
# 下载 Memoh-2026.9.16-1-mac-arm64.zip，解包 →
#   ai.memoh.desktop / 2026.9.16-1 / Team P9R669C27U / Notarized Developer ID / arm64
swift run --package-path application-test channel-verify <解出的 Memoh.app> --expect stable
#   detected channel → stable；winning source Vendor；status up to date
# 同一份 Info.plist 改成 2026.9.16-0 的桩 bundle：
#   verdict UPDATE 2026.9.16-0 → 2026.9.16-1
swift run --package-path application-test feed-discover <Memoh.app>
#   review electronManifestUnreachable（通用源解不出，这是加 recipe 的理由）
# changelog（2026-10-05，2026.9.27-1 真包）:
#   changelog pane → recipe changelog:ai.memoh.desktop:-: 10 entries; newest v0.20.0, headings 🚀 Features / 🐞 Bug Fixes
# 包内 OSS 版本: npx @electron/asar extract Contents/Resources/app.asar x
#   x/package.json → 2026.9.27-1；x/node_modules/@memohai/runtime/package.json → 0.20.0
```

## 建议下一步
- 无。

## 历史与实测

### Recipes/ai-memoh-desktop.swift — stable probe

2026-09-16 接入时的实测：

- `latest-mac.yml` 的 `Last-Modified` 为 `Wed, 16 Sep 2026 09:16:45 GMT`，`releaseDate` 为
  `2026-09-16T09:15:57.934Z`；带 `?noCache=` 查询与不带时返回同一份内容。
- 探测正则、`releaseDate`、arm64 URL、arm64 sha512 四个 pattern 在真实响应上各命中一次，
  分别是 `2026.9.16-1`、`2026-09-16T09:15:57.934Z`、`Memoh-2026.9.16-1-mac-arm64.zip`、`2nQGysc9…gzkTQ==`。
- 变异验证：去掉版本后缀、把校验和改成取首个 `sha512:`、把 URL 的架构锚放宽成任意架构，三处分别让
  对应用例变红；还原后四条用例全绿。第一轮只有一份原序 fixture，取首个 `sha512:` 那处变异**没变红**，
  因为 arm64 恰好排第一，于是补了对调顺序的用例。

### Recipes/ai-memoh-desktop.swift — changelog（GitHub releases）

2026-10-05 加入时的实测：

- `latest-mac.yml` 已到 `2026.9.27-1`（`Last-Modified: Sun, 27 Sep 2026 07:05:08 GMT`），结构与接入时相同，
  探针的四个 pattern 在新响应上仍各命中一次；`1-mac.yml` / `beta-mac.yml` / `alpha-mac.yml` / `nightly-mac.yml` 仍 404。
- 下载 `Memoh-2026.9.27-1-mac-arm64.zip`（133,941,650 B）解包，`app.asar` 顶层 `package.json` 为 `2026.9.27-1`，
  `node_modules/@memohai/runtime/package.json` 为 `0.20.0`。源码里没有别的地方注入 OSS 版本或 commit：
  `commitHash` 来自运行时向服务端取的 capabilities，不是构建时烘进去的。
- `felinics/Memoh` 最新 20 个 release 中 14 个稳定、6 个预发布（2026-10-05 v0.21.0 发布前数；最新的预发布是 `v0.10.0-alpha.1`），
  tag 全部是 `v` 加三段数字，没有别的产品线混在里面。
- 最初考虑过只靠 tag 保留 `v` 来同时避开缓存和 verify 两处比较，实测 `VersionComparator.comparableMarketingVersion`
  会去掉开头的 `v`，所以只避开了 verify；缓存那边接受 provisional。

