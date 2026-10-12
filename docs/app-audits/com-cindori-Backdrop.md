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
- 状态: **可用**。BackdropWallpaper 在跑也照装：它是 bundle 自己 `Contents/Library/LaunchAgents/` 里 plist 的 `BundleProgram`，
  `NestedAppGuard` 2026-10-12 起像登录项一样放行这类 agent（旧 agent 要等 Backdrop 下次启动才换掉，见「已知问题」）
- 读的是: 人人可手动下载的 GA（feed 最新 item）
- 格式: dmg，带 Sparkle delta
- 校验: feed 带 `sparkle:edSignature`，无独立摘要字段；装前 Team ID 闸
- 端到端（2026-10-12）:
  1. **不运行**：2.8.0 放进 `/Applications`（未启动）→ `duo install /Applications/Backdrop.app --yes --json` →
     `{"applied":true,"bytesDownloaded":9169866,"outcome":"installed","route":"sparkle"}`，6 s，走 delta；
     结果 2.9.0 (135)，`codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，Team `ZQK6SX26CE`，
     `diff -r` 与厂商 dmg 里的 bundle 一致，`duo backups` 有 2.8.0 备份。
  2. **运行中**：启动 2.8.0，主程序拉起 `BackdropWallpaper --wallpaper-agent`（父进程 launchd，`parent bundle version` 134）。
     放行之前 `duo install` 返回 `skipped`（"BackdropWallpaper is running from inside Backdrop…"），磁盘保持 2.8.0。
     放行之后：`duo install` → `{"applied":true,"bytesDownloaded":9169866,"outcome":"installed","route":"sparkle"}`，8 s，走 delta；
     `duo restart Backdrop` → `restarted`，主程序和 agent 都换了新 pid、都从新 bundle 跑，`parent bundle version` 135；
     之后 10 s 磁盘一直是 135。`codesign --verify --deep --strict` 通过，`spctl` = Notarized Developer ID，Team `ZQK6SX26CE`，
     `diff -r` 与厂商 2.9.0 一致，`duo backups` 有 2.8.0 备份。
  3. **主程序已退出、agent 还在**（最常见的状态）：`duo install` → `installed`；`duo restart` → `not running — nothing to restart`，
     旧 agent（134）照旧在跑；打开 Backdrop 后换成新 agent（135）。

## 已知问题
- **BackdropWallpaper 一旦启动就一直在**。实测主程序退出后 agent 60 s 仍在；系统壁纸扩展还会再拉起
  `--wallpaper-renderer` 进程。它在 `Contents/Resources/` 下、父进程是 launchd、不是 `.regular`，原本命中
  `NestedAppGuard` 的拒绝条件（VMPal 那条规则），一键因此基本总是被拒。用户没有界面可以单独退出它。
  已解决：`NestedAppGuard` 现在放行 bundle 自己 LaunchAgents plist 的 `BundleProgram`（renderer 是同一个可执行文件，一并放行）。
- **装完到下次打开 Backdrop 之间，旧 agent 跑的是旧代码**。厂商自己的启动会换掉它：主程序退出、旧 agent 134 仍在跑时
  把 2.9.0 放到位，60 s 内旧 agent 一直在（从被挪走的旧 bundle 里跑）；启动 2.9.0 后 3 s 内旧 agent 消失、新 agent 起来，
  `launchctl print gui/<uid>/com.cindori.Backdrop.Wallpaper.agent` 的 `parent bundle version` 从 134 变成 135。
  Backdrop 在偏好里按 agent 记着注册时的 bundle（`com.cindori.Backdrop.Wallpaper.agent.registration` = bundle 路径、inode 和哈希），
  大概就是靠它发现 bundle 换了（推测，没追进代码）。
  这是 `SMAppService.h` 要求 app 自己做的事（更新后重新 register，换了可执行文件就先 unregister，unregister 会杀掉在跑的 agent），
  不是 launchd 自动做的。主程序装前在跑时 `duo restart` 会把它拉起来，没在跑就等用户下次打开。
- **启动后会把自己设成系统壁纸**。`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` 里 Desktop 与 Idle 的
  `Provider` 变成 `com.cindori.Backdrop.WallpaperExtension`，`LastSet` 与一次 2.9.0 启动只差 2 s；原来的壁纸选择被覆盖，
  Backdrop 的偏好和 Application Support 里没找到原设置的副本，删掉 Backdrop 也不会恢复，要去「系统设置 › 墙纸」重新选。真机验证前先记下当前壁纸。

## 建议下一步
无。

## 如何复验

```bash
swift run --package-path application-test feed-discover <Backdrop.app>   # → declared
swift run --package-path application-test channel-verify <Backdrop.dmg>  # → winning source Sparkle, latest 2.9.0, deltas 5
curl -sS https://cdn.cindori.com/apps/backdrop/updates/2.8.0-134/Backdrop.dmg -o Backdrop-2.8.0.dmg  # 上一版
plutil -p /Applications/Backdrop.app/Contents/Library/LaunchAgents/com.cindori.Backdrop.Wallpaper.agent.plist
launchctl print gui/$(id -u)/com.cindori.Backdrop.Wallpaper.agent | grep -E 'pid =|parent bundle version'   # agent 跑的是哪一版
```
