# Official auto_updates rollback and retained fixes

Date: 2026-11-06. VMPal macOS 27.2 (26B123).

Following [Handy's channel verification](handy-channel-verification.md), restored
HomebrewCaskSource's official auto_updates fallthrough. The installed-path source
is again ThirdPartyCaskSource and ignores homebrew/cask receipts. Removed the
experimental official ownership routing and its installation-time version gate.
The official catalog and existing provenance tests retain their pre-experiment behavior.

Retained the third-party receipt/path ownership, qualified original-tap updates,
fail-closed handling when the third-party tap cannot be checked, suppression of
redundant app/package rows, and the committed queue-aware Upgrade All behavior.

## Local verification

- Core: 153 tests in 29 suites passed, including official receipt fallthrough,
  third-party ownership, original-tap failures, Homebrew behavior and MAS isolation.
- App: 328/328 cases passed; 1253 localization keys agree.
- No host applications were replaced. VM-only fixture installs preserve the
  previous CompressO copy and do not delete application preferences.

## Final-build VMPal verification

Host and VM executable SHA-256 matched; strict signature verification passed:
`a1a4e0da16f333c0c21b23f1a8a7e38392fcd8f3d8667e56d5d35cf90316d5fc`.
Release build and `git diff --check` passed.

### Official auto_updates

Handy remains installed by homebrew/cask at 0.10.0. It is shown in Apps again,
with upstream release notes and Up to date, rather than the Homebrew group.
The final build's info-level check log confirms the actual source:

```text
Handy [com.pais.handy] v0.10.0: GitHub → 0.10.0 [upToDate]
```

The app executable remains
`aa356164a4919c52992d347e1ead001b55536d378a80ea0dff5d1f480e35e236`;
its receipt remains homebrew/cask 0.10.0. No Handy downgrade or replacement
was performed in this validation.

### Upgrade All

Installed the real historical CompressO 4.0.0 cask in a VM test directory
outside application scanning, then restored the current 4.1.0 tap definition.
This exercises the package fallback rather than the app-owned route.

- The Homebrew tree showed one outdated package and Upgrade All.
- Clicked that package's Update. It showed Starting; Upgrade All immediately
  disappeared, even while the outdated target was still represented.
- The package upgraded to 4.1.0. The popover returned to Up to date.
- This rerun covers the single claimed-target state. The two-target running /
  queued / cancel matrix was verified previously in verification.md; it was
  not repeated in this rerun. Queue-related App tests passed again.

### Third-party application update and popover

Prepared a separate 4.0.0 fixture installation at the original nested app
directory, restored the tap's current definition, and restarted the fixed app.
Clicked CompressO's Update in the popover; it showed Installing, with no duplicate
Homebrew package Update, then returned to no updates.

```text
install start: CompressO [com.compresso.app] 4.0.0 → 4.1.0 via homebrew
install returned: CompressO [com.compresso.app] applied=true bytes=0 staged=false
install done: CompressO now 4.1.0
app version: 4.1.0
receipt source.tap: codeforreal1/tap
receipt source.version: 4.1.0
```

The Caskroom app link still resolves to the original nested directory, and the
compresso CLI link resolves inside that same bundle. The tap checkout is clean.
The temporary package-only installation was uninstalled before this app-path
verification. Its empty directory and the preserved pre-test bundle remain in
the VM; no preferences were removed. An unrelated pre-existing test endpoint error remains outside this task.

The standalone duo CLI was not rebuilt or run in this rerun. Source routing
is in the shared Core stack and covered by the Core tests above.

This record omits personal paths, full
desktop images and unrelated application inventories.
