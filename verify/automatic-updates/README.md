# Automatic update verification — 2026-11-05

Safety baseline production code reviewed and tested: `ba72046b6c8289e0e9b16559f7e80ab892f827e0`.

## Deferral classification fix validated at `97e8d38b`

The subsequent fix keeps `AutomaticInstall.Deferred` distinct through the app's
install outcome and records `deferred`, retaining its reason. Expected refusals
skip generic failure logs and failure-event creation. The early process,
eligibility, existing-installer and complete-backup guards use the same outcome.

- Host App tests: 326/326; localization 1,248 keys; Core targeted tests 11/11.
- A real current-source Debug app in VMPal encountered an actual unreadable
  other-user process: Events recorded started then deferred, failure events
  remained zero, and Discord Canary stayed at 0.0.1459.
- After stopping the test helper, another scheduled check updated 0.0.1459 →
  0.0.1488, with automatic=true and no failure events; strict signature
  verification passed. Test automatic settings were removed afterwards.
- VMPal safety/event/scheduler suites at that revision: 57/57 passed.
- [Raw real-app refusal and recovery results](vm-deferral-result.txt).
- Local author-run adversarial follow-up: traced every automatic guard return,
  typed error propagation through coordinator and app catches, and the
  `.notInstalled`-only failure reporter. Deferral clears the busy state and
  cannot be counted as an installed app. No exchange/backup permission was
  relaxed. The real-app probe caught an initially missed early return; that
  attempt was corrected and rerun, not counted as passing.

## Post-preflight refusal follow-up

Review found that the later self-updater/nested-helper refusals still returned
`notInstalled`. These now return `deferred` with a reason for automatic work;
manual behavior is preserved. The neighboring staged, unreadable-staging and
in-flight self-update collision branches now preserve their existing notes as
deferral reasons as well. These changes only classify already-refused attempts:
process/backup/permission decisions and exchange code are unchanged.

Host `make test-app`: 326/326, localization 1,248 keys. Local author-run review
traced both process-refusal branches and all neighboring staging returns, checked
that automatic branches neither open apps nor populate failure errors, and
verified the manual returns remain unchanged. The specific launch-between-checks
race was inspected in code, not reproduced deterministically in the VM; the
97e8d38b VM record above validates the unchanged deferred outcome/event mapping.

## Installation collision follow-up

Automatic attempts refused by another process holding the install lock, a live
prior install journal, or this app's already-claimed row now return `deferred`.
The lock catch distinguishes `heldByAnother` from `unavailable`: filesystem/lock
errors remain real failures. All permit and lock releases remain paired; no
collision guard is bypassed and manual outcomes are unchanged. Local author-run
review traced `install` → `runInstall` → `runInstallJob` → `performInstall`,
including all early returns and failure reporting. Current host App tests passed
326/326 with 1,248 localization keys. This is a refusal-classification change;
the VM event-mapping evidence remains the explicitly pinned record above, not a
claim that these lock races were reproduced in the VM.

## Fresh policy-gate and retry follow-up

Fresh one-click `Withheld` and late `NestedAppRunningError` refusals now become
`AutomaticInstall.Deferred` only inside automatic work. Manual errors keep their
original types. Integrity/I/O failures are not reclassified. The process checks
before download/apply and the final captured exchange callback all use this
classification. Delta and local-stash retry classifiers refuse to retry a typed
deferral, avoiding a second download after a safety refusal.

Current host App: 326/326 and 1,248 keys. Current host Core targeted: 12/12.
Current VMPal safety/event/scheduler selection: 58/58, identical production files
and test bodies, with the same VM-only Swift Testing manifest described below.
The policy regression checks automatic versus manual error types, preserved
reasons, both retry classifiers, and unchanged signature/I/O failures. Existing
real-filesystem permission-withdrawal and post-staging helper tests also passed.
Local author-run adversarial follow-up traced fresh-gate throws before the main
coordinator catch, nested checks at download/apply/exchange, and delta/stash
wrapping; no guard was weakened. Actual scheduled GUI install/event evidence is
still the pinned 97e8d38b record, not a claimed replay of the latest GUI build.

## Safety baseline validation

- Host: `make test-app` passed 326/326; 1,248 localization keys agree.
- Host: AutomaticInstall/EventStore/RefreshLane/NestedAppGuard selection passed
  95/95. Complete App and CLI unsigned Release builds passed.
- VMPal macOS 27.2: identical production Sources, AutomaticInstall/EventStore/
  RefreshLane selection passed 56/56. The VM-only manifest selects these suites
  because Command Line Tools lacks XCTest; Swift Testing macros are loaded
  explicitly. Production source and test bodies are unchanged.
- VM scratch filesystem attacks: withdraw permission after entry and before
  the exchange; start a real ad-hoc-signed helper only after Contents staging.
  Both refuse the operation and preserve the original marker. The helper test
  first requires the actual helper to appear, so unrelated unknown PIDs cannot
  make it pass accidentally.
- VM cross-user attack: run a copied helper as `nobody`, unlink its executable,
  then inspect as uid 501. PID 79019 remained alive with both executable and
  saved argv paths unreadable. The actual snapshot retained it and
  `AutomaticInstall.checkProcesses` threw `Deferred`. The helper was stopped.
  This is an actual cross-user process test, not a second GUI login session.
- Timeout/follow-up callback ordering and skipped-trigger regressions passed.
- Current Release build in the VM: scheduled Discord Canary 0.0.1459 →
  0.0.1488 succeeded without an install click. KeepBackups=0 still created a
  fresh 538,662,630-byte backup. Started/installed events and the durable
  automatic=true install record agree; the app stayed closed and strict deep
  signature verification passed. Test auto-update settings were removed.
- [Current installation output](vm-current-result.txt).
- [Current raw test excerpts](core-current-tests.txt).

## Current local adversarial review (author-run)

Reviewed the PR diff against its merge base, traced scheduler/watcher callers,
backup and route gates, task-local propagation and both exchange paths. This
is an author-run review, not an independent agent review.

- data-loss: attacked permission withdrawal and helper launch after staging in
  the VM as above; original files remained. Synchronous permission snapshots
  and the process callback are captured before Dispatch and run after staging.
- data-loss: attacked incomplete process inspection using a real other-user
  unlinked helper; the unknown PID is retained and blocks installation.
- data-loss: inspected mandatory backup outcomes: only `.saved` proceeds;
  installer/external-manager routes and elevation are refused unattended.
- data-loss: tested scheduled work finishing after timeout and a follow-up
  refresh, plus a trigger arriving during installation callback. The lane
  serializes callbacks and new refreshes; watcher refreshes carry no callback.
- Install bookkeeping does not await the same app lane from its callback;
  directory-watcher triggers use separate tasks. No same-lane await cycle found.

Process inspection cannot atomically prevent an external app launch at the
filesystem exchange instruction. Full-disk backup failure, live Low Data Mode
switching and Developer ID signing remain unexercised.

## Earlier end-to-end baseline

The following original installation record and screenshots were produced from
`747febf5251efb523cf0992c776657da134e0c65`; they are not current-head test results.

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
