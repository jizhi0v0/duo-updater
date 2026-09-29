# Secretive

## 基本信息
- Bundle ID: `com.maxgoedjen.Secretive.Host`（内嵌 SSH agent `com.maxgoedjen.Secretive.SecretAgent`，
  位于 `Contents/Library/LoginItems/SecretAgent.app`）
- Team ID: `Z72PRUAWF6`
- 观测版本: `4.0.0`（`CFBundleVersion` 是 `1.<CI run id>`，如 `1.35554366823`，不参与比较）
- 自更新机制: 自研，只提醒不安装。`Brief/Updater.swift` 经 XPC 服务 `SecretiveUpdater.xpc`
  取本仓库的 releases，跳过 prerelease，按 release 名比较版本，给出 release 页面链接
- 分发: GitHub Releases（`maxgoedjen/secretive`，每版一个 `Secretive.zip`）/ Homebrew cask
  `secretive`（非 `auto_updates`，`url` 就是同一个 GitHub zip）
- 开源: 是。以下渠道、版本方案均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | 未验证   | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（对不在 Caskroom 里的真包跑
`channel-verify` 的结果；经 brew 安装的副本由哪个源应答未验证）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.maxgoedjen.Secretive.Host` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道对外分发。仓库里的 prerelease 只有 2020 年的 `v0.1.1`–`v0.5.1`，此后全部是正式版。
`.github/workflows/nightly.yml` 每天出一个 `0.0.0_nightly-<date>` 的构建，只作为 Actions
artifact 上传、不建 release，不是可订阅的轨道。

## 更新检测
- 源: `maxgoedjen/secretive` GitHub Releases，`/releases/latest`（2026-09-29 为 `v4.0.0`）
- 版本方案: settled from source: `.github/workflows/release.yml` on `main`——tag 推送触发，
  `CLEAN_TAG` = tag 去掉 `v` 写进 `CFBundleShortVersionString`，`CFBundleVersion` = `1.$RUN_ID`；
  资产固定叫 `Secretive.zip`。tag `v4.0.0` → `4.0.0` == 真包 `CFBundleShortVersionString`，
  `v3.0.4` → `3.0.4` 同样相等。
- 注意事项: 仓库有 tag `v3.0.1-skipped`，没有对应 release；anchor `^v([0-9]+(?:\.[0-9]+)+)$`
  也不收它。v3.0.1 在 releases 列表里缺席，3.0.0 之后直接是 3.0.2。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | `Updater.swift` 只挑出一个 `Release` 供提醒，不下载资产（读源码） | 30 个 release 每个只有整包 `Secretive.zip`（2026-09-29 `releases?per_page=30`） | — |

## 按 OS 分轨
- 真包 `LSMinimumSystemVersion`: 4.0.0 为 `15.0`，3.0.4 为 `14.0`。
- 厂商更新器按 release 正文里的 `Minimum macOS Version` 一行过滤（`Release.minimumOSVersion`），
  取「系统能跑的最新非 prerelease」。2026-09-29 的正文: `v4.0.0` 写 `15.0.0`，`v3.0.x` 写
  `14.0.0`，`v2.4.x` 写 `12.0.0`。
- 我们的 GitHub 源不读这个下限，见「已知问题」。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource`；`channel-verify` 给出 changelogURL
  `…/releases/tag/v4.0.0`）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: **仅检测**（`installAssetPattern` 为 nil）
- 格式: zip — `Secretive.zip`，universal（`x86_64 arm64 arm64e`）
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-09-29，v4.0.0 与 v3.0.4 解压）: 主 app 与 `SecretAgent.app` 都是
  `Developer ID Application: Max Goedjen (Z72PRUAWF6)`，`spctl` 均为
  `accepted / Notarized Developer ID`，`codesign --verify --deep --strict` 通过。
  也就是说，装包本身能过安装闸。
- 阻塞: 替换 bundle 时 SSH agent 还在跑。
  - `SecretAgent.app` 由主 app 用 `SMAppService.loginItem` 注册为登录项，`LSUIElement=true`。
    日常情况是主 app 关着、agent 常驻，所有 `ssh` 签名都走它的 socket。
  - `AppRestarter.isStandaloneNestedApp` 只认 `.regular` 激活策略的内嵌 app，所以一键更新既不退出
    也不重启这个 agent（读源码）。换包后它继续跑旧代码，而它的 bundle 已在磁盘上被替换。
  - 厂商自己的做法（`Sources/Secretive/App.swift`）是主 app 下一次激活时，若
    `justUpdatedBuild` 为真就 `forceLaunch()` 重拉 agent，注释写的是 agent "will be running
    from earlier update still"。我们的一键更新只在主 app 原本就开着时才重开它，而日常主 app 是关着的。
  - 换包后旧 agent 还能不能正常签名（比如它按需拉起的 `SecretAgentInputParser.xpc` 在 bundle
    被替换后能否启动）**未验证**。按规定没有启动真包去测，所以这条风险证明不了是安全的，只好不接一键。

## 已知问题
- 装不了新版的系统上会报「有更新」。4.0.0 要求 macOS 15。macOS 14 上装着 3.0.4 的用户会看到
  `3.0.4 → 4.0.0`，而厂商更新器按正文里的下限会跳过这一版、保持安静。因为只做检测，不会装上一个
  打不开的包，但这条提示对这部分用户没用。`GitHubReleaseRule` 目前没有表达 OS 下限的字段。

## 如何复验
```
# GET https://api.github.com/repos/maxgoedjen/secretive/releases/latest → v4.0.0
# ditto -x -k Secretive.zip → Secretive.app: com.maxgoedjen.Secretive.Host / 4.0.0 / Team Z72PRUAWF6
swift run --package-path application-test channel-verify <v4.0.0>/Secretive.app --expect stable
#   → winning source GitHub, latest 4.0.0, status up to date
swift run --package-path application-test channel-verify <v3.0.4>/Secretive.app --expect stable
#   → winning source GitHub, latest 4.0.0, status UPDATE → 4.0.0
```

## 建议下一步
1. 一键安装: 先在测试机上实测「agent 常驻、主 app 关着时替换 bundle」之后 `ssh-add -l` 和一次
   签名是否还正常；要是不正常，就需要引擎在换包后重拉 `LoginItems` 下的 accessory 登录项，
   做完这一步再加 `installAssetPattern: ^Secretive\.zip$`、`installerKind: .zip`。
2. OS 下限: 如果以后给 `GitHubReleaseRule` 加上按正文或包内 `LSMinimumSystemVersion` 过滤的能力，
   这个 app 是现成的用例。
