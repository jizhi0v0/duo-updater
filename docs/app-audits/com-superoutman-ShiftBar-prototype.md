# ShiftBar

macOS 27 原生菜单栏折叠的补充工具（主动隐藏范围 + 手动展开收起）。官网
[shiftbar.0x01.build](https://shiftbar.0x01.build/)，分发仓库
[Superoutman/ShiftBar](https://github.com/Superoutman/ShiftBar)。

审计日期 2026-09-20。**无需任何 recipe**：bundle 自报 `SUFeedURL`，`SparkleAppcastSource`
直接解析（`feed-discover` 判定 `declared`）。这份文档存在的理由是它促成了一处**通用**
解析缺口的修复，见「Changelog」一节。

## 基本信息
- Bundle ID: `com.superoutman.ShiftBar.prototype`
- Team ID: `8BRPJ7FY4X`（Developer ID Application: Beijing Likelike Culture Co., Ltd.）
- 观测版本: 0.1.13（`CFBundleVersion` 14），feed 与 dmg 均取自 2026-09-20 的 v0.1.13 release
- 自更新机制: Sparkle 2.9.4（`Contents/Frameworks/Sparkle.framework`）
- 架构: arm64 only（`lipo -archs` 单切片）
- `LSMinimumSystemVersion`: 27.0

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓（generic，零 recipe） | — | — | —（资产在 GitHub，但由 Sparkle 应答） | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**

- Homebrew: `brew search --cask shiftbar` 无结果（只有同名不同物的 `swiftbar`）。
- MAS: 无商店分发，dmg 直分发 + Developer ID 签名。
- GitHub: release 资产就是 feed 和 dmg 的托管地，但 `SUFeedURL` 排在优先链更前，
  不需要 `GitHubReleaseRule`。写一条只会是死规则。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.superoutman.ShiftBar.prototype` | 独立（唯一轨道） | — | — | ✓ |

**只有一条轨道，这一点从发布源头settled**，不是从 tag 名推的：
`.github/workflows/publish-release.yml` 在发布前断言版本号必须是 `x.y.z`、build 必须是
纯整数且**严格大于上一个 release 的 build**，`gh release edit --draft=false --latest`
无条件标 latest，全流程没有 prerelease 分支。feed 里也没有任何 `<sparkle:channel>` 标签
——不是「全部打标因而没有默认渠道」那种 `NEEDS BINDING` 形状。

⚠️ bundle id 末尾的 `.prototype` **不是渠道后缀**，`ReleaseChannel.detect()` 不认它，
判定结果是 stable（见「如何复验」）。

## 更新检测
- 源: `SparkleAppcastSource`（generic，无 recipe）
- Feed: `https://github.com/Superoutman/ShiftBar/releases/latest/download/appcast.xml`
  —— 这条地址由 bundle 的 `SUFeedURL` 自报，且厂商 workflow 发布后会 `curl` 同一条地址
  与本地文件逐字节 `cmp`，所以它是厂商自己保证可用的规范地址。
- 版本方案**无陷阱**：`<sparkle:shortVersionString>0.1.13` 对 `CFBundleShortVersionString`，
  `<sparkle:version>14` 对 `CFBundleVersion`，两边都对得上。workflow 里对这两个字段与
  `release.json` 的一致性有断言。
- **按 OS 分轨**：feed 声明 `<sparkle:minimumSystemVersion>27.0`（workflow 硬断言该值），
  **无** `maximumSystemVersion`。`SparkleAppcastSource.usableItems` 会读并过滤这两个边界，
  所以这条走的是真在被消费的路径，不是 `VendorProbeSource` 那条对 min/max 视而不见的路径。
  该下限是一整代的静态下限（app 本身只在 macOS 27 上运行），但仍由 feed 每次现读，
  没有也不该冻进 `hostRequirement`。
- **按设备灰度**：无。feed 是 GitHub release 上的静态文件，无 device id、无请求参数、
  无 rollout 轨道，人人拿到同一份。
- 读的是**轨道最新 = 本机应得**：厂商自己的 Sparkle 读的就是这条 feed 的这一个 item，
  我们不比它激进（见「一键安装」）。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 无 | 能（若厂商开始发） |
| 证据 | `strings -a Sparkle.framework/Versions/B/Autoupdate` 命中 `binarydelta`/`bspatch`/`deltaFrom` 共 68 处；Sparkle 2.9.4 自带 `BinaryDelta` | 2026-09-20 取到的 feed 里没有 `<sparkle:deltas>`，`channel-verify` 报 `deltas 0`；每个 release 只挂整包 dmg | 是 Sparkle 原生 binary delta 格式，`VendorAppcastDeltas` 从 appcast 取补丁、`DeltaApplier` 套用，现成机制，无需新东西 |

- 格式: Sparkle binary delta（一旦厂商发布）
- 阻塞项: 无。纯粹是厂商目前不发。

## Changelog
- 来源: **Sparkle feed 内联** `<description sparkle:format="markdown">`（Markdown 短横线列表
  + 结尾一行系统要求散文），无独立 changelog 页 —— 官网是纯落地页，下载键指回 GitHub releases。
- 跟随 channel: 不适用（单轨道）
- Recipe 状态: **不需要**

⚠️ **这里原本有个通用缺口，本次一并修了。** 2026-09-20 实测：feed 内联了 183 字符的
notes，但 `structuredChangelog` 返回 nil，渲染落到原始文本回落路径。根因不在厂商：

- Sparkle 有**两种**官方内联 Markdown 写法，
  [官方文档](https://sparkle-project.org/documentation/publishing/)明说
  "As of Sparkle 2.9 and macOS 12, you can embed markdown release notes using
  `<description sparkle:format="markdown">`"（另有 2.4 起的 `plain-text`）。
- 我们只读了 `<sparkle:markdownDescription>` 那一种；`sparkle:format` **属性从未被解析**。
- 于是 body 落进 `descriptionHTML`，`AppcastHTMLChangelogParser.isStructured` 因为
  Markdown 短横线列表里一个 `<li>` 都没有而拒绝，structured 为 nil。

修法是通用的（不是给 ShiftBar 开小灶）：解析 `sparkle:format`，为 `markdown` 的
`<description>` **增量**登记一份到 markdown 键上——原 body 仍留在 `descriptionHTML`，
因为它是 `releaseNotesHTML` 回落。`plain-text` 故意不路由。见
`SparkleDescriptionFormatTests`。

**独立限制（与上面无关，修了也不会变）**：ShiftBar 的 workflow 每次覆写同一个
`appcast.xml` 且只保留**一个** item，所以 `releaseHistory` 恒为 1 条，历史版本的更新说明
取不到。

## 一键安装
- 状态: 支持（通用 dmg 路径，无需登记）
- 格式: dmg（v0.1.8 曾同时挂 zip，之后只有 dmg）
- 下载: `https://github.com/Superoutman/ShiftBar/releases/download/v<版本>/ShiftBar-<版本>.dmg`
  （由 feed 的 `<enclosure url>` 给出，workflow 断言它与这个模板逐字相等）
- 完整性: feed 带 `sparkle:edSignature`（EdDSA）；release 另挂 `SHA256SUMS`
- **读的是**: **人人可手动下载的 GA**。这条 feed 的唯一 item 就是厂商自己的 Sparkle
  会装的那一个，同一个 dmg 也挂在 release 页上供手动下载。不存在"抢跑厂商未分配构建"
  的问题——没有灰度、没有 prerelease 轨道可越界。
- 阻塞: 无

## 已知问题
1. `releaseHistory` 恒为 1（上游 feed 只留一个 item），见「Changelog」。
2. 上游迭代很快（0.1.8 → 0.1.13 跨两天），feed 只保留最新一版，
   所以任何按版本冻结的 fixture 都会迅速过期——本文档引用的 feed 内容以 2026-09-20 为准。

## 如何复验

全部用仓库自带 harness 对**真实 dmg**（v0.1.13，sha256
`4d0cd2394abdf65b39ba29b2f202816f27e16d4b22fd737549962464b4b50733`，与仓库
`distribution/SHA256SUMS` 一致）跑生产代码，2026-09-20：

```sh
swift run --package-path application-test feed-discover <ShiftBar dmg>
swift run --package-path application-test channel-verify <ShiftBar dmg> --expect stable
```

`feed-discover` 输出：

```
ShiftBar  [com.superoutman.ShiftBar.prototype]  0.1.13 (14)
   declared  https://github.com/Superoutman/ShiftBar/releases/latest/download/appcast.xml
      (Info.plist names it; SparkleAppcastSource already resolves this app)
```

`channel-verify` 输出（节选）：

```
  short version   0.1.13
  build version   14
  KSChannelID     <none>
  RemotingName    <none>
  inferred        stable
  ChannelBinding  <none for this app>
  detected channel  → stable
  ✓ detection matches --expect stable
  UpdateChecker.check() — full production source chain
    winning source  Sparkle
    latest          0.1.13
    download        https://github.com/Superoutman/ShiftBar/releases/download/v0.1.13/ShiftBar-0.1.13.dmg
    release notes   183 chars inline, changelogURL <nil>
    release history 1 entries
    deltas          0
    status          up to date
```

真实 bundle 读数（dmg 只读挂载，未安装）：

```
CFBundleIdentifier        com.superoutman.ShiftBar.prototype
CFBundleShortVersionString 0.1.13
CFBundleVersion            14
LSMinimumSystemVersion     27.0
SUFeedURL                  https://github.com/Superoutman/ShiftBar/releases/latest/download/appcast.xml
lipo -archs                arm64
codesign TeamIdentifier    8BRPJ7FY4X
Sparkle.framework          2.9.4
```
