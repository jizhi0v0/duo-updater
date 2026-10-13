# RustGIS

## 基本信息
- App: RustGIS — 纯 Rust（egui）写的桌面 GIS（Mac / Windows / Linux，另有 web 版），Apache-2.0 开源
- Bundle ID: `org.rustgis.RustGIS`
- 仓库: `opengeos/RustGIS`（默认分支 `main`）；下载页 `https://downloads.rustgis.app/`
- Team ID: `Z6ABKZWLA7`（Developer ID + 公证，dmg 已 staple）
- 观测版本: 0.1.0（`CFBundleVersion` 同为 `0.1.0`）；观测日期: 2026-10-13
- 自更新机制: 无。二进制里唯一的 GitHub API 地址是 `opengeos/geolibre-rust/releases/latest`，那是给分析工具
  下载 geolibre 插件二进制（装进 `~/Library/Application Support/RustGIS`），不更新 app 本身
- 分发: GitHub Releases（`-macos-aarch64.dmg` / `-macos-x86_64.dmg`）。`downloads.rustgis.app` 是同一组
  release 资产的镜像（`manifest.json` 每个 artifact 同时给 `download_url` 与 `github_url`，`digest` 与 GitHub 相同）。
  `package-managers.yml` 推第三方 tap `opengeos/homebrew-rustgis`，不是 homebrew/cask；没有 MAS

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |
| **rc**     | —       | —        | —   | —      | —           |

当前生效源: **GitHub**（channel-verify 实测）。`feed-discover` 给出 `no Sparkle and no electron-builder update config`。

## Channel 详情

只有一条轨，settled from source: `.github/workflows/release.yml` on `main`。

- 版本 = tag 去 `v`，写进 `packaging/macos/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`
  （`@VERSION@` 占位）；workflow 拒绝与 Cargo `[workspace.package].version` 不一致的 tag。
- workflow 注释写明预发布用 `v0.2.0-rc.1` 这种 tag。截至 2026-10-13 只有 `v0.1.0` 一个 release，还没有任何 rc。
- app 没有更新器，也就没有「接收 beta」开关。rc 不是用户在 app 内选的轨：装 rc 的人是手动下的。规则读
  `/releases/latest`（GitHub 计算时排除 pre-release），`versionPattern` 用 `$` 锚定，rc tag 进不了 stable。
  装着 `0.2.0-rc.1` 的副本，在 `0.2.0` 正式版出来之前看到的是 `0.1.0`，比较结果为已是最新，不会误推。

## 更新检测
- 源: `opengeos/RustGIS` GitHub Releases，`/releases/latest`
- 版本: `^v([0-9]+(?:\.[0-9]+)+)$`，与 `CFBundleShortVersionString` 一致

## 按架构 / 按 OS 分轨
- 两个 dmg: `RustGIS-<v>-macos-aarch64.dmg`（`lipo` = arm64）与 `RustGIS-<v>-macos-x86_64.dmg`（`lipo` = x86_64），
  install pattern 两个都匹配，由资产选择器按文件名里的架构标记挑
- `LSMinimumSystemVersion` = `11.0`（两个架构相同）；release 不声明 OS 上下限

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | — |
| 证据 | 没有更新器（见上） | v0.1.0 资产只有完整包与 `SHA256SUMS` | — |

## Changelog
- 来源: GitHub Release body，经 `GitHubMarkdownParser`
- 结构化（2026-10-13，channel-verify `changelog pane`，0.1.0）: `source structured: 1 entries; newest 0.1.0: 72 items,
  headings ["Highlights", "What's Changed"]; first items ["**Your data, any map**: GeoJSON, CSV, Sh",
  "**Cartography and layouts**: unique valu", "**Analysis**: SQL selection, overlay and"]`
- 跟随 channel: —（单轨）
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**（按 Team 闸；端到端未跑，见下）
- 格式: dmg（公证、staple）；bundle 内没有嵌套 app、LoginItems 或 helper
- Pattern: `^RustGIS-[0-9][0-9A-Za-z.-]*-macos-(?:aarch64|x86_64)\.dmg$`, kind `.dmg`；不匹配 Linux/Windows 包与
  `rustgis-cli-*-macos-*.tar.gz`
- 校验: GitHub 资产 `digest`（sha256）。下载后 `shasum -a 256`: aarch64 = `7f705788…44b9bc68`、
  x86_64 = `8799f32a…5491097f`，都与各自 `digest`、`SHA256SUMS` 相同
- **读的是**: 人人可手动下载的 GA（GitHub `/releases/latest`，下载页链接的就是这两个 dmg）
- 端到端: **未跑**。截至 2026-10-13 只有 v0.1.0 一个 release，没有「上一版」可装
- 阻塞: 无

## 已知问题
- 无。没有自更新器，运行中一轮不存在碰撞问题。

## 建议下一步
1. 下一个 release 出来后：装 0.1.0，跑 `duo install --yes`（不运行；运行中 + `duo restart`），补进本文件。
2. 第一个 rc 出来后复查：`/releases/latest` 仍指向正式版、rc 安装不被推回旧正式版。

## 如何复验
```
swift run --package-path application-test feed-discover <RustGIS-0.1.0-macos-aarch64.dmg>   # → no Sparkle and no electron-builder update config
swift run --package-path application-test channel-verify <RustGIS-0.1.0-macos-aarch64.dmg> --expect stable
#   → detected stable，winning source GitHub，latest 0.1.0，up to date
codesign -dv <RustGIS.app>        # → TeamIdentifier=Z6ABKZWLA7
spctl -a -vv <RustGIS.app>        # → accepted, source=Notarized Developer ID
```
