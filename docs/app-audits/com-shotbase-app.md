# Shotbase

**这不是审计**：family `com-shotbase-app`（`Recipes/com-shotbase-app.swift`）里 Shotbase `com.shotbase.app` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-shotbase-app.swift — ChangelogRecipe（GitHub releases）

转引自 recipe 注释，未复测。整段原文；代码里去掉了两个没写日期的现状数字（Sparkle 2.9.5、七个条目），它们来自引入这段的提交 `af1ef0fe`（2026-08-27）。

`updates.shotbase.com/appcast.xml` is a stock Sparkle 2.9.5 feed served
off GitHub Pages, and `SparkleAppcastSource` already answers for the app
from it. What it cannot do is render notes: not one of the seven items
carries a `<description>` or a `<sparkle:releaseNotesLink>`, so there is
neither inline text to parse NOR a page to fall back to in a web view —
the pane would simply be blank.

复测 2026-09-14（约 08:06 UTC，只读 GET `updates.shotbase.com/appcast.xml`）：13 个 `<item>`，`<description` 与 `releaseNotesLink` 都出现 0 次，代码里 "not one of its items" 仍成立。Sparkle 版本没有复核。
