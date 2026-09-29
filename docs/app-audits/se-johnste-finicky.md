# Finicky

## 基本信息
- Bundle ID: `se.johnste.finicky`
- Team ID: `C3XWNKDP3M`（Developer ID Application: John Sterling）
- 观测版本: `4.2.2`（`CFBundleVersion` 同为 `4.2.2`）
- 自更新机制: 自研检查，不自动安装（Go；`GET finicky.johnste.se/update-check?version=<CFBundleVersion>`，
  间隔 24h，结果发给 app 窗口显示「New Version Available」+ release/下载链接；不下载、不安装）
- 分发: GitHub Releases（`johnste/finicky`）/ Homebrew cask `finicky`（非 `auto_updates`，
  `url` 指向同一个 GitHub 资产）
- 开源: 是。以下渠道、版本方案、端点均读自仓库源码（`main` 分支）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | ✓        | —   | ✓      | —           |
| **alpha/beta** | —   | —        | —   | ○      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: 直接下载的副本为 **GitHub**；
Homebrew 装的副本由 `HomebrewCaskSource` 应答（它只认本地 Caskroom 里有的 cask）。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `se.johnste.finicky` | 共享 | — | tag 锚 `^vX.Y.Z$` + 非 prerelease | ✓ |
| alpha/beta | `se.johnste.finicky` | 共享 | 版本号带 `-alpha` / `-beta` 后缀 | GitHub `prerelease` 位 | ○ |

预发布轨: tag 形如 `v4.4.0-alpha`、`v4.2.1-beta`、`v4.0.0-beta.3`，全部标 `prerelease`，
资产名同为 `Finicky.dmg`。`main` 分支 `apps/finicky/assets/Info.plist` 里
`CFBundleShortVersionString` 是 `4.4.0-alpha`，即预发布包的版本号自带后缀（读源码；
未下载预发布包核对）。本次只接 stable 轨，预发布轨未接入。

## 更新检测
- 源: `johnste/finicky` GitHub Releases，`/releases/latest`
- 版本方案: tag `v<version>`；`CFBundleShortVersionString` 与 `CFBundleVersion` 都是
  `4.2.2`，与 tag `v4.2.2` 去 `v` 后相同。
- 厂商端点对照（2026-09-29）: app 内检查的 `apiHost` 是构建时 ldflags 注入的，源码里为空；
  从 v4.2.2 二进制的字符串里读到 `finicky.johnste.se`。
  `GET https://finicky.johnste.se/update-check?version=4.2.1` →
  `latestVersion:"v4.2.2"`，`downloadUrl` 为 GitHub `v4.2.2/Finicky.dmg`，与 `/releases/latest`
  的 tag 相同。请求只有版本号和 `User-Agent: finicky/<version>`，没有设备标识。
  `hasUpdate` 对 `4.2.2` 也返回 `true`，是否有更新由客户端用 semver 比较。
  传 `4.4.0-alpha` 时返回 `v4.4.0-alpha`，即端点按传入版本分轨。
- 注意事项: v4.0.0 之前（v2.x/v3.x）资产是 `Finicky.zip`，`v4.0.0-alpha` 资产名是小写
  `finicky.dmg`；两者都不是最新 stable，不影响。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 无 | 无 | 不能 |
| 证据 | `version.go` 只取 `downloadUrl` 给用户点（读源码） | v4.0.0 起每个 release 只有一个整包 `Finicky.dmg`（v3 是 `Finicky.zip`；2026-09-29） | — |

## 按 OS 分轨
- 包的 `LSMinimumSystemVersion` 是 `12.0`（v4.2.1、v4.2.2 相同）；update-check 响应没有
  min/max 系统版本字段。

## Changelog
- 来源: GitHub Release body，`changelogURL` 为 release 页
- 结构化（2026-09-29，`channel-verify` 的 `changelog pane` 行，从 4.2.1 检查）: ✓ 2 条纯列表，无小标题（正文本身没有标题行）；只带回最新一版的说明（1 个条目）
- 跟随 channel: 只读 stable
- Recipe 状态: 不需要

## 一键安装
- 状态: **支持**
- 格式: dmg — v4.0.0 起每个 release 一个不带版本号的 `Finicky.dmg`（v3 线是 `Finicky.zip`，pattern 不收），universal（x86_64 + arm64）
- Pattern: `^Finicky\.dmg$`, kind `.dmg`
- **读的是**: 人人可手动下载的 GA（官方 repo 公开资产；Homebrew cask 的 `url` 也是它）
- 包验（2026-09-29，v4.2.2 只读挂载）: `se.johnste.finicky` / `4.2.2`，Team `C3XWNKDP3M`，
  `spctl accepted / Notarized Developer ID`，hardened runtime，universal；dmg 根下为
  `Finicky.app` + `Applications` 链接。v4.2.1 同样 Notarized、同 Team。
- 端到端（2026-09-29）: 装 4.2.1 → `duo check` 报 `4.2.1 → 4.2.2 [GitHub, in-place]` → `duo install --yes`
  走完 backup / download / verifyingCodeSignature / install → 装好的包 `4.2.2`、Team `C3XWNKDP3M`、
  `codesign --verify --deep --strict` 通过、`spctl` Notarized

## 已知问题
- 预发布轨（alpha/beta）未接入，装着预发布版的副本按 stable 规则比较。

## 如何复验
```
# GET https://api.github.com/repos/johnste/finicky/releases/latest → v4.2.2
# 挂载 v4.2.2/Finicky.dmg → se.johnste.finicky / 4.2.2 / Team C3XWNKDP3M
swift run --package-path application-test channel-verify <挂载点>/Finicky.app --expect stable
#   → winning source GitHub, latest 4.2.2, status up to date
# 同样挂载 v4.2.1/Finicky.dmg
swift run --package-path application-test channel-verify <挂载点>/Finicky.app --expect stable
#   → winning source GitHub, latest 4.2.2, status UPDATE → 4.2.2
```

## 建议下一步
- 需要时接预发布轨（`usePrereleases: true` 的 beta rule + channel proof）。
