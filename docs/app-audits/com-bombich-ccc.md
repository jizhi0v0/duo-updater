# Carbon Copy Cloner

## 基本信息
- Bundle ID: `com.bombich.ccc`
- Team ID: `L4F2DED5Q7`
- 已安装版本: 未在本机安装；核对了厂商官方下载 `ccc-7.1.6.8368.zip`（`CFBundleShortVersionString` 7.1.6 / `CFBundleVersion` 8368）
- 自更新机制: Sparkle（`SUFeedURL` = `https://api.bombich.com/updates/ccc`），但该端点当前对任何请求都返回空 body（见下）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✗（见下）| ✗（auto_updates）| —   | —      | ✓           |
| **beta**     | ✗（见下）| —        | —   | —      | ✓（2026-08-29 补齐）|

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（两个 channel）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.bombich.ccc` | — | `download_ccc.php?v=latest` 重定向文件名 | `ReleaseChannel.detect()` 默认 `.stable` | ✓ |
| beta    | `com.bombich.ccc` | 共享 | `download_ccc.php?v=latestbeta` 重定向文件名 + `CFBundleShortVersionString` 的 `-b<N>` 后缀（`detect()` 新增 step 0.8）| `channel: .beta` | ✓（2026-08-29 补齐，见下）|

**2026-08-29 补记：此前记为"阻塞，需人工抓包"的判断是错的，不是查不到，是没试对参数。**
用户提供了 `download_ccc.php?v=latestbeta`（**无连字符**，区别于之前试过的
`?v=beta`/`?v=latest-beta`）——这个变体当时没试过。实测这条路径直接跟 stable 一样两跳
302 到一个真实的 beta 构件（`ccc-7.1.7-b7.8389.zip`），完全不需要抓包或猜 `SUFeedURL`
的请求形状。

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

### beta

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

- 来源: VendorProbe 的 `changelogURL` 指向厂商自己的发布记录页
  `https://bombich.com/software/updates/ccc7_rn.html`（三段式版本号，按发布倒序列出
  7.0 → 7.1.6，2026-08-29 核对）
- 跟随 channel: 是——stable 的 `changelogURL` 指向 `ccc7_rn.html`，beta 的
  `changelogURL` 指向独立页面 `ccc7_rn_beta.html`
- Recipe 状态: 不需要独立 `ChangelogRecipe`——`changelogURL` 已经是一个可读的人工
  发布记录页，在详情窗口以 WebView 呈现即可，不需要结构化解析

## 一键安装

- 状态: **仅检测**，未接一键
- 格式: zip（`.app` 直出，无嵌套 pkg）
- **读的是**: 人人可手动下载的 GA（`download_ccc.php?v=latest` 就是厂商官网"下载"
  按钮背后的同一个链接，不存在轨道/灰度问题）
- 阻塞: 不是技术阻塞，是范围决策——CCC 装机时带一个特权 helper
  （`com.bombich.ccchelper`）、一个 LaunchDaemon 和一个 XPC service，原地替换
  `.app` 相比本 registry 里现有的 zip-swap 一键（不带特权组件的应用）是一个更大的
  改动面，留给单独决定，本次审计不默认加

## 已知问题

- Sparkle `SUFeedURL` 本身处于失效状态（见"更新检测"），如果 Bombich 之后修好这个
  端点，`SparkleAppcastSource` 会自动开始生效并可能与本次新增的 VendorProbe
  同时应答——`UpdateChecker` 的优先链会让 Sparkle 赢（先于 VendorProbe），行为仍然
  正确，不需要预先处理。
- 一键安装仍未接（stable、beta 都是），见下"建议下一步"。

## 建议下一步

1. **stable 检测已完成**：`DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift`
   新增 `com.bombich.ccc` 的 `VendorProbeRecipe`（`.redirectFilename`，
   `download_ccc.php?v=latest`）；回归测试
   `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/CarbonCopyClonerProbeRecipeTests.swift`。
2. **beta 检测已完成（2026-08-29）**：同一文件新增第二条 `com.bombich.ccc` recipe
   （`channel: .beta`，`download_ccc.php?v=latestbeta`），`ReleaseChannel.swift`
   新增 step 0.8 识别 `-b<N>` 短后缀，测试同一份文件里补齐（stable/beta 各自的
   pattern 互不误伤 + `detect()` 单测 + 负控制）。此前记为"需要用户抓包"的阻塞
   已解除——是没试对 query 参数拼写，不是真的需要抓包。
3. **一键安装**：技术上可行（zip 直出 `.app`，Team `L4F2DED5Q7`，两个 channel 同一个
   Team，签名闸能一致通过），但因为装机带特权 helper/LaunchDaemon/XPC，是否要做需要
   单独决定，未在本次默认加入。
