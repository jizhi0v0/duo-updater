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

**已启用（两轨各一条 `installAssetPattern` + `kind: .dmg`）。** 曾因一个测错对象的
结论被搁置，下面把过程留着，免得再走一遍。

> ⚠️ 2026-08-30 首次审计时记录为：`codesign --verify --deep --strict` 对两个真实 app
> 均报 `invalid signature (code or signature have been modified)`，同时 `spctl` 返回
> Code Signing subsystem internal error。**这条结论 2026-09-03 复测未能复现，见下。**

2026-09-03 在同一台机器、同一个 OS build（macOS 27.0 / 26A5425a）上重新下载
`Vorssaint-3.3.2.dmg` 与 `Vorssaint-3.3.3-beta.3.dmg` 并挂载复测：

```text
$ codesign --verify --deep --strict --verbose=2 /Volumes/…/Vorssaint.app
…/Vorssaint.app: valid on disk
…/Vorssaint.app: satisfies its Designated Requirement      # exit 0

$ spctl -a -vvv -t execute /Volumes/…/Vorssaint.app
…/Vorssaint.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Pedro Gomes (3D485NHW29)
```

两个 app 都带 hardened runtime、stapled ticket、Team ID 一致（`3D485NHW29`）。
首次那次的 spctl "internal error" 与 codesign "modified" 同时出现，更像是当时
**code signing 子系统处于瞬时故障状态**，而不是包本身的属性。

真正没签名的是 **DMG 容器**（`codesign --verify` 报 `code object is not signed at all`，
`spctl` 报 `no usable signature`）——而这不是安装路径检查的东西：`SignatureVerifier`
的闸开在解出来的 `.app` 上，不在容器上。

### 启用后的形态（2026-09-03）

两轨每个 release 各只发一个资产，beta 的名字带渠道：

```text
stable  Vorssaint-3.3.2.dmg          （tag v3.3.2）
beta    Vorssaint-3.3.3-beta.3.dmg   （tag v3.3.3-beta.3）
```

- stable 的 `^Vorssaint-[0-9.]+\.dmg$` 里 `[0-9.]+` **跨不过 `-beta.3` 的连字符**，
  所以它匹配不上 beta 资产。这不是多余的保险：`/releases/latest` 排除 prerelease 只在
  正常路径成立，**列表兜底那条路没有这个保护**。
- beta 已在 `ChannelProofRegistry.githubProofs` 登记
  `.artifact(#"/download/v[0-9.]+-beta\."#)`。锚在 tag 路径段而不是裸 `-beta`——
  owner（`vorssaintapp`）和 repo（`vorssaint-utils`）今天都不含这个词，但**能被每个
  URL 的固定部分满足的 proof 是永远不会失败的 proof**（VSCodium 那条注释的教训）。
  本次顺手补了一条从 registry 推导的检查 `anArtifactProofCannotMatchItsRulesInvariantURLPrefix`
  来钉死这件事：写这条 proof 时把它改成裸 `vorssaint` 曾经**全套测试都能过**。

### 端到端验收（2026-09-03，走 beta 这一侧，因为它才会出错）

```text
~/Applications 装 Vorssaint 3.3.3-beta.1（build 80）
duo check    → 3.3.3-beta.1 → 3.3.3-beta.3  [GitHub, in-place]     ← 不是 stable 3.3.2
duo install  → installed
落盘          short 3.3.3-beta.3  build 82  Team 3D485NHW29
```

stable 与 beta **共享 bundle id 和 app 名**，`ReleaseChannel.detect` 只能靠显示版本里的
`-beta.N` 分流——这条路径现在有真实安装验过，不只是单元测试。

## 结论

Vorssaint 是 `auto_updates true` 下确实会漏掉的活跃 app。stable / beta 现在由同一
官方 GitHub 仓库分轨检测，真实 bundle 的共享身份和 beta 后缀均已验证；Homebrew
通用覆盖没有被重复实现，一键安装也因签名验证失败而保持关闭。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-vorssaint-utils.swift — stable GitHubReleaseRule（一键为什么在 2026-09-03 打开）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（当天实测两条轨的 app 都过 `codesign --verify --deep --strict` 与 `spctl`；没签名的是 dmg 容器，而 `SignatureVerifier` 只查解出来的 `.app`），被推翻的早先说法、OS build 与两个版本号搬到这里。

One-click enabled 2026-09-03 after measuring the artifacts rather than
trusting the earlier note. That note said the stable dmg's app failed
strict code-sign verification on macOS 27 and used it as the reason to
withhold an install spec; on the same OS build (27.0 / 26A5425a) both
the stable 3.3.2 and the 3.3.3-beta.3 app pass
`codesign --verify --deep --strict` ("valid on disk", "satisfies its
Designated Requirement") and `spctl -a -t execute` ("accepted",
"Notarized Developer ID", ticket stapled, Team 3D485NHW29). What IS
unsigned is the dmg CONTAINER — and `SignatureVerifier` gates on the
extracted `.app`, never the container, so it was never the blocker it
was read as.

### Recipes/com-vorssaint-utils.swift — stable GitHubReleaseRule（beta 端到端核对与 repo 改名）

转引自 recipe 注释，未复测。整段原文；（原注释这两部分之间没有空行，是一段。）代码里留下的是结论：beta 一侧端到端验过（beta 装机拿到的是更新的 beta 而不是稳定版）；改名后钉住规范 slug，因为 URLSession 跟 301 时丢 `Authorization`。版本号、夜扫抓到它的经过（#340、#341）和 2026-09-05 对 301 的核对搬到这里。

Verified end to end 2026-09-03 from the beta side, which is the one
that can go wrong: installed `3.3.3-beta.1` in `~/Applications`, the
row offered `3.3.3-beta.3` and NOT stable 3.3.2 (the display version's
`-beta.N` is what `ReleaseChannel.detect` reads — stable and beta share
both the bundle id and the app name, so nothing else distinguishes
them), and `duo install` landed it on the beta build.
Renamed upstream; re-pointed 2026-09-05 (was vorssaintapp/vorssaint-utils).
The nightly sweep caught it as `staleSlug` + `anonymousDespiteToken` on both
channels (#340, #341): URLSession drops `Authorization` following GitHub's
301, so the rule was silently competing for the anonymous 60/hour per-IP
budget. Verified 2026-09-05: `repos/vorssaintapp/vorssaint-utils` answers
301 and `full_name` reads `vorssaint/vorssaint-utils`.

### Recipes/com-vorssaint-utils.swift — beta GitHubReleaseRule（`listPageSize`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是条件（`-beta.` tag 少且连续，但稳定版会把最新的 beta tag 往后推），「5 keeps margin」这个无时间的余量说法按下面的复测改成了带日期的位置加条件（2026-09-14 在第 3 位：再来一个稳定版仍在 5 条的页里，再来两个就不在），2026-09-04 的计数、位置和页大小搬到这里。

listPageSize: measured 2026-09-04 — only 4 `-beta.` tags exist in the
repo's whole history (73 releases scanned), all consecutive
(first-match index 0, worst gap 1). Small sample, so 5 keeps margin
rather than trimming to the observed minimum; real page measured at
17 KB, vs 48 KB at the old per_page=20.

复测 2026-09-14（11:02 UTC，只读 `gh api repos/vorssaint/vorssaint-utils/releases?per_page=100`）：共 76 条；`-beta.` tag 仍是 4 个、连续，位于第 3–6 位（`v3.3.3-beta.4`…`v3.3.3-beta.1`），前面是 `v3.3.5`、`v3.3.4`、`v3.3.3`。beta rule 的 `listPageSize` 是 5。
