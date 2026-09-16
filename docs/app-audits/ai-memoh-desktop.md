# Memoh Desktop

## 基本信息
- Bundle ID: `ai.memoh.desktop`
- Team ID: `P9R669C27U`（`Developer ID Application: Shenzhen Moerin Technology Co., Ltd.`）
- 观测版本: `2026.9.16-1`（short == build，后缀一并带着）
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

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater 的 blockmap 差分） | 无 | 不能 |
| 证据 | electron-updater 依赖 | `latest-mac.yml` 只有两个 zip 条目，未列 blockmap（2026-09-16） | 不是 Sparkle delta，没有现成机制 |

## Changelog
- 来源: 无。`latest-mac.yml` 是清单，没有正文；GitHub release notes 讲的是 OSS 服务端版本（`v0.20.0`），
  编号对不上桌面版。
- Recipe 状态: 不需要（目前没有可对号的来源）。

## 一键安装
- 状态: **支持**
- 格式: zip —— `Memoh-{ver}-mac-arm64.zip`，相对路径，解析到 `https://desktopresource.memoh.ai/`
- **读的是**: 人人可手动下载的 GA（memoh.ai 下载页给的就是同一个文件），无灰度
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
- 老的 GitHub 构建（≤ v0.16.0，`Memoh-0.16.0-mac-arm64.dmg` 等）是另一套版本编号；没有核对过它们的
  bundle id 是否也是 `ai.memoh.desktop`。

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
