# 四个应用接入验收（2026-11-16）

实现源代码：`c87031be7723be261516ffdc73d16ff7545a0746`。其后合入的 main 更新只涉及既有夜扫状态文件，没有替换既有 identity、签名锚或失败计数。

## 产品结果

隔离的 Apple Silicon、macOS 27.2（26B123）VM，使用生产 CLI 安装与重启路径：

| App / 轨道 | 检测 | 一键安装 | 结构化更新日志 |
|---|---|---|---|
| electerm stable | 5.10.0 提供 5.11.8；新版最新 | 停用及运行中两轮通过 | GitHub 正文，双语分节保留 |
| Suspicious Package stable | 4.7 提供 4.8；新版最新 | 停用及运行中两轮通过 | 官网 37 条历史；嵌套列表和尾部说明保留 |
| RapidAPI / Paw stable | 4.5.4 提供 4.5.5；新版最新 | 停用及运行中两轮通过，包含 EdDSA | 官网最近 40 条，Fixes / New 等标题保留 |
| Mattermost stable | 6.3.2 提供 6.4.0；新版最新 | 停用及运行中两轮通过 | 官方文档最近 40 条，类别、平台和补丁边界保留 |
| Mattermost 旧签名 ID | 4.1.0 提供 6.4.0 | 原地迁移为 `Mattermost.Desktop` 通过 | 复用 stable 说明 |
| Mattermost RC | 6.2.5-rc.4 提供 rc.5；新版仍为 RC 且最新 | 运行中安装、显式重启通过 | 无独立 RC 说明，保持空状态 |
| Mattermost nightly | 日期 20261115 提供 20261116；新版仍为 nightly 且最新 | 停用安装、启动新版通过 | 无独立逐日说明，保持空状态 |

运行中安装沿用现有原地换包行为：旧进程继续运行，随后显式 `duo restart` 切换到新进程，再检查版本与更新状态。没有把原地换包误记成自动退出/重开。

三个应用的合成 UserDefaults 标记、Mattermost 的合成数据文件均保留。七组最终包的严格代码签名、公证和预期 Team 均通过，见 [VM 收据](final-vm-receipt.json)。未测试真实账号、服务器连接、云数据、许可证迁移或全部业务功能。Paw 厂商明确不支持 macOS 27+；这里的安装/启动通过不等于厂商兼容性认证。

旧 ID 迁移后没有可供恢复的长期备份；实际 `duo backups restore` 返回没有备份，未把它列为恢复成功。签名/版本边界和 journal 的中断恢复分类由单元测试覆盖。

## Mattermost 完整版本

新 RC 的原始 plist 短版本都是 `6.2.5`，日期 nightly 都是 `6.5.0`；`app.asar/package.json` 保留完整 RC/日期版本。生产 scan/check 的关键输出：

```text
short version   6.2.5-rc.4
detected channel → rc
winning source  → Vendor
latest          → 6.2.5-rc.5
status          → UPDATE → 6.2.5-rc.5

short version   6.2.5-rc.5
detected channel → rc
status          → up to date

short version   6.5.0-nightly.20261115
detected channel → nightly
latest          → 6.5.0-nightly.20261116
status          → UPDATE → 6.5.0-nightly.20261116

short version   6.5.0-nightly.20261116
detected channel → nightly
status          → up to date
```

6.1.0-rc.4 这个仍在 plist 保留后缀的真实旧包，也由官方 RC 源提供 6.2.5-rc.5。没有使用 GitHub 已停在 6.1.0-rc.4 的列表冒充当前 RC。

路径模式的 `channel-verify` 只手工读取 plist，并额外要求同 bundle 的 VendorProbe 回答；混合来源的 stable 和被 coerce 的版本会触发其辅助失败。Mattermost 采用已有 `--scan` / `--check` 生产模式与实际安装结果验收；stable pane 的结构化输出另行读取，没有把辅助失败记为通过。

## 夜扫与实时验证

[安装字节记录](install-report.json)包含精确 **7 个** recipe ID，均 `ok`，没有 OS skip、unresolved 或 warning：

- `github:electerm/electerm:stable`
- `vendor:com.mothersruin.SuspiciousPackageApp:stable`
- `sparkle:com.luckymarmot.Paw:stable:ed25519`
- `sparkle:com.luckymarmot.Paw:stable:legacy-dsa`
- `github:mattermost/desktop:stable`
- `vendor:Mattermost.Desktop:rc`
- `vendor:Mattermost.Desktop:nightly`

finding ID 加 `install:` 前缀。Paw 的两个密钥组保持独立；旧 DSA-only 组没有 Ed key，明确记录在 `unavailablePublicKeys`，仍检查下载包身份。Vendor/GitHub 不重复登记到通用 feed 清单。Mattermost 的两个 unsigned 旧 ID 保留检测，不提供跨 ID 安装；它们不冒充安装字节检查成功。

[实时解析记录](feed-report.json)列出精确 **14 项** feed / vendor / GitHub / changelog 检查，全部 `ok`。命令按应用分别运行：

```sh
duo verify --only luckymarmot
duo verify --only electerm
duo verify --only SuspiciousPackageApp
duo verify --only mattermost
duo verify-install --only luckymarmot
duo verify-install --only electerm
duo verify-install --only SuspiciousPackageApp
duo verify-install --only mattermost
```

CLI 从变更 checkout 构建、签名并写入 source stamp，没有使用 stale-binary 例外。首三个应用的安装轮次使用 `35e18c7e`，随后最终 CLI 再核对检测与 pane；Mattermost 的同基线 RC/nightly 安装使用 `c87031be`，其余应用安装路由未被后续版本读取变更改变。首三个应用的安装字节检查在 `f3d91623` 完成，安装路由之后未改变；当前 Mattermost 字节检查和最终实时解析在 `c87031be` 完成。JSON 收据保留各项验证源版本。新 ID 的这些结果是首次观察，不冒充既有身份锚的连续性校验。

## 检查与审查

- 最终定向 Core 检查 70 项通过，另有 MDX Markdown 来源约束 1 项通过；feed inventory 的 7 项测试通过。
- 本地 App 365 项与脚本检查通过。完整本地 Core 运行受启动盘低于生产 10 GiB 安全余量影响，没有降低余量或将空间失败改成通过。
- 干净 CI runner 的完整 `make test-swift` 已通过（Core 7,553 项，1 项已登记 known issue；CLI 731 项），见 [CI 运行](https://github.com/jizhi0v0/duo-updater/actions/runs/43894732017)；最终完整检查状态随 [PR #2052](https://github.com/jizhi0v0/duo-updater/pull/2052) 的当前 head。
- 独立模型 `gpt-6-astra` 对 `44297401..c87031be` 的本地对抗审查已完成，无剩余发现。覆盖 trust（签名、旧 ID、渠道隔离）、untrusted-input（ASAR 产品标记、边界、溢出及缓存替换）和 data-loss（RC journal / 重启恢复比较）。

审查修复保留在回归用例中：Paw 的 h5-only 改名公告、Suspicious Package 列表后的说明、Mattermost 当前 vendor RC 选择，以及同数字版本下未变化 RC 不能被判为已完成新版安装。

## 清理与范围

测试安装位于隔离 VM，测试后退出并移入该 VM 的任务专属废纸篓目录（[清理记录](cleanup.json)）；原始包、日志和只读副本保留为验收材料。主机的应用安装没有被替换。历史 Suspicious Package Preview、Paw MAS 许可迁移、早期未签名 Mattermost 和特殊旧版本的边界继续见各应用审计，不把它们隐含计入当前一键覆盖。
