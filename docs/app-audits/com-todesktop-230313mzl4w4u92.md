# Cursor

**这不是审计**：family `com-todesktop-230313mzl4w4u92`（`Recipes/com-todesktop-230313mzl4w4u92.swift`）里 Cursor `com.todesktop.230313mzl4w4u92` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-todesktop-230313mzl4w4u92.swift — ChangelogRecipe（真实响应里的两个坑）

转引自 recipe 注释，未复测。整段原文；代码里只把「26KB」这个实测大小换成了「the page chrome」。原句没写日期，引入它的提交是 `4a6cc00a`（2026-08-14）。

Two things the real response teaches that the markup doesn't:
```
 • The document contains its whole `<main>` TWICE (it has two `</html>`
   tags — a Next.js streaming artifact), so every post matches twice.
   `ChangelogExtractor` de-duplicates on version+title; without that the
   pane listed each release two rows apart.
 • The last post has no following post to stop at, so `<footer` closes the
   body — otherwise it swallowed 26KB of page chrome as "items".
```
`www.cursor.com` 308s to the apex domain; followed once here rather than
on every fetch.
