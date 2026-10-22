# Adrafinil

## 基本信息
- App: Adrafinil — 只在 AI 编程 agent 干活时阻止 Mac 睡眠（含合盖）。菜单栏 app（`LSUIElement`）+ 一个用户级 LaunchAgent + 一个 root LaunchDaemon + CLI。
  开源（MIT），`kageroumado/adrafinil`，与 Phosphene 同一作者
- Bundle ID: `glass.kagerou.adrafinil`（daemon `glass.kagerou.adrafinil.daemon`、helper `glass.kagerou.adrafinil.helper`、CLI `glass.kagerou.adrafinil.cli`，都在同一个 bundle 里）
- Team ID: `52K336H235`（Developer ID + 公证）。真包 1.0、1.9、1.13.0、1.13.1 全部同一 Team，`codesign --verify --deep --strict` 通过，spctl `Notarized Developer ID`
- 观测版本: 1.13.1（tag `v1.13.1`，资产 `Adrafinil-1.13.1.dmg`，`CFBundleVersion` 29）；观测日期: 2026-10-22
- 自更新机制: 有。1.0 没有；1.1.1–1.5.4 只提示有新版；**1.6.0 起会自己下载、暂存、换包**（[Tiptoe](https://github.com/artginzburg/Tiptoe) 1.1.0 over
  [mxcl/AppUpdater](https://github.com/mxcl/AppUpdater) 4.2.1，`Adrafinil/App/SilentUpdates.swift`、`Package.resolved`，v1.13.1 源码）。没有 Sparkle、没有 `SUFeedURL`
- 分发: GitHub Releases；Homebrew cask `adrafinil`（`auto_updates true`，`depends_on macos >= 26`）；官网 `kagerou.glass/adrafinil/`。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —（cask `auto_updates`，`HomebrewCaskSource` 让给下一个源） | — | ✓ | — |

当前生效源: **GitHub**（channel-verify：`winning source GitHub`）。cask 装的副本同样落到 GitHub 规则

## 覆盖清单
- 各版本的 bundle id / Team（真包读取）:
  - v1.0（`Adrafinil-1.0.dmg`）: `glass.kagerou.adrafinil`，Team 52K336H235，short `1.0`、build 3，arm64，二进制里没有 GitHub 更新地址；
    已有 `Contents/Library/LaunchAgents` 与 `Contents/Library/LaunchDaemons` 两个服务
  - v1.9（`Adrafinil-1.9.dmg`）: 同 id、同 Team，short `1.9`（两段，与 tag 一致）、build 24
  - v1.13.0、v1.13.1: 同 id、同 Team，short 与 tag 一致，build 28 / 29
  - 没换过 bundle id，也没换过 Team，安装闸不会拒旧副本
- 其他轨: 无。21 个 release 全部非 prerelease、非 draft，tag 全是 `vX.Y` / `vX.Y.Z`；`SilentUpdates` 用 `TiptoeGitHub(owner:repo:)`，没开 AppUpdater 的 `allowPrereleases`
- 同 bundle id 下的其他产品: 无。每个 release 只有 Adrafinil 的 dmg；v1.9 多一个 `adrafinil-1.9.0.dmg`，GitHub digest 与 `Adrafinil-1.9.dmg` 相同（同一个包两个名字），不匹配 install pattern
- 主机下限: Adrafinil 自己 `LSMinimumSystemVersion` 26.4、只有 arm64（1.0 起都是），DuoUpdater 是 arm64 + macOS 15，能装上它的机器我们都能跑；无需 `hostRequirement` / `architectureRequirement`

## Channel 详情

只有 stable。tag: v1.0 v1.1 v1.1.1 v1.1.2 v1.2.0 v1.3.0 v1.4.0 v1.5 v1.5.1 v1.5.2 v1.5.3 v1.5.4 v1.6.0 v1.7.0 v1.8 v1.9 v1.10.0 v1.11.0 v1.12.0 v1.13.0 v1.13.1。

## 更新检测
- 源: `kageroumado/adrafinil` GitHub Releases，`/releases/latest`
- 版本方案: tag `v1.13.1` → `CFBundleShortVersionString` `1.13.1`、`CFBundleVersion` `29`；两段式 tag 的 short 也是两段（1.0、1.9 真包实测）
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读全部 21 个 tag；锚定，`v1.14.0-rc.1`、`v1.14.0-beta` 不匹配；下一个大版本 `v2.0` 能读（python `re` 实测）
- install pattern `^Adrafinil-[0-9]+(?:\.[0-9]+)+\.dmg$`：每个 release 的 `Adrafinil-<tag 版本>.dmg` 都匹配
- 实测（2026-10-22，channel-verify，真包）:
  - 1.13.0 → `detected channel stable`，`winning source GitHub`，`latest 1.13.1`，`status UPDATE → 1.13.1`
  - 1.13.1 → `latest 1.13.1`，`status up to date`
  - 1.9、1.0 → `download …/v1.13.1/Adrafinil-1.13.1.dmg`，`status UPDATE → 1.13.1`

## 按架构 / 按 OS 分轨
- 架构: arm64 only（1.0–1.13.1）。`LSMinimumSystemVersion` 26.4，release 不声明上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | AppUpdater 只下整个 dmg（`AppUpdater.swift` 的 `NetworkTransfer.download`） | 每个 release 只有 dmg；channel-verify `deltas 0` | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（1.6.0 起，自动安装默认开） | 没查（没有运行它） | ○ 需要引擎加一种停放位，不做 |
| 证据 | 读自 v1.13.1 源码和它锁定的 Tiptoe a48f105 / AppUpdater a2b8989 | — | 没有完成记录文件；停放的 dmg 文件名只有 UUID |

怎么停放（源码，未在真机上看）:
- `AdrafinilSettings` 默认 `autoInstallUpdates = true`、`launchAtLogin = true`（存在 `~/Library/Application Support/Adrafinil/config.json`，不是 UserDefaults）。
  只在 setup 完成后（`AdrafinilDidCompleteFirstRun`）才 `SilentUpdates.start`；每 4 小时、以及打开菜单 / 唤醒后（距上次超过 1 小时）查一次 `/releases`
- 有新版且自动安装开着时，AppUpdater 把 dmg 下到 `$TMPDIR/app-updater-<UUID>/.app-updater-<UUID>.dmg`，再拷到 app 旁边成为 `/Applications/.app-updater-<UUID>.dmg`，
  校验后交给 Tiptoe 等「安静时刻」：无输入 120 s 且没有可见窗口（`QuietPolicy`），**另加 Adrafinil 自己的闸**：daemon 报告没有任何 agent 被保持唤醒
  （`nothingIsBeingKeptAwake`，daemon 不可达也算「不行」，这个闸不随时间放宽）
- 换包: 旧包改名 `.app-updater-backup-<UUID>.app`，放入新包，拉起新进程，删备份和那份 dmg
- 待装的那份只在进程内存里（`TiptoeGitHub.waiting`），退出就丢

和我们的交互:
- **它会和我们抢吗**: app 不运行时不会。运行中时：我们换完包、旧进程还没退时，它手里可能握着一份准备好的安装；装之前只校验
  bundle id / Team / 签名标识（`PreparedInstallation.installAndRelaunch` → `driver.validate` → `requireMatch`），**不比版本**。
  握的是同一版就把同版本再装一遍；握的是更旧的一版（新版发布后它最多 4 小时才再查）就会把我们装的换回旧版，下次检查再升上来。
  1.13.1 的说明写的就是同类问题（「Update Now」会装上它一直握着的上一版）
- `duo restart` 让旧进程退出，握着的那份随之丢掉，不会发生上面的回退
- 判断: 与 Phosphene 相同，结果自愈、不伤数据，不加 `OneClickGate`

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: ✓。channel-verify `changelog pane`: `source structured: 1 entries; newest 1.13.1: 2 items, headings []; first items ["Update Now always installs the newest re", "Adrafinil checks for updates every four "]`
- 用生产解析器（`GitHubMarkdownParser.parse`）跑了四个真实正文（临时探针，已删）:
  - 列表式（1.13.1、1.12.0）: 只取列表项，开头的 `**Download:** [Adrafinil-x.dmg](…)` 段被丢掉，正好
  - 粗体段落式（1.13.0，没有列表）: 走 prose 那一轮，三条：`**Download:**` 链接段、「Count yourself in」、「日本語に対応しました」，下载链接多成一条
  - 带 `###` 小节的（1.9）: `New` / `Changed` 两个标题**保留成 heading**，小节下的粗体段落各成一条；但开头一条推广别的 app 的列表项也进来了，
    导语段「Adrafinil now speaks Simplified Chinese.」被丢掉
- 跟随 channel: 只有一个轨
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（不加 `OneClickGate`，理由见下）
- 端到端: **未跑**（本次是 agent 接入，没做真机；由主会话做）
- 格式: dmg（ULFO，arm64），根目录 `Adrafinil.app`
- 校验: GitHub digest 与下载的包一致：1.13.1 `sha256:89eb7c82f0a706235eed5ef13ce5700e6fd12d2e5155cce5d1179decd50dfa0b`，
  1.13.0 `sha256:538e8aa21bdcb34d93bb7136b22dadea51a15e7223f65348dd9f2b4e0f6c8704`
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）

### 外部组件：换包后谁在跑旧代码（读自 v1.13.1 源码与 `Docs/ARCHITECTURE.md`，未在真机上看）
- `Contents/Library/LaunchAgents/AdrafinilDaemon` + `LaunchAgent.plist`: label `glass.kagerou.adrafinil.daemon`，`BundleProgram`，`RunAtLoad` + `KeepAlive`，
  以用户身份常驻（app 关着也在跑），所有策略在这里
- `Contents/Library/LaunchDaemons/AdrafinilHelper` + `LaunchDaemon.plist`: label `glass.kagerou.adrafinil.helper`，**root**，`RunAtLoad` + `KeepAlive`，
  只有它调 `pmset -a disablesleep` 和 IOPM 断言；`SMAuthorizedClients` 要求调用方是 `glass.kagerou.adrafinil` + Apple 签发证书
- **什么时候注册**: 只在首启 setup 窗口里由用户点按钮时（`HelperInstaller.installIfNeeded` → `SMAppService.daemon/agent(plistName:).register()`，
  外加 `SMAppService.mainApp` 登录项）；之后系统要求在「登录项与扩展」里批准。`AppDelegate` 注释写明启动本身不做任何特权操作。
  setup 完成后的每次启动，若 `launchAtLogin` 开着会补注册 `mainApp` 登录项（不碰 daemon/helper）
- **换包后**: launchd 继续跑已加载的旧映像。1.1 起两者都带 `ExecutableStaleness`（启动时记下自己可执行文件的 dev/inode/size/mtime）:
  - daemon: app 连上来订阅状态时（`AppXPCServer`）、从「保持唤醒」回到空闲时、安全切断解除时，若文件已换且当前没有保持唤醒 → `exit(0)`，KeepAlive 让 launchd 从新 bundle 拉起
  - helper: 新 daemon 启动时会探测 helper 版本（`logHelperVersion`），helper 在这次调用（以及每次解除阻止）里检查，文件已换且当前没阻止睡眠 → `exit(0)`，同样由 launchd 拉起新的
  - 所以换包 + `duo restart` 后，新 app 一连上，daemon 和 helper 会依次换成新代码；正在保持唤醒时会推迟到空闲。厂商自己的 Tiptoe 换包靠的也是这一套
- **厂商自己更新时**: 不 bootout、不重新注册，就是整包替换 + 上面的自我接管。注册失效时 app 有 `repairServices`（unregister 再 register），只在 daemon 持续不可达时自动跑一次
- **会不会版本不一致**: 窗口期内会（新 app + 旧 daemon/helper），厂商按「版本错位」设计了容忍：`Assertion` 等线格式容错解码、daemon 日志记 helper 版本不一致。
  app 不运行时换包：退出 app 会让 daemon 暂停（`applicationShouldTerminate` → `setPaused(true)`），旧 daemon 一直闲着，直到下次启动 app 才接管新二进制
- **BTM 授权**: 同一路径、同一 Team、同一 label，duo 换包与厂商自己的换包形状相同。仓库里的先例（SwitchHosts，SMAppService LaunchDaemon，见 `net-oldj-switchhosts.md`）
  真机记录是换包后 BTM 仍 `[enabled, allowed]`；**本 app 未在真机上核**
- **结论**: 一键直接开，不加 `OneClickGate`、不加 `loginItemAgentRestarts`（后者只认 `Contents/Library/LoginItems` 里的 `.app`，这里不适用；
  而且在保持唤醒时杀 daemon 会丢掉正在跑的 agent 的保持，厂商刻意推迟到空闲）

### 真机时要注意的副作用（读自 v1.13.1 源码，未在真机上看）
- **首启弹 setup 窗口**（`InstallerView`），启动本身**不弹管理员框、不注册任何服务**。setup 里：
  - 注册 helper/daemon 和登录项要点按钮；之后系统会弹「登录项」通知并要求在「系统设置 › 通用 › 登录项与扩展」里批准（批准 root daemon 时系统可能要求管理员认证，未验证）
  - **agent 那一步默认勾上所有检测到的 agent（含 Claude Code）**，点安装会写 `~/.claude/settings.json` 的 hooks（`UserPromptSubmit`/`Stop`/`SessionEnd`…）和 `~/.claude.json` 的 MCP 条目，
    还有 `~/.codex/hooks.json`、`~/.cursor/hooks.json`、`~/.gemini/settings.json` 等。**一定点 Skip**；动之前备份 `~/.claude/settings.json` 和 `~/.claude.json`
  - CLI 软链到 `/usr/local/bin/adrafinil`，不可写时退到 `~/.local/bin/adrafinil`（不弹管理员框）
- 服务注册后，helper 会以 root 跑 `pmset -a disablesleep 1/0`（全局睡眠设置）。只要没有 agent hooks、没开「自动嗅探」（默认关），就不会去阻止睡眠
- 启动时会强杀同 bundle id 的其他实例（`terminateOtherInstances`）
- 「是否参与匿名统计」只问一次，默认不发；1.13.0 起
- setup 完成后才启动自更新器；自动安装默认开（见「已停放整包」）
- 退出 app = 暂停 daemon（释放所有保持唤醒），所以 `duo restart` 一个正在保持唤醒的 Adrafinil，会让当时在跑的 agent 失去保持，直到它的下一次 hook 重新获取；
  用户手动退出也是一样。厂商自己的换包有闸挡住这种时刻，我们没有
- 产生的数据: `~/Library/Application Support/Adrafinil/`（config.json、state.json、events.log、cli.sock）、`~/Library/Preferences/glass.kagerou.adrafinil.plist`

推荐的两轮真机步骤:
1. app 不运行、从没启动过: 装 1.13.0 → `duo install glass.kagerou.adrafinil --yes --json` → 磁盘 1.13.1、Team 不变、codesign/spctl 通过、`duo check` up to date；
   再 `xattr -l /Applications/Adrafinil.app` 记下有没有 `com.apple.provenance`（厂商 1.9 的 README 说带它的副本**首次**注册后台服务会静默失败；对已注册的更新是否有影响未知）
2. app 运行中，分两种做法，任选:
   - 2a（不碰 root）: 装 1.13.0，`defaults write glass.kagerou.adrafinil AdrafinilDidCompleteFirstRun -bool true` 跳过 setup（这样自更新器会启动、但没有服务，app 会提示服务不可用），
     启动 → 等它下完（`/Applications/.app-updater-*.dmg` 出现）→ `duo install` → `duo restart` → 轮询约 10 s 磁盘版本仍 1.13.1
   - 2b（全量，要用户在系统设置里批准）: 装 1.13.0，走 setup：点注册服务、**agent 那步点 Skip**；在「登录项与扩展」批准后，`launchctl print gui/$UID/glass.kagerou.adrafinil.daemon` 看 pid，
     `launchctl print system/glass.kagerou.adrafinil.helper`（system 域不用 sudo 也能读 `pid`/`program`，以 `com.apple.mDNSResponder.reloaded` 试过）、`ps -o pid,lstart -p <pid>`。然后 `duo install` → `duo restart`，
     约 10 s 后两者 pid 都应换新、启动时间晚于换包，`program` 仍指 `/Applications/Adrafinil.app/...`；`pmset -g | grep SleepDisabled` 应为 0；BTM 两项仍是 enabled/allowed
   - 造「握着的版本比 latest 旧」: GitHub 上只有 1.13.1 比 1.13.0 新，没法直接造；可行的是让运行中的 1.12.0 只看到去掉 v1.13.1 的 `/releases` 列表（本机代理改写那一个 URL），
     让它握住 1.13.0，再 `duo install` 装 1.13.1、**不 restart**，离开键鼠 2 分钟以上，看磁盘是不是被换回 1.13.0。需要代理对 api.github.com 做 HTTPS 解密，未试
- 收尾: 走过 2b 的话，用 app 里的「Settings › Uninstall and quit…」——它先 `forceReleaseAll` 清掉 `disablesleep`，再 unregister helper/daemon/登录项、删 hooks、CLI 软链和数据目录，不用 sudo。
  如果没走 uninstall 就删了 app，root helper 会一直跑到重启，要用户执行 `sudo launchctl bootout system/glass.kagerou.adrafinil.helper`，再确认 `pmset -g | grep SleepDisabled` 是 0
  （不是 0 就 `sudo pmset -a disablesleep 0`）。之后挪走 `/Applications/Adrafinil.app` 和可能留下的 `/Applications/.app-updater-*`，`hdiutil info` 确认没有残留挂载，
  `sfltool dumpbtm` 前后比对（先核 dump 非空）

## 已知问题
- 运行中换包后若不 restart，旧进程握着的准备安装可能在安静时刻再装一遍（同版本无害；旧版本会短暂降级、随后自愈）
- 1.0 的 daemon/helper 没有 `ExecutableStaleness`：从 1.0 一键升上来后，旧 daemon/helper 一直跑 1.0 的代码，直到注销 / 重启（或 app 的 repair 重新注册）。
  1.0 没有自更新器，厂商给 1.0 用户的唯一路径（手动拖拽替换）也是同样结果
- `duo restart` 正在保持唤醒的 Adrafinil 会暂停 daemon、释放保持（见上）
- 1.13.0 那种粗体段落正文，changelog 里多一条下载链接；1.9 多一条推广条目、丢导语段

## 如何复验
```bash
gh release download v1.13.1 --repo kageroumado/adrafinil --pattern 'Adrafinil-1.13.1.dmg' -D v1.13.1
gh release download v1.13.0 --repo kageroumado/adrafinil --pattern 'Adrafinil-1.13.0.dmg' -D v1.13.0
.claude/skills/coverage-discovery/scripts/check-bundle.sh v1.13.1/Adrafinil-1.13.1.dmg v1.13.0/Adrafinil-1.13.0.dmg
swift run --package-path application-test channel-verify v1.13.0/Adrafinil-1.13.0.dmg --expect stable   # UPDATE → 1.13.1
swift run --package-path application-test channel-verify v1.13.1/Adrafinil-1.13.1.dmg --expect stable   # up to date
# 外部组件: v1.13.1 的 Docs/ARCHITECTURE.md、AdrafinilDaemon/LaunchAgent.plist、AdrafinilHelper/LaunchDaemon.plist、
#   AdrafinilShared/Sources/AdrafinilShared/ExecutableStaleness.swift（16fe852，v1.1 起）、AdrafinilDaemon/Daemon.swift relaunchIfUpdatedWhenIdle、
#   AdrafinilHelper/HelperXPCService.swift relaunchIfUpdated、Adrafinil/Installer/HelperInstaller.swift
# 自更新器: Adrafinil/App/SilentUpdates.swift；Tiptoe a48f105 的 Sources/TiptoeGitHub/、AppUpdater a2b8989 的 AppUpdater.swift
```

## 建议下一步
1. 主会话真机两轮（见「一键安装」），尤其 2b：确认换包后 daemon/helper 自己换成新代码、BTM 授权不掉、`com.apple.provenance` 不影响已注册服务
