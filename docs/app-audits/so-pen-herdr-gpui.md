# Herdr（herdr-gpui）

## 基本信息
- App: Herdr — Herdr 守护进程的 Rust/GPUI 桌面客户端（终端会话、workspace、worktree、agent 活动）
- Bundle ID: `so.pen.herdr-gpui`
- 仓库: `sheprd-labs/sheprd`（旧名 `penso/herdr-gpui`；GitHub 301 到 `/repositories/1377952273/…`）
- Team ID: `VJAHQVZ96V`（Fabien Penso），Developer ID + 公证
- 观测版本: 20261007.2（2026-10-07）；观测日期: 2026-10-07
- 自更新机制: 自带。读 `api.github.com/repos/penso/herdr-gpui/releases/latest` 和 release 里签名的
  `update-manifest.json`（+ `update-manifest.sig`），下载 `herdr-gpui-<ver>-macos-universal.app.tar.gz`；
  界面上还有「Update with Homebrew」分支（二进制字符串）。无 Sparkle、无 `SUFeedURL`
- 分发: 只有 GitHub Releases。Homebrew 的 `herdr` 是 formula（守护进程本身，0.9.3），不是这个 app；没有 cask
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。

## 更新检测
- 源: `sheprd-labs/sheprd` GitHub Releases，`/releases/latest`
- 版本方案: 日期版本，tag `vYYYYMMDD.N`；short == build == tag 去掉 `v`（20261007.1 / 20261007.2 真包）。
  一天可以发好几版（20260921 有 .1–.4），`VersionComparator` 按数字比较第二段（`20261007.10` > `.9`，有测试）
- 34 个 release 全部是这个形状，没有 prerelease；tag 锚 `^v([0-9]{8}\.[0-9]+)$` 是后备

## 增量更新
- 无（manifest 只列整包 `.app.tar.gz`）。

## 按 OS 分轨
- `LSMinimumSystemVersion` = `14.2`（release 正文也写 macOS 14.2+）。
- 架构: 只发 universal（`lipo -archs` = `x86_64 arm64`）。

## Changelog
- 来源: GitHub Release body（Keep a Changelog 风格 `### Added` / `### Changed` / `### Fixed`），经 `GitHubMarkdownParser`
- 结构化（2026-10-07，channel-verify `changelog pane`）: ✓ `source structured`；20261007.2 5 条，小节
  `Added` / `Fixed` 保留；正文开头那段平台说明（「GUI-only release…」）不计入条目
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — `Herdr-<ver>-universal-apple-darwin.dmg`，旁边是 `.crt` / `.sha256` / `.sha512` / `.sig`、更新器用的
  `.app.tar.gz` 与 Linux / Windows 包；GitHub 为每个资产发布 sha256 `digest`
- Pattern: `^Herdr-[0-9]{8}\.[0-9]+-universal-apple-darwin\.dmg$`, kind `.dmg`
- 包验（2026-10-07）: 20261007.1 / 20261007.2 挂载，Team `VJAHQVZ96V`，`--deep --strict` 0，`spctl` Notarized Developer ID
- 端到端（2026-10-07）:
  - 不运行: 20261007.1 → `duo check` `[GitHub, in-place]` → `duo install --yes --json` `installed`（6 s，39826779 字节）→
    20261007.2、inode 变、Team 不变、Notarized、与厂商包 `diff -r` 一致、`duo backups` 有备份
  - 运行中: 重装 20261007.1 并启动（40 s 内它的更新器没自行暂存东西，像是要用户点「Install and Restart」）→
    `duo install` `installed` → `duo restart Herdr` → 新进程起来，之后 10 s 磁盘版本保持 20261007.2
- 机器现状: Herdr 20261007.2 仍装在 `/Applications`，未运行（本机没有 Herdr 守护进程）

## 如何复验
```
swift run --package-path application-test channel-verify Herdr-20261007.2-universal-apple-darwin.dmg   # → up to date
swift run --package-path application-test channel-verify Herdr-20261007.1-universal-apple-darwin.dmg   # → UPDATE → 20261007.2
```

## 历史与实测

- 2026-11-04: 仓库改名 `penso/herdr-gpui` → `sheprd-labs/sheprd`（GitHub 301 到
  `/repositories/1377952273/…`；tag 与 assets 未变，最新 v20261103.1）。旧 slug 每轮检查都吃一次
  301，而 URLSession 跟随时会丢掉 `Authorization`，那一跳按匿名预算计（本机事件库 24h 内只有这条
  规则还在重定向）。匿名 60/h 耗尽后该行 403；规则已 pin 到新 slug。
