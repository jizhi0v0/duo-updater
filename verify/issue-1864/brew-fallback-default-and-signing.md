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
  — 111 tests / 11 suites passed. The full Core suite ran 7,157 tests; the only two
  failures (`readsALiveChild`, `vendorResolvesInstallPlans`) fail the same way on `main`
  in this environment (process ancestry, live vendor network).
- Mutations: making `signingDiffers` always false fails
  `digestOnlyReleaseIsSkippedForASignedBrewCopy` and `aSkippedSourceDoesNotHideALaterOne`;
  disabling the recorded-refusal branch fails
  `recordedRefusalKeepsTheSameCopyOnHomebrewWithoutAsking` (both stamps).
- CLI: `swift test --package-path CLI --scratch-path DuoUpdaterCore/.build` — 692 tests passed.
- App: `make test-app` passed; 1,280 localization keys, all reachable.

## Not yet validated

No real-machine run yet: Settings row, the three-state row menu in the popover and the
workbench, re-check on a default change, and a refused fallback install keeping the
row on Homebrew.
