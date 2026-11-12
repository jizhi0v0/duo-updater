# Keep allowed running apps up to date

The user explicitly approved keep-latest behavior for While running on
2026-11-12. An allowed app may be asked to quit while in front, playing media
or doing work. There is no first-seen wait, interval between successful updates,
app-idle requirement, whole-Mac-idle requirement or workload gate.

The update is downloaded and verified before the normal quit. A refused quit
is not forced. Failure back-off, per-app/global authorization, independent
background-service checks, competing self-updater checks, installation trust,
backup preferences and final-exchange guards remain. Global permission is
rechecked before claiming the quit, and permission/service state is checked
again after the app's asynchronous process inspection.

The delay picker and idle/activity probes were removed. Existing ledger dates
still decode as history but do not delay updates. Old event reasons remain
localized so retained history can still be read. The settings and setup guide
now describe the possibility of restarting an app in use. The list, row menu
and setup board use “Keep Up to Date”, “Only When Not Running” and “Never”;
closed-window wording is avoided because an app can still be running. The
master switch and its search result now both say “Automatically update apps”.

## Real-machine result (2026-11-12)

Apple Silicon MacBook Pro, macOS 27.3, Developer ID `make install`. Existing
While running choices, automatic-update switches and the five-minute schedule
were used. Backup preferences were not changed (backups were off).

Before the change, Spotify 1.3.8.620 was running as PID 1631, started at
14:34:01 CST. The old automatic pass deferred it at 17:37:41 with:

```text
The app is running and was used in the last hour.
```

The new DuoUpdater process started at 17:43:49. Its ordinary scheduled pass
produced these actual Events rows, without an idle-period test override:

```text
17:44:04 Spotify started   1.3.8.620 -> 1.3.9.2055  trigger=automatic
17:44:57 Spotify installed 1.3.8.620 -> 1.3.9.2055  quitForUpdate=true reopened=true
```

The reopened Spotify process was PID 57925, started at 17:44:54. Its on-disk
Info.plist read 1.3.9.2055. Thus a running, explicitly allowed app was updated
and reopened about 68 seconds after DuoUpdater started, without the former
one-hour observation period. RustDesk's service remained PID 554, started at
14:33:42; no vendor background service was signalled.

The running Settings window showed the new keep-latest explanation and no
wait-time picker. The final safety/copy build started as PID 84238 at
18:03:34 CST. Its live list and picker showed “Keep Up to Date”, “Only When
Not Running” and “Never”; the setup board showed the same three titles. The
setup sheet was closed without applying changes.
[Settings screenshot](settings.png) uses isolated rendering
and is evidence for text/layout, not glass appearance.

## Checks

- Red before the policy change: first-observation and rapid-successive-update
  fixtures both returned `.wait(.delay(30))` instead of `.quitAndUpdate`.
- Red before the permission checkpoint: a withdrawn authorization still reached
  the normal-quit callback. The new guard leaves it unclaimed and uncalled.
- Related Core suites before independent review: 51 tests passed, including
  refused-quit, independent-service, unknown-process and exchange protections.
- After the review fix, 47 tests in six relevant policy/quit/exchange suites
  passed. The new parameterized test covers whole-bundle and Contents exchange:
  it revokes permission inside the final process check, asserts the guard was
  reached, expects deferral and verifies that the old on-disk marker remains.
  Both cases failed before the fix (no deferral; new marker replaced old) and
  passed after the post-inspection permission check was added.
- `make test-swift CORE_TEST_FLAGS='--skip CLIToolProcessOriginTests/readsALiveChild'`:
  Core 7,301 tests passed with the existing schema-drift known issue; CLI 692
  tests passed; application-test build passed. The single skipped process-origin
  test is the unchanged host-dependent PID-1 ancestry failure recorded in the
  preceding background-service verification.
- `make test-app`: 343/343 cases; localization keys/specifiers passed.
- `make test-scripts` and `make install`: passed.
- The anonymous-XPC reader tests now call the synchronous reader through
  `offCooperativePool`, matching production. The previous CI run failed two fake
  handshakes; tests no longer block cooperative workers while waiting for XPC.
  The owned copied executable is ad-hoc signed before launch: the copied Apple
  executable was observed exiting before the fallback read. A signed-copy probe
  stayed alive and returned its saved exec path after unlinking, and the final
  complete App test run passed.

## Independent adversarial review (2026-11-12)

One read-only review by Astra at medium effort, explicitly requested by the
user. The reviewer examined the original PR diff and the pending keep-latest
changes, including surrounding guards and tests. It did not run the tests or
repeat real-machine verification.

- process-control: examined explicit app/global permission, normal quit and
  refusal, restart/recovery, independent background services, opaque process
  identity and removed idle/activity waits. No other confirmed blocker.
- privilege: examined the revision-4, read-only helper, mutual signing gates,
  bounded kernel reads, PID-lifetime validation and task-local propagation
  across Dispatch. No other confirmed blocker.
- data-loss: found one P2: the final exchange checked permission before process
  inspection, which can now wait for the helper. A grant withdrawn during that
  wait was not checked again. The primary agent reproduced it deterministically
  on both file-exchange paths, added the post-inspection permission check and
  ran the red-to-green regression plus the related suites. The correction was
  verified by the primary agent; no second independent review was performed.

Backup preferences, trust checks and refused-quit behavior remain in force.
No vendor service was stopped or restarted.
