# TypeWhisper

## 基本信息
- Bundle ID: `com.typewhisper.mac`
- Team ID: `2D8ALY3LCL`
- 观测版本: `1.6.0` (build `1091`)
- 自更新机制: **Sparkle**（`SUFeedURL = https://typewhisper.github.io/typewhisper-mac/appcast.xml`）
- 分发: GitHub Releases (`TypeWhisper/typewhisper-mac`) / Homebrew cask `typewhisper`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | — (`auto_updates`) | — | — | — |
| **release-candidate** | ✓ | — | — | — | — |
| **daily**  | ✓       | —        | —   | —     | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（泛化 `SparkleAppcastSource`，
零 recipe；三条轨都靠 feed 的 `<sparkle:channel>` 标记分轨）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.typewhisper.mac` | 共享 | — | default（无标记） | ✓ |
| release-candidate | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>release-candidate` | ✓ |
| daily   | `com.typewhisper.mac` | 共享 | 装机 build 命中 feed 条目 | `<sparkle:channel>daily` | ✓ |

共享 bundle id。appcast 3 条（观测 2026-08-30）：default = `1.6.0/1091`（stable），
`release-candidate` = `1.6.0-rc2/1083`，`daily` = `1.7.0-daily.20260830/1161`。
三轨互不串：`usableItems` 只允许装机 build 命中的那条 channel。

配套的一个 GitHub 陷阱（写进 audit 免得下一个人踩）：该 repo 的**非 prerelease
release 全是 plugin 包**（`plugin-whisperkit-v1.2.0` 等，资产只有插件 zip），app
本体走 prerelease 的 daily tag。如果有人给这个 bundle 加 GitHub rule，
`/releases/latest` 会指到最新的 plugin release——GitHub 源不是这个 app 的版本面，
Sparkle feed 才是。

## 更新检测
- 源: 泛化 Sparkle。
- 版本方案: short 与 build 双轨；比较落在 build，显示走 short。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: Sparkle inline（feed `<description>`）
- 跟随 channel: 是（按装机轨道）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（Sparkle 原生路径，各轨 feed enclosure）
- 格式: `TypeWhisper-v{ver}.zip`
- **读的是**: 人人可手动下载的 GA（feed 公开条目）
- 包验（2026-08-30，v1.6.0 解包）: `com.typewhisper.mac` / `1.6.0` / build
  `1091`，Team `2D8ALY3LCL`，notarized

## 已知问题
- 无。

## 如何复验
```
# GET https://typewhisper.github.io/typewhisper-mac/appcast.xml
#   → 3 条：default=1.6.0，rc=1.6.0-rc2，daily=1.7.0-daily.20260830
# 解包 TypeWhisper-v1.6.0.zip → com.typewhisper.mac / 1.6.0 / 1091
# channel-verify --check com.typewhisper.mac → winning=Sparkle, up to date
```

## 建议下一步
无。三轨检测 + 一键 + changelog 均由泛化 Sparkle 源覆盖，零代码，审计文档即交付物。
