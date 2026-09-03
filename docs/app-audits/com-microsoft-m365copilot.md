# Microsoft 365 Copilot

## 基本信息
- Bundle ID: `com.microsoft.m365copilot`
- Team: Microsoft（pkg 为 Developer ID Installer，公证）
- 观测版本: short `1.2608` / build `1.2608.0301`
- 自更新机制: 随 pkg 安装 `Microsoft AutoUpdate`（MAU，`com.microsoft.autoupdate2`），
  与 Office 家族同款自更新基建
- 分发: Microsoft 官方 CDN（fwlink → aka.ms → `res.cdn.office.net`）+ Homebrew
  cask `microsoft-365-copilot`（`auto_updates: true`）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | — | ✓ |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（`redirectFilename`，
与 Office 家族 Word/PowerPoint 同一模式）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.microsoft.m365copilot` | 单一渠道 | — | — | ✓ |

单渠道。

## 更新检测
- 源: `https://aka.ms/M365CopilotForMac`（301 → 版本化 pkg 的 CDN URL，单跳）。
  **两跳链的坑已写进 recipe**：vendor 的 canonical 入口 `fwlink/?linkid=2325438`
  是 302 → `aka.ms/M365CopilotForMac` → 301 → CDN；`followRedirects:false` 只读
  第一跳 Location（也就是那个裸 aka.ms 别名），所以版本探针直接指 aka.ms。
- 版本方案: pkg 文件名 `…_1.2608.0301_Installer.pkg` 携带的是 **build**（展开
  真包核实 `CFBundleVersion` = `1.2608.0301` 逐字相等，short 是 `1.2608`）→
  `versionIsBuild: true` 走 build-vs-build，不需要 Office 家族那种段裁剪。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | MAU 支持 | 没查 | 不能 |
| 证据 | — | — | 我们不走 MAU 差分 |

## Changelog
- 来源: **没有可用的**。`learn.microsoft.com/en-us/microsoft-365-copilot/release-notes`
  存在（HTTP 200），但它是**整个 Microsoft 365 Copilot 服务**的功能公告页，按
  **日期 × 产品**组织（Excel / Word / Outlook / PowerPoint / OneNote / Viva
  Insights / SharePoint …），**不是这个 Mac app 的构建说明**。
- 判据（2026-09-03 抓页实测）: 我们探针从 pkg 文件名读到的 build `1.2608` 在整页出现
  **0 次**。所以按版本绑的 recipe 永远匹配不上；按日期绑的会把 Excel、Outlook 的功能
  条目显示在 Copilot app 这一行下面。
- Recipe 状态: **有意不接**——UI 回落到嵌入式网页，那至少如实呈现为「厂商的页面」。

## 一键安装
- 状态: **支持**（`kind: .pkg`，经系统安装器）
- **读的是**: vendor canonical fwlink（人人可手动下载的 GA）
- **kind: .pkg 是硬约束**：真包展开核实（2026-08-30），pkg 除 app 本体外还装
  `Microsoft AutoUpdate`（`Office16_all_autoupdate`）作为兄弟组件——bundle-only
  拆包会把新 app 留在旧 MAU 旁边。
- 包验（2026-08-30 展开）: `Microsoft 365 Copilot.app` → `com.microsoft.m365copilot`
  / short `1.2608` / build `1.2608.0301`；pkg `signed by a developer certificate
  issued by Apple for distribution`，notarized，trusted timestamp 2026-08-03。

## 已知问题
- aka.ms 别名若被 vendor 退役，探针会失效（与任何 vendor 端点同类风险）；
  安装仍走 fwlink，届时两条链路各自有迹可查。

## 如何复验
```
# GET https://aka.ms/M365CopilotForMac → 301 → …/Microsoft_365_Copilot_universal_1.2608.0301_Installer.pkg
# pkgutil --expand-full 展开 → com.microsoft.m365copilot / 1.2608 / 1.2608.0301
# channel-verify --check com.microsoft.m365copilot → winning=Vendor, up to date
```

## 建议下一步
- changelog：找 Microsoft 官方的 M365 Copilot app release notes 页并接上。
