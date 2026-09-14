# Alcove

**这不是审计**：family `com-henrikruscon-Alcove`（`Recipes/com-henrikruscon-Alcove.swift`）里 Alcove `com.henrikruscon.Alcove` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-henrikruscon-Alcove.swift — 公开 VendorProbe（`download.tryalcove.com/latest`，detection-only）

转引自 recipe 注释，未复测。唯一的改写：原文 "matching the installed licensed build" 按本目录的机器状态规则改成了针对那台被量的机器的说法。第一段括号里的 "see GitHubReleasesSource" 迁移时已经指不到东西（`GitHubReleasesSource.swift` 里没有 Alcove）。

The old endpoint (update.tryalcove.com) is GONE — verified 2026-07-29 it no
longer resolves at all (NXDOMAIN), so the previous recipe silently produced
no version and left uncredentialed users with ZERO Alcove detection (the
henrikruscon/alcove-releases GitHub mirror had already been retired for
lagging; see GitHubReleasesSource).

Verified 2026-07-29
it reported exactly 1.7.9 (203), matching the licensed build installed on the machine verified that day
build-for-build — so unlike every mirror before it, this one is IN SYNC with
the licensed channel rather than trailing it.

The public
binaries at download.tryalcove.com/{Alcove.dmg,Alcove.zip} are the *trial*
build and lag this metadata badly: on 2026-07-29 the dmg was 1.7.7 (199)
(`x-alcove-version: 1.7.7`, confirmed by mounting it and reading the
bundle's Info.plist) while /latest already said 1.7.9. Installing it while
claiming 1.7.9 would leave a permanent phantom "update available" that no
install can ever clear. There is no versioned public download path either
(`/1.7.9/Alcove.dmg`, `?version=…` etc. all 404 or serve the same stale
trial build), so users without a license key are sent to the download page
by hand — and Alcove's own updater keeps them current regardless.

复测 2026-09-14（03:13 UTC；DNS 查询、只读 GET、对 dmg/zip 只发 HEAD）：`update.tryalcove.com` 仍是 NXDOMAIN；`/latest` 仍回 `1.7.9`（build 203，`published_at` 2026-06-30）；`?channel=beta` 回 404 `{"message":"No releases available."}`，带 `X-Channel: beta` 头回的仍是同一份 1.7.9；`Alcove.dmg` 与 `Alcove.zip` 的 `x-alcove-version` 都还是 `1.7.7`；`/1.8.0/Alcove.dmg` 回 404。

That page is not what gets parsed:
www.tryalcove.com/changelog is a real page — it server-renders every version
and date, newest 1.7.9 — but it is not scrapable: each entry's body is an
empty placeholder, with the actual features/fixes arrays inlined in a
content-hashed minified route chunk (`/assets/ChangelogPage-<hash>.js`)
whose filename changes on every deploy.

复测 2026-09-14（03:14 UTC，只读 GET，默认 UA 与 Safari UA 各一次）：`www.tryalcove.com/changelog` 与 `tryalcove.com/changelog` 都回 16,916 字节的 HTML，里面没有任何 `x.y.z` 形状的版本号，也没有名为 `ChangelogPage-*.js` 的资源（只有 `index-*.js`、`jsx-runtime-*.js` 等 modulepreload）。代码里这句已改写成「这份 HTML 里没有版本文本」。原句来自 `c2927845`（2026-08-09）。

There is no GitHub rule: the
`henrikruscon/alcove-releases` mirror one used to read LAGS the real release
(2026-06-14: stuck at 1.7.2 while the vendor served 1.7.3).

### Recipes/com-henrikruscon-Alcove.swift — ChangelogRecipe（`api.tryalcove.com/changelog`）

转引自 recipe 注释，未复测。唯一的改写：原文 "matching the installed copy on 2026-08-22" 按本目录的机器状态规则改成了针对那台被量的机器的说法。

Newest is 1.7.9, matching
the copy installed on the machine checked on 2026-08-22.
