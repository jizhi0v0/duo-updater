# JetBrains Air

## 基本信息
- Bundle ID: `com.jetbrains.air`
- Team ID: `2ZEFAR8TH3`（downloaded cask verified 2026-06-04）
- 已验证版本: 261.681.18 (`CFBundleVersion` 261.681.18)
- 自更新机制: JetBrains Toolbox / Sparkle feed; Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable/public preview** | ✓ | ✗ | — | — | — |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Toolbox** for Toolbox-managed installs; otherwise Sparkle may answer if the installed app exposes a usable `SUFeedURL`.

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| public preview / eap | `com.jetbrains.air` | 共享 | Toolbox manifest | channel-retargeted Sparkle feed | ✓ |

## 更新检测
- 源: `ToolboxSource` for managed installs; `SparkleAppcastSource` only when safe for the actual direct install.
- 端点: verified cask `SUFeedURL` is `https://plugins.jetbrains.com/fleet-parts/fleet-feed/AIR/eap/macos_aarch64/feed.xml`; ToolboxSource retargets Air/Fleet Sparkle feed to Toolbox quality (`eap`/`release`) and compares installer-base builds.
- 注意事项: The app's baked-in `SUFeedURL` can point at nightly while Toolbox tracks Public Preview; Toolbox-managed installs must not be checked by plain Sparkle.

## Changelog
- 来源: `ChangelogRecipe`，`structuredFormat: .jetBrainsProductReleases`
- 端点: `https://data.services.jetbrains.com/products/releases?code=AIR&type=eap,preview,release`
- 跟随 channel: 否（Air 只有 preview 一条轨道）
- Recipe 状态: 已有。条目版本取 `build`（= 安装包的 `CFBundleShortVersionString`），`<h4>` 作标题，`<li>`/`<p>` 作条目，丢掉 "Share your feedback" 页脚

## 一键安装
- 状态: 仅检测 / notes
- 格式: Toolbox-managed action
- 阻塞: direct install one-click not implemented.

## 已知问题
- Non-Toolbox direct installs need real-bundle verification before claiming Sparkle coverage.

## 建议下一步
1. Keep Toolbox-managed update path as source of truth.
2. If direct Air installs matter, verify a real bundle with `application-test channel-verify` and document whether plain Sparkle is channel-correct.

## 历史与实测

- 2026-09-23：`https://air.dev/changelog` 已变成跳转壳（`window.location.replace("https://www.jetbrains.com/air/")` + meta refresh），
  `/assets/index-aByjwpFL.js`（142 KB）里只剩 React 运行时和同一个跳转，没有任何发布数据——旧的两阶段 JSX 正则 recipe 一条也匹配不上，
  界面退回嵌入网页。`jetbrains.com/air/changelog/`、`/air/whatsnew/` 均 404。
- 同日实测 releases API：不带 `type` 时 `AIR` 数组为空；`type=preview` 返回 33 条（`eap`、`release` 各 0 条），
  其中 25 条带 `whatsnew`，最早的 8 条（261.311.29 及更早，除 261.232.34 外）为空、被跳过。
  `version` 是两段式列车号（`262.834`，多个 build 共用），本机安装的 Air `CFBundleShortVersionString` = `CFBundleVersion` = `262.834.44`，
  与 `build` 一致，所以按 `build` 建条目。
- `whatsnew` 三种形态：`<h4>` + `<ul><li>`（功能版）、`<h4>` + `<p>` 正文（262.43.30/32）、只有 `<p>`（小修复，261.311.x 第一段是标题式短句）；
  页脚是 `<p>Share your feedback…</p>`，或 `Learn more about Air… and share your feedback…`，早期几条页脚不在 `<p>` 里。
  相邻 build 常复用同一份说明（如 262.132.34/35），是厂商原样。
