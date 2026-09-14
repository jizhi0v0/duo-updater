# Headlamp

**这不是审计**：family `com-microsoft-Headlamp`（`Recipes/com-microsoft-Headlamp.swift`）里 Headlamp `com.microsoft.Headlamp` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-microsoft-Headlamp.swift — ChangelogRecipe（GitHub releases JSON，正则读取）

转引自 recipe 注释，未复测。前三段原句没写日期；日期取自引入这些句子的提交：`e52a7a9d`（2026-09-03）、`63a92707`（2026-09-03）。最后一段的末句迁移时已不成立：`Recipes/net-imput-helium.swift` 也是用正则读 GitHub API JSON 的，代码里已改写。

Headlamp — its GitHub releases, read with regexes rather than through
`structuredFormat: .gitHubReleases`, because that decoder deliberately
refuses this body: `GitHubMarkdownParser` bails on a Markdown TABLE, and
Headlamp writes its whole changelog as tables (142 table rows in v0.45.0
— its own doc comment names this app as the reason the guard exists).

The bullet pattern behind it is not redundancy for its own sake: the
table layout starts at 0.44.0, and the older releases still on the page
(0.30.0 … 0.43.0) are plain bullet lists.

That bullet is `[-*]`, both markers, because this vendor changed marker
mid-history: 0.36.0 and newer write `- `, 0.38.0 and 0.30.0 … 0.35.0
write `* `. A `-`-only pattern does not fail on those — it yields an
entry with no items, which `ChangelogExtractor` drops, so 8 of the 18
releases simply vanished from the rail while the recipe still reported
success. Measured against the live endpoint, not inferred.

18 entries on the live endpoint (2026-09-03), newest 0.45.0.

`\s*` around every colon: this endpoint serves the SAME document compact
(`"tag_name":"v0.45.0"`) and pretty-printed (`"tag_name": "v0.45.0"`),
and which one you get is not the recipe's to choose — it varied by
request on 2026-09-03. A pattern written against either form alone reads
as a clean "the vendor restyled their page" failure against the other.
The registry's other GitHub-API recipes never met this because they go
through `Decodable`, which cannot see whitespace at all.

复测 2026-09-14（03:15 UTC，只读 GET `repos/kubernetes-sigs/headlamp/releases?per_page=100`）：最新 app tag 仍是 `v0.45.0`；100 条里 0 个 prerelease；`v0.38.0` 与 `v0.35.0` 的正文用 `* ` 条目（17、57 条，0 个 `- `），`v0.36.0`、`v0.37.0`、`v0.39.0` 主要用 `- `。

### Recipes/com-microsoft-Headlamp.swift — stable GitHubReleaseRule（repo 改名）

转引自 recipe 注释，未复测。

⚠️ Renamed headlamp-k8s/headlamp
-> kubernetes-sigs/headlamp (measured 2026-08-29). The canonical name
is pinned here on purpose, and it is not cosmetic: GitHub answers the
old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
`Authorization` while following it — the fetch that actually returns
the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
whatever token the user configured. Three rules were quietly doing
that.
