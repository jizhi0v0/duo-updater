# Moshi（Tauri）

Moshi 桌面端的 Tauri 版。它的原生重写 Moshi Go 是另一个 bundle id、另一条 feed，见
[Moshi Go](app-getmoshi-desktop.md)；两者为什么不会串，也写在那份里。

## 基本信息
- Bundle ID: `app.getmoshi.desktop.tauri`（0.1.0 起一直是这个）
- Team ID: `FL442366Y7`（`Developer ID Application: Moshi Tech Limited`）
- 观测版本: `0.4.18`（官网 dmg）、`0.4.19`（feed 与 tar.gz），short == build；2026-10-07
- 自更新机制: Tauri updater（`tauri-plugin-updater`），endpoint `desktop/latest.json`，minisign 签名
- 开源: 否

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓ 一键      |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**。
没有 Sparkle / electron-builder 配置（`feed-discover`），没有 cask（厂商 tap 只有 `moshi-hook`）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.getmoshi.desktop.tauri` | 单一渠道 | — | — | ✓ |

## 更新检测
- 源: `https://cdn.getmoshi.app/desktop/latest.json`，二进制里 Tauri updater 配置写死的地址（紧跟着它的是 updater 公钥）。
  标准 Tauri 静态 JSON：顶层 `version` / `notes` / `pub_date`，加一个 `platforms` map
  （`darwin-aarch64`、`darwin-x86_64`、`windows-x86_64`、`linux-x86_64`）。只有顶层有 `version`，取首个匹配即可。
- 版本方案: feed `version` == `CFBundleShortVersionString` == `CFBundleVersion`。
- 发布时间: `pub_date` 带微秒（`2026-10-07T05:51:30.992707Z`），`ReleaseDate.publishedFields` 能解析
  （临时测试实测，得到 `2026-10-07 05:51:30 +0000`）。
- 按 OS 分轨: 无；`LSMinimumSystemVersion` 是 `10.13`。
- 灰度: 无，所有安装读同一份文件。
- 官网滞后: 2026-10-07 官网下载按钮还是 0.4.18 的 dmg，feed 已是 0.4.19。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | Tauri updater 只下全量 `.app.tar.gz` | `latest.json` 每个平台一个全量 url（2026-10-07） | — |

## Changelog
- 来源: recipe —— `https://cdn.getmoshi.app/desktop/latest/manifest.json`，与 Moshi Go 的 manifest 同形
  （`{latest, releases[{version, notes, date}]}`），pattern 也相同。
- 结构化: `recipe changelog:app.getmoshi.desktop.tauri:-: 20 entries; newest 0.4.19: 7 items, headings []`
  （`channel-verify`，2026-10-07）。
- 全量比对: 生产 `ChangelogExtractor` 的输出与 JSON 解码后的 notes 逐条对照，20 个条目（0.4.0–0.4.19）、
  92 条，全部一致；`⌘` `⌃` `⇧` `↵` `→` `—` `…` 和引号都正确反转义。
- 跟随 channel: 单渠道。
- Recipe 状态: 已有。

## 一键安装
- 状态: **支持**
- 端到端（2026-10-07，`make cli` 后的 `duo`）:
  - 未运行: 官网 0.4.18 dmg `ditto` 到 `/Applications`，`duo install --yes --json` →
    `{"applied":true,"bytesDownloaded":10955733,"outcome":"installed","route":"vendor"}`，约 11 s；
    之后 0.4.19 / 0.4.19，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` `accepted` /
    `Notarized Developer ID`，Team `FL442366Y7`，与厂商 tar.gz 解出的 bundle `diff -r` 一致，`duo backups` 有 0.4.18。
  - 运行中: 见「已知问题」第一条 —— app 一启动就自己把磁盘上的 bundle 换成了新版，`duo install` 到场时已无事可做
    （`--json` 只输出 schema 行，exit 0，这是空计划的正常输出）。`duo restart` 把仍在跑旧代码的进程重启了，
    `moshi-desktop-bridge` sidecar 也跟着换了新进程。
- 格式: `.app.tar.gz`（`Moshi_<ver>_aarch64.app.tar.gz`），取 `platforms` 里 `darwin-aarch64` 那个对象的 `url`
  （`"darwin-aarch64"\s*:\s*\{[^{}]*?"url"…`，绑定在自己的对象里，`darwin-x86_64` 紧挨着它）。
  里面只有 `Moshi.app`；`Contents/MacOS` 里除主程序外还有 `moshi-desktop-bridge`，它是主程序启动的 sidecar
  （`--listen 127.0.0.1:0 --token …`），不是 login item，app 退出它也退出（实测退出后无残留进程）。
- 校验: `signature` 是 Tauri 的 minisign 签名，不是摘要；body 无 sha256/sha512，不接 `checksumPattern`，靠 Team ID 闸。
- **读的是**: 人人可手动下载的 GA —— 无灰度，同版本 dmg 在 CDN 上可直接下。
- 阻塞: 无。

## 已知问题
- **运行中的 app 会在启动约 3 秒内静默自更新，且不重启。** 把 0.4.18 装回 `/Applications`、启动、不跑 duo，
  每秒读一次磁盘：t+2s 仍是 0.4.18，t+3s 变成 0.4.19、inode 换了，进程 pid 不变。也就是说磁盘是新版、
  在跑的还是旧代码，直到用户自己重启。对 duo 的影响：
  - 开着的 Moshi 几乎碰不到碰撞窗口（3 秒），`duo check` 读磁盘会显示已是最新；
  - 一键真正有用的是没在运行的旧副本（Tauri 只在启动时更新，长期不开的副本会一直停在旧版）。

## 如何复验
```
# GET https://cdn.getmoshi.app/desktop/latest.json → version 0.4.19（2026-10-07）
swift run --package-path application-test channel-verify Moshi_0.4.18_aarch64.dmg
#   app.getmoshi.desktop.tauri / 0.4.18 / detected channel → stable
#   VendorProbe latest 0.4.19, download …/v0.4.19/Moshi_0.4.19_aarch64.app.tar.gz, verdict UPDATE 0.4.18 → 0.4.19
#   winning source Vendor
#   changelog pane → recipe changelog:app.getmoshi.desktop.tauri:-: 20 entries; newest 0.4.19: 7 items
# bundle id 历史: https://cdn.getmoshi.app/desktop/v<ver>/Moshi_<ver>_aarch64.app.tar.gz 解 Info.plist
#   0.1.0 … 0.4.19 全是 app.getmoshi.desktop.tauri
```

## 建议下一步
1. 厂商若把 Tauri 用户迁到 Moshi Go（例如 `latest.json` 改发 Moshi Go 的包），一键装下来的 bundle id 会和已装的不同，
   届时要重新审计这条 recipe。

## 历史与实测
- 2026-10-07 接入。官网 dmg 0.4.18，feed 0.4.19（当天 05:51 UTC 发布），manifest 20 个版本（0.4.0–0.4.19，2026-09-25 起）。
