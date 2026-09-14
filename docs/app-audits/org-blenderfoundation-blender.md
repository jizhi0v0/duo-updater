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
- Recipe 状态: 已有，`sourceTemplate` 按目标版本的 major.minor 取页：`https://developer.blender.org/docs/release_notes/{majorMinor}/`（有可提供的更新时取它的版本，否则取已装版本）。LTS 页（标题与 "was released on" 句都带 `LTS`、没有 Corrective Releases 小节）同样解析；开发中的 minor（"is currently in Alpha/Beta"）解析为零条，回落到嵌入网页。
- `duo verify` 的覆盖：模板 recipe 需要一个版本才能取页，Blender 没有 vendor/GitHub 源，所以**没装 Blender 的机器上这条是 `skipped`**，模板页不会被扫到。

## 一键安装
- 状态: Homebrew-managed only
- 格式: cask app
- 阻塞: direct-install detection not implemented.

## 已知问题
- dev-docs 没有「只列已发布版本」的索引（导航把开发中的 minor 排在最前），所以不走 `indexLinkPattern`，改走按 major.minor 的模板。
- 模板 recipe 在没装 Blender 的机器上 `duo verify` 为 `skipped`（见上）。

## 建议下一步
1. Keep current Homebrew + `{majorMinor}`-templated changelog coverage. A new Blender minor needs no recipe edit.

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-blenderfoundation-blender.swift — ChangelogRecipe（钉在一个版本上的发布说明页）

转引自 recipe 注释，未复测。整段原文。括号里的 "(5.3 Alpha, 5.2 Beta)" 与 "the latest RELEASED minor" 迁移时都已不成立：5.2 LTS 已发布，`source` 仍钉在 5.1（见下面的更正）。代码里去掉了括号里的版本，并把 "version-pinned to the latest RELEASED minor; bump it when a new Blender ships" 改成 "version-pinned to a RELEASED minor"，另加一句警告：只把钉的版本改到 5.2 解析出 0 条、面板静默退回内嵌网页；recipe 改好之前，5.2 用户看到的是 5.1 的说明。原句没写日期，引入它们的提交是 `599e8dde`（2026-06-04）；其余原样，重新折行。

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

### Recipes/org-blenderfoundation-blender.swift — ChangelogRecipe 从钉 `/5.1/` 改为 `{majorMinor}` 模板

2026-09-14，只读 GET，Safari UA。在上面「更正」之外补两处代码事实：版本窗口（`minimumAppVersion` / `belowAppVersion`）两个都没设，所以 `ChangelogRecipeSelection` 对任何版本都选中这条 recipe，5.2 用户看到 5.1 的说明时没有任何警告；`verify/baseline.json` 记着 `lastGoodVersion` 5.1，而 `Verify.sweepChangelog` 的 lag 检查要一个版本来比，Blender 没有 vendor/GitHub 源，版本只能来自扫描到的 Blender 拷贝，所以只在装了 Blender 的机器上才会触发。

逐页取回的结构（`<h1>` / 发布句 / `<h2 id>`）：

    5.1  "Blender 5.1 Release Notes"      "Blender 5.1 was released on March 17, 2026."       compatibility, bugfixes, corrective-releases
    5.2  "Blender 5.2 LTS Release Notes"  "Blender 5.2 LTS was released on July 14, 2026."    compatibility, bugfixes
    5.0  "Blender 5.0 Release Notes"      "Blender 5.0 was released on November 18, 2025."    compatibility, bugfixes, corrective-releases
    4.5  "Blender 4.5 LTS Release Notes"  "Blender 4.5 LTS was released on July 15, 2025."    compatibility, bugfixes
    4.2  "Blender 4.2 LTS Release Notes"  "Blender 4.2 LTS was released on July 16, 2024."    compatibility
    5.3  "Blender 5.3 Release Notes"      "Blender 5.3 is currently in Alpha until September 30, 2026."  compatibility

旧 `entryPattern` 在这些页上用 Python 复算：5.1、5.0 各 1 条，5.2、4.5、4.2、5.3 都是 0 条。上面「更正」列的三处原因缺一个都不行：前两处加上可选的 `LTS` 仍是 0 条，lookahead 再接受 `</article>` 才是 1 条。所以旧注释那句 "has to be bumped by hand" 照做，结果是静默的零条回落。LTS 页的修复列表在单独的 LTS 页上（5.2 页正文指向 `blender.org/download/lts/5-2/`），这就是它没有 Corrective Releases 小节的原因。

新 recipe 走生产路径 `ChangelogService.loadDiagnostic`（15:24 UTC，打真实页面）：

    5.2.1  → /5.2/  1 条  5.2  July 14, 2026      24 项
    5.1.2  → /5.1/  1 条  5.1  March 17, 2026     24 项
    5.0.1  → /5.0/  1 条  5.0  November 18, 2025  31 项
    4.5.3  → /4.5/  1 条  4.5  July 15, 2025      22 项
    4.2.14 → /4.2/  1 条  4.2  July 16, 2024      15 项
    5.3.0  → /5.3/  0 条
    (无版本) → source /5.2/  1 条  5.2

`BlenderChangelogRecipeTests` 的 5.1、5.2、5.3 fixture 是这次取回页面的 `<h1>` … `</article>` 切片。
