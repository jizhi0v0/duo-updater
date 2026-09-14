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

转引自 recipe 注释，未复测。这句和上一组那句写的是同一次观测，一个写 2026-08-27、一个写 2026-08-26，两处原文照录。两句都由同一个提交 `57e9b6ef` 引入（2026-08-27 11:09 +0800，即 UTC 2026-08-27 03:09），`git log` 定不了是哪一天观测的——未解决。

(It is NOT
legitimate merely because the RC was the most recently PUBLISHED item —
the feed is ordered by publish date, not by version, which is what made
the canary recipe land on `2026.1.4 RC 2` over the already-published,
already-newer `2026.2.1 Canary 2` on 2026-08-26; see issue #76 and
`VendorProbeRecipe.entryStartPattern`, which now resolves that correctly.)
