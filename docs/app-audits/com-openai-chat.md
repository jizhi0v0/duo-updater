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
- 来源: feed `<description>` 是产品通知文案（劝用户换新 app），不是 release
  notes；未接 ChangelogRecipe
- Recipe 状态: 暂无——UI 回落到嵌入式网页

## 一键安装
- 状态: **支持**（`kind: .pkg`，直接从 feed enclosure 取）
- **读的是**: feed 条目里 vendor 自己的更新件 `ChatGPT_Classic.pkg`。它是
  **无版本号移动指针**，但版本与 enclosure 出自**同一条 feed 条目**——新鲜度
  由构造保证（好过 version.txt 与 /latest/ dmg 分家那种搭配）。
- 包验（2026-08-30 下载核实）: `Developer ID Installer: OpenAI OpCo, LLC
  (2DC432GLL2)`，notarized，trusted timestamp 2026-07-15；标准 flat pkg
  （Payload/Scripts）→ 系统安装器负责 bundle 外组件，`kind: .pkg` 正确。
  与装机 Team 一致 → 签名闸通过。
- feed 声明 `hardwareRequirements=arm64`、`minimumSystemVersion=14.0`。

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
