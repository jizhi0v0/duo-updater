# Pulse（egoist）

## 基本信息
- App: Pulse — 活动监视器（Mac / Windows / Linux），用 egoist 的 Go GUI 工具包 mygo 写成
- Bundle ID: `com.egoist.pulse`
- 仓库: `egoist/pulse-feedback`（只放 issue 和 release 资产，没有源码）
- Team ID: `GJE9R5VE87`（Developer ID + 公证；0.1.4 与 0.1.5 两个 dmg 相同）
- 观测版本: 0.1.5（`CFBundleVersion` 同为 `0.1.5`）；观测日期: 2026-10-10
- 自更新机制: 自研（mygo `internal/update`）。二进制里写死
  `https://github.com/egoist/pulse-feedback/releases/latest/download/update-darwin-arm64.json`，manifest 给出
  `version`、`notes`、`date`、整包 `url`（`pulse-<v>-darwin-arm64.tar.gz`）、ed25519 `signature`，以及从上一版起的
  `deltas`。启动约 12 s 后检查一次，写 `~/Library/Application Support/Pulse/updater.json` 的 `lastCheck`。
  无 Sparkle、无 `SUFeedURL`、无 electron-builder 配置
- 分发: GitHub Releases；官网 `https://pulse.egoist.dev/download?platform=mac` 302 到同一个 release 的
  `Pulse.<v>.arm64.dmg`。没有 Homebrew cask、没有 MAS
- **没有 macOS CLI。** release 里的 `install.sh`（`curl … | sh`）装的是 Linux 版 GUI 到 `~/.local/pulse.app`，脚本
  `command_name=''`，不链任何命令；在 macOS 上第一步就退出：`install.sh: Pulse installs on Linux`（exit 1，实测）。
  官网也没有命令行安装说明

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | ○           |

当前生效源: **GitHub**（channel-verify 实测）。

## Channel 详情

只有一条轨。两个 release（v0.1.4、v0.1.5）都不是 prerelease；manifest 没有渠道字段；二进制只认一个
`update-darwin-arm64.json` 地址。没有源码可读，单轨结论来自 release 列表与 manifest，不是 settled from source。

## 更新检测
- 源: `egoist/pulse-feedback` GitHub Releases，`/releases/latest`；tag `v0.1.5` 去掉 `v` 等于
  `CFBundleShortVersionString`
- 厂商 manifest（备选，未接）: `update-darwin-arm64.json` 的 `version` 同值；它和 dmg 在同一个 release 里，
  读 GitHub 已经覆盖
- 选 GitHub 的原因: 资产自带 `digest`，release 正文就是 changelog（与 manifest 的 `notes` 同文）

## 按架构 / 按 OS 分轨
- 只有 Apple silicon: `lipo -archs` = `arm64`，release 里没有 Intel dmg 或 darwin-amd64 包。Intel Mac 装不上
  Pulse，也就不会有需要提醒的 Intel 安装
- `LSMinimumSystemVersion` = `12.0`（0.1.4、0.1.5 相同）；manifest 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 不能 |
| 证据 | 二进制含 mygo `update.Delta` / `update.delta (%d passes)` / `damaged delta update` | 2026-10-10 manifest `deltas: [{from: "0.1.4", url: …/pulse-0.1.4-to-0.1.5-darwin-arm64.delta, size: 472510}]` | `DeltaApplier` 只吃 Sparkle `BinaryDelta`，而补丁的目标是 `.tar.gz` 整包，不是 dmg 里的 bundle |

- 格式: mygo 自有（具体格式未验证，没有源码）
- 阻塞项: 格式不是 Sparkle 的；整包 dmg 只有 4.6 MB，补丁收益很小

## Changelog
- 来源: GitHub Release body（`- ` 列表），经 `GitHubMarkdownParser`
- 结构化（2026-10-10，channel-verify `changelog pane`，从 0.1.4 起）: `source structured: 1 entries; newest
  0.1.5: 1 items, headings []; first items ["The icon's light stays within its rounde"]`
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg（公证）；bundle 里只有一个主可执行文件，没有嵌套 app、helper 或 LaunchAgent
- Pattern: `^Pulse\.[0-9.]+\.arm64\.dmg$`, kind `.dmg`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: 0.1.5 = `dc005004…d1d853`、0.1.4 =
  `694f73fa…678a4`，都与各自 `digest` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`；官网 mac 下载链接 302 到同一份文件）
- 端到端（2026-10-10）:
  - 不运行: 0.1.4 → `duo check` `0.1.4 → 0.1.5 [GitHub, in-place]` → `duo install --yes --json` `installed`
    （6.4 s，4617694 字节）→ 0.1.5 / `0.1.5`、inode 变、Team 不变、`--deep --strict` 通过、`spctl` Notarized
    Developer ID、与厂商包 `diff -r` 一致、`duo backups` 有 0.1.4
  - 运行中: 重装 0.1.4 并启动，观察 60 s：它自己检查了更新（`lastCheck` 写入），但磁盘上 bundle 不变、没有暂存包。
    `duo install --yes --json` `installed`（9.0 s）→ `duo restart pulse` → 新进程跑 0.1.5，之后 12 s 磁盘保持 0.1.5
- 阻塞: 无

## 已知问题
- **没测到与自更新器的碰撞。** 60 s 内它只检查、不下载，没有可以「抢」的暂存构建；manifest 地址写死在二进制里，
  也没有找到能让它暂存更旧版本的覆盖开关。它的更新是否要用户在界面里确认，未验证。
- `install.sh` 不是 macOS 的 CLI，见「基本信息」。若以后 mygo 给 macOS 加命令行入口，需要重新审计。

## 建议下一步
1. 出现 Intel 包（`darwin-amd64` / `x64` dmg）时，确认 install pattern 与资产选择器的架构标记。

## 如何复验
```
swift run --package-path application-test channel-verify <Pulse.0.1.4.arm64.dmg>   # → UPDATE → 0.1.5，winning source GitHub
swift run --package-path application-test feed-discover <Pulse.0.1.5.arm64.dmg>    # → no Sparkle and no electron-builder update config
sh install.sh                                                                        # macOS 上 → install.sh: Pulse installs on Linux
```
