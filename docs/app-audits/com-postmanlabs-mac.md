# Postman

**这不是审计**：family `com-postmanlabs-mac`（`Recipes/com-postmanlabs-mac.swift`）里 Postman `com.postmanlabs.mac` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-postmanlabs-mac.swift — ChangelogRecipe（`.postmanReleaseNotes`）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（旧正则会在转义引号处把一行截断，而且不报错），计数搬到这里。计数原句没写日期，引入它的提交是 `01ab5b77`（2026-08-22）。

Postman — CDN-hosted JSON array under the "notes" key (newest-first).
Each element has "version", "content" (Markdown; `\r\n` line separators in
recent entries, bare `\n` in older ones) and "createdAt" (ISO-8601).
Structured decode (StructuredChangelogDecoder.decodePostman): split
`content` on real newlines, strip the `#### ` feature-heading prefix
(keeping the heading text as an item), skip `##`/`###` section headers and
the "August 21, 2026"-style date line, drop lines under 10 chars, keep
everything else (including markdown syntax like `**bold**` / `[t](url)`
verbatim — nothing downstream strips it for this recipe). This replaces a
regex itemPattern that only recognized the escaped `\\r\\n` form and, on
top of that, truncated any line containing an escaped quote at the
backslash (`[^\\]{10,}` stops there) — confirmed against the live feed:
2 of the 30 most recent releases had a mid-sentence truncation the old
path produced silently.
