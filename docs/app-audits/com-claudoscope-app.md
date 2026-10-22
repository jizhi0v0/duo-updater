# Claudoscope

## 基本信息
- App: Claudoscope，菜单栏常驻（`LSUIElement=true`）的 Claude Code 本地数据查看器：读 `~/.claude` 下的会话记录、配置、hooks、skills 等；开源（`cordwainersmith/Claudoscope`）
- Bundle ID: `com.claudoscope.app`
- 仓库: `cordwainersmith/Claudoscope`
- Team ID: `DN8M2CQ4D2`；`codesign --verify --deep --strict` 通过；spctl: Notarized Developer ID（读了 v0.3.0、v0.3.1、v0.3.2、v0.3.3、v0.3.6、v0.3.8、v0.3.9、v1.3.0、v1.4.0 的真包，Team 全部相同）
- 观测版本: 1.4.0（tag `v1.4.0`，`CFBundleVersion` 202610081625）；上一版 1.3.0（202610042056）；观测日期: 2026-10-22
- 自更新机制: 自研，从 v0.3.3 起（源码 `Claudoscope/Services/UpdateService.swift`，提交 `7da9e0f`「Add self-updating via GitHub Releases API (v0.3.3)」）。读本仓库 `/releases/latest`，有新版就弹「Update Available」窗口；用户点「Download and Install」才下载、换包、重启。不暂存，不和我们抢（详见「已停放整包」）
- 分发: GitHub Releases（每版一个 `Claudoscope.dmg`）；Homebrew cask `claudoscope`（`auto_updates true`，url 就是同一个 GitHub 资产，`depends_on arch: arm64`、`macos >= 14`）；官网下载按钮走 `dl.claudoscope.com` 计数后重定向到 GitHub（v1.4.0 release 正文）。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（cask `auto_updates`，交给 app 自己 / 本规则） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify 实测，见下）。真包没有 `SUFeedURL`。

## 覆盖清单
- 各版本的 bundle id / Team（读真包）: v0.3.0 → v1.4.0 都是 `com.claudoscope.app`、Team `DN8M2CQ4D2`，没有改名前的旧 id。
- 其他轨: 29 个 release 全部 `prerelease=false`，没有 beta / nightly tag，仓库也没有别的产品发在这里。
- 版本范围: 版本号和 tag 对不上的有三版（见「更新检测」），都低于最新 tag，照常被推最新版。
- 主机下限: DuoUpdater 只跑 arm64、macOS 15+（`App/project.yml`）；Claudoscope `LSMinimumSystemVersion` 14.0，v1.x 是 universal、v0.x 是 arm64，都不需要门控。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.claudoscope.app` | — | 默认 | `/releases/latest` | ✓ |

## 更新检测
- 源: `cordwainersmith/Claudoscope` GitHub Releases，`/releases/latest`（2026-10-22 指向 `v1.4.0`）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读得出全部 29 个 tag，也读得出 `v2.0.0`、`v1.5`；`v1.5.0-rc.1`、`v1.5.0-beta` 不匹配
- install pattern `^Claudoscope\.dmg$`（29 个 release 的唯一资产都叫这个名字）
- 版本方案: tag `vX.Y.Z` = `CFBundleShortVersionString`；`CFBundleVersion` 从 v0.3.8 起是构建时间戳，更早是 `1`，不参与比较
- **版本号和 tag 对不上的旧版**（读真包，不是读源码）:

  | tag | 包里的 `CFBundleShortVersionString` | channel-verify |
  |---|---|---|
  | v0.3.0 | 1.0.0 | `UPDATE → 1.4.0` |
  | v0.3.1 | 1.0.0 | `UPDATE → 1.4.0` |
  | v0.3.2 | 0.3.2（源码 tag 里的 Info.plist 写 1.0.0，真包是 0.3.2） | `UPDATE → 1.4.0` |
  | v0.3.6 | 0.3.5 | `UPDATE → 1.4.0` |

  结论：这些副本被当成 1.0.0 / 0.3.5，比最新的 1.4.0 低，所以**不会被误判成已是新版，也不会误报**（它们确实要更新）。唯一的偏差是 changelog 面板只看最新一条，和别的 app 一样，不受影响。厂商 tag 回不到 1.0.0 以下，这个问题不会再出现。v0.3.0–v0.3.2 没有自更新器（可执行文件里没有 `releases/latest` 字符串，`UpdateService` 从 v0.3.3 才有），这些副本只能靠我们或手动更新。

## 按架构 / 按 OS 分轨
- v1.x 是 universal（`x86_64 arm64`），v0.3.x 是 arm64；每版一个 dmg，不分架构资产；`LSMinimumSystemVersion` 14.0；release 不声明 OS 上限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `UpdateService` 只下整个 dmg | 每个 release 只有一个 `Claudoscope.dmg`（2026-10-22 `gh api …/releases`） | — |

## 已停放整包（自更新器下完、还没装的那份）
> 第 2 栏应来自 Phase 4 第二轮的前后 diff；这一轮还没跑，下面只有源码结论。

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（真机第二轮补） | 不需要 |
| 证据 | v1.4.0 `UpdateService.swift`：启动 5 s 后（距上次检查超过 1 h）和每 24 h 只做检查；`downloadAndInstall()` 只由「Update Available」窗口和设置页的按钮调用。点了之后下到 `$TMPDIR/ClaudoscopeUpdate-<UUID>/Claudoscope.dmg`，挂载、校验 Team `DN8M2CQ4D2`，把当前 bundle 改名为同目录的 `Claudoscope.app.bak`，拷入新版，然后退出重开；失败时删临时目录 | — | — |

- `.bak`: 厂商更新器换包后留下 `Claudoscope.app.bak`（与 app 同目录），新版成功启动两次后删掉（`ClaudoscopeApp.swift` 的 `UpdateTriggerView`）。扩展名不是 `.app`，`AppScanner` 不把它当成副本（`guard entry.pathExtension == "app"`，读代码，没在真机上看）。
- 两条更新路线互不干扰：厂商的只在用户点击时动手，我们换完包后它下次检查看到已是最新就不弹。

## Changelog
- 来源: GitHub Release 正文，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 1.3.0 起）: `source structured: 1 entries; newest 1.4.0: 17 items, headings ["New Features", "Changed", "Fixed"]; first items ["**Trace tab.** A session viewer tab that", "**Replay.** A play button in the Trace t", "**Share card.** Export the trace as a 12"]`
- 三个 `###` 标题都保留，没有被压平；17 = 8 + 2 + 7，正好是三节的列表项数。
- **第一个标题前的两段说明不显示**：本版的概述和「Requires a one-time full reparse on first launch (parser version 14).」都在 `### New Features` 之前，`GitHubMarkdownParser.sectionProse` 按设计不收第一个标题前的文字（见它的文档注释）。这是通用解析器的取舍，规则没改。
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（规则已接；真机端到端未跑）
- 端到端: **未跑**。本次审计没有动真机，交给主会话
- 格式: dmg（UDZO，`hdiutil imageinfo` 实测），根目录 `Claudoscope.app` + `Applications` 软链
- 嵌套 / 常驻组件: 没有 LoginItems / Helpers / XPC / LaunchAgent。`Contents/MacOS/claudoscope-mcp`（同 Team 签名）是 MCP stdio shim，只在用户在设置里开了 MCP、Claude Code 拉起它时运行，换包后旧 shim 要等那个 Claude Code 会话重启才换成新代码（读源码，未实测）
- 签名: 上一版 1.3.0 和最新 1.4.0 都是 Team `DN8M2CQ4D2`、Notarized Developer ID；更早各版也一样，没换过 Team
- 校验: GitHub 资产 `digest`。v1.4.0 `sha256:59b1712cc95f27403a7c85b5f286e302b1fe9139833c5abd21a3dde0afa04ebe`、v1.3.0 `sha256:1086d4546a85e4c28b2a987d5c21858a48a7d15e3fd085a19a12254ba2d71799`，下载的包 `shasum -a 256` 相同，大小 28697969 / 27648615 等于资产大小
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，厂商自己的更新器读的也是它）
- 阻塞: 无

### 真机前要知道的副作用（来源：v1.4.0 源码，未在真机上观察）
- **首次启动**: 没看过引导（`hasSeenOnboarding` 为假）就弹引导窗口，之后弹一次「开机启动」询问（NSAlert，会临时把 activation policy 切成 `.regular`）；选是就 `SMAppService.mainApp.register()` 注册成登录项。
- **启动 5 s 后**（距上次检查超过 1 h）请求 GitHub `/releases/latest`，有新版就弹「Update Available」窗口；不点就不下载。
- **`~/.claude`**: 默认设置下启动**不写** `~/.claude`。启动时会做的只有：删除 `~/.claude/.claudoscope-events/` 下的 `*.json`（自己的事件队列；目录不存在就什么都不做）。要写都得用户先打开开关：
  - 通知（`sessionNotificationConfig.masterEnabled`，默认 false）: 写 `~/.claude/hooks/claudoscope-notify.sh`、往 `~/.claude/settings.json` 加 Notification / Stop hook、写 `~/.claude/.claudoscope-notify-installed`；**一旦开过，之后每次启动都会 `ensureHooks()` 补齐 hook**
  - MCP（`mcpServerConfig.enabled`，默认 false）: 跑 `claude mcp remove/add -s user`（写 `~/.claude.json`），在 `~/Library/Application Support/Claudoscope/mcp.sock` 开 socket
  - Hardening / Routing 面板的安装: 改 `~/.claude/settings.json`、`~/.claude/CLAUDE.md`、`~/.claude/hooks/`、`~/.claude/skills/`，先备份到 `~/.claude/.claudoscope-*-backup-<时间>/`
  - Canon: 写项目自己的 `.claude/`
- 自己的数据: `~/Library/Application Support/Claudoscope/`（SQLite 缓存、书签），偏好 `~/Library/Preferences/com.claudoscope.app.plist`（cask 的 `zap` 列的也是这些）。
- entitlements: 不沙盒，有 `com.apple.security.automation.apple-events`（「Resume in terminal」、点通知聚焦终端时用，会弹自动化授权；启动不触发）。

## 已知问题
- 第一个标题前的说明段落不进 changelog 面板，见上。
- 厂商更新器在 app 旁边留 `Claudoscope.app.bak`，直到新版启动两次。

## 建议下一步
1. 主会话真机端到端（两轮，见下），然后把 README 那一行的一键状态改成实测结果。
2. 下一个正式版出来后复查 `/releases/latest`、版本模式、资产名。

### 真机两轮建议
真机前先备份 `~/.claude/settings.json`、`~/.claude.json` 和 `defaults export com.claudoscope.app`（如果已有）；跑完对比 `~/.claude` 有没有新文件。
1. **不运行**: `ditto` 1.3.0 进 `/Applications`，不启动 → `duo check` → `duo install --yes --json`；看 outcome、版本、inode、`codesign --verify --deep --strict`、`spctl`、Team、`diff -r`。
2. **运行中**: 再放 1.3.0 并启动（会弹引导和开机启动询问：不注册登录项；5 s 后会弹「Update Available」，**不要点 Download and Install**）→ `duo install` → `duo restart Claudoscope` → 10 s 内轮询磁盘版本。厂商更新器不暂存，不用造「暂存了更旧的版本」；可以按 T0 diff `~/Library/{Caches,Application Support,Containers}` 确认没有停放的 dmg，补上「已停放整包」第 2 栏。

## 如何复验
```bash
gh api repos/cordwainersmith/Claudoscope/releases --paginate -q '.[]|.tag_name+" "+([.assets[]|.name+" "+(.size|tostring)+" "+.digest]|join(" | "))'
gh release download v1.3.0 --repo cordwainersmith/Claudoscope --pattern 'Claudoscope.dmg'
.claude/skills/coverage-discovery/scripts/check-bundle.sh Claudoscope.dmg          # → com.claudoscope.app、DN8M2CQ4D2、Notarized
swift run --package-path application-test channel-verify Claudoscope.dmg --expect stable   # 1.3.0 → GitHub，UPDATE → 1.4.0
# v1.4.0 → up to date；v0.3.0 / v0.3.1（包里 1.0.0）、v0.3.6（包里 0.3.5）→ UPDATE → 1.4.0
```
