# XQuartz

**这不是审计**：family `org-xquartz-X11`（`Recipes/org-xquartz-X11.swift`）里 XQuartz `org.xquartz.X11` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-xquartz-X11.swift — GitHubReleaseRule（pkg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（`pkgutil --check-signature` 的签名者、notarized 与 timestamped，`Distribution` 声明的 id 与装机 bundle 相同，checked 2026-08-16），pkg 的版本号与字节数搬到这里；其余原样，重新折行。

The installed app lives in `/Applications/Utilities`, which the scanner
covers. Verified 2026-08-16 against the real 2.8.6 pkg (122,035,963 B):
`pkgutil --check-signature` reports "Developer ID Installer: Apple Inc. -
XQuartz (NA574AWV7E)", notarized and timestamped, and its `Distribution`
declares `org.xquartz.X11` at version 2.8.6 — the same id the installed
bundle reports.
