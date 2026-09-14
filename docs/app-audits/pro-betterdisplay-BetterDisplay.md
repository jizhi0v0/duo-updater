# BetterDisplay

**这不是审计**：family `pro-betterdisplay-BetterDisplay`（`Recipes/pro-betterdisplay-BetterDisplay.swift`）里 BetterDisplay `pro.betterdisplay.BetterDisplay` 的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/pro-betterdisplay-BetterDisplay.swift — ChangelogRecipe（appcast 指向的 changelog 页是空壳）

转引自 recipe 注释，未复测。整段原文；代码里 "— fetched 2026-08-27, 1149 bytes, no body content at all" 改成 "with no body content at all (checked 2026-08-27 and 2026-09-14; History has the size)"；其余原样。

The appcast carries no `<description>`; every item points
`<sparkle:releaseNotesLink>` at
`waydabber.github.io/BetterDisplay/changelog.html?tag=<tag>`. That page is
an EMPTY shell — fetched 2026-08-27, 1149 bytes, no body content at all.
Its inline script reads `?tag`, GETs
`api.github.com/repos/waydabber/BetterDummy/releases/tags/<tag>` (the old
repo name, still redirecting) and renders `response.body` with marked.js.
So the web view was rendering GitHub markdown the whole time, minus our
styling and plus the vendor's "Download app for macOS" button image. Going
to the API directly gets the identical text, the version and date headings
the shell never had, and the history a per-tag page cannot hold.

复测 2026-09-14（13:59 UTC，只读 GET `waydabber.github.io/BetterDisplay/changelog.html`，Safari UA）：200，解压后 1,149 B，没有 `<body>` 元素：只有 `<head>` 里的样式与两个脚本引用，和一段读 `?tag` 再 GET `api.github.com/repos/waydabber/BetterDummy/releases/tags/<tag>` 的内联脚本。

### Recipes/pro-betterdisplay-BetterDisplay.swift — ChangelogRecipe（三条 recipe，三条轨）

转引自 recipe 注释，未复测。整段原文（段首的说明句接着缩进的三条要点，要点用代码块围起来）。`.stable` 那条只列 4.x 版本、`.unstable` 那条末句 "show an internal 5.x user the 4.x notes" 迁移时都已不准确，代码里改写了，见下面的更正；其余原样。

THREE recipes, one per track — none of them removable as a duplicate,
even though `.beta` and `.unstable` differ only in `channel`. The tracks
split on GitHub's `prerelease` flag, and BetterDisplay resolves its
channel from two Settings toggles rather than from the bundle id (see
`BetterDisplayChannel`):
```
  * `.stable`   → prerelease: false — v4.3.6, v4.3.5, …
  * `.beta`     ("Receive pre-release updates") → prerelease: true —
                v5.0.3, v5.0.2, … Includes the two `arm64_pre` builds
                (v5.0.0/v5.0.1), which are excluded from what we OFFER
                because they are Apple-silicon-only, but are real history
                and belong in the rail.
  * `.unstable` ("Receive internal pre-release updates") → deliberately
                the same feed as `.beta`. The internal track has no
                per-version notes anywhere: its items link
                `changelog.html?tag=pre`, and that rolling release's body
                is static boilerplate about what internal builds are. The
                pre track is where those builds come from and the closest
                true history for them; without this third registration the
                channel-aware lookup would fall back to `.stable` and show
                an internal 5.x user the 4.x notes.
```

更正 2026-09-14（15:15 UTC，`gh api 'repos/waydabber/BetterDisplay/releases?per_page=40'`）：新到旧前 9 条是 `v4.3.7`（prerelease false，2026-09-11）、`v5.0.5`（false，2026-08-31）、`v5.0.4`（true）、`v5.0.3`（true）、`v5.0.2`（true）、`v4.3.6`（false）、`v5.0.1`（true）、`v5.0.0`（true）、`v4.3.5`（false）；40 条里 `prerelease: false` 的 5.x 只有 `v5.0.5`。所以 `.stable` 的列表现在同时有 4.x 与 5.x，内部轨的用户退回 `.stable` 时看到的也不只是 4.x 的说明。`v5.0.5` 在原句写下（`195c8b44`，2026-08-27）之后才创建；它创建时是否就是 `prerelease: false` 没有记录。代码里 `.stable` 那条改成「例如 v4.3.6、v4.3.5；自 v5.0.5 起也包括 5.x」（checked 2026-09-14），末句改成「给内部轨的用户看 stable 各版本的说明」。

### Recipes/pro-betterdisplay-BetterDisplay.swift — ChangelogRecipe（滚动的 `pre` release 为什么进不了列表）

转引自 recipe 注释，未复测。整段原文；代码里第 40 新的 release 的日期换成「早了好几年」并注明核对日期，`pre` 自己的创建日期（厂商事件的日期）原样；其余原样，重新折行。

That rolling `pre` release cannot leak into either rail as an entry titled
"pre": GitHub orders this endpoint by `created_at`, and `pre` was created
2022-04-06 while the 40th-newest release is 2025-01-03 (both read
2026-08-27). It is far outside a `per_page=40` window and sinks further
with every release the vendor cuts.

复测 2026-09-14（13:57 UTC，`gh api 'repos/waydabber/BetterDisplay/releases?per_page=40'` 与 `…/releases/tags/pre`）：40 条里最新的是 `v4.3.7`（created 2026-09-11），第 40 条是 `v3.3.3`（created 2025-01-22）；`pre` created 2022-04-06。

### Recipes/pro-betterdisplay-BetterDisplay.swift — ChangelogRecipe（`skipSections` 为什么按整个标题匹配）

转引自 recipe 注释，未复测。整段原文；代码里 "18 of the newest 40 releases carry it, and between them they use only TWO distinct texts" 改成 "about half of the newest 40 releases carried it when checked (2026-08-27 and 2026-09-14; History has the counts)"（原句没写日期，引入它的提交是 `a6ac16b1`，2026-08-27），"anywhere in those 40 bodies" 改成 "in the 40 bodies checked"；其余原样，重新折行。

`skipSections` drops the contributor roster. It is not a changelog: 18 of
the newest 40 releases carry it, and between them they use only TWO
distinct texts — the same paragraph repeated down a 15-row rail. The
vendor gives no marker for it (no HTML comment, no `<details>` anywhere in
those 40 bodies), so the heading IS the marker, and they have spelled it
two ways. Both are listed. `### Localization Improvements` (v3.3.4) is
deliberately NOT listed — that one holds real changes, which is why the
match is whole-heading rather than a substring.

复测 2026-09-14（同一次 `per_page=40` 读取）：40 条里 20 条带其中一种名单标题——19 条 "Included Localizations"（`v3.3.4` 同时还有 "Localization Improvements"），1 条 "Localizations included in this release"（`v3.3.3`）；40 条正文里 `<details` 与 `<!--` 都是 0 次。名单正文逐条带贡献者列表，「只有两种不同文本」没有按原来的切法重算。

### Recipes/pro-betterdisplay-BetterDisplay.swift — ChangelogRecipe（三条 recipe，三条轨；`arm64_pre` 的理由，收尾批次）

转引自 recipe 注释，未复测。整段原文，是 #632（`9babda42`）改写之后留在代码里的版本（改写之前的原文见上面「三条 recipe，三条轨」那一组），段首说明句接缩进的三条要点，要点用代码块围起来。`.beta` 那条里 "because they are Apple-silicon-only" 按当前代码不成立，代码里改写了，见下面的更正；其余原样。

THREE recipes, one per track — none of them removable as a duplicate,
even though `.beta` and `.unstable` differ only in `channel`. The tracks
split on GitHub's `prerelease` flag, and BetterDisplay resolves its
channel from two Settings toggles rather than from the bundle id (see
`BetterDisplayChannel`):
```
  * `.stable`   → prerelease: false — e.g. v4.3.6, v4.3.5; since v5.0.5
                that includes 5.x releases as well as 4.x ones (checked
                2026-09-14; History has the tags).
  * `.beta`     ("Receive pre-release updates") → prerelease: true —
                v5.0.3, v5.0.2, … Includes the two `arm64_pre` builds
                (v5.0.0/v5.0.1), which are excluded from what we OFFER
                because they are Apple-silicon-only, but are real history
                and belong in the rail.
  * `.unstable` ("Receive internal pre-release updates") → deliberately
                the same feed as `.beta`. The internal track has no
                per-version notes anywhere: its items link
                `changelog.html?tag=pre`, and that rolling release's body
                is static boilerplate about what internal builds are. The
                pre track is where those builds come from and the closest
                true history for them; without this third registration the
                channel-aware lookup would fall back to `.stable` and show
                an internal-track user the stable releases' notes instead.
```

更正 2026-09-15：DuoUpdater 只发 arm64 构建——`App/project.yml` 项目级 `settings` 里 `ARCHS: arm64`，由 `a8295aee`（2026-08-14）钉死，早于这句话（`195c8b44`，2026-08-27）。所以 DuoUpdater 能运行的每一台 Mac 都能运行 arm64-only 的构建，"Apple-silicon-only" 不是不提供这两个构建的理由，写下时就不是。不提供它们的理由在 `Sources/BetterDisplayChannel.swift` 的文档注释里：这个 tag 的含义没有得到厂商确认，而 5.0.2 起的构建都以更高的版本号进了 `pre`，所以排除它不损失任何可提供的更新。那段注释里同样以 Intel Mac 为前提的两句（签名闸拦不住跨架构错误、`archVerdict` 会把它们提供给跑不了的 Intel Mac）一并改了，`Tests/DuoUpdaterCoreTests/BetterDisplayChannelTests.swift` 的 `arm64PreIsNeverInAnyAllowedSet` 文档注释里的同一说法也改了。代码里这条改成 "(`BetterDisplayChannel` says why)"。
