# Homebrew（BrewUI）

Homebrew 官方 GUI，随 Homebrew 7.0.0（2026-09-13）正式发布。仓库 `Homebrew/BrewUI`，
cask `homebrew-app`，装出来的 bundle 名是 `Homebrew.app`。

## 基本信息
- Bundle ID: `sh.brew.app`
- Team ID: `927JGANW46`（`Developer ID Application: Patrick Linnane`，`spctl` 判定
  `Notarized Developer ID`；对 0.4.0 bundle 取证，2026-09-13）
- 观测版本: `0.4.0`（`CFBundleVersion` 1062）
- 架构: universal（`x86_64 arm64`）
- 系统要求: `LSMinimumSystemVersion` 26.2；cask 写的是 `depends_on macos: :tahoe`（>= 26）
- 自更新机制: **无**。没有 `SUFeedURL`、没有 Sparkle。它的「升级自己」是替用户跑
  `brew upgrade --cask homebrew-app`（源码 `SelfUpgradeIdentity.swift`，
  `displayCommand` 就是这句），并且把自己排除在批量升级之外。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓        | —   | ○      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew**。
cask 没有 `auto_updates`，所以 `HomebrewCaskSource` 会应答。GitHub Releases 带着
同一个 zip（cask 就是从那里下的），但没有 GitHub 规则，标 ○。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `sh.brew.app` | 单一渠道 | — | — | ✓ |

只有一条轨。GitHub 上 9 个 release 里只有最早的 v0.1.0 / v0.1.1 标了 prerelease，
v0.1.2 起全部是正式版（2026-09-13 实测）；cask 只有一个 token。

## 更新检测
- 源: `HomebrewCaskSource`（零改动，无需 recipe）
- 版本方案: **与 Homebrew 本体无关**。GUI 自己的版本号（0.x）独立发布，2026-09-05
  至 09-13 之间 GUI 发了 v0.2.2 → v0.3.0 → v0.3.1 → v0.4.0，brew 只发了 6.0.22 → 7.0.0。
  **`brew update` 不会升级它**——那只更新 brew 本体和元数据；GUI 要 `brew upgrade --cask`
  或 DuoUpdater 的一键。
- cask `version` == tag 去 `v` == `CFBundleShortVersionString`（`0.4.0`），无错位。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | 非 Sparkle，无自更新器 | release 资产只有 `.zip` / `.pkg` / `.dSYMs.zip`（v0.3.1，2026-09-13） | 走 brew，brew 自己下载 |

## Changelog
- 来源: `ChangelogRecipe`（`.gitHubReleases`），
  `https://api.github.com/repos/Homebrew/BrewUI/releases?per_page=40`
- 跟随 channel: 否（只有一条轨）
- Recipe 状态: **已接**（2026-09-13）

`HomebrewCaskSource` 不带任何 notes，唯一的链接是 `formulae.brew.sh/cask/homebrew-app`
列表页。正文是 GitHub 自动生成的「What's Changed」列表，`GitHubMarkdownParser` 已经
剥掉 `by @user in <PR>` 后缀（`@dependabot[bot]` 这种带方括号的用户名也匹配 `@\S+`）、
跳过 New Contributors / Full Changelog。早期两个 prerelease 的正文是 CRLF，被
`.gitHubReleases` 的 stable-only 过滤掉。条目里会包含 dependabot 和 BrewTestBot 的
维护类 PR 标题——那是厂商自己的发布说明，没有过滤。

## 一键安装
- 状态: **支持**（`[homebrew]` 路由，`brew install --cask --force homebrew-app`）
- **运行中升级实测（2026-09-13，0.3.1 → 0.4.0）**：DuoUpdater 和 brew 都不因 app
  在运行而拒绝或退出它；brew 换掉了 `Contents/MacOS/Homebrew`（inode 变化）但保留了
  `Homebrew.app` 目录本身的 inode；旧进程继续跑旧的可执行文件、五个页面都能用；
  `duo install` 结尾报 "Still running the old code"，菜单栏行给 Relaunch，点了之后
  只剩一个进程、映射新的可执行文件、`duo check` 答 `0.4.0 (latest 0.4.0)`。
  没测的：BrewUI 自己用的 `brew upgrade --cask` 那条路。

## 已知问题
- 无。

## 如何复验
```
# gh api 'repos/Homebrew/BrewUI/releases?per_page=40' → tag vX.Y.Z，最新 == cask version
# brew info --cask --json=v2 homebrew-app → tap homebrew/cask，auto_updates 为空
# codesign -dvv Homebrew.app → sh.brew.app / 927JGANW46
# duo verify --only sh.brew.app → changelog 条目数 ≥ 1
```

## 建议下一步
- 无。
