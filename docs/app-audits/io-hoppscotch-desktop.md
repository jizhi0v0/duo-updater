# Hoppscotch

## 基本信息
- App: Hoppscotch Desktop — 开源 API 客户端（Postman 类），Tauri v2；发版仓库 `hoppscotch/releases`（只放二进制），源码在 `hoppscotch/hoppscotch` 的 `packages/hoppscotch-desktop`
- Bundle ID: `io.hoppscotch.desktop`（Cloud 与 Self-Host 两个版本、以及第一代 app 全用这一个 id）
- Team ID: `XBK86CMQGZ`（26.8.2、26.9.0、25.2.0、第一代 25.1.1-2 的真包都是这个；arm64 与 x64 相同）
- 观测版本: 26.9.0（tag `v26.9.0-0`，2026-09-30）；上一版 26.8.2（`v26.8.2-0`）；观测日期: 2026-10-22
- 自更新机制: Tauri v2 `tauri-plugin-updater` 2.3.1（可执行文件里的 user agent 字符串 `tauri-plugin-updater/2.3.1`），读 `https://releases.hoppscotch.com/hoppscotch-cloud-desktop.json`（Cloud）或 `…/hoppscotch-selfhost-desktop.json`（Self-Host）。用户在 app 里点更新时才下载（`updater.rs` 的 `download_and_install_update` 由前端调用），下到内存里，再当场换包
- 分发: GitHub Releases（每版 Cloud + Self-Host 各一对 arm64/x64 dmg、tar.gz），Homebrew cask `hoppscotch`（装 Cloud arm64 dmg）和 `hoppscotch-selfhost`（装 Self-Host arm64 dmg），都没有 `auto_updates`。没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓（通用 cask 源，仅 brew 装的副本） | — | ✓ | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（channel-verify，非 brew 装的副本；brew 装的副本由排在前面的 `HomebrewCaskSource` 应答）。`feed-discover` 对 26.9.0 Cloud dmg: `no Sparkle, no electron-builder update config and no MyGo feed`。

## 覆盖清单
- **各版本的 bundle id / Team**（读真包）: 23.8.3-1、25.1.1-0、25.1.1-2（第一代）、25.2.0、26.8.2、26.9.0（Cloud 与 Self-Host）都是 `io.hoppscotch.desktop`、Team `XBK86CMQGZ`、`spctl` Notarized Developer ID。没有改过 id，Team 没换过。
- **同一 id 下的两个版本（Cloud / Self-Host）**: 同一个 release 同时发 `Hoppscotch_mac_<arch>.dmg`（Cloud）和 `Hoppscotch_SelfHost_mac_<arch>.dmg`。26.9.0 两个 arm64 包的 Info.plist 字节相同（md5 一样），版本、id、Team 也一样，差别只在可执行文件 `Contents/MacOS/hoppscotch-desktop` 里编进去的更新地址。规则只装 Cloud；Self-Host 副本由 `OneClickGate` 的 `.executableContains` 挡在一键之外，仍然有检测（两个版本共用 tag，版本号对 Self-Host 同样正确）。
- **第一代 app（v23.8.3-1 … v25.1.1-2）**: 可执行文件叫 `Hoppscotch`，更新源 `https://releases.hoppscotch.com/central-desktop.json`，bundle 版本保留 tag 的 `-N`（`23.8.3-1`、`25.1.1-0`、`25.1.1-2`）。`central-desktop.json` 至今（2026-10-22）仍是 `v25.1.1-2`，厂商没有把这一代迁到第二代。第二代从 `v25.2.0-0` 开始，bundle 版本不带后缀（`25.2.0`）。第一代副本由 `.installedVersion(^[0-9]+(?:\.[0-9]+)+$)` 挡在一键之外，检测照常（版本比较读到 `25.1.1-2` < `26.9.0`，channel-verify 显示 UPDATE → 26.9.0）。
- **x64 副本**: x64 的 Cloud（25.2.0、26.8.2、26.9.0）和 Self-Host（26.9.0）可执行文件里都**没有**完整的更新地址字面量（只有 `ch-cloud` / `ch-selfh` 这样的碎片），所以 `.executableContains` 对任何 x64 副本都不放行（失败即拒）。DuoUpdater 只跑 arm64（`App/project.yml` `ARCHS: arm64`），x64 副本只会是 Rosetta 下跑的 Intel 版；它们保留检测、没有一键。
- **版本范围、主机下限**: 所有样本 `LSMinimumSystemVersion` 10.13，低于我们的下限。
- **其他轨**: 88 个 release 全部不是 prerelease，没有 beta/nightly。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable（Cloud，第二代 arm64） | `io.hoppscotch.desktop` | 共享 | 可执行文件含 `hoppscotch-cloud-desktop.json` | GitHub `/releases/latest` | ✓ 检测 + 一键 |
| stable（Self-Host） | 同上 | 共享 | 可执行文件含 `hoppscotch-selfhost-desktop.json` | 同一条规则 | ✓ 检测，一键由 gate 拒 |
| 第一代 | 同上 | 共享 | bundle 版本带 `-N` | 同一条规则 | ✓ 检测，一键由 gate 拒 |

## 更新检测
- 源: `hoppscotch/releases` GitHub Releases，`/releases/latest`（2026-10-22 是 `v26.9.0-0`）
- 版本: `^v([0-9]+(?:\.[0-9]+)+)-[0-9]+$`，读 tag 的主版本、丢掉 `-N`。88 个非 prerelease tag 全部能读（`-0` 67 个、`-1` 15 个、`-2` 5 个、`-3` 1 个）。`25.1.1`、`24.6.0`、`24.3.1`、`23.12.3`、`23.12.0` 各有 2–3 个 tag，都是第一代的重发
- 资产: `^Hoppscotch_mac_(?:aarch64|x64)\.dmg$`，按主机架构选；Self-Host 资产、tar.gz、Windows/Linux 包不匹配。`v26.6.1-0` 只发了 Self-Host 资产，那一版对 Cloud 没有可装的包
- Release 正文只有一行（`chore: bump cloud-desktop and selfhost-desktop to 26.9.0-0`）

## 按架构 / 按 OS 分轨
- 架构: 分架构资产（`_aarch64` / `_x64`），各自单架构（`lipo -archs`: `arm64` / `x86_64`）。`LSMinimumSystemVersion` 10.13

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | tauri-plugin-updater 2.3.1 只下整包 tar.gz（`download` 返回 `Vec<u8>`） | `hoppscotch-cloud-desktop.json` 每个平台只有 `url` + `signature`（2026-10-22） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 不会 | 无（2026-10-22 真机运行 Cloud 26.8.2，没有停放任何东西） | 不需要 |
| 证据 | tauri-plugin-updater 2.3.1 `src/updater.rs`（tag `updater-v2.3.1`）：`download` 把整包读进内存，macOS `install_inner` 把当前 app rename 到临时目录、把 tar.gz 直接解到原路径；不写停放文件 | — | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-22，channel-verify `changelog pane`，从 26.8.2 起）: `source structured: 1 entries; newest 26.9.0: 1 items, headings []; first items ["chore: bump cloud-desktop and selfhost-d"]`
- **面板只有一行 bump 说明。** GitHub 正文每版只有这一行；完整的发版说明在厂商网站（`https://hoppscotch.com/releases`、`https://hoppscotch.com/changelog` 2026-10-22 都返回 200），Tauri 清单的 `notes` 里另有一段摘要
- 跟随 channel: —（单轨）
- Recipe 状态: 待定（要不要写 ChangelogRecipe 还没决定）

## 一键安装
- 状态: **支持（Cloud 第二代 arm64 副本）**，Self-Host、第一代、x64 副本仅检测
- 端到端（2026-10-22，本分支 `make cli` 的 duo）:
  - Self-Host 26.8.2（可执行文件含 `hoppscotch-selfhost-desktop.json`）: `duo check` → `26.8.2 → 26.9.0 [GitHub]`；`duo install` → `Skipping: Hoppscotch — detection only for this copy — this is not a proven Cloud edition copy (Self-Host, or an Intel build); update it from its own updater`，磁盘仍是 26.8.2 Self-Host、inode 不变
  - Cloud 26.8.2，不运行: `duo check` → `26.8.2 → 26.9.0 [GitHub, in-place]`；`duo install` `extracting verifyingCodeSignature installing done installed.` → 26.9.0、可执行文件 inode 变、含 `hoppscotch-cloud-desktop.json`、`TeamIdentifier=XBK86CMQGZ`、`codesign --verify --deep --strict` 退出 0、`spctl` accepted、`diff -r` 与厂商 26.9.0 Cloud 包相同
  - Cloud 26.8.2，运行中: 启动（窗口 `main`），`duo install` 后提示 `Still running the old code`；`duo restart Hoppscotch` 后新进程起来，之后 10 s 磁盘一直是 26.9.0、签名有效。启动建了 `~/Library/{Application Support,Caches,Logs,WebKit}/io.hoppscotch.desktop`
- 格式: dmg（UDZO），根目录 `Hoppscotch.app`。Pattern `^Hoppscotch_mac_(?:aarch64|x64)\.dmg$`，kind `.dmg`
- 嵌套: 没有。`Contents` 只有 `MacOS/hoppscotch-desktop`、`Resources/icon.icns`、`Info.plist`、签名；没有 LoginItems / Helpers / LaunchAgent，没有 `LSUIElement`
- 签名: 26.8.2、26.9.0 都是 `TeamIdentifier=XBK86CMQGZ`，`codesign --verify` 通过，`spctl` Notarized Developer ID
- 校验: GitHub 资产 `digest`。26.9.0 `Hoppscotch_mac_aarch64.dmg` `sha256:a4aebe60…3a1b`、48686523 字节；26.8.2 `sha256:f307364a…7aab`、48213102 字节；下载的 dmg `shasum -a 256` 相同
- **读的是**: 人人可手动下载的 GA（`/releases/latest`，也是 Homebrew cask 用的资产）
- **门控**（`OneClickGate`，都要放行）:
  1. `.installedVersion(^[0-9]+(?:\.[0-9]+)+$)` — 第一代（版本带 `-N`）拒
  2. `.executableContains("hoppscotch-cloud-desktop.json")` — 读 `Contents/MacOS/<CFBundleExecutable>`，按 4 MiB 分块 `read(2)`、不映射。真包结果: Cloud arm64 25.2.0 / 26.8.2 / 26.9.0 放行；Self-Host arm64 26.8.2 / 26.9.0、x64 Cloud 25.2.0 / 26.8.2 / 26.9.0、x64 Self-Host 26.9.0、第一代 25.1.1-2 拒
- 第 2 个 gate 的结论按 bundle 缓存，键是 Info.plist 和可执行文件各自的 (device, inode, size, mtime)；重复询问只做两次 `stat`，不重新解析 plist。安装时（`InstallCoordinator.perform`）不走缓存、重读一次。只读普通文件（`open` 带 `O_NONBLOCK`，再 `fstat`），超过 256 MiB 不读、不放行
- 门控开销（2026-10-22，Release 构建，`OneClickGate.admits` 减同一路径上立即返回的 requirement，n=12 次首次调用、144 次重复调用；当时 load average 约 55，有一个 xcodebuild 在跑）:
  - 首次调用（缓存空）: Cloud 26.9.0（标记在 15.9 MB 处，读到第 4 块就停）冷读中位 12.7 ms / p90 12.9 ms，热读 11.6 / 12.0 ms；Self-Host 26.9.0（67 MB 全读）冷读 48.7 / 49.7 ms，热读 46.8 / 47.7 ms
  - 重复调用（命中缓存）: 中位 12–13 µs，p90 15–20 µs
- 阻塞: 无

## 已知问题
- Self-Host、第一代、x64 副本只有检测没有一键，见上。x64 Cloud 副本被拒是因为字面量不完整，不是因为它是别的版本；可执行文件里另有 `Sitemap: https://hoppscotch.io/sitemap.xml`（Cloud）/ `Sitemap: http://localhost:3000/sitemap.xml`（Self-Host）可以同时分出两种架构（上面所有样本都对得上），没有用
- changelog 面板只有一行 bump 说明，见上
- `hoppscotch-selfhost` cask 装的副本也没有一键：gate 对所有路线都生效，`brew upgrade --cask` 这条也被拒，只剩检测
- 安装时的 gate 在 `InstallCoordinator.perform` 开头读一次（不走缓存），到换包之间副本若被换成别的版本，不会再查
- 下载下来的包不查版本：`Hoppscotch_mac_*.dmg` 按资产名认作 Cloud，不读包里可执行文件的标记
- 没有「不包含」这种 requirement，表达不了「不是 Self-Host」，所以 x64 Cloud 副本只能一起拒掉

## 如何复验
```
gh release view v26.9.0-0 -R hoppscotch/releases --json assets -q '.assets[]|.name+" "+.digest'
swift run --package-path application-test feed-discover Hoppscotch_mac_aarch64.dmg        # → no Sparkle / electron / MyGo
swift run --package-path application-test channel-verify <26.8.2 Cloud dmg> --expect stable   # → GitHub，UPDATE → 26.9.0
swift run --package-path application-test channel-verify <26.9.0 Cloud dmg> --expect stable   # → up to date
.claude/skills/coverage-discovery/scripts/check-bundle.sh <dmg>                          # → XBK86CMQGZ, Notarized
grep -a -c -F hoppscotch-cloud-desktop.json <app>/Contents/MacOS/hoppscotch-desktop      # Cloud arm64 1, Self-Host 0
curl -s https://releases.hoppscotch.com/central-desktop.json | head -3                     # 第一代仍是 v25.1.1-2
swift test --package-path DuoUpdaterCore --filter OneClickGateTests
```

## 历史与实测
- 2026-10-22（从 `io-hoppscotch-desktop.swift` 注释迁出）：原文「the pattern reads every tag's base version and the suffix is dropped: all 88 tags read (2026-10-22). v26.6.1-0 shipped SelfHost assets only: nothing to install then.」——当天 88 个非 prerelease tag 全部读得出；v26.6.1-0 只有 SelfHost 资产。

## 建议下一步
1. 决定要不要为 hoppscotch.com 的发版说明写 ChangelogRecipe。
