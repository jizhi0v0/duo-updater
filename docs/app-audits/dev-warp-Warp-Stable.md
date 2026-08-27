# Warp

> 审计日期 2026-06-04 · 模式 REPORT（已接入）· 结论：**stable 完整（检测+一键）；preview/dev 已检测；beta/canary 轨道已废弃，无配方**

## 基本信息
- Bundle ID: `dev.warp.Warp-Stable`（preview/dev 各自独立：`dev.warp.Warp-Preview` / `dev.warp.Warp-Dev`）
- 自更新机制: Warp 自研更新器

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗(auto)  | —   | —      | ✓           |
| **preview**  | —       | —        | —   | —      | ✓           |
| **dev**      | —       | —        | —   | —      | ✓           |
| **beta**     | —       | —        | —   | —      | ✗(轨道废弃) |
| **canary**   | —       | —        | —   | —      | ✗(轨道废弃) |

当前生效源: **VendorProbe**（stable 走 `app.warp.dev/download` 页面；preview/dev 走 `releases.warp.dev/channel_versions.json`）

## Channel 详情（Pattern A — 独立 bundle id）

| Channel | Bundle ID | 独立/共享 | 检测信号 | 状态 |
|---------|-----------|----------|---------|------|
| stable  | `dev.warp.Warp-Stable`  | 独立 | bundle id `-Stable` 后缀  | ✓ 检测+一键 |
| preview | `dev.warp.Warp-Preview` | 独立 | bundle id `-Preview` 后缀 | ✓ 仅检测 |
| dev     | `dev.warp.Warp-Dev`     | 独立 | bundle id `-Dev` 后缀     | ✓ 仅检测 |
| beta    | `dev.warp.Warp-Beta`    | 独立 | — | ✗ 轨道冻结于 2024-12，无配方 |
| canary  | `dev.warp.Warp-Canary`  | 独立 | — | ✗ 轨道冻结于 2022-09，无配方 |

Beta/Canary 轨道仍在 `channel_versions.json` 中有键，但版本停更已数月/数年。不加配方，避免永久报"需要更新"（那个"最新"是过时构建）。

## 更新检测
- stable: VendorProbe `app.warp.dev/download?package=dmg` → GET，**不跟随**（302 直接到 320 MB dmg）；version 从小的重定向 body 中提取 `releases.warp.dev/stable/v<ver>.stable`
- preview/dev: VendorProbe `releases.warp.dev/channel_versions.json` → `"version":"v<ver>.<channel>_NN"` 各自 pattern

## Changelog
- stable: ChangelogRecipe ✓（`docs.warp.dev/changelog/2026/`，Starlight 渲染页，年份路径）
- preview/dev: 无独立 changelogURL（WebView 均指向同一 `docs.warp.dev/changelog` 页）
- 缺口: preview 和 dev 的 `changelogURL` 与 stable 共用；VendorProbe 的 changelogURL 字段已设，不是 ChangelogRecipe

## 一键安装
- stable: ✓ dmg（`releases.warp.dev/stable/v<ver>/Warp.dmg`），Team 2BBY89MBSN
- preview/dev: 仅检测

## channel-verify 状态
- ✓ **三 channel 全部已验证 2026-06-04**。stable `dev.warp.Warp-Stable`（本机 `--scan`）/ preview `dev.warp.Warp-Preview` / dev `dev.warp.Warp-Dev`（官方 dmg 只读挂载）各自 VendorProbe 应答=对应版本，无幽灵更新；channel 由连字符后缀直读。beta/canary 死轨已弃、不给 recipe。证据：`application-test/records/dev-warp-Warp-Stable.md`
