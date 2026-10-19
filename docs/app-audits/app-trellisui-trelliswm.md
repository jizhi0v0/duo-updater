# TrellisWM

## 基本信息
- Bundle ID: `app.trellisui.trelliswm`
- Team ID: `W437NFRGZW`（Developer ID Application: Dan Fessler），0.9.4 与 0.9.5 真包一致，`spctl` 为 Notarized Developer ID
- 观测版本: 0.9.5（`CFBundleShortVersionString` 0.9.5，`CFBundleVersion` 200），取自 `https://trelliswm.app/releases/TrellisWM-0.9.5.dmg`（2026-10-19）；另取 0.9.4（198）
- 自更新机制: Sparkle（`SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks`）
- 架构 / OS: arm64；`LSMinimumSystemVersion` 14.0；`LSUIElement`（菜单栏 app，窗口管理器）
- 产品页 `https://trelliswm.app/`：下载地址写在页面脚本的配置里（`download:"/releases/TrellisWM-0.9.5.dmg"`），付费走 Lemon Squeezy，下载即 14 天 Pro 试用

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | ✓       | —        | —   | —      | —           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Sparkle**（`feed-discover`：`declared  https://trelliswm.app/appcast.xml`）。

- Homebrew —：`brew search --cask trellis` 无结果（2026-10-19）。
- MAS / GitHub —：没有。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `app.trellisui.trelliswm` | 独立 | — | — | ✓ |

feed 3 条 item 都没有 `<sparkle:channel>`；产品页只有一个下载。

## 更新检测
- 源: `SparkleAppcastSource`
- 端点: `https://trelliswm.app/appcast.xml`
- feed 形状（2026-10-19）: 3 条（0.9.5/200、0.9.4/198、0.9.3/162），`minimumSystemVersion` 14.0，没有 `maximumSystemVersion`、`phasedRolloutInterval`；每条 `<sparkle:releaseNotesLink>` 指向 `releases/TrellisWM-<version>.html`；带 `<sparkle:deltas>`
- 版本: `sparkle:version` = `CFBundleVersion`，`shortVersionString` = `CFBundleShortVersionString`

## 增量更新（delta / binary patch）

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有 | 有 | 能（已接） |
| 证据 | Sparkle | feed 里 12 个 `sparkle:deltaFrom`（from 85/149/152/162/198）；channel-verify `deltas 5`（对当前 0.9.5） | 端到端 0.9.4 → 0.9.5 只下了 12462 字节（delta），全量 dmg 4142895 |

## 已停放整包（自更新器下完、还没装的那份）

| | 客户端会停放吗 | 本次实际停放了什么 | 我们能否直接拿来装 |
|---|---|---|---|
| 结论 | 没查 | 没查 | 没查 |
| 证据 | 第二轮（运行中）没跑，见「一键安装」 | — | — |

## Changelog
- 来源: feed 只给 `releaseNotesLink`。`Recipes/app-trellisui-trelliswm.swift` 按 `sourceTemplate` 取所提供版本的 `releases/TrellisWM-<version>.html`：每个版本一个 `<h1>`，下面是 `<h2>` 分节和 `<li>` 条目。0.9.5 的页面还带着 0.9.4 那一节，所以版本取自每个 `<h1>`，每节一条。
- 结构化（channel-verify，从 0.9.4 起，2026-10-19）: `recipe changelog:app.trellisui.trelliswm:-: 2 entries; newest 0.9.5: 1 items, headings ["Improved"]; first items ["See where a window will land before you "]`。一次临时测试（已删）用 `ChangelogService.parse` 跑三个真实页面：0.9.5 页 → 0.9.5（1 条）+ 0.9.4（16 条，分节 New / Pictures in motion / Fixed）；0.9.4、0.9.3 页没有 `<h1>`，解析为 nil，退回内嵌网页（只在它们再次成为所提供版本时才会用到）。
- 跟随 channel: 不适用
- Recipe 状态: ✓ 已有（之前 pane 是 `web page …, no structure`）

## 一键安装
- 状态: 支持（Sparkle 通用路径，dmg，EdDSA + Team ID 闸）
- 端到端（2026-10-19）:
  - 第一轮（未运行）：0.9.4（官方 dmg）放进 `/Applications`。`duo check TrellisWM` → `0.9.4 → 0.9.5 [Sparkle, in-place]`；`duo install TrellisWM --yes --json` → `outcome: installed`，`route: sparkle`，`bytesDownloaded: 12462`（delta），7.0 s。之后为 0.9.5 (200)，inode 变了，`codesign --verify --deep --strict` 通过，`spctl` accepted / Notarized Developer ID，与厂商 0.9.5 `diff -r --no-dereference` 一致。
  - 第二轮（运行中）未跑：它是窗口管理器，启动就接管并重排屏幕上的窗口，首次设置还会关掉一些 macOS 功能（它的 0.9.4 说明写「设置可以把被关掉的 macOS 功能重新打开」），超出验证该动的范围。
- 格式: dmg
- 校验: 只有 EdDSA 签名，没有 SHA 摘要
- **读的是**: 人人可手动下载的 GA。enclosure 就是产品页下载按钮指向的 dmg，feed 无 `phasedRolloutInterval`
- 嵌套: 只有 Sparkle 自带的 `Updater.app`
- 阻塞: 无

## 已知问题
- 无。

## 如何复验

```sh
curl -sSL -o TrellisWM-0.9.5.dmg https://trelliswm.app/releases/TrellisWM-0.9.5.dmg
swift run --package-path application-test feed-discover TrellisWM-0.9.5.dmg
swift run --package-path application-test channel-verify TrellisWM-0.9.5.dmg
curl -sSL https://trelliswm.app/releases/TrellisWM-0.9.5.html | grep -oE '<h1>[^<]+</h1>|<h2>[^<]+</h2>'
```

2026-10-19：channel-verify（0.9.5 dmg）`winning source Sparkle`、`latest 0.9.5`、`release history 3 entries`、`deltas 5`、`status up to date`。

## 建议下一步
1. 第二轮（运行中，自更新器已暂存）征得同意后再跑。
