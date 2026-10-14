# Secretive onboarding review

There's nothing to review: the onboarding was never made. The executor stopped before writing any code. Below is what's missing, plus what the redo has to get right, based on Secretive's repo and its real packages.

Two things I could not check: the Team ID and notarization status of the packages. Unpacking the zips with `ditto -x -k` was refused for me as well, and I didn't try another extractor. Everything else I read straight from the zips without unpacking them.

---

### 1. BLOCKING: no onboarding exists (no recipe, goldens, audit doc or test run)

**Evidence**
- `git rev-parse HEAD` returns `57e6ce0d…`, the same as the base commit.
  - `git log 57e6ce0..HEAD` is empty, and `git status --porcelain --ignored` is clean.
  - `../exec.diff` is 0 bytes and `../exec.head` is the base commit.
- Searching the repo for `secretive` or `maxgoedjen` (Swift, md, json, yml) finds nothing, so Secretive was not already covered by the base.
- The executor's last message (`../exec.jsonl`, `permission_denials`) says it stopped because `ditto -x -k` was denied four times.
  - It wrote no recipe, no goldens and no audit doc.
  - It never ran `make test` and made no commit.

**Fix:** redo the onboarding with zip extraction allowed into `scr/`. The redo needs:
- **A new recipe file**, `Recipes/com-maxgoedjen-Secretive-Host.swift`:
  ```swift
  GitHubReleaseRule(
      bundleID: "com.maxgoedjen.Secretive.Host",
      owner: "maxgoedjen", repo: "secretive",
      versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
      installAssetPattern: #"^Secretive\.zip$"#,
      installerKind: .zip)
  ```
- **The rest of the onboarding:**
  - a line in `AppRecipeIndex.all`
  - re-recorded goldens (`DUO_RECORD_RECIPE_GOLDENS=1 swift test … --filter RecipeGoldenTests`)
  - `docs/app-audits/com-maxgoedjen-Secretive-Host.md` and a line in the README index
  - `make test` with its exit code reported
- **What the evidence already supports:**
  - **Bundle id:** read from each zip's Info.plist.
    - The bundle id is `com.maxgoedjen.Secretive.Host` in v4.0.0, v3.0.4, v2.4.1 and v1.0.3.
    - The nested helper is `com.maxgoedjen.Secretive.SecretAgent`. It lives at `Contents/Library/LoginItems/SecretAgent.app` with `LSUIElement`. It is not a separate install and must not get its own rule.
  - **Version matches the tag:** `release.yml` stamps the version from the tag without its `v`, and the build number as `1.<run_id>`.
    - Measured: v4.0.0 is `4.0.0` / `1.35554366823`.
    - Measured: v3.0.4 is `3.0.4` / `1.19746755792`.
    - So the default (non-build-number) version comparison is right.
  - **One asset per release:** every release from v0.1.1 to v4.0.0 ships exactly one asset, `Secretive.zip`, with `Secretive.app` at the top level.
  - **Architectures:** v3 and v4 are universal (x86_64, arm64, arm64e); v2.4.1 is x86_64 and arm64.
  - **Updater:** the app has no Sparkle framework and no `SUFeedURL`. Its own updater (the `SecretiveUpdater` XPC service) reads `api.github.com/repos/maxgoedjen/secretive/releases`, with no device id in the request. So the rule reads the same build everyone can download by hand: the public release, not a build allocated to one machine.
  - **Build provenance:** `gh attestation verify` passes for both zips. Each was built by `release.yml@refs/tags/v4.0.0` (run 35554366823) and `@refs/tags/v3.0.4` (run 19746755792).
- **Before setting `installAssetPattern`, check signing on the unpacked bundle** (`codesign -dvvv`, `spctl -a -vv`). The source's default Team ID is `Z72PRUAWF6` (`Config.xcconfig`), but that is not checked on a real package yet.
  - This matters more here than usual. Secretive's keys live in the Secure Enclave or keychain under the app's team-scoped access group, so a build signed by a different team would lose access to every key.
  - The zip is notarized but not stapled (`release.yml` runs `notarytool submit` and never staples). Expect `spctl` to need an online check.
- **Packages examined:**
  - `https://github.com/maxgoedjen/secretive/releases/download/v4.0.0/Secretive.zip` (sha256 `877517e2…1ac1fa`)
  - `…/v3.0.4/Secretive.zip` (sha256 `696d0781…d084ba`)
  - `…/v2.4.1/Secretive.zip` and `…/v1.0.3/Secretive.zip`

### 2. BLOCKING (for the redo): each release has its own macOS floor, and a plain GitHub rule can't see it

**Evidence**
- **The floors:** each release states its minimum macOS in the release text. The JSON from `/releases/latest` contains `Minimum macOS Version\r\n15.0.0`.

  | Release | Floor in release text | `LSMinimumSystemVersion` in the zip |
  |---|---|---|
  | v4.0.0 | 15.0.0 | 15.0 |
  | v3.0.4 | 14.0.0 | 14.0 |
  | v2.4.1 | 12.0.0 | 12.0 |
  | v1.0.3 | — | 10.15 |

- **The vendor's updater honours them:** `Updater.evaluate` picks the newest non-prerelease release whose floor is at or below this Mac's macOS (`Brief/Release.swift`, `minimumOSVersion`).
- **duo-updater's GitHub rule doesn't:**
  - `GitHubReleaseRule` has no field for an OS floor.
  - `GitHubReleasesSource` never produces the "vendor says this release isn't for this macOS" refusal (`OSWindowRefusal`).
  - Result: a v3.0.4 install on macOS 14 would show "update to 4.0.0" forever. One-click would download 22.8 MB and then be refused by the installer's OS check (Gate 6 in `VendorInstaller.swift`). The vendor's own app correctly says it is up to date.

**Fix**
- At minimum, the audit doc must record these floors (skill Phase 3⅞) and qualify detection as "✓ on macOS ≥ 15; phantom update on 14".
- Proper fix, either of:
  - Give `GitHubReleaseRule` an optional pattern that reads the floor from the release text, and have the GitHub source produce the refusal. The pattern would be `Minimum macOS Version\s*\n\s*([0-9.]+)`. This is new machinery, so it needs agreement first.
  - Use a `VendorProbeRecipe` on the releases JSON with `minimumSystemVersionPattern`. The downside: unauthenticated `api.github.com` already answered **403** to my curl, so this route loses the GitHub source's token and caching.

### 3. NOTE: nightly and one-off builds look stable to duo-updater, and nobody serves them

**Evidence**
- `nightly.yml` and `oneoff.yml` build the same bundle id with the version set to `0.0.0_nightly-YYYY-MM-DD` / `0.0.0_oneoff-YYYY-MM-DD` (`Info.plist` `CFBundleShortVersionString = $(CI_VERSION)`).
- They are published only as Actions artifacts, which need a GitHub login and expire after 90 days. The latest successful nightly was run 38367930469 on 2026-10-13.
- `ReleaseChannel.detect` only recognises a nightly word after a dash (the `versionTailPattern`). The underscore means these builds are classified `.stable`. So the stable rule will offer 4.0.0 over a nightly, and one-click would swap it for the stable build.
- The vendor's own updater does the same, since it reads `0.0.0_nightly…` as 0.0.0. I have not checked this against a real nightly bundle; that would need an authenticated download plus extraction.

**Fix:** decide this explicitly in the audit, either way:
- Add a Secretive-only rule in `detect` that maps `^0\.0\.0_(nightly|oneoff)-\d{4}-\d{2}-\d{2}$` to `.nightly`, so nobody gets a cross-channel push. Then list nightly as ✗ in `CHANNEL_COVERAGE_TODO.md` (no consumable source).
- Or argue in the audit that matching the vendor's own behaviour is acceptable.

Either way, nightly is ✗ for detection. The prereleases v0.1.1 to v0.5.1 (2020) are pre-1.0 history, not a live beta track. `/releases/latest` already excludes them, so no beta rule is needed.

### 4. NOTE: Homebrew-installed copies take a different route that must be documented

**Evidence**
- The Homebrew cask `secretive` is at 4.0.0, points at the same GitHub URL, and has no `auto_updates`.
- `HomebrewCaskSource` comes before `GitHubReleasesSource` in `SourceStack.swift` (lines 37 vs 41). So for copies Homebrew installed, Homebrew answers and the GitHub rule never runs.
- The cask's `depends_on.macos` is empty in the API JSON. I did not check whether brew itself would refuse 4.0.0 on macOS 14.

**Fix:** the audit's coverage table should show Homebrew ✓ for brew installs and name which source answers for each install type. The macOS-14 behaviour from finding 2 also needs checking on the brew route.

### 5. NOTE: the changelog needs no recipe, but check how it renders

`GitHubReleasesSource` already turns the release text into a structured changelog (`GitHubMarkdownParser.parse`, around line 1370). Secretive's release template has `## Features`, `## Fixes`, `## Minimum macOS Version`, `## Build` and `## Attestation` sections. Check in the re-recorded golden that the Build and Attestation sections don't show up as changelog entries; if they do, note it in the audit.

### 6. NOTE: one-click updates the background agent only on restart

The in-place swap replaces `Secretive.app` together with the bundled `SecretAgent.app` (a login item). duo-updater never relaunches apps, so the running agent that actually serves SSH keeps the old code until it restarts or the user logs in again. The one-click section of the audit should say this.

### 7. NOTE: the brief points at a skill that doesn't exist

The brief requires `.claude/skills/coverage-discovery/SKILL.md`. It isn't in this clone: `.claude/skills` only has app-audit, channel-discovery and fragile-recipe, as the executor also reported. Fix the brief, or put the skill in the clone, before re-running.
