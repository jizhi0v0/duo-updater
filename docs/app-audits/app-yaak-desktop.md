# Yaak

审计日期：2026-09-06。

## 基本信息

- Bundle ID：`app.yaak.desktop`；Team ID：`7PU3P6ELJ8`（Gregory Schier）。
- 官方真包观测：stable `2026.7.1`，beta `2026.8.0-beta.1`；两个 plist 版本字段均保留完整版本，包括 beta 后缀。
- 两轨 Apple Silicon DMG 均通过 Gatekeeper：`Notarized Developer ID`，同一 Team ID。
- 官方发布：[mountain-loop/yaak](https://github.com/mountain-loop/yaak/releases)，stable 发布于 2026-09-01。
- Tauri 自更新，无 Sparkle；Homebrew cask 标记 `auto_updates: true`，不能把 cask 元数据当作有效检测源。

## 覆盖矩阵

| Channel | Sparkle | Homebrew | GitHub | VendorProbe | 一键安装 | 结构化日志 |
|---|---|---|---|---|---|---|
| stable | — | 元数据 | ✓ | — | ✓ arm64 DMG | ✓ |
| beta | — | — | ✓ | — | ✓ arm64 DMG | ✓ |

本次验证的是官网/GitHub 直装分发；未扩展商店或其他渠道。

## 更新检测与渠道

生产源链由 GitHub 应答。stable 使用 `/releases/latest`，仅接受完整数字 tag；beta 使用 releases 列表，仅接受完整 `v…-beta.N` tag。相同 bundle ID，以真包保留的版本后缀识别 beta。资源规则只接受对应渠道的 `_aarch64.dmg`，排除 x64、Windows/Linux、更新器 tarball 和签名附件。

beta 安装的渠道证明锚定下载 URL 的 beta tag 路径；stable tag 不能通过该证明。最近 100 条发布中 72 条匹配 beta，最大相邻匹配间距 5，查询最低深度为 6；保留默认 20 条窗口。beta 跟随 beta train，本次未实现 beta 自动转入正式版的候选策略。

## Changelog

官方 releases JSON 经现有 `gitHubReleases` 解码器和 Markdown parser 输出版本、日期及逐项说明。两条 recipe 显式区分 stable/beta，排除 draft；stable 不显示预发布说明。真实响应 fixture 经 `ChangelogService.parse` 验证。

## 一键更新验证

使用生产 `AppScanner → UpdateChecker → InstallCoordinator → AppScanner → UpdateChecker`，官方 `2026.7.0` 副本成功升级到 `2026.7.1`。下载 66,472,915 bytes，代码签名门控、替换完成，重新检查为 `upToDate`。stable/beta 最新真包分别运行 `channel-verify --expect stable/beta`，GitHub 版本与本地版本一致，无幻影更新。beta 验证到包和检测链，未执行 beta 旧版到新版替换。

## 如何复验

1. 从官方 releases 下载对应 arm64 DMG，检查 `Info.plist` 两个版本字段与 bundle ID。
2. `spctl --assess --type execute -vv <app>`：应为上述 Team ID 的公证构建。
3. `swift run --package-path application-test channel-verify <dmg> --expect <stable或beta>`。
4. `swift test --package-path DuoUpdaterCore --filter ActiveAppsIntegrationTests`。
5. `duo verify --only app.yaak.desktop --samples`：2 GitHub + 2 changelog 全通过。
