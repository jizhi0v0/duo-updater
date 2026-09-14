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

转引自 recipe 注释，未复测。第一段原句没写日期；日期取自引入这句话的提交：`7a0110cd`（2026-08-22）。第一段唯一的改写：原文 "It was installed and scanned but matched no recipe" 按本目录的机器状态规则改成了针对那台被量的机器的说法。第三段迁移时已不成立：页面并非 JS 渲染，那次读的是 gzip 压缩流（见下一组的更正），代码里已改写成指向 IDE 的 `ChangelogRecipe`。

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
