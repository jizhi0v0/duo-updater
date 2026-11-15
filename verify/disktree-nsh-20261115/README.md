# Disktree NSH VM verification — 2026-11-15

Passed: native GUI one-click update from 0.1.7 to 0.1.8, followed by a launch
that restored the saved scan directory and displayed its `keep.txt` fixture.

Scope: a new recipe for `com.huacnlee.disktree` / `huacnlee/disktree`.
The separately supported `io.github.tobi.disktree` / `tobi/disktree` is an
independent product. Neither identifier is migrated to the other.

Environment: macOS VM 1, Apple Silicon, macOS 27.2 (26B123), 8 GB RAM.
The host's installed App remains 0.1.7. VM applications and validation packages
are retained; no snapshot rollback is used.

## Artifact and source checks

Real release bundles 0.1.0 and 0.1.8, plus the real 0.1.7 copy used to seed the
VM, all carry `com.huacnlee.disktree`, short/build equal to the release version,
and a valid strict deep ad-hoc signature with the same signed identifier and
no Team ID. The ordinary arm64 tar.gz contains a complete `Disktree.app`.
The upstream release script and install script distinguish this archive from
the separate `-updater.tar.gz`. The recipe selects only the ordinary arm64
archive, excluding updater, Intel, Linux, sidecar and the other product's zip.

The downloaded 0.1.8 archive is 12,659,183 bytes. Its SHA-256 matches GitHub's
published asset digest:
`7b08b6196d23a075115e801b083d295f83b39c366c9b9cc5eba5db9d29b775ef`.
The shipping installer verifies that digest again before the app identity
gates and swap. The VM already had the existing `AllowDigestOnlyInstalls`
setting enabled; stored preferences were not changed.

## Automated and production checks

`swift test --package-path DuoUpdaterCore --force-resolved-versions --filter
'DisktreeNSHRecipeTests|RecipeGoldenTests|DigestOnlyInstallTests|GitHubReleaseRuleTests|GitHubRuleCoverageTests'`
passed: 119 tests in 3 suites. These cover the new independent registration,
tag/asset exclusions, goldens and the existing digest-only trust/opt-in gates.
The preceding golden-record run intentionally failed after adding only this
family's golden; the comparison run passed.

Signed native Release GUI and staged CLI built against the changed Core.
The GUI was built with `DUO_SPARKLE_ALLOWS_AUTOMATIC_UPDATES=NO`, then launched
with process-only automatic-update preference overrides. Its CDHash remained
`61e69cca2813ba3e96acbaabb9428b5482c1d917` through the test; published build
151 did not replace the validation code. Its Developer ID Team is RS59HDH7Y3.

Production `channel-verify --expect stable` exited 0 for all three real copies:

- [0.1.0](channel-first.log): GitHub → UPDATE 0.1.8.
- [0.1.7](channel-old.log): GitHub → UPDATE 0.1.8.
- [0.1.8](channel-new.log): GitHub → up to date.

The same production chain loaded structured GitHub notes for 0.1.8: one
release entry with two items. No separate changelog recipe is needed.

## Native GUI update

- [Previous CLI](before-check.ndjson): real 0.1.7 copy is unknown.
- [Changed CLI](after-rule-check.ndjson): same copy offers GitHub 0.1.8 with
  route `in-place`. CLI check returns 1 when an update is available; the
  channel harness above returns 0 when its expected channel/probe matches.
- The native popover showed 0.1.7 → 0.1.8 and an enabled per-App Update button.
  Clicking that button started the actual installation, rather than Update All.
- Guest 02:29:06: installation started; first-attempt download completed in
  2 seconds with 12,659,183 bytes transferred.
- 02:29:09: in-place swap completed, `elevated=false`, `applied=true`.
- 02:29:10: installation reported complete at 0.1.8, without Installer handoff
  or administrator prompt. This was a stopped-app update (`wasRunning=false`).
- [Installed recheck](installed-check.ndjson): 0.1.8 / up-to-date.
- [Identity receipt](after-signature.txt): short/build 0.1.8 / 0.1.8, same bundle
  ID, signed identifier and ad-hoc signature; strict deep verification passed.
- The App's remembered directory file was byte-identical immediately after
  the swap. Launching 0.1.8 displayed the seeded directory and `keep.txt`.
  Startup rewrote JSON without its previous trailing newline; the saved
  directory value and fixture contents remained unchanged. See the
  [launch/state receipt](launch-and-state.txt).

Native UI: [before](before.png), [after](after.png).
The [native install log](native-install.log) records the download and swap.

## Limits and final state

The old App was stopped during installation. A second update while the old
App is running was not performed. The unchanged digest-only unit suite covers
the settings-off refusal; a second settings-off GUI round was not performed.
No mise metadata update, Intel-copy update or vendor installer-script execution
was tested. These are not represented as completed installation rounds.

The validation GUI and launched Disktree were quit after capture. The VM was
returned to its original suspended state. Its updated NSH App, previous and new
DuoUpdater copies, CLI, seed package and fixture remain available in
`~/duo-verify/disktree-nsh-20261115`.
