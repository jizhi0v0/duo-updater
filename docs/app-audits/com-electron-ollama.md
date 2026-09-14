# Ollama

## 基本信息
- Bundle ID: `com.electron.ollama`
- Team ID: 未复核（local bundle signature not checked）
- 观测版本: 0.24.0（审计当天 Homebrew cask 为 0.30.4）
- 自更新机制: Electron / Homebrew cask `auto_updates`

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   | —       | ✗        | —   | ✓      | ○           |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **GitHub**（`ollama/ollama` `/releases/latest`）。`auto_updates: true` cask 会让 Homebrew 返回 nil。2026-06-06 接入 `GitHubReleaseRule`，验证 latest zip 内 `.app` 自报 `0.30.6` 与 tag `v0.30.6` 同构。

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | `com.electron.ollama` | — | — | GitHub releases | C ✓ / G ✓（2026-06-06 接入） |

## 更新检测
- 源: `GitHubReleaseRule`（`ollama/ollama`，默认 pattern 剥 `v` 前缀）；local bundle has no `SUFeedURL`.
- 端点: `https://api.github.com/repos/ollama/ollama/releases/latest`。
- 验证（2026-06-06）: `ollama.com/install.sh` 与 `ollama.com/download/Ollama.dmg` 均 307→ github `releases/latest/download`；latest zip 内 `.app` 自报 `CFBundleShortVersionString = 0.30.6`，与 tag `v0.30.6` 同构，无幽灵更新。
- 备选（未采用）: redirect-VendorProbe 抠最终 path 的 `v0.30.6`，可免 GitHub API 60/时限流；本次保留 API 方式（用户决定，2026-06-06）。
- 注意事项: 审计当天观测到的那份拷贝是 0.24.0、cask 已是 0.30.4，两者漂移，说明 `auto_updates` cask 不能当检测源。

## Changelog
- 来源: `ChangelogRecipe` + `ChangelogCatalog`
- 跟随 channel: 否
- Recipe 状态: 已有，GitHub releases page（`https://github.com/ollama/ollama/releases`）
- 条目取 `<li>`；有的发布整篇是散文、一个 `<li>` 都没有（2026-09-11 实测 v0.34.0、v0.32.12），
  这时走第二条 `<p>` pattern，跳过 "Full Changelog: vA...vB" 对比链接行（当天第一页 10 条发布都以它收尾）。
  没有这条兜底时，没条目的发布会被丢掉，最新一条恰好是散文时整个面板就落后一个版本（#507）。

## 一键安装
- 状态: 已启用（best-effort），`GitHubReleaseRule` 的 `installAssetPattern` 取 `Ollama-darwin.zip`，原地替换；装完 `ollama serve` 仍是旧进程，行落到 `needsRestart`。

## 已知问题
- 无。（原先这里写「只有 release notes；更新状态仍会是 unknown」，那是 2026-06-06 接入 `GitHubReleaseRule` 之前的状态。）

## 建议下一步
1. 检测已由 `GitHubReleaseRule` 接上（见「更新检测」）；原先这一条建议的就是它。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-electron-ollama.swift — ChangelogRecipe（GitHub releases 页）

转引自 recipe 注释，未复测。

Most releases are a bullet list, but some are written as prose with no
<li> at all — v0.34.0 and v0.32.12 on the live page, 2026-09-11. An entry
that yields no items is dropped, so the newest release vanished from the
pane and `duo verify` read the changelog as a whole release behind
(#507).

It skips the "Full Changelog: vA...vB" compare-link line
(all ten releases on the page that day end with it), which would
otherwise be a prose release's last item.

### Recipes/com-electron-ollama.swift — stable GitHubReleaseRule（一键 `Ollama-darwin.zip`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`0ca0f173`（2026-06-06）、`df241b20`（2026-06-06）。唯一的改写：原文说的是“装着的那份”在漂移，按本目录的机器状态规则改成了针对那台被量的机器的说法。第一句里的 "with no detection source — only a changelog recipe" 说的是这条 rule 接入之前（同一个提交接入），代码里已改写成「没有这条 rule 时」。

Ollama — Electron app distributed via an `auto_updates` Homebrew cask,
which falls through `HomebrewCaskSource` and leaves no `SUFeedURL`, so
the copy installed on the machine measured then drifts (0.24.0 while GitHub ships v0.30.6) with no
detection source — only a changelog recipe. The macOS app is the same
GitHub `/releases/latest`: ollama.com/install.sh and ollama.com/download
both 307→ github releases/latest/download (`Ollama-darwin.zip` / the
`Ollama.dmg` asset).

复测 2026-09-14（03:12 UTC，HEAD 不跟随重定向）：`ollama.com/install.sh` 307 到 `…/releases/latest/download/install.sh`（不是 app 资产）；`ollama.com/download` 回 200 页面；`ollama.com/download/Ollama.dmg` 与 `ollama.com/download/Ollama-darwin.zip` 各自 307 到 `github.com/ollama/ollama/releases/latest/download/` 下的同名资产。代码里那句已按这次复测改写。

Verified end-to-end 2026-06-06: the .app inside
the latest zip self-reports CFBundleShortVersionString 0.30.6 (homogeneous,
no ghost update).

Ollama ships its own updater, but it drifts in practice (seen stuck on
0.24.0 while GitHub was on v0.30.6), so rather than refuse to act we offer
the swap as a fallback when its updater hasn't kept up.
