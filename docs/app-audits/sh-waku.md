# Waku

**这不是审计**：family `sh-waku`（`Recipes/sh-waku.swift`）里 Waku `sh.waku` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/sh-waku.swift — ChangelogRecipe（appcast 的 notes 文件为什么不用）

转引自 recipe 注释，未复测。整段原文；代码里括号里试过的版本范围与状态码改成 "(History has the versions tried)"（原句没写日期，引入它的提交是 `05cdcc76`，2026-08-22）；其余原样，重新折行。

The appcast points `<sparkle:releaseNotesLink>` at a per-version file,
`releases.waku.sh/Waku-<version>.md`, whose body is a bare Markdown
bullet list — no heading, no title, no version in it — so it produced no
entries and the pane fell back to a web view rendering raw `- ` lines.
That file is fetchable for any version by name (0.1.9 … 0.1.12 all 200)
but the site root 404s, so there is NO index: templating it can only ever
show the one version being offered.

复测 2026-09-14（13:59 UTC，只读 GET，不跟随重定向）：`releases.waku.sh/Waku-0.1.12.md` 与 `Waku-0.1.19.md` 都是 200，站点根 `releases.waku.sh/` 是 404。

### Recipes/sh-waku.swift — ChangelogRecipe（改读 GitHub releases）

转引自 recipe 注释，未复测。整段原文；代码里 "seven releases" 这个没写日期的条数（引入它的提交同上）去掉了，"Two of those seven" 改成 "Two of those releases"；其余原样，重新折行。

github.com/egoist/waku carries the same bullets AND the history — seven
releases, each with its published date. Same content, more of it, and it
reuses the decoder every other GitHub-sourced app already goes through.
Two of those seven (v0.1.9, v0.1.7) say only "See CHANGELOG.md for
details."; they still get an entry, via `GitHubMarkdownParser`'s prose
pass, rather than leaving a gap in the version rail.

复测 2026-09-14（13:57 UTC，`gh api 'repos/egoist/waku/releases?per_page=100'`）：14 个 release，`v0.1.4` 到 `v0.1.19`；正文只有 "See CHANGELOG.md for details." 的仍是 `v0.1.9` 与 `v0.1.7` 两条。
