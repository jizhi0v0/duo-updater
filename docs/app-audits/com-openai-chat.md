# ChatGPT Classic

## 基本信息
- Bundle ID: `com.openai.chat`
- Team ID: `2DC432GLL2` (OpenAI OpCo)
- 观测版本: `1.2026.184` (build `1784145287`)
- 自更新机制: Sparkle feed 存在，但 **bundle 内无 `SUFeedURL`**（挂载真包核实）
- 分发: 官方静态 CDN `persistent.oaistatic.com` + Homebrew cask `chatgpt-classic`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | —       | —        | —   | —      | ✓           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **VendorProbe**（feed 是 Sparkle
格式，但泛化 Sparkle 源靠 bundle 里的 `SUFeedURL` 起跳——Classic 没有，所以必须
recipe 显式指过去）。

## 产品状态（写进 audit 是有意的）
这是 OpenAI 的**上一代**桌面 app，维护模式。其 appcast 的 release notes 原文就是
"Install Update to keep using ChatGPT Classic … [Recommended] Or, try the new
ChatGPT app."。截至 2026-08-30 仍在发版（1.2026.184，pubDate 2026-07-15）。
如果 OpenAI 停更，`RecipeHealth` 会开始报——那是 vendor 的决定，不是我们的 bug。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.openai.chat` | 单一渠道 | — | — | ✓ |

单渠道。feed 单条 item，无 channel 标记。

## 更新检测
- 源: `https://persistent.oaistatic.com/sidekick/public/sparkle_public_appcast.xml`
  —— **这正是 Homebrew 自家 `chatgpt-classic` cask 的 `livecheck` 用的端点
  （`strategy :sparkle`）**，第三方已依赖同一端点做同一件事。
- 版本方案: `sparkle:shortVersionString`（`1.2026.184`）== 包的
  `CFBundleShortVersionString`；`sparkle:version`（`1784145287`）==
  `CFBundleVersion`。同命名空间，无陷阱。

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 没查 | 无 | 不能 |
| 证据 | — | feed 条目无 `<sparkle:deltas>`（观测 2026-08-30） | — |

## Changelog
- 来源: **没有**。feed 的 `<description>` 是产品通知文案，不是 release notes ——
  2026-09-03 抓下原文核过，整段是：「"Install Update" to keep using ChatGPT Classic」
  +「**[Recommended] Or, try the new ChatGPT app**」+ 一个指向新产品的链接。
  全 feed **只有 1 个 `<item>`**，没有任何按版本的历史，同一段文案会挂在之后每一个
  build 下面。
- Recipe 状态: **有意不接**。把厂商的劝退广告渲染成「本次更新内容」比回落到嵌入式网页
  更糟——后者至少如实呈现为「厂商的页面」。

## 一键安装
- 状态: **不支持（detection-only）**。

> ⚠️ 2026-08-30 首次审计写的是「支持（`kind: .pkg`）」，理由是「标准 flat pkg
> （Payload/Scripts）→ 系统安装器负责 bundle 外组件」。**2026-09-03 下真包复验后
> 撤销**：那个理由不成立，而且 pkg 交给 `PackageInstaller` 会 100% 被闸掉。

### 为什么不能开一键

**1. 目的地闸必然拒绝（决定性）。** `PackageInstaller.verifyOpenable` 对 pkg 是
**fail-closed**：读不出「这个包往哪写 `.app`」就不交给安装器。这个包读不出来——
不是解析器不行，是包本身没声明。拿真包的字节跑仓库自己的两个 reader，都返回空集：

```text
PackageInfo:  install-location="/"，只有空的 <bundle-version/>，没有任何 <bundle path=…>
Bom:          唯一带 .app 的一行是
              ./Library/Application Support/OpenAI/ChatGPT Classic Update/ChatGPT Classic.app.zip
              → 是个 zip，没有任何一段路径 component 以 .app 结尾
destinations(inPackageInfo:) → []
destinations(inBomListing:)  → []
```

所以开了 `install:` 的结果是：下载 78 MB，然后每次都抛
`packageDestinationsUnreadable`——一个永远点不通的 Update 按钮。
`VendorProbeRecipeTests` 里有一条用真实字节钉住这件事（变异测过：把
`install:` 加回去它就红）。

**2. 这个 pkg 根本不是「把 app 放到原地」。** payload 只是把一个 zip 放到
`/Library/Application Support/OpenAI/ChatGPT Classic Update/`，真正干活的是
`postinstall`：ditto 解包、验签（bundle id `com.openai.chat` + Team `2DC432GLL2`），
然后**无条件**装到 `/Applications/ChatGPT Classic.app`。后果：

- 装在 `/Applications/ChatGPT.app` 的副本会被 **`mv` 到 Classic 路径**——我们跟踪的
  bundle 路径在脚下变了；
- 装在**别处**的副本（`~/Applications` 也在 `AppScanner` 扫描范围内）不会被碰，
  而 `/Applications` 下多出一个新副本 → 「装成功了但用户看的那个没变」；
- 两个路径**都被占用**时脚本直接 `exit 1`（`Refusing to update because both
  ChatGPT paths are occupied`）；
- 走 mv 那条路径时它自己 `launchctl asuser … open -n` **重启 app**，跟我们的
  relaunch 撞车。

### 包身份（仍然核过，供后来者参考）
- `Developer ID Installer: OpenAI OpCo, LLC (2DC432GLL2)`，notarized，
  trusted timestamp 2026-07-15，与装机 Team 一致 → 签名闸本身是过的。
- feed 声明 `hardwareRequirements=arm64`、`minimumSystemVersion=14.0`。
- enclosure 是**无版本号移动指针**，但版本与 enclosure 出自**同一条 feed 条目**，
  新鲜度由构造保证——这一条对**检测**依然成立，检测不受影响。

## 已知问题
- 产品处于日落轨道（vendor 自己在 release notes 里劝退）。不影响接入正确性。

## 如何复验
```
# GET https://persistent.oaistatic.com/sidekick/public/sparkle_public_appcast.xml
#   → 1 条，short=1.2026.184
# 挂载 ChatGPT_Classic.dmg → com.openai.chat / 1.2026.184 / 1784145287
# channel-verify --check com.openai.chat → winning=Vendor, up to date
```

## 建议下一步
- changelog 无意义（feed 文案是迁移劝告），不建议接。
- 若 vendor 停更导致 RecipeHealth 报错，届时移出 registry 即可。
