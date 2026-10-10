# Shottr

**这不是审计**：family `cc-ffitch-shottr`（`Recipes/cc-ffitch-shottr.swift`）里 Shottr `cc.ffitch.shottr` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/cc-ffitch-shottr.swift — stable VendorProbe（`shottr.cc/api/version.json`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`599e8dde`（2026-06-04）。

`latestVersion` is the STABLE marketing version (1.9.1), equal to the
app's CFBundleShortVersionString.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`latestVersion` 仍是 `1.9.1`，`betaLatestVersion` 是 `1.9.0`。

### Recipes/cc-ffitch-shottr.swift — ChangelogRecipe（`shottr.cc/newversion.html`）

实测 2026-10-10（只读 GET，curl 与生产解析器 `ChangelogService.loadDiagnostic` 各一次）：200，10877 字节，
16 个条目，`1.9.3`（页首 `<h1>Shottr v1.9.3 is out!</h1>`）到 `1.5.1`，页面没有任何日期。同日
`verify/baseline.json` 的 `vendor:cc.ffitch.shottr:stable` 为 `1.9.3`，与最新条目一致。`1.7.1` 一段没有
列表，只有两个 `<p>`（第一个是加粗的 `Changes`），所以条目回退读 `<p>`。`1.7.2` 段里留着被注释掉的
`<!--<h1>Shottr v1.7.2 is out!</h1>`，不能算成第二条。页面里的 "Beta" 两处都是正文（macOS Ventura Beta、
视频路径），没有 beta 条目。
