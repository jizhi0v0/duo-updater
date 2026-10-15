# Seedmux

## 基本信息
- App: Seedmux — 给编码 agent 用的原生 macOS 终端（内置 tmux，手机端可远程看/起 agent），另有 Linux 版 `smx`
- Bundle ID: `com.xx.seedmux`（0.1.0、0.1.72、0.1.78、0.1.79 arm64 与 0.1.79 x86_64 真包相同）
- 仓库: `wishworldbetter/seedmux` — 只有 `README.md` 和 Releases，源码不公开
- Team ID: `DM5Z8Y9C3V`（Developer ID + 公证；上面五个真包相同）
- 观测版本: 0.1.79（`CFBundleVersion` 82）；观测日期: 2026-10-15
- 自更新机制: Sparkle 2（`SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks` = true、`SUScheduledCheckInterval` = 3600）
- 分发: 只有 GitHub Releases（每个 release 带 appcast、arm64 / x86_64 的 zip 与 dmg、Sparkle delta、Linux 二进制）。
  没有 Homebrew cask、没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | ✓       | —        | —   | —      | —           |

当前生效源: **Sparkle**（通用源，无 recipe）。`feed-discover` 对 0.1.78 zip: `declared
https://github.com/wishworldbetter/seedmux/releases/latest/download/appcast.xml`。

## Channel 详情

单轨。appcast 里没有 `<sparkle:channel>`（0.1.79 的 `appcast.xml` 4 个 item、`appcast-x86_64.xml` 3 个 item，都不带标签）；
截至 2026-10-15 共 80 个 release，全部非 pre-release。源码不公开，app 内是否有 beta 开关没法从源码确认；包里的 Info.plist
只有一个 `SUFeedURL`。

## 更新检测
- 源: `SparkleAppcastSource`，地址取 bundle 自己的 `SUFeedURL`
- 按架构分 feed: arm64 构建声明 `…/latest/download/appcast.xml`（item 带 `<sparkle:hardwareRequirements>arm64`），x86_64
  构建声明 `…/latest/download/appcast-x86_64.xml`。每份拷贝读自己包里写的那份，不需要 binding
- 两份 feed 的 enclosure 都是 `releases/latest/download/Seedmux-<v>.zip`；厂商每个 release 都把最近几版的 zip 重新挂上
  （0.1.79 的 release 带 0.1.72–0.1.79 的 zip），所以下一个 release 发布后旧 enclosure 地址仍能解析
- OS: item 声明 `minimumSystemVersion` 13.0（0.1.0 那个旧 item 写 14.0），没有 `maximumSystemVersion`；包里
  `LSMinimumSystemVersion` = 13.0

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有（只 arm64） | 能 |
| 证据 | 内置 Sparkle.framework | 2026-10-15 `appcast.xml` 的 0.1.79 item 带 5 个 `sparkle:deltaFrom` 77–81；`appcast-x86_64.xml` 没有 `deltas` | 通用 Sparkle 源 + `DeltaApplier`；channel-verify 对 0.1.78 报 `deltas 5` |

- 格式: Sparkle binary delta
- 本次一键是否实际走了 delta: 未核实

## Changelog
- 来源: appcast inline `<description sparkle:format="markdown">`
- 结构化（2026-10-15，channel-verify `changelog pane`，从 0.1.78 起）: `source structured: 4 entries; newest 0.1.79:
  9 items, headings [] (rendered as markdown); first items ["New: start an agent from your phone. Tap", "Codex started
  from the phone without a f", "Home list is ordered by the most recent "]`
- 厂商每条 notes 是中英双语（英文段、`---`、中文段），所以每项内容出现两次；没有分节标题
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（通用 Sparkle 路径，EdDSA + Team 闸）
- 格式: zip
- 嵌套: `Contents/MacOS/smx`（Go 写的守护进程）是 `Contents/Library/LaunchAgents/com.xx.seedmux.daemon.plist` 的
  `BundleProgram`（`KeepAlive` / `RunAtLoad` true，参数 `smx daemon --log auto`），由 app 用 `SMAppService` 登记；不是嵌套
  `.app`，`NestedAppGuard` 不拦。另有 Sparkle 自带的 `Updater.app`
- **读的是**: 人人可手动下载的 GA（GitHub `releases/latest`）
- 端到端（2026-10-15，不运行）: 0.1.78 → `duo check` `0.1.78 → 0.1.79 [Sparkle, in-place]` → `duo install --yes` →
  `verifyingSignature → extracting → verifyingCodeSignature → installing → done`，4.7 s。结果: 版本 0.1.79、`smx`
  inode 变了、Team `DM5Z8Y9C3V`、`codesign --verify --deep --strict` = 0、`spctl` = Notarized Developer ID、`diff -r`
  与 vendor 的 0.1.79 bundle 相同（exit 0）
- 端到端（2026-10-15，运行中，含守护进程）: 启动 0.1.78 → app 用 `SMAppService` 登记并拉起 `com.xx.seedmux.daemon`
  （`launchctl print`: pid 7594，`parent bundle version = 81`）→ `duo install` 6.9 s，提示 "Still running the old code" →
  `duo restart` → app 新 pid 跑新 bundle；守护进程换成新 pid 10616（`runs = 2`），`lsof` 看到它跑的 `smx` inode 等于磁盘上
  0.1.79 的文件。launchd 的 `parent bundle version` 仍显示 81（登记元数据没刷新，进程本身是新的）。30 s 后磁盘仍是 0.1.79
- app 自己的 Sparkle: 0.1.78 启动时只弹了更新提示（`SUUpdateAlert` 窗口），没有自动下载暂存（`~/Library/Caches/com.xx.seedmux`
  下没有 Sparkle 暂存目录），所以这次没有构成暂存碰撞；「已暂存一个比 latest 旧的版本」的情形没有复现
- 启动副作用（app 的行为，测完已还原）: 往 `~/.zshrc` 追加 `# >>> seedmux agent-shims >>>` 段；新建
  `~/.claude/skills/seedmux-team`、`~/.agents/skills/seedmux-team`、`~/.codex/seedmux.config.toml`（另留一个
  `.seedmux-hook-migration.json.<UUID>.backup`）和 `~/.seedmux/`；`~/.claude/settings.json` 没改。守护进程 `KeepAlive`，
  app 退出后仍在跑；`sfltool dumpbtm` 多出 `2.com.xx.seedmux`
- 阻塞: 无

## 已知问题
- 真机验证要先备份上面列的 shell / agent 配置：一启动就会写入。

## 建议下一步
1. 自更新器已暂存旧版时的碰撞没复现（它只提示、不自动下载）。若厂商改成自动下载，重跑运行中一轮。

## 如何复验
```
swift run --package-path application-test feed-discover <Seedmux-0.1.78.zip>         # → declared …/appcast.xml
ditto -x -k <Seedmux-0.1.78.zip> <dir>
swift run --package-path application-test channel-verify <dir>/Seedmux.app           # → stable，Sparkle，UPDATE → 0.1.79，deltas 5
ditto -x -k <Seedmux-0.1.79-x86_64.zip> <dir2>
swift run --package-path application-test channel-verify <dir2>/Seedmux.app          # → …/appcast-x86_64.xml，up to date
```
