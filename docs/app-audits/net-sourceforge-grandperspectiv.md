# GrandPerspective

**这不是审计**：family `net-sourceforge-grandperspectiv`（`Recipes/net-sourceforge-grandperspectiv.swift`）里 GrandPerspective `net.sourceforge.grandperspectiv` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-sourceforge-grandperspectiv.swift — SourceForge VendorProbe（一键 dmg 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（挂载出来的 app 的 `CFBundleIdentifier` 与 `CFBundleShortVersionString` 与探针所报一致，checked 2026-08-16），dmg 版本 3.7.2 搬到这里。

GrandPerspective — Developer ID (Erwin Bonsma, 3Z75QZGN66), notarized,
stapled ticket; `spctl -a -t exec` accepts the mounted app. One-click
verified 2026-08-16 against the 3.7.2 dmg: `CFBundleIdentifier` and
`CFBundleShortVersionString` on the mounted app match what the probe
reports.
