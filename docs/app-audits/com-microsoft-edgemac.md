# Microsoft Edge

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable/beta/dev 三 channel 已接入；canary 未覆盖（企业 API 不含）**

## 基本信息
- Bundle ID: `com.microsoft.edgemac`（beta/dev 各自独立：`com.microsoft.edgemac.Beta` / `.Dev`）
- 自更新机制: **Microsoft AutoUpdate (MAU)**（后台静默升级）
- 版本方案: 4 段（`137.0.3296.52`），`ProductVersion` = `CFBundleShortVersionString` 一致

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓ +一键      |
| **beta**     | —       | ✗(auto)  | —   | —      | ✓ +一键      |
| **dev**      | —       | ✗(auto)  | —   | —      | ✓ +一键      |
| **canary**   | —       | ✗(auto)  | —   | —      | ✗(无企业API)|

当前生效源: **VendorProbe**（三 channel 统一命中企业端点）

## Channel 详情（Pattern A — 独立安装，各自 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.microsoft.edgemac`       | 独立 | bundle id 无后缀 → stable | 独立 pattern | ✓ |
| beta    | `com.microsoft.edgemac.Beta`  | 独立 | bundle id `.Beta` 后缀    | 独立 pattern | ✓ |
| dev     | `com.microsoft.edgemac.Dev`   | 独立 | bundle id `.Dev` 后缀     | 独立 pattern | ✓ |
| canary  | `com.microsoft.edgemac.Canary`| 独立 | bundle id `.Canary` 后缀  | ✗无端点      | ✗ |

`.Beta` / `.Dev` 后缀大写；`ReleaseChannel.detect` 做小写化比对，可正确识别。Edge Canary 不在 Microsoft 企业 API 返回列表中，无法用同一端点覆盖，留白。

## 更新检测
- 源: VendorProbe（`mode: .responseBody`）
- 端点: `https://edgeupdates.microsoft.com/api/products?view=enterprise`（三 channel 共用同一 JSON）
- 每 channel 用各自锚定的 regex 限定到 `"Product":"Stable|Beta|Dev"` + `"Platform":"MacOS"` 块
- versionPattern（stable）: `(?s)"Product"\s*:\s*"Stable".*?"Platform"\s*:\s*"MacOS".*?"ProductVersion"\s*:\s*"([0-9]+(?:\.[0-9]+){3})"`
- 版本方案: 4 段 `ProductVersion` = 安装包 `CFBundleShortVersionString`，无 `versionIsBuild` 风险

## Changelog
- stable: changelogURL `https://learn.microsoft.com/deployedge/microsoft-edge-relnote-stable-channel` (WebView)
- beta: `https://learn.microsoft.com/deployedge/microsoft-edge-relnote-beta-channel`
- dev: **无 changelogURL**
- 无 ChangelogRecipe（均为 WebView 内嵌官网页）

2026-08-28（issue #107）：Microsoft 把**按 channel 分的**页面从 `…-relnotes-<channel>`
改成 `…-relnote-<channel>`（单数），旧拼法全部 404。stable / beta 按新拼法重指即可。

**注意这不是一次全局重命名**：安全公告页至今仍是 `microsoft-edge-relnotes-security`，
复数。要猜这个 section 里别的页面之前先看这条。

**dev 则是彻底没有了。** `learn.microsoft.com/en-us/deployedge/toc.json`（2026-08-28）
一共 8 条 `relnote*` 路径 —— Beta / Stable / Mobile Beta / Mobile Stable、
对应的三条 `-archive-`、外加上面那条 security —— 没有一条是 Dev；
`…relnote-dev-channel`、`…relnotes-dev-channel`、`…relnote-dev`、
`…relnote-archive-dev-channel` 四种拼法实测都 404；Learn 自己的搜索 API 查
"Edge Dev channel release notes" 返回的是 Beta / Security / release schedule。
Dev 因此留空：把按钮指到 Beta 或 Stable 的页面，等于给 Dev 用户看另一条 train
的改动，比不给更糟（与 Thunderbird Daily 同一判断）。

下游安全：`changelogURL` 为 nil 时 `WorkbenchWindowView` 回落到
`ChangelogCatalog.url(forBundleID:)`，而 `ChangelogCatalog.pages` 没有 Edge 条目，
所以结果是「不显示 notes」，不会显示成另一条 train 的。

## 一键安装
- stable: ✓ `fwlink/?linkid=2093504` → `MicrosoftEdge-<ver>.pkg`，走系统 pkg 安装
- beta/dev: **一键 ✓**（2026-07-03 加）。同一个企业 API JSON 里 `Artifacts[].Location` 就带各 channel 的 `MicrosoftEdge{Beta,Dev}-<ver>.pkg`；install `.bodyPattern` 用与 versionPattern 平行的锚定 `"Product":"Beta|Dev" … "Platform":"MacOS" … "Location":"(…\.pkg)"` 定到该 channel 首个(最新)MacOS release，`\.pkg` 锚跳过同级 `.plist`。pkg 与 stable 同为 `Developer ID Installer: Microsoft Corporation (UBF8T346G9)`、已公证（`spctl` accepted），过签名门。channel gate 仍按各自 bundle id 分发。正则已在实时响应验证：Beta→150.0.4078.50、Dev→151.0.4119.1，pkg 文件名版本与检测版本对齐。

## 建议下一步
1. Edge Canary (`com.microsoft.edgemac.Canary`) 无可靠公开端点 → 暂不支持，保留在本 audit 记录里

## channel-verify 状态
- ✓ **stable/beta/dev 全部已验证 2026-06-04**（官方 `.pkg` 经 `pkgutil --expand-full` 取出 payload `.app` 后跑 channel-verify、未安装）。三者 bundle id `com.microsoft.edgemac[.Beta/.Dev]` detect ✓，VendorProbe 各自应答；**版本方案核对通过**——recipe 版本与 `CFBundleShortVersionString` 同为 4 段营销号，无幽灵 build 风险。verdict 显示 UPDATE 是因为企业版 pkg 落后于 recipe 读的消费版渠道，属正常。
- Canary 无 recipe（范围外、企业 API 也不列），未验证。证据：`application-test/records/com-microsoft-edgemac.md`
