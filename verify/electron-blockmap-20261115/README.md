# Electron ZIP blockmap verification — 2026-11-15

Environment: Apple Silicon macOS VM 1, macOS 27.2 (26B123), VMPal Tools 0.41. The host app and unrelated working copies were not installed over. VM applications and archives were retained.

## Production blockmap update

`flyenv_vm.py` runs the non-shipping `application-test/blockmap-verify` harness, which links the production Core. It scans a prepared copy, calls `VendorInstaller.download` and `apply`, and records the installed version and target ZIP SHA256. Local-stash reuse is disabled for this experiment. The cache is redirected into its own unused `DUO_STATE_DIR`.

- Cold 4.20.1: 165,703,939-byte ZIP + 175,100-byte map = **165,879,039 bytes**; installed 4.20.1 and retained the baseline after success.
- Genuine 4.20.1 → 4.20.2: the **165,572,419-byte** target was reconstructed into `electron-update.zip`; **43,465,419 bytes** including the map were fetched, saving **73.75%**. Installed version: 4.20.2.
- Reconstructed SHA256: `c3fbd63e9b9fb52ad798a98e95eb881bf72b8d1813a9de5cc76b6a69b0131cd2`, equal to the digest GitHub publishes for that exact ZIP.
- After rebasing and adding the total-I/O cap, the final harness repeated a reverse update to prepare 4.20.1 and then the genuine 4.20.1 → 4.20.2 update. The latter again fetched exactly **43,465,419 bytes**, verified the published SHA256 and installed 4.20.2. [Final-code receipts](flyenv-final-results.json).
- Receipts: [flyenv-results.json](flyenv-results.json); publisher metadata: [flyenv-versions.json](flyenv-versions.json). This is one version pair, not a claimed saving for every app or version.

## DMG → ZIP feasibility

For each row, `prepare_vm.py` downloads the currently selected DMG and proposed ZIP, verifies available publisher digests, extracts both, and checks id, short/build versions, Team, ARM64 and strict deep codesign. Then `install_vm.py` prepares an independent copy from the DMG and calls production `VendorInstaller.apply` using the ZIP. The harness checks the installed version, opens that exact path through LaunchServices, records its PID, waits five seconds and confirms it remains alive. Test instances are then terminated. These same-version container swaps exercise install feasibility; they are distinct from FlyEnv’s genuine version upgrade above.

30 of 32 product candidates passed install and startup. Only those 30 change routes. Hyper and T3 Code retain DMG routes. Three additional independent Beta packages passed, while T3 Nightly could not complete startup alongside the existing instance.

| Product | Version | Install and startup | Route in this change |
|---|---|---|---|
| Bdash | 1.35.4 | pass | ZIP |
| BlueBubbles Server | 1.9.12 | pass | ZIP |
| Bruno | 4.3.0 | pass | ZIP |
| Chatbox | 1.24.4 | pass | ZIP |
| Cherry Studio | 2.2.2 | pass | ZIP |
| claude-devtools | 0.5.0 | pass | ZIP |
| draw.io | 32.6.10 | pass | ZIP |
| Ferdium | 7.2.3 | pass | ZIP |
| Granola | 7.786.3 | pass | ZIP |
| Heynote | 2.9.1 | pass | ZIP |
| Hyper | 3.4.1 | install passed; startup not passed | retain DMG |
| Joplin | 3.7.22 | pass | ZIP |
| Kap | 3.6.0 | pass | ZIP |
| Lens | 2026.11.91422-latest | pass | ZIP |
| Logseq | 2.0.2 | pass | ZIP |
| Lunatask | 2.1.29 | pass | ZIP |
| massCode | 6.3.1 | pass | ZIP |
| OpenChamber | 2.7.2 | pass | ZIP |
| Paseo | 0.15.4 | pass | ZIP |
| Plexo | 1.0.0-rc.15 | pass | ZIP |
| Podman Desktop | 1.30.5 | pass | ZIP |
| Porting Kit | 6.7.0 | pass | ZIP |
| Rambox | 3.2.0 | pass | ZIP |
| Requestly | 26.6.29 | pass | ZIP |
| ResponsivelyApp | 1.18.0 | pass | ZIP |
| Signal Desktop | 8.35.0 | pass | ZIP |
| Standard Notes | 3.202.11 | pass | ZIP |
| T3 Code | 0.1.9 | install passed; startup not passed | retain DMG |
| Tad | 0.14.0 | pass | ZIP |
| Termius | 10.4.1 | pass | ZIP |
| TimeScribe | 1.18.0 | pass | ZIP |
| Upscayl | 2.15.0 | pass | ZIP |

### Independent channels

| Package | Version | Install and startup |
|---|---|---|
| T3 Code Nightly | 0.1.10-nightly.20261115.4723 | install passed; existing instance prevented startup |
| ResponsivelyApp Beta | 2.0.0-beta.0 | pass |
| Signal Beta | 8.36.0-beta.1 | pass |
| Termius Beta | 10.4.1 | pass |

Heynote Beta and OpenChamber Preview currently resolve the same stable target ZIP as their stable rules; the fixture suite checks both rules. Detection-only beta rules, old bundle-id distinctions, signing/edition gates, MAS handling and channel matching are preserved. Responsively Beta, Signal Beta and Termius Beta use their own compared and installed packages, not a stable package substituted as evidence.

Every corresponding DMG/ZIP pair has equal ARM64 main-executable CDHash and `app.asar` SHA256 except Signal stable/Beta. Signal DMGs are universal and ZIPs are ARM64. Signal identity/version/Team/codesign, feed ZIP SHA512, production apply and startup all passed. We do not claim byte equivalence: [signal-semantic-comparison.json](signal-semantic-comparison.json) additionally records four x64-only entries and two native modules whose thinned ARM64 bytes still differ.

Hyper 3.4.1 exits with SIGTRAP during V8 initialization; its original DMG bundle also exits with SIGTRAP. The pair has matching ARM64 CDHash/asar, but no runnable result was obtained on this VM, so no route migration is made. [Control](hyper-dmg-launch.json).

T3 Code ordinary 0.1.9 now contains `T3 Code (Beta).app`, while its earlier rule served alpha copies (current main separately added Beta support in #2027). Both ordinary and Nightly ZIP installs passed, but an already running `/Applications/T3 Code (Beta).app` owns the `t3code-v2` single-instance profile. Test copies exited through the app’s lock path; an attempted isolated launch did not establish a separate profile. The existing instance was not stopped and no successful startup was invented. Both routes remain DMG. [Additional attempt](t3-isolated-launch-results.json).

TimeScribe left its known PHP `nightwatch:agent` child after its test instance exited. The child’s executable was verified to be under this verification copy and terminated; unrelated processes were retained.

Raw results: [package-comparison.json](package-comparison.json), [install-results.json](install-results.json), [channel-package-comparison.json](channel-package-comparison.json), [channel-install-results.json](channel-install-results.json). Each row includes the exact target/paths/hashes or PID. VM files remain under `~/duo-verify/electron-blockmap-20261115` and `~/Applications/DuoBlockmap`.

## Storage UI

The unsigned Release app was launched in the VM with a separate `DUO_STATE_DIR`.
A copy of the successful FlyEnv baseline seeded this GUI cache. The Storage page
showed **165.8 MB** for “Update archive cache”, including the 2 GB explanation.
Clicking “Clear Caches” changed the row to **0 bytes** and disabled the button;
the cache directory was empty. The original FlyEnv experiment baseline remained
present. The verification app was stopped and shared resource leases released.

[Before](storage-before.png) · [After](storage-after.png) · [Filesystem receipt](storage-clear.json).

## Local validation

- Core: 7,518 tests across 670 suites passed; the existing schema-drift known
  issue remains marked as known by the repository.
- CLI: 730 tests across 84 suites passed; all application-test harnesses built.
- App: 365 of 365 cases executed and passed on the final rerun. Earlier runs
  hit the pre-existing download-resume timeout and unlinked-process-identity
  tests; neither production path was changed by this work. The final rerun
  passed both. Localization: 1,428 catalog keys reachable.
- `make test-scripts` passed. `make test`'s Core/CLI and script components passed;
  the App component was rerun separately after the transient failures above.
- App and CLI unsigned Release builds passed. The two new strings use existing
  shipped languages; an initially added unsupported Korean entry was removed.

## Safety and coverage limits

- Only ZIP targets with publisher whole-archive SHA512/SHA256 can use differential downloads. Legacy GitHub assets with no digest still use a full ZIP and the original signature gates. A hash computed by this verification script is evidence about the tested artifact, not newly invented publisher metadata.
- Unsupported/malformed maps, missing or changed baseline, invalid range responses and target-hash mismatch fall back to the full route; failed bytes count. Live-transfer cancellation escapes without full fallback. Offline loopback tests exercise these states.
- Cache budget, allocation overhead, claimed-reader preservation, orphan cleanup and symlink rejection are covered by Core tests. The disposable cache is exposed in Storage settings/CLI and reclaimed before backups for disk space.
- Startup survival is not an assertion that every app feature, service, permission prompt, login or user-data migration was tested. The tested host is macOS 27.2; no macOS 15 claim is made beyond the project’s normal build/deployment checks.

## Nightly byte coverage

A Release CLI built from this rebased checkout ran `verify-install --full` with
all 30 migrated product IDs, private copies of the committed identity/baseline
stores, and a matching source stamp. No stale-binary override was used. These
Vendor/GitHub entries are enumerated by the existing registries; no duplicate
generic audited-feed entry was added.

The actual set is exactly the [35 expected installable recipe IDs](nightly-expected-ids.json):
**7,038,088,600 bytes** inspected, **33 ok, 2 expected architecture warnings,
0 failed, 0 unresolved, 0 skipped**. [Original report](nightly-install.json).
The two warnings are Signal stable/Beta changing universal DMG to ARM64 ZIP;
bundle id, signed id and Team remain unchanged. VM package comparison and
production install/startup evidence above justify this deliberate route choice.
The original warning report is preserved; the global identity-drift guard and
baseline counters are not weakened or reset. Signal continuity verification
against the explicitly accepted architecture passed **2 ok, 0 warnings**
([continuity report](nightly-signal-accepted.json)). The committed identity-store
change preserves every key, first-seen field, signing/feed anchor and store
metadata; only the 35 observed entries receive current URL/time stamps, plus
those two explicit architecture changes. `verify/install-baseline.json` is
unchanged. [Acceptance checks](nightly-identity-acceptance.json).

Each affected audit now names its exact monitor IDs and results. Existing
only-detection beta rules remain `duo verify` targets and are not represented as
successful archive inspections. CLI inventory tests ran with the full 730-test
CLI suite.

## Reproduction

Build the non-shipping `blockmap-verify` product from `application-test` and copy it into the VM. Copy `migration-targets.json` plus `prepare_vm.py`, then run the script as the guest user. Run `install_vm.py` against `package-comparison.json`. Its defaults expect the harness at `~/Desktop/blockmap-verify`; use a unique uploaded filename or an explicit copy when updating it, because VMPal’s Desktop send keeps existing names by suffixing the new copy.

For the four extra channel packages, set `TARGETS_FILE=channel-targets.json` / `COMPARISON_FILE=channel-package-comparison.json` for preparation, then `COMPARISON_FILE=channel-package-comparison.json` / `RESULTS_FILE=channel-install-results.json` for installs. `flyenv_vm.py` expects the updated harness at `~/Desktop/blockmap-verify-v2` and refuses to reuse an existing experiment cache.
