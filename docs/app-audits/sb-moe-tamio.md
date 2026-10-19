# Tamio

## 基本信息
- App: Tamio — 给 AI agent 用的 SSH 客户端（服务器状态、SFTP、端口转发，带 MCP server `tamio-mcp`），Swift，开源
- Bundle ID: `sb.moe.tamio`
- 仓库: `missuo/tamio`（默认分支 `main`）；官网 https://tamio.sh/
- Team ID: `NCFNX3LJ83`（Developer ID + 公证）
- 观测版本: 0.2.3、0.2.4（`CFBundleVersion` 与短版本相同）；另挂载核对了最早的 release 0.1.2；观测日期: 2026-10-19
- 自更新机制: Sparkle 2.6.4（`SUEnableAutomaticChecks` = true，`SUScheduledCheckInterval` = 86400，EdDSA `SUPublicEDKey`）
- 分发: GitHub Releases（dmg + `appcast.xml`）；第三方 tap cask `owo-network/brew/tamio`（`auto_updates true`）；没有 MAS
- 架构 / 系统: universal（x86_64 + arm64），`LSMinimumSystemVersion` = 14.0

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | —        | —   | —      | —           |

当前生效源: **Sparkle**（bundle 自带 `SUFeedURL`，`feed-discover` 判定 `declared`，不需要 recipe）

Homebrew 一栏是 —：cask 在第三方 tap（未信任的 tap 不会出现在 brew 的列表里），且 `auto_updates true`，
`HomebrewCaskSource` 对它让位，答案仍来自 Sparkle。

## Channel 详情

只有一条轨，settled from source: `.github/workflows/release.yml` on `main`。推 `v*` tag 触发，
`gh release create … --latest`，不带 `--prerelease`；appcast 由 `Workflow/Scripts/appcast.sh` 每次重写，只有一个 item，
没有 `<sparkle:channel>`。到 2026-10-19 共 8 个 release（v0.1.2 – v0.2.4），全部非 prerelease。

覆盖清单：
- **bundle id**: 0.1.2、0.2.3、0.2.4 都是 `sb.moe.tamio`，没有改名；同仓库没有别的 Mac app
- **版本区间**: 最早的 0.1.2 已带同一个 `SUFeedURL` 与 `SUPublicEDKey`（当时 Sparkle 在 `Contents/PlugIns/MacBridge.bundle` 里），
  Team 同为 `NCFNX3LJ83`，所以所有已发布的版本都能检测、都能一键
- **发布轨**: 只有 stable

## 更新检测
- 源: Sparkle，`https://github.com/missuo/tamio/releases/latest/download/appcast.xml`
- 版本: `sparkle:version` = `sparkle:shortVersionString` = tag 去掉 `v`；workflow 在构建前检查 tag 与 `MARKETING_VERSION` 一致
- 实测（2026-10-19，channel-verify，真包 0.2.3 dmg）: `winning source Sparkle`，`latest 0.2.4`，`status UPDATE → 0.2.4`
- 注意: feed 只有最新一版，`release history 1 entries`

## 按架构 / 按 OS 分轨
- universal 单包；appcast 的 item 带 `sparkle:minimumSystemVersion` 14.0，没有上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2.6.4） | 无 | — |
| 证据 | Sparkle.framework | appcast（2026-10-19）没有 `<sparkle:deltas>` | 若以后发，`VendorAppcastDeltas` / `DeltaApplier` 现成 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 默认不会 | 无 | — |
| 证据 | Info.plist 没有 `SUAutomaticallyUpdate`，Sparkle 只弹提示 | 第二轮启动后 60 s 的前后 diff 无 >8 MB 新文件 | 用户在 Sparkle 里点更新后才会下载；那是 Sparkle 自己的安装流程 |

## Changelog
- 来源: recipe，仓库 `CHANGELOG.md`（Keep a Changelog，`## [x.y.z] - date` + `### Added/Changed/Fixed/Removed`）
- 为什么不用 appcast: 唯一那条 item 的 `<description sparkle:format="plain-text">` 只有最新一版（838 字符），没有结构；
  workflow 用 `Workflow/Scripts/release-notes.sh` 从 `CHANGELOG.md` 切出该版本那节，写进 release 正文和更新窗口，所以文件是源头
- 结构化（2026-10-19，channel-verify，真包 0.2.3）:
  `changelog pane  recipe changelog:sb.moe.tamio:-: 9 entries; newest 0.2.4: 2 items, headings ["Added", "Fixed"]`
  ——`[Unreleased]` 被排除，9 条 = 0.1.1 – 0.2.4（0.1.1 有节但没有 release）
- 跟随 channel: —（单轨）
- Recipe 状态: 已有（`Recipes/sb-moe-tamio.swift`）

## 一键安装
- 状态: 支持
- 端到端（2026-10-19，真包 0.2.3 → 0.2.4，`make cli` 后的 duo）:
  - 第一轮（未运行）：`ditto` 0.2.3 进 `/Applications`。`duo check Tamio` → `0.2.3 → 0.2.4 [Sparkle, in-place]`；
    `duo install Tamio --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 31260880`，12 s。
    之后为 0.2.4，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，
    Team `NCFNX3LJ83`，`diff -r --no-dereference` 与厂商 0.2.4 包一致；`duo backups` 无 Tamio 的备份
  - 第二轮（运行中）：重装 0.2.3 并启动。Sparkle 启动即检查（`SULastCheckTime` 在启动后约 2 s），侧栏出现
    「New version available Tamio 0.2.4」，弹出更新提示窗（`SUUpdateAlert`），**不自动下载**（没有 `SUAutomaticallyUpdate`），
    60 s 内 `~/Library/Caches` / `Application Support` / `Containers` 没有新的 >8 MB 文件。
    `duo install --yes --json` → `outcome: installed`，`route: sparkle`，16 s；盘上 0.2.4、inode 变了，校验同第一轮，与厂商包一致；
    旧进程继续运行旧代码。之后 10 s 内盘上一直是 0.2.4，没有被自更新器改回
  - `duo restart Tamio` → `still running — likely a save prompt, left it alone`：首次启动有一个模态的许可协议窗
    （「Welcome to Tamio」，勾选同意后才能 Continue，另有 Quit），挡住了退出。没有替用户同意许可，所以
    **重启这一步在「已同意许可」的副本上没有验证**；进程按 PID 结束后，`duo` 装好的 0.2.4 留在盘上
- 格式: dmg（根目录 `Tamio.app`），EdDSA 签名（`sparkle:edSignature`），Sparkle 路线
- 校验: appcast 的 `sparkle:edSignature` + `length`（31260880，与下载字节数相等）；Team ID 闸
- **读的是**: 人人可手动下载的 GA（GitHub latest release 的 appcast）
- 嵌套: `Sparkle.framework/Updater.app`（Sparkle 自带，非常驻）；`Contents/Helpers/tamio-mcp` 是 agent 按需拉起的
  MCP server，不是常驻 helper
- 系统侧影响: 启动前后 `sfltool dumpbtm` 无 Tamio 条目（没有登录项 / LaunchAgent / 特权 helper）；`~/.claude/skills`
  不变——Tamio 只在用户点设置里的「Install Skill」时才往那里拷 skill（`AgentBridge.installSkill`）
- 阻塞: 无

## 已知问题
- 首次启动的许可协议窗是模态的，用户同意前 Tamio 不响应正常退出，`duo restart` 会如实报「still running」并放手；
  更新本身照样装上，下次启动即是新版

## 建议下一步
1. 无。

## 如何复验

```sh
gh release download v0.2.3 -R missuo/tamio
swift run --package-path application-test feed-discover Tamio-0.2.3.dmg
swift run --package-path application-test channel-verify Tamio-0.2.3.dmg
```

## 历史与实测

- 2026-10-19 加 changelog recipe 前，channel-verify 在真包 0.2.4 上: `changelog pane  raw inline notes, 838 chars, no structure`
- 2026-10-19 用 recipe 的三条正则在 `CHANGELOG.md`（10758 字节）上逐条核对：9 条，每条的条目数与 `###` 分组为
  0.2.4 2（Added, Fixed）· 0.2.3 1 · 0.2.2 2 · 0.2.1 3 · 0.2.0 11 · 0.1.4 5 · 0.1.3 2 · 0.1.2 10 · 0.1.1 11；
  文件没有尖括号、没有链接定义块
