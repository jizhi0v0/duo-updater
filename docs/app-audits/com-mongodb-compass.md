# MongoDB Compass

**这不是审计**：family `com-mongodb-compass`（`Recipes/com-mongodb-compass.swift`）里 MongoDB Compass `com.mongodb.compass` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-mongodb-compass.swift — stable VendorProbe（download-center JSON，一键 arm64 dmg）

转引自 recipe 注释，未复测。整段原文，代码里留下的是改写过的结论。其中 "(a single current entry in practice)" 迁移时已不成立（见下面的复测），代码里已改写。

MongoDB Compass — the vendor's own download-center JSON
(`s3.amazonaws.com/info-mongodb-com/com-download-center/compass.json`,
status 200, 7814 bytes when checked 2026-08-16). `versions` is
newest-first (a single current entry in practice); `versions[0]._id`
read `1.49.14`, matching BOTH `CFBundleShortVersionString` and
`CFBundleVersion` of the mounted arm64 dmg — no `versionIsBuild` needed.
The same entry's `platform` array carries a `download_link` per
arch/os; the arm64/darwin one is captured directly (no template
needed, unlike GIMP). No checksum is published in this feed.
Installed-bundle identity confirmed 2026-08-16: `com.mongodb.compass`,
notarized Developer ID, Team 4XWMY46275 (MongoDB, Inc.) — `spctl`
accepted as "Notarized Developer ID".

复测 2026-09-14（07:27 UTC，只读 GET 同一 JSON）：200，7,760 B；`versions` 有 6 个条目，依次是 `1.50.0`、`1.50.0-readonly`、`1.50.0-isolated`、`1.50.0-beta.0`、`1.50.0-beta.0-readonly`、`1.50.0-beta.0-isolated`；版本 pattern 和一键 pattern 的首个匹配都落在 `1.50.0` 那一条；全文没有 sha/md5/checksum 字段。当天 7,814 B 与今天 6 个条目的 7,760 B 大小相近，所以原文那天很可能也不止一个条目——这是推断，没有当天的完整响应可以对照（`GroupAProbeRecipeTests` 的 fixture 是裁剪过的）。
