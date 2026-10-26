# Textream

## 基本信息
- App: Textream — 原生 SwiftUI 提词器（刘海 / 浮窗里随语音高亮讲稿），开源
- Bundle ID: `dev.fka.textream`（1.2.0 到 1.7.1 读过的真包都是这个，Mac App Store 版也是，见「覆盖清单」）
- 仓库: `f/textream`（默认分支 `master`，未归档）
- Team ID: `RJA7656U34`（1.6.4 起；`codesign --verify --deep --strict` 通过，spctl `Notarized Developer ID`）。1.6.3 及更早是 ad-hoc，见「覆盖清单」
- 观测版本: 1.7.1（tag `v1.7.1`，2026-09-06 发布）；上一版 1.7.0；观测日期: 2026-10-26
- 自更新机制: **只提示，不下载**。settled from source: `Textream/Textream/UpdateChecker.swift`（`master`）请求 `https://api.github.com/repos/f/textream/releases/latest`，按 `tag_name` 去掉 `v` 后逐段比数字，新于 `CFBundleShortVersionString` 时弹 NSAlert，点「Download」只用 `NSWorkspace.open` 打开 release 页面。`TextreamApp.swift` 在 `applicationDidFinishLaunching` 里静默调一次（`#if !APP_STORE`，商店版不编进去），菜单「Check for Updates」再手动调。没有 Sparkle（bundle 无 `Contents/Frameworks`、无 `SUFeedURL`），二进制里也只有这一处 GitHub API 字符串（`https://api.github.com/repos/` + `/releases/latest`）
- 分发: GitHub Releases（每个 release 两个 dmg，见「按架构 / 按 OS 分轨」）；Homebrew cask `textream`（1.7.1，`auto_updates` 未设，`depends_on macos: :sequoia`，url 固定指 `Textream.dmg`）；Mac App Store（id 6800061488，见下）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源） | ✓（商店副本由 App Store 源答） | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 1.7.1 `Textream.dmg`: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team（都读真包，`check-bundle.sh`）:
  - 1.7.1、1.7.0、1.6.5、1.6.4（`Textream.dmg` 和 `Textream-macos15.dmg` 各读一份）: `dev.fka.textream`，Team `RJA7656U34`，Notarized Developer ID。上游 `ci: sign and notarize macOS releases (#77)` 合在 1.6.4 发布前几分钟
  - 1.6.3、1.5.2、1.4.3（两种 dmg）、1.4.1、1.2.0、1.0.0（只有 `Textream.dmg`）: `dev.fka.textream`，`TeamIdentifier=not set`（ad-hoc）
  - 其余没下的 1.x 版本（1.0.1–1.3.6、1.5.0/1.5.1、1.6.0–1.6.2）: 签名未读；我的猜测是与相邻版本一样 ad-hoc（签名步骤是 1.6.4 才进 CI 的）
- Mac App Store 版: iTunes lookup（`id=6800061488`，2026-10-26）给出 `bundleId dev.fka.textream`、`version 1.0`、`minimumOsVersion 26.0`，与 GitHub 版同 id、版本线不同。商店副本带 `_MASReceipt`，`UpdateChecker` 里 `if app.isMASApp, !source.answersAppStoreCopies { continue }` 让它永远到不了 GitHub 规则，所以不会出现「1.0 → 1.7.1」的假更新，也不会被一键换成 Developer ID 的 dmg。没有商店版真包，未在真 bundle 上验证
- 其他轨: 没有。29 个 release 全部 `prerelease: false`，release workflow 写死 `prerelease: false`；没有 beta / nightly 资产、没有别的仓库
- 同 id 的两种构建: 见「按架构 / 按 OS 分轨」。规则对两种副本都给 `Textream.dmg`
- 版本范围: 版本模式读得出全部 29 个稳定 tag（`v1.0.0` … `v1.7.1`）。一键只对 Team `RJA7656U34` 的副本（1.6.4 及以后）放行；1.6.3 及更早的 ad-hoc 副本被 Team 闸拒（安装时 `noTeamIdentifier`），要手动装一次。这是安全的拒绝，不需要 gate；`.publishedDigestOnly` 不适用：现在的资产有 Team，装过去就是 Team 出现，不是 ad-hoc 对 ad-hoc
- 旧 bundle id: 没有改过名（读过的最老真包 1.0.0 就是 `dev.fka.textream`；cask 也只有这一个）
- 主机下限: DuoUpdater 只出 arm64、macOS 15.0 起（`App/project.yml`）。1.6.5 起 `LSMinimumSystemVersion` 15.0；1.6.4 及更早是 15.7（上游 issue #19、#47），所以 15.0–15.6 上不会有那些旧副本。两种 dmg 都是 universal（x86_64 + arm64）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `dev.fka.textream` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `f/textream` GitHub Releases，`/releases/latest`
- 版本方案: settled from source: `.github/workflows/release.yml` 从 tag 去掉 `v` 后用 `.github/set-macos-marketing-version.rb` 写进 Xcode 工程的 marketing version。tag `v1.7.1` → `CFBundleShortVersionString` `1.7.1`、`CFBundleVersion` `1`（build 号一直是 1）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：29 个 tag 全读出；`v2.0.0`、`v2.0` 读出；`v1.8.0-rc.1`、`v1.8.0-beta` 不匹配
- install pattern `^Textream\.dmg$`：只匹配 `Textream.dmg`，不匹配 `Textream-macos15.dmg`
- channel-verify（2026-10-26，真包）:
  - 1.7.0 `Textream.dmg`: `detected channel → stable`、`winning source GitHub`、`latest 1.7.1`、`download https://github.com/f/textream/releases/download/v1.7.1/Textream.dmg`、`status UPDATE → 1.7.1`
  - 1.7.1 `Textream.dmg`: `winning source GitHub`、`latest 1.7.1`、`status up to date`
  - 1.7.1 `Textream-macos15.dmg`: `winning source GitHub`、`latest 1.7.1`、`status up to date`（同版本不提示，不会把两种构建当成两个版本）

## 按架构 / 按 OS 分轨
- 1.4.3 起每个 release 两个 dmg，settled from source（`release.yml` 的 build matrix）: `Textream.dmg` 由 `macos-26` runner + Xcode 26.0 构建，`Textream-macos15.dmg` 由 `macos-15` runner + Xcode 16.2 构建，代码相同。release 正文说前者给 macOS 26 Tahoe 及以后、后者给 macOS 15 Sequoia
- 真包（1.7.1）: 两者 bundle id、版本、Team、`LSMinimumSystemVersion` 15.0 都相同，都是 universal；区别只在 `DTSDKName`（`macosx26.0` / `macosx15.2`）、`DTXcode`（`2601` / `1620`）和 `LC_BUILD_VERSION` 的 sdk（26.0 / 15.2，`minos` 都是 15.0）。Tahoe 版的可执行文件引用了 SwiftUI `Glass` 符号，Sequoia 版没有（2026-10-26 真机实测推翻了「没有」: `grep -c Glass` 两个构建分别是 11 和 7，两边都有）
- macOS 端源码里唯一的 Liquid Glass 调用是 `ContentView.swift` 的 `glassEffect`，包在 `#if compiler(>=6.2)` + `if #available(macOS 26.0, *)` 里，else 分支用 `.ultraThinMaterial`。也就是说 Tahoe 版在 macOS 15 上走的是和 Sequoia 版一样的分支
- 规则只装 `Textream.dmg`，和 homebrew-cask 官方的 `textream`（不分系统，一律 `Textream.dmg`，`depends_on macos: :sequoia`）一致；作者自己的 tap（`f/homebrew-textream`）用 `on_sequoia` 给 Sequoia 装 `-macos15` 版。后果: 装着 `Textream-macos15.dmg` 版的副本，一键后会换成同版本号的 Tahoe 版构建。macOS 26 及以后这就是厂商推荐的构建；macOS 15 上 Tahoe 版的实际表现**未验证**（这里没有 macOS 15 主机），依据只有上面的 `LSMinimumSystemVersion`、源码里的可用性判断和 Homebrew 官方 cask 的做法
- 引擎现在没有「按主机 macOS 选资产」的字段，`OneClickGate` 也只看磁盘上的副本、不看主机。如果要让 Sequoia 版副本留在 Sequoia 版，不改引擎也做得到: 两条规则 + `installedExecutableMarker`（原设想以 Tahoe 版独有的 SwiftUI `Glass` 符号为标记，但上面实测它分不开两种构建，得另找标记）+ 按包名限定的 `OneClickGate`（Hoppscotch 的做法）。代价是标记依赖厂商一直用 `glassEffect`，且从 15 升到 26 的用户会一直留在 Sequoia 版。本次没做，见「建议下一步」

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 自带检查只打开 release 页面（`UpdateChecker.swift`），bundle 无 Sparkle | release 资产只有两个整包 dmg | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 真机（2026-10-26）：1.7.0 运行中什么也没停放，自带检查只弹框 | 不需要 |
| 证据 | `UpdateChecker.swift` 不下载任何东西，只 `NSWorkspace.open` release 页 | — | — |

## Changelog
- 来源: GitHub release 正文（workflow 写的 `## Installation` 段 + GitHub 生成的 `## What's Changed`），经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 1.7.0 起）: `source structured: 1 entries; newest 1.7.1: 9 items, headings ["Installation", "What\'s Changed"]; first items ["**Textream.dmg** — for macOS 26 Tahoe an", "**Textream-macos15.dmg** — for macOS 15 ", "Keep App Store assets local"]`
- 分节保留（两个标题都在 headings 里，没有被压平成条目）。每个 release 都带的「Installation」段（两种 dmg 的说明）也作为一节显示，是厂商模板文字，不是改动
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-26，本分支 `make cli` 的 duo）**（对 Team `RJA7656U34` 的副本，1.6.4 起）
- 端到端:
  - 第一轮（不运行）: 1.7.0 → `duo install` → 1.7.1（`Textream.dmg`，`DTXcode` 2601）、`TeamIdentifier=RJA7656U34`、`codesign` 退出 0、`spctl` Notarized Developer ID
  - 第二轮（运行中）: 1.7.0 从 20:26:19 起运行，`duo install` 就地装好，提示 `Still running the old code`。`duo restart Textream` → `still running — likely a save prompt, left it alone`。截图: Textream 自己的 NSAlert「Update Available — Textream 1.7.1 is available… Later / Download」挡着退出，duo 不动它是对的（与 Joplin 同）；测试进程最后 `kill -TERM`，已退出
  - 两种构建: 每个 release 有 `Textream.dmg`（Xcode 26.0.1 / macosx26.0）和 `Textream-macos15.dmg`（Xcode 16.2 / macosx15.2），id、版本、Team 都相同，规则对两者都装 `Textream.dmg`。上面「按架构 / 按 OS 分轨」里设想的 `Glass` 标记实测分不开它们（`grep -c Glass` 两个构建分别是 11 和 7，`swift_coroFrameAlloc` 两个都是 0）。怎么处理等用户定
  - 终态: 1.7.1（`Textream.dmg` 构建），未运行
- 格式: dmg（根目录 `Textream.app` + `Applications` 软链）
- 嵌套 / 常驻组件: 无。`Contents` 下只有 `MacOS/Textream`、`Resources`、`_CodeSignature`；没有 Frameworks、LoginItems、Library、XPCServices。entitlements 只有 `com.apple.security.device.audio-input`。Info.plist 注册 URL scheme `textream`；app 还注册 Services 菜单（`NSApp.servicesProvider`），设置里可开本地 browser / director 服务器（随 app 进程起落）
- 签名: 1.7.1 和上一版 1.7.0 都是 Team `RJA7656U34`、notarized。1.6.3 及更早没有 Team，从那些版本升级会被 Team 闸拒
- 校验: GitHub 资产 `digest`。`Textream.dmg` 1.7.1 `sha256:b1225e2df372558cec5d7e42095b70e91249cb7898ef4a12ff6013f02a4d15b9`、1.7.0 `sha256:ba88abcfbf27af0956297c6b5a6acae416c1791a9927fd7795df9b1dd9fe064c`，下载后 `shasum -a 256` 都相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 阻塞: 无

## 已知问题
- 1.6.3 及更早的 ad-hoc 副本能看到更新但不能一键（Team 闸），要手动装一次
- 装着 `Textream-macos15.dmg` 构建的副本会被一键换成 `Textream.dmg` 构建（同版本号），见「按架构 / 按 OS 分轨」
- 自带检查每次启动静默请求一次 GitHub API；有新版时会弹「Update Available」框，和我们的提示并存，但它不下载、不换包，不会和一键抢

## 如何复验
```bash
gh release view v1.7.1 -R f/textream --json assets -q '.assets[]|.name+" "+.digest'
gh release download v1.7.1 -R f/textream -p 'Textream.dmg' -p 'Textream-macos15.dmg'
gh release download v1.7.0 -R f/textream -p 'Textream.dmg' -O Textream-1.7.0.dmg
.claude/skills/coverage-discovery/scripts/check-bundle.sh Textream-1.7.0.dmg Textream.dmg Textream-macos15.dmg
swift run --package-path application-test feed-discover Textream.dmg                              # → no Sparkle, no electron-builder, no MyGo
swift run --package-path application-test channel-verify Textream-1.7.0.dmg --expect stable       # → GitHub，UPDATE → 1.7.1
swift run --package-path application-test channel-verify Textream.dmg --expect stable             # → up to date
swift run --package-path application-test channel-verify Textream-macos15.dmg --expect stable     # → up to date
curl -s 'https://itunes.apple.com/lookup?id=6800061488&entity=macSoftware'                       # → bundleId dev.fka.textream
```

## 建议下一步
1. 决定 Sequoia 版副本的去向: 维持现状（一律换成 `Textream.dmg`，同 Homebrew 官方 cask），或者按「按架构 / 按 OS 分轨」末段的两条规则方案让它们留在 `-macos15` 构建。有 macOS 15 主机时先在上面跑一次 Tahoe 版构建。
2. 下一个正式版出来后，复查 `/releases/latest`、资产名仍是 `Textream.dmg`、Team 仍是 `RJA7656U34`。
