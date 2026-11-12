# Automatic updates with persistent background services

## Policy

An app with only background processes left is not closed for an unattended
installation. Its update waits and names those processes. An independent root
service inside a running app's bundle also prevents an automatic quit that
would leave that service running. No vendor service is stopped or restarted.
There are no new exemptions allowing an app's own live service to be replaced.

An identified service blocks its own bundle, not unrelated apps. When normal
process inspection cannot identify it, the already-approved privileged helper
may read the kernel's executable path, including the saved exec path of an
unlinked executable. The app and helper check PID plus start seconds and
microseconds. Every installation checkpoint reads again, including the final
exchange. Missing/old helpers, timeouts and unresolved live identities still
fail closed. The lookup does not register the helper, request approval or run a
shell command. Its reply contains no argv or environment.

## Real-machine result (2026-11-12)

MacBook Pro, Apple Silicon, macOS 27.3; Developer ID build installed with
`make install`. Existing automatic-update preferences were left enabled.

Before: at 16:18:08–16:18:10 CST, magpie, Amp, Obelus and Postman all deferred
with `running processes could not be checked completely`. Their diagnostics
referenced PID 554, `service`, with `proc_pidpath` = 0/ENOENT,
`PROC_PIDTBSDINFO` = 0/EPERM and failed `KERN_PROCARGS2` reads.

`ps -ww -p 554 -o pid,uid,lstart,comm` identified it:

```text
554  0  Thu Nov 12 14:33:42 2026  /Applications/RustDesk.app/Contents/MacOS/service
```

The first development-build pass at 16:45 still reached the old helper and
safely deferred. By 16:47 the old helper was no longer running; no registration
changes or forced restart were made. The next scheduled pass started the new helper.
The actual automatic-update events were:

```text
16:50:41 magpie  installed 0.1.3850    -> 0.1.3862
16:50:44 Amp     installed 1.0 (1278)  -> 1.0 (1281)
16:50:52 Obelus  installed 0.19.1      -> 0.19.2
16:51:20 Postman installed 12.36.2     -> 12.36.3
```

The pass's diagnostics recorded PID 554 with `privilegedPath` result 1,
21 occurrences. The same RustDesk PID and start time remained after all four
updates. No RustDesk or ToDesk service was signalled. The running workbench
showed magpie 0.1.3862 as up to date with the old deferral removed; on-disk
Info.plists also confirmed magpie 0.1.3862 and Amp build 1281.

- [Before: deferred workbench](before.png)
- [After: up-to-date workbench](after.png)

These captures use isolated window rendering; they verify version/status text,
not background glass appearance. RustDesk itself had no pending update in this
pass. Its own-service refusal, and the refusal before quitting a main app with
an independent root service, are covered by regression fixtures.

## Checks

- `swift test --package-path DuoUpdaterCore --force-resolved-versions --filter 'AutomaticBackgroundProcessTests|AutomaticInstallTests|AutomaticUpdateDiagnosticsTests|RunningAppQuitBeforeApplyTests'`: 39 tests passed.
- `make test-app`: 342/342 cases executed; localizable-key check passed.
- `make test-scripts`: passed.
- `swift test --package-path CLI --scratch-path DuoUpdaterCore/.build --force-resolved-versions`: 692 tests passed.
- `swift build --package-path application-test --scratch-path DuoUpdaterCore/.build --force-resolved-versions`: passed.
- `make install`: passed, including signing and macOS 15 back-deployment checks.
- `make test-swift`: the Core run executed 7,308 tests and failed the unchanged
  `CLIToolProcessOriginTests.readsALiveChild` assertion
  `o.ancestors.last?.pid == 1`. It also reported the existing schema-drift known
  issue. That process-origin reader does not use the changed guard or helper.
  CLI tests and the application-test build were therefore run separately.

## Local adversarial self-review (2026-11-12)

Performed by the implementing agent; this is not an independent agent review.

- privilege: inspected the structured read-only selector, the unchanged
  mutual code-signing gates and approval requirement, revision negotiation,
  and both app/helper PID-lifetime checks. There is no client path or command
  to execute, no signal to vendor processes and no new registration path.
- Attacked stale identity before/after the lookup, old helper revisions, missing
  and silent helpers, malformed paths, unlinked executables, lost task-local
  context at Dispatch, unknown live processes beside known ones, and a service
  that appears inside the target before the exchange. Regression tests cover
  the refusals. Kernel argument reads are size-bounded and only the first saved
  executable string is returned; argv and environment are not exported.
- No additional defect confirmed in the final diff. Automatic replacement of a
  target's own persistent service remains deliberately unsupported here.
