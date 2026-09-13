# WorkBuddy AI（国际站）

审计 2026-08-27。WorkBuddy 是**两个 app**，不是一个 app 的两个 channel：本文档是国际站
`com.workbuddy.workbuddy-ai`；国内站 `com.workbuddy.workbuddy` 见
[com-workbuddy-workbuddy.md](com-workbuddy-workbuddy.md)。两站共用的部分——更新端点、三个陷阱、
changelog 页面标记、一键安装的闸与 host 钉死、验证方法——只写在国内站那份里，这里不重复。

## 基本信息

| | 国际站 |
|---|---|
| Bundle ID | `com.workbuddy.workbuddy-ai` |
| App 名 | WorkBuddy AI.app |
| URL scheme | `workbuddy-ai` |
| 官网 | https://www.workbuddy.ai |
| 观测版本 | 5.4.2 |
| Team ID | `FN2V63AD2J` — Tencent Technology (Shanghai) Company Limited |
| 自更新机制 | 自研（Electron + `electron.net.fetch`，非 electron-updater，无 `app-update.yml`，无 Sparkle） |

国际版另有 `TuringShield.bundle`（腾讯安全 SDK），国内版没有；这属于两站构建差异，
与更新检测无关。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

| | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| **stable（国际站）** | — | — | — | — | ✓ 一键 |

当前生效源：**VendorProbe**（前四条源全部不适用：无 `SUFeedURL`、无 cask、非 MAS、
无公开 GitHub 发布）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---|---|---|---|---|---|
| stable | `com.workbuddy.workbuddy-ai` | 独立 | — | — | ✓ |

没有非 stable channel，理由（两站相同）见国内站文档的「Channel 详情」。

## Changelog

| | URL | 状态 |
|---|---|---|
| 国际站 | https://www.workbuddy.ai/docs/workbuddy/Changelog | 200，但**落后于自己的轨道**（写作时最新条目 5.2.7，而发布版是 5.4.2） |

解析结果（2026-08-27 实测）：国际站 2 条（最新 5.2.7）。这个 2 是**厂商页面本身**如此，
不是 recipe 坏了 —— 同一条正则在 CN 页跑出 58 条。`duo verify` 会为此报一条 ⚠（最新条目
5.2.7 落后于探测到的 5.4.2），这条警告是真的，且厂商补上笔记后会自动消失。

## 一键安装

- 状态：**支持**（检测 + 一键）
- install 正则钉死的下载 host：`codebuddy-1328495429.cos.accelerate.myqcloud.com`
  （为什么要钉、钉错会怎样，见国内站文档「一键安装」）

## 已知问题

- 国际站 changelog 页滞后于其发布轨道，vendor 侧问题，我们这边无解。
