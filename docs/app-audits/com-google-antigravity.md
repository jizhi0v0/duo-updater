# Antigravity

**这不是审计**：family `com-google-antigravity`（`Recipes/com-google-antigravity.swift`）里 Antigravity `com.google.antigravity` 与 Antigravity IDE `com.google.antigravity-ide`（两个独立 app，不是渠道）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-antigravity.swift — hub VendorProbe（`latest-arm64-mac.yml`，一键 zip + sha512）

转引自 recipe 注释，未复测。

Antigravity — its own electron-builder feed, on the Cloud Run service the
app's updater polls (found by capturing that request, 2026-08-16; there
is no Omaha entry — six plausible appids answered
`error-unknownApplication` while Gemini's returned `ok`).

Verified 2026-08-16 on the mounted artifact: com.google.antigravity,
`CFBundleShortVersionString` 2.8.1, Team EQHXZ8M8AV, notarized, and no
SUFeedURL (so nothing else covers it).

The feed's `sha512` is verifiable: the served zip's Content-Length is
exactly the `size` it states (165926585 on 2026-08-16), so the hash was
taken on the bytes we will actually download — unlike Signal's feed,
where a size delta gave away a hash computed before stapling.

复测 2026-09-14（03:14 UTC，只读 GET manifest + 对 zip 只发 HEAD）：manifest 是 `version: 2.13.0`、`size: 166728118`、`stagingPercentage: 10`；zip 的 `Content-Length` 与 `x-goog-stored-content-length` 都是 166728118。

### Recipes/com-google-antigravity.swift — IDE VendorProbe（`com.google.antigravity-ide`）

转引自 recipe 注释，未复测。第一段原句没写日期；日期取自引入这句话的提交：`7a0110cd`（2026-08-22）。第一段唯一的改写：一处本机状态措辞（这个 app 装没装），按本目录的机器状态规则改成了针对那台被量的机器的说法。第三段迁移时已不成立：页面并非 JS 渲染，那次读的是 gzip 压缩流（见下一组的更正），代码里已改写成指向 IDE 的 `ChangelogRecipe`。

Different
bundle id (`com.google.antigravity-ide`), different version line (2.5.5
against the other's 2.9.1), different binary (Electron — it is a VS Code
fork, the Windsurf/Codeium lineage Google acquired). It was installed on the machine scanned that day but matched no recipe, so its row had no source and no notes at
all. The sibling recipe's own comment had already noticed this product
existed ("the IDE, under `.../antigravity/stable/`") without covering it.

Verified 2026-08-22: the real commit → 204, all-zeroes → 200 with the
manifest.

No `changelogURL`: the hub's points at `antigravity.google/changelog`,
but that page is JS-rendered — 88 KB with zero version strings in the
served HTML — so there is no way to confirm from here that it even
describes the IDE rather than only the hub. Linking it would be a
guess dressed up as coverage.

复测 2026-09-14（03:14 UTC，只读 GET，全零 commit 与 `no_hostname`）：HTTP 200，`productVersion` 与 `name` 都是 `1.107.0`，`version` 是 commit hash，下载 URL 路径是 `…/antigravity/stable/2.5.5-4923483625488384/…`。

### Recipes/com-google-antigravity.swift — hub / IDE ChangelogRecipe（`antigravity.google/changelog`）

转引自 recipe 注释，未复测。第二段原句没写日期；日期取自引入这句话的提交：`e52a7a9d`（2026-09-03）。

That recipe's sibling (the IDE) says the page is "JS-rendered — 88 KB
with zero version strings in the served HTML". That reading was of a
*compressed* body: the server answers gzip even for
`Accept-Encoding: identity`, and the 88/99 KB it counted is the gzip
stream. Decoded it is 401 KB of fully server-rendered Astro markup
carrying every release for all four products (2026-09-03) — which is
also why both apps can be covered from the one page.

18 hub entries and
30 IDE entries on the live page, versions matching what the two probe
recipes detect (hub 2.12.0, IDE 2.5.5).

Antigravity IDE — the `ide` panel of the same page, for the second,
separate app (`com.google.antigravity-ide`, a VS Code fork) whose probe
recipe deliberately carried NO `changelogURL` because it could not
confirm the page described the IDE at all. It does: the page's own tab
strip has an "Antigravity IDE" panel, and its newest entry is 2.5.5 —
the exact version that recipe detects.

复测 2026-09-14（03:14 UTC，只读 GET，`Accept-Encoding: identity`）：服务器仍回 `content-encoding: gzip`，压缩流 109,007 字节，解压 437,159 字节；`data-list-panel` 有 `cli` / `hub` / `ide` / `sdk` 四个；带版本链接的行 hub 20 条（最新 2.13.0）、IDE 30 条（最新 2.5.5）；113 个 `section-row-wrapper` 行里没有一行缺 `data-h3-pin` 标题。

### 2026-10-03 — changelog 迁到 `/docs/changelog`（#922、#822）；hub probe 的灰度方向更正

复测 2026-10-03（只读 GET，浏览器 UA）：

- `https://antigravity.google/changelog` 回 HTTP 200、346 字节的 meta-refresh 壳（`<meta http-equiv="refresh" content="0;url=/docs/changelog">`），不是 3xx，URLSession 不跟，两条 `ChangelogRecipe` 因此 `noEntriesExtracted`（首次在 2026-09-29 的 sweep 里出现）。
- `https://antigravity.google/docs/changelog` 解压后 644,774 字节，仍是服务端渲染的 Astro。结构整个换了：每行是 `<article class="rn-row" id="rel-<产品>-<版本>">`，版本链接文字带 `v` 前缀（`v2.19.1`），日期在 `<time class="rn-date-text">`，标题在 `<h3 class="rn-headline">`，导语在 `div.rn-summary > p`，条目是 `li.rn-item`。旧标记（`section-row-wrapper`、`data-h3-pin`）出现 0 次。
- 行数：hub 27、IDE 30、CLI 61、SDK 18；136 个 `<article>` 与 136 个 `</article>`、136 个 `rn-headline` 一一对应；新 pattern 的 body 里没有一行含下一个 `rel-` id（不越界）。hub 最新 2.19.1（September 30, 2026），IDE 最新 2.5.5（August 13, 2026）。
- 同时 hub probe（不带 `x-user-staging-id`）连续 6 次答 `version: 2.19.1`，IDE probe 答 2.5.5，两边与 changelog 最新条目一致。

#822 的 "reads AHEAD" 不是 probe 卡住。转引 #822 的 2026-09-23 triage：manifest 带 `vary: x-user-staging-id, x-app-version` 和 `cache-control: no-store`；不带 staging header 42/42 次答 2.15.1，而 changelog 已列 2.16.0；带随机 staging id 10/60（另一轮 2/30）拿到 2.16.0，同一个 id 拿到后会一直拿到，即按 id 分桶；2.16.0 的 zip 真实存在（181,548,704 字节）。这和上面 2026-09-14 的复测方向相反：那次不带 header 读到的是 `stagingPercentage: 10` 的 2.13.0，即 probe **领先**于灰度（原注释 "would be offered here before the app itself takes it" 描述的情形）。两种行为都实测过，哪个都不是规律。recipe 注释已改为同时记下两种：落后时 changelog 从第一天就列出新版本，`duo verify` 报 changelog 领先，feed 追上后自愈；领先时已装的 app 可能被提示一个它自己的 feed 还没给它的版本。遇到任何一种，先看实时 feed，再判断是不是灰度。
