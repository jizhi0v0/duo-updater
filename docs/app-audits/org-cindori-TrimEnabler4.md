# Trim Enabler

> 审计 2026-10-12。Cindori 的三款 app 之一，另两款见 [Sensei](org-cindori-Sensei.md)、
> [Backdrop](com-cindori-Backdrop.md)。

## 基本信息
- Bundle ID: `org.cindori.TrimEnabler4`
- Team ID: `ZQK6SX26CE`（证书名 Developer ID Application: Oskar Groth；与 Sensei、Backdrop 的 Cindori AB 同一 Team；4.3.5 与 4.3.6 一致）
- 观测版本: `4.3.6` (build `26`，最新，2021-01-02) / `4.3.5` (build `25`，上一版)
- 自更新机制: DevMate（`DevMateKit.framework` 内的 Sparkle），Info.plist **没有** `SUFeedURL`
- 架构: **x86_64 only**（Apple silicon 上走 Rosetta）；`LSMinimumSystemVersion` = `10.9`
- 内嵌: `Contents/Library/LaunchServices/org.cindori.TEHelper`（SMJobBless 特权 helper）。**首次启动就会安装**：2026-10-12 启动 4.3.5 的同一分钟里，
  `/Library/PrivilegedHelperTools/org.cindori.TEHelper` 和 `/Library/LaunchDaemons/org.cindori.TEHelper.plist` 出现
  （`sfltool dumpbtm` 列为 `16.org.cindori.TEHelper`）。一键只换 app，不动这个 root helper；app 新版启动时是否升级它，没有验证。
  端到端测试后要清掉它（需要 root）：`launchctl bootout system/org.cindori.TEHelper`，再删上面两个文件
- **已停止开发**：4.3.6 的 release notes 写明 Big Sur 是它支持的最后一个 macOS，建议改用 Sensei。官网仍提供下载。
  在 macOS 27 上启动时系统弹通知：这个版本在 macOS 28 将无法打开（Intel 应用）。

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —（bundle 不声明 feed） | ○（cask `trim-enabler` 存在，非 `auto_updates`；VendorProbe 先应答） | —（`itunes.apple.com/lookup?bundleId=` 返回 0） | — | ✓ `Recipes/org-cindori-TrimEnabler4.swift` |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**（`channel-verify`：`winning source  Vendor`）。

## Channel 详情

只有一条轨，feed 无 `<sparkle:channel>`。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.cindori.TrimEnabler4` | — | — | — | ✓ |

## 更新检测
- 源: `VendorProbeSource`，recipe `Recipes/org-cindori-TrimEnabler4.swift`（与 The Unarchiver 同形：DevMate appcast）
- `feed-discover` 判定: `review templatedAddress`，候选 `https://updates.devmate.com/%@.xml`（取自二进制字符串）。
  按 bundle id 填入后 301 → `https://updateinfo.devmate.com/org.cindori.TrimEnabler4/updates.xml`（200），recipe 直接读后者。
- feed 15 个 item，newest-first；版本是主 `<enclosure>` 上的 `sparkle:shortVersionString` 属性，`entryStartPattern`
  把版本、`pubDate`、zip 绑在同一个 item 上。每条 `minimumSystemVersion` 都是 `10.9`，没有上限。
- 上一版 4.3.5 → `duo check`：`Trim Enabler  4.3.5  →  4.3.6  [Vendor, in-place]`；4.3.6 → `up to date`
- 官网下载 `cdn.cindori.com/apps/trimenabler/TrimEnabler.zip` 与 feed 的 `TrimEnabler-26.zip` 字节相同
  （SHA-256 `e26f2703…896db5`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（DevMate 的 Sparkle 1） | 有 | **不能** |
| 证据 | `DevMateKit.framework` | 2026-10-12 每个 item 带 3 个 `<sparkle:deltas>` | 一键日志：`delta route: Trim Enabler build 25 → 4.3.6, patch 138424 B`，随后 `Applying version 1 patches is no longer supported`，0.7 s 后自动回落整包 |

- 格式: Sparkle binary delta **v1**，当前 `BinaryDelta` 不再支持。代价是每次多下 ~140 KB 和一次失败尝试，结果正确。

## Changelog
- 来源: 网页（recipe 的 `changelogURL` = `https://updateinfo.devmate.com/org.cindori.TrimEnabler4/26/releasenotes.html`）
- 结构化: `web page …, no structure`
- **不能结构化**：这页从 4.3.6 一直列到 4.0，各版本之间只用 `<hr>` 分隔，只有最上面一段标了版本号（标题 `Trim Enabler 4.3.6`），
  拆不出按版本的条目。产品已冻结，不值得写 ChangelogRecipe。
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持
- 读的是: 人人可手动下载的 GA（feed 最新 item，与官网 zip 同一文件）
- 格式: zip
- 校验: feed 只给 `length`，没有摘要；装前 Team ID 闸。Intel-only 由 `HostArch.canRunIntelBuilds` 在安装时把关。
- 端到端（2026-10-12）:
  1. **不运行**：4.3.5 放进 `/Applications` → `duo install "/Applications/Trim Enabler.app" --yes --json` →
     `{"applied":true,"bytesDownloaded":64063226,"outcome":"installed","route":"vendor"}`，10 s
     （= 138424 B 失败的 delta + 63924802 B 整包）；结果 4.3.6 (26)，inode 变更，`codesign --verify --deep --strict` 通过，
     `spctl` = Notarized Developer ID，Team `ZQK6SX26CE`，`diff -r` 与厂商 zip 一致，`duo backups` 有 4.3.5 备份。
  2. **运行中**：启动 4.3.5 → `duo install` 同样 `installed`，磁盘 4.3.6 保持不回退（DevMate 没有自动暂存）。
     `duo restart "Trim Enabler"` 返回 `still running — likely a save prompt, left it alone`：首次启动弹的 newsletter 订阅框是模态窗，
     挡住了退出，duo 按设计没有强杀。关掉后重新启动，跑的是 4.3.6（build 26）。

## 已知问题
- DevMate delta 是 v1 格式，每次一键先失败一次再走整包（见上）。
- 在 macOS 28 上无法运行（Intel），届时检测仍会显示，但装上的版本也打不开。厂商不会再发新版。

## 建议下一步
1. 无。产品冻结在 4.3.6，recipe 只为让旧版用户看到并装上最后一版。

## 历史与实测

- 2026-10-14，`entryPatternNoMatch`（issue #1254）：`versionPattern` 原为不锚定的 `sparkle:shortVersionString="([0-9.]+)"`。
  每个 item 的 3 个 `<sparkle:deltas>` enclosure 都带同一属性，所以一个 item 内命中 4 次；`highestVersionEntry` 的
  「切片内只能命中一次」守卫因此拒收切片，回落到整页首次命中。版本仍是 4.3.6，但 pubDate 和 zip 没有绑在同一 item 上。
  修复：版本只读非 delta 的主 enclosure（`<enclosure(?![^>]*deltaFrom)…`）。实测：feed 15 个 item 各命中 1 次，
  版本 4.3.6 → 4.0，pubDate 与 zip 与 item 一致。
- 2026-10-14，changelog（issue #1253）：`updateinfo…/26/releasenotes.html` 是一页 15 段、以 `<hr>` 分隔的合并列表，
  只有最上面一段标了版本号。`updates.devmate.com/releasenotes/<build>/…` 跳转（redirect）到对应的 `updateinfo` 页（`26` 跳到合并页），各 build 页（25、24、21、20、3）头部版本各不相同。
  试验（生产 `ChangelogExtractor`）：body 取整个 `dm-rn-content` 时，4.3.6 下挂 7 条 `<li>`，其中 6 条属于 4.3.5 及更早版本（误归属）；
  body 在第一个 `<hr` 截断时只剩 1 条（4.3.6 的 crash 修复），`<p>` 的 Big Sur 说明不在 `<li>` 里。结论：不写 ChangelogRecipe，列入 `ChangelogCoverage.acknowledged`，理由同上。

## 如何复验

```bash
curl -sSL https://updates.devmate.com/org.cindori.TrimEnabler4.xml | head -20
swift run --package-path application-test channel-verify "<Trim Enabler.app>"   # → winning source Vendor, latest 4.3.6
curl -sSLO https://dl.devmate.com/org.cindori.TrimEnabler4/25/1605105283/TrimEnabler-25.zip   # 上一版
```
