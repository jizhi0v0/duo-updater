# Xcode

**这不是审计**：family `com-apple-dt-Xcode`（`Recipes/com-apple-dt-Xcode.swift`）里 Xcode `com.apple.dt.Xcode` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-apple-dt-Xcode.swift — ChangelogRecipe（Apple developer release notes JSON）

转引自 recipe 注释，未复测。

and which the pane could only ever embed: the `/documentation/…` URL
serves a 17 KB SPA shell with no note text in it (fetched 2026-09-03).

### Recipes/com-apple-dt-Xcode.swift — ChangelogRecipe（每个版本列车一页）

转引自 recipe 注释，未复测。原句没写日期；日期取自引入这句话的提交：`07d150fc`（2026-09-03）。

One page per release train, and every beta of a train shares its page:
the top of `xcode-27-release-notes` IS beta 6's notes, with each earlier
beta below it under `Updates in Xcode 27 Beta N`.
