# Telegram Desktop

**这不是审计**：family `com-tdesktop-Telegram`（`Recipes/com-tdesktop-Telegram.swift`）里 Telegram Desktop `com.tdesktop.Telegram` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

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
