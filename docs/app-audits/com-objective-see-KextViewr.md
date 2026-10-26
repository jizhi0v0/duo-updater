# KextViewr

## 基本信息
- App: KextViewr — Objective-See 的内核扩展查看器，列出当前加载的全部 kext（2.0.0 通过 `/usr/bin/kmutil` 读取），显示 bundle id、路径、所在 collection、地址、大小、架构；开源（`objective-see/KextViewr`，默认分支 `main`）
- Bundle ID: `com.objective-see.KextViewr`（1.1.0、2.0.0 相同）
- Team ID: `VBG97UB4TA`（Developer ID Application: Objective-See, LLC）；两个版本都是这个 Team，`codesign --verify --deep --strict` 通过，spctl: Notarized Developer ID（2.0.0 已 staple 票据；1.1.0 是 2016 年签的，没有 staple，spctl 在线判定为 Notarized Developer ID）
- 观测版本: 2.0.0（tag `v2.0.0`，资产 `KextViewr_2.0.0.zip`，2023-02-21）；上一版 1.1.0（`bitbucket.org/objective-see/deploy/downloads/KextViewr_1.1.0.zip`，产品页的「Older Version」）；观测日期: 2026-10-26
- 自更新机制: **无**。Info.plist 无 `SUFeedURL`，bundle 里没有 Sparkle 或任何 framework；v2.0.0 源码（`KextViewr/AppDelegate.m`、`consts.h`）唯一的网络动作是用 `NSWorkspace openURL` 在浏览器里打开 `https://objective-see.com` 和产品页 `PRODUCT_URL`。2.0.0 可执行文件 `strings` 里没有 `products.json`，也没有 VirusTotal 等任何 API 地址。1.1.0 的可执行文件会请求 VirusTotal API（`virustotal.com/vtapi/v2/file/report` 等，查 kext 的扫描结果），同样没有 `products.json` 或版本检查
- 分发: GitHub Releases（只有 v2.0.0 一个 release，一个 zip）；Homebrew cask `kextviewr`（2.0.0，`url` 就是 GitHub v2.0.0 资产，sha256 `cd921417…968e` 与下载一致，无 `auto_updates`、无 `livecheck`，未 deprecated）；官网产品页 `objective-see.org/products/kextviewr.html` 的下载按钮链到 GitHub 的 `v2.0.0/KextViewr_2.0.0.zip`，页上写的 SHA-1 `56F8D3B8…C6FF` 与下载一致；另给一个「Older Version」1.1.0（bitbucket，「compatible with older versions of macOS」）
- 厂商近况: 最后一个 release v2.0.0（2023-02-21），仓库未归档；产品页、README 没有停止维护的声明

### objective-see.org 与 GitHub 的版本对照（2026-10-26）
- 产品页 `products/kextviewr.html`: Current version 2.0.0，下载链到 GitHub `v2.0.0/KextViewr_2.0.0.zip` → 与 GitHub latest **一致**
- `objective-see.org/products.json` 的 `"KextViewer"` 条目（键名拼写如此）: `version` 2.0.0，`zip` 指向 GitHub v2.0.0 资产 → **一致**。KextViewr 本身不读这个 JSON（见上），我们也不读
- 结论: 官网上没有比 GitHub 更新的版本；GitHub Releases 是正版下载源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源，只管 brew 装的副本；本次未单独验证） | — | ✓ | — |

当前生效源（非 brew 装的副本）: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 2.0.0: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- bundle id：1.1.0（bitbucket，x86_64、`LSMinimumSystemVersion` 10.7）和 2.0.0（universal、11.0）都是 `com.objective-see.KextViewr`，没有改名；cask 无 `old_tokens`。仓库只出这一个产品
- 两个版本的差别不只是架构：1.1.0 是给 macOS 11 之前用的旧版（自己枚举 kext，带 VirusTotal 查询，bundle 里有 `VTInfoWindow.nib`），2.0.0 是重写的 macOS 11+ 版（用 `kmutil`，去掉了 VirusTotal，bundle 里有 `Assets.car`、`patrons.txt`）。两者在包上可区分的标记：`LSMinimumSystemVersion` 10.7 vs 11.0、`CFBundleShortVersionString` 1.x vs 2.x、`Contents/Resources/VTInfoWindow.nib` 只在 1.1.0 里。它们不是并行的两条产品线：1.1.0 版本号更低、2016 年后不再发，厂商把它标成「Older Version」供旧系统用。DuoUpdater 只跑在 macOS 15+（`App/project.yml`），这些主机都满足 2.0.0 的 11.0 下限，所以 1.1.0 副本升到 2.0.0 正是厂商给新系统的建议，不加 `OneClickGate`
- 版本范围 / 签名: 两个版本同 Team `VBG97UB4TA`、都已公证 → 检测 ✓、一键 Team 闸放行。更早的版本（1.0.x）没有找到公开下载，未核
- 其他轨: GitHub 只有一个 release（v2.0.0），不是 prerelease，tag 也只有 `v2.0.0`；仓库没有 beta / nightly 分支或构建脚本。单轨
- 主机下限: DuoUpdater 是 arm64、macOS 15.0（`App/project.yml`）；KextViewr 2.0.0 universal、`LSMinimumSystemVersion` 11.0，无需架构 / OS 门控。1.1.0 只有 x86_64，只能在 Rosetta 下跑，但检测和换包不受影响（channel-verify 实测 1.1.0 → 2.0.0）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.objective-see.KextViewr` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `objective-see/KextViewr` GitHub Releases，`/releases/latest`
- 版本方案: tag `v2.0.0` → `CFBundleShortVersionString` `2.0.0`、`CFBundleVersion` `2.0.0`（1.1.0 两者也相同）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`。Python `re` 核对：`v2.0.0`/`v1.1.0` → 2.0.0/1.1.0；`v2.1`、`v3.0.0` 可读；`v2.1.0-beta`、`v2.1.0-rc.1`、无 `v` 的 `2.1.0`、`v2` 不匹配
- install pattern `^KextViewr_[0-9]+(?:[._][0-9]+)+\.zip$`：只有一个 release，名字是点分；同厂商的 DHS 在 1.5.x 用过下划线（`DHS_1_5_1.zip`），所以两种都接受。核对：`KextViewr_2.0.0.zip`、`KextViewr_1.1.0.zip`、`KextViewr_2_1_0.zip` 匹配，`KextViewr_2.0.0.dmg`、`KextViewr.zip`、`KextViewr_2.1.0_beta.zip` 不匹配
- channel-verify（2026-10-26，真包 `ditto -x -k` 解压后的 bundle）:
  - 1.1.0: `detected channel → stable`、`winning source GitHub`、`latest 2.0.0`、`status UPDATE → 2.0.0`
  - 2.0.0: `detected channel → stable`、`winning source GitHub`、`latest 2.0.0`、`status up to date`

## 按架构 / 按 OS 分轨
- 2.0.0 一个 universal zip（`lipo -archs` = `x86_64 arm64`），`LSMinimumSystemVersion` 11.0；1.1.0 只有 x86_64、10.7（历史包，不再发，见覆盖清单）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见基本信息） | 每个 release 只有一个 zip | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无 | 不需要 |
| 证据 | 没有更新器，不下载 | — | — |

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-26，channel-verify `changelog pane`，从 1.1.0 起）: `source structured: 1 entries; newest 2.0.0: 2 items, headings []; first items ["UI refresh/improvements", "macOS 11+ compatibility (#1)"]`
- v2.0.0 正文就是两行纯文本，没有小标题；两行都成了条目，没有标题可丢
- 仓库里的 `KextViewr/changelog.txt` 是从 TaskExplorer 抄来的旧文件（内容是 TaskExplorer 1.0.0–1.2.0），不是 KextViewr 的说明，不用
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（同 Team `VBG97UB4TA` 的全部已知副本）
- 端到端: 待主会话
- 格式: zip，根目录就是 `KextViewr.app`；pattern `^KextViewr_[0-9]+(?:[._][0-9]+)+\.zip$`，kind `.zip`
- 签名: 2.0.0 `TeamIdentifier=VBG97UB4TA`、Notarized Developer ID（已 staple）、hardened runtime（`flags=0x10000(runtime)`）
- 嵌套 / 常驻组件: 无。bundle 里只有 `MacOS/KextViewr` 和资源文件：没有嵌套 app、framework、XPC、kext、`Library/LoginItems`、`Library/LaunchServices`；源码里没有 `SMAppService` / `SMJobBless` / LaunchAgent
- 校验: v2.0.0 资产没有 GitHub digest；下载包 sha256 `cd92141750812797cffd626f697c133fac84b615b5d4cd5dae56a8160320968e`，与 Homebrew cask 一致。Team-ID 路线不需要 digest
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

### 真机注意事项（从 v2.0.0 源码读出）
- 启动即枚举 kext（`applicationDidFinishLaunching` → `enumKexts`，执行 `/usr/bin/kmutil`），关窗即退出；没有首次启动标记、没有偏好写入，只有用户点「保存」时才把结果写到用户选的文件
- 不改网络 / 代理 / DNS / 系统安全设置：源码里没有 `SCPreferences`、PAC、hosts、Network Extension、root CA、`AuthorizationCreate`；它只读 kext 列表
- 1.1.0 副本启动时会向 VirusTotal 发请求（每个 kext 的哈希）；真机从 1.1.0 起跑一键时不需要启动它

## 已知问题
- GitHub 上只有一个 release，没有上一版 GitHub 资产可比；上一版取自产品页的 bitbucket 链接（1.1.0）
- 若厂商下次换资产命名（加架构后缀或改 dmg），一键会找不到资产，届时要更新 pattern

## 如何复验
```bash
gh api repos/objective-see/KextViewr/releases -q '.[]|.tag_name+" "+(.prerelease|tostring)+" "+(.assets[]|.name+" "+(.digest//"nodigest"))'
gh release download v2.0.0 --repo objective-see/KextViewr --pattern 'KextViewr_2.0.0.zip'
curl -sLO https://bitbucket.org/objective-see/deploy/downloads/KextViewr_1.1.0.zip
.claude/skills/coverage-discovery/scripts/check-bundle.sh KextViewr_2.0.0.zip KextViewr_1.1.0.zip   # 都是 com.objective-see.KextViewr / VBG97UB4TA / Notarized
ditto -x -k KextViewr_1.1.0.zip old && swift run --package-path application-test channel-verify old/KextViewr.app --expect stable   # → GitHub，UPDATE → 2.0.0
curl -s https://objective-see.org/products.json | grep -A3 'KextViewer'   # 官网 JSON 的版本
curl -s https://objective-see.org/products/kextviewr.html | grep -o 'releases/download/[^"]*'  # 产品页下载链
```

## 建议下一步
1. 厂商发下一个 release 时复查：Team 是否仍是 `VBG97UB4TA`、资产名是否仍匹配 `KextViewr_<ver>.zip`、tag 仍是 `v<x.y.z>`。
