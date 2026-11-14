# Seven recipe alerts — macOS VM verification (2026-11-14)

Product source: `e5ba473d53624bb1b24e0ef06febdd5100b896cb`. The follow-up changes only documentation and these verification artifacts.

Environment: an independent VMPal clone, **Duo recipe seven 27.2**, macOS 27.2 (26B123), Apple Silicon, 4 CPUs / 8 GB, fixed 1440 × 900 display. The existing suspended 27.2 VM was shut down normally and cloned; the other task's running VM was left alone. The unnecessary new OS download was stopped. No VM or snapshot was deleted or reverted.

The signed app and CLI were installed at `/Applications/DuoUpdater.app` and `~/.local/libexec/duo` in the clone. Its previous app, CLI and preferences remain under `~/duo-verify/recipe-broken-seven/prior`. Build identity and source digest: [system-build.log](evidence/system-build.log).

## Installed copies and actual updates

All copies were genuine official downloads installed in `/Applications`, not mock bundles or a temporary HOME.

- Cork: **2.1.1 → 2.1.2**, stopped-app CLI install, `applied: true`.
- Herdr / Sheprd: **20261103.1 → 20261109.1**, stopped-app CLI install and a second running-app install. `duo restart /Applications/Herdr.app` relaunched the new `sheprd` executable at the original install path; Bundle ID and Team remained the same.
- Msty Studio: **2.9.12 → 3.0.0**, the running app's ordinary **Update** button in the installed DuoUpdater, followed by its relaunch. PID changed from 4757 to 6701; the installed version and live check both reported 3.0.0. The current `Vendor` policy uses the ordinary update route for this major-number change; no policy or confirmation rule was bypassed. An earlier click during the Herdr CLI install was refused by the machine-wide install lock; the successful click happened after that install completed.
- MacDown 3000: **3000.0.7 → 3000.0.8**, stopped-app CLI install, `applied: true`. The final check was answered by **Sparkle**, matching version 3000.0.8 / build 1476.
- AppFlowy: **0.14.11 → 0.15.0**, stopped-app CLI install, `applied: true`.
- Simple Comic: **1.11.0 → 1.12.0**, stopped-app CLI install, `applied: true`. The final check was answered by **Sparkle**, matching version 1.12.0 / build 363.
- Inkscape: **1.4.4**, already current. This fix changes notes parsing; no newer version was invented or installed.

Commands and results:

```sh
duo check /Applications/Herdr.app /Applications/MstyStudio.app /Applications/Cork.app \
  '/Applications/MacDown 3000.app' /Applications/AppFlowy.app \
  '/Applications/Simple Comic.app' /Applications/Inkscape.app --all --json
# Before: six updates, Inkscape current; exit 1 as documented.
# After: seven up-to-date rows, no errors or updates; exit 0.

duo install /Applications/Herdr.app /Applications/Cork.app \
  '/Applications/MacDown 3000.app' /Applications/AppFlowy.app \
  '/Applications/Simple Comic.app' --yes --json
# Five installed / applied:true rows; exit 0.

duo install /Applications/Herdr.app --yes --json
duo restart /Applications/Herdr.app
# Running round: installed / applied:true; then “Sheprd restarted”; both exit 0.
```

Raw evidence: [before](evidence/check-before.ndjson), [five installs](evidence/install-stopped.ndjson), [Herdr running install](evidence/herdr-install-running.ndjson), [restart](evidence/herdr-restart.log), [running versions and signatures](evidence/running-update-versions-signatures.log), [new processes](evidence/running-update-processes.log), [final check](evidence/check-final.ndjson).

All seven final bundles passed `codesign --verify --deep --strict`. The three installed Sparkle keys exactly match the accepted maintenance baseline: [versions, signing IDs, Teams and keys](evidence/final-versions-signatures.log). The new MacDown and Simple Comic copies also successfully used their live Sparkle feeds.

## Official installer identity checks

`duo verify-install --full --identities <copy of this PR's identities.json>` used the production inspection path. The first run verified Herdr but hit TLS errors or timeouts for six other targets. Retrying those six with `--max-concurrency 1` yielded **6 ok, 0 warnings, 0 failures, 0 unresolved**: all seven installers were verified across the two runs, including all three newly accepted keys.

The original failures are retained: [first run](evidence/install-verify.log), [report](evidence/install-verify.json); [successful retry](evidence/install-verify-retry.log), [report](evidence/install-verify-retry.json). No TLS check was disabled.

## Native release notes

The production `channel-verify` harness read the real installed bundles; the installed app's workbench rendered the same notes:

- Cork **2.1.2 / 2026-11-02**, **four items** from the original announcement, excluding replies: [harness](evidence/Cork-channel-before.log), [native UI](cork-native.png).
- Inkscape **1.4.4**, **90 items** from the intended changes section: [successful harness retry](evidence/Inkscape-channel-retry.log), [native UI](inkscape-native.png).
- Msty **3.0.0**, **15 items** with Highlights / Enhancements / Fixes; 34 stable history entries: [harness](evidence/MstyStudio-channel-before.log), [native UI](msty-native.png).

The broad VM recipe sweep returned 12 ok, 0 warnings, 0 broken and one transient Inkscape probe timeout. Its immediate installed-bundle harness retry successfully resolved 1.4.4 and parsed the 90 notes; the final seven-app CLI check also succeeded. Both the transient and recovery are retained: [sweep](evidence/verify-final.log), [report](evidence/verify-final.json), [first harness attempt](evidence/Inkscape-channel-before.log), [successful retry](evidence/Inkscape-channel-retry.log).

## Final VM state and limits

All seven target apps remain installed at their latest versions and are **not running**: [process check](evidence/processes-final.log). The Herdr core processes started by this test were terminated normally after quitting its GUI. Old official archives and the prior DuoUpdater build remain in the verification directory; the VM was not rolled back.

This verifies the seven requested alerts on these stable installed copies. It does not claim new validation of Cork's old bundle-ID migration, prerelease tracks, Simple Comic's App Store edition, or a vendor-staged update older than the offered release. No host app or CLI installation was replaced.
