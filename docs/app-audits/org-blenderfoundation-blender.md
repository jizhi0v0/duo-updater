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

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-blenderfoundation-blender.swift — ChangelogRecipe（钉在一个版本上的发布说明页）

转引自 recipe 注释，未复测。整段原文。括号里的 "(5.3 Alpha, 5.2 Beta)" 与 "the latest RELEASED minor" 迁移时都已不成立：5.2 LTS 已发布，`source` 仍钉在 5.1（见下面的更正）。代码里去掉了括号里的版本，并把 "version-pinned to the latest RELEASED minor; bump it when a new Blender ships" 改成 "version-pinned to a RELEASED minor"，另加一句警告：只把钉的版本改到 5.2 解析出 0 条、面板静默退回内嵌网页，修复另行登记。原句没写日期，引入它们的提交是 `599e8dde`（2026-06-04）；其余原样，重新折行。

Blender — developer.blender.org/docs/release_notes/<major.minor>/ is the
clean per-version notes page (the blender.org/download marketing pages are
sprawling splash pages with no parseable block). Each page is an <h1>
"Blender 5.1 Release Notes", a <p>"Blender 5.1 was released on DATE."</p>,
then module-section <ul>s and Compatibility/Bugfixes lists up to the
"Corrective Releases" heading. We surface a COARSE summary (changed-module
list + compat/bugfix bullets). Requiring the literal "was released on" is a
GUARD: the dev-docs nav lists in-development versions first (5.3 Alpha,
5.2 Beta) whose intros read "is currently in Alpha/Beta" and so DON'T
match — yielding zero entries (safe embed fallback) rather than a partial
changelog. URL is version-pinned to the latest RELEASED minor; bump it when
a new Blender ships (same as the old Warp/Ghostty version-pins) — Blender
exposes no released-only index to follow.

更正 2026-09-14（13:59–14:01 UTC，只读 GET，Safari UA，不跟随重定向）：`developer.blender.org/docs/release_notes/5.2/` 200，`<h1>` 是 "Blender 5.2 LTS Release Notes"，正文 "was released on July 14, 2026"；`/5.3/` 的 `<h1>` 是 "Blender 5.3 Release Notes"，正文 "Blender 5.3 is currently in"；`/docs/release_notes/` 的导航依次列 5.3、5.2 LTS、4.5 LTS、5.1、5.0。recipe 的 `source` 仍是 `/5.1/`（`Recipes/org-blenderfoundation-blender.swift:27`）。只把钉的版本改成 5.2 会得到 0 条，原因有三处，都是在 13:59 UTC 取回的 5.2 页上用本地 Python 按 recipe 的 `entryPattern` 复算的：(1) `<h1>` 是 "Blender 5.2 LTS Release Notes"，而 pattern 要求 `Blender\s+<version>\s+Release Notes`；(2) 引言是 `<p>Blender 5.2 LTS was released on July 14, 2026.`，而 pattern 要求 `Blender\s+[\d.]+\s+was released on`；(3) 页上没有 `id="corrective-releases"` 的 `<h2>`（5.1 那页有 1 个，5.2 那页 0 个；5.2 的 `<h2>` 只有 `compatibility` 与 `bugfixes`），而 body 的 lookahead 要求它。
