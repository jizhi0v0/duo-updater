# Goose

**这不是审计**：family `com-electron-goose`（`Recipes/com-electron-goose.swift`）里 Goose `com.electron.goose` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-electron-goose.swift — stable GitHubReleaseRule（repo 改名）

转引自 recipe 注释，未复测。

⚠️ Renamed block/goose
-> aaif-goose/goose (measured 2026-08-29). The canonical name
is pinned here on purpose, and it is not cosmetic: GitHub answers the
old slug with a 301 to `/repositories/<id>/…`, and URLSession drops
`Authorization` while following it — the fetch that actually returns
the releases came back `x-ratelimit-limit: 60`, i.e. ANONYMOUS,
whatever token the user configured. Three rules were quietly doing
that.
