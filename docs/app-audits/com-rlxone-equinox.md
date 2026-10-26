# Equinox

## 基本信息
- App: Equinox — 动态壁纸（HEIC）制作工具，沙盒 app（`com.apple.security.app-sandbox`），开源（`rlxone/Equinox`，默认分支 `main`，未归档）
- Bundle ID: `com.rlxone.equinox`（v1.0.1 起所有 GitHub 包相同；Mac App Store 版同 id，见覆盖清单）
- Team ID: v6.0、v7.0 `ANWX99972B`（Developer ID Application: DZMITRY MIADZIUKHA），`codesign --verify --deep --strict` 通过，spctl: Notarized Developer ID；**v5.0、v4.0、v1.0.1 是 ad-hoc**（`Signature=adhoc`、`flags=0x2(adhoc)`、`TeamIdentifier=not set`）
- 观测版本: 7.0（`CFBundleVersion` 20，tag `v7.0`，资产 `Equinox-Installer.dmg`）；上一版 6.0（build 17）；观测日期: 2026-10-26
- 自更新机制: **无**。settled from source: `v7.0` tag 的全部源码里没有 `URLSession` / `URLRequest` / `dataTask`（`grep -rlE` 计数 0），没有 Sparkle 依赖；Info.plist 无 `SUFeedURL`；可执行文件和三个自带 framework 的 `strings` 里没有 sparkle / appcast / releases 地址，只有帮助菜单和欢迎页的 GitHub、官网、PayPal、App Store 评论链接（都经 `NSWorkspace.shared.open` 交给浏览器）
- 分发: GitHub Releases（每版一个 dmg）；Homebrew cask `equinox`（7.0，`url` 即 GitHub 的 v7.0 资产，`auto_updates` 未设，`depends_on macos >= 12`）；Mac App Store `id1591510203`（免费，见覆盖清单）；官网 equinoxmac.com。仓库 README 把 App Store 和 GitHub Releases 并列为两个下载入口
- 厂商近况: v7.0 发布于 2026-09-25；README 没有停止维护、终止的说法

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源，只管 brew 装的副本；本次未单独验证） | ✓（通用 App Store 源，只管商店副本；本次未单独验证） | ✓ | — |

当前生效源（非 brew、非商店的副本）: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 7.0: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- bundle id：v1.0.1 / v4.0 / v5.0 / v6.0 / v7.0 的真包都是 `com.rlxone.equinox`，没有改名。v1.0 这个 release 没有资产，无包可读（它的 tag 与 v1.0.1 只差两天）
- 版本范围 / 签名（逐个读真包）:
  - v7.0、v6.0: Team `ANWX99972B`，公证 → 一键 ✓
  - v5.0、v4.0、v1.0.1: ad-hoc，无 Team → 检测 ✓（v4.0 真包 UPDATE → 7.0），**一键被 Team 闸拒**（见一键安装）。`.publishedDigestOnly` 不适用：新版有 Team，信任只升不降
  - 资产名: v1.0.1–v4.0 是 `Equinox.dmg`，v5.0 起是 `Equinox-Installer.dmg`。名字里虽有 Installer，dmg 里是 `Equinox.app` 和 `/Applications` 链接，不是安装器。install pattern `^Equinox(?:-Installer)?\.dmg$` 两个名字都收
- **Mac App Store 版（同 bundle id）**: iTunes lookup `bundleId=com.rlxone.equinox`（2026-10-26）→ `Equinox: Dynamic Mac Wallpaper`，trackId 1591510203，`version 7.0`，免费，`currentVersionReleaseDate 2026-09-25`，与 GitHub 版本线同步。settled from source（`Equinox/Equinox.xcodeproj/project.pbxproj` on `v7.0`）：`Release-App-Store` 和 `Release-Installer` 两个配置用同一个 `PRODUCT_BUNDLE_IDENTIFIER`、同一个 entitlements 文件，只差 `APP_DISTRIBUTION`（`app_store` / `installer`），写进 Info.plist 的 `AppDistribution`。代码里读它的只有 `NSApplication.isAppStoreBuild` / `isInstallerBuild`（`Extensions/AppExtensions.swift`），用于支持页：商店版走 StoreKit 小费，安装版显示一个打开 PayPal 的捐赠项（`SupportViewController.swift`）。功能、版本号相同，差别在分发和签名
  - 区分标记: GitHub 包实测 `AppDistribution=installer`、无 `Contents/_MASReceipt`、Developer ID 签名（v6.0、v7.0；v5.0 及更早没有 `AppDistribution` 键）。商店包**没有实测**（只能经 App Store 安装）；按源码它是 `AppDistribution=app_store`，引擎用的是商店安装带的 `Contents/_MASReceipt/receipt`（`InstalledApp.isMASApp`）
  - 商店副本不会走到这条规则：`UpdateChecker` 只把 `isMASApp` 的副本交给 `answersAppStoreCopies` 为真的源（`UpdateChecker.swift` 的 `apps(_:visibleTo:)` 和检查循环），`GitHubReleasesSource` 里另有 `guard !app.isMASApp`。所以一键不会拿 Developer ID 包盖掉商店副本。与 Itsytv（`com.itsytv.app`）同一情形
- 其他轨: 8 个 release 都不是 prerelease，tag 只有 `v1.0`…`v7.0`；`.github/workflows/workspace.yml` 只做 CI 构建和测试，没有发版或 nightly；Homebrew 没有 `equinox@beta` 之类的变体（`brew search --cask equinox` 只有 `equinox` 和无关的 `equibop`）。单轨
- 主机下限: DuoUpdater 是 arm64、macOS 15.0（`App/project.yml`）；Equinox 是 universal，7.0 的 `LSMinimumSystemVersion` 12.0（6.0 及更早 10.14），无需架构 / OS 门控

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.rlxone.equinox` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `rlxone/Equinox` GitHub Releases，`/releases/latest`
- 版本方案: tag `v7.0` → `CFBundleShortVersionString` `7.0`；`CFBundleVersion`（20 / 17 / 9 / 6 / 1）不参与比较
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`。Python `re` 核对：全部 8 个 tag（`v1.0`、`v1.0.1`、`v2.0`…`v7.0`）都读得出；`v8.0`、`v10.0.1` 可读；`v8.0-beta`、`v8.0-rc.1`、无 `v` 的 `8.0`、`v8` 不匹配
- install pattern `^Equinox(?:-Installer)?\.dmg$`，kind `.dmg`；`Equinox-Installer.zip`、`Equinox-Installer.DMG`、`Equinox-Beta.dmg` 不匹配
- channel-verify（2026-10-26，真 dmg 挂载只读）:
  - 6.0: `detected channel → stable`、`winning source GitHub`、`latest 7.0`、`status UPDATE → 7.0`
  - 4.0（ad-hoc）: `winning source GitHub`、`latest 7.0`、`status UPDATE → 7.0`
  - 7.0: `winning source GitHub`、`latest 7.0`、`status up to date`

## 按架构 / 按 OS 分轨
- 架构: 每版一个 universal dmg（`x86_64 arm64`，v1.0.1–v7.0 相同）；`LSMinimumSystemVersion` 7.0 为 12.0，6.0 及更早为 10.14。README 说 10.14 / 10.15 用户停在 6.0，与 DuoUpdater 的 15.0 下限无关

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见基本信息） | 每个 release 只有一个 dmg（API 资产列表） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（没有更新器；2026-10-26 运行中一轮正常完成，见一键安装） | 不需要 |
| 证据 | 没有更新器，不下载 | — | — |

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，6.0 → 7.0）: `source structured: 1 entries; newest 7.0: 4 items, headings []; first items ["**macOS 27 refinements** — updated the i", "**Japanese localization added** — Equino", "**Reliability fixes** — fixed crashes wh"]`
- v7.0 正文是一张截图 + `## What's Changed` + 4 条编号列表；4 条全保留（编号列表走解析器的宽松一轮），截图行不进条目。唯一的标题是通用的 `What's Changed`，不是分类标题，没有被压平进条目，没有丢内容。条目保留行内 Markdown（加粗、PR 链接），由渲染器处理
- 只显示 1 条（7.0）：`/releases/latest` 的 rule 只读一个 release（引擎设计）
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持（只对 Developer ID 的 6.0 及以后的副本）**
- 端到端（2026-10-26，本分支 `make cli` 的 duo，6.0 → 7.0 两轮都通过）:
  - 第一轮（不运行）和第二轮（运行中）: 都装到 7.0，`TeamIdentifier=ANWX99972B`、`codesign` 退出 0、Notarized Developer ID；运行中一轮的 `duo restart` 重新拉起后是 7.0
  - 终态: 7.0，未运行
- 格式: dmg（`hdiutil imageinfo` 退出 0），根目录 `Equinox.app` + `Applications` 链接 + `.background`
- 签名: 7.0、6.0 `TeamIdentifier=ANWX99972B`、Notarized Developer ID、hardened runtime（`flags=0x10000(runtime)`），带 `embedded.provisionprofile`；entitlements 两版相同（sandbox、user-selected read-write、location、`com.apple.developer.team-identifier`）
- 校验: GitHub 给 v5.0 起的资产发了 `digest`。v7.0 `sha256:26b2fae0…7f747127`、v6.0 `sha256:1271dfb0…bd24261`，与下载文件的 `shasum -a 256` 相同；GitHub rule 自动传给安装器，不需要逐 rule 配置
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- **5.0 及更早 → 7.0 会被拒**: 已装副本 ad-hoc，没有 Team，`SignatureVerifier.verifyTeamIdentifierMatch` 报 `noTeamIdentifier(which: "installed")`。检测照常提示 7.0，用户需手动装一次；之后走一键。v5.0 资产下载 1172 次、v4.0 4037 次（2026-10-26 读 API），这组副本不少
- 商店副本: 不经过这条规则，见覆盖清单
- 嵌套 / 常驻组件: 无。`Contents/Frameworks` 只有 `EquinoxAssets` / `EquinoxCore` / `EquinoxUI` 三个自家 framework；没有 LoginItems、Helpers、XPC、LaunchServices；源码里没有 `SMAppService` / `SMLoginItem`

### 真机注意事项（从 v7.0 源码和包读出）
- 沙盒 app，数据在 `~/Library/Containers/com.rlxone.equinox`（cask 的 `zap` 也列了它和 `~/Library/Application Scripts/com.rlxone.equinox`）
- 每次启动都先开欢迎窗口（`StoriesController.start()` → `presentWelcome()`）；Solar 类型壁纸页用 `CLLocationManager` 请求定位权限（`NSLocationUsageDescription`），不用这功能就不会弹
- 没有 URL scheme（Info.plist 无 `CFBundleURLTypes`），没有登录项

## 已知问题
- 5.0 及更早的副本不能一键（ad-hoc，见上），只能手动换到 6.0 / 7.0 一次
- 资产名在 v5.0 改过一次；若再改，install pattern 匹配不到，检测仍正常、一键会报无可装资产

## 如何复验
```bash
gh api 'repos/rlxone/Equinox/releases?per_page=100' -q '.[]|.tag_name+" "+(.prerelease|tostring)+" "+([.assets[]|.name+"|"+(.digest//"nodigest")]|join(","))'
gh release download v7.0 --repo rlxone/Equinox --pattern 'Equinox-Installer.dmg' --dir v7.0
gh release download v6.0 --repo rlxone/Equinox --pattern 'Equinox-Installer.dmg' --dir v6.0
gh release download v4.0 --repo rlxone/Equinox --pattern 'Equinox.dmg' --dir v4.0
.claude/skills/coverage-discovery/scripts/check-bundle.sh v7.0/Equinox-Installer.dmg v6.0/Equinox-Installer.dmg v4.0/Equinox.dmg   # ANWX99972B / ANWX99972B / not set
swift run --package-path application-test feed-discover v7.0/Equinox-Installer.dmg                       # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify v6.0/Equinox-Installer.dmg --expect stable      # → GitHub，UPDATE → 7.0
swift run --package-path application-test channel-verify v7.0/Equinox-Installer.dmg --expect stable      # → GitHub，up to date
curl -s 'https://itunes.apple.com/lookup?bundleId=com.rlxone.equinox'                                   # 商店版同 id
```

## 建议下一步
1. 厂商发下一个 release 时复查：签名是否仍是 `ANWX99972B`、资产名是否仍匹配、tag 仍是 `v<x.y>`。
