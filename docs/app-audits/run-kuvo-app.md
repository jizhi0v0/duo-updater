# Kuvo

> 审计 2026-10-12（项目 2026-10-11 发出 0.1.0–0.1.2，三版同一天）。

## 基本信息
- Bundle ID: `run.kuvo.app`
- Team ID: `C8Y523R7T5`（Developer ID Application: Serhat Andiç；0.1.0 / 0.1.1 / 0.1.2 三个真包一致）
- 观测版本: `0.1.2`（最新）/ `0.1.1`（上一版）。`CFBundleVersion` 与 `CFBundleShortVersionString` 相同
- 自更新机制: Sparkle 2（`SUFeedURL` + `SUPublicEDKey`，`SUEnableAutomaticChecks` = true；
  `SPUStandardUpdaterController(updaterDelegate: nil)`，无 channel 委托）
- 架构: arm64 only；`LSMinimumSystemVersion` = `15.0`
- 内容: 原生 Docker 前端，用 Virtualization.framework 跑 Alpine VM 里的 Docker 引擎
- 开源: `github.com/serhatandic/kuvo`（默认分支 `main`）。以下「settled from source」均读自 `main`
  （与 `v0.1.1` 相比只有 `.github/workflows/release.yml` 不同）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic，无 recipe） | —（无 cask） | — | —（feed 本身就是 release 附件，Sparkle 先应答，不需要 rule） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify`：`winning source  Sparkle`）。

## Channel 详情

只有一条轨。**settled from source**：
- `.github/workflows/release.yml` 只接受 `vMAJOR.MINOR.PATCH` 标签，且必须在 `main` 上；没有 prerelease 路径。
- `scripts/appcast.sh` 每次只写一个 `<item>`，没有 `<sparkle:channel>`。
- `Sources/Kuvo/Updates.swift` 不设 updater delegate，没有 `allowedChannels`。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `run.kuvo.app` | — | `SUFeedURL` | — | ✓ |

## 更新检测
- 源: `SparkleAppcastSource`（generic）
- 端点: `https://github.com/serhatandic/kuvo/releases/latest/download/appcast.xml`（302 到最新 release 的 `appcast.xml` 附件）
- `feed-discover` 判定: `declared`
- 上一版 0.1.1 → `channel-verify`：`status  UPDATE → 0.1.2`
- 注意事项:
  - feed 永远只有一个 item（`appcast.sh` 只写当前版本），所以 release history 恒为 1 条。
  - enclosure 指向**带版本号**的 `releases/download/v<VERSION>/Kuvo.dmg`，与 feed 同一次发布生成，带 `sparkle:edSignature`。
  - `minimumSystemVersion` = `15.0`，无上限。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2） | 无 | — |
| 证据 | 内嵌 `Sparkle.framework` | `appcast.sh` 不生成 `<sparkle:deltas>`；2026-10-12 feed 无 deltas，`channel-verify` `deltas 0` | 没有可消费的补丁，dmg 只有 3.4 MB |

## Changelog
- 来源: **无**。`channel-verify`：`changelog pane  none — the pane says there are no release notes`
- feed 只有 `sparkle:fullReleaseNotesLink`（指向 GitHub release 页），没有 `<description>`；`SparkleAppcastSource` 不读这个字段。
- GitHub release 正文是发版 workflow `--generate-notes` 加一行固定说明（"Requires macOS 15 or later on Apple silicon…"），
  外加 compare 链接，三版都没有实际内容；仓库里没有 CHANGELOG。
- **✗ 做不了**：厂商没有发布任何更新说明。不写 recipe。厂商以后在 release 正文写说明了，再加 GitHub changelog recipe。

## 一键安装
- 状态: 支持
- 读的是: 人人可手动下载的 GA（feed 指向的 dmg 与 `releases/latest/download/Kuvo.dmg` 同一文件）
- 格式: dmg
- 校验: `sparkle:edSignature`；GitHub release 资产带 `digest`（`sha256:1a58b2a2…` for 0.1.2）；装前 Team ID 闸
- 端到端（2026-10-12）:
  1. **不运行**：0.1.1 放进 `/Applications` → `duo install /Applications/Kuvo.app --yes --json` →
     `{"applied":true,"bytesDownloaded":3412123,"outcome":"installed","route":"sparkle"}`，7 s；结果 0.1.2，inode 变更，
     `codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，Team `C8Y523R7T5`，`diff -r` 与厂商 dmg 一致，
     `duo backups` 有 0.1.1 备份。
  2. **运行中（VM 在跑、引擎应答 `_ping`）**：`duo install` 同样 `installed`，磁盘 0.1.2，旧进程照常服务。
     首次 `duo restart Kuvo` 返回 `still running — likely a save prompt, left it alone`（见下面的弹窗）；弹窗答掉后
     `duo restart Kuvo` → `restarted`，5 s 完成，新进程报 `Version="0.1.2"`，引擎 5 s 内重新应答 `_ping`。

## 已知问题
- **首次启动的「Use Kuvo for the docker command?」弹窗会挡住退出**（settled from source：`ContentView.swift` 的 `.alert`，
  引擎连上后出现）。默认按钮是「Use Kuvo」（回车即接受），接受会把 `~/.docker/config.json` 的 `currentContext` 改成 `kuvo`；
  「Not Now」只记 `dockerContext.asked`，不碰 `~/.docker`。弹窗开着时 restart 不会强杀，这是 duo 的既定行为。
- **退出会延迟**：引擎没停时 `applicationShouldTerminate` 返回 `.terminateLater`，请 VM 关机，最多等 15 s 后强停
  （`KuvoApp.swift`、`VirtualMachine.swift`）。实测引擎空载时退出 5 s 内完成。
- 启动时自动做的事（与更新无关，测试时需知道）：在 `/opt/homebrew/bin` 或 `/usr/local/bin` 建 `kuvo` symlink（都不可写时退到
  `~/.kuvo/bin` 并往 `~/.zprofile` 追加 PATH）；下载约 41.5 MB Alpine 镜像；在 `~/Library/Application Support/Kuvo/` 建
  64 GiB 稀疏磁盘；VM 以读写方式共享整个 `/Users`；无条件删除 `~/.terrarium`（旧名遗留）。没有登录项、LaunchAgent 或特权 helper
  （启动前后 `sfltool dumpbtm` 无差异）。

## 建议下一步
1. 无代码改动。厂商开始写 release 正文时，补一个 GitHub changelog recipe。

## 如何复验

```bash
swift run --package-path application-test feed-discover <Kuvo.app>   # → declared
swift run --package-path application-test channel-verify <Kuvo 0.1.1 .app>   # → winning source Sparkle, UPDATE → 0.1.2
curl -sSLO https://github.com/serhatandic/kuvo/releases/download/v0.1.1/Kuvo.dmg   # 上一版
```
