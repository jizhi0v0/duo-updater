# Headroom

## 基本信息
- App: Headroom — 菜单栏 app，在本机起一个压缩代理（`127.0.0.1:6767`），把 Claude Code / Codex 等编程 agent 的请求改道经过它以省 token；Tauri 2 + Python 后端；MIT
- Bundle ID: `com.extraheadroom.headroom`（可执行文件 `headroom-desktop`，`LSUIElement`）
- 仓库: `gglucass/headroom-desktop`（默认分支 `main`，发 rc 的分支 `staging`）
- Team ID: `ZA6LNF9PF9`（0.9.45、0.9.46、0.9.47-rc.3 三个真包相同；dmg 公证）
- 观测版本: 0.9.46（2026-10-21 发布）；上一版 0.9.45；观测日期: 2026-10-22
- 自更新机制: **Tauri updater**（`tauri-plugin-updater`，minisign 校验 `.app.tar.gz`）。settled from source: `src-tauri/src/lib.rs` on `main`：stable 端点 `DEFAULT_UPDATER_ENDPOINT` = `…/releases/latest/download/latest.json`；beta 端点由构建时 `HEADROOM_UPDATER_STAGING_ENDPOINTS` 注入，`release-macos.yml` 给的是 `…/releases/download/staging-rolling/latest.json`（0.9.46 可执行文件里能 `strings` 到这个地址）
- 分发: GitHub Releases（dmg + Tauri 更新包 `.app.tar.gz`）；Homebrew cask `headroom`（`auto_updates true`，所以 `HomebrewCaskSource` 让给下一个源）；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（auto_updates） | — | ✓ | — |
| **beta**     | —       | —        | —   | ○（需引擎改动，见下） | ○ |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 对 0.9.46 dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- 各版本的 bundle id / Team:
  - 0.1.8 起（2026-04-01）一直是 `com.extraheadroom.headroom`（`src-tauri/tauri.conf.json` 在 tag v0.1.8、v0.2.2、v0.3.10、v0.6.0、v0.6.7 处读）。0.1.0–0.1.7 是 `com.garm.headroom`，0.1.7 到 0.1.8 相隔 7 分钟。**缺口**：这些 tag 没有 GitHub release（最老的 release 是 v0.6.7，2026-07-08），拿不到真包核 Team，`BundleIDMigration` 要求两边 Team 都在真包上观测过，所以不加。这些副本自己的 Tauri updater 读的也是 `releases/latest/download/latest.json`（v0.1.7 的 `lib.rs`），会被厂商自己原地换成新 id
  - Team：0.9.45 / 0.9.46 / 0.9.47-rc.3 都是 `ZA6LNF9PF9`。**`v0.9.28-gt.2`（签名迁移测试版，release 正文「Signing-migration test build, signed by garmtech. Not for distribution」）是 `LG7M5PWA5X`**。厂商在试换签名 Team；真换了以后安装闸会拒掉所有旧副本（Team 不一致，安全失败，用户手动更新一次）。下一版发布时先核 Team
- 其他轨:
  - beta（rc）：同 bundle id。app 在三种情况下读 staging 端点：运行中的版本带 `-`（`is_prerelease_version`）、环境变量 `HEADROOM_BETA_CHANNEL` 为真、或 `~/Library/Application Support/Headroom/beta_channel` 文件存在（`beta_channel_enabled`，`lib.rs`）。rc 真包 `CFBundleShortVersionString` = `0.9.47-rc.3`。**未接入**，原因见 Channel 详情
  - `-gt.N` / `garmtech-rolling`：签名迁移测试，只从 `garmtech-rolling` 更新，不对外分发。pattern 不收；这种副本会被 stable rule 判成 stable、看到 0.9.46（channel-verify 实测 `UPDATE → 0.9.46`），一键会因 Team 不同被安装闸拒掉
  - `linux-preview`、`windows-preview`、`staging-rolling`、`garmtech-rolling`：都是 prerelease 指针 release，`/releases/latest` 不会返回它们，versionPattern 也不收
  - `vendor-wheels-v1`：非 prerelease，但只有两个 Python wheel（`hnswlib-0.8.0-…whl`），正文「Pre-built wheels for sdist-only PyPI packages. Consumed by headroom-desktop bootstrap via pip --find-links」。不是 app，有意不收
- 版本范围、主机下限: `LSMinimumSystemVersion` 14.0；dmg universal（`x86_64 arm64`）。DuoUpdater 只出 arm64（`App/project.yml` `ARCHS: arm64`），不需要架构门控。GitHub 上最老的 release 是 0.6.7，资产名从那时起一直是 `Headroom_<version>_mac.dmg`

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.extraheadroom.headroom` | 共享 | 默认 | `/releases/latest` | ✓ |
| beta    | `com.extraheadroom.headroom` | 共享 | 版本带 `-rc.N`；或 `beta_channel` 哨兵文件 / 环境变量 | 厂商：`staging-rolling/latest.json` | ○ |

- **rc 副本今天被当成 stable。** `ReleaseChannel.detect` 的通用规则不认 `-rc.N`（只有 CotEditor 有按 bundle id 的分支），channel-verify 对 0.9.47-rc.3 真包：`inferred stable`、`latest 0.9.46`、`status up to date`。不会降级（0.9.47-rc.3 > 0.9.46），但 rc.3 之后的 rc 不会提示；等 0.9.47 正式版发布，rc 副本会被提示 0.9.47 并能一键装上（厂商自己的 beta 端点在正式版发布时也会刷到正式版，`release-macos.yml`「Beta installs poll staging-rolling; a newer stable has to reach them too」）
- 接 beta 要改引擎：`ReleaseChannel.detect` 加一个 `com.extraheadroom.headroom` + `-rc.N` → `.beta` 的分支（CotEditor 的写法），再加一个 beta 源。beta 源应读厂商的 `staging-rolling/latest.json`（VendorProbe），不应读 GitHub 最新 rc tag：2026-10-22 rc.3 已发布，但 `staging-rolling/latest.json` 仍是 `0.9.47-rc.2`（rc.3 的 release 只有 mac 资产；`release-macos-staging.yml` 头注释：某平台缺席时 staging-rolling 继续提供上一个完整的 rc），读 tag 会领先厂商给 beta 用户的版本。只装了正式版、靠 `beta_channel` 哨兵文件选 beta 的副本还需要一个读该文件的 `ChannelBinding`。本 PR 不做

## 更新检测
- 源: `gglucass/headroom-desktop` GitHub Releases，`/releases/latest`
- 版本: tag `v0.9.46` → `^v([0-9]+(?:\.[0-9]+)+)$` → `0.9.46`，等于 `CFBundleShortVersionString` 和 `CFBundleVersion`（`release-macos.yml` 校验 `package.json` 与 `tauri.conf.json` 版本一致）。锚定：`v0.9.47-rc.3`、`v0.9.28-gt.2` 不匹配，`v1.0.0` 匹配
- 68 个非 prerelease release 中 67 个读得出（2026-10-22；分诊时 66 个读出 65 个），唯一读不出的是 `vendor-wheels-v1`，见上
- **`/releases/latest` 稳定性**: `release-macos.yml` 先把新版建成 prerelease（`/releases/latest` 看不到），等 macOS/Windows/Linux 都上传、证明（attestation）做完、`latest.json` 合并好，最后才 `gh release edit … --prerelease=false --latest`；`[publish: download-only]` 的版本一直是 prerelease。所以 `/releases/latest` 就是厂商 stable updater 被提供的版本。发版很频繁（0.9.24–0.9.46 在 2026-09-27 到 10-21 之间，约每天一版），rule 不需要别的处理
- 按平台发版（`[platforms: …]`）只收窄 `latest.json`，资产照常全挂。0.8.9–0.9.46 每版的 `headroom_platform_scope` 都含 `darwin-aarch64`/`darwin-x86_64`（逐版读 `latest.json`），所以目前没有「GitHub latest 有、mac 厂商端点不给」的版本；将来若出现，我们会比厂商多提示一版，装的仍是该版真包
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，同厂商 stable updater）

## 按架构 / 按 OS 分轨
- 架构: 一个 universal dmg（`lipo` `x86_64 arm64`）；`latest.json` 的 `darwin-aarch64` / `darwin-x86_64` 指向同一个 `_mac.app.tar.gz`
- `LSMinimumSystemVersion` 14.0；`latest.json` 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Tauri updater 只下整包 `.app.tar.gz` | `latest.json` 每个平台只有 `signature` + `url`（v0.9.46，2026-10-22） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会（直接原地换包） | 无（2026-10-22 真机运行 0.9.45 约 20 s，没有停放任何东西） | 不需要 |
| 证据 | `TauriPendingUpdate::install` 调 `download_and_install`：下载到内存、校验、原地替换 bundle，之后提示「installed and ready to restart」（`src/lib/appUpdate.ts`）。bundle 可写时（`silent_install_supported`）无需点击就会在后台装 | — | — |

- 后果：app 运行时，磁盘上的 bundle 可能已被它自己换成新版，进程仍是旧版，直到用户重启或「idle applier」（65 分钟无流量）重启
- 记录文件、容器: 无（不落盘停放）

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`（正文与仓库 `.github/release-notes/<version>.md` 相同）
- 结构化（2026-10-22，channel-verify `changelog pane`，从 0.9.45 起）: `source structured: 1 entries; newest 0.9.46: 1 items, headings []; first items ["Windows addons find Git Bash in custom i"]`
- 厂商正文是一句话的散文，没有标题和列表（最近 32 个正式版没有一个含 `#` 或 `- `），面板显示为一条，没有被压平的标题。0.9.15–0.9.35 的正文多数为空
- `release history 1 entries`
- 跟随 channel: rc 的正文是「Staging (release candidate) build. Not for general distribution.」，beta 没接，不涉及
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持，真机两轮通过（2026-10-22，本分支 `make cli` 的 duo）**
- 端到端:
  - 第一轮（不运行）: 0.9.45 → `duo check` `0.9.45 → 0.9.46 [GitHub, in-place]` → `duo install` `extracting verifyingCodeSignature installing done installed.` → 0.9.46、可执行文件 inode 变、`TeamIdentifier=ZA6LNF9PF9`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 0.9.46 包相同
  - 第二轮（运行中，没碰向导）: 启动 0.9.45（主进程 + `--crash-guard`，窗口「Welcome to Headroom」），`duo install` → `Still running the old code`；`duo restart Headroom` 后主进程和 crash guard 都换成新的，之后 10 s 磁盘一直是 0.9.46、签名有效
  - 本机没有 Headroom 旧数据；启动前后 `~/.claude/settings.json`、`~/.claude.json`、`~/.codex/config.toml`、`~/.zshrc`、`~/.zprofile`、`~/.profile` 字节相同，`~/Library/LaunchAgents` 不变。启用过客户端的副本被换包时 crash guard 会改写这些文件，这种情形没测
- 格式: dmg（UDIF zlib），根目录 `Headroom.app`。Pattern `^Headroom_[0-9]+(?:\.[0-9]+)+_mac\.dmg$`，kind `.dmg`，`-rc`/`-gt` 的 dmg 不匹配
- 嵌套: 没有。`Contents/MacOS` 只有 `headroom-desktop`，`Contents/Resources` 只有 `icon.icns`，没有 LoginItems / Helpers / XPC
- 签名: 0.9.45、0.9.46 都是 `TeamIdentifier=ZA6LNF9PF9`，`spctl` Notarized Developer ID，`codesign --verify` 通过
- 校验: GitHub 资产 `digest`。v0.9.46 dmg `sha256:00f76e4b3a3f0088d34bad9ab7f79dd95d4bbaaab1dbd97ffb6fd9b68de2bc63`、v0.9.45 dmg `sha256:bddd96293daa59487f3b7b08b092ac491ad9d781447c2370065eb285dede0c2a`，下载的 dmg `shasum -a 256` 各自相同（21723844 / 21717623 字节）
- **读的是**: 人人可手动下载的 GA
- 阻塞: 无

### 启动副作用
来源都是 `main` 上的源码（2026-10-22 读），除标注外都**未在真机观测**（真机结果见上「端到端」）：
- **会改 `~/.claude`、shell 配置、Codex 配置**——但只在用户在向导/Connectors 页启用某个客户端之后：`apply_client_setup("claude_code")`（`src-tauri/src/client_adapters.rs`）往 `~/.claude/settings.json` 的 `env` 写 `ANTHROPIC_BASE_URL`（指向本机代理）、`ENABLE_TOOL_SEARCH`，加 guard hook、`~/.claude/hooks/headroom-rtk-rewrite.sh`、`~/.claude/commands/remote-control.md`、statusline；往 `~/.zshrc` / `~/.zprofile` / `~/.bashrc` / `~/.bash_profile` / `~/.profile` 写 shell 块；Codex 则改 `~/.codex/config.toml`（provider 与 MCP）。启用后若 Claude Code 正在这台机器上用，它的请求会改走 Headroom 代理
- **退出与启动会自动改写这些文件**：每次退出 `clear_client_setups()` 撤掉接线；下次启动 `restore_client_setups()` 按 `remembered_clients` 重新接上；每小时、以及 `~/.claude/settings.json` 变化后 5 分钟内 `repair_client_setups()` 自愈。所以只要 `~/Library/Application Support/Headroom/` 里有旧的启用记录，单纯启动就会改 `~/.claude/settings.json`
- **崩溃守护进程**：启动时再起一份自己（`headroom-desktop --crash-guard`），读 stdin 等主进程退出，然后把客户端接线撤掉再退出。主进程被 duo 退出/替换时它也会写一次配置文件
- **首启**：没有 Python 运行时时不自动装（`warm_runtime_on_launch` 直接返回，交给向导）；会显示「Welcome to Headroom」窗口。向导里装运行时会下载 python-build-standalone、`pip` 装 headroom 及 `vendor-wheels-v1` 的 wheel、rtk、codebase-memory-mcp（可执行文件里的下载地址）
- **登录项**：向导默认打开「开机启动」，`tauri-plugin-autostart` 写 `~/Library/LaunchAgents/Headroom.plist`（参数 `--autostart`，app 会把 `ProcessType` 改成 `Interactive`）。指向 app 自己的可执行文件，不是常驻 helper，换包后下次登录启动的是新包。从 dmg 直接运行时拒绝打开
- **自更新器**：见「已停放整包」。运行中的旧版每小时检查一次，bundle 可写时静默原地换包。它读的端点与 rule 相同，所以只会装同一个 latest，不会比 duo 装得旧；唯一的例外是 duo 刚装上一个新发布的版本，而旧进程手里还拿着上一轮的检查结果、正在下载——窄窗口，未实测
- **版本变化后的首启**：Python 引擎 pin 变了时，启动会先做运行时升级（「Preparing update」界面，0.9.45 正文「The first start after updating can take a few minutes」）
- **数据目录**：`~/Library/Application Support/Headroom/`、`~/.headroom`、`~/Library/Logs/Headroom`（cask 的 zap 列表）
- **卸载**：可执行文件支持 `--uninstall`（无界面撤销对其他工具的改动）

### 推荐的两轮真机步骤
0. 先备份：`~/.claude/settings.json`、`~/.claude.json`、`~/.codex/config.toml`（若有）、`~/.zshrc` `~/.zprofile` `~/.bashrc` `~/.bash_profile` `~/.profile`；确认 `~/Library/Application Support/Headroom/` 不存在（存在就先挪开，否则启动会恢复旧的客户端接线）；记 `sfltool dumpbtm` 和 `ls ~/Library/LaunchAgents`
1. **不运行**：`ditto` 0.9.45 到 `/Applications/Headroom.app`，不启动 → `duo check headroom` → `duo install headroom --yes --json` → 0.9.46，核 inode、`codesign --verify --deep --strict`、`spctl -a -vv`、Team、`diff -r` 对厂商 0.9.46 bundle
2. **运行中**：重放 0.9.45 并启动，**不要走向导、不要启用任何客户端**（关掉欢迎窗口即可）→ `duo install` → `duo restart Headroom` → 10 s 内轮询磁盘版本；之后 `pgrep -fl headroom-desktop` 确认 `--crash-guard` 进程随旧主进程退出；对比第 0 步的备份，`~/.claude` 与 shell 文件应不变
   - 「暂存一个比 latest 旧的版本」造不出来：Tauri 不落盘停放；更新端点是编译期常量（`option_env!`），运行时只有 `HEADROOM_BETA_CHANNEL` 能把它切到 `staging-rolling`（今天是 0.9.47-rc.2，比 latest 新）。所以碰撞检查只能看「duo 装完后旧进程的静默安装会不会把磁盘换回旧版」：它读的是同一个 latest，预期不会
3. 收尾：退出 app，检查 `~/Library/LaunchAgents/Headroom.plist` 有没有被写（没走向导应没有），删掉第 2 步新建的 `~/Library/Application Support/Headroom/`，恢复第 0 步挪开的目录

## 已知问题
- beta（rc）副本被当成 stable：不降级，但在下一个正式版之前看不到新 rc。见 Channel 详情
- 厂商在试另一个签名 Team（`LG7M5PWA5X`，`v0.9.28-gt.2`）。正式切换后旧副本的一键会被 Team 闸拒掉
- `com.garm.headroom`（0.1.0–0.1.7）没有可下载的真包，未加迁移

## 建议下一步
1. 可补一轮：启用过 Claude Code 客户端的副本被换包时，crash guard 撤掉 / 重接接线的前后对比
2. 要接 beta 时（引擎改动）：`ReleaseChannel.detect` 加 `com.extraheadroom.headroom` 的 `-rc.N` → `.beta` 分支；beta 用 VendorProbe 读 `https://github.com/gglucass/headroom-desktop/releases/download/staging-rolling/latest.json`（`"version"`、`platforms.darwin-aarch64.url` 是 `.app.tar.gz`）；`beta_channel` 哨兵文件要 `ChannelBinding`
3. 每次新正式版先核 Team 是否还是 `ZA6LNF9PF9`

## 如何复验
```
gh api repos/gglucass/headroom-desktop/releases/latest -q .tag_name                      # → v0.9.46
gh release view v0.9.46 -R gglucass/headroom-desktop --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Headroom_0.9.46_mac.dmg          # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify Headroom_0.9.45_mac.dmg --expect stable   # → GitHub，UPDATE → 0.9.46
swift run --package-path application-test channel-verify Headroom_0.9.46_mac.dmg --expect stable   # → up to date
swift run --package-path application-test channel-verify Headroom_0.9.47-rc.3_mac.dmg    # → inferred stable，up to date（beta 未接）
.claude/skills/coverage-discovery/scripts/check-bundle.sh Headroom_0.9.46_mac.dmg        # → ZA6LNF9PF9，Notarized，archs x86_64 arm64
curl -sL https://github.com/gglucass/headroom-desktop/releases/download/staging-rolling/latest.json | jq .version
```

2026-10-22 的 channel-verify 原文（0.9.45 dmg）:
```
  detected channel  → stable
  ✓ detection matches --expect stable
    winning source  GitHub
    latest          0.9.46
    download        https://github.com/gglucass/headroom-desktop/releases/download/v0.9.46/Headroom_0.9.46_mac.dmg
    release notes   0 chars inline, changelogURL https://github.com/gglucass/headroom-desktop/releases/tag/v0.9.46
    changelog pane  source structured: 1 entries; newest 0.9.46: 1 items, headings []; first items ["Windows addons find Git Bash in custom i"]
    status          UPDATE → 0.9.46
```
