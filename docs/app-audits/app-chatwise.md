# ChatWise

**这不是审计**：family `app-chatwise`（`Recipes/app-chatwise.swift`）里 ChatWise `app.chatwise` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/app-chatwise.swift — ChangelogRecipe（`releases.chatwise.app/releases`）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`df9f943d`（2026-08-22）。

ChatWise — the public /changelog page is a SvelteKit shell (a ~4 KB
document with no notes in it) that hydrates from the releases JSON
endpoint, so we read that endpoint directly.
