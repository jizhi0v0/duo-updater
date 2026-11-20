# Bitwarden

**这不是审计**：family `com-bitwarden-desktop`（`Recipes/com-bitwarden-desktop.swift`）里 Bitwarden `com.bitwarden.desktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 相关安装副本

- GitHub OSS：`desktop-v` 选定桌面发行版，DMG 只接受旧 `Bitwarden-…` 和新 `oss-Bitwarden-…`。
  安装目录中的 `app.asar/preload.js` 带 OSS 入口 `;// ./src/preload.ts` 才开放一键安装。
- 官网商业版和 GitHub 商业版：旧 `commercial-Bitwarden-…`，新 `bit-Bitwarden-…`。
  商业副本可检测到同一版本，需从 Bitwarden 的内置更新器或官网更新。缺失、无法读取或无法判定入口的副本同样只检测。
- Homebrew `bitwarden`：2026-11-20 cask 元数据为 `auto_updates: true`，指向无前缀的 OSS 2026.10.4 DMG。
  该 cask 仍由 Homebrew 管理，若启用 DuoUpdater 一键更新，也须通过同一已安装版别检查。
- Mac App Store：`com.bitwarden.desktop`，商品 `1352778147`。App Store 自身商品保留原有安装入口。

## 夜扫覆盖

- `duo verify --github --only com.bitwarden.desktop` 对应 `github:bitwarden/clients:stable`。
- `duo verify-install --only com.bitwarden.desktop` 下载规则选中的 OSS DMG。GitHub 商业 DMG
  及 App Store 下载由各自发行路径提供，未纳入这条 GitHub 安装检查。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-bitwarden-desktop.swift — GitHub rule（`bitwarden/clients` monorepo）

转引自 recipe 注释，未复测。

Bitwarden — the ONLY rule here that can't read `/releases/latest`: the
monorepo tags every client, and the newest release is usually `web-…` or
`cli-…`, not the desktop app (on 2026-08-16 `/releases/latest` was
`web-v2026.7.1` while the desktop app sat at `desktop-v2026.7.0`).

Measured over the newest 100 releases,
consecutive `desktop-v` tags are at most 7 apart (re-verified
2026-09-04: same 7, `desktop-v2026.6.0`→`desktop-v2026.5.0` and three
other pairs), so the desktop tag sits well inside a page of 10 today
— chosen over the observed 7 to leave margin rather than trim to the
minimum, per the same logic as every other rule in `GitHubReleaseRegistry` — but a long
burst of web/cli/browser releases would still push it off the page,
and the rule would then resolve nothing, which surfaces as the row
going quiet rather than as an error.

The newest release of this monorepo is a web/CLI/browser tag far
more often than the desktop one (measured 2026-09-05: the one-row
page was `web-v…`, and the same shape held across the newest 100
releases, `desktop-v` tags at most 7 apart), so a one-row probe
here would fall back to the full page most rounds and only add a
request.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`repos/bitwarden/clients/releases?per_page=100` 首条 `web-v2026.8.1`，第一个 `desktop-v` 在第 3 位，相邻 `desktop-v` 最大间隔 7，21 个 `desktop-v` tag 全是裸版本号、非 prerelease。

### 2026-11-20 — DMG 前缀与版别

[`desktop-v2026.11.0` 发布说明](https://github.com/bitwarden/clients/releases/tag/desktop-v2026.11.0)
记录 OSS 从无前缀改为 `oss-`，商业版从 `commercial-` 改为 `bit-`。
旧规则回退到 2026.10.4（[#2124](https://github.com/jizhi0v0/duo-updater/issues/2124)）。

在 Apple Silicon macOS VM 挂载旧版和新版各两个官方 DMG。四个包的 bundle ID
均为 `com.bitwarden.desktop`、Team 均为 `LTZ2PFU5D6`。2026.10.4 和 2026.11.0 的 build
分别为 `73705`、`74806`，同一版本的两个版别一致。四个包都有 arm64 与 x86_64。
两个 OSS 包含 `;// ./src/preload.ts`，两个商业版包含
`;// ../../bitwarden_license/bit-desktop/src/preload.ts`。上游
[OSS Webpack 配置](https://github.com/bitwarden/clients/blob/desktop-v2026.11.0/apps/desktop/webpack.config.js)
与[商业版 Webpack 配置](https://github.com/bitwarden/clients/blob/desktop-v2026.11.0/bitwarden_license/bit-desktop/webpack.config.js)
各有独立的 preload 入口。实测新版 OSS DMG 的 SHA-256 与 GitHub 发行资产声明一致。
