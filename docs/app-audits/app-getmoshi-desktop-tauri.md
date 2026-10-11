# Moshi（Tauri）

Moshi 桌面端的 Tauri 版。它的原生重写 Moshi Go 是另一个 bundle id，见 [Moshi Go](app-getmoshi-desktop.md)。
**2026-10-10 起厂商通过 Tauri 自己的更新 feed 把 Tauri 用户迁到 Moshi Go**，所以这个 bundle id 不再有自己的 recipe：
Tauri 副本由 `BundleIDMigration`（`app.getmoshi.desktop.tauri → app.getmoshi.desktop`）归到 Moshi Go 名下，
用 Moshi Go 的 feed、MyGo key 和 changelog 检查与一键更新。

## 基本信息
- Bundle ID: `app.getmoshi.desktop.tauri`（0.1.0 起直到最后一版 0.4.23 都是这个）
- Team ID: `FL442366Y7`（`Developer ID Application: Moshi Tech Limited`），与 Moshi Go 相同
- 观测版本: `0.4.23`（Tauri 的最后一版，`desktop/v0.4.23/` 的 tar.gz）；Tauri feed 现在给的是 Moshi Go `0.5.12`；2026-10-11
- 自更新机制: Tauri updater（`tauri-plugin-updater`），endpoint `desktop/latest.json`，minisign 签名
- 开源: 否

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | 无自己的 recipe；归到 Moshi Go 的（一键） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**，读的是 Moshi Go 的 recipe
（`InstalledApp.recipeBundleID` 把版本低于 0.5.0 的 `app.getmoshi.desktop.tauri` 副本归到 `app.getmoshi.desktop`）。
没有 Sparkle / electron-builder 配置（`feed-discover`），没有 cask（厂商 tap 只有 `moshi-hook`）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.getmoshi.desktop.tauri` | 单一渠道，迁往 Moshi Go | — | `BundleIDMigration`（Team `FL442366Y7`，版本 < 0.5.0） | ✓（经 Moshi Go） |

## 更新检测
- 现状（2026-10-11）: `https://cdn.getmoshi.app/desktop/latest.json` 的 `version` 是 `0.5.12`，`platforms` 只剩
  `darwin-aarch64` 一项，url 是 `desktop/v0.5.12/Moshi_0.5.12_aarch64.app.tar.gz`。这个包里是 **Moshi Go**
  （见「历史与实测」）。也就是说 Tauri feed 已经不再描述 Tauri app，而是一座通往 Moshi Go 的桥，所以不再读它。
- duo 现在怎么查: Tauri 副本走 Moshi Go 的 recipe（`desktop-go/update-darwin-arm64.json`），得到 Moshi Go 的最新版
  （2026-10-11 是 0.5.13，比 Tauri feed 的 0.5.12 新一版）。
- 旧 recipe（2026-10-07 至 2026-10-11）读 Tauri feed 顶层 `version` / `pub_date`，取 `darwin-aarch64` 对象里的 `url`。
- 版本方案: Tauri 包 feed `version` == `CFBundleShortVersionString` == `CFBundleVersion`；Moshi Go 同样如此。
- 灰度: 无。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | Tauri updater 只下全量 `.app.tar.gz` | Moshi Go feed 的 `deltas[]` 只有 `from` 0.5.x 的（2026-10-11：0.5.10/0.5.11/0.5.12） | Tauri 副本的版本对不上任何 `from`，走全量包 |

## Changelog
- 来源: Moshi Go 的 recipe（`desktop-go/latest/manifest.json`），Tauri 副本经 `BundleIDMigration` 选到它。
- Tauri 自己的 manifest（`desktop/latest/manifest.json`）不再读。它的旧 recipe 在 2026-10-10 之后只解析到 0.4.23（#1177）:
  manifest 新加的第一条 `0.5.12` **没有 `date` 字段**（其余条目都有），而 entry pattern 要求 `notes` 之后、下一个
  `"version"` 之前出现 `"date"`，于是从 0.5.12 起匹配不上，第一条匹配落到 0.4.23。这条 0.5.12 的 notes
  就是 Moshi Go 0.5.12 的 notes 前面加一句 "Moshi Desktop is now Moshi Go, a new native app. Your settings come with you."。
- 跟随 channel: 单渠道。

## 一键安装
- 状态: **支持（经 Moshi Go 的 recipe）**，Tauri 副本被换成 Moshi Go。
- 为什么放行: 厂商自己的 Tauri 更新器做的就是这件事（Tauri feed 发的就是 Moshi Go 包，0.4.23 的 notes 写
  "Macs with Apple silicon move to it with a normal update"）；Moshi Go 首次启动会导入 Tauri app 的设置
  （二进制里有 `MigrateFromTauri` / `TauriSettingsPath`、`settings: migrated %d keys from the Tauri app`，
  0.5.0、0.5.12、0.5.13 都有；**读字符串得出，没实跑**）。闸 4 只放行 `app.getmoshi.desktop.tauri → app.getmoshi.desktop`
  这一个方向、Team `FL442366Y7`、副本版本 < 0.5.0；Team ID 闸和 MyGo 签名校验照旧。
- 原地替换保留磁盘上的路径：一键后 `Moshi.app` 这个文件名里装的是 Moshi Go。厂商 Tauri feed 的包本身也叫 `Moshi.app`
  （里面的可执行文件是 `Moshi Go`），所以这和厂商更新器的结果一致；从 Moshi Go 官网 dmg 手装则得到 `Moshi Go.app`。
- 端到端（2026-10-11，`make cli` 后的 `duo`，不运行一轮）: 厂商 Tauri 0.4.23 aarch64 包解出的副本，
  `duo install <path> --yes --json` → `installed`（下载 16.1 MB）。之后同一路径里是 `app.getmoshi.desktop`
  0.5.13、可执行文件 `Moshi Go`、`TeamIdentifier=FL442366Y7`，`codesign --verify --deep --strict` 通过，`duo check` 报已是最新。
  运行中一轮没跑：再起一个 Tauri 实例会读写与正式副本同一份设置。设置是否真被导入也没核（未启动 Moshi Go）。
- 2026-10-07 的 Tauri→Tauri 端到端（0.4.18 → 0.4.19，不运行 / 运行中两轮）记在「历史与实测」。

## 已知问题
- 运行中的 Tauri app 启动约 3 秒内会静默自更新且不重启（2026-10-07 实测，0.4.18 → 0.4.19）。现在 Tauri feed 发的是
  Moshi Go，推测一启动就会把自己换成 Moshi Go（**未验证**，依据是 feed 内容和厂商 notes）。
- 只有 arm64：Tauri feed 的 `darwin-x86_64` 项已经没了，Moshi Go 只发 arm64。

## 如何复验
```
# GET https://cdn.getmoshi.app/desktop/latest.json → version 0.5.12，platforms 只有 darwin-aarch64（2026-10-11）
# 下载 desktop/v0.5.12/Moshi_0.5.12_aarch64.app.tar.gz 解包:
#   Moshi.app/Contents/MacOS/Moshi Go；Info.plist CFBundleIdentifier app.getmoshi.desktop，0.5.12 / 0.5.12
#   codesign -dv → Identifier=app.getmoshi.desktop，TeamIdentifier=FL442366Y7，Notarization Ticket=stapled
#   diff -r 与 desktop-go/moshi-go-0.5.12-darwin-arm64.tar.gz 解出的 "Moshi Go.app" → 无差异
# 下载 desktop/v0.4.23/Moshi_0.4.23_aarch64.app.tar.gz → app.getmoshi.desktop.tauri / 0.4.23 / FL442366Y7
# desktop/v0.4.24、v0.5.0、v0.5.1、v0.5.11、v0.5.13 的 tar.gz → 404（Tauri 路径下没有别的 0.5.x）
# GET https://cdn.getmoshi.app/desktop/latest/manifest.json → latest 0.5.12；releases[0] 是 0.5.12，键只有 version/notes/localized
swift test --package-path DuoUpdaterCore --filter BundleIDMigrationTests
```

## 建议下一步
1. 真机一键运行中一轮：Tauri 0.4.x 副本运行时 `duo install` / `duo restart`，核对设置是否被导入、
   `duo restart` 能否找到仍以 Tauri id 运行的进程（不运行一轮 2026-10-11 已过）。

## 历史与实测
- 2026-10-07 接入。官网 dmg 0.4.18，feed 0.4.19（当天 05:51 UTC 发布），manifest 20 个版本（0.4.0–0.4.19，2026-09-25 起）。
  - 下载 0.1.0 … 0.4.19 的 `.app.tar.gz` 读 Info.plist，全是 `app.getmoshi.desktop.tauri`。
  - 一键端到端（`make cli` 后的 `duo`）: 未运行时官网 0.4.18 dmg `ditto` 到 `/Applications`，`duo install --yes --json` →
    `{"applied":true,"bytesDownloaded":10955733,"outcome":"installed","route":"vendor"}`，约 11 s；之后 0.4.19 / 0.4.19，
    `codesign --verify --deep --strict` 通过，`spctl` `accepted` / `Notarized Developer ID`，与厂商 tar.gz 解出的 bundle
    `diff -r` 一致。运行中：app 启动约 3 秒内自己把磁盘上的 bundle 换成新版（t+2s 仍 0.4.18，t+3s 0.4.19、inode 换了、pid 不变），
    `duo install` 到场时已无事可做；`duo restart` 重启了仍跑旧代码的进程，`moshi-desktop-bridge` sidecar 也换了新进程。
  - changelog: `channel-verify` 得 `20 entries; newest 0.4.19: 7 items`；生产 `ChangelogExtractor` 输出与 JSON 解码后的 notes
    逐条对照，20 个条目、92 条全部一致。
- 2026-10-09: 夜扫记录 identity 变化（`identityChanged` 记在 0.4.22）。
- 2026-10-10: 厂商发 Tauri 0.4.23（notes 第一条: Moshi Go 接班，Apple silicon 的 Mac 通过正常更新迁过去），随后 Tauri feed
  改发 0.5.12，`pub_date` `2026-10-10T09:27:29.987291Z`。
- 2026-10-11 退役 Tauri recipe（#1167 installer `bundleIDMismatch`，#1177 changelog 落后一整版）:
  - Tauri feed 的 0.5.12 包（15790364 B，sha256 `d732ad35…6bd461`）解出 `Moshi.app`：`app.getmoshi.desktop` / 0.5.12，
    Team `FL442366Y7`，公证票已钉，`codesign --verify --deep --strict` 通过；与 Moshi Go feed 的 0.5.12 tar.gz 解出的 bundle
    `diff -r` 无差异，只有外层文件夹名不同（`Moshi.app` 对 `Moshi Go.app`）。
  - Tauri 0.4.23 包是 `app.getmoshi.desktop.tauri` / 0.4.23 / `FL442366Y7`；Moshi Go 0.5.0 包是 `app.getmoshi.desktop` /
    `FL442366Y7` —— `BundleIDMigration` 的 lastFrom 0.4.23、firstTo 0.5.0 即取自这两个包。
  - 处理照 WorkBuddy 国内站（#1030）和 PrintCraft→PdfCraft（#1087）的先例：`BundleIDMigration` 登记这次交接，删掉以 Tauri id
    为键的 probe 和 changelog recipe（该表的不变量要求旧 id 不再被任何 recipe 作键），family 文件和 golden 一并删除。
    Moshi Go 的 feed 当天是 0.5.13，比 Tauri feed 新，且带 MyGo 签名，Tauri 副本因此直接拿到最新的 Moshi Go。
