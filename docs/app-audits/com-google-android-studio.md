# Android Studio

**这不是审计**：family `com-google-android-studio`（`Recipes/com-google-android-studio.swift`）里 Android Studio `com.google.android.studio`（stable 与 Canary/Beta 预览共用这个 bundle id）的覆盖情况没有审过。这份文件只接收从 recipe 注释迁出的历史，登记在索引的「仅迁出历史（未审计）」一节。

## 历史与实测

从 recipe 注释迁出（2026-09-14）。正文逐字，只去掉了行首 `// `；每组标明出处。

### Recipes/com-google-android-studio.swift — Canary / Beta VendorProbe（releases-list JSON）

转引自 recipe 注释，未复测。

With two feature trains open at once, a newer
train's Canary can publish AFTER an older train's RC — 2026-08-27 had
`2026.1.4 RC 2` at item [0] and `2026.2.1 Canary 2`, the actually-newer
build, at item [1] — so plain first-match on the channel set landed on
the older train's RC.

### Recipes/com-google-android-studio.swift — `channelProofs`（Canary / Beta 的 artifact marker）

转引自 recipe 注释，未复测。这句和上一组那句写的是同一次观测，一个写 2026-08-27、一个写 2026-08-26，两处原文照录。两句都由提交 `57e9b6ef`（2026-08-27 11:09 +0800）引入，它的提交信息写的是「on 2026-08-27 2026.1.4 RC 2 (older 261 train) sat …」，与第一组的日期一致；这一组的 2026-08-26 是从它替换掉的旧 `ChannelArtifactProof.swift` 注释里沿用下来的（`7e7fe6fc`，2026-08-26，原话「exactly what the feed served on 2026-08-26」）。所以 08-27 是那次提交时的观测，08-26 是前一天那条旧注释的观测；两天的 feed 是否一样没有记录。

(It is NOT
legitimate merely because the RC was the most recently PUBLISHED item —
the feed is ordered by publish date, not by version, which is what made
the canary recipe land on `2026.1.4 RC 2` over the already-published,
already-newer `2026.2.1 Canary 2` on 2026-08-26; see issue #76 and
`VendorProbeRecipe.entryStartPattern`, which now resolves that correctly.)
