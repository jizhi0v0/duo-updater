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
| **beta**     | ✗（见下）| —        | —   | —      | ✗（需人工抓包）|

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（本次新增）

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.bombich.ccc` | — | `download_ccc.php?v=latest` 重定向文件名 | 无 | ✓（本次接入） |
| beta    | `com.bombich.ccc` | 共享 | Settings → Software Update → "Inform me of beta releases" 勾选项 | 未知（疑似同一 `SUFeedURL` 请求上叠加的 header/参数）| 阻塞，需人工抓包 |

## 更新检测

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
- 跟随 channel: 否（只有 stable 页面被接入；beta 有独立页面
  `ccc7_rn_beta.html`，但 beta 检测本身被阻塞，暂不需要）
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

- **Beta channel 未接入**，需要人工协助才能继续：
  - 同 bundle id `com.bombich.ccc`，通过 Settings → Software Update → "Inform me
    of beta releases" 勾选项启用（`https://bombich.com/software/updates/ccc7_rn_beta.html`
    显示当前 beta 是 "CCC 7.1.7-b7 (pre-release)"，证明轨道确实存在）。
  - 公开端点没有对应的 beta 构建：`download_ccc.php?v=beta` 重定向到普通下载页
    （不是文件），`?v=latest-beta` 直接回退到和 `?v=latest` 完全相同的 stable zip
    （2026-08-29 实测两者）。
  - 真正的 beta 内容大概率要在勾选该偏好后，观察真实 app 对 `SUFeedURL`
    （`https://api.bombich.com/updates/ccc`）发出的实际请求（多半是叠加了某个
    header 或查询参数）才能确认——这需要用户用抓包工具（Charles/mitmproxy）在开着
    beta 开关的真机上验证，本次调查到此为止，未继续猜测。
- Sparkle `SUFeedURL` 本身处于失效状态（见"更新检测"），如果 Bombich 之后修好这个
  端点，`SparkleAppcastSource` 会自动开始生效并可能与本次新增的 VendorProbe
  同时应答——`UpdateChecker` 的优先链会让 Sparkle 赢（先于 VendorProbe），行为仍然
  正确，不需要预先处理。

## 建议下一步

1. **stable 检测已完成**：`DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift`
   新增 `com.bombich.ccc` 的 `VendorProbeRecipe`（`.redirectFilename`，
   `download_ccc.php?v=latest`）；回归测试
   `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/CarbonCopyClonerProbeRecipeTests.swift`。
2. **beta channel**：需要用户抓包（Settings 里勾上 "Inform me of beta releases"
   后，观察真实 app 对 `api.bombich.com/updates/ccc` 发出的请求头/参数），拿到证据
   后再决定是走同一 `SUFeedURL`（改造 `SparkleAppcastSource`/`ChannelBinding`）还是
   一个独立的 VendorProbe beta 端点。
3. **一键安装**：技术上可行（zip 直出 `.app`，Team `L4F2DED5Q7`），但因为装机带特权
   helper/LaunchDaemon/XPC，是否要做需要单独决定，未在本次默认加入。
