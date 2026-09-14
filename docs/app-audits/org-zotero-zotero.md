# Zotero

**这不是审计**：family `org-zotero-zotero`（`Recipes/org-zotero-zotero.swift`）里 Zotero `org.zotero.zotero` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/org-zotero-zotero.swift — VendorProbe（版本段数不固定）

转引自 recipe 注释，未复测。整段原文；代码里只把句首的 "Verified 2026-08-19 by mounting `Zotero-10.0.dmg`:" 改成 "On the mounted `Zotero-10.0.dmg`, … (checked 2026-08-19)"，读到的值不变（10.0 就是触发这次改动的那个版本）。

The version component count is NOT fixed at three: Zotero 10.0 shipped
as a two-segment string (2026-08-17), which is what broke the original
`[0-9]+\.[0-9]+\.[0-9]+` pattern — the literal is still on the page,
unchanged in shape. Verified 2026-08-19 by mounting
`Zotero-10.0.dmg`: CFBundleShortVersionString and CFBundleVersion are
both exactly `10.0`, so the page string still matches what the installed
bundle self-reports and no phantom update is possible; still
org.zotero.zotero, Team 8LAYR367YV, notarized Developer ID
(`spctl -t install`: accepted). The vendor's own
`download/client/dl?channel=release&platform=mac` redirect resolves to
exactly the templated URL below, so the template shape is unchanged.

### Recipes/org-zotero-zotero.swift — VendorProbe（一键 dmg 的挂载核对）

转引自 recipe 注释，未复测。整段原文；代码里留下的是结论（模板地址上的 dmg 里是 org.zotero.zotero、Team、Notarized Developer ID、universal，`CFBundleShortVersionString` 与页面上的字符串逐字一致，first checked 2026-08-16），当时挂载的那个 dmg 地址与版本号搬到这里；其余原样，重新折行。

One-click originally verified 2026-08-16 by mounting
`download.zotero.org/client/release/9.0.6/Zotero-9.0.6.dmg`:
CFBundleShortVersionString is exactly `9.0.6` (matches the page verbatim,
no scheme mismatch), org.zotero.zotero, Team 8LAYR367YV (Corporation for
Digital Scholarship), notarized Developer ID, universal binary. Zotero
publishes every release at that exact path/filename shape, so the
install URL is templated from the matched version rather than scraped
(there is no link to scrape — the download button is client-rendered).
