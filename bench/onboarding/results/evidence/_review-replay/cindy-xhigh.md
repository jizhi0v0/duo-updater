**Blocking findings: 0**

What I checked. First, the groups of installed copies, before reading the rules:

- Global stable (`com.xd.cindy`) and cn stable (`com.xd.cindycn`), 0.1.17 to 0.1.104. Each is covered by its own rule.
  - The GitHub API shows `cindy-<ver>-darwin-(arm64|x64)-(global|cn).dmg` on every stable tag back to v0.1.17. The one exception is v0.1.52, which has only the arm64-global dmg; the cn rule's list fallback walks back past it.
  - Upstream `forge.config.ts` already derives the region bundle id (`com.xd.cindycn` / `com.xd.cindy`) at v0.1.17, so no older copy carries a renamed id.
- x64 copies on Apple Silicon. `HostArch` lists `x64` as an Intel token, and the host's arm64 dmg is preferred.
- Beta copies on the same bundle ids. This gap is recorded (audit ○, open TODO entry).
  - Every `-beta` tag in the API listing has `prerelease: true`.
  - If an unflagged beta ever became `/releases/latest`, `^v([0-9]+(?:\.[0-9]+)+)$` rejects it: that cycle gets no detection, not a wrong version.
  - An unnumbered `0.1.108-beta` reads as `.stable` in `ReleaseChannel.detect`. `VersionComparator` still ranks it above 0.1.104, so it is never offered a lower stable.
- Canary copies. Recorded ✗, with a reason.
- The stray `v1.0.0` release (non-prerelease, 0 assets, 2026-07-25) matches the tag pattern. It is neither `/releases/latest` (verified: v0.1.104) nor inside the 20-row fallback or changelog page, so nothing reads it.

Then the code:

- **`recipeID`**: Cindy is the only pair among all 120 registry rules that shares a slug and a channel across bundle ids. Every other shared-slug pair (Zed, UTM, GitHub Desktop, CotEditor, Yaak, WhatCable, tinycast, vorssaint, trycua, t3code) differs by channel, so no other key changes. Nothing parses the `github:` key's segments, and the baseline live set and the prune both come from the registry.
- **Shared `/releases/latest` URL**: the validator cache stores raw bodies, and each rule re-settles them with its own asset pattern.
- **Changelog**:
  - The cache key goes through `recipeID`, so the two regions get distinct slots.
  - The decoder drops prereleases, and `maxEntries` counts only parsed entries, matching the 9-entry window of 0.1.104 to 0.1.88 (0.1.97 has 12 `###` sections).
  - New releases only push that window forward.

**Unverified external claims the behavior depends on**

- `docs/app-audits/com-xd-cindy.md:56-57`: "release 的创建顺序偶有颠倒（0.1.85 晚于 0.1.86 发布），`/releases/latest` 不受影响".
  - The API shows the inversion is in `created_at`, not `published_at`. v0.1.86 was created 2026-09-15T12:06:12Z and published 2026-09-18T07:31:31Z; v0.1.85 was created 2026-09-16T15:51:19Z and published 2026-09-17T03:45:20Z.
  - If GitHub picks `/releases/latest` by `created_at` (the legacy ordering) rather than by the newest published release marked latest, both rules have a stale window. A stable built from an older commit would stay hidden behind the previous stable until the next release, and those rows would read "up to date".
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-xd-cindy.swift:35-37` and `docs/app-audits/com-xd-cindy.md:6`: "`-global` is com.xd.cindy, Team SX9RG894L5; `-cn` is com.xd.cindycn, Team NTC4BJ542G (mounted 0.1.103 and 0.1.104 of both, all notarized…)". One-click relies on each region's Team staying the same across versions. If an older copy was signed by a different Team, the Team-ID gate refuses its install.
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-xd-cindy.swift:42` and `docs/app-audits/com-xd-cindy.md:39`: beta "不改版本串" and "nothing in the bundle says which" (the `0.1.108-beta` package was not downloaded). How the stable rule treats beta copies depends on the beta build's real `CFBundleShortVersionString`.
- `docs/app-audits/com-xd-cindy.md:112-116`: the upstream updater's `checkExistingPatch` discards a staged build that is not newer than the current bundle. If this is false, or if the noted old-process relaunch path happens, Cindy's own updater can roll a duo-installed version back. The audit marks this untested.

**Other unverified external claims**

- `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-xd-cindy.swift:33-34` and `docs/app-audits/com-xd-cindy.md:47-49`: the CDN manifest's 0.1.104 `installer.sha256` "equals the GitHub cn dmg's digest". The GitHub side is confirmed: the API digest is `sha256:8f0704e3…6331`. The CDN side is not checked.
- `docs/app-audits/com-xd-cindy.md:11`: "无 `SUFeedURL`，无 `app-update.yml`".
- `docs/app-audits/com-xd-cindy.md:13`: "无 Homebrew cask（… `brew info --cask cindy` 不存在），无 MAS".
- `docs/app-audits/com-xd-cindy.md:60`: `LSMinimumSystemVersion` = `12.0` on the 0.1.103 and 0.1.104 builds.
- `docs/app-audits/com-xd-cindy.md:134-135`: codesign and spctl results ("Notarized Developer ID").
- `docs/app-audits/com-xd-cindy.md:68`: the hotfix zip size of 278,776,768 bytes from the cn manifest.
- `CHANNEL_COVERAGE_TODO.md:476`: canary "只有 app 自己的 CDN `manifest-<platform>-canary.json`，无公开构件".
- PR description: the `channel-verify` results (UPDATE → 0.1.104 from 0.1.103, up to date on 0.1.104, each region's own dmg) and the changelog-pane output.
