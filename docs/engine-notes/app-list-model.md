# AppListModel: design history

Companion to `App/Sources/AppListModel.swift`. The source file keeps the
current contract; this file keeps *why it looks that way* where that
reasoning is a rejected prior design, an incident timeline, or a measurement
rather than something still true today. Written for issue #409, which asked
this file to be migrated in slices rather than all at once — each `§` below
is one slice's content, introduced by a short paragraph naming which part of
`AppListModel.swift` that slice covers. This is not one-file-per-subsystem
the way `docs/engine-notes/README.md`'s
naming rule reads at a glance; it is one file per *source* file, exactly as
the README states, and `AppListModel.swift` is the one source file large
enough that its own migration spans several unrelated subsystems.

**§1** (below) is the first slice, the install path. This slice is
deliberately short. Most of the install path's comments describe
a **current** contract or a non-obvious constraint (why `offered` and not the
re-check's own result decides `.answerRegressed`, why `refreshRunningApps()`
takes a fresh snapshot before deferring to a self-updater, why `GateHandle`
tolerates a double release) — those stay next to the code, per this issue's
own classification, and are not repeated here. What follows is the one piece
of this slice that is a genuine rejected-design retelling with nothing else
pointing at it.

Two incidents that used to be retold a third time in this slice were trimmed
instead of copied here, because they already have an authoritative home:
Docker's 4.86.0-before-4.87.0 first-match bug is `VendorProbeRecipe.swift`'s
account (and `CHANGELOG.md`'s user-facing one); ChatGPT's 6971→6962
same-app-race is `SelfUpdaterStaging.staged`'s and
`UpdatePolicy.stagedBlocksInstall`'s own doc comments. See the PR for this
slice for the full duplicate count.

---

## §1 Why the per-host gate covers only the download phase

`runInstall` takes a per-host semaphore (GitHub releases, one vendor CDN)
before the download permit, so a host with several apps updating at once
doesn't split its bandwidth across all of them and doesn't trip its own rate
limiter. The gate is released — via `GateHandle`, handed to
`InstallCoordinator.perform` as `releaseAfterDownload` — the moment the bytes
are down, not when the whole install finishes.

That release point was not always there. Confirmed against `git log`
(commit `bab37c82`, "keep every install inside the concurrency budget, and
free the host gate at end of download"): an earlier version held the host
gate for the *entire* install, not just the fetch. What that meant in
practice: two apps sharing one host would serialize across each other's
extract, swap, and relaunch too, not just their downloads — all of which have
nothing to do with the host's bandwidth, the thing the gate exists to
protect. Two GitHub-hosted apps updating at the same time could not extract
or swap concurrently even though neither step touches the network again.

Splitting the host gate from the "apply" phase (extract/verify/swap, gated
separately by `Self.installPermits`) only paid off once the release point
moved to "bytes are down" — narrowing the *scope* of what the gate covers is
what let two same-host apps stop blocking each other outside their downloads.
`GateHandle`'s "release twice is a no-op" property is what makes the earlier
release safe to add: `InstallCoordinator` releases it via the callback as soon
as the fetch ends, and `runInstall`'s own `defer`-equivalent release after
`performInstall` returns still covers every path that never reaches that
callback at all (an early-out before download, a throw, a cancel) without
double-signaling the semaphore on the paths that do.

---

**§2** (below) is the second slice: running-app detection
(`armRunningAppsMonitor` / `refreshRunningApps` / `handleRunningAppsChange`,
and `retry()` as one of the callers that leans on it), the path issue #247
rewrote. The current contract — KVO is the source of truth, the
notifications are kept as a redundant second path, a snapshot needs a live
run loop to stay current — stays next to the code; what follows is the
measurement issue #247 was filed and closed on, which nothing else in the
source points at.

## §2 Why running-app detection trusts KVO over the launch/terminate notifications (issue #247)

Before commit `03dd3d46` ("App: drive the running set from KVO, not the
launch/terminate notifications", 2026-09-02), `runningAppPaths` was kept
live off `NSWorkspace.didLaunchApplicationNotification` /
`didTerminateApplicationNotification` alone. Those notifications are posted
per app by LaunchServices and, per that commit's own measurement, were
simply missing for some apps in both directions — while
`runningApplications` (the array KVO observes) cannot fail to lose an entry
when a process exits, so it always moved. One process observing both
notifications and KVO, against a 200 ms poll as ground truth, 2026-09-02:

    Alcove, 4 quits + 4 relaunches    notifications 0/8    KVO 8/8
    UURemote quit (+ UURemoteServer)  no didTerminate      KVO caught both
    AppCleaner (control)              both fired           KVO 512 ms earlier

KVO also beat the 200 ms poll by 26–180 ms on every transition it caught,
which is why the ~2 s reconcile timer issue #247 originally proposed as a
backstop was dropped rather than added: there was nothing left for a
periodic reconcile to catch that KVO didn't already report sooner.

⚠️ One-time measurement on one machine, not a tracked benchmark — see this
directory's README on the difference. It has not been re-run for this pass:
whether the specific notification gaps above (Alcove's, UURemote's) are a
stable LaunchServices property, or an artifact of that machine/OS build on
2026-09-02, is unverified either way. What *was* re-checked for this pass
(2026-09-12): `armRunningAppsMonitor` still observes
`NSWorkspace.runningApplications` via KVO as its primary path, with the two
notifications kept as a secondary one, matching the source comment — the
architecture this measurement justified has not drifted.

**A false claim this pass found, not just an old one it moved.** `retry()`'s
own doc comment read: "`NSWorkspace`'s launch/terminate notifications are
the only thing maintaining that set." That was true of the code when it was
written — commit `3841dfb8`, the same day, 13 minutes *before* `03dd3d46`
landed — but was never updated once KVO shipped, and has said the opposite
of the running mechanism ever since: KVO has been the source of truth since
2026-09-02, and `retry()`'s explicit re-derivation is a defensive floor
under that live path (the same role `performRefresh` and
`performLocalRescan`'s own comments describe it playing at their call
sites), not the only thing keeping the set current. Fixed in the same edit
that added this section's pointer, on the reasoning that a comment
contradicting the section it now points at is worse than the long version
it replaced.

---

**§3** (below) is the third slice: channel-switch detection
(`recheckChannelSwitches` / `runChannelSwitchRecheck` /
`fingerprints(forBoundIDs:)`, under the `// MARK: - Channel-switch recheck`
heading), the scheduling around a `ChannelBinding` app's own in-app channel
toggle that issue #74 found broken and that got revised twice in the same
evening. The current contract — cancel-and-restart beats both "drop the new
trigger" and "let both run", and the cancelling task must wait the superseded
one out before its own claim pass starts — stays next to the code; what
follows is why those two alternatives were tried and rejected.

## §3 Why a channel-switch recheck cancels and waits, rather than dropping or racing (issue #74)

The watcher that notices a flip at all — a filesystem stream on the vendor
preference files a bound app's channel lives in, debounced and coalesced
through a fingerprint compare — predates this section, and its own genesis
(the Surge timeline: a launch event reading `KDDefaults.plist` before Surge
had finished writing it) already has an authoritative home,
`ChannelBinding.preferenceWatchPaths`'s own doc comment — not repeated here.
What follows is two bugs found in the recheck *scheduling* around that
watcher, both from 2026-08-26.

**The original bug** (issue #74, filed and fixed 2026-08-26). Before commit
`3d19c1f8` ("supersede an in-flight channel recheck instead of dropping the
new one"), a trigger that arrived while a recheck was already on the network
was dropped by a `channelSwitchRecheckRunning` guard — and because
`lastSeenChannelFingerprints` was booked *before* the per-row rechecks ran,
nothing ever compared that state again. Observed on this machine, flipping
BetterDisplay's prerelease toggle back and forth: "a single flip settles in
~2.4s every time (1s FSEvents debounce + fingerprint pass + networked
recheck)" (quoted from the issue), and a flip landing inside another flip's
~2.4s window was forgotten until an unrelated event — another bound app's
launch/quit, the watcher's 900s re-arm, wake, or the next full check —
happened to trigger a fresh pass; worst case, ~15 minutes on the wrong track.
Fixed by cancelling the in-flight pass and starting over instead of dropping
the new trigger, with fingerprints booked per id only once that id's own
recheck finishes (`ChannelSwitchDetector.booked`).

**The bug that fix introduced** (found by reading, the same evening — see the
caveat below on how it was found; fixed by commit `7e7b89d0`, ~75 minutes
after `3d19c1f8`).
`Task.cancel()` only raises a flag: the cancelled pass kept running —
`recheckMany` scans on a detached task, which cancellation cannot reach — and
kept holding `installing[id] = .checking` on the rows it had claimed. The new
pass's claim filter is `installing[id] == nil`, so it skipped exactly those
rows: neither pass rechecked them, and a flip could go un-acted-on by both.
Fixed by making the new task explicitly await the superseded one's
completion before running its own claim pass, chained inside the new task so
`channelRecheckTask` is already reassigned by the time a third trigger
arrives.

⚠️ **How likely that second bug was, in the fixing commit's own words, is more
qualified than the source comment (before this pass) put it.** `7e7b89d0`
measured the claim window at roughly 0.3s inside a ~0.72s settle, and ran
twenty flips with deliberately dense extra triggers — a bound app
launching/quitting, an unrelated `~/Library/Preferences` write, each within
300ms of the flip — without reproducing it once, closing with "this is a
defect found by reading... not a bug anyone has reported." The source
comment in `recheckChannelSwitches`, before this pass, described the same
double-trigger shape as "enough to hit it," with no such caveat. Both
statements describe a real, narrow window that the fix correctly closes —
the difference is confidence, not mechanism — so this is flagged as
overstated rather than rewritten as false, and the source now points here
instead of repeating either framing.

Not independently re-verified this pass (2026-09-12): whether the 2.4s /
0.72s / 0.3s timings above still hold — the preference-watcher debounce they
were measured against has since been cut from 1s to 0.25s (same MARK
section, `armLocalRescan`), which should shorten all three, and none of them
has been re-measured since. What *was* re-checked: `recheckChannelSwitches`
still cancels-and-waits rather than dropping or racing, and
`runChannelSwitchRecheck` still books per completed id via
`ChannelSwitchDetector.booked` — the architecture both 2026-08-26 fixes
produced has not drifted.

---

Tests: `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/` has no dedicated test for
the host-gate release point itself (it's exercised indirectly by
`AppListModel`'s own concurrency, which the app-layer test target does not
construct — see `CLAUDE.md`'s "App 层的测试 target" section for why). The
per-host/App-Store gate split itself is `hostInstallGate(for:)` and
`Self.appStoreInstallGate` in `AppListModel.swift`, upstream of §1.

Same absence for §2: nothing constructs `AppListModel` to exercise
`armRunningAppsMonitor`'s KVO wiring itself. What IS tested, in
`DuoUpdaterCore/Tests/DuoUpdaterCoreTests/RunningBundlePathCacheTests.swift`,
is the cache `refreshRunningApps` calls into — eviction on a process quit,
re-resolution on reappearance, the staging-name normalisation `retry()`'s
correctness depends on — everything downstream of "here is this event's
snapshot of running bundle URLs", not the KVO delivery itself.

Same absence for §3: nothing constructs `AppListModel` to exercise
`recheckChannelSwitches`'s cancel-and-wait scheduling itself — the two
2026-08-26 races were both found by reading, not by a failing test, and
neither has one today. What IS tested, in
`DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ChannelSwitchDetectorTests.swift`,
is `ChannelSwitchDetector.changes`/`.booked` — the per-id fingerprint compare
and the "leave an unfinished id looking changed" bookkeeping the first fix
depends on — not the `Task`-cancellation race the second fix closes. That
test file's own `/// The regression behind issue #74, as a sequence.` comment
(line 220) is a second retelling of the first bug, written to justify its own
fixture rather than to be a design record; left as is, per this directory's
own guidance that a test's incident retelling documents the test, not the
class.
