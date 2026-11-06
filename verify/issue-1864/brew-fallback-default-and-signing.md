# Brew fallback default and signing check — 2026-11-06

Follow-up to `brew-first-fallback.md`. Three changes:

1. **Settings default.** General → Install routing gains "Check other sources for
   Homebrew apps" (off by default, key `BrewFallbackByDefault`). Changing it re-checks
   the brew rows that follow the default.
2. **Per-copy choice in three states.** The row menu's toggle becomes "When Homebrew Has
   No Update": Use Settings / Check Other Sources / Homebrew Only. A per-copy choice beats
   the default both ways; "Homebrew Only" (`BrewFallbackBlockedKeys`) holds when the
   default is on. Existing `BrewFallbackKeys` entries keep meaning "Check Other Sources".
3. **Signing check.** After brew says "up to date" and other sources are allowed:
   - Before download: a source whose rule declares no Team ID (`installTrust` other than
     `.developerID`, today `.publishedDigestOnly`) is skipped for a copy that has a Team
     ID. Gate 3 would refuse it anyway. Later sources are still asked.
   - At install: gate 3 is unchanged. When it refuses a fallback install for its
     signature (`BrewFallbackPolicy.isSigningRefusal`), the app and `duo install` record
     the copy with its Team ID (`BrewFallbackSigningRefusals`). While the copy still has
     that Team ID, later checks keep it on Homebrew without asking other sources. A copy
     reinstalled with another signature is checked again; any row-menu choice clears it.
   - The row menu says why a row stays on Homebrew (`brewFallbackWithheldForSigning`).

Detection cannot compare Team IDs in general: the GitHub API, Sparkle appcasts and vendor
endpoints do not publish them, and the nightly `verify/identities.json` is repository
data, not shipped with the app (and its nightly PRs skip code review).

## Casks whose build differs from the other source

From the Homebrew cask API (`formulae.brew.sh/api/cask.json`, 7,813 casks, 2026-11-06):

- Brew-specific rebuilds: `sourcegit` downloads `ybeapps/homebrew-sourcegit`'s
  `…-signed.dmg`, not upstream `sourcegit-scm/sourcegit`; `sparkplate` similar.
  No GitHub recipe here, so not affected today.
- Same bundle id, other edition: `c0re100-qbittorrent` (Enhanced Edition) and
  `qbittorrent@lt20` share `org.qbittorrent.qBittorrent` with the official
  detection-only recipe. With fallback on, the official version would be shown.
- Brew-specific download endpoints (`warp`, `jdownloader`, `foks`, `liquibase-*`,
  `wolfram-engine`) and vendor CDN mirrors (GitHub Desktop, DBeaver, Mullvad Browser,
  Picard, OpenLogi): likely the same build; not verified per app.

## Automated checks

- Core: `swift test --package-path DuoUpdaterCore --filter 'BrewFallbackSigningTests|ThirdPartyCaskSourceTests|HomebrewCask|SourceStorePolicy|BrewProvenance|HomebrewUnchanged'`
  — 129 tests / 12 suites passed (after the fixes in item 6 below). The full Core suite ran 7,157 tests; the only two
  failures (`readsALiveChild`, `vendorResolvesInstallPlans`) fail the same way on `main`
  in this environment (process ancestry, live vendor network).
- Mutations: making `signingDiffers` always false fails
  `digestOnlyReleaseIsSkippedForASignedBrewCopy` and `aSkippedSourceDoesNotHideALaterOne`;
  disabling the recorded-refusal branch fails
  `recordedRefusalKeepsTheSameCopyOnHomebrewWithoutAsking` (both stamps).
- CLI: `swift test --package-path CLI --scratch-path DuoUpdaterCore/.build` — 692 tests passed.
- App: `make test-app` passed; 1,280 localization keys, all reachable.

## Real-machine result (2026-11-07)

Host: Apple Silicon, macOS 27.2, `make install` Developer ID build of this branch
(Team RS59HDH7Y3), driven through cua-driver 0.39.0 (accessibility actions; one
desktop click to open the menu bar popover). Evidence from the app's own
`com.duoupdater.app` log stream. 19 apps installed by Homebrew casks.

1. Settings → General → Install routing shows "Check other sources for Homebrew apps"
   with its description; the checkbox reflects `BrewFallbackByDefault`.
2. Default off: every brew row answered `Homebrew → … [upToDate]` (WezTerm
   `updateAvailable` from brew, a pre-existing version-format oddity).
3. Popover row menu (WezTerm): "When Homebrew Has No Update" submenu with
   "Use Settings (Homebrew Only)", "Check Other Sources", "Homebrew Only". Choosing
   Check Other Sources wrote `BrewFallbackKeys = [_Applications_WezTerm.app]` and
   re-checked the row at once (brew still had an update, so it stayed on Homebrew).
4. Turning the default on logged `brew fallback default → true: re-checked 18 row(s)`
   (19 minus WezTerm's own choice). Rows moved to Sparkle/GitHub after brew; IINA
   moved to `Sparkle → 1.5.1 [updateAvailable]` while the cask is at 1.5.0.
5. Workbench row menu (IINA, now answered by Sparkle) still offered the submenu, with
   "Use Settings (Check Other Sources)". Choosing Homebrew Only with the default on
   wrote `BrewFallbackBlockedKeys = [_Applications_IINA.app]`, re-checked to
   `Homebrew → 1.5.0 [upToDate]`, and the "Update 1.5.1" button went away. After a
   relaunch with the default still on, IINA was again answered by Homebrew.
6. Two defects found here and fixed in this PR, each with a test that fails without
   the fix: a disk rescan (`carriedForward`) dropped the brew owner of rows another
   source answered, and a row whose downstream check failed (Transmission: brew up
   to date, then Sparkle "Could not connect to the server") lost it too. Before the
   second fix the default's re-check counted 16 rows; after both, toggling off and
   on re-checked 17 rows each way (19 minus the two per-copy choices), Transmission
   included.
7. Choosing "Use Settings" in the popover menu for WezTerm and IINA cleared both
   per-copy keys; IINA followed the default back to Sparkle 1.5.1. Settings were left
   as found: default on, no per-copy choices, no signing refusals.

8. Signing check, with a real app replaced (2026-11-07). IINA 1.5.0 from the
   official cask (Team 67CQ77V27R; Homebrew at 1.5.0, its Sparkle feed at 1.5.1) was
   backed up with `ditto` and re-signed ad-hoc (`codesign --force --deep --sign -`),
   so the installed copy had no Team ID.
   - Detection could not see the difference (no Team ID on the installed side, the
     Sparkle release declares none either way): Check Again → `Homebrew → 1.5.0
     [upToDate]`, then `Sparkle → 1.5.1 [updateAvailable]`, as designed.
   - Update 1.5.1 in the workbench: delta failed on the changed bytes, full archive
     downloaded, then gate 3 refused — "The installed copy has no developer
     signature, but this version is signed by a developer (Team 67CQ77V27R)…". The
     log then read `brew fallback: IINA kept on Homebrew — Sparkle build refused for
     its signature`, and `BrewFallbackSigningRefusals = {_Applications_IINA.app = ""}`.
     IINA on disk was unchanged (1.5.0, ad-hoc).
   - Check Again → `Homebrew → 1.5.0 [upToDate]`, then `other sources withheld — an
     earlier install from one was refused for its signature`; Sparkle was not asked.
     The popover row menu showed "Kept on Homebrew: another source's build is signed
     differently. Choose an option to check again."
   - `brew reinstall --cask iina` restored the original (Team 67CQ77V27R,
     `codesign --verify --deep --strict` passed). Check Again → `Sparkle → 1.5.1
     [updateAvailable]`: the record no longer matched the copy's signature, so it
     expired by itself.
   - Choosing a menu option cleared the record (`BrewFallbackSigningRefusals = {}`).
     Settings left as found: default on, no per-copy choices, no refusals.

9. Review round fixes (2026-11-07, independent review agent), on a fresh `make install`:
   - Toggling the Settings default off and straight back on (300 ms apart, while the
     first re-check was on the network) logged `→ false: re-checked 18 row(s)` and then
     `→ true: re-checked 18 row(s)`. Before the fix the second toggle found every row
     busy and did nothing, leaving them on the "off" answers.
   - IINA with its own "Homebrew Only" choice, in the workbench: its menu read
     "Use Settings (Check Other Sources)"; after turning the default off (IINA itself
     not re-checked, 18 rows) it read "Use Settings (Homebrew Only)". The workbench
     row's equality now compares the menu's inputs.
   - Re-choosing the selected option now clears a refusal recorded since the row's
     last check (`BrewFallbackPolicy.takesChoice`, tested and mutation-checked); the
     Settings help no longer promises an automatic hold for another edition.
   Settings left as found.

Not exercised on this host: the detection-time skip for a `.publishedDigestOnly`
release (no installed brew copy here has such a GitHub rule). It is covered by
`BrewFallbackSigningTests` (mutation-checked).
