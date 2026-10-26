# FlowVision

## 基本信息
- Bundle ID: `netdcy.FlowVision`（1.0.2 起所有版本都是这个 id，下面「覆盖清单」逐版读过真包）
- 仓库: `netdcy/FlowVision`（开源，原生 AppKit 图片浏览器）
- Team ID: `M9PR3WG2FN`（1.4.0 起）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.7.6（tag `1.7.6`，资产 `FlowVision.1.7.6.zip` 与 `FlowVision.1.7.6.Xcode26.zip`）；观测日期: 2026-10-26
- 自更新机制: 无。没有 Sparkle、没有 `SUFeedURL`；源码（`FlowVision/Sources/`）和可执行文件里都没有 GitHub、releases 地址或更新检查，可执行文件里唯一的外链是 `https://flowvision.app`（官网与标签帮助页）
- 分发: GitHub Releases；Homebrew cask `flowvision`（装不带后缀的 zip，`auto_updates` 未设）；官网 flowvision.app 的下载按钮也指向 GitHub 上不带后缀的 zip；MAS 上没有（`mas search FlowVision` 只有同名的另一款游戏）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用源，只答 Caskroom 里有的副本） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）；brew 装的副本由排在 GitHub 前面的 `HomebrewCaskSource` 先答（`SourceStack.make` 的顺序，本次没有 brew 装的副本可测）。

## 覆盖清单
- 各版本的 bundle id / Team（逐个下载真包读，见「历史与实测」的表）:
  - 1.0.2 – 1.3.1: `netdcy.FlowVision`，ad-hoc（无 Team），spctl 拒。安装闸（Team 必须一致）拒这些副本的一键，它们仍看得到 1.7.6，手动更新一次即可。新版有 Team、GitHub 也没给这些旧资产发 digest，`.publishedDigestOnly` 不适用。
  - 1.4.0 起: `netdcy.FlowVision`，Team `M9PR3WG2FN`，Notarized。
  - 1.0.2 的包里版本写的是 `1.0`（build 1）：比较时 1.0 < 1.7.6，照样提示更新，不会卡住。
- 其他轨: 没有 prerelease / beta / nightly：36 个 release 全部 `prerelease: false`。tag 比 release 多三个：`1.0`、`1.0.3`、`1.6.7-Xcode26`，都没有 release（没有资产可下）；`versionPattern` 锚定 `^…$`，`1.6.7-Xcode26` 读不进来。
- **同一 bundle id 下的两种构建**（不是渠道，是厂商同一版本发的两份编译产物）:
  - 1.7.3 起每个 release 两个 zip：`FlowVision.<v>.zip`（Xcode 16.4 编译，`DTXcode` 1640）和 `FlowVision.<v>.Xcode26.zip`（Xcode 26.2，`DTXcode` 2620，macOS 26 上工具栏是液态玻璃风格）。release 说明原话：默认不带后缀的是 Xcode 16 版本。两者 id、Team、版本号、build 号都一样。
  - 1.7.0 – 1.7.2 只发一个 zip，但它是 Xcode 26 编译的（`DTXcode` 2611 / 2620）；1.6.7 及更早是 Xcode 16 或更早。
  - 区分信号：gate 读不了 Info.plist 的 `DTXcode`，只能读可执行文件。Xcode 26 的每个构建都导入 Swift 6.2 运行时的 `swift_coroFrameAlloc`，Xcode 16 及更早的都没有（17 个真包实测，见「历史与实测」）。源码里 `#if compiler(>=6.2)` 决定的 `SDK_VERSION` 是厂商自己的开关，但它编出来的 `NSToolbarSpaceItemIdentifier` 在 1.2.x – 1.3.1（Xcode 15/16）里也有，不能用。
  - 接法（照 Hoppscotch 的两版并存）：两条规则，带标记的 `xcode26` 规则答带 `swift_coroFrameAlloc` 的副本、给 `.Xcode26.zip`；不带标记的规则答其余副本、给不带后缀的 zip。两组 scoped `OneClickGate` 让每种 zip 只装到同一种构建的副本上；`Homebrew:flowvision`（装不带后缀的 zip）只给 Xcode 16 构建的副本。安装时下载包也按同一标记查。
  - 结果：1.7.0 – 1.7.2 的副本（Xcode 26 编译）被读成 Xcode 26 构建，提示并一键装 `.Xcode26.zip`，保持它现在的液态玻璃工具栏；用 brew 装的 1.7.0 – 1.7.2 副本，brew 那条 offer 被闸拦下（brew 会把它换成 Xcode 16 构建）。
- 版本范围: `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$` 读进全部 36 个稳定 tag（含四段的 `1.2.2.1`），拒 `1.6.7-Xcode26`。
- 主机下限: 包是 universal（x86_64 + arm64），`LSMinimumSystemVersion` 1.4.0 起是 11.0（更早是 11.0 / 12.0），低于我们自己的部署下限，不需要 `hostRequirement`。
- 改名: 没有，所有版本同一个 id；cask 的 zap 也只列 `netdcy.FlowVision`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（Xcode 16 构建） | `netdcy.FlowVision` | 共享 | 可执行文件里没有 `swift_coroFrameAlloc` | 不带标记的规则 + `executableLacks` 闸 | ✓ |
| stable（Xcode 26 构建） | `netdcy.FlowVision` | 共享 | 可执行文件里有 `swift_coroFrameAlloc` | `installedExecutableMarker` 规则（variant `xcode26`）+ `executableContains` 闸 | ✓ |

两种构建都是 stable，没有 beta/nightly 轨。

## 更新检测
- 源: `netdcy/FlowVision` GitHub Releases，`/releases/latest`
- 版本方案: tag `1.7.6` → `CFBundleShortVersionString` `1.7.6`、`CFBundleVersion` `20260908`（build 是日期，不参与比较）
- `versionPattern` `^([0-9]+(?:\.[0-9]+)+)$`
- install pattern: 默认 `^FlowVision\.[0-9]+(?:\.[0-9]+)+\.zip$`；Xcode 26 `^FlowVision\.[0-9]+(?:\.[0-9]+)+\.Xcode26\.zip$`（默认那条读不进 `.Xcode26.zip`，因为 `[0-9]+(?:\.[0-9]+)+` 吃不下 `Xcode26`）
- 注意事项: 如果厂商哪天不再发 `.Xcode26.zip`，`xcode26` 规则会退回到最后一个带这个资产的 release，并报 `installAssetMissing`（`GitHubReleasesSource` 的回退逻辑），不会把 Xcode 16 的包给 Xcode 26 副本。

## 按架构 / 按 OS 分轨
- 架构: 每个资产都是 universal（x86_64 arm64），不分架构
- `LSMinimumSystemVersion`: 11.0；两种构建一样，没有 `MaximumSystemVersion`
- 按 OS 分的是两种构建（Xcode 26 构建在 macOS 26 上才有液态玻璃工具栏，两者都支持 11.0+），由厂商让用户自选，不按主机选；我们按副本当前是哪种构建来选，不按主机

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（无 Sparkle.framework，可执行文件无更新相关字符串） | release 只有两个整包 zip | 不适用 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没跑（无更新器，没有可停放的东西） | — |
| 证据 | 没有更新器（源码与二进制） | — | 不适用 |

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: `changelog pane  source structured: 1 entries; newest 1.7.6: 6 items, headings ["Bug Fixes", "Note", "Bug 修复", "说明"]; first items ["Fixed an issue where the favorites panel", "Fixed a crash that could occur when gene", "Two compiled versions are provided. The "]` —— 分节标题保留为标题。正文是中英双语，中文节（「Bug 修复」「说明」）重复英文节的内容，原样显示。
- 跟随 channel: 两种构建共用同一个 release 正文
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（两种构建各装各的 zip）；真机第一轮两种构建都通过，第二轮被系统的网络卷权限框挡住（2026-10-26）
- 端到端（2026-10-26，本分支 `make cli` 的 duo）:
  - 第一轮，普通（Xcode 16）构建，不运行: 1.7.5 → `duo install`（`downloading` `verifyingSignature` `extracting` `verifyingCodeSignature` `installing` `installed`）→ 1.7.6、`TeamIdentifier=M9PR3WG2FN`、`codesign` 退出 0、`spctl` Notarized Developer ID；`DTXcode` 1640、`swift_coroFrameAlloc` 计数 0，装前装后不变（构建保持）
  - 第一轮，Xcode 26 构建，不运行: 1.7.5（`DTXcode` 2620、标记 7）→ 1.7.6，`DTXcode` 2620、标记 7（构建保持），Team、`codesign`、Notarized 同上
  - 第二轮，Xcode 26 构建运行中（`open -g` 19:44:22）: `duo install` 就地装好，提示 `Still running the old code`；`duo restart FlowVision` → `still running — likely a save prompt, left it alone`。截图显示原因是 FlowVision 首启触发的系统 TCC 框「FlowVision.app would like to access files on a network volume」，不是 FlowVision 自己的提示。磁盘上是 1.7.6 的 Xcode 26 构建、`codesign` 0；测试进程最后 `kill -TERM`。这个 TCC 框留给用户，没回答
  - 跨构建的 offer 没在真机上走（规则选包从不给跨构建的 offer），由 `OneClickGateTests.flowVisionOneClickIsPerBuild` 覆盖
  - 终态: 1.7.6（Xcode 26 构建），未运行
- 格式: .zip（`ditto -x -k` 解出来根目录就是 `FlowVision.app`）
- 嵌套 / 常驻组件: 无（`Contents/Frameworks` 下只有 ffmpeg 的 8 个 framework，没有 app / xpc / LoginItems）
- 校验: GitHub digest `sha256:be9d3f34592ee279ccb59d8b25c637ed1665c7c59699a197c3bc93bb8cd981b9`（`FlowVision.1.7.6.zip`），与下载的包一致
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 被拒的副本: 1.3.1 及更早（ad-hoc，无 Team）；brew 装的 Xcode 26 构建副本拿到的 brew offer（会换构建）；任何一种构建拿到另一种构建的 zip

## 已知问题
- 构建标记是编译器 ABI 的产物，不是厂商写的开关。两个方向的失效：
  - 厂商以后用 Xcode 26 编默认 zip（不再发 Xcode 16 版）：默认包里会出现标记，安装时的包检查拒装，Xcode 16 副本的一键失败关闭（仍提示更新）。
  - 将来的编译器不再导入 `swift_coroFrameAlloc`：Xcode 26 副本会被当成 Xcode 16 构建，一键会装不带后缀的 zip（失败打开）。到时要换标记；更干净的信号是 Info.plist 的 `DTXcode`，但 `OneClickGate` 目前没有读 plist 键的要求类型。
- 1.0.2 – 1.3.1（ad-hoc）只有检测，没有一键。

## 如何复验
```bash
gh release download 1.7.6 --repo netdcy/FlowVision --pattern 'FlowVision.1.7.6*.zip'
gh release download 1.7.5 --repo netdcy/FlowVision --pattern 'FlowVision.1.7.5*.zip'
.claude/skills/coverage-discovery/scripts/check-bundle.sh FlowVision.1.7.6.zip
ditto -x -k FlowVision.1.7.5.zip x175 && swift run --package-path application-test channel-verify x175/FlowVision.app --expect stable
grep -c -a -F swift_coroFrameAlloc x175/FlowVision.app/Contents/MacOS/FlowVision   # 0 = Xcode 16 构建
```

channel-verify 实测（2026-10-26，各包解压后的 `.app`）:

| 包 | 构建 | 结果 | 给的下载 |
|---|---|---|---|
| `FlowVision.1.7.5.zip` | Xcode 16 | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.zip` |
| `FlowVision.1.7.6.zip` | Xcode 16 | GitHub, up to date | `…/1.7.6/FlowVision.1.7.6.zip` |
| `FlowVision.1.7.5.Xcode26.zip` | Xcode 26 | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.Xcode26.zip` |
| `FlowVision.1.7.6.Xcode26.zip` | Xcode 26 | GitHub, up to date | `…/1.7.6/FlowVision.1.7.6.Xcode26.zip` |
| `FlowVision.1.7.2.zip` | Xcode 26 | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.Xcode26.zip` |
| `FlowVision.1.6.7.zip` | Xcode 16 | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.zip` |
| `FlowVision.1.3.1.zip` | ad-hoc | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.zip`（一键被 Team 闸拒） |
| `FlowVision.1.0.2.zip`（包内 `1.0`） | ad-hoc | GitHub, UPDATE → 1.7.6 | `…/1.7.6/FlowVision.1.7.6.zip`（一键被 Team 闸拒） |

## 建议下一步
1. 运行中一轮要等用户回答网络卷的 TCC 框后再跑（普通构建的运行中一轮也没跑）。
2. 若 `OneClickGate` 以后加了读 Info.plist 键的要求类型，把标记换成 `DTXcode`。

## 历史与实测

2026-10-26，逐个下载 release 资产、`ditto -x -k` 解压后读（`标记` = 可执行文件里 `swift_coroFrameAlloc` 出现的次数，`grep -c -a -F`）:

| 资产 | 包内版本 | DTXcode | Team | spctl | 标记 |
|---|---|---|---|---|---|
| FlowVision.1.7.6.zip | 1.7.6 | 1640 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.7.6.Xcode26.zip | 1.7.6 | 2620 | M9PR3WG2FN | Notarized Developer ID | 7 |
| FlowVision.1.7.5.zip | 1.7.5 | 1640 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.7.5.Xcode26.zip | 1.7.5 | 2620 | M9PR3WG2FN | Notarized Developer ID | 7 |
| FlowVision.1.7.3.zip | 1.7.3 | 1640 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.7.3.Xcode26.zip | 1.7.3 | 2620 | M9PR3WG2FN | Notarized Developer ID | 7 |
| FlowVision.1.7.2.zip | 1.7.2 | 2620 | M9PR3WG2FN | Notarized Developer ID | 7 |
| FlowVision.1.7.0.zip | 1.7.0 | 2611 | M9PR3WG2FN | Notarized Developer ID | 7 |
| FlowVision.1.6.7.zip | 1.6.7 | 1620 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.6.0.zip | 1.6.0 | 1600 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.5.0.zip | 1.5.0 | 1600 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.4.0.zip | 1.4.0 | 1600 | M9PR3WG2FN | Notarized Developer ID | 0 |
| FlowVision.1.3.1.zip | 1.3.1 | 1600 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.3.0.zip | 1.3.0 | 1600 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.2.2.1.zip | 1.2.2.1 | 1520 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.2.2.zip | 1.2.2 | 1520 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.1.0.zip | 1.1.0 | 1520 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.0.4.zip | 1.0.4 | 1520 | 无（ad-hoc） | 拒 | 0 |
| FlowVision.1.0.2.zip | 1.0 | 1520 | 无（ad-hoc） | 拒 | 0 |

全部 `netdcy.FlowVision`、universal、`codesign --verify --deep --strict` 通过、没有嵌套 app。1.7.6 两种构建 `nm -u` 的差异：Xcode 26 版多导入 `_swift_coroFrameAlloc`、`_NSToolbarSpaceItemIdentifier`，Xcode 16 版多 `__swift_FORCE_LOAD_$_swiftDataDetection` 等；`_NSToolbarSpaceItemIdentifier` 在 1.2.2 – 1.3.1 里也有，`libswiftDataDetection` 在 1.6.x 里没有，所以都不当标记。
