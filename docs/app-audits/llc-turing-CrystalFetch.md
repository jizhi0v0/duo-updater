# CrystalFetch

## 基本信息
- Bundle ID: `llc.turing.CrystalFetch`
- Team ID: `WDNLXAD4W8`（Developer ID Application: Turing Software, LLC）
- 观测版本: `2.2.0`（`CFBundleVersion` 是递增构建号 `6`，不参与比较）
- 自更新机制: 无（Info.plist 没有 `SUFeedURL`，`Contents/Frameworks` 里只有 `OpenSSL.framework`，没有 Sparkle）
- 分发: GitHub Releases（`TuringSoftware/CrystalFetch`）/ Homebrew cask `crystalfetch`（非 `auto_updates`，
  url 即 GitHub 资产）/ Mac App Store（id6454431289，同一 bundle id）
- 开源: 是。版本与资产名读自仓库 `.github/workflows/build.yml`（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓        | ✓   | ✓      | —           |

Homebrew 与 MAS 列走的是通用源（cask 安装 / 商店收据），不需要本 recipe；这两条路径本次没有
用 cask 装或商店副本单独验证（未验证）。
当前生效源（`UpdateChecker` 优先链中第一个应答的）: 直接下载的副本为 **GitHub**
（channel-verify 实测，见下）；商店副本由 `GitHubReleasesSource` 的 `isMASApp` 闸跳过 GitHub，
交给商店。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `llc.turing.CrystalFetch` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |

单渠道：仓库 6 个 release（v1.0.0 … v2.2.0）全部非 prerelease、非 draft，tag 列表与 release 列表一致。

## 更新检测
- 源: `TuringSoftware/CrystalFetch` GitHub Releases
- 版本方案: `build.yml` 在 `release: created` 时打包，版本号来自 Xcode 工程，tag 由人手建。
  实测 tag `v2.2.0` → `2.2.0` == 包的 `CFBundleShortVersionString`；`v2.1.1` 的包同样是 `2.1.1`。
- 资产: 每个 release 只有一个 `CrystalFetch.dmg`（`upload-release-asset` 写死 `asset_name`），
  六个 release 全部如此，无命名漂移、无缺 mac 资产的 release。
- 同一次 CI 还把 App Store 版 pkg 上传到 App Store Connect（`submit` job，`app-store` 配置，
  bundle id 同为 `${PRODUCT_BUNDLE_PREFIX}.CrystalFetch`）。2026-09-29 iTunes lookup:
  商店版本 `2.2.0`，`currentVersionReleaseDate` 2025-04-16，GitHub v2.2.0 发布于 2025-03-28。
- 注意事项: 商店版与 GitHub 版同 bundle id，由 `isMASApp` 闸隔开；不会把 Developer ID 包换进商店副本。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | bundle 里无更新框架 | release 只有整包 dmg（2026-09-29） | — |

## 按 OS 分轨
- 包 `LSMinimumSystemVersion` = `12.0`（2.1.1 与 2.2.0 相同）；cask `depends_on macos: :monterey` 一致。
  release 没有按 OS 分的资产。

## Changelog
- 来源: GitHub Release body（v2.2.0 body 217 字符，v1.0.0 为空）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要
- channel-verify 输出为 `release notes 0 chars inline, changelogURL …/releases/tag/v2.2.0`；
  body 是否在 app 里被结构化带回未在本次验证（未验证）

## 一键安装
- 状态: **支持**
- 格式: dmg — `CrystalFetch.dmg`，universal（`lipo -archs`: `x86_64 arm64`）
- Pattern: `^CrystalFetch\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 下的也是同一个 url）
- 包验（2026-09-29，v2.2.0 与 v2.1.1 挂载）: `llc.turing.CrystalFetch`，Team `WDNLXAD4W8`，
  `spctl accepted / source=Notarized Developer ID`，universal
- 端到端（2026-09-29）: 装 2.1.1 → `duo check` 报 `2.1.1 → 2.2.0 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `2.2.0`、Team `WDNLXAD4W8`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- 无。

## 如何复验
```
# GET https://api.github.com/repos/TuringSoftware/CrystalFetch/releases/latest → v2.2.0
# 挂载 v2.2.0/CrystalFetch.dmg → llc.turing.CrystalFetch / 2.2.0 / Team WDNLXAD4W8
swift run --package-path application-test channel-verify <v2.2.0 CrystalFetch.dmg> --expect stable
#   → winning source GitHub, latest 2.2.0, status up to date
swift run --package-path application-test channel-verify <v2.1.1 CrystalFetch.dmg> --expect stable
#   → winning source GitHub, latest 2.2.0, status UPDATE → 2.2.0
```

## 建议下一步
无。检测 + 一键均已覆盖（含端到端）。
