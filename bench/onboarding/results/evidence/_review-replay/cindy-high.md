**Blocking findings: 0**

I checked the following and found no blocking defect:

- **Copies a user might have:** global `com.xd.cindy`, cn `com.xd.cindycn`, `-beta` copies on the same bundle ids, and old releases.
  - Upstream `forge.config.ts` derives the bundle id per region (`com.xd.cindycn / com.xd.cindy`), the same at v0.1.17 and v0.1.104.
  - Every macOS release from v0.1.17 to v0.1.104 ships `cindy-<ver>-darwin-(arm64|x64)-(global|cn).dmg`.
  - Both stable groups are covered by their own anchored asset pattern.
  - A beta copy reports either `0.1.108` or `0.1.108-beta`. `ReleaseChannel.detect` classifies both as `.stable`: step 4 needs `-beta<N>` or `-beta.<N>`, and `beta` is not in `versionTailChannelWords`. So the stable rule serves beta copies and never offers them an older version. The missing beta track is recorded in `CHANNEL_COVERAGE_TODO.md` and in the audit.
- **Tags:**
  - `^v([0-9]+(?:\.[0-9]+)+)$` reads every non-prerelease tag the API lists.
  - It rejects every `vX.Y.Z-beta` tag, so a beta the vendor forgets to flag is still excluded. It accepts two-part tags.
  - `/releases/latest` returns v0.1.104, and the asset digests match the audit.
  - The stray non-prerelease `v1.0.0` has no assets and is the oldest by `created_at`. `/releases/latest` never returns it, and the missing-asset walk would skip it.
- **`recipeID` change:**
  - No other `github:<slug>:<channel>` key is shared by two bundle ids. Every repo with two rules uses one bundle id across two channels, or two channels (Zed / Zed Preview), so no other key changes.
  - No code in the module that builds the rules reads `recipeID`, so there is no static-init cycle.
  - `RecipeHealth.Entry.displayName` still finds the bundle id in the `:`-split id, and `Baseline.prune` uses the same `recipeID`.
- **Changelog window:** In the newest 20 releases, skipping prereleases and the dropped 0.1.97 gives exactly 104, 103, 101, 95, 94, 93, 92, 90, 88. That matches the `maxEntries: 9` claim. Sharing one changelog source URL already has precedent (antigravity), and the cache key handles it.

**Unverified external claims the behavior depends on**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-xd-cindy.swift:35-37`: "`-global` is com.xd.cindy, Team SX9RG894L5; `-cn` is com.xd.cindycn, Team NTC4BJ542G (mounted 0.1.103 and 0.1.104 of both, all notarized, short == build == tag)". Upstream source confirms the bundle ids, but not the Team IDs or that the plist version equals the tag. If a region's Team differs, or changes between releases, the Team-ID gate refuses every one-click install for that region. If the plist version differs from the tag, every copy shows a permanent update.
- `docs/app-audits/com-xd-cindy.md:39`: "0.1.108-beta 的包是否带 `-beta` 后缀没有下载验证" (not verified by download whether the 0.1.108-beta build carries a `-beta` suffix). Plain `0.1.108` and `0.1.108-beta` both detect as `.stable`, and the stable rule serves them. A shape such as `0.1.108-beta.1` would detect as `.beta`, find no rule, and silently get no detection.

**Other unverified external claims**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-xd-cindy.swift:33-34`: the CDN manifest's "installer sha256 for 0.1.104 equals the GitHub cn dmg's digest".
- `docs/app-audits/com-xd-cindy.md:13`: "无 Homebrew cask（2026-10-14 `brew info --cask cindy` 不存在），无 MAS" (no Homebrew cask, no Mac App Store listing).
- `docs/app-audits/com-xd-cindy.md:60`: "两个区域 arm64 真包 `LSMinimumSystemVersion` = `12.0`" (both regions' real arm64 builds have `LSMinimumSystemVersion` 12.0).
- `docs/app-audits/com-xd-cindy.md:112-116`: the claims about the upstream updater's `checkExistingPatch` and the staged-build relaunch path (read from source, not run).
- `CHANNEL_COVERAGE_TODO.md:285-289`: the beta toggle in `update-channel-settings.json` (`enableBeta` / `orgDefaultEnableBeta`), and that the userData directory names per region are still unknown.
- `docs/app-audits/com-xd-cindy.md:88`: the claim that 0.1.97 has 13 prose lines and is dropped by `proseItemCap`.
