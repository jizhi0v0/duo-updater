# AnyDesk

**这不是审计**：family `com-philandro-anydesk`（`Recipes/com-philandro-anydesk.swift`）里 AnyDesk `com.philandro.anydesk` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-philandro-anydesk.swift — stable VendorProbe（`changelog.txt`，`(macOS)` 锚）

转引自 recipe 注释，未复测。整段原文；"the day this was written" 指引入这句话的提交 `84505c3a`（2026-08-16）。代码里去掉了当天的 Windows 版本号，改成「Windows 的版本号更高（历史里有数值）」——那是一句不带日期的现状，所以按（c）复测过，见本节末尾。

Every platform's releases share the file, newest first, as
`22.07.2026 - 9.7.3 (macOS)`. The `(macOS)` anchor is load-bearing and
`selectHighest` must stay off: Windows is on a HIGHER number (9.7.14 the
day this was written), so an unanchored or highest-wins pattern reports
a version this app will never install.

### Recipes/com-philandro-anydesk.swift — stable VendorProbe（一键 `anydesk.dmg`）

转引自 recipe 注释，未复测。

Verified 2026-08-16 on the downloaded dmg: AnyDesk.app 9.7.3,
com.philandro.anydesk, Developer ID `AnyDesk Software GmbH (KHRWM533LU)`
— the same Team as the installed copy — notarized and accepted by
`spctl`.

### Recipes/com-philandro-anydesk.swift — ChangelogRecipe（同一份 `changelog.txt`）

转引自 recipe 注释，未复测。整段原文；"the day this was written" 指引入这段的提交 `e52a7a9d`（2026-09-03）。代码里同样去掉了版本号，并删掉了条目计数那一句。

The `(macOS)` anchor is load-bearing for exactly the reason the probe's
is: Windows runs on a HIGHER number (9.7.15 the day this was written), so
an unanchored pattern lists another platform's releases under this app.
80 macOS entries on the live file (2026-09-03), newest 9.7.3.

复测 2026-09-14（约 07:45 UTC，只读 GET `download.anydesk.com/changelog.txt`，281,736 B）：最新的 macOS 条目是 `22.07.2026 - 9.7.3 (macOS)`，最新的 Windows 条目是 `17.08.2026 - 9.7.15 (Windows)`，Windows 仍然更高；macOS 条目共 80 个。`anydesk.dmg` 的 HEAD：`Last-Modified: Wed, 22 Jul 2026 10:20:43 GMT`。
