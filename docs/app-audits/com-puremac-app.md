# PureMac

**这不是审计**：family `com-puremac-app`（`Recipes/com-puremac-app.swift`）里 PureMac `com.puremac.app` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-puremac-app.swift — stable GitHubReleaseRule（tag 锚）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（这个 repo 会发只带 CLI 压缩包的 `cli-v…` tag，不锚 tag 就会把它读成版本号），2026-08-17 那次的经过搬到这里。"GitHub marks it latest" 迁移时已不成立（见下面的复测），代码里改成了「GitHub 可能把它标成 latest」；`GitHubReleaseRuleTests.pureMacRuleRejectsTheCLIProductTag` 的注释里同一句也改成了过去时。

The tag is anchored because this repo ships a *second product* out of
the same releases: on 2026-08-17 it published `cli-v1.0.0`, carrying
only `puremac-cli-1.0.0.tar.gz`, and GitHub marks it latest. The default
pattern is unanchored, so it read that tag as version 1.0.0 — which,
against an installed 2.9.x, evaluates as "up to date" and hides every
real update. The macOS-asset gate already walks past that release, but
the number it walked past should never have parsed in the first place:
one guard against a silent no-update is not enough.

复测 2026-09-14（约 07:30 UTC，只读 `gh api repos/momenbasel/PureMac/releases/latest` 与 `releases?per_page=10`）：latest 是 `v2.9.8`（2026-08-21）；`cli-v1.0.0`（2026-08-17T22:44:53Z，非 prerelease）仍在列表里，排在 `v2.9.8` 之后，其余九条都是 `v2.9.x` tag。
