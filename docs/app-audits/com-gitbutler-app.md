# GitButler

| 副本 | 检测 | 一键升级 | 更新日志 |
|---|---|---|---|
| 官网正式版 `com.gitbutler.app` | 官方 Tauri 正式轨 JSON | Apple Silicon 的版本化 `GitButler.app.tar.gz`，经已有 vendor 安装链核对签名、Team、bundle ID 和架构 | 官方下载页的逐版日志，保留小标题和正文 |
| 官网 Nightly `com.gitbutler.app.nightly` | 厂商有独立 Nightly 源，DuoUpdater 暂未登记 | 待 Nightly 专项验收 | 暂未接入 |

正式版和 Nightly 的版本号分别递增。分轨由包内 bundle ID 和厂商源确定。官网 macOS 提供 Apple Silicon 与 Intel 架构各自的 DMG。正式轨 recipe 读取原厂 Apple Silicon 更新归档，DuoUpdater 的支持平台为 Apple Silicon。Homebrew 的 `gitbutler` cask 也使用同一官方归档。 [官方安装页](https://gitbutler.com/downloads) · [厂商轨道说明](https://docs.gitbutler.com/releases)

## 夜扫覆盖

- `vendor:com.gitbutler.app:stable` 检查正式 Apple Silicon feed。它读取 `/release/darwin-aarch64/0.0.0`，固定旧基准保证条件接口会提供最新版本，而已达最新版的厂商客户端通常收到 HTTP 204。
- `install:vendor:com.gitbutler.app:stable` 检查对应下载包和已展开的 macOS 签名身份。JSON 的版本字段要与归档路径版本一致，归档需属于正式轨、ARM64、GitButler 官方下载主机。厂商的 Tauri minisign 签名不参与既有 vendor 安装链的 Apple 代码签名验证。
- `changelog:com.gitbutler.app:-` 检查官网正式版下载页的最新条目和历史版本卡片。Nightly 使用独立 ID 和源，其日志与安装字节夜扫本批均暂缓。

2026-11-28，本批用签名 Release CLI 对正式轨运行 `duo verify --vendor --changelog` 和 `duo verify-install --full`，该应用的版本源、日志和安装包均为 `ok`。

## 历史与实测

2026-11-28，ARM64 正式轨请求版本 `0.23.4` 返回 `0.23.5` 和 `0.23.5-3373/macos/aarch64/GitButler.app.tar.gz`，请求 `0.23.5` 返回 HTTP 204。核对 0.23.4（下载路径 build 3353）及 0.23.5（3373）的真包，两者均为 `com.gitbutler.app`、Team `AT87WZ3SVG`，通过严格签名和 Gatekeeper 公证检查。包内 `CFBundleVersion` 分别等于各自营销版本。 [正式接口样本](https://app.gitbutler.com/releases/release/darwin-aarch64/0.23.4)

同日官网 Nightly 源提供 `0.5.2295`。ARM64 归档内是 `GitButler Nightly.app`，ID 为 `com.gitbutler.app.nightly`，同 Team 且严格签名和公证通过。正式轨 recipe 的精确 ID 不匹配该副本。 [Nightly 接口样本](https://app.gitbutler.com/releases/nightly/darwin-aarch64/0.0.0)

2026-11-28，在 Apple Silicon、macOS 27.3 上用签名 Release CLI 验证 0.23.4 → 0.23.5。官网下载 49,036,839 字节，停用副本实际原地替换成功。升级后复查为最新，bundle ID、原厂 Team、严格签名和公证均通过。生产日志路径读出 10 个版本，0.23.5 的 18 条说明及 Changes、Fixes、CLI、Native app 四个标题。已用 GitButler Nightly 真包复查，识别为 Nightly，正式轨未给出更新和日志。
