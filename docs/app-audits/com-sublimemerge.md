# Sublime Merge

**这不是审计**：family `com-sublimemerge`（`Recipes/com-sublimemerge.swift`）里 Sublime Merge `com.sublimemerge` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-sublimemerge.swift — stable VendorProbe（一键 zip）

转引自 recipe 注释，未复测。

Verified 2026-08-09 on build
2125: `Sublime Merge.app`, Team Z6D26JE4Y4, accepted by spctl.

复测 2026-09-14（约 09:08 UTC，只读 GET）：`www.sublimemerge.com/download` 的 latest 标记是 `Build 2130`（页上日期 14 September 2026），`/updates/stable_update_check` 回 `"latest_version": 2130`。代码里的 "Build 2125" 因此标成了示例。没有下载 2130。
