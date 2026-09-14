# Beekeeper Studio

**这不是审计**：family `io-beekeeperstudio-desktop`（`Recipes/io-beekeeperstudio-desktop.swift`）里 Beekeeper Studio `io.beekeeperstudio.desktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/io-beekeeperstudio-desktop.swift — GitHubReleaseRule（一键 arm64 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（arm64 dmg 里是公证的 Developer ID 构建、Team 7KK583U8H2、版本等于 tag，checked 2026-06-06），被核对的 5.8.1 搬到这里；末句前半说的是写这条注释的那台机器，代码里删了（机器状态不留在代码里），后半「Team 闸在安装时比对」原样留下。

Best-effort one-click: the `Beekeeper-Studio-<ver>-arm64.dmg` asset wraps
`Beekeeper Studio.app` — verified 2026-06-06 a notarized Developer ID build
(Team 7KK583U8H2, Matthew Rathbone) reporting version 5.8.1 == tag, bundle
id io.beekeeperstudio.desktop. Electron app with its own updater, so a
fallback. The filename carries the version, so the pattern stays version-
agnostic; arm64 (the bare `…-<ver>.dmg` is NOT universal — checked with
`file` on 6.0.1, it is a single x86_64 slice — and a `-mac.zip` also ships,
so the arm64 anchor is what keeps an Intel build off an arm64 Mac). Not
installed on the author's machine — the VendorInstaller Team-gate enforces
the match against whatever is installed.
