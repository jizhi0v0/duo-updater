# DHS

## 基本信息
- App: DHS（Dylib Hijack Scanner）— Objective-See 的按需扫描工具，找出易被 dylib 劫持或已被劫持的 app；开源（`objective-see/DylibHijackScanner`，默认分支 `main`）
- Bundle ID: `com.objective-see.DHS`（1.4.1、1.5.0、1.5.1、1.6.0 相同）
- Team ID: `VBG97UB4TA`（Developer ID Application: Objective-See, LLC）；四个版本都是这个 Team，`codesign --verify --deep --strict` 通过，spctl: Notarized Developer ID
- 观测版本: 1.6.0（tag `v1.6.0`，资产 `DHS_1.6.0.zip`）；上一版 1.5.1（`DHS_1_5_1.zip`）；观测日期: 2026-10-26
- 自更新机制: **无**。Info.plist 无 `SUFeedURL`，bundle 里没有 Sparkle 或任何 framework；v1.6.0 源码（`DHS/AppDelegate.m`、`Consts.h`）唯一的网络动作是用 `NSWorkspace openURL` 在浏览器里打开 `https://objective-see.org` 和产品页 `PRODUCT_URL`。可执行文件 `strings`（1.4.1、1.5.1、1.6.0）里没有 `products.json`，也没有 `NSURLSession` / `NSURLConnection`。这一点和 KnockKnock 不同：KnockKnock 的 `Update.m` 会读 `objective-see.org/products.json`，DHS 没有对应代码
- 分发: GitHub Releases（每版一个 zip）；Homebrew cask `dhs`（1.6.0，`url` 就是 GitHub v1.6.0 资产，sha256 `3e72ffa5…728f` 与下载一致，无 `auto_updates`、无 `livecheck`，未 deprecated）；官网产品页 `objective-see.org/products/dhs.html` 的下载按钮直接链到 GitHub 的 `v1.6.0/DHS_1.6.0.zip`；没有 MAS 版（iTunes lookup 按 bundle id 返回 0 条）
- 厂商近况: 最后一个 release v1.6.0（2025-10-11），仓库未归档

### objective-see.org 与 GitHub 的版本对照（2026-10-26）
- 产品页 `products/dhs.html`: 1.6.0，下载链到 GitHub `v1.6.0/DHS_1.6.0.zip` → 与 GitHub latest **一致**
- `objective-see.org/products.json` 的 `"Dynamic Hijack Scanner"` 条目: `version` **1.4.1**，`zip` 指向 `bitbucket.org/objective-see/deploy/downloads/DHS_1.4.1.zip` → **落后**于 GitHub。DHS 本身不读这个 JSON（见上），所以它不影响任何副本；我们也不读它
- 结论: GitHub Releases 是正版下载源；官网上没有比 GitHub 更新的版本

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓（通用 cask 源，只管 brew 装的副本；本次未单独验证） | — | ✓ | — |

当前生效源（非 brew 装的副本）: **GitHub**（channel-verify 实测，见下）。`feed-discover` 对 1.6.0: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- bundle id：1.4.1（bitbucket 上的旧包，x86_64、`LSMinimumSystemVersion` 10.8）、1.5.0（arm64）、1.5.1、1.6.0（universal）都是 `com.objective-see.DHS`，没有改名；cask 无 `old_tokens`。同仓库没有别的产品
- 版本范围 / 签名: 四个版本同 Team `VBG97UB4TA`、都已公证 → 检测 ✓、一键 Team 闸放行
- 其他轨: GitHub 三个 release（v1.5.0 / v1.5.1 / v1.6.0）都不是 prerelease，tag 也只有这三个；仓库没有 beta / nightly 分支或构建脚本。单轨
- 主机下限: DuoUpdater 是 arm64、macOS 15.0（`App/project.yml`）；DHS 1.6.0 universal、`LSMinimumSystemVersion` 11.0，无需架构 / OS 门控。1.4.1 只有 x86_64，只能在 Rosetta 下跑，但检测和换包不受影响（channel-verify 实测 1.4.1 → 1.6.0）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.objective-see.DHS` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `objective-see/DylibHijackScanner` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.6.0` → `CFBundleShortVersionString` `1.6.0`、`CFBundleVersion` `1.6.0`（每版两者相同）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`。Python `re` 核对：`v1.6.0`/`v1.5.1`/`v1.5.0` → 1.6.0/1.5.1/1.5.0；`v1.7`、`v2.0.0` 可读；`v1.6.1-beta`、`v2.0.0-rc.1`、无 `v` 的 `1.7.0`、`v2` 不匹配
- install pattern `^DHS_[0-9]+(?:[._][0-9]+)+\.zip$`：资产命名在 1.6.0 改成点分（`DHS_1.6.0.zip`），之前是下划线（`DHS_1_5_1.zip`、`DHS_1_5_0.zip`），两种都接受。核对：上面三个名字都匹配，`DHS_1.6.0.dmg`、`DHS.zip`、`DHS_1.6.0_beta.zip` 不匹配
- channel-verify（2026-10-26，真包 `ditto -x -k` 解压后的 bundle）:
  - 1.5.1: `detected channel → stable`、`winning source GitHub`、`latest 1.6.0`、`status UPDATE → 1.6.0`
  - 1.5.0: `winning source GitHub`、`latest 1.6.0`、`status UPDATE → 1.6.0`
  - 1.4.1: `winning source GitHub`、`latest 1.6.0`、`status UPDATE → 1.6.0`
  - 1.6.0: `winning source GitHub`、`latest 1.6.0`、`status up to date`

## 按架构 / 按 OS 分轨
- 1.5.1 / 1.6.0 一个 universal zip（`lipo -archs` = `x86_64 arm64`）；1.5.0 只有 arm64、1.4.1 只有 x86_64（历史包，不再发）。`LSMinimumSystemVersion` 11.0（1.4.1 是 10.8）

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
- 结构化（2026-10-26，channel-verify `changelog pane`，从 1.5.1 起）: `source structured: 1 entries; newest 1.6.0: 2 items, headings []; first items ["☑️ Support for parsing arm64 binaries", "☑️ Improved detection of SIP-protected di"]`
- v1.6.0 正文就是两行 `☑️` 开头的条目，没有小标题；两条都保留，没有标题可丢。条目前的 `☑️` 是厂商原文
- `/releases/latest` 的 rule 只读一个 release，从 1.5.0 起看也只显示 1.6.0 的说明（引擎设计，非本 rule 问题）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（同 Team `VBG97UB4TA` 的全部已知副本）
- 端到端: 待主会话
- 格式: zip，根目录就是 `DHS.app`；pattern `^DHS_[0-9]+(?:[._][0-9]+)+\.zip$`，kind `.zip`
- 签名: 1.6.0 `TeamIdentifier=VBG97UB4TA`、Notarized Developer ID、hardened runtime（`flags=0x10000(runtime)`），无 entitlements
- 嵌套 / 常驻组件: 无。bundle 里只有 `MacOS/DHS` 和资源文件：没有嵌套 app、framework、XPC、`Library/LoginItems`、`Library/LaunchServices`；源码里没有 `SMAppService` / `SMJobBless` / LaunchAgent
- 校验: v1.6.0 资产的 GitHub digest `sha256:3e72ffa559332afb65a83bfbc3b5973064aac9a424dee9cc8bc57e63f86d728f`，与下载的包一致；v1.5.1 资产没有 digest。Team-ID 路线不需要它
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

### 真机注意事项（从 v1.6.0 源码读出）
- 首次启动写 `~/Library/Preferences/com.objective-see.DHS.plist` 的 `notFirstTime`，并显示一次关于 / 赞助窗口（`AppDelegate.m` `NOT_FIRST_TIME`）
- 偏好「Save output」（默认关）打开时，扫描结果写到 **app 所在目录** 的 `dhsFindings.txt`（`outputDirectory = bundlePath` 的上一级，即通常是 `/Applications/dhsFindings.txt`）。这个文件在 bundle 外，换包不碰它
- 不改网络 / 代理 / DNS / 系统安全设置：源码里没有 `SCPreferences`、PAC、hosts、Network Extension、root CA、`AuthorizationCreate`；它只读文件做扫描
- 「Full system scan」会遍历整个磁盘的可执行文件；`Scanner.m` 的 `PROTECTED_DIRECTORIES`（`~/Library/Mail`、`~/Library/Safari` 等 12 个）是跳过列表，注释写明是为了不弹隐私授权框。列表之外的受保护位置（如 Desktop / Documents / 外接卷）扫描时是否弹框**未验证**。真机一键不需要启动它

## 已知问题
- `objective-see.org/products.json` 里 DHS 停在 1.4.1（bitbucket 链接），与 GitHub / 产品页不一致；DHS 和我们都不读它，只是记一笔
- 资产命名在 1.5.x 和 1.6.0 之间变过（下划线 → 点）；pattern 已两种都收。若厂商再换命名（例如加架构后缀或改 dmg），一键会找不到资产，届时要更新 pattern

## 如何复验
```bash
gh api repos/objective-see/DylibHijackScanner/releases -q '.[]|.tag_name+" "+.prerelease+" "+(.assets[]|.name+" "+(.digest//"nodigest"))'
gh release download v1.6.0 --repo objective-see/DylibHijackScanner --pattern 'DHS_1.6.0.zip'
gh release download v1.5.1 --repo objective-see/DylibHijackScanner --pattern 'DHS_1_5_1.zip'
.claude/skills/coverage-discovery/scripts/check-bundle.sh DHS_1.6.0.zip DHS_1_5_1.zip   # 都是 com.objective-see.DHS / VBG97UB4TA / Notarized
ditto -x -k DHS_1_5_1.zip old && swift run --package-path application-test channel-verify old/DHS.app --expect stable   # → GitHub，UPDATE → 1.6.0
curl -s https://objective-see.org/products.json | grep -A3 'Dynamic Hijack Scanner'   # 官网 JSON 的版本
curl -s https://objective-see.org/products/dhs.html | grep -o 'releases/download/[^"]*'  # 产品页下载链
```

## 建议下一步
1. 厂商发下一个 release 时复查：Team 是否仍是 `VBG97UB4TA`、资产名是否仍匹配 `DHS_<ver>.zip`、tag 仍是 `v<x.y.z>`。
