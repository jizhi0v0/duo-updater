# CotEditor

审计日期：2026-09-06。

## 基本信息

- Bundle ID：`com.coteditor.CotEditor`；Team ID：`HT3Z3A72WZ`（Mineko IMANISHI）。
- 官方真包观测：stable `7.0.9` / build `843`；beta `7.1.0-beta.6` / build `845`。
- 两轨 universal DMG 均通过 Gatekeeper：`Notarized Developer ID`。
- [官方发布](https://github.com/coteditor/CotEditor/releases)：两轨最新版本均发布于 2026-09-05。
- 直装版内置 Sparkle，带 `SUPublicEDKey`，但没有 `SUFeedURL`。地址 `https://coteditor.com/appcast.xml` 可在两份签名二进制及官方 `UpdaterManager.swift` 中确认。

## 覆盖矩阵

| Channel / 分发 | Sparkle | Homebrew | Mac App Store | 一键更新 | 结构化日志 |
|---|---|---|---|---|---|
| stable 直装 | ✓ | 元数据，auto_updates | — | ✓ | ✓ |
| beta 直装 | 当前 feed 可推断，有限覆盖 | — | — | 包及检测已验证 | ✓，含可晋升 stable |
| stable 商店版 | — | — | 通用 MAS 源 | 现有 MAS 路径，本次未验证 | stable recipe |

## 更新检测

`SparkleFeedCatalog` 填补缺失地址，生产源链由 Sparkle 应答。保留真实 EdDSA 密钥、最低系统版本、渠道标签和安装门控；无需新增易漂移的版本爬取。7.0.9 要求 macOS 15，7.1 beta 要求 macOS 26；feed 保留旧系统版本。回归测试验证 macOS 14 只能选 5.2.3，stable 不能选 beta。

## Beta 范围限制

官方更新器允许 beta 的条件是 `Bundle.main.version.isPrerelease || checksUpdatesForBeta`，标签为 `prerelease`。本次沿用现有 Sparkle 按 feed 中已知 build 推断渠道：当前 beta build 845 可以识别，但不读取 `checksUpdatesForBeta`；旧 beta 一旦从 feed 移除，会保守退回默认渠道。因此不宣称完整 beta 偏好支持。后续需将偏好与实际 bundle 版本一起传入渠道解析，不能用单独的偏好覆盖 beta 包的默认行为。

## Changelog

官方 GitHub releases JSON 通过现有结构化解码器输出版本、日期与 Markdown 条目。stable 排除预发布；beta 包含 beta 及 stable，和 Sparkle 允许晋升正式版一致。draft 在两轨均排除。无须嵌入官方 HTML release-notes 页面。

## 一键更新验证

生产 `AppScanner → UpdateChecker → InstallCoordinator` 将官方 `7.0.8` 副本升级到 `7.0.9`，下载 25,609,728 bytes；Sparkle EdDSA、代码签名与替换阶段通过，重新扫描检查为 `upToDate`。两个最新真包运行 `channel-verify` 均由 Sparkle 应答，版本与包一致，无幻影更新。beta 未执行旧版到新版替换。

## 如何复验

1. 从官方 releases 获取 DMG，读取 `Info.plist`、运行 `codesign -dv` 与 `spctl --assess --type execute -vv <app>`。
2. `swift run --package-path application-test channel-verify <dmg> --expect <stable或beta>`。
3. `swift test --package-path DuoUpdaterCore --filter ActiveAppsIntegrationTests`。
4. `duo verify --only com.coteditor.CotEditor --samples`：2 changelog 全通过；Sparkle 由真包 harness 验证。
