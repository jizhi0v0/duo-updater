# Audacity

## 基本信息
- Bundle ID: `org.audacityteam.audacity`
- Team ID: `AWEYX923UX`（downloaded cask verified 2026-06-04）
- 已验证版本: 3.7.7.0 (`CFBundleVersion` 3.7.7.0)
- 自更新机制: Homebrew cask（`auto_updates` 未声明，即 false）

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✓        | —   | —      | —           |
| **preview**  | —       | —        | —   | ✗      | ✗           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **Homebrew** only for brew-installed copies.

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `org.audacityteam.audacity` | — | brew provenance | Homebrew cask | ✓ |
| preview | `org.audacityteam.audacity` | 共享 | 无 | prerelease | ✗ |

## 更新检测
- 源: `HomebrewCaskSource`
- 端点: Homebrew cask `audacity`
- 注意事项: downloaded cask bundle has no `SUFeedURL`; cask version is `3.7.7` while `CFBundleShortVersionString` is `3.7.7.0`. Changelog parser deliberately skips `Audacity-4.0.0.alpha-*` prerelease rows.

## Changelog
- 来源: `ChangelogRecipe`
- 跟随 channel: 否
- Recipe 状态: 已有，GitHub releases page (`https://github.com/audacity/audacity/releases`)

## 一键安装
- 状态: Homebrew-managed only
- 格式: cask app
- 阻塞: direct-install detection not implemented.

## 打包形状（runtime 标记相关）
- `CFBundleExecutable` 是 **`Wrapper`**，不是 `Audacity`：70,080 字节的启动器，`otool -L` 只有
  `libSystem.B.dylib`，`strings` 里只有 `Audacity` 和 `AUDACITY_PRESERVE_LIBRARY_PATH`——
  作用是设好 dylib 搜索路径再 exec 同目录的 `Audacity`（21,251,232 字节，链 AppKit）。
- `Contents/Frameworks` 里 **144 个 `lib-*.dylib`，一个 `.framework` 都没有**，所以按布局判定
  runtime 的规则全部落空。
- 后果：`AppRuntimeDetector` 原来把标记读在 `Wrapper` 上，Audacity 一行没有 runtime 徽章。
  2026-09-05 加了「退到 `Contents/MacOS/<bundle 名>` 再读一次」的规则后判为 `native` +
  `Links AppKit`。实测于 3.7.8.0（mini，macOS 26.6）。

## 已知问题
- Preview/alpha builds share the stable bundle id and currently have no safe detection signal.

## 建议下一步
1. No custom detection needed for brew-installed Audacity.
2. Keep Audacity 4 preview blocked until a distinct bundle id or reliable installed-channel marker exists.
