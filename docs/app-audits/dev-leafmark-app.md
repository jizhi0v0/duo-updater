# Leafmark（叶笺）

## 基本信息
- App: Leafmark · 叶笺 — Markdown 桌面编辑器（macOS / Windows），用 MyGo（`github.com/egoist/mygo`）写成
- Bundle ID: `dev.leafmark.app`
- 仓库: `KevinXC5/leafmark`（MIT），官网 `https://kevinxc5.github.io/leafmark/`
- Team ID: **无（ad-hoc 签名）**。`codesign -dvv`: `Signature=adhoc`、`TeamIdentifier=not set`、`Identifier=dev.leafmark.app`；
  `codesign --verify --deep --strict` 通过。没有公证，所以 `.tar.gz` 和 dmg 里的 bundle 都没有钉票据（`Contents/CodeResources`）
- 观测版本: 0.9.1、0.9.2（`CFBundleShortVersionString` = `CFBundleVersion`）；观测日期: 2026-10-13
- 自更新机制: MyGo 自带的更新器。Go build info 里 `dep github.com/egoist/mygo v0.4.1`；feed 与 key 由 `mygo build` 链进二进制
  （`mygo.json`: `updates.github` = `KevinXC5/leafmark`、`deltas: 3`、`changelog: .github/release-notes.md`）
- 分发: GitHub Releases（`Leafmark.<v>.{arm64,amd64}.dmg`，以及更新用的 `.tar.gz` / `.delta` / `update-darwin-*.json`）；
  没有 Homebrew cask（`brew search --cask leafmark` 无结果），没有 MAS
- 架构: arm64 与 amd64 分别构建（`lipo -archs` = `arm64`），各自链着自己的 `update-darwin-<arch>.json`
- `LSMinimumSystemVersion` = `12.0`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe | MyGo（通用） |
|------------|---------|----------|-----|--------|-------------|-------------|
| **stable** | —       | —        | —   | —      | —           | ✓ |

当前生效源: **MyGo**（`MyGoUpdateSource`，channel-verify 实测 2026-10-13）。没有任何按 app 写的 recipe：feed 与 key
都从已装 app 的二进制读出（`MyGoUpdateConfig`）。

## Channel 详情

只有一条轨。manifest 没有渠道字段，release 列表里没有 prerelease（2026-10-13，v0.7.1–v0.9.2 都是正式版）。

## 更新检测
- 源: `MyGoUpdateSource`，读二进制里链的
  `https://github.com/KevinXC5/leafmark/releases/latest/download/update-darwin-arm64.json`（amd64 构建读 `-amd64`）
- 二进制里的 key: `arFeLNqUcZDj4bjo7f1FiZ3ndod0Ghgu6B15b/BKUH8=`，与仓库 `mygo.json` 的 `updates.publicKey` 相同；
  0.9.2 二进制的 `__TEXT,__rodata` 里以 NUL 结尾、解码为 32 字节的 44 字符 base64 串只有这一个
- 版本 / 日期 / 下载地址 / 签名取 manifest 顶层（`MyGoManifest.release`）
- **读的是**: 人人可手动下载的 GA。manifest 无灰度字段，每个副本读同一个文件

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | **能** |
| 证据 | MyGo 更新器自带 `ApplyDelta`（`mygo.json` `deltas: 3`） | 2026-10-13 manifest（0.9.2）`deltas[]` from 0.9.1（161516 B）/ 0.9.0（583593 B）/ 0.8.0（943061 B），全量 10297458 B | `MyGoManifest` + `MyGoDelta`，签名用二进制里的 key |

- 没公证，dmg 和 `.tar.gz` 里的 bundle 一样（都没有钉票据），所以 dmg 装的副本第一次也能走补丁——公证过的 MyGo app
  （Pulse、Moshi Go）没有这个便宜，见它们的审计

## Changelog
- 来源: manifest 的 `notes`（`MyGoUpdateSource` 交给 changelog pane）。Leafmark 的 `.github/release-notes.md` 把整段历史写成
  `### <版本>` 小节，manifest 的 `notes` 是全文（0.9.2 约 7 KB，`### 0.9.2` … `### 0.1.0`）；`MyGoUpdateSource.changelog`
  在开头就是本版本标题、且至少还有一个版本标题时按版本拆开
- 结构化（2026-10-13，channel-verify `changelog pane`，从 0.9.1 起）: `source structured: 22 entries; newest 0.9.2: 5 items,
  headings ["问题修复"] (rendered as markdown)`
- app 自己的更新窗口（「发现新版本 0.9.2」）同样只显示 0.9.2 那一节，与拆开后的第一条一致
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（`InstallTrust.myGoSignatureOnly`）。2026-10-19 起不再受「允许无开发者签名的 app 一键更新」控制：校验用的是已装 app 自己二进制里的 key，与 app 自带更新器同一个锚点。下面的端到端是在开关打开时跑的
- 格式: `.tar.gz`（manifest 顶层 `url`），解出 `Leafmark.app`，没有嵌套 app、helper 或 LaunchAgent
- 校验: 来源证明是 MyGo Ed25519 签名（签文件的 SHA-256），key 取自已装 app 的二进制；之后跑 ad-hoc 身份闸（ad-hoc 标记、
  bundle id 两边一致、版本与 manifest 一致）。manifest 不发摘要
- 端到端（2026-10-13，`make cli` 后，`duo install leafmark --yes --json`；0.9.1 → 0.9.2，0.9.1 取自 manifest `previous[]` 的 `.tar.gz`）:
  - 设置打开、不运行: `duo check` `0.9.1 → 0.9.2 [MyGo, in-place]` → `installed`，`bytesDownloaded: 161516`（只下补丁，全量是
    10297458），14.3 s → 0.9.2、ad-hoc 封印有效、`Identifier=dev.leafmark.app`、与厂商 0.9.2 `diff -r` 一致、`duo backups` 有 0.9.1
  - 设置打开、运行中: app 启动后弹出自己的「发现新版本 0.9.2 / 取消 / 确定升级」窗口，60 s 内磁盘不变、没有暂存目录
    （MyGo 暂存在 `/Applications/.Leafmark.app.update-*`）。`duo install` `installed`（161516 B）→ `duo restart leafmark` →
    新进程跑 0.9.2，之后 10 s 磁盘保持 0.9.2，与厂商 0.9.2 一致
  - 设置关闭: `duo check` `0.9.1 → 0.9.2 [MyGo]`（没有 in-place）；`duo install` `skipped`，原因「no developer signature — turn on
    one-click updates for such apps in DuoUpdater's Settings → General to install it checked by its developer's update
    signature」，磁盘保持 0.9.1。重新打开后 `installed`（161516 B）。设置已还原
- 阻塞: 无（设置关闭时只检测）

## 已知问题
- 自更新器默认先问（上面的窗口），不会自己装；勾了自动安装后与 duo 的碰撞没测，它暂存的只会是同一个版本

## 建议下一步
1. 无。

## 如何复验
```
swift run --package-path application-test feed-discover <Leafmark.app 0.9.2>
#   declared  https://github.com/KevinXC5/leafmark/releases/latest/download/update-darwin-arm64.json
#   (MyGo: the binary links this feed and key arFeLNqU…; MyGoUpdateSource already resolves this app — no recipe)
swift run --package-path application-test channel-verify <0.9.1 的 .tar.gz 解出的 Leafmark.app>
#   winning source MyGo；latest 0.9.2；deltas 3；changelog pane → source structured: 22 entries
duo verify --mygo --only leafmark        # → mygo:dev.leafmark.app ✓（夜扫：feed 解析、包可下、最小签名文件用目录里的 key 验过）
# 端到端: ditto <0.9.1 bundle> /Applications/ → duo install leafmark --yes --json → bytesDownloaded 161516
```
