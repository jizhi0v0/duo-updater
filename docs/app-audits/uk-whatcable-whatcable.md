# WhatCable

## 基本信息
- Bundle ID: `uk.whatcable.whatcable`
- Team ID: `M4RUJ7W6MP`（Developer ID Application: Darryl Morley）
- 观测版本: stable `1.4.0`（build `130`）· beta `1.5.0-beta.8`（build `137`）
- 架构: universal（`lipo -archs` → `x86_64 arm64`）
- `LSMinimumSystemVersion`: 14.0
- 自更新机制: **app 自带更新器，直接读 GitHub Releases**（不是 Sparkle——
  仓库 `Package.swift` 里没有 Sparkle 依赖，bundle 里没有 `SUFeedURL`）
- 分发: GitHub Releases（`darrylmorley/whatcable`）+ Homebrew cask `whatcable`
  （`auto_updates: true`）+ 官网 whatcable.uk
- 开源: 是（仓库公开）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | — (`auto_updates`) | — | ✓ | — |
| **beta**   | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub Releases**（两条 rule，各自 `channel` 门控）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable | `uk.whatcable.whatcable` | 共享 | 版本串**无**后缀 | `/releases/latest`（GitHub 不返 prerelease）| ✓ |
| beta | 同上 | 共享 | `CFBundleShortVersionString` = `1.5.0-beta.8` → `ReleaseChannel.detect` 第 4 步 | `usePrereleases: true` + 锚定 `-beta.<N>` 的 versionPattern | ✓ |

**为什么 beta 这条必须有**：beta 包的 marketing 串原样带 `-beta.8`（实测 v1.5.0-beta.8
的 Info.plist），`detect` 判为 `.beta`，stable rule 的 channel 闸就会拒它——没有 beta
rule 的话，一个 beta 安装会**没有任何源**、行永远显示 Failed。这是 `VendorProbeRecipe`
里 Alfred `.beta` 那条注释记录过的同一个形状。

### 未覆盖的那一半：app 内的 beta 开关

WhatCable 设置里有 "Receive beta updates"，落盘在 `uk.whatcable.whatcable` 的
`receiveBetaUpdates` key（源码 `Sources/WhatCable/App/AppSettings.swift`）。它的注释
自己写着：关掉时"the updater keeps hitting `releases/latest`, which GitHub never
returns a pre-release from"。

我们**没有读这个 key**。缺口是单向的、已知的：一个跑 **stable** 构建但把开关打开的用户，
厂商自己的更新器会给他 beta，我们只给 stable。反方向——把 beta 推给没开开关的人——不可能
发生，因为 beta rule 只对**已经在跑 beta** 的副本生效。补上要写一个 `ChannelBinding`，
记在 `CHANNEL_COVERAGE_TODO.md` §2，不在本次范围内。

## 更新检测
- stable: `/releases/latest`，tag `v1.4.0`，pattern `^v([0-9]+(?:\.[0-9]+)+)$`
- beta: releases 列表，tag `v1.5.0-beta.8`，pattern
  `^v([0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+)$` —— **后缀必须保留**，截成 `1.5.0` 会让每个
  beta 都读成比自己新
- `listPageSize: 5`（实测 2026-09-06，最新 100 个 release：prerelease 首命中 index 0，
  两个 prerelease 之间最长非 prerelease 连续段 = 1；gzip 后 per_page=5 是 5.9 KB，
  默认的 20 是 23.8 KB）
- 版本方案: tag 去 `v` 即 marketing 串，与 bundle 同构。build（`CFBundleVersion`）
  单调递增（127 → 130 → 137）但 GitHub 不发布它，比较只用 marketing。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 非 Sparkle，无 delta 概念 | 无 | 不能 |
| 证据 | 仓库无 Sparkle 依赖 | 每个 release 只有 `WhatCable.zip` + `whatcable-cli-<ver>.zip` | — |

## Changelog
- 来源: **GitHub release body**，`GitHubMarkdownParser` 原生渲染，**不需要
  ChangelogRecipe**。
- 质量: v1.4.0 的 body 是几百字的分区 Markdown（`## Connected devices` /
  `## Speed verdicts`…），每条 bullet 还带 issue 号和致谢。beta 也有正文
  （beta.7/beta.8 只有标题、没有分区，属于正常的短说明）。

## 一键安装
- 状态: **支持**（两个 channel 都支持）
- 格式: zip —— 资产名两条轨**完全相同**：`WhatCable.zip`
- 资产 pattern: `^WhatCable\.zip$`。同 release 里的 `whatcable-cli-<ver>.zip` 是独立的
  CLI 产物（app bundle 内部另有一份 `Contents/Helpers/whatcable`，Homebrew cask 就是
  symlink 那份），锚定后不会串。
- 包验（2026-09-06，真实下载解包）:
  - v1.4.0 → `WhatCable.app` / `uk.whatcable.whatcable` / `1.4.0` / build 130 /
    universal / `Developer ID Application: Darryl Morley (M4RUJ7W6MP)` /
    `spctl` = `Notarized Developer ID`
  - v1.5.0-beta.8 → 同 bundle id、同 Team、`1.5.0-beta.8` / build 137
  - 两条轨 Team 相同 → 签名闸拦不住跨轨，靠 channel 闸 + channel proof
- Channel proof: `.artifact(#"/download/v[0-9.]+-beta\."#)`。两条轨文件名一模一样，
  **tag 路径段是唯一的判据**（`…/download/v1.5.0-beta.8/WhatCable.zip` vs
  `…/download/v1.4.0/WhatCable.zip`）。

## 已知问题
- **beta 不会被"毕业版"接走**：跑 `1.5.0-beta.8` 的副本不会被提示装 `1.5.0` 正式版，
  要等 `1.6.0-beta.1`。这是刻意的取舍：放宽 pattern 让 stable tag 也匹配，就会让上面那条
  `.artifact` proof 在一次**合法**解析上误报（两条轨在 artifact 上除了 tag 段没有任何
  区别）。实际等待窗口不长——2026-08-20 到 08-31 的 11 天里发了 8 个 beta。
- Homebrew cask 存在但 `auto_updates: true`，按本仓库既定策略不作为源。

## 如何复验
```
# GET https://api.github.com/repos/darrylmorley/whatcable/releases/latest → v1.4.0
# GET .../releases?per_page=5 → 首条 v1.5.0-beta.8（prerelease）
# 解包 WhatCable.zip → uk.whatcable.whatcable / Team M4RUJ7W6MP / notarized
duo verify --only whatcable
```

## 建议下一步
- `ChannelBinding` 读 `receiveBetaUpdates`，覆盖"stable 构建 + 开了开关"这一格。
