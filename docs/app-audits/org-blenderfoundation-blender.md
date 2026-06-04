# Blender

## 基本信息
- Bundle ID: `org.blenderfoundation.blender`
- Team ID: `68UA947AUU`（downloaded cask verified 2026-06-04）
- 已验证版本: 5.1.2 (`CFBundleVersion` 5.1.2)
- 自更新机制: Homebrew cask（`auto_updates` 未声明，即 false）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓        | —   | —      | —           |
| **daily/beta/alpha** | — | — | — | ✗ | ✗ |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew** only for brew-installed copies.

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.blenderfoundation.blender` | — | brew provenance | Homebrew cask | ✓ |
| daily/beta/alpha | `org.blenderfoundation.blender` | 共享 | 无 | builder builds | ✗ |

## 更新检测
- 源: `HomebrewCaskSource`
- 端点: Homebrew cask `blender`
- 注意事项: downloaded cask bundle has no `SUFeedURL`; daily/alpha/beta builds are rolling and not safely distinguishable from stable by bundle id.

## Changelog
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有但 **version-pinned** to `https://developer.blender.org/docs/release_notes/5.1/`

## 一键安装
- 状态: Homebrew-managed only
- 格式: cask app
- 阻塞: direct-install detection not implemented.

## 已知问题
- Changelog URL must be bumped each Blender minor release; there is no released-only index.

## 建议下一步
1. Keep current Homebrew + version-pinned changelog coverage.
2. When Blender ships a new stable minor, update the ChangelogRecipe URL and fixture.
