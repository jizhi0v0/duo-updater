# Search（Office Commun）

## 基本信息
- App: Search — 基于 WebKit 的小型浏览器
- Bundle ID: `com.officecommun.search`
- 仓库: `driceroland/Search`（MIT）
- Team ID: `7BYKA895MC`（Developer ID + 公证；1.0.3 与 1.0.4 两个 dmg 相同）
- 观测版本: 1.0.4（build `202609272118`）；观测日期: 2026-10-09
- 自更新机制: 自研（`Sources/Search/Updater.swift`）。启动时及之后每小时读
  `https://officecommun.com/search/appcast.json.zip`——codesign 签过的 `appcast.json`，要求 Team `7BYKA895MC`
  与标识 `com.officecommun.search.appcast`——下载 feed 里的 `Search.zip`，核 `sha256` 后**在 app 运行中直接换掉
  bundle**（旧 bundle 改名为同目录的 `Search.app.old`，退出或下次启动时删掉）。不自动重启。无 Sparkle、无 `SUFeedURL`
- 分发: GitHub Releases、官网（同一份文件）、第三方 tap `driceroland/tap/search`（`auto_updates true`）
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | ○           |

当前生效源: **GitHub**（channel-verify 实测）。

## Channel 详情

只有一条轨。settled from source：`build.sh` / `publish.sh`（`main`）每个芯片只写一份 `appcast.json`，没有
prerelease 或渠道字段；GitHub 上 5 个 release（v1.0 – v1.0.4）都不是 prerelease。

## 更新检测
- 源: `driceroland/Search` GitHub Releases，tag `v1.0.4` 形状，去掉 `v` 等于 `CFBundleShortVersionString`
- `CFBundleVersion` 是构建时间 `YYYYMMDDHHMM`（`build.sh`），不参与比较
- 厂商 feed（备选，未接）: `https://officecommun.com/search/appcast.json` 给出 `version`、`url`（zip）、`dmg`、
  `sha256`、`dmgSha256`、`notes`（一段话）、`minimumSystemVersion`。2026-10-09 它的 `dmgSha256` 与 GitHub 上
  `Search.dmg` 的 `digest` 相同，`sha256` 与 `Search.zip` 的 `digest` 相同——两边是同一批文件
- 选 GitHub 而不是厂商 feed 的原因: release 正文是分小节的完整 changelog（feed 的 `notes` 只有一段摘要），
  资产自带 `digest`，Intel 构建由资产名的 `Intel` 标记自动分开

## 按架构 / 按 OS 分轨
- 1.0.4 及以前只有 Apple silicon（`lipo -archs` = `arm64`）。`build.sh` 写明 1.0.5 起 Intel 单独出包：
  GitHub 上叫 `Search-Intel.dmg`（`tap.sh`），官网在 `/search/intel/appcast.json`（2026-10-09 时 404，尚未发布）
- install pattern `^Search(-Intel)?\.dmg$`：资产选择器把 `Intel` 认作 x86_64 标记，Intel Mac 选 `Search-Intel.dmg`，
  Apple silicon 选不带标记的 `Search.dmg`
- `LSMinimumSystemVersion` = `14.0`（feed 的 `minimumSystemVersion` 同值）

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `Updater.swift` 只下整包 zip | feed 只列整包 zip/dmg（2026-10-09） | 无可消费的补丁 |

## Changelog
- 来源: GitHub Release body（开头一段摘要 + `### Added` / `### Fixed` 列表），经 `GitHubMarkdownParser`
- 结构化（2026-10-09，channel-verify `changelog pane`）: `source structured: 1 entries; newest 1.0.4: 131 items,
  headings ["Added", "Fixed"]`
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg（公证并 staple）；bundle 里没有嵌套 app 或 helper，没有 LaunchAgent
- Pattern: `^Search(-Intel)?\.dmg$`, kind `.dmg`
- 校验: GitHub 资产 `digest`（sha256）。1.0.4 下载后 `shasum -a 256` = `657ca99f…6c5`，与 `digest` 及厂商 feed 的
  `dmgSha256` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`；官网下载链接指向同一份文件）
- 端到端（2026-10-09）:
  - 不运行: 1.0.3 → `duo check` `1.0.3 → 1.0.4 [GitHub, in-place]` → `duo install --yes --json` `installed`
    （27 s，3509849 字节）→ 1.0.4 / `202609272118`、inode 变、Team 不变、`--deep --strict` 通过、`spctl` Notarized
    Developer ID、与厂商包 `diff -r` 一致、`duo backups` 有 1.0.3
  - 运行中: 重装 1.0.3 并启动。它自己的更新器在约 4 s 内就把磁盘上的 bundle 换成 1.0.4，进程仍从
    `Search.app.old` 跑 1.0.3。此时 `duo check` 为 up to date、`duo install` 无事可做；`duo restart Search` 后新进程
    跑的是 1.0.4，`Search.app.old` 被 app 自己删掉，之后 10 s 磁盘保持 1.0.4
- 阻塞: 无

## 已知问题
- **自更新器几乎总是先到。** 它在启动时就换 bundle，duo 的一键只会在 app 没运行、或运行中但一小时检查还没到时
  遇到旧版。两者装的是同一份文件，先后无所谓。
- **没法构造「app 暂存的是更旧版本」的碰撞测试。** feed 必须是厂商 Developer ID 签名的（`Updater.opened`），
  `SEARCH_FEED` 覆盖只在测试模式（`Store.testing`）下生效，所以没有办法让它暂存一个比 duo 装的更旧的构建。
  按代码推断：duo 装完后，若 app 还在跑旧版，它下一次每小时检查会再下载同一个版本并再换一次 bundle——同版本、
  同签名，无害。**这一条未实测。**
- duo 换完后 app 若仍在运行，它仍是旧代码，直到重启（与 app 自己的更新器行为一致：它也不重启）。

## 建议下一步
1. 1.0.5 发布后在 Intel 上（或用 `channel-verify` 挂 `Search-Intel.dmg`）确认选中的是 Intel 包。

## 如何复验
```
swift run --package-path application-test channel-verify <Search 1.0.3 的 Search.app>   # → UPDATE → 1.0.4，winning source GitHub
swift run --package-path application-test feed-discover <Search.app>                    # → no Sparkle and no electron-builder update config
```
