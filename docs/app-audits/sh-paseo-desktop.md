# Paseo

2026-11-15 路线更新：当前一键安装使用已在 VM 验证的 ZIP；下文原有 DMG 包与端到端记录保留为历史证据。Duo 的 blockmap 优化以所选 ZIP 的发布方整包校验值为前提，缺少校验值时仍全量下载。详见文末「Electron ZIP 迁移」。

## 基本信息
- Bundle ID: `sh.paseo.desktop`
- Team ID: `99ZMJMKU9Y` (Mohamed Boudra Ziani)
- 观测版本: `0.6.1`（short == build）
- 自更新机制: electron-updater（`app-update.yml`: provider github, channel latest）
- 分发: GitHub Releases (`getpaseo/paseo`) / Homebrew cask `paseo`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `sh.paseo.desktop` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |
| beta    | （同 bundle，beta 构建） | — | — | 未接入 | ○ |

单渠道（本接入只做 stable）。**beta 轨道存在**：repo 把 beta 发成 prerelease
release（`v0.7.0-beta.2`，资产 `beta-mac.yml` + dmg）——锚定的 stable pattern
拒读 `-beta` 后缀，且 `/releases/latest` 按 GitHub 定义排除 prerelease，双保险
不会把 beta 推给 stable 装机。beta 轨道本身未接入（构建 channel 不同，需要
装机 build 命中 beta feed 才能安全跟随，属 ChannelBinding 范畴）。

## 更新检测
- 源: `getpaseo/paseo` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.6.1` → `0.6.1` == 包的 short 与 build。同构，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | electron-updater 支持 | 无 | 不能 |
| 证据 | — | release 资产无 delta（观测 2026-08-30） | — |

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Paseo-{v}-arm64.dmg`（`.deb`/`AppImage` 是 Linux 兄弟）
- Pattern: `^Paseo-[0-9.]+-arm64\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-08-30，v0.6.1 挂载）: `sh.paseo.desktop` / `0.6.1`，Team
  `99ZMJMKU9Y`，`spctl accepted / Notarized Developer ID`；自包含 bundle
  （无 `Contents/Library`，daemon 由 app 自行管理）→ `.dmg` 正确

## 已知问题
- beta 轨道未接入（见上）。vendor 的 beta 是 prerelease 轨，不与 stable 冲突。

## 如何复验
```
# GET https://api.github.com/repos/getpaseo/paseo/releases/latest → v0.6.1
# 挂载 Paseo-0.6.1-arm64.dmg → sh.paseo.desktop / 0.6.1
# channel-verify --check sh.paseo.desktop → winning=GitHub, up to date
```

## 建议下一步
- beta 轨道：若要接，需先核实 beta 构建的装机形态与 channel 选择机制。

## 历史与实测

### Electron ZIP 迁移（2026-11-15）

安装容器改为 `Paseo-0.15.4-arm64.zip`。在 macOS 27.2 Apple Silicon VM 中，从本次对应 DMG 准备的独立副本，经生产 `VendorInstaller.apply` 校验与替换为同版本 ZIP，再通过 LaunchServices 启动指定路径，确认 PID 存活后退出测试实例。版本、bundle ID、Team、arm64 与代码签名检查均通过。本次对应 DMG/ZIP 的 arm64 主程序 CDHash 与 app.asar 相同。既有旧 bundle ID、版本门控、edition 与仅检测渠道的范围沿用原规则；没有新增跨组安装。
整包发布校验值存在时才会尝试 blockmap；旧 GitHub 发布缺少 digest 时仍走全量 ZIP 与原有签名检查。

本次包、逐项结果与限制见 [集中验证记录](../../verify/electron-blockmap-20261115/README.md)。这些是一次验证的结果，不代表应用所有版本或功能均已测试。

## 夜扫覆盖

2026-11-15 ZIP 容器验收。

Vendor/GitHub registry 由 `duo verify-install` 自动枚举，本次没有向通用 feed inventory 重复添加条目。实际下载并读取以下精确 recipe ID：

- `github:getpaseo/paseo:stable`：0.15.4，ZIP，179,357,523 bytes，身份匹配、读取检查通过。

命令、35 个目标的集合核对与原始结果见[集中夜扫记录](../../verify/electron-blockmap-20261115/README.md)。旧副本/edition 的闸与原有缺口保持原文范围，本次只改变上述安装容器。
