# GitUp

## 基本信息
- App: GitUp — 原生 macOS Git 客户端（`git-up/GitUp`，GPL-3.0）
- Bundle ID: `co.gitup.mac`
- Team ID: `FP44AY6HHW`（Developer ID Application: Lucas Derraugh）；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID
- 观测版本: 1.5.0（tag `v1.5.0`，资产 `GitUp.zip`，4789559 字节，`CFBundleVersion` 1058）；continuous 1.6.0（tag `b1059`，同资产名，4797982 字节，build 1059）；观测于 vmpal「macOS VM 1」（macOS 27.2），2026-11-01
- 自更新机制: 内置 Sparkle 2（`Sparkle.framework`、`SUPublicEDKey`），但 Info.plist **没有 `SUFeedURL`**：feed 地址在代码里拼成 `raw.githubusercontent.com/git-up/GitUp/master/appcasts/<track>/appcast.xml`，track 由构建自己决定（仓库里有 `appcasts/stable` 与 `appcasts/continuous`；stable 的 appcast 只列 1.5.0）。`feed-discover` 因此报 templatedAddress，通用 Sparkle 源读不到
- 分发: GitHub Releases（单个 universal `GitUp.zip`）；Homebrew cask `gitup-app`（1.5.0，`auto_updates true`）；Mac App Store 无（lookup resultCount 0）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —（feed 模板地址，未登记） | —（auto_updates，让位） | — | ✓ 一键 universal zip | — |
| **continuous** | — | — | — | —（tag 是 build 号，stable pattern 不收；副本读成 stable-ahead） | — |

当前生效源: **GitHub**（`duo check` 实测；`duo verify --only co.gitup.mac` 的 rule 与 changelog 都 ✓）

## 覆盖清单
- 真包（都读自 zip）:
  - v1.5.0: `co.gitup.mac`，Team FP44AY6HHW，Notarized，两个版本键 1.5.0 / 1058，`LSMinimumSystemVersion` 12.4，可执行文件 `x86_64 arm64`（universal）
  - b1059（prerelease）: 同 id、同 Team、同架构，版本 1.6.0 / 1059
- 嵌套: 没有 `.app` 子包；没有 LoginItems / LaunchAgent / root helper
- 其他轨: continuous 构建是 GitHub prerelease，tag 写成 build 号（`b1059`、`b1058`…），包内版本是**下一个**版本线（1.6.0）。最新 52 个 release 里 25 个是这种 build tag
- 版本范围: 1.3（`v1.3`）起是 `v` 形式；stable appcast 与 GitHub `/releases/latest` 一致（1.5.0）
- 主机下限: universal 资产；`LSMinimumSystemVersion` 12.4，低于我们的下限

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `co.gitup.mac` | — | 版本纯数字 | `/releases/latest` | ✓ |
| continuous | 同 id | 共享 | 包内版本是下一版（1.6.0），无后缀、无本地标记 | 没有 beta rule：tag 是 build 号，`versionPattern` 读不出 | —（副本读成 stable-ahead，不降级） |

- 为什么不登记 Sparkle feed: 地址带 `<track>` 占位，stable 副本与 continuous 副本请求的是两个不同文件；只登记 stable 那只会在 continuous 副本上把它锁到 stable feed。规则用 GitHub，与厂商 stable appcast 的答案一致（1.5.0）
- 为什么不加 beta rule: `b1059` 这样的 tag 里没有版本号，stable/continuous 的唯一本地区别是包内版本（1.6.0 对 1.5.0），而 1.6.0 在正式发布前只存在于 continuous；按版本比较，stable rule 已经给出安全答案

## 更新检测
- 源: `git-up/GitUp` GitHub Releases，`/releases/latest`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`（`b1059`、`b1058` 不匹配；`v1.3` 匹配）
- `installAssetPattern` `^GitUp\.zip$`；没有任何其他资产
- `duo check`（2026-11-01，vmpal）: 1.4.3（build 1052）→ `update 1.5.0`，route `in-place`；1.5.0 副本 up-to-date
- continuous 1.6.0 副本：`UpdateChecker` 判定 up-to-date（remote 1.5.0 比它旧，不降级）；`GitUpGitHubRuleTests.aContinuousCopyIsNotDowngraded` 钉住

## 按架构 / 按 OS 分轨
- 单个 universal zip（`x86_64 arm64`）；`LSMinimumSystemVersion` 12.4

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 的 binary delta 能力） | stable appcast 里没有 `<sparkle:deltas>` | 不需要 |
| 证据 | 内置 Sparkle 2 | `appcasts/stable/appcast.xml`（2026-11-01）只有一条 item 和一个 zip enclosure | 整包 zip + GitHub digest |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会（Sparkle 下完直接装） | 无 | — |
| 证据 | Sparkle 的默认安装路径；stable appcast 的 enclosure 是 zip | 2026-11-01 两轮 | 没有可拿的 |

## Changelog
- 来源: GitHub release 正文（`GitHubMarkdownParser`，`.gitHubReleases`，`tagPattern` 同 stable）
- 结构化: `## What's Changed` 下先是 "The highlights…" 的要点（含嵌套 bullet），再是 GitHub 的 PR 列表（`* … by @user in https://github.com/…/pull/N`），最后 `**Full Changelog**` 比较链接
- 面板：要点与 PR 条目都保留，`by @user in <url>` 后缀被剥掉，`Full Changelog` 行被丢掉，标题保留
- 跟随 channel: 只有 stable

## 一键安装
- 状态: 支持（universal zip，Team 闸 + GitHub digest）
- 端到端（2026-11-01，vmpal「macOS VM 1」，本分支 `make cli` 的 duo）:
  - 第一轮（不运行）: 1.4.3（build 1052）→ `duo install GitUp --yes` → `outcome installed`，`bytesDownloaded 4789559`；盘上 1.5.0（build 1058），Team FP44AY6HHW，codesign / spctl 通过
  - 第二轮（运行中）: 1.4.3 在跑（pid 85384）→ `duo install GitUp` 装成 1.5.0；`duo restart GitUp` 换 pid（85384 → 85429），版本 1.5.0
  - 终态: 1.5.0，`duo check` 报 up-to-date
- 校验: `sha256:5e1d915ed533334e1691f9c01eb3cb9d2e5f459fb7aa2631b71120ff59ad585b`

## 已知问题
- continuous 副本（1.6.0）只检测到 stable 1.5.0，看不到后续 continuous 构建；这是有意不做 beta rule 的结果（tag 是 build 号），不是源失效
- Sparkle feed 的模板地址没有登记；厂商若把 `SUFeedURL` 写进 Info.plist，Sparkle 源会先应答，这条 rule 仍会作为回退
- b1058 与 v1.5.0 是同一份 zip（digest 相同），即 continuous 后来被提升成正式版；这不影响 stable 规则

## 如何复验
```bash
curl -L -o /tmp/gitup.zip https://github.com/git-up/GitUp/releases/download/v1.5.0/GitUp.zip
unzip -q /tmp/gitup.zip -d /tmp/gitup && codesign -dv --verbose=4 /tmp/gitup/GitUp.app
duo verify --only co.gitup.mac
duo check --all --json | grep gitup
duo install GitUp --yes --json
```
