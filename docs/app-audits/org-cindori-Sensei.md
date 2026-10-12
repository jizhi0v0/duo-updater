# Sensei

> 审计 2026-10-12。Cindori 的三款 app 之一，另两款见 [Backdrop](com-cindori-Backdrop.md)、
> [Trim Enabler](org-cindori-TrimEnabler4.md)。

## 基本信息
- Bundle ID: `org.cindori.Sensei`
- Team ID: `ZQK6SX26CE`（Developer ID Application: Cindori AB；2.1.2 与 2.1.3 两个真包一致）
- 观测版本: `2.1.3` (build `141`，最新) / `2.1.2` (build `139`，上一版)
- 自更新机制: Sparkle（`SUFeedURL` + `SUPublicEDKey`），默认弹窗询问，不自动下载
- 架构: universal（`x86_64 arm64`）；`LSMinimumSystemVersion` = `14.0`
- 内嵌: `Contents/Library/LoginItems/Sensei Monitor.app`（`org.cindori.SenseiMonitor`，`LSUIElement` = true，
  首次启动时以 SMAppService 登录项注册，作业名 `org.cindori.SenseiMonitor`）
- 授权: Paddle，首次启动开 14 天试用
- 不开源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic，无 recipe） | ✗（cask `sensei` 为 `auto_updates: true`，按设计让路） | —（`itunes.apple.com/lookup?bundleId=` 返回 0） | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify`：`winning source  Sparkle`）。

## Channel 详情

只有一条轨：feed `https://cdn.cindori.com/apps/sensei/updates/update.xml` 17 个 item，**0 个 `<sparkle:channel>`**；
官网、cask 都没有 beta 入口。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.cindori.Sensei` | — | `SUFeedURL` | — | ✓ |

## 更新检测
- 源: `SparkleAppcastSource`（generic）
- 端点: `https://cdn.cindori.com/apps/sensei/updates/update.xml`
- `feed-discover` 判定: `declared`
- 上一版 2.1.2 → `duo check`：`Sensei  2.1.2  →  2.1.3  [Sparkle, in-place]`
- 注意事项:
  - 同一个短版本号可能有两个 build：`2.1.1` 有 137/138，`2.0` 有 124/125，`1.6.2`、`1.6.0` 也各有两个。
    changelog 按短版本去重（13 条），release history 按 item 记 17 条。
  - 每条都有 `minimumSystemVersion`（2.0 起 `14.0`，1.6–1.7 为 `13.0`，1.5.14 为 `11.0`），没有 `maximumSystemVersion`、
    `phasedRolloutInterval`、`criticalUpdate`。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2） | 无 | — |
| 证据 | 内嵌 `Sparkle.framework` | 2026-10-12 feed 17 个 item 无 `<sparkle:deltas>`；`channel-verify` `deltas 0` | 没有可消费的补丁，一键走整包 dmg |

## Changelog
- 来源: Sparkle inline（`<description>` 里的 HTML，CDATA）
- 结构化: `source structured: 13 entries; newest 2.1.3: 13 items, headings ["Fixed", "Improved"]`
- 每条开头有一个只写版本的 `<h2>`（`2.1.3 (141) (2026-09-24)`、`2.1.2 (139)`）。2.1.2 那种 `<h2>` 后面直接跟列表的，
  解析器原本会把它当成第一条条目；本次在 `AppcastHTMLChangelogParser` 里丢掉只重复本条版本号的标题
  （测试 `testVersionAndBuildHeadingIsNotAnItem` 等三条）。
- 跟随 channel: — （单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持
- 读的是: 人人可手动下载的 GA（feed 的最新 item，与官网 `cdn.cindori.com/apps/sensei/Sensei.dmg` 同一构建）
- 格式: dmg（Sparkle enclosure）
- 校验: feed 带 `sparkle:edSignature`，无独立摘要字段；装前 Team ID 闸
- 端到端（2026-10-12，`duo` 由当时的 `make cli` 构建）:
  1. **不运行**：2.1.2 放进 `/Applications` → `duo install /Applications/Sensei.app --yes --json` →
     `{"applied":true,"bytesDownloaded":37801138,"outcome":"installed","route":"sparkle"}`，11 s；
     结果 2.1.3 (141)，inode 变更，`codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，
     Team `ZQK6SX26CE`，`diff -r` 与厂商 dmg 里的 bundle 一致，`duo backups` 有 2.1.2 备份。
  2. **运行中**：启动 2.1.2（主程序 + Sensei Monitor 都起来，Sparkle 弹「2.1.3 可用」询问窗，未自动下载暂存）→
     `duo install` 同样 `installed`，磁盘变 2.1.3 并保持 10 s 不回退。`duo restart Sensei` 返回
     `still running — likely a save prompt, left it alone`：首次启动的试用期提示是模态窗，挡住了正常退出，
     duo 按设计没有强杀。这是首次启动才有的窗。

## 已知问题
- **Sensei Monitor 在替换后继续跑旧代码，直到主程序下次启动**。它在 `Contents/Library/LoginItems/` 下，
  `NestedAppGuard` 对登录项按设计放行，`AppRestarter` 只重启 `.regular` 的内嵌 app，所以 duo 不碰它。
  实测：主程序退出、Monitor（build 139）仍在跑时 `duo restart Sensei` 返回 `not running — nothing to restart`；
  随后启动新版 Sensei（141），旧 Monitor 以 exit 0 退出（`launchctl print gui/<uid>/org.cindori.SenseiMonitor`：
  `last exit code = 0`）。也就是说厂商自己的主程序在启动时清掉旧 Monitor，Sparkle 自更新依赖的也是这一点。
  Monitor 只是菜单栏里的统计显示，跑旧代码期间不会损坏数据。
- Monitor 和主程序都通过 XPC 连 `org.cindori.Sensei.Daemon.stats`，这个服务要先装特权 helper（需要管理员密码）。
  没装时两边都会持续报 `connectionInvalid`，与更新无关（一键之前就在报）。

## 建议下一步
1. 无代码改动需要。changelog 标题修正已随本次接入合入。

## 如何复验

```bash
swift run --package-path application-test feed-discover <Sensei.app>   # → declared
swift run --package-path application-test channel-verify <Sensei.dmg>  # → winning source Sparkle, latest 2.1.3
curl -sS https://cdn.cindori.com/apps/sensei/updates/2.1.2-139/Sensei.dmg -o Sensei-2.1.2.dmg  # 上一版，做一键端到端
```
