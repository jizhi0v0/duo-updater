# Carbon Copy Cloner

## 基本信息
- Bundle ID: `com.bombich.ccc`——**三个独立、各自仍在维护的大版本代际（5/6/7）共用同一个
  bundle id**，2026-08-29 下载并展开三份真实 zip 核实：
  - CCC 7: `ccc-7.1.6.8368.zip`，`CFBundleShortVersionString` 7.1.6 / `CFBundleVersion` 8368
  - CCC 6: `ccc-6.1.13.7699.zip`，6.1.13 / 7699
  - CCC 5: `ccc-5.1.28.6213.zip`，5.1.28 / 6213
- Team ID: `L4F2DED5Q7`（三个代际相同）
- 已安装版本: 未在本机安装
- 自更新机制: Sparkle，但两条 `SUFeedURL` 都失效（见下）——CCC 7 是
  `https://api.bombich.com/updates/ccc`；CCC 5/6 是**不同的字面 URL**
  `https://update.bombich.com/software/updates/ccc.php`，但会 301→302 转到前者，回同一个
  空 body

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **CCC 7 stable** | ✗（见下）| ✗（auto_updates）| —   | —      | ✓           |
| **CCC 7 beta**   | ✗（见下）| —        | —   | —      | ✓（2026-08-29 补齐）|
| **CCC 6 stable** | ✗（同一套失效基建）| ✗（auto_updates 只覆盖 latest 那份 cask）| — | — | ✓（2026-08-29 补齐） |
| **CCC 5 stable** | ✗（同上）| ✗（同上）| — | — | ✓（2026-08-29 补齐） |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（四条 recipe）

## Channel 详情

| Channel/代际 | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| CCC 7 stable | `com.bombich.ccc` | — | `download_ccc.php?v=latest` 重定向文件名 | `channel: .stable` + `installedVersionPattern: ^7\.` | ✓ |
| CCC 7 beta   | `com.bombich.ccc` | 共享 | `download_ccc.php?v=latestbeta` 重定向文件名 + `CFBundleShortVersionString` 的 `-b<N>` 后缀（`detect()` 新增 step 0.8）| `channel: .beta` + `installedVersionPattern: ^7\.` | ✓ |
| CCC 6 stable | `com.bombich.ccc` | 共享 | `download_ccc.php?v=ccc6` 重定向文件名 | `installedVersionPattern: ^6\.` | ✓（2026-08-29 新增） |
| CCC 5 stable | `com.bombich.ccc` | 共享 | `download_ccc.php?v=ccc5` 重定向文件名 | `installedVersionPattern: ^5\.` | ✓（2026-08-29 新增） |

**2026-08-29 补记 1：beta 阻塞是没试对参数，不是真的需要抓包。**
用户提供了 `download_ccc.php?v=latestbeta`（**无连字符**，区别于之前试过的
`?v=beta`/`?v=latest-beta`）——这个变体当时没试过。实测这条路径直接跟 stable 一样两跳
302 到一个真实的 beta 构件（`ccc-7.1.7-b7.8389.zip`），完全不需要抓包或猜 `SUFeedURL`
的请求形状。

**2026-08-29 补记 2（关键正确性问题，用户指出）：CCC 有多个仍在维护的大版本，
`?v=latest` 只会给最新的那个（CCC 7），跨代际比较是错的。**
Bombich 的下载页（`bombich.com/download`）标着 macOS 兼容矩阵：CCC 7 需要 Ventura+，
CCC 6 覆盖 Catalina–Sonoma，CCC 5 覆盖 High Sierra–Big Sur——三条线现在都还在发布点版本
（下载页同时列着 `?v=ccc5`/`?v=ccc6`/`?v=ccc7` 三个可用链接，不只是 `?v=latest` 那个别名）。
升代际是**付费升级**，不是免费更新："We do not sell CCC 4 or CCC 5 licenses. To use CCC 4
or 5, please purchase a CCC 6 license"（bombich.com/en/kb/ccc/6）。

在这条修复之前，`download_ccc.php?v=latest` 那一条 recipe 会让**任何**装着 CCC 5/6 的机器
被告知"有新版本 7.1.6"——版本号数字上确实更大（"7.1.6" > "6.1.13"），但产品意义上是错的：
Big Sur 上的 CCC 5 用户根本装不了 CCC 7（需要 Ventura），而且这是一次要掏钱的大版本升级，
不是免费的点更新。这正是 `VersionComparator`"绝不跨命名空间比较"规则想防的那类陷阱的
另一种形状。

修复方式：给 `VendorProbeRecipe` 加了一个新字段 `installedVersionPattern`（`hostRequirement`
的对偶——`hostRequirement` 管"这台 Mac 能不能跑这个 recipe 的构建"，`installedVersionPattern`
管"装机的这个 app 是不是这个 recipe 想覆盖的那个代际"），`VendorProbeSource.probeDiagnostic`
在 channel gate 之后、host gate 之前新增一道过滤，三条 stable recipe 各自锁定
`^5\.`/`^6\.`/`^7\.`，互不覆盖。同时因为三条 recipe 现在共享 `(bundleID, channel)`，
`channelProofsCoverEveryChannelRecipe` 那条既有守卫要求每条都带独立 `variant`
（`"ccc5"`/`"ccc6"`/`"ccc7"`），否则会共用一个 `recipeID`，验证基线和 issue 历史会串。

**2026-08-29 补记 3：四条 recipe 都补上了 `hostRequirement.minimumSystemVersion`。**
一开始没加,理由是"静态值追不上会变的端点"——但去查证后发现这个顾虑不成立:
Wayback Machine 里 CCC 6 系统需求页 2022-05（发布约一年后）的快照已经写着
"macOS 10.15 Catalina"，跟现在（页面最后更新 2023-11）完全一样，两年多没挪过；
CCC 5 的系统需求页（最后更新 2021-02，CCC 6 发布后 CCC 5 停止开发）写的
"OS X 10.10 Yosemite" 跟挂载真包读到的 `LSMinimumSystemVersion` 逐字节一致。
Bombich 是按大版本号发一份独立的系统需求文档,不是按点版本——这跟 `hostRequirement`
已有的用法（Raycast v2 的 macOS 26 门槛,对这条产品线是永久的）是同一种"固定门槛"
形状,不是 Sparkle `sparkle:minimumSystemVersion` 那种"每次发布都可能变,必须逐条动态读"
的形状。三个值都是从真机挂载的 `LSMinimumSystemVersion` 读出来的（CCC5=10.10、
CCC6=10.15、CCC7=13.1，beta 与 stable 共用 13.1），CCC5/CCC6 各有厂商自己文档独立佐证。

## 更新检测

### stable

- 源: VendorProbe，`.redirectFilename` 模式
- 端点: `https://bombich.com/software/download_ccc.php?v=latest`
  （HEAD 请求经两跳重定向 `api.bombich.com/download/ccc?v=latest` → CDN
  `bombich.scdn1.secure.raxcdn.com/software/files/ccc-7.1.6.8368.zip`，只读
  `Location`/最终 URL，不下载 27 MB 正文）
- 版本方案: 文件名 `ccc-<marketing>.<build>.zip`，marketing 段是 2 或 3 段（`7.1` 或
  `7.1.6`，取决于版本代际），build 恒为 3 位以上数字（`8368`）。正则按"末尾 3 位以上
  数字段是 build，前面全部是 marketing"切分，两种代际都验证过。marketing 每次发布都
  会变（7.0→7.0.4→7.1→…→7.1.6，参照 `https://bombich.com/software/updates/ccc7_rn.html`
  的发布历史），不是冻结 marketing 的 app，默认 marketing-only 比较（`versionIsBuild:
  false`）成立。

### CCC 6 stable

- 源: VendorProbe，`.redirectFilename` 模式，同一台端点换个 query 值
- 端点: `https://bombich.com/software/download_ccc.php?v=ccc6`，两跳 302 到 CDN：
  `bombich.scdn1.secure.raxcdn.com/software/files/ccc-6.1.13.7699.zip`（2026-08-29 实测）
- 真机验证（下载并展开真实 zip）: `CFBundleShortVersionString="6.1.13"
  CFBundleVersion="7699" CFBundleIdentifier="com.bombich.ccc"`，Team `L4F2DED5Q7`
- 版本方案: 与 CCC 7 stable 同一套正则（`ccc-<marketing>.<build>.zip`）
- `installedVersionPattern: ^6\.`——锁定这条只对装机是 6.x 的 CCC 生效，见上面"补记 2"
- changelog: `https://bombich.com/en/kb/ccc/6/release-notes`（独立于 CCC 7 的页面，
  2026-08-29 核对 200 且有真实内容，标题 "CCC 6 Release Notes"）

### CCC 5 stable

- 源: VendorProbe，`.redirectFilename` 模式，同一台端点再换一个 query 值
- 端点: `https://bombich.com/software/download_ccc.php?v=ccc5`，两跳 302 到 CDN：
  `bombich.scdn1.secure.raxcdn.com/software/files/ccc-5.1.28.6213.zip`（2026-08-29 实测）
- 真机验证（下载并展开真实 zip）: `CFBundleShortVersionString="5.1.28"
  CFBundleVersion="6213" CFBundleIdentifier="com.bombich.ccc"`，Team `L4F2DED5Q7`
- 版本方案: 同上，`installedVersionPattern: ^5\.`
- changelog: `https://bombich.com/en/kb/ccc/5/release-notes`（2026-08-29 核对 200）

### beta（CCC 7 专属）

- 源: VendorProbe，`.redirectFilename` 模式，同一台端点换个 query 值
- 端点: `https://bombich.com/software/download_ccc.php?v=latestbeta`（**无连字符**——
  `?v=beta`、`?v=latest-beta` 都是死路，`?v=latestbeta` 才是真的）。同样两跳 302 到
  CDN：`bombich.scdn1.secure.raxcdn.com/software/files/ccc-7.1.7-b7.8389.zip`
- 真机验证（2026-08-29，下载并展开真实 zip）: `CFBundleShortVersionString="7.1.7-b7"
  CFBundleVersion="8389" CFBundleIdentifier="com.bombich.ccc"`，Team `L4F2DED5Q7`（与
  stable 一致），已公证
- 版本方案: 文件名 `ccc-<marketing>-b<N>.<build>.zip`（例：`7.1.7-b7`），正则在原有
  marketing 分组末尾加 `-b[0-9]+`，捕获组连同 beta 后缀一起取出，与
  `CFBundleShortVersionString` 逐字符一致，`versionIsBuild` 同样不需要开
- **channel 检测信号**: `CFBundleShortVersionString` 的 `-b<N>` 短后缀——不是 Mozilla
  的 `b<N>`（要求恰好一个点、无连字符，如 `155.0b5`），也不是 GitHub Desktop 那种全词
  `-beta<N>`（如 `3.5.12-beta2`）。`ReleaseChannel.detect()` 原有 step 4 两条规则都
  接不住，补了一条按 bundle id 限定的 step 0.8（同 Little Snitch 那条 0.7 一个思路：
  bundle id 共享、版本串本身就是唯一信号时，才值得为单个 app 单独开规则，不改全局
  pattern）
- changelog: 复用之前调查阶段就已经找到的 `ccc7_rn_beta.html`（当时只是没接进 recipe）

- 注意事项:
  - **Info.plist 确实有 `SUFeedURL`**（`https://api.bombich.com/updates/ccc`），
    这一点最初的调查前提是错的（并非"没有暴露给静态扫描"）。但该端点对所有测试过的
    请求变体（裸 GET、多种 User-Agent 含 Sparkle 格式的、加 `appVersion` 查询参数、
    以及 `SparkleAppcastSource` 自己会发的那个 `URLSession`/UA 组合）都返回
    **HTTP 200 + Content-Length 0**（2026-08-29 测量，五种变体，含原生 `URLSession`
    复现，排除了 Python/TLS 指纹被拦截的可能）。`SparkleAppcastSource` 会把空 body
    解析成空 item 列表，永远报"无更新"——这是一个静默失效的源，不是"没有"的源。
  - Homebrew cask `carbon-copy-cloner` 是 `auto_updates: true`，`HomebrewCaskSource`
    正确跳过，不是遗漏。
  - 因此在这两个失效点之上补一个 VendorProbe 是必要的，不是重复建设。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 没查（Sparkle feed 本身读不到内容，无法判断） | 不适用 |
| 证据 | 主二进制里能看到 `SUUpdater`/`SparkleDelegate` 符号，但 `Contents/Frameworks`
  下没有独立的 `Sparkle.framework`（疑似静态链接一个较旧的 Sparkle）| — | — |

- 格式: 未知（Sparkle feed 打不开，无法确认是否发 `<sparkle:deltas>`）
- 阻塞项: 同上——feed 端点本身空 body，delta 机制无从验证

## Changelog

- 来源: 每条 recipe 的 `changelogURL` 指向该代际自己的发布记录页——CCC 7 stable
  `ccc7_rn.html`、CCC 7 beta `ccc7_rn_beta.html`、CCC 6
  `en/kb/ccc/6/release-notes`、CCC 5 `en/kb/ccc/5/release-notes`，全部 2026-08-29
  核对过 200 且有真实按版本排列的内容
- 跟随 channel/代际: 是，四条各自独立
- Recipe 状态: 不需要独立 `ChangelogRecipe`——都是可读的人工发布记录页，详情窗口
  WebView 呈现即可

## 一键安装

- 状态: **仅检测**，四条都未接一键
- 格式: zip（`.app` 直出，无嵌套 pkg），三个代际一致
- **读的是**: 人人可手动下载的 GA（`download_ccc.php?v=<latest|latestbeta|ccc6|ccc5>`
  就是厂商下载页对应按钮背后的同一个链接，不存在轨道/灰度问题）
- 阻塞: 不是技术阻塞，是范围决策——CCC 装机时带一个特权 helper
  （`com.bombich.ccchelper`）、一个 LaunchDaemon 和一个 XPC service（CCC 6 的挂载
  验证过同一类组件），原地替换 `.app` 相比本 registry 里现有的 zip-swap 一键（不带
  特权组件的应用）是一个更大的改动面，留给单独决定，本次审计不默认加

## 已知问题

- Sparkle 两条 `SUFeedURL`（CCC 7 自己那条 + CCC 5/6 共用那条）都处于失效状态（见
  "更新检测"），如果 Bombich 之后修好，`SparkleAppcastSource` 会自动开始生效并可能与
  本次新增的 VendorProbe 同时应答——`UpdateChecker` 的优先链会让 Sparkle 赢（先于
  VendorProbe），行为仍然正确，不需要预先处理。
- 一键安装仍未接（四条都是），见下"建议下一步"。
- CCC 5/6 是否也有 beta 轨道未确认——`?v=beta`/`?v=latestbeta` 在这台机器上只观察到
  返回 CCC 7 的构件，没有证据说 5/6 完全没有，只是没找到证据说它们有；不是"查过了
  没有"，是"没查到证据"，别当成已排除。

## 建议下一步

1. **CCC 7 stable/beta 检测已完成**：
   `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift` 两条
   `com.bombich.ccc` recipe（`.redirectFilename`，`download_ccc.php?v=latest` /
   `?v=latestbeta`）；`ReleaseChannel.swift` 新增 step 0.8 识别 `-b<N>` 短后缀。
2. **多代际正确性已修复（2026-08-29，用户发现的问题）**：新增
   `VendorProbeRecipe.installedVersionPattern` 字段（`hostRequirement` 的对偶）+
   `VendorProbeSource.probeDiagnostic` 里新的一道过滤，CCC 6/CCC 5 各自注册一条
   recipe 并锁定 `^6\.`/`^5\.`，避免被 `?v=latest`（CCC 7 的答案）跨代际覆盖。三条
   stable recipe 因为共享 `(bundleID, channel)` 各补了 `variant`
   （`"ccc7"`/`"ccc6"`/`"ccc5"`），满足 `channelProofsCoverEveryChannelRecipe` 的
   唯一性要求。回归测试全部在
   `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/CarbonCopyClonerProbeRecipeTests.swift`：
   四条 recipe 数量断言、每代际 `installedVersionPattern` 的 3×3 矩阵（只有对角线为
   真）、一条不依赖网络的"未来第 8 代际找不到 recipe 时必须答 nil 而不是随便退化到
   某一条"、以及一条打真实端点的活测试（CCC 6 装机必须解析到 build `7699`，不能是
   CCC 7 的 `8368`）。`duo verify --only bombich`：四条全绿。
3. **一键安装**：技术上可行（zip 直出 `.app`，四条 recipe 的 Team 都是
   `L4F2DED5Q7`，签名闸能一致通过），但因为装机带特权 helper/LaunchDaemon/XPC，是否
   要做需要单独决定，未在本次默认加入。
4. **CCC 5/6 beta 轨道**：未确认是否存在，不是本次范围；如果以后要查，起点是
   `?v=<ccc5|ccc6>beta` 这类同构猜测,或者装一份 5/6 真机在偏好里勾选 beta 开关看
   `SUFeedURL` 请求变化。
