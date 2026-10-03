# Shift（字体编辑器，shift.graphics）

审计 2026-10-04。

> ⚠️ 同名不同产品：Homebrew 的 `shift` cask 是 shift.com 的「Workstation」
> （`com.rdbrck.shift`），装的也是 `/Applications/Shift.app`，与这份无关。
> `HomebrewCaskSource` 先按文件名找 cask，但只认 brew 真装过的 cask，
> 而同一路径上只能有一个 `Shift.app`，所以这个撞名不会把字体编辑器错认成那个 cask。

## 基本信息

- Bundle ID: `app.shift`（Release）、`app.shift.nightly`（Nightly）
- Team ID: `XZZWQ784ZU`（两个渠道相同，Notarized Developer ID）
- 观测版本: Release `0.1.1`、Nightly `0.111.1`（两者 short == build），`LSMinimumSystemVersion` 13.0，
  arm64 包 `lipo -archs` = `arm64`（另有 x64 包）
- 开源: `github.com/shift-editor/shift`（MIT OR Apache-2.0），Electron + Rust
- 自更新机制: **electron-updater**，`provider: generic`，bundle 自带 `Contents/Resources/app-update.yml`：

  ```yaml
  # Release
  provider: generic
  url: https://shift-editor.github.io/shift/updates/release/darwin/arm64
  updaterCacheDirName: shift-updater
  # Nightly
  provider: generic
  url: https://shift-editor.github.io/shift/updates/nightly/darwin/arm64
  updaterCacheDirName: shift-nightly-updater
  ```

- Sparkle: 没有 `SUFeedURL`
- Homebrew: 没有这个 app 的 cask（见上面的撞名说明）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe | Electron |
|---|---|---|---|---|---|---|
| **stable** (`app.shift`) | — | — | — | — | — | ✓ + changelog recipe |
| **nightly** (`app.shift.nightly`) | — | — | — | — | — | ✓ |

当前生效源：**Electron**（`ElectronManifestSource`）。两个渠道都不需要 VendorProbe recipe 或
GitHubReleaseRule。

## Channel 详情

settled from source: `docs/releases.md` 与 `apps/desktop/electron-builder.config.ts` on `main`。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `app.shift` | 独立 | — | 各自的 `app-update.yml` | ✓ |
| nightly | `app.shift.nightly` | 独立 | bundle id 后缀 `.nightly` | 各自的 `app-update.yml` | ✓ |

Pattern A：构建时 `SHIFT_DISTRIBUTION=release|nightly` 决定 `appId`、`productName`
（`Shift` / `Shift Nightly`）、数据目录和更新地址，两个可以并存。仓库没有 beta 轨道：
「Alpha / Developer Preview」只是 GitHub release 的 prerelease 标记和标题用语，不进版本号，
不是一个单独的构建。

## 更新检测

- 源: `ElectronManifestSource`
- 端点（GitHub Pages，`update-feeds` 分支）:
  - `https://shift-editor.github.io/shift/updates/release/darwin/arm64/latest-mac.yml`
  - `https://shift-editor.github.io/shift/updates/nightly/darwin/arm64/latest-mac.yml`
  - 另有 `…/darwin/x64/latest-mac.yml`；按架构分地址，地址由 bundle 自己写死，不需要猜
- 版本方案（settled from source: `docs/releases.md`）: 所有产物同一个三段数字版本，写进
  `CFBundleShortVersionString` 和 `CFBundleVersion`，与 manifest 的 `version` 一致。
  Release 走 `0.1.1`、`0.1.2`…；Nightly 是 `0.<GITHUB_RUN_NUMBER>.<GITHUB_RUN_ATTEMPT>`。
  两条线的数字没有可比性（Nightly 0.111.1 > Release 0.1.1），但 bundle id 不同，互不干扰。
- Release 的二进制在 GitHub Releases（`v0.1.1`，标记为 prerelease）；Nightly 的在
  Cloudflare R2 `releases.shift.graphics/nightly/<完整 commit>/`，每个 commit 一个不可变目录。
- manifest 没有 `minimumSystemVersion` / `stagingPercentage` 一类字段：不按 OS 分轨，没有灰度。
- 不在 `duo verify` 的扫描范围里（`ElectronManifestSource` 没有表可遍历，见它的类型注释）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（electron-updater blockmap 差分） | Release 有 blockmap；Nightly 没有 | 不能 |
| 证据 | electron-updater | Release 的 GitHub release 里有 `*.zip.blockmap`；`docs/releases.md` 说 Nightly 跨 commit 目录推不出上一版 blockmap，退回整包下载 | `DeltaApplier` 只吃 Sparkle binary delta |

## Changelog

- 来源: recipe（`Recipes/app-shift.swift`），读仓库根目录的 `CHANGELOG.md`（Release Please 生成）
- 结构化: `channel-verify` 的 `changelog pane` 行：
  `recipe changelog:app.shift:-: 1 entries; newest 0.1.1: 122 items, headings ["Features", "Bug Fixes", "Performance"]`
- 不用 GitHub releases：每个版本化 release 都是 `prerelease: true`，`.gitHubReleases` 对 stable
  只读非 prerelease，会一条都读不到；列表里还有滚动的 `nightly` release。
- 不用 `shift.graphics/releases`：那页是带视频的散文介绍，没有条目结构。
- 跟随 channel: 否。Nightly 没有 changelog（滚动 release 的正文只写了构建自哪个 commit），
  recipe 只挂在 `app.shift` 上。

## 一键安装

- 状态: 支持，由 `ElectronManifestSource` 提供（manifest 的 arm64 zip + sha512 + size，
  走 `VendorInstaller` 的 zip 路线 + Team ID 闸）
- 端到端:
  - Nightly：从 0.109.1 用 `duo install --yes` 升到 0.111.1，通过（下面「历史与实测」有记录）
  - Release：**未跑**。目前只发过 `v0.1.1` 一个版本，没有更早的包可装；走的是同一个源、同一条
    zip 路线、同一个 Team
- 格式: zip（DMG 给手动安装用）
- **读的是**: app 自己的 electron-updater 读的同一份 manifest。manifest 没有
  `stagingPercentage`，所以轨道最新的构建就是每台机器分到的构建。
- 嵌套 app: 只有 Electron 标准的 4 个 `Shift Helper*.app`（`Contents/Frameworks`，`LSUIElement`），
  没有 LoginItems / 常驻 helper
- 阻塞: 无

## 已知问题

- **Nightly 的 manifest 里写了 DMG，但 R2 上没有。** `files:` 列出
  `Shift-Nightly-<v>-macOS-arm64.dmg`，那个地址返回 404，R2 只归档了更新用的 zip。
  `ElectronManifest.artifact(forArch:)` 取 `files:` 里第一个名字带 `arm64` 的条目，眼下 zip
  排在 DMG 前面，所以一键不受影响；厂商若把 DMG 排到前面，Nightly 的一键会下到 404。
- Nightly 的旧 R2 目录在被新构建取代 14 天后删除，能拿来做 N→N+1 测试的旧版本有时间窗口。
- 版本线还在 0.x / Alpha，发布流程（feed 路径、R2 布局）改动的可能性比成熟产品高。

## 如何复验

```bash
# 1. manifest（两条轨）
curl -sS "https://shift-editor.github.io/shift/updates/release/darwin/arm64/latest-mac.yml" | head -3
curl -sS "https://shift-editor.github.io/shift/updates/nightly/darwin/arm64/latest-mac.yml" | head -3

# 2. 真包身份 + 渠道判定 + changelog pane
swift run --package-path application-test channel-verify Shift-0.1.1-macOS-arm64.dmg --expect stable
codesign -dvv "Shift Nightly.app" 2>&1 | grep TeamIdentifier

# 3. 生产源对真包的结论（channel-verify 的路径模式不跑 ElectronManifestSource，需要装上后用）
swift run --package-path application-test electron-verify app.shift

# 4. recipe fixture
swift test --package-path DuoUpdaterCore --filter ShiftChangelogRecipeTests
```

## 建议下一步

- 无。等 Release 发出第二个版本（0.1.2）后补一次 Release 的端到端。

## 历史与实测

### 2026-10-04 接入时的测量

**manifest。** Release arm64 `version: 0.1.1`，zip
`github.com/shift-editor/shift/releases/download/v0.1.1/Shift-0.1.1-macOS-arm64.zip`
（139,451,832 字节），`releaseDate: '2026-10-01T18:21:50.522Z'`。Nightly arm64 `version: 0.111.1`，zip
`releases.shift.graphics/nightly/f561c6ec…/Shift-Nightly-0.111.1-macOS-arm64.zip`
（139,736,239 字节），`releaseDate: '2026-10-03T16:15:41.533Z'`；同目录的 `.dmg` HEAD 返回 404。

**包身份。** `Shift-0.1.1-macOS-arm64.dmg` 挂载：`app.shift`，`0.1.1` / `0.1.1`，Team `XZZWQ784ZU`，
`spctl` accepted（Notarized Developer ID）。Nightly 0.111.1 zip 解包：`app.shift.nightly`，
`0.111.1` / `0.111.1`，同一 Team，`spctl` accepted。`channel-verify` 判定分别为 stable / nightly。

**生产源。** 对两个解出的 bundle 调 `AppScanner().scan(bundlesAt:)` + `ElectronManifestSource`，
再跑 `SourceStack.make` 全链：

```
Shift app.shift 0.1.1 stable → resolved 0.1.1 zip sha512 ✓ 139451832 · chain Electron upToDate
Shift Nightly app.shift.nightly 0.111.1 nightly → resolved 0.111.1 zip sha512 ✓ 139736239 · chain Electron upToDate
```

**Nightly 端到端。** 旧版 0.109.1（R2 `c46529a6…/Shift-Nightly-0.109.1-macOS-arm64.zip`，同 Team）
放进 `/Applications`：`duo check` 报 `0.109.1 → 0.111.1 [Electron, in-place]`；
`duo install --yes` 依次 `downloading … verifyingSignature … extracting … verifyingCodeSignature …
installing … installed.`。结果 `0.111.1`、Team `XZZWQ784ZU`、`codesign --verify --deep --strict`
返回 0、`spctl -t exec` accepted；之后 `duo check` 为 up to date。测试安装已移到废纸篓。

**changelog。** `CHANGELOG.md` 23,422 字节，1 条（`0.1.1`，2026-10-01），122 个条目，分在
Features / Bug Fixes / Performance 三节；文件末尾的 `## Changelog` 前言不算一条。
