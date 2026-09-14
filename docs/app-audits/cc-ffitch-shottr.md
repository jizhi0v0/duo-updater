# Shottr

**这不是审计**：family `cc-ffitch-shottr`（`Recipes/cc-ffitch-shottr.swift`）里 Shottr `cc.ffitch.shottr` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/cc-ffitch-shottr.swift — stable VendorProbe（`shottr.cc/api/version.json`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`599e8dde`（2026-06-04）。

`latestVersion` is the STABLE marketing version (1.9.1), equal to the
app's CFBundleShortVersionString.

复测 2026-09-14（UTC 2026-09-13 23:38–23:50，只读 GET）：`latestVersion` 仍是 `1.9.1`，`betaLatestVersion` 是 `1.9.0`。
