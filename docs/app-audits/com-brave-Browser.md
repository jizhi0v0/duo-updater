# Brave Browser Beta / Nightly

**这不是审计**：family `com-brave-Browser`（`Recipes/com-brave-Browser.swift`）里 Brave Beta `com.brave.Browser.beta` 与 Brave Nightly `com.brave.Browser.nightly`（stable `com.brave.Browser` 没有 recipe，不在这个 family 里）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-brave-Browser.swift — beta / nightly VendorProbe（arm64 appcast）

转引自 recipe 注释，未复测。

Verified 2026-08-09 on beta 194.104
and nightly 195.47 — Team KL8N8XSYF4, notarized, ids matching.

### Recipes/com-brave-Browser.swift — nightly 的 `transientBodyPattern`（2026-10-16 实测）

2026-10-16 10:16 起 `nightly-arm64/appcast.xml` 回 HTTP 200、465 B：`<?xml …?>`、`<rss>`、`<channel>` 里只有
`title` / `link` / `description` / `language`，**没有任何 `<item>`**；同一时间 `beta-arm64` 有 4 个 `<item>`、`dev-arm64` 有 1 个。
连取三次结果相同。`vendorResolvesInstallPlans` 因此报 `versionPatternNoMatch: no match in 465-byte body`，
PR #1353 的 `test` / `swift` / `release` 三个检查都挂在这一条上（与 PR 改动无关）。
上一次夜扫成功是 `lastGoodAt` 2026-10-15T14:32:54Z（1.99.41.0）。
nightly 每天出包，空 feed 读成厂商故障（`vendorErrorEnvelope`，infra，五天窗口）而不是 track 关闭；
pattern 对当天的空 body 命中、对 beta 的 8,190 B 正常 body 不命中（`BraveNightlyEmptyFeedTests` 钉住两个方向）。
