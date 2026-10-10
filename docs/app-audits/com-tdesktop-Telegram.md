# Telegram Desktop

**这不是审计**：family `com-tdesktop-Telegram`（`Recipes/com-tdesktop-Telegram.swift`）里 Telegram Desktop `com.tdesktop.Telegram` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史和 changelog recipe 的说明，登记在索引的「仅迁出历史（未审计）」一节。

## Changelog

- probe 的 changelogURL 是 `https://telegram.org/blog`（功能博客，不写桌面版本号，不能逐版本解析）。
- ChangelogRecipe ✓：`.gitHubReleases` 读 `api.github.com/repos/telegramdesktop/tdesktop/releases?per_page=40`，
  `maxEntries: 20`，不设 channel（只读非 prerelease）。tag `v7.3.1` 去掉 `v` = 重定向文件名 `td-setup-mac-7.3.1.dmg`
  里的版本。beta 也用纯数字 tag（`v7.2.10`、`v7.2.6`），只靠 GitHub 的 `prerelease` 位区分，stable 过滤把它们挡掉，
  与 probe 从不给 beta 一致。
- probe 的 changelogURL 没改，仍是博客；结构化条目来自 GitHub。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-tdesktop-Telegram.swift — stable VendorProbe（重定向文件名，一键 dmg）

转引自 recipe 注释，未复测。三段整段原文。代码里把第一段和第三段合成了一句结论（dmg 里的 app 两个版本字段都等于文件名里的版本，2026-08-16 与 2026-09-08 各挂载核对过一次）；第二段代码里留下的是结论（改名分两步、先 beta 后 7.2.7 正式线，重定向随正式线一起换，旧路径是退役不是滞后，保留了 2026-09-08 的日期），发布时间线和那几个 URL 搬到这里。

Verified 2026-08-16 by downloading and mounting the 7.0.9 dmg:
`Telegram.app`, com.tdesktop.Telegram, CFBundleShortVersionString AND
CFBundleVersion both exactly `7.0.9` (no build/marketing split to work
around), Team C67CF9S4VU (Telegram FZ-LLC), notarized Developer ID
(`spctl`: source=Notarized Developer ID), universal (x86_64 + arm64).

TWO FILENAME STEMS, and both are load-bearing. Telegram renamed every
artifact it publishes — `tsetup.*` / `tportable.*` → `td-setup-mac-*`,
`td-setup-win-*`, `td-portable-win-*` — and did it in two steps, which
is what says it was planned rather than a slip (release assets, read
2026-09-08): v7.2.5, 2026-09-04T12:53Z, is the last one on the old
names; v7.2.6-beta, eighteen minutes later, is the first on the new
ones; v7.2.7, 2026-09-07, carries them onto the stable line. The
redirect moved with that stable release, from
`td.telegram.org/tmac/tsetup.7.2.5.dmg` to
`td.telegram.org/mac/td-setup-mac-7.2.7.dmg` (`curl -I
https://telegram.org/dl/desktop/mac` → 302 to the latter, 2026-09-08),
and the old path is retired rather than lagging:
`updates.tdesktop.com/tmac/tsetup.7.2.7.dmg` is 404 while the same path
at 7.2.5 is still 200.

Re-verified 2026-09-08 by downloading and mounting the renamed 7.2.7
dmg the redirect now resolves to: same `Telegram.app`,
com.tdesktop.Telegram, CFBundleShortVersionString and CFBundleVersion
both `7.2.7`, Team C67CF9S4VU, `spctl -t install` "Notarized Developer
ID", universal — i.e. only the filename changed, not the artifact's
identity or its version scheme.

复测 2026-09-14（约 08:20 UTC，只读 HEAD `telegram.org/dl/desktop/mac`，不跟重定向）：302，`location: https://td.telegram.org/mac/td-setup-mac-7.2.8.dmg`。没有复查旧路径，也没有下载。

### Changelog recipe 接入，2026-10-10

- `gh api "repos/telegramdesktop/tdesktop/releases?per_page=40"`：最新 `v7.3.1`（2026-10-10，非 prerelease）、`v7.3.0`
  （正文只有 "- Money."）、`v7.2.10`（prerelease）、`v7.2.9` …；40 条里 prerelease 7 条，tag 全是 `vX.Y.Z`。
- 同时 `curl -sSI https://telegram.org/dl/desktop/mac` → `location: https://td.telegram.org/mac/td-setup-mac-7.3.1.dmg`，
  与最新 stable tag 一致（baseline 里的 7.2.9 也在条目里）。
