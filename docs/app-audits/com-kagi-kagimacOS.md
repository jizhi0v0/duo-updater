# Orion

**这不是审计**：family `com-kagi-kagimacOS`（`Recipes/com-kagi-kagimacOS.swift`）里 Orion `com.kagi.kagimacOS` 的覆盖情况没有审过。这份文件只接收 recipe 的实测历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

### Recipes/com-kagi-kagimacOS.swift — ChangelogRecipe 与 probe 的 `changelogURL`（2026-10-10）

实测 2026-10-10：

- 原 `changelogURL` `https://browser.kagi.com/updates/orion-release-notes.html` → `302 location:
  https://cdn.kagi.com/updates/orion-release-notes.html` → 200。这份 cdn 副本最新只到「Orion 1.1」
  （June 23, 2026），落后于线上 1.1.3。
- 26_0 appcast（`cdn.kagi.com/updates/26_0/appcast.xml`）每个 item 的 `<sparkle:releaseNotesLink>` 都是
  `https://orionbrowser.com/updates/orion-release-notes.html`；该页 200、273,798 字节，最新
  「Orion 1.1.3 (152) ✴︎ Sep 28, 2026」= baseline `vendor:com.kagi.kagimacOS:stable` 的 `1.1.3`。页面另有
  `orion-rc-release-notes.html` 链接（RC 说明已单独成页），但本页较早部分仍留着「Orion RC …」「Orion Beta …」
  条目，recipe 跳过它们。
- 生产解析器（临时测试，`ChangelogService.loadDiagnostic`）：http=200，28 条，最新 `1.1.3`（Sep 28, 2026，
  46 条，小标题「Legacy macOS fixes」「Other improvements and bug fixes」）、`1.1.2`（title `hotfix`，构建 151，
  Aug 18, 2026）、`1.1.2`（构建 150，Aug 17, 2026）。1.0 之前的老格式条目也读出（`0.99.138` …`0.99.127`），其中
  几条页面上就写作「Orion 130.2」「Orion 128.2.1」这类（没有 `0.99.` 前缀），与 `shortVersionString` 方案不同；
  只影响历史条目的显示，最新条目不受影响。
