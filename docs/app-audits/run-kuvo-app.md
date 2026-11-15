# Kuvo Box

> 初审 2026-10-12；2026-11-15 修订更新源。Docker 产品现名 Kuvo Box，仍为 `run.kuvo.app`，与 AI 编程产品 Kuvo Code（`run.kuvo.code`）分别更新。

## 基本信息
- Bundle ID: `run.kuvo.app`
- Team ID: `C8Y523R7T5`（Developer ID Application: Serhat Andiç；0.1.0 / 0.1.1 / 0.1.2 的历史包与本轮 0.1.3 一致）
- 观测版本: 当前 `0.1.3` / 上一版 `0.1.2`。`CFBundleVersion` 与 `CFBundleShortVersionString` 相同
- 自更新机制: Sparkle 2（`SUFeedURL` + `SUPublicEDKey`，`SUEnableAutomaticChecks` = true；
  `SPUStandardUpdaterController(updaterDelegate: nil)`，无 channel 委托）
- 架构: arm64 only；`LSMinimumSystemVersion` = `15.0`
- 内容: 原生 Docker 前端，用 Virtualization.framework 跑 Alpine VM 里的 Docker 引擎
- 官方仓库: [`serhatandic/box`](https://github.com/serhatandic/box)；早期 `serhatandic/kuvo` 地址现在服务另一产品 Kuvo Code。下文标明日期的历史实测保留原版本语境。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic + 旧 feed 修正） | — | — | —（Sparkle 先应答，不需要版本 rule） | — |

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
- 已发布包仍声明 `https://github.com/serhatandic/kuvo/releases/latest/download/appcast.xml`；`SparkleFeedCatalog.supersededFeeds` 只对 `run.kuvo.app` + 这一精确地址改用 `https://github.com/serhatandic/box/releases/latest/download/appcast.xml`。
- `feed-discover` 判定: `declared`
- 早期 0.1.1 → 0.1.2 的检测记录来自 2026-10-12；本轮 0.1.2 → 0.1.3 的完整生产链及 VM 结果见历史与实测。
- 注意事项:
  - feed 当前只有一个 item（`appcast.sh` 只写当前版本），release history 仅来自该条。
  - enclosure 指向**带版本号**的 `releases/download/v<VERSION>/Kuvo.dmg`，带 `sparkle:edSignature`；当前 feed 内绝对地址仍写旧仓库，生产解析和验证共用已登记仓库搬迁规则，将 release 路径迁至 `serhatandic/box`。版本、文件名、大小、签名不变。
  - `minimumSystemVersion` = `15.0`，无上限。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2） | 无 | — |
| 证据 | 内嵌 `Sparkle.framework` | `appcast.sh` 不生成 `<sparkle:deltas>`；2026-10-12 feed 无 deltas，`channel-verify` `deltas 0` | 没有可消费的补丁，dmg 只有 3.4 MB |

## Changelog

当前 0.1.3 feed 使用 `<description sparkle:format="markdown">` 内联说明，包含 What's new / Fixes；由通用 Sparkle Markdown 路径解析。官方仓库也已提供 `CHANGELOG.md`，旧审计的「没有更新说明」结论仅适用于当时的 0.1.0–0.1.2。

`ChangelogCatalog` 以官方 Box releases 页兜底；内联原生条目优先。本轮 `channel-verify` 输出 `source structured: 1 entries; newest 0.1.3: 10 items, headings ["What\'s new", "Fixes"]`。VM 原生工作台确认两组标题及条目均保留，见[验证记录](../../verify/kuvo-identities/README.md)。

## 一键安装
- 状态: 支持
- 读的是: 官方 `serhatandic/box` 的 GA 安装包；修正后的 feed 下载地址仍指向同一版本的 `Kuvo.dmg`。
- 格式: dmg
- 校验: `sparkle:edSignature`；GitHub release 资产带 `digest`（`sha256:1a58b2a2…` for 0.1.2）；装前 Team ID 闸
- 本轮端到端（2026-11-15，独立 Apple Silicon macOS VM）：0.1.2 → 0.1.3，未运行和运行中两轮均为 `applied:true / outcome:installed / route:sparkle`，每轮下载 3,659,402 bytes。运行中 `duo restart` 返回 `restarted`，磁盘版本连续 10 秒保持 0.1.3。严格深度验签、Notarized Developer ID、Team / ID 检查通过；与官方包文件比较无差异。VM 的 `KeepBackups=0`，未产生新的 Kuvo 备份。原始回执见[验证记录](../../verify/kuvo-identities/README.md)。
- 历史端到端（2026-10-12）:
  1. **不运行**：0.1.1 放进 `/Applications` → `duo install /Applications/Kuvo.app --yes --json` →
     `{"applied":true,"bytesDownloaded":3412123,"outcome":"installed","route":"sparkle"}`，7 s；结果 0.1.2，inode 变更，
     `codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，Team `C8Y523R7T5`，`diff -r` 与厂商 dmg 一致，
     `duo backups` 有 0.1.1 备份。
  2. **运行中（VM 在跑、引擎应答 `_ping`）**：`duo install` 同样 `installed`，磁盘 0.1.2，旧进程照常服务。
     首次 `duo restart Kuvo` 返回 `still running — likely a save prompt, left it alone`（见下面的弹窗）；弹窗答掉后
     `duo restart Kuvo` → `restarted`，5 s 完成，新进程报 `Version="0.1.2"`，引擎 5 s 内重新应答 `_ping`。

## 已知问题
- **厂商自更新器仍指向另一个产品**：VM 启动 Box 0.1.2 时，其 Sparkle 弹窗错误提供 Code 0.7.2。Duo 修正自己的读取和下载路径，不改写厂商签名包中的 `SUFeedURL`；不要通过 Box 的这个弹窗安装 Code。本轮未让 Box 自更新器下载错误产品。
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

已按精确旧 feed 修正产品归属；保留 Bundle ID 匹配，不将 Box 迁移到 Code。新地址、下载地址和更新密钥需要随厂商后续发布复核。

夜间 feed 校验将这条记录标记为 `declaredFeedServesDifferentProduct`：Box 与 Code 的版本序列不可比较，因此只跳过版本先后判断；Box feed 的可用条目、系统要求和下载地址仍照常监测。若厂商改变旧地址的产品归属，需重新核对并更新此标记。

## 历史与实测

### 2026-11-15：仓库搬迁，两个产品保持独立

- 官方 Box 仓库保留 0.1.0–0.1.3 的 Docker 应用；官方 Code 仓库最早 0.1.0 为独立 AI 编程产品，版本范围重叠，不能登记为 Bundle ID 迁移。
- 真实 Box 0.1.3 包仍为签名 ID `run.kuvo.app`、Team `C8Y523R7T5`、arm64、最低 macOS 15，严格深度验签通过，Gatekeeper 报 Notarized Developer ID。
- Box 与 Code 共用 Team 和 Sparkle key `uG/YbzL4kf+DAYCiTTfK8ztEOBo96hkEAuKk9rw9BE4=`；安装必须继续检查产品 ID，不能仅凭同团队或同 key 接受跨产品包。
- 旧 feed 返回 Code 0.7.2，Box 的正确 feed 返回 0.1.3。Box feed 内旧 enclosure 地址返回 HTTP 404；官方 Box 仓库的同 tag / 同文件下载可用。
- 离线回归在修复前分别复现旧 feed 未更换和旧下载 URL 未迁移；修正后两条生产路径均通过。独立 macOS VM 的旧客户端也将 Box 0.1.2 误报为可更新到 Code 0.7.2，记录用于与修复后的结果对照。

- 本轮 VM 复验完成：旧 CLI 误报 0.7.2，新 CLI 检测 0.1.3，静止与运行中升级、重启、签名和原生日志均通过。Box 启动后的 Docker 业务与嵌套虚拟化没有作为本轮验收内容；不沿用历史引擎 `_ping` 结果宣称本轮已覆盖。
- 本轮未构造旧版暂存包与新版安装的碰撞；Box 的厂商 updater 指向错误产品，因此没有武装该下载。限制与原始回执见[verify/kuvo-identities](../../verify/kuvo-identities/README.md)。

## 如何复验

```bash
swift run --package-path application-test feed-discover <Kuvo.app>   # → declared
swift run --package-path application-test channel-verify <Kuvo-0.1.2.dmg> --expect stable   # → Sparkle, UPDATE → 0.1.3
curl -sSLO https://github.com/serhatandic/box/releases/download/v0.1.2/Kuvo.dmg   # 上一版
```
