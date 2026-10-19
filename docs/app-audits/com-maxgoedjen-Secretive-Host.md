# Secretive

## 基本信息
- Bundle ID: `com.maxgoedjen.Secretive.Host`（内嵌 SSH agent `com.maxgoedjen.Secretive.SecretAgent`，
  位于 `Contents/Library/LoginItems/SecretAgent.app`）
- Team ID: `Z72PRUAWF6`
- 观测版本: `4.0.0`（`CFBundleVersion` 是 `1.<CI run id>`，如 `1.35554366823`，不参与比较）
- 自更新机制: 自研，只提醒不安装。`Brief/Updater.swift` 经 XPC 服务 `SecretiveUpdater.xpc`
  取本仓库的 releases，跳过 prerelease，按 release 名比较版本，给出 release 页面链接
- 分发: GitHub Releases（`maxgoedjen/secretive`，每版一个 `Secretive.zip`）/ Homebrew cask
  `secretive`（非 `auto_updates`，`url` 就是同一个 GitHub zip）
- 开源: 是。以下渠道、版本方案均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | 未验证   | —   | ✓      | —           |
| **nightly**| —       | —        | —   | ✗（只有 Actions artifact） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（对不在 Caskroom 里的真包跑
`channel-verify` 的结果；经 brew 安装的副本由哪个源应答未验证）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.maxgoedjen.Secretive.Host` | 单一渠道 | — | tag 锚 `^vX.Y.Z$` | ✓ |
| nightly | `com.maxgoedjen.Secretive.Host` | 共享 bundle id | 版本 `0.0.0_nightly-<date>`（`ReleaseChannel.detect` 0.99） | 无 rule，不提供更新 | — |

单渠道对外分发。仓库里的 prerelease 只有 2020 年的 `v0.1.1`–`v0.5.1`，此后全部是正式版。

nightly 不是可订阅的轨道，但装上了必须认得出来:
- `.github/workflows/nightly.yml` 每天 08:00 UTC 出一个构建，只作为 Actions artifact 上传，
  不建 release。用的是**同一个** bundle id、名字、Team。2026-10-13 那个 artifact 的
  `expires_at` 是 2027-01-11，即 90 天后过期（artifacts API 实读）。匿名能否下载**未验证**:
  匿名请求被限流挡住，官方文档也没写。
- 版本由 `sed s/GITHUB_CI_VERSION/0.0.0_nightly-$DATE/` 写进 `Config.xcconfig` 的 `CI_VERSION`。
  2026-10-14 下载 run 38367930469 的 artifact 实读 Info.plist:
  `CFBundleShortVersionString = 0.0.0_nightly-2026-10-13`、`CFBundleVersion = 1.38367930469`、
  Team `Z72PRUAWF6`。
- 分隔符是下划线，通用的版本尾词规则（只认 `-nightly`）读不到，修复前这个副本被判成 stable
  0.0.0。修复前 `channel-verify` 实跑结果: `detected channel → stable`、`status UPDATE → 4.0.0`，
  也就是会把 stable 4.0.0 当更新推给 nightly 副本。
- 现在 `ReleaseChannel.detect` 有一条只对这个 bundle id 生效的规则（0.99），把
  `<数字>_nightly[-<数字>…]` 判为 `.nightly`。GitHub 源没有 nightly rule，于是直接跳过、不发请求。
  修复后 `channel-verify --expect nightly` 结果: `detected channel → nightly`、
  `status unknown (no source answered)`。测试见 `SecretiveChannelTests`。
- `.github/workflows/oneoff.yml`（手动触发，截至 2026-09-16 共 19 次）以同样的方式写入
  `0.0.0_oneoff-<date>`，这个副本**仍判为 stable 0.0.0**，会被推 4.0.0。没有修，因为这类构建算哪个渠道
  缺证据；实际装到它的人应该很少。

## 更新检测
- 源: `maxgoedjen/secretive` GitHub Releases，`/releases/latest`（2026-09-29 为 `v4.0.0`）
- 版本方案: settled from source: `.github/workflows/release.yml` on `main`——tag 推送触发，
  `CLEAN_TAG` = tag 去掉 `v` 写进 `CFBundleShortVersionString`，`CFBundleVersion` = `1.$RUN_ID`；
  资产固定叫 `Secretive.zip`。tag `v4.0.0` → `4.0.0` == 真包 `CFBundleShortVersionString`，
  `v3.0.4` → `3.0.4` 同样相等。
- 注意事项: 仓库有 tag `v3.0.1-skipped`，没有对应 release；anchor `^v([0-9]+(?:\.[0-9]+)+)$`
  也不收它。v3.0.1 在 releases 列表里缺席，3.0.0 之后直接是 3.0.2。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | `Updater.swift` 只挑出一个 `Release` 供提醒，不下载资产（读源码） | 30 个 release 每个只有整包 `Secretive.zip`（2026-09-29 `releases?per_page=30`） | — |

## 按 OS 分轨
- 真包 `LSMinimumSystemVersion`: 4.0.0 为 `15.0`，3.0.4 为 `14.0`。
- 厂商更新器按 release 正文里的 `Minimum macOS Version` 一行过滤（`Release.minimumOSVersion`），
  取「系统能跑的最新非 prerelease」。2026-09-29 的正文: `v4.0.0` 写 `15.0.0`，`v3.0.x` 写
  `14.0.0`，`v2.4.x` 写 `12.0.0`。
- 我们的 GitHub 源不读这个下限，见「已知问题」。

## Changelog
- 来源: GitHub Release body（`GitHubReleasesSource`；`channel-verify` 给出 changelogURL
  `…/releases/tag/v4.0.0`）
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 3.0.4 检查）: ✓ 分节保留 — `Features` / `Fixes`，19 条；只带回最新一版的说明（1 个条目）
- 跟随 channel: 单渠道
- Recipe 状态: 不需要

## 一键安装
- 状态: ✓ **一键**（`installAssetPattern: ^Secretive\.zip$`、`installerKind: .zip`；换包后由
  `loginItemAgentRestarts` 重启内嵌 SSH agent，见下）
- 格式: zip — `Secretive.zip`，universal（`x86_64 arm64 arm64e`）
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产）
- 包验（2026-09-29，v4.0.0 与 v3.0.4 解压）: 主 app 与 `SecretAgent.app` 都是
  `Developer ID Application: Max Goedjen (Z72PRUAWF6)`，`spctl` 均为
  `accepted / Notarized Developer ID`，`codesign --verify --deep --strict` 通过。
  也就是说，装包本身能过安装闸。
- 换包时 SSH agent 还在跑（为什么曾经只检测、现在怎么解决）：
  - `SecretAgent.app` 由主 app 用 `SMAppService.loginItem` 注册为登录项，`LSUIElement=true`。
    日常情况是主 app 关着、agent 常驻，所有 `ssh` 签名都走它的 socket。
  - `AppRestarter.isStandaloneNestedApp` 只认 `.regular` 激活策略的内嵌 app，所以一键更新既不退出
    也不重启这个 agent（读源码）。换包后它继续跑旧代码，而它的 bundle 已在磁盘上被替换。
  - 厂商自己的做法（`Sources/Secretive/App.swift`）是主 app 下一次激活时，若
    `justUpdatedBuild` 为真就 `forceLaunch()` 重拉 agent，注释写的是 agent "will be running
    from earlier update still"。我们的一键更新只在主 app 原本就开着时才重开它，而日常主 app 是关着的。
  - **实测（2026-10-19）：换包后，签名会在 XPC 重新拉起时挂死。** 装 3.0.4、启动、装上 agent（登录项）、
    在 Secretive 里建一把不需认证的测试密钥；主 app 退出、agent 常驻；在测试分支上临时给规则加
    `installAssetPattern: ^Secretive\.zip$` + `.zip`，`duo install Secretive --yes --json` → `installed`（22831028 B），
    磁盘上主 app 与 agent 都成了 4.0.0，agent 可执行文件 inode 变了，旧 agent（3.0.4）的 pid 与两个 XPC 不变。
    用 `SSH_AUTH_SOCK=~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh` 跑
    `ssh-keygen -Y sign`（只签本地文件，`-Y verify` 校验）：
    - 旧 agent + 旧 XPC：签名成功。
    - 让 `SecretAgentInputParser.xpc` 退出（SIGKILL，模拟它空闲退出），它从**新**包被拉起（4.0.0）：
      签名 **20 s 超时、两次都挂住**，`ssh-add -L` 也列不出。日志：新 XPC
      `Received message forbidden due to code signing requirement`（`xpc_support_check_token` -67065），
      旧 agent `SWIFT TASK CONTINUATION MISUSE: send(_:) leaked its continuation without resuming it`。
      也就是新 XPC 拒收旧 agent 的消息，旧 agent 不处理失败，`ssh` 永远等。
    - 结束旧 agent：launchd 立刻从新包把 agent 拉起（4.0.0），签名恢复。
    - 测完删除测试密钥、Disable Agent（BTM 变 disabled）、app 与容器移入废纸篓；`~/.ssh/config` 与 shell
      配置前后校验和不变。
  - 所以直接开一键会在主 app 关着时让 SSH 签名在某个时刻开始挂死，直到用户打开 Secretive 或重新登录。
    补救办法已证实：换包后重启 agent（结束旧 agent 进程即可，launchd 会从新包拉起）。DuoUpdater 现在
    没有这个机制（`AppRestarter` 只重启 `.regular` 内嵌 app，`NestedAppGuard` 跳过 `LoginItems`），
    要接一键需要先加「换包后重启指定后台登录项」。
  - **现在的做法**：recipe 的 `loginItemAgentRestarts` 声明 `com.maxgoedjen.Secretive.SecretAgent`。
    `InstallCoordinator` 在换包前记下从本 bundle `Contents/Library/LoginItems/SecretAgent.app/Contents/MacOS/`
    跑着的进程（pid + 启动时间），换包后确认它是 launchd 作业（见下）再发 `SIGTERM`，再在 10 s 内等 launchd 从新包拉起新进程；
    没回来就记日志、`duo install` 打警告、`--json` 带 `agentsNotRestarted`（`LoginItemAgentRestart`）。
    agent 原本没在跑就不动它。
  - **真机端到端（2026-10-19，本分支 `make install` + `make cli`）**：装 3.0.4、Start Agent、建不需认证（Notify）
    的测试密钥，基线签名成功。
    - 主 app 关着：`duo install Secretive --yes --json` → `{"applied":true,"bytesDownloaded":22831028,"outcome":"installed","route":"vendor"}`
      （15.4 s）。agent pid 15780 → 21340（11:40:04 启动，`launchctl print` 的 `runs` 1 → 2），日志
      `login-item agent com.maxgoedjen.Secretive.SecretAgent: restarted from the new bundle (pid 21340)`。
      签名成功；`kill -KILL` `SecretAgentInputParser` 后它从新包重新拉起，再签两次都成功（修复前这一步挂死）。
    - 主 app 开着：重新放回 3.0.4、让 launchd 拉起 3.0.4 的 agent、打开主 app，签名成功；`duo install` → `installed`，
      agent pid 22654 → 23168，日志同上；杀 XPC 后签名成功；`duo restart Secretive` → `restarted`，签名成功，
      再杀 XPC 签名仍成功。Secretive 的 agent 面板显示 agent 版本 4.0.0。
    - 清理：删除测试密钥、Disable Agent（BTM `disabled`）、app 与 4 个容器移入废纸篓（含上一轮留下的两个 XPC
      容器）；`~/.ssh/config` 与 shell 配置字节一致。
  - **只重启 launchd 管着的 agent**。Secretive 2.x 和 3.x 都是先注册登录项（2.x `SMLoginItemSetEnabled`，3.x
    `SMAppService`），登录项没在跑时都回退成 LaunchServices 直接拉起（`App.swift` 的 `forceLaunchAgent()`，
    读源码 v2.4.1 / v3.0.0 / v3.0.2；3.0.3 起先 `register()` 再回退）。LaunchServices 拉起的 agent 没有
    launchd 作业，结束它就没人再拉起。2026-10-19 实测 2.4.1（这台机器的 BTM 里留着上一轮已 disabled 的
    条目，所以走的正是回退路径）：`launchctl list` 里 agent 的标签是
    `application.com.maxgoedjen.Secretive.SecretAgent.…`，没有 `com.maxgoedjen.Secretive.SecretAgent` 作业；
    退出主 app、`SIGTERM` 后 15 s 内没有新 agent。所以 `LoginItemAgentRestart` 在发信号前先
    `launchctl print gui/<uid>/<agent bundle id>`，只有作业的 `pid` 正是快照里的旧进程才结束它；否则不动它、
    报 `agentsNotRestarted`（用户打开 Secretive 时它会按 `justUpdatedBuild` 自己换掉 agent）。不按版本分：
    同一版本两种状态都可能出现。
  - **复测（2026-10-19，commit 96d735c1 的 `make install` + `make cli`）**：
    - launchd 作业的 agent：装 3.0.4、Start Agent、建测试密钥（Notify）、退出主 app。换包前
      `launchctl print gui/501/com.maxgoedjen.Secretive.SecretAgent` 有一行 `\tpid = 77600`。`duo install` →
      `installed`，作业 pid 77600 → 78398、`runs` 1 → 2，日志 `restarted from the new bundle (pid 78398)`；签名成功，
      杀两次 XPC 后仍成功。
    - LaunchServices 拉起的 agent：放回 3.0.4，`launchctl bootout gui/501/com.maxgoedjen.Secretive.SecretAgent`，
      `open …/LoginItems/SecretAgent.app`（标签 `application.com.maxgoedjen.Secretive.SecretAgent.…`），签名成功。
      `duo install --json` → `{"agentsNotRestarted":["com.maxgoedjen.Secretive.SecretAgent"],…,"outcome":"installed"}`，
      stderr 警告，日志 `not running as its launchd job (job pid none) — left running`，agent pid 不变。杀 XPC 后
      `ssh-add -L` 超时（exit 124），即 #1457 的挂死。打开 Secretive：它重新注册登录项，launchd 拉起新 agent
      （pid 80844），签名成功，再杀 XPC 仍成功；旧 agent（可执行文件已删）还在跑但不再接 socket，测试后手动结束。
    - 清理：删除测试密钥、Disable Agent（BTM `disabled`）、app 与 4 个容器移入废纸篓；`~/.ssh/config` 字节一致。
- 端到端（2026-10-19）: 装 3.0.4 → `duo check` 报 `3.0.4 → 4.0.0 [GitHub, in-place]` → `duo install` 装上，
  agent 随之重启（见上）。2026-09-29 只检测时是 `Skipping: Secretive — detection only`。

## 已知问题
- 无。（2026-09-29 记的「macOS 14 上会报 4.0.0 更新」不成立：DuoUpdater 自身 `deploymentTarget` 是
  macOS 15.0（`App/project.yml`），跑不到 macOS 14 上；4.0.0 的 `LSMinimumSystemVersion` 15.0 恰好落在
  这个下限上。）

## 如何复验
```
# GET https://api.github.com/repos/maxgoedjen/secretive/releases/latest → v4.0.0
# ditto -x -k Secretive.zip → Secretive.app: com.maxgoedjen.Secretive.Host / 4.0.0 / Team Z72PRUAWF6
swift run --package-path application-test channel-verify <v4.0.0>/Secretive.app --expect stable
#   → winning source GitHub, latest 4.0.0, status up to date
swift run --package-path application-test channel-verify <v3.0.4>/Secretive.app --expect stable
#   → winning source GitHub, latest 4.0.0, status UPDATE → 4.0.0
```

## 建议下一步
1. 一键安装: 已接入（见「一键安装」）。菜单栏 app 里 agent 没回来时只有日志，界面上没有提示。
2. OS 下限: 已不需要（DuoUpdater 最低 macOS 15，见「已知问题」）。
