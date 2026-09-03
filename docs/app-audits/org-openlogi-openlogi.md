# OpenLogi

## 基本信息

- Bundle ID: `org.openlogi.openlogi`
- Team ID: `8U3ZJ258K9`
- 已安装验证版本: `0.8.1`（build `20260826.132846`）
- 自更新机制: 自研 `gpui-updater`，release build 内写死官方 stable manifest
  `https://updates.openlogi.org/channels/stable/latest.json`
- 分发: 官网 / GitHub Releases / Homebrew cask `openlogi`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | — (`auto_updates`) | — | ✓ | ○（官方 manifest，未采用） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**。

`auto_updates: true` 的含义是 Homebrew 把更新责任交回应用自身；即使这份 app
由 brew 安装，`HomebrewCaskSource` 也会按设计返回 nil。接入前对真实 brew 安装
运行 `channel-verify --check`，结果为 `winning source <none>` / `unknown`。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|-----------|----------|----------|------|
| stable | `org.openlogi.openlogi` | 单一渠道 | 默认 `.stable` | GitHub tag 必须完整匹配 `vX.Y.Z` | ✓ |

官方 updater 源码与 release workflow 都把 channel 固定为 `stable`；没有发现
beta/nightly 构建或本机需要辨识的 channel 偏好。

## 更新检测

- 源: `GitHubReleasesSource`
- Repo: `AprilNEA/OpenLogi`
- Tag pattern: `^v([0-9]+(?:\.[0-9]+)+)$`
- 版本方案: GitHub `v0.8.2` → `0.8.2`，与真实 bundle 的
  `CFBundleShortVersionString` `0.8.1` 同构；不比较时间型 build
  `20260826.132846`
- 交叉验证: 真包二进制内的 manifest URL 在 2026-08-30 返回 `version: 0.8.2`、
  `app_id: org.openlogi.openlogi`、`channel: stable`；同一版本的 GitHub Release
  同时发布 arm64/x86_64 DMG
- 防跨渠道: pattern 锚定两端，`v0.8.3-rc.1` 不会被截成 stable `0.8.3`

## Changelog

- 来源: GitHub Release body（由 `GitHubReleasesSource` 原生带回）
- 跟随 channel: 是，仅 stable release
- Recipe 状态: 不需要单独 `ChangelogRecipe`

## 一键安装

- 状态: **支持**（`installAssetPattern` 钉 arm64 DMG，`kind: .dmg`）
- 官方格式: 分架构 DMG。每个 release 发 12 个产物（macOS arm64/x86_64、Windows
  msi/zip、Linux deb/rpm/pkg.tar.zst），**每个都配一个 `.minisig`**，外加 `SHA256SUMS`。
  所以 pattern 必须以 `\.dmg$` 收尾——不锚定的话
  `OpenLogi-v0.8.3-macos-arm64.dmg.minisig` 会被截成一个厂商从未发布过的 URL。
- 端到端验证（2026-09-03）: `~/Applications` 装 0.8.2 → `duo check` 给出
  `0.8.2 → 0.8.3 [GitHub, in-place]` → `duo install` 绿，落盘 short `0.8.3`、
  Team `8U3ZJ258K9`。
- ⚠️ **包没有 stapled notarization ticket**（0.8.2 / 0.8.3 都没有，是这家厂商的发包
  习惯，不是回归）。`spctl` 仍判 `accepted / Notarized Developer ID`（联网查票），
  而 `SignatureVerifier` 只查签名有效性与 Team 一致、**不查装订**，所以替换闸不受
  影响；代价是首次启动时 Gatekeeper 要联网。
- ⚠️ **`CFBundleVersion` 是时间戳**（`20260830.162827`），与 tag 不同命名空间。
  当前无害，因为 `GitHubReleasesSource` 把远端 build 置为 `nil`、比较只走 marketing。
  **不要"顺手改进"成把 tag 塞进 build。**

## 本机验证

2026-08-30 使用 Homebrew 安装官方 cask，真实读取：

| 项目 | 结果 |
|------|------|
| App | `/Applications/OpenLogi.app` |
| Bundle / version | `org.openlogi.openlogi` / `0.8.1` / build `20260826.132846` |
| Team / notarization | `8U3ZJ258K9` / stapled ticket |
| 接入前全链 | `unknown` |
| 接入后全链 | `GitHub` / `UPDATE 0.8.1 → 0.8.2` ✓ |

## 已知问题

- `spctl -a -vv` 在本机 macOS 27 beta 对该 bundle 返回 Code Signing subsystem
  internal error；`codesign -dvvv` 能读取 Developer ID Team 与 stapled ticket。
  这不影响 detection-only 路径。

## 建议下一步

1. 保持当前 detection-only GitHub rule，合并后由 verify 监控 repo slug 与 latest tag。
2. 若批准一键，再单独核对 0.8.2 DMG 的 Team、签名、公证、架构选择和 bundle-only
   安装边界，然后在本 app PR 内或后续 OpenLogi 专属 PR 打开资产规则。
