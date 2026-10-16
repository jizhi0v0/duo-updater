# Stremio

审计 2026-10-16（首次接入）。所有结论来自厂商真包（挂载只读，未启动）和端点实测。

## 基本信息
- Bundle ID: `com.westbridge.stremio5-mac`（5.1.16 起）；更早的 v5 是 `com.stremio.stremio-shell-macos`（见下）
- Team ID: `BH62GT22G7` — Developer ID Application: West Bridge Ltd（5.1.16、5.1.18、5.1.26、5.1.27、5.1.28
  逐个读过，全部相同，均 `Notarized Developer ID`）
- 观测版本: `5.1.28`（short = build），上一版 `5.1.27`。`LSMinimumSystemVersion` 10.13.5，主二进制 `minos 11.0`，
  捆绑 dylib 最高 `minos 12.0`；`Stremio_arm64.dmg` 只有 arm64，Intel 是另一个文件 `Stremio_x64.dmg`
- 自更新机制: 自研（Rust 外壳，二进制里 `src/updater.rs`）。问 `updater/check`，下载 dmg、校验 SHA-256，
  然后写一个 `stremio-updater.sh`：`hdiutil mount` → `cp -R` 到 `/Applications/<时间戳>.app` →
  `rm -rf /Applications/Stremio.app` → `mv` → `open`（脚本原文在二进制字符串里）
- Homebrew: cask `stremio`（5.1.26，`auto_updates true`，livecheck 读下载页）与 `stremio@beta`
  （livecheck 读 `updater/check`；Sequoia 及更早钉 5.1.27，Tahoe 起 5.1.28）
- 外壳闭源（Stremio 的 GitHub 组织里没有 macOS shell 仓库；Windows 的 `stremio-shell-ng`、Linux 的
  `stremio-linux-shell` 是另外的产品线）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —（`auto_updates`，让位） | — | — | ✓ 一键 |
| **rc**       | —       | —       | —   | —      | — 未接（见下） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Vendor**（`Recipes/com-westbridge-stremio5-mac.swift`）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.westbridge.stremio5-mac` | — | — | `updater/check` 的 `version` | ✓ |
| stable（旧 id） | `com.stremio.stremio-shell-macos` | — | — | 同一端点 | ✓ 仅检测 |
| rc      | 共享 | 共享 | 启动参数 `--release-candidate` | 查询加 `rc` | 未接 |

### Coverage checklist

- **每个 bundle id**
  - `com.westbridge.stremio5-mac`：5.1.16 – 5.1.28，recipe + 一键。
  - `com.stremio.stremio-shell-macos`：5.1.14 读到的就是这个 id，ad-hoc 签名（`TeamIdentifier=not set`，
    `codesign` 报 `code has no resources but signature indicates they must be present`），Homebrew 当时给这版
    标了 `fails_gatekeeper_check`。它的更新器问同一个 `updater/check`，安装脚本直接把 `/Applications/Stremio.app`
    换成 dmg 里的 app，等于厂商把旧 id 迁到新 id。`BundleIDMigration` 要求两边同一 Team，这里旧端没有 Team，
    所以旧 id 单独一条**仅检测** recipe（实测 5.1.14 → `UPDATE 5.1.14 → 5.1.28`，下载链接是下载页）。
    5.1.15 在 CDN 上 404，5.1.10 / 5.1.12 / 5.1.13 的 dmg 还在，它们的 id 没读，按 5.1.14 推断同为旧 id（**未验证**）。
  - `com.smartcodeltd.stremio`（Stremio 4.4，Qt 外壳）：**不接，有记录的缺口**。4.4.172 真包：x86_64 only，
    没签名（`codesign` 无 Authority）。它自己的更新器（开源 `Stremio/stremio-shell` 的 `autoupdater.cpp`）
    带 `shellVersion` 问同一个 `updater/check`，实测 `shellVersion=4.4.172` 和 `4.4.106` 都回
    `{"upToDate":true,"expiredRelease":"4.4.183"}`：厂商不把 v4 推到 v5，也不再给 v4 发版。bundle id、
    签名、架构都和 v5 不同，跨代推送是厂商自己没做的事。
  - Stremio Lite（下载页 "Native version"，`dl.strem.io/apple/macos/release/Stremio-2.0.7-….zip`，AltStore
    源里是 `com.stremio.pal` 2.0.8）：另一个产品、另一条版本线，不在本次范围。
- **每条轨**: 二进制有 `--release-candidate`（"Check for RC updates"）启动参数，查询带 `rc` 时端点给
  `…/[versions]/rc/v5.1.28_arm64.json`、`version` 也是 5.1.28（2026-10-16）。这是命令行开关，没有设置项，
  普通副本不会进这条轨，且装出来的包和 stable 同 id、版本串不带后缀，副本上分不出来。所以不接。
- **每个版本区间**: 5.1.16 起 Team 一直是 `BH62GT22G7`，一键闸对所有新 id 副本都成立；旧 id 副本见上。
- **我们的宿主下限**: DuoUpdater 只跑 Apple silicon、macOS 15+。Intel 的 x64 dmg 不需要规则。Homebrew
  `stremio@beta` 在 Sequoia 及更早钉 5.1.27 的原因，它的提交（`46e7346e1`）和 PR #289263 都没写。5.1.27 与
  5.1.28 的 `LSMinimumSystemVersion`、主二进制 `minos`、dylib 最高 `minos` 完全相同；厂商端点不按 OS 分
  （请求里没有 OS 参数）。所以 recipe 跟随厂商，给 macOS 15 也提供 5.1.28。**5.1.28 在 macOS 15 上能否
  正常运行未验证。**
- **版本 pattern**: 绑定 JSON 的 `version` 键，`^[0-9]+(\.[0-9]+)+` 后必须紧跟引号。测试覆盖 5.1.14、5.1.16、
  5.1.26、5.1.28、6.0.0、5.2；`5.1.29-rc.1` 读成 nil；`{"error":"unknown product"}` 读成 nil。
  CDN 上读到的 v5 版本全是 `5.1.N` 三段。

## 更新检测
- 源: `VendorProbeSource`，端点 `https://www.stremio.com/updater/check?product=stremio-shell-macos&arch=arm64`
  （二进制里三个主机 `www.strem.io` / `www.stremio.com` / `www.stremio.net`；查询形状与 Homebrew `stremio@beta`
  livecheck 相同。外壳自己的请求**没有抓包**，它有 `--autoupdater-endpoint` 覆盖开关，可以用来抓）
- 回答（2026-10-16）: `{"versionDesc":"https://dl.strem.io/stremio-shell-macos/[versions]/v5.1.28_arm64.json?from=website&init=1488695","version":"5.1.28"}`
- descriptor: `{"version":"5.1.28","tag":"v5.1.28","released":"2026-09-22T11:34:53.000Z","arch":"arm64","files":[{"url":"…/v5.1.28/Stremio_arm64.dmg","checksum":"cd1963db…","os":"macos",…}]}`
- **下载页落后于更新器**: 2026-10-16 下载页仍链 5.1.26，更新器（不带 rc）已经给 5.1.28，所以 5.1.26 副本
  会被自己的更新器升到 5.1.28。recipe 跟更新器。
- 不带 `arch` 时 `versionDesc` 是无架构的 `v5.1.28.json`，`version` 相同。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 更新器只下整包 dmg 并按 descriptor 的 SHA-256 校验（`---> Checksum verified.` 等字符串） | descriptor 的 `files` 只有一个 dmg（5.1.26、5.1.28 两份读过） | — |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 会（下载后等安装脚本） | 5.1.27 运行中停放了完整的 5.1.28 dmg（实测） | 不需要（见下） |
| 证据 | 字符串：`Fetching updates`、`Checksum verified.`、`stremio-updater.sh`（参数是 dmg 路径，装完 `rm "$DMG"`） | 2026-10-16 真机：启动 5.1.27 后约 90 s 出现 `$TMPDIR/Stremio_arm64.dmg`（113,661,066 B，UDZO，内含 5.1.28）；app 运行期间、退出时、5.1.28 再启动 80 s 内都没有跑 `stremio-updater.sh`，bundle 不动 | 一键自己下载厂商 dmg，不读它 |

- dmg 存放目录: `$TMPDIR/Stremio_arm64.dmg`（2026-10-16 实测；文件名不带版本）。

## Changelog
- 来源: 无
- 结构化: `changelog pane  none — the pane says there are no release notes`（5.1.27 与 5.1.28 两个包同一行）
- 更新器的两个 JSON 都不带说明；`www.stremio.com/changelog`、`/release-notes`、`/whats-new` 都 404；
  外壳仓库不公开；`blog.stremio.com` 是公告博客，不按版本。`stremio-shell-ng`（Windows，v5.0.26 与
  macOS 5.1.28 同一天发）有 GitHub release 说明，但那是另一个外壳、另一条版本号，对不上 macOS 的版本
- 跟随 channel: —
- Recipe 状态: 不需要（没有可按版本对上的页面）

## 一键安装
- 状态: 支持（`install: .versionTemplate("https://dl.strem.io/stremio-shell-macos/v{version}/Stremio_arm64.dmg")`，`.dmg`）
- 端到端: 真机端到端（2026-10-16，集成分支 `make cli`）：5.1.27 → 5.1.28，`backed up … verifyingCodeSignature … installed.`；装后 Team 不变、`spctl` Notarized Developer ID，`duo check` 报 up to date
- 格式: dmg（UDZO，无 SLA；根目录 `Stremio.app` + `Applications` 软链接；5.1.28 为 113,661,066 B）
- 校验: **不接**。descriptor 的 `checksum` 是 dmg 的 hex SHA-256，真实下载相等（5.1.28
  `cd1963dbf0c26900d8880f440a2e7e0c3841c8f58b7e23e6491f9f66d066fd3d`、5.1.27 `ec1364e4…`、5.1.26 `f85286f2…`，
  `shasum -a 256` 与 descriptor / cask 一致）。但它在第二跳 JSON 里，probe 读的 `updater/check` 回答里没有，
  recipe 表达不了两跳。Team 闸是唯一的完整性检查
- **读的是**: 轨道最新（`updater/check` 不带设备信息，所有副本同一答案；比下载页新一版，见上）
  - 可以接受的原因: 厂商自己的更新器给每个副本的就是这个版本
- 包内常驻物: 没有嵌套 `.app`、没有 `Contents/Library`、没有 LaunchAgent / SMAppService 字符串。
  `Contents/MacOS/node` + `server.js` 是 app 运行时拉起的流媒体服务子进程（`127.0.0.1:11470`），
  随 app 退出（字符串 `Stremio server stopped.`；未实测）
- 旧 id `com.stremio.stremio-shell-macos`：仅检测（ad-hoc 签名，没有 Team 可比）

## 已知问题
- Homebrew `stremio@beta` 给 macOS 15 钉 5.1.27，原因未公开；我们给 macOS 15 提供 5.1.28（跟厂商）。
- 外壳自己的更新器停放的 dmg 在 duo 换包后不会被再装一次（运行中一轮实测，见建议下一步 1）；装好后它留在 `$TMPDIR` 里。

## 建议下一步
1. （已做）运行中一轮，2026-10-16，main `make cli`：5.1.27 运行中、自带更新器已停放 5.1.28 dmg，`duo install --yes` → `installed.` 并提示 `Still running the old code: Stremio`；`duo restart` → `restarted`，新进程映射 5.1.28 的主程序；之后正常退出、再启动 5.1.28 观察 80 s，`stremio-updater.sh` 都没跑，bundle inode 不变。Team `BH62GT22G7`、`codesign --strict` 0、Notarized。新增 `~/Library/{Application Support/stremio-server, Caches/com.westbridge.stremio5-mac, Preferences/com.westbridge.stremio5-mac.plist, WebKit/com.westbridge.stremio5-mac}`，登录项前后无差异
2. 用 `--autoupdater-endpoint` 指向本地服务抓一次外壳的真实请求，核对查询参数。
