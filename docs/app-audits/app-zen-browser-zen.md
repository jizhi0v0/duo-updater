# Zen Browser

**这不是审计**：family `app-zen-browser-zen`（`Recipes/app-zen-browser-zen.swift`）里 Zen Browser `app.zen-browser.zen` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/app-zen-browser-zen.swift — GitHub rule（`zen.macos-universal.dmg`）

转引自 recipe 注释，未复测。唯一的改写：原文说这个 app 在“本地”没有装，按本目录的机器状态规则改成了针对做验证那台机器的说法。

Best-effort one-click: the `zen.macos-universal.dmg` wraps `Zen.app` —
verified 2026-06-06 a notarized Developer ID build (Team 9V5K9TP787, Mauro
Baladés) reporting version 1.20.2b == tag (the trailing `b` kept, matching
CFBundleShortVersionString), bundle id app.zen-browser.zen.

A Firefox fork
with its own updater, so a fallback; not installed on the machine this was verified on, so the Team-gate
enforces the match at install time.
