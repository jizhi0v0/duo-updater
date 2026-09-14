# IntelliJ IDEA

**这不是审计**：family `com-jetbrains-intellij`（`Recipes/com-jetbrains-intellij.swift`）里 IntelliJ IDEA `com.jetbrains.intellij` 与 IntelliJ IDEA EAP `com.jetbrains.intellij-EAP` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-jetbrains-intellij.swift — stable VendorProbe（`code=IIU&type=release`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`2fcbc0a2`（2026-08-08）。

It was pinned to exactly three (`YYYY.x.y`) and JetBrains then
shipped a fourth — `"version": "2026.2.0.1"` — so the anchored pattern
stopped matching and the row silently fell to "unknown" with the probe
reporting "resolved no version".
