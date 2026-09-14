# AweSun（向日葵，Oray）

**这不是审计**：family `com-oray-sunlogin-macclient`（`Recipes/com-oray-sunlogin-macclient.swift`）里 AweSun `com.oray.sunlogin.macclient` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-oray-sunlogin-macclient.swift — ChangelogRecipe（`.sunLoginSoftwareLogs`）

转引自 recipe 注释，未复测。整段原文；代码里只留下「与 VendorProbeRecipe 用同一个 JSON 接口，形状见 `sunLoginSoftwareLogs` 的文档注释」。

AweSun (Oray) — same JSON API as the VendorProbeRecipe (verified live
2026-08-21: GET returns 200/~15KB; the earlier "50 bytes" observation
that prompted a re-check did not reproduce and the endpoint/logic are
both healthy — see `sunLoginSoftwareLogs`'s doc comment for the shape).
