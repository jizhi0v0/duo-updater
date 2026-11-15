# T3 Code Beta VM verification — 2026-11-15

Status: passed — real native GUI update from 0.1.6 to 0.1.9 in macOS VM 1.

Scope: add a beta rule to the existing T3 Code recipe family. The installed
`T3 Code (Beta)` 0.1.6 and the public v0.1.9 arm64 DMG share bundle identifier
`com.t3tools.t3code` and developer Team `ARK85ZXQ4Z`. Nightly and preview have
different tag/asset shapes and must not match the beta rule.

Environment: macOS VM 1, Apple Silicon, macOS 27.2 (26B123), 8 GB RAM.
The VM's installed apps and verification packages are retained. No host T3 Code
installation is replaced, no VM snapshot is reverted.

## Before the change

After placing the complete real 0.1.6 bundle in `/Applications/T3 Code (Beta).app`,
the VM's previous CLI returned `status: unknown`, with installed short/build
`0.1.6` / `0.1.6`. Strict deep signature validation passed.

## Automated checks

`swift test --package-path DuoUpdaterCore --force-resolved-versions --filter 't3Code|RecipeGoldenTests'`
passed: 12 tests in 2 suites, including parameterized alpha/beta tag/asset
exclusions, beta name detection, channel proof drift, and recipe goldens.
The golden record run deliberately exited 1 after rewriting only this family;
the following comparison run passed.

Shipping CLI and native GUI built successfully against the changed Core.
The wider GitHub/registry checks passed: 475 tests in 75 suites.
`channel-verify --check com.t3tools.t3code --expect beta` used the real
AppScanner for the installed 0.1.6 copy (its folder is still named Alpha), and
selected beta / GitHub / UPDATE 0.1.9, exit 0. The public 0.1.9 DMG's real app,
checked with path mode and `--expect beta`, returned up-to-date, exit 0, and
loaded structured 0.1.9 GitHub notes. See [older bundle](channel-old.log) and
[newer bundle](channel-new.log).

## GUI validation setup

The first GUI launch was replaced by the published build 151 while automatic self-update was enabled:
its on-disk CDHash differed from the staged test app, and the old unknown
verdict persisted. The test source's app version is beta.9/build 150.
For the final verification artifact only, `SUAllowsAutomaticUpdates` was set
false (the same Info.plist control used by the repository's development-build
setting), and the app was re-signed with the same Developer ID. Its code is
unchanged. `AutomaticUpdates`, `SUAutomaticallyUpdate` and
`SUEnableAutomaticChecks` were overridden only in that launch's argument
domain. Stored update preferences were not changed. Search and Show all were transient view state and were cleared by quitting
the validation app before suspending the VM.

The final artifact's CDHash is `eb4cd0bfea003f6e4de83371e312d859b9c20841`.
The native popover displayed 0.1.6 → 0.1.9 with an enabled Update button;
clicking the app's row opened its GitHub release notes in the workbench.
The per-app Update click completed the actual download and install:

- `01:46:52` guest time: native install start, 0.1.6 → 0.1.9.
- Download: 195,374,334 bytes from GitHub, first attempt, 18 seconds.
- `01:47:23`: in-place swap completed, `elevated=false`, `applied=true`.
- `01:47:24`: installed 0.1.9; recheck returned up-to-date.
- Installed short/build: 0.1.9 / 0.1.9; same bundle ID and Team ARK85ZXQ4Z;
  `codesign --verify --deep --strict` passed.
- The native row displayed v0.1.9 and a checkmark. Launching the updated app
  opened its Welcome/setup screen; no account was configured.
- This was a stopped-app update (`wasRunning=false`). A second update while
  the old app is running was not performed. The host's existing T3 Code stays
  at 0.1.6; no host App installation was replaced.

The GUI workbench loaded this release's GitHub notes. There was no Installer
handoff or administrator prompt during the T3 update.

## Evidence locations

Raw guest evidence and packages: `~/duo-verify/t3-beta-20261115` in the VM.
Repository receipts:

- [Before rule](before-check.ndjson), [after rule](after-check.ndjson),
  [installed recheck](installed-check.ndjson).
- [Installed identity and signature](after-signature.txt).
- [Native install log](native-install.log).
- Native UI [before](before.png), [after](after.png).

[Launch process receipt](launch.txt) records the updated executable running.
The final validation app was quit, and the VM was returned to its original
suspended state after verification. The installed T3 Code, both installation
packages, and the previous DuoUpdater copies remain in the VM.

No unrelated version's evidence is used as approval for this beta rule.
