# Lapce

## 基本信息
- App: Lapce — Rust 写的代码编辑器，开源
- Bundle ID: `io.lapce`
- 仓库: `lapce/lapce`
- Team ID: `CYSGAZFR8D`（Developer ID + 公证；v0.1.0、v0.2.8、v0.4.5、v0.4.6、2026-10-09 nightly 全部同一 Team，`codesign --verify --deep --strict` 通过）
- 观测版本: 0.4.6（tag `v0.4.6`，资产 `Lapce-macos.dmg`，`CFBundleVersion` 1）；观测日期: 2026-10-20
- 自更新机制: 自研（`lapce-app/src/update.rs`）。每小时查一次 GitHub：stable 构建查 `releases/latest`，nightly 构建查 `releases/tags/nightly`；
  有新版只在标题栏显示「Restart to update」，用户点了才下载 `Lapce-macos.dmg`、挂载、删掉旧 `Lapce.app` 再拷新的、`open -n` 重启。
  点之前什么都不下载。v0.1.0 还没有这个更新器（二进制里没有 `releases/latest` / `Restart to update`）
- 分发: GitHub Releases；Homebrew cask `lapce`（url 即 GitHub 资产，`auto_updates` 未设）。没有 MAS，没有 nightly cask

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|             | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|-------------|---------|----------|-----|--------|-------------|
| **stable**  | —       | ✓（cask 装的副本走 brew） | — | ✓ | — |
| **nightly** | —       | —        | —   | ✗（识别、不推 stable；见下） | — |

当前生效源: **GitHub**（channel-verify：`winning source GitHub`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `io.lapce` | 共享 | 可执行文件里的 `Lapce-Stable`（不读，缺 nightly 标记即 stable） | `/releases/latest` | ✓ |
| nightly | `io.lapce` | 共享 | 可执行文件里的 `Lapce-Nightly`（`LapceBuild`） | 无 rule，stable rule 让位 | ✗ 仅识别 |

- nightly 怎么发（`.github/workflows/release.yml`，读于 2026-10-20）: 每天 `cron: 0 0 * * *`，删掉旧的 `nightly` release 和 tag，
  再以 `--prerelease` 建同名 `nightly`。资产名与 stable 相同（`Lapce-macos.dmg`），同 id、同 Team。
- 它和 stable 在 Info.plist 上**完全一样**: plist 是仓库里的模板 `extra/macos/Lapce.app/Contents/Info.plist`，版本只在
  `release: vX.Y.Z` 提交里改，所以两次 release 之间的 nightly 都报上一版的号。2026-10-09 nightly（commit f66ffaa）与 v0.4.6
  的 Info.plist `diff` 为空，都是 `0.4.6`。
- 唯一的区别编进了可执行文件: `lapce-core/build.rs` 按 `RELEASE_TAG_NAME` 写 `NAME = "Lapce-<Stable|Nightly|Debug>"`
  和 `VERSION`（nightly 为 `0.4.6+Nightly.f66ffaa`）。实测: nightly 含 `Lapce-Nightly` 2 次、`Lapce-Stable` 0 次；
  v0.4.6 / v0.4.5 含 `Lapce-Stable` 3 次、`Lapce-Nightly` 0 次。`+Nightly.` 不能当标记——stable 里也有（更新器拼 nightly 版本号的格式串）。
- **为什么必须识别 nightly**: 只有 stable rule 时 nightly 副本被当成 stable，下一个 stable 发布时会被推送并一键装到 nightly 上——
  换了轨道，而且 app 按 `NAME` 找数据目录（`~/Library/Application Support/dev.lapce.Lapce-Nightly` vs `…Lapce-Stable`），
  用户会看到设置和插件「没了」（`…Lapce-Stable` 是 cask 的 zap 列出的路径；`…Lapce-Nightly` 按 `ProjectDirs::from("dev", "lapce", NAME)` 推得，未在真机上看）。所以 `LapceBuild` 把它判为 `.nightly`，`GitHubReleasesSource` 的渠道闸让 stable rule 跳过它。
- **为什么 nightly 不接 rule（缺口的理由）**: nightly tag 叫 `nightly`，不带版本；装好的副本 plist 版本在两次 release 之间不动，
  所以没法用版本号比新旧。能比的只有 commit（二进制里 `+Nightly.<7 位>` 对 release 的 `target_commitish`），
  这要 `BuildLineage` / `headBuildPattern` 那一类按 commit 排序的机制，而它们只在 VendorProbe 上有、`GitHubReleaseRule` 没有。
  nightly 自己的更新器每小时查 `releases/tags/nightly`，用户点一下就跟上。
- 其他: 按 `build.rs`，本地 release 构建不带 `v` tag 也会编成 `Lapce-Nightly`（未实测），同样被识别为 nightly、不推 stable。

## 更新检测
- 源: `lapce/lapce` GitHub Releases，`/releases/latest`
- 版本方案: tag `v0.4.6` → `CFBundleShortVersionString` `0.4.6`、`CFBundleVersion` 恒 `1`
- `versionPattern` `^v([0-9]+(?:\.[0-9]+)+)$`：读全部 34 个非 prerelease tag（v0.0.6 … v0.4.6）；锚定，`nightly` 和带后缀的 tag 不读
- install pattern `^Lapce-macos\.dmg$`（universal，文件名不带版本；同 release 里的 `Lapce-windows-portable.zip` 等不匹配）
- 实测（2026-10-20，channel-verify，真包）:
  - v0.4.5 → `detected channel stable`，`winning source GitHub`，`latest 0.4.6`，`status UPDATE → 0.4.6`
  - v0.4.6 → `detected channel stable`，`latest 0.4.6`，`status up to date`
  - nightly（2026-10-09）→ `Lapce build nightly`，`detected channel nightly`，`winning source <none>`，`status unknown (no source answered)`
- **早期版本段（缺口）**: v0.0.6 – v0.2.0（2022-01 – 2022-09）的包 plist 版本是占位的 `0.10.0-dev`（v0.1.0 真包实测；仓库模板到
  `fdb1e52 bump version to 0.2.1` 才开始盖真实版本，v0.2.8 真包为 `0.2.8`）。这些副本被判为 `.dev`，没有源应答，不推任何东西（v0.1.0 实测
  `detected channel dev`、`no source answered`），不会被误装。要覆盖它们得从二进制读真实版本，而且仅判成 stable 也没用（`0.10.0` 比 0.4.6 大，会显示已是最新）；
  这一段也没有自己的更新器。`BundleIDMigration`（同 id）、`OneClickGate`（本来就不推）、`.publishedDigestOnly`（有 Team）都不适用。

## 按架构 / 按 OS 分轨
- 架构: x86_64 arm64（universal）；`LSMinimumSystemVersion`: 无（Makefile `MACOSX_DEPLOYMENT_TARGET=10.11`）。release 不声明上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | `update.rs` 只下整个 `Lapce-macos.dmg` | v0.4.6 的 23 个资产里没有 patch（macOS 只有 `Lapce-macos.dmg`，另两个 `lapce-proxy-darwin-*.gz` 是给远端主机的 proxy） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 没查（未跑运行中一轮） | — |
| 证据 | `download_release` 只在用户点「Restart to update」后执行，下载完立刻 `extract` + `restart`；文件 `~/Library/Application Support/dev.lapce.Lapce-Stable/updates/Lapce-macos.dmg`，macOS 上 `cleanup()` 不删，留下的是**已装上**的那版 | — | — |

- 记录文件与字段: 无（没有完成记录，也没有摘要）
- 容器: dmg，根目录 `Lapce.app` + `Applications` 链接
- 两份副本会不会共用这个目录: stable 副本共用 `dev.lapce.Lapce-Stable/updates/`，nightly 用 `dev.lapce.Lapce-Nightly/updates/`（按源码推得）

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource`）
- 结构化: ✓。channel-verify `changelog pane`: `source structured: 1 entries; newest 0.4.6: 9 items, headings ["Features/Changes", "Bug Fixes"]`
- 跟随 channel: 是（nightly 不显示 stable 的说明：nightly 没有源应答）
- Recipe 状态: 不需要

## 一键安装
- 状态: 支持（stable）；nightly 副本不推
- 端到端: 未跑（交给主会话真机：v0.4.5 → v0.4.6）
- 格式: dmg（universal）
- 校验: GitHub digest `sha256:d4ba42218148446c265c6a823107a969b3b0dca5e14df834563f2859927228f5`，与下载的 v0.4.6 包 `shasum -a 256` 一致；
  v0.4.5 `sha256:354e7e5b…13b8` 同样一致；规则无需额外配置
- **读的是**: 人人可手动下载的 GA（`/releases/latest`）
- 嵌套: 无（`Contents/` 下只有 `MacOS/lapce`、`Resources/lapce.icns`）
- 自更新器会不会和我们抢: 不会。它只在用户点击后才下载并立刻替换；没有后台下载
- 阻塞: 无

## 已知问题
- nightly 轨只识别不更新（见 Channel 详情）
- v0.0.6 – v0.2.0 的 `0.10.0-dev` 副本不检测（见更新检测）
- 识别 nightly 要读整个可执行文件（universal，按 size+mtime 缓存，同一份只读一次）

## 建议下一步
1. 主会话真机一键：v0.4.5 → v0.4.6（不运行 + 运行中两轮），回填本节和 README 行
2. 若要接 nightly：需要 `GitHubReleaseRule` 按 commit 比较（二进制 `VERSION` 的 `+Nightly.<sha7>` 对 `nightly` release 的 `target_commitish`）

## 如何复验
```bash
gh release download v0.4.6 -R lapce/lapce -p Lapce-macos.dmg -D v0.4.6
gh release download nightly -R lapce/lapce -p Lapce-macos.dmg -D nightly
.claude/skills/coverage-discovery/scripts/check-bundle.sh v0.4.6/Lapce-macos.dmg
swift run --package-path application-test channel-verify v0.4.6/Lapce-macos.dmg --expect stable
swift run --package-path application-test channel-verify nightly/Lapce-macos.dmg --expect nightly   # Lapce build nightly、no source answered
```
