# The Unarchiver

**这不是审计**：family `com-macpaw-site-theunarchiver`（`Recipes/com-macpaw-site-theunarchiver.swift`）里 The Unarchiver `com.macpaw.site.theunarchiver` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-macpaw-site-theunarchiver.swift — stable VendorProbe（DevMate appcast，一键 zip）

转引自 recipe 注释，未复测。

One-click verified 2026-08-09 on the 4.3.9 archive from this same
feed: `The Unarchiver.app` inside, bundle id and Team (S8EX82NJP6)
matching the installed copy, spctl "Notarized Developer ID".

### changelogURL 改为 DevMate 新地址（2026-10-10）

接入前挂的是 `https://updates.devmate.com/releasenotes/147/com.macpaw.site.theunarchiver.html`；2026-10-10
`curl -sIL`（Safari UA）：301 → `https://updateinfo.devmate.com/com.macpaw.site.theunarchiver/147/releasenotes.html`
→ 200，页面标题 "DevMate updater"，正文是 The Unarchiver 4.3.9 的更新说明（与 feed 里的 `shortVersionString="4.3.9"`
一致）。`changelogURL` 改为直接挂终点。没有 ChangelogRecipe 用这个地址。

同日顺带看到：probe 的 feed `https://updates.devmate.com/com.macpaw.site.theunarchiver.xml` 也 301 →
`https://updateinfo.devmate.com/com.macpaw.site.theunarchiver/updates.xml`（200，跟随后仍能读到 4.3.9），
feed 里的 `sparkle:releaseNotesLink` 仍写旧的 updates.devmate.com 地址。这两处本次没改。
