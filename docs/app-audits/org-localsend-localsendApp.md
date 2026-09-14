# LocalSend

**这不是审计**：family `org-localsend-localsendApp`（`Recipes/org-localsend-localsendApp.swift`）里 LocalSend `org.localsend.localsendApp` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-localsend-localsendApp.swift — GitHubReleaseRule（资产 pattern 兼作 macOS 发布的闸）

转引自 recipe 注释，未复测。整段原文。末句 "which is genuinely the newest macOS release" 迁移时已不成立（引入它的提交是 `cbed6aa9`，2026-08-20），代码里改写了，见下面的更正；其余原样。

LocalSend — the reason `installAssetPattern` doubles as the macOS-release
gate. Upstream builds Windows/Linux/Android on CI but the dmg by hand
(`support/scripts/compile_mac_dmg.sh`, one maintainer, Developer ID +
notarization), and version numbers are shared across all five platforms
out of a single `pubspec.yaml`. So a mobile-only hotfix advances the tag
without producing a macOS build: v1.18.1 (2026-08-12) ships four `.apk`
files and says so in its own release notes — "Android+iOS only hotfix".
Reading the tag alone reported a 1.18.0 → 1.18.1 update that nobody can
ever install. With the pattern set, resolution walks back to v1.18.0,
which is genuinely the newest macOS release (Homebrew's cask and the
vendor's own download page both agree).

更正 2026-09-14（13:57 UTC，`gh api 'repos/localsend/localsend/releases?per_page=20'`）：新到旧依次是 `v1.18.2`（2026-08-21，资产里有 `LocalSend-1.18.2.dmg`）、`v1.18.1`（2026-08-12，没有 dmg）、`v1.18.0`（2026-08-10，有 `LocalSend-1.18.0.dmg`，另挂着一个 `LocalSend-1.18.2-no-proxy.dmg`，pattern 的 `[0-9.]+\.dmg$` 不收它）。v1.18.0 只在 v1.18.2 发布之前是最新的 macOS 版本。代码里改成：resolution 越过这种 tag，走回最近一个带 dmg 的 release——当时是 v1.18.0。原文括号里 Homebrew cask 与厂商下载页的对照没有复测。
