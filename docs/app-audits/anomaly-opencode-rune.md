# OpenCode (Rune)

## 基本信息

- 官方桌面客户端仓库为 [anomalyco/opencode-rune](https://github.com/anomalyco/opencode-rune)。公开发行包为 `anomaly.opencode-rune`，由 Anomaly Innovations, Inc. 的 Developer ID `5NZ4Q7NXJ4` 签名。
- 官方只发布 dev 桌面轨。Apple Silicon 和 Intel 各有独立安装包，DuoUpdater 选择受支持的 arm64 版本。已检查的发行包最低要求 macOS 13。

## 覆盖矩阵

| 副本 | 检测 | 一键安装 | 结构化日志 |
|---|---|---|---|
| 官方 dev `anomaly.opencode-rune` | VendorProbe，读取 dev manifest 的完整版本 | arm64 DMG，校验 SHA-256 与签名身份 | GitHub dev 发布记录 |
| PR 副本 `anomaly.opencode-rune.pr.<N>` | 上游按 PR 发布一次性测试包，没有连续更新轨 | 由各 PR 的下载页手动替换 | 各 PR 的说明 |
| 本地开发副本 `anomaly.opencode-rune.dev` | 由上游开发脚本构建，无对应发行轨 | 通过原构建流程替换 | 源码提交记录 |

PR 安装包可与 dev 副本并存。厂商只允许公开发行 ID 使用内置更新器。参考 [试用说明](https://github.com/anomalyco/opencode-rune/blob/dev/docs/trying-opencode-rune.md) 与 [macOS 更新器](https://github.com/anomalyco/opencode-rune/blob/dev/features/updater/src/mac.rs)。

## 更新检测

[dev manifest](https://anoma.ly/release/opencode/desktop-rune/dev.json) 给出 `release.version`。它与公开包的 `CFBundleShortVersionString` 相同，例如 `0.0.0-dev-503`，而 `CFBundleVersion` 是单独的 `503`。已有版本尾缀规则识别 `.dev`，并按数字递增比较 dev 序号。DuoUpdater 等待 `rollout_percent` 达到 100%，厂商自己的更新器可以在此之前按设备分桶提前更新。发布工作流先更新这个 manifest，再把同一发行版镜像到 GitHub。参考 [发布工作流](https://github.com/anomalyco/opencode-rune/blob/dev/.github/workflows/release.yml) 与 [客户端分桶逻辑](https://github.com/anomalyco/opencode-rune/blob/dev/features/updater/src/protocol.rs)。

## 一键安装

按键读取清单里 `release.targets.macos-arm64-dmg` 对象。只接受路径内版本与 `release.version` 一致、路径内 SHA-256 与目标摘要一致的 DMG。归档摘要、旧副本的 bundle ID 和签名团队通过验证后，还要核对签名封存的 `CFBundleShortVersionString` 与清单发布版本完全一致。同份清单中的 `macos-arm64` 条目是内置更新器使用的 ZIP，具有自己的路径与摘要。

## Changelog

[GitHub Releases](https://github.com/anomalyco/opencode-rune/releases) 的 dev 镜像以普通 release 发布。结构化解析只接受 `vX.Y.Z-dev-N`，按版本显示各次发布的项目。采样发布说明中的单个 “What's Changed” 通用标题由现有 Markdown 解析器省略。

## 夜扫覆盖

VendorProbe 的枚举注册项为 `vendor:anomaly.opencode-rune:dev`，可用 `duo verify --only anomaly.opencode-rune` 检查版本和发布说明，用 `duo verify-install --only anomaly.opencode-rune` 检查可安装归档。公开 dev 轨含 DMG 安装规则，PR 和本地开发副本没有可供夜扫的发行轨。

## 历史与实测

- 2026-11-28，挂载 GitHub 当前、相邻和最早公开发布的 arm64 DMG，检查 `0.0.0-dev-503`、`0.0.0-dev-502` 和 `0.0.0-dev-488` 均使用 `anomaly.opencode-rune`、Team ID `5NZ4Q7NXJ4` 和与版本尾缀相同的数字构建号。502 和 503 的深度签名校验、Gatekeeper 与公证票据校验均通过。
- 2026-11-28，dev manifest 回答 `0.0.0-dev-503`。503 的 GitHub 镜像 DMG 的 SHA-256 与同一版本的厂商 manifest 记录一致。
- 2026-11-28，Developer ID 签名的 Release CLI 在 Apple Silicon macOS 27.2 VM 上通过厂商源将 dev-502 原地升到 dev-503，保留 bundle ID 和签名团队。更新后通过深度签名和 Gatekeeper 校验，复查显示为最新版。`duo verify` 的版本与结构化日志均通过，`duo verify-install` 下载并校验了厂商的 arm64 DMG。
