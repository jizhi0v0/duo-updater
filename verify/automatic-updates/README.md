# Automatic update verification — 2026-11-05

Code reviewed and tested: `747febf5251efb523cf0992c776657da134e0c65`.

## VMPal

macOS VM 1, macOS 27.2 (26B123). Host applications were not replaced or restarted.
Developer ID signing returned errSecInternalComponent; the VM used an ad-hoc
signed build from the complete Release build. The VM's existing application and
preferences were preserved under `~/duo-verify/automatic-updates/`.

- AutomaticUpdates=true with CheckFrequency=manual: no automaticUpdate events;
  Discord Canary remained 0.0.1459.
- Scheduled checks enabled with an overdue LastCheckDate: the application itself
  performed Discord Canary 0.0.1459 → 0.0.1488, without an install command/click.
- KeepBackups=0 throughout: a 538,662,630-byte backup of 0.0.1459 was created.
- The Events UI visibly showed started and installed with both versions.
- The durable install event carried automatic=true and applied=true.
- The updated app was not running; strict deep codesign verification passed.
- Test enablement and check frequency were removed afterwards, restoring the
  previous defaults. The updated app, rollback backup and evidence were retained.

Raw output: [vm-result.txt](vm-result.txt).
Screenshots: [settings](settings.png), [events](events.png).

## Checks

- `make test-release-build`: complete App and CLI Release builds passed.
- `make test-app`: 326/326 cases passed; 1,243 localization keys agreed.
- `make test-scripts`: exit 0.
- Core safety filter (AutomaticInstall, InPlaceSwap, InstallCoordinator,
  InstallEvent, EventStore): 72 tests passed with one declared known issue.
- Final AutomaticInstallTests: all 5 passed, including a real scratch bundle swap
  refused after permission was withdrawn; the original marker remained intact.
- Extended AutomaticInstallTests + NestedAppGuardTests: 43/44 passed.
  `theLiveListSeesAHelperWhoseExecutableTheSwapUnlinked` failed at line 821
  (`seen.value`). It failed again alone and with the main checkout's existing
  test binary, at the same assertion. This is not reported as a passing check.

Live Low Data Mode switching, full-disk backup failure and production Developer ID
signing were not exercised. Network permission withdrawal and complete-backup-only
policy have automated coverage; these do not substitute for those live scenarios.

## Local adversarial review (author-run)

Risk classification from scripts/check_adversarial_review.py: data-loss.
Reviewed the change against its merge base, including callers and existing tests.

- data-loss: attacked the interval between download and replacement. The final
  swap repeats the process check after staging, before replaceItemAt; no quit or
  relaunch is sent. Existing nested-guard boundary tests still pass apart from the
  separately reproduced live unlinked-process test above.
- data-loss: checked backup failure and incomplete backup outcomes. Only `.saved`
  permits automatic installation; the VM proved a backup was actually made even
  with the global backup preference off.
- data-loss: checked a policy change before commit with a real scratch directory.
  The swap threw AutomaticInstall.Deferred and preserved the original contents.
- Checked unattended route revalidation, elevation refusal, suppression of staged
  updater clearance and permission UI, and task-local propagation into commit
  tasks. Manual updates retain their existing interaction policy.

This was an author-run review, not an independent agent review. Runtime process
checks reduce launch races but cannot atomically prevent another program from
launching an application at the filesystem exchange instruction.
