# Homebrew compatibility fixes — VM result, 2026-11-17

The seven runtime groups passed on VMPal `macOS VM 1`, Apple Silicon
`VirtualMac2,1`, macOS 27.2 (26B123), Xcode 27.2 (27B52), Homebrew 7.0.12.
Rosetta and a separate `/usr/local` Brew were installed in the VM. The
functional run built the complete production Core at
`f00a515be5d3e91456a69a75e9a06b4f7e91a245`; the later
`ec78e8cb7607e787db0dfaad04b4a15b8a3ab689` changes only a test assertion.
The guest's shipping-source diff between those commits was empty.

All compilation and runtime checks were performed inside the VM. The original
host working tree and host applications were preserved. This is real Brew
installation/execution verification through production Core entry points,
with controlled minimal app archives and an injected catalog. It is not a
walkthrough of every shipping GUI row or a vendor-signing audit.

## Functional result

[`functional/result.json`](functional/result.json) reports `passed: true`.
Raw command lines, exit statuses and output are retained in that directory.

- Platform variation: real Brew's resolved version/URL agree with the ARM
  entry. Core resolves the same app from the variation's version, URL,
  artifacts and OS requirements, rather than the intentionally wrong base.
- Old token: an unmigrated old receipt resolves the canonical cask. A same-name
  unowned copy and a receipt from a different tap are not adopted. Real Brew
  migration followed by canonical pin/unpin remains correct while a legacy
  alias exists; its actual origin is recorded in `old-alias-origin.txt`.
- Formula and app-cask pins: the real pinned formula is excluded from the
  production parser; app-cask pin suppresses its Brew action, and unpin restores
  the update. Unit checks also preserve explicitly allowed vendor fallback.
- Complete cask identities: comma and colon suffix changes both produce an
  update; real Brew upgrades change bundle build 101 to 102 and settle current.
  Opaque hash/date suffixes and marketing downgrade protection are covered by
  the focused production tests.
- Prefix isolation: official and third-party Intel-owned apps are explicitly
  refused by source, checker, fetch and apply. Neither prefix's records nor app
  bytes change. Removing only the main link while a helper survives still
  refuses; receipt-only third-party ownership also refuses.
- Receipt-only and stale-record controls: the official missing-link case
  retains ownership (#2036), and an app already self-updated to the offered
  marketing version stays current despite its older Brew receipt. This does
  not identify why the #2036 reporter's original link disappeared.
- GUI shell environment: LaunchServices starts the probe without CLI Brew
  overrides; shell-only NO_AUTO_UPDATE and interval 2055 reach real Brew config
  and normal executor/preflight/fetch. The synthetic Homebrew token is passed;
  unrelated synthetic secret and shell PATH are excluded. See
  [`functional/env-result.json`](functional/env-result.json).

All eight fixture uninstall operations returned zero. The temporary shell
configuration and tap rename maps were restored; a subsequent guest check
found no `duo2055vm-*` records in either Caskroom or the ARM Cellar, no temporary
`.zshrc`, and no tracked working-tree changes.

## Build and test results

- Focused compatibility, execution and third-party suites at `ec78e8cb`: all
  40 test functions passed, including their parameter cases. Raw output is
  [`focused-ec78e8cb.log`](focused-ec78e8cb.log).
- App tests at `dd356203`: 370/370 cases executed and passed; all 1,430
  localization keys are reachable. CLI tests: 731 passed; the existing
  `application-test` package built successfully. Their shipping sources differ
  from the final implementation only by deletion of the redundant alias guard
  discussed below; current focused and functional checks cover that change.
- Script tests passed in the VM. Logs are retained beside this record.
- Production Core Release build at `ec78e8cb` passed in the VM (172.20 seconds).
- The ordinary Core full run at `dd356203` executed 7,583 tests and failed one
  unexpected App Store language assertion (plus one declared known issue).
  All three Homebrew-related suites passed. The unchanged language case passed
  alone, and its complete 27-test cache suite passed in a fresh process at
  `ec78e8cb`.
- A separate run of all remaining 7,556 Core tests at `ec78e8cb` completed with
  five unexpected live endpoint/probe failures and three known issues. The
  unexpected failures were CCC beta/CCC 6 probes and live vendor install-plan
  probes. Both groups together cover the full Core suite; no test was omitted,
  and these results do not constitute an all-green full-suite result.

The App Store test's expected language ignores the process-wide rejection
latch used by production lookups. Concurrent live tests can set that latch on
HTTP 400, which is consistent with the observed discrepancy, but the logs do
not identify a particular writer or prove that causal chain. No unrelated
App Store production behavior or external recipe was changed to obtain a pass.

Large raw logs are compressed as `.log.gz`; no content was removed from them.

## Independent adversarial review

The reviewer used `gpt-6-astra`, a different model from implementation, and
reviewed the merge-base diff, callers, guards and tests. The final shipping
code review at `f00a515b` has no remaining confirmed finding. Review covered
process-control, data-loss, privilege, trust, secrets and untrusted-input.

Two confirmed initial implementation problems were corrected and exercised:
stale receipts reoffering already installed releases, and a surviving helper
link hiding the main app's foreign ownership. Relocated artifact targets and
identical basenames in different source folders also have direct tests.

An earlier suspicion about alias selection was withdrawn. Removing only the
proposed token-directory symlink guard did **not** fail its targeted test:
one test passed in 0.028 seconds. That guard and the misleading test setup were
removed rather than manufacturing a failing mutation. The remaining test
asserts exact app owners, allowing empty alias inventory entries, and checks
the new canonical pin/full-record behavior. See
[`alias-guard-removed.log`](alias-guard-removed.log) and
[`alias-review-observation.json`](alias-review-observation.json).

## Scope

Intel-prefix app updates are deliberately unsupported and receive an explicit
refusal; this change does not implement Rosetta execution routing. Pin is a
Brew-source decision, not a global ban on explicitly selected updates from
other sources. No public issue reply, release, deployment or merge was made.
