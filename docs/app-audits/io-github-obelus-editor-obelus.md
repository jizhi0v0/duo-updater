# Obelus

## 基本信息
- App: Obelus — Rust 写的代码编辑器，内置 agent；同一个编辑器有窗口版 `obg` 和终端版 `ob` 两个二进制
- Bundle ID: `io.github.obelus-editor.obelus`（`Obelus.app`，可执行文件 `obg`）
- 仓库: `obelus-editor/obelus`（Apache-2.0，默认分支 `master`）
- Team ID: **无（ad-hoc 签名）**。`codesign -dvvv`: `Signature=adhoc`、`TeamIdentifier=not set`、
  `Identifier=io.github.obelus-editor.obelus`；`codesign --verify --deep --strict` 退 0；`spctl -a -vv` rejected
- 观测版本: 0.16.0（2026-10-16 发布）；观测日期: 2026-10-19
- 自更新机制: 无。settled from source：`crates/obelus-app/src/app/project/releases.rs`（`master`）每天问一次
  `https://api.github.com/repos/obelus-editor/obelus/releases/latest`，只在欢迎页说「有新版」，不下载、不替换
- 分发:
  - GitHub Releases：每个 release 一个 universal2 `Obelus-<v>-universal2-apple-darwin.app.zip`，另有 `ob-`/`obg-`
    的 `universal2-apple-darwin.tar.xz`（裸二进制）、Linux deb/rpm/AppImage、Windows msi/zip、`SHA256SUMS`
  - README 的主推路径是 `contrib/install.sh`：把 `obg`（`--bin ob` / `--bin both` 换成终端版）**裸二进制**装进
    `~/.local/bin`（`--dir` / `OBELUS_INSTALL_DIR` 可改），按 `SHA256SUMS` 核对；macOS 上不装 `.app`
  - mise：`github:obelus-editor/obelus[matching=obg-]` / `[matching=ob-]`，同样是裸二进制
  - 没有 Homebrew cask（`brew info --cask obelus`: No Cask with this name exists），不在 MAS
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测，见「如何复验」）。

本文只覆盖 `Obelus.app`。`install.sh` / mise 装在 `~/.local/bin` 的 `ob`、`obg` 裸二进制不是 app，扫描看不到，
见「已知问题」。

## Channel 详情

只有一条轨。settled from source：`.github/workflows/release.yml`（`master`）在推 `v*` tag 时构建，tag 必须等于
`v` + `Cargo.toml` 里 `obelus-cli` 的 version，否则失败。workflow 允许带后缀的 prerelease tag（MSI 的版本号会去掉
后缀），但现有 12 个 release（v0.9.0–v0.16.0）没有一个是 prerelease，tag 也都是三段纯数字。app 自己的版本检查
读 `/releases/latest`，同样不看 prerelease。

## 更新检测
- 源: `obelus-editor/obelus` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.16.0` → bundle 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 都是 `0.16.0`；
  0.9.0 / 0.15.0 / 0.16.0 三个真包一致
- `versionPattern` `^v([0-9]+\.[0-9]+\.[0-9]+)$`（锚死，将来的 `-rc` tag 读不进来；v1.0.0 这样的下一个主版本照读）
- install pattern `^Obelus-[0-9]+\.[0-9]+\.[0-9]+-universal2-apple-darwin\.app\.zip$`：一个 release 31 个资产里只命中
  这一个 `.app.zip`（`obg-…-universal2-apple-darwin.tar.xz` 是裸二进制，不是 app，不能命中）
- 首个 release v0.9.0 起每个 release 都有这个 `.app.zip`，bundle id 从未变过

## 按架构 / 按 OS 分轨
- 不分：universal2（`lipo -archs`: `x86_64 arm64`）
- Info.plist 没有 `LSMinimumSystemVersion`；arm64 切片 `minos 11.0`（`vtool -show-build`）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 源码只有版本检查，没有下载/安装 | release 只有整包（2026-10-19 的资产列表） | 无可消费的补丁 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没跑（无更新器） | — |
| 证据 | `releases.rs` 只请求 `/releases/latest` 的 JSON，答案缓存在磁盘上一天 | — | — |

## Changelog
- 来源: GitHub Release body，GitHub 自动生成的 `## What's Changed`（每个 PR 一条 `* <标题> by @user in <链接>`）
  + `**Full Changelog**` 链接
- 结构化（2026-10-19，channel-verify `changelog pane`，0.15.0 → 0.16.0）:
  `source structured: 1 entries; newest 0.16.0: 16 items, headings []; first items ["The theme being worn says when it is beh", "A caret its band carried rides the band,", "Open documents are put in the reader's o"]`
- 小节: 只有一个 `What's Changed`，`headings []` 是正确结果，不是被压平；16 条 = v0.16.0 正文里的 16 个 PR
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **digest-only**（`installTrust: .publishedDigestOnly`）——用户在设置 → 通用里打开
  「无开发者签名的 app 按文件哈希一键更新」才可用；关闭时只检测
- 格式: zip，里面只有 `Obelus.app`（9 个条目）；bundle 里没有嵌套 app、framework、XPC 或 helper，
  `Contents/MacOS` 只有 `obg`，`Resources` 只有 `obelus.icns`
- 条件核对（2026-10-19，三个真包）: 封印 `--deep --strict` 退 0；签名标识 `io.github.obelus-editor.obelus`；
  short == tag；GitHub 资产 `digest` 与下载后 `shasum -a 256` 相同:

  | 资产 | 字节 | sha256 |
  |---|---|---|
  | `Obelus-0.16.0-universal2-apple-darwin.app.zip` | 50388533 | `7136f4554a866bf4b64df63a6fdd1c2f12e38da0d4754a5bbfc9cf22da064577` |
  | `Obelus-0.15.0-universal2-apple-darwin.app.zip` | 49208093 | `b27c81451ba4ddc6d71e0c1b075f4f2352abc5b9ec317ba3f6f43083a39e1373` |
  | `Obelus-0.9.0-universal2-apple-darwin.app.zip` | 40756016 | `d3bde27b6b51db8568acd0a0d1e976cee71186b57660527ebd3bc62e48d3dd60` |

- **读的是**: 人人可手动下载的 GA（`/releases/latest`，README 和 app 自己的版本检查都指向它）
- 端到端（2026-10-19，真机，Apple silicon；`make cli` 用本分支构建的 `duo`）:
  - 不运行、设置关闭: 0.15.0 放进 `/Applications` → `duo check` `0.15.0 → 0.16.0 [GitHub]` → `duo install --yes --json`
    `skipped`，原因「no developer signature — turn on one-click updates for such apps …」；bundle 原样（版本、inode 不变）
  - 不运行、设置打开（`AllowDigestOnlyInstalls`）: `installed`（`route` vendor，50388533 字节 = 0.16.0 的 `.app.zip`，
    17 s）→ short / build 都是 `0.16.0`、inode 变、签名标识 `io.github.obelus-editor.obelus`（adhoc）、
    `--deep --strict` 0、`spctl` rejected（预期，ad-hoc）、与厂商 zip 解出的 bundle `diff -r` 一致；之后 `duo check` up to date。
    `duo backups` 没有 Obelus 的条目：这次运行时「保留备份」（`KeepBackups`）是关的，没备份是预期结果，与本 rule 无关
  - 运行中一轮没跑: app 没有自更新器（只读 `/releases/latest` 的 JSON），不存在碰撞面
- 阻塞: 无

## 已知问题
- **`install.sh` / mise 装的 `ob`、`obg` 不检测。** README 在 macOS 上主推的就是这条路径（`~/.local/bin` 里的裸
  二进制，ad-hoc），所以按 README 装的用户多半没有 `Obelus.app`。仓库对非 Homebrew CLI 的决定是逐个工具写
  `CLIToolProvider`、不做通用系统（`CLITools/`）；Obelus 没有 self-update 命令，厂商的更新方式是重跑 `install.sh`
  或 `mise upgrade`，`SHA256SUMS` 可满足 `CLIToolTrust` 的哈希路线。这是独立的一块工作，没在本次做。
- 厂商将来若改用 Developer ID 签名，装着 ad-hoc 旧版的用户一键会被 `teamIdentifierAppeared` 拒绝（信任只升不降），
  要手动更新一次；rule 也要改回默认的 Team-ID 路线。
- ad-hoc 签名每次构建 cdhash 都变，app 拿到的 TCC 授权（如果有）更新后可能要重授；与谁来装无关。

## 建议下一步
1. `ob` / `obg` 裸二进制：照现有 `CLITools/` 的 provider 写法单独接（检测 `~/.local/bin` 及 `--dir`，版本 `obg --version`，
   一键 = 下载 tar.xz + 按 `SHA256SUMS` 核对），带 icon。

## 如何复验
- `swift run --package-path application-test feed-discover <0.15.0 的 Obelus.app>` →
  `no Sparkle, no electron-builder update config and no MyGo feed`
- `swift run --package-path application-test channel-verify <0.15.0 的 Obelus.app>`（2026-10-19）:
  bundle `io.github.obelus-editor.obelus` 0.15.0；detected channel `stable`；winning source `GitHub`；latest `0.16.0`；
  download `…/releases/download/v0.16.0/Obelus-0.16.0-universal2-apple-darwin.app.zip`；status `UPDATE → 0.16.0`
