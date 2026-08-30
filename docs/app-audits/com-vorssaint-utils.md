# Vorssaint

> 审计 2026-08-30 · stable / beta 真实 DMG 验证 · GitHub 双渠道检测已接入

## 基本信息

- Bundle ID: `com.vorssaint.utils`（stable / beta 共享）
- 官网仓库: <https://github.com/vorssaintapp/vorssaint-utils>
- 已装 stable: `CFBundleShortVersionString = 3.3.2`，`CFBundleVersion = 78`
- 已挂载 beta: `CFBundleShortVersionString = 3.3.3-beta.3`，`CFBundleVersion = 82`
- 两个真实 app 的 Team ID 均为 `3D485NHW29`，arm64，公证票均已 stapled
- 自更新线索: `Info.plist` 没有 `SUFeedURL`、`KSChannelID` 或可用的 Sparkle 配置

Homebrew cask 的 homepage 仍写旧 slug `vorssaint/vorssaint-utils`，GitHub 已把官方仓库
规范化为 `vorssaintapp/vorssaint-utils`。规则直接 pin 规范 slug，避免带 Authorization
的 GitHub 请求在 301 跳转时退化到匿名限流。

## 覆盖矩阵

> ✓ = 已接入 · ○ = 可接入但本次未启用 · — = 不适用

| Channel | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|---|---|---|---|---|---|
| stable | — | `auto_updates true`，通用源跳过 | — | ✓ 检测 | — |
| beta | — | — | — | ✓ 检测 | — |

当前生效源: **GitHubReleasesSource**（stable + beta，均 detection-only）。

这里的 Homebrew 语义是接入理由，而不是重复覆盖：`auto_updates true` 表示 Homebrew
把更新交给 app 自己，`HomebrewCaskSource` 因此明确返回 nil；若 cask 是
`auto_updates false` 或缺省，通用 Homebrew 源已经支持，就不应再写 app 专用规则。

## Channel 详情

| Channel | Bundle ID | 检测信号 | GitHub tag 门控 | 状态 |
|---|---|---|---|---|
| stable | `com.vorssaint.utils` | 纯数字版本 `3.3.2` | `^vX.Y.Z$` | ✓ |
| beta | `com.vorssaint.utils` | 版本后缀 `-beta.N` | `^vX.Y.Z-beta.N$` | ✓ |

beta 的真实 app 没有独立 bundle id、独立 app 名或 Keystone 字段，
`3.3.3-beta.3` 是唯一可见渠道信号。`ReleaseChannel.detect()` 新增了严格的整串规则：
只把以 `-beta.<数字>` 结束的 dotted semver 判为 beta；
`0.3.377-beta.1429+sha` 这类带 `+sha` 的稳定构建元数据仍判 stable。

## 更新检测

两条 `GitHubReleaseRule` 都读取规范仓库 `vorssaintapp/vorssaint-utils`：

- stable: `/releases/latest`，只接受 `v3.3.2` 这类无后缀 tag。
- beta: releases list，`usePrereleases: true`，只接受 `v3.3.3-beta.3` 这类 tag。
- 两条都不设置 `installAssetPattern`，因此只展示版本和 GitHub release 页面。

真实线上响应（2026-08-30）为 stable `v3.3.2`、beta `v3.3.3-beta.3`；
`duo verify --only vorssaint --github` 对两条规则均返回通过：

```text
GitHub rule   ✓ 2  ⚠ 0  ✗ 0  ~ 0  - 0
```

## 本机验证

stable 经 Homebrew cask 安装到 `/Applications/Vorssaint.app`。接入前完整生产链为
`winning source = none / status = unknown`；接入后同一真实安装结果为：

```text
detected channel → stable
winning source   → GitHub
latest           → 3.3.2
status           → up to date
```

beta `Vorssaint-3.3.3-beta.3.dmg` 从官方 GitHub release 下载并只读挂载；
`channel-verify ... --expect beta` 直接读取真实 bundle 后输出：

```text
short version    3.3.3-beta.3
build version    82
detected channel → beta
✓ detection matches --expect beta
```

该工具的单文件模式只执行 VendorProbe，因此随后显示 `VendorProbe no version` 是预期；
GitHub 两轨的端点和 tag 提取由上面的 `duo verify` 独立验证。

## Changelog

使用 GitHub release body，天然跟随 stable / beta 各自命中的 release；没有额外的
`ChangelogRecipe`。

## 一键安装

**未启用。** stable 与 beta DMG 中对应 `Vorssaint.app` 的 Team ID 一致，但
`codesign --verify --deep --strict` 对两个真实 app 均报告：

```text
invalid signature (code or signature have been modified)
```

`codesign -dvvv` 同时能看到 hardened runtime 与 stapled notarization ticket，
`spctl` 在当前 macOS 27 beta 上返回 Code Signing subsystem internal error。无论这是
上游签名问题还是 beta 系统回归，都不足以通过 DuoUpdater 的替换闸，所以保持
detection-only；不会把未经验证的 DMG 暴露为一键更新。

## 结论

Vorssaint 是 `auto_updates true` 下确实会漏掉的活跃 app。stable / beta 现在由同一
官方 GitHub 仓库分轨检测，真实 bundle 的共享身份和 beta 后缀均已验证；Homebrew
通用覆盖没有被重复实现，一键安装也因签名验证失败而保持关闭。
