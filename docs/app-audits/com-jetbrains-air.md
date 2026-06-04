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
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有，两阶段 shell → hashed JS bundle (`https://air.dev/changelog`)

## 一键安装
- 状态: 仅检测 / notes
- 格式: Toolbox-managed action
- 阻塞: direct install one-click not implemented.

## 已知问题
- Non-Toolbox direct installs need real-bundle verification before claiming Sparkle coverage.

## 建议下一步
1. Keep Toolbox-managed update path as source of truth.
2. If direct Air installs matter, verify a real bundle with `application-test channel-verify` and document whether plain Sparkle is channel-correct.
