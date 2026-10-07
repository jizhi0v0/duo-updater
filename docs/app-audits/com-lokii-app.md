# Lokii

## 基本信息
- App: Lokii — Rust + AppKit 的文件搜索（类 Everything）
- Bundle ID: `com.lokii.app`
- 仓库: `huangy7/lokii`
- 签名: **ad-hoc，无 Team ID**（`spctl` rejected）；封印完整（`codesign --verify --deep --strict` 0），
  签名标识 = bundle id
- 观测版本: 0.1.1（2026-10-06）；观测日期: 2026-10-07
- 自更新机制: 自带 `AppUpdater`，读 `api.github.com/repos/huangy7/lokii/releases/latest`（二进制字符串）；无 Sparkle
- 分发: 只有 GitHub Releases
- 开源: 是

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | ✓      | —           |

当前生效源: **GitHub**（channel-verify 实测）。

## 更新检测
- 源: `huangy7/lokii` GitHub Releases，`/releases/latest`
- 版本方案: tag `vX.Y.Z` == `CFBundleShortVersionString`；`CFBundleVersion` 恒为 `1`（0.1.0、0.1.1）
- 资产: `Lokii-arm64.dmg` / `Lokii-x86_64.dmg`，名字里没有版本，arch 交给源的架构偏好

## 增量更新
- 无。

## 按 OS 分轨
- `LSMinimumSystemVersion` = `13.0`；arm64 / x86_64 分包。

## Changelog
- ✗ **无从结构化**: 两个 release 的正文都只有一句「See the assets to download this version and install.」，
  仓库里也没有 CHANGELOG 文件。channel-verify 显示 `source structured: 1 items`，那一条就是这句话本身
- Recipe 状态: 无可写

## 一键安装
- 状态: **digest-only**（`installTrust: .publishedDigestOnly`）——用户在设置 → 通用里打开
  「无开发者签名的 app 按文件哈希一键更新」才可用
- Pattern: `^Lokii-(?:arm64|x86_64)\.dmg$`, kind `.dmg`
- 条件核对（2026-10-07，0.1.0 / 0.1.1 两个 arch 共 4 个包）: 封印 `--deep --strict` 0；签名标识 `com.lokii.app`；
  short == tag；GitHub 为每个资产发布 sha256 `digest`，与下载实测逐一相同
- 端到端（2026-10-07）: 0.1.0 装进 `/Applications` → `duo check` `0.1.0 → 0.1.1 [GitHub]` →
  `duo install --yes --json` 在设置关闭时 `skipped`，原因「no developer signature — turn on one-click updates
  for such apps in DuoUpdater's Settings → General…」（拒绝路径 ✓）→ 经用户同意临时打开
  `AllowDigestOnlyInstalls` 再 `duo install`：`installed`（4992333 字节 = arm64 dmg）→ 0.1.1、inode 变、
  签名标识 `com.lokii.app`、`--deep --strict` 0、与厂商包 `diff -r` 一致 → 设置改回关闭
- 机器现状: Lokii 0.1.1 仍装在 `/Applications`，未运行

## 已知问题
- ad-hoc 签名每次构建 cdhash 都变；文件搜索要的完全磁盘访问授权会不会因此在更新后失效，未验证。

## 如何复验
```
swift run --package-path application-test channel-verify Lokii-arm64.dmg   # 0.1.1 → up to date；0.1.0 → UPDATE → 0.1.1
gh api repos/huangy7/lokii/releases --jq '.[] | .assets[] | "\(.name) \(.digest)"'   # 对照 shasum -a 256
```
