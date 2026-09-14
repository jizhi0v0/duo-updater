# Hidden Bar

**这不是审计**：family `com-dwarvesv-minimalbar`（`Recipes/com-dwarvesv-minimalbar.swift`）里 Hidden Bar `com.dwarvesv.minimalbar` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-dwarvesv-minimalbar.swift — stable GitHubReleaseRule（一键 `Hidden-Bar-v<ver>-macos.zip`）

转引自 recipe 注释，未复测。

Hidden Bar — the app DOES carry a Sparkle feed
(`SUFeedURL = api.amore.computer/v1/apps/com.dwarvesv.minimalbar/appcast.xml`),
which is why it looks covered from the outside and isn't: fetched
2026-08-16 the feed answers 200 with a well-formed `<channel>` — title,
link, description — and **no `<item>` at all**.

One-click verified 2026-08-16 by unpacking `Hidden-Bar-v1.10-macos.zip`:
`Hidden Bar.app`, com.dwarvesv.minimalbar, 1.10, universal, Team
W777S7V8TN (Dwarves Foundation Company Limited), notarized Developer ID.

复测 2026-09-14（03:11 UTC，只读 GET）：feed 仍回 HTTP 200，419 字节，`<channel>` 里只有 title / link / description / language，0 个 `<item>`。
