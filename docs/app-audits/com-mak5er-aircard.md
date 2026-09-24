# AirCard

## 基本信息
- Bundle ID: `com.mak5er.aircard`
- Team ID: 无（ad-hoc 签名，`Signature=adhoc`、`TeamIdentifier=not set`）
- 观测版本: 1.2.4（`CFBundleVersion` 7），2026-09-24
- 自更新机制: 无（无 `SUFeedURL`、无 Sparkle/electron-updater；SwiftUI 壳 + Python 后端）
- 源码: [Mak5er/AirCard](https://github.com/Mak5er/AirCard)（MIT）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | —        | —   | ✓      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub Releases**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.mak5er.aircard` | — | — | — | ✓ |

2026-09-24 时 releases 共 7 个（v1.0 … v1.2.4），全部 `prerelease=false`，没有其他轨道。

## 更新检测
- 源: `GitHubReleaseRule(owner: "Mak5er", repo: "AirCard")`，默认 `versionPattern`。
- 版本方案: settled from source: `build.sh` on `main` —— Info.plist 由脚本内联写入，
  `CFBundleShortVersionString` 与 tag 同构（tag `v1.2.4` ↔ `1.2.4`）。
  早期 tag 有两段式（`v1.2`、`v1.1`、`v1.0`）。
- Homebrew: `brew search --cask aircard` 无结果（只返回 `aircall`）；MAS 无（`mas search AirCard` 与 iTunes Search API `entity=macSoftware` 均无 `com.mak5er.aircard`）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不适用 |
| 证据 | bundle 里没有 Sparkle / 任何更新框架 | 每个 release 只有一个 `AirCard.dmg` 资产 | — |

## Changelog
- 来源: GitHub release 正文（`GitHubReleasesSource` 自带）
- Recipe 状态: 不需要

## 一键安装
- 状态: 仅检测
- 格式: dmg（v1.2.4 资产 2,689,185 字节）
- **读的是**: 人人可手动下载的 GA（repo 最新非 prerelease 的 release）
- 阻塞: `build.sh` 以 `codesign --force --deep --sign -` 做 ad-hoc 签名，产物没有
  Team ID，`SignatureVerifier` 的 Team 闸必拒；因此不设 `installAssetPattern`，
  与 `Recipes/org-alacritty.swift` 的 Detection-only 说明同理。
  核验方式：读 `build.sh` + 对 1.2.4 的已装 bundle 跑 `codesign -dvvv`；未单独下载 dmg 复验。

## 建议下一步
1. 若上游改为 Developer ID 签名 + 公证，再补 `installAssetPattern`（资产名 `AirCard.dmg`）与对应 `installerKind`，并下真包验 Team ID。
