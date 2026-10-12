# Backdrop

> 审计 2026-10-12。Cindori 的三款 app 之一，另两款见 [Sensei](org-cindori-Sensei.md)、
> [Trim Enabler](org-cindori-TrimEnabler4.md)。

## 基本信息
- Bundle ID: `com.cindori.Backdrop`
- Team ID: `ZQK6SX26CE`（Developer ID Application: Cindori AB；2.8.0 与 2.9.0 两个真包一致）
- 观测版本: `2.9.0` (build `135`，最新) / `2.8.0` (build `134`，上一版)
- 自更新机制: Sparkle（`SUFeedURL` + `SUPublicEDKey`），默认弹窗询问
- 架构: universal（`x86_64 arm64`）；`LSMinimumSystemVersion` = `15.0`
- 内嵌（都在本 bundle 里，都不是 `.regular`）:
  - `Contents/Resources/BackdropWallpaper.app`（`com.cindori.Backdrop.Wallpaper`，`LSUIElement` = true），
    由 `Contents/Library/LaunchAgents/com.cindori.Backdrop.Wallpaper.agent.plist` 声明为 SMAppService LaunchAgent：
    `BundleProgram` 指向它，`--wallpaper-agent`，`KeepAlive` = false，`RunAtLoad` = false，靠同名 MachService 按需拉起。
    另有作业 `com.cindori.Backdrop.Wallpaper.renderer`（同一可执行文件，`--wallpaper-renderer`）。
  - `Contents/Extensions/BackdropWallpaperExtension.appex`，系统壁纸服务托管。
- 不开源

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic，无 recipe） | ✗（cask `backdrop` 为 `auto_updates: true`，按设计让路） | —（`itunes.apple.com/lookup?bundleId=` 返回 0） | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`channel-verify`：`winning source  Sparkle`）。

## Channel 详情

只有一条轨：feed `https://cdn.cindori.com/apps/backdrop/updates/update.xml` 63 个 item，**0 个 `<sparkle:channel>`**。

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.cindori.Backdrop` | — | `SUFeedURL` | — | ✓ |

## 更新检测
- 源: `SparkleAppcastSource`（generic）
- 端点: `https://cdn.cindori.com/apps/backdrop/updates/update.xml`
- `feed-discover` 判定: `declared`
- 上一版 2.8.0 → `duo check`：`Backdrop  2.8.0  →  2.9.0  [Sparkle, in-place]`

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有（Sparkle 2） | 有 | 能 |
| 证据 | 内嵌 `Sparkle.framework` | 2026-10-12 最新 item 带 5 个 `<sparkle:deltas>`（from 134/132/130/129/128） | `DeltaApplier`：一键日志 `delta route: Backdrop build 134 → 135, patch 9169866 B instead of 44275034 B`，结果与厂商整包逐字节一致 |

## Changelog
- 来源: Sparkle inline（`<description>` 里实体转义的 HTML）
- 结构化: `source structured: 40 entries; newest 2.9.0: 8 items, headings []`（无分节，条目自带 `New:` / `Improved:` / `Fixed:` 前缀）
- 每条开头是 `<h2>2.9.0 (135)</h2>`，后面直接跟列表。本次之前解析器把它当成第一条条目（`first items ["2.9.0 (135)", …]`，9 条）；
  `AppcastHTMLChangelogParser` 现在丢掉只重复本条版本号的标题，变为 8 条。
- 2.3.2 一条只有 197 字符的纯文本，没有列表，回落原文。
- 跟随 channel: — （单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **仅在 BackdropWallpaper 不运行时可装**；运行时被 `NestedAppGuard` 拒绝（见「已知问题」）
- 读的是: 人人可手动下载的 GA（feed 最新 item）
- 格式: dmg，带 Sparkle delta
- 校验: feed 带 `sparkle:edSignature`，无独立摘要字段；装前 Team ID 闸
- 端到端（2026-10-12）:
  1. **不运行**：2.8.0 放进 `/Applications`（未启动）→ `duo install /Applications/Backdrop.app --yes --json` →
     `{"applied":true,"bytesDownloaded":9169866,"outcome":"installed","route":"sparkle"}`，6 s，走 delta；
     结果 2.9.0 (135)，`codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，Team `ZQK6SX26CE`，
     `diff -r` 与厂商 dmg 里的 bundle 一致，`duo backups` 有 2.8.0 备份。
  2. **运行中**：启动 2.8.0，主程序拉起 `BackdropWallpaper --wallpaper-agent`（父进程 launchd）→ `duo install` 返回
     `{"outcome":"skipped","reason":"BackdropWallpaper is running from inside Backdrop and would keep running the old version. Quit it, then update again. Backdrop was not updated."}`，磁盘保持 2.8.0。

## 已知问题
- **BackdropWallpaper 一旦启动就一直在，一键因此基本总是被拒**。实测主程序退出后 agent 30 s 仍在；
  系统壁纸扩展还会再拉起 `--wallpaper-renderer` 进程。它在 `Contents/Resources/` 下、父进程是 launchd、不是 `.regular`，
  正好命中 `NestedAppGuard` 的拒绝条件（VMPal 那条规则）。用户没有界面可以单独退出它。
- **厂商自己的启动会换掉旧 agent**：模拟 Sparkle 自更新（主程序退出、旧 agent 134 仍在跑时把 2.9.0 放到位），
  启动 2.9.0 后旧 agent 消失，新 agent 起来，`launchctl print` 的 `parent bundle version` 从 134 变成 135。
  也就是说 VMPal 那种「替换后无法恢复」的情况在这里不成立：主程序下次启动就会接上新代码。
  要不要为这类 SMAppService LaunchAgent 放宽 guard 是个策略决定，尚未做。

## 建议下一步
1. 决定 `NestedAppGuard` 对「bundle 里 `Contents/Library/LaunchAgents/` 声明的 SMAppService agent」是否像登录项一样放行；
   放行后 Backdrop 一键才在常见状态下可用。

## 如何复验

```bash
swift run --package-path application-test feed-discover <Backdrop.app>   # → declared
swift run --package-path application-test channel-verify <Backdrop.dmg>  # → winning source Sparkle, latest 2.9.0, deltas 5
curl -sS https://cdn.cindori.com/apps/backdrop/updates/2.8.0-134/Backdrop.dmg -o Backdrop-2.8.0.dmg  # 上一版
plutil -p /Applications/Backdrop.app/Contents/Library/LaunchAgents/com.cindori.Backdrop.Wallpaper.agent.plist
```
