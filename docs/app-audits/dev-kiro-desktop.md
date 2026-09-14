# Kiro

**这不是审计**：family `dev-kiro-desktop`（`Recipes/dev-kiro-desktop.swift`）里 Kiro `dev.kiro.desktop` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/dev-kiro-desktop.swift — VendorProbe（Squirrel.Mac 元数据）

转引自 recipe 注释，未复测。整段原文；代码里只把「323-byte」换成了「small」。原句写于提交 `61ed6c74`（2026-08-16）。

Kiro — the Squirrel.Mac metadata its own updater reads (found by
capturing that request, 2026-08-16). One 323-byte JSON, already scoped
to this architecture by its filename, stating `currentRelease` and the
exact artifact for it.

### Recipes/dev-kiro-desktop.swift — VendorProbe（为什么不读下载页）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（下载页把两个架构的链接放在同一版本下、版本文字在 hash 命名的类里；manifest 形状在这台主机上回 403，when checked 2026-08-16——这个日期是提交 `61ed6c74` 的日期，原句没写），「which was the first thing that worked」「which is why the page was used at all」这段经过搬到这里。

Preferred over the download page, which was the first thing that worked:
that page carries both architectures' links under the same version and
its version text sits in hash-named utility classes, so reading it meant
naming the architecture in a regex and hoping the markup held. Guessing
at a manifest had failed earlier — every `latest-mac.yml` / `latest.yml`
/ `/latest` shape on this host answers 403 — which is why the page was
used at all.

### Recipes/dev-kiro-desktop.swift — VendorProbe（一键 zip 的核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（zip 里是 Kiro.app、dev.kiro.desktop、Developer ID `AMZN Mobile LLC (94KV3E626L)`、公证且被 spctl 接受，checked 2026-08-16；闸在安装时拿它比装着那份的 Team），版本 1.0.309 搬到这里。末句前半说的是写这条注释的那台机器没装它（机器状态不留在代码里），代码里删了；后半「闸在安装时比对」留下了。

Verified 2026-08-16 on the downloaded artifact: Kiro.app 1.0.309,
dev.kiro.desktop, Developer ID `AMZN Mobile LLC (94KV3E626L)`, notarized
and accepted by `spctl`. Not installed on the machine this was written
on, so the comparison against an installed copy's Team is unverified —
the gate performs it at install time regardless.

### Recipes/dev-kiro-desktop.swift — ChangelogRecipe（带版本号与不带版本号的标题）

转引自 recipe 注释，未复测。整段原文；代码里把「8 of the 15 IDE entries in today's feed」改成了「about half the IDE entries」。原句没写日期，引入它的提交是 `a16c5be1`（2026-08-22）。

Only some titles carry a version ("IDE 1.0.337: Agent Focus, …"); the
rest are titled but unversioned ("IDE: Permission Improvements …"). Both
shapes are kept — `Changelog.Entry` accepts a title without a version,
and dropping the unversioned ones would silently lose 8 of the 15 IDE
entries in today's feed. The `IDE` prefix is consumed either way so the
rail doesn't repeat it on every row.
