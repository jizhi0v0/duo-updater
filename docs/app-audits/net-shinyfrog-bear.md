# Bear

**这不是审计**：family `net-shinyfrog-bear`（`Recipes/net-shinyfrog-bear.swift`）里 Bear `net.shinyfrog.bear` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/net-shinyfrog-bear.swift — `MacAppStoreProbeCase`（`mac-software`）

转引自 recipe 注释，未复测。整段原文；末句（2026-09-04 的上线核对）整句搬到这里，其余原样留在代码里，与 [com-culturedcode-ThingsMac.md](com-culturedcode-ThingsMac.md) 的同形处理一致。

Bear — Mac App Store–exclusive markdown notes app, continuously
maintained since 2016, no reason to expect delisting. Native Mac
listing (`mac-software`): exercises `nativeMacVersion` and the
`trackViewUrl` zero-redirect path A2 added. Confirmed live
2026-09-04: lookup kind mac-software, trackViewUrl → 0 redirects,
`?platform=mac` page carries a parseable `mostRecentVersion` shelf.
