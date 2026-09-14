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
Docker's 4.86.0-before-4.87.0 first-match bug is
[`docs/app-audits/com-docker-docker.md#历史与实测`](../app-audits/com-docker-docker.md#历史与实测)'s
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

**§4** (below) is the fourth slice: the check round — `refresh` /
`performRefresh`, the TestFlight sync helpers around it
(`recheckTestFlightRows`, `startAutomaticTestFlightSync`), the two memos the
round's rows are judged against (`elevationRequiredPaths`, `runtimeKeys`), and
the network-free rescan trio (`refreshLocal` / `performLocalRescan` /
`refreshRow`). This is the file's most-revised stretch — ten commits between
June and September 2026 each left a dated measurement or a "used to" in it —
so unlike §1–§3 it is several short items rather than one story. The current contract (single-flight
with a follow-up for the intent that owes one, the scan published before the
network check, `roundBaseline` and `CheckRoundWriteBack` for rows that move
under a round, one sync for the whole app) stays next to the code.

Each item names the commit it was checked against. Every number below is a
one-time measurement on the development machine, quoted from that commit or
from the comment it introduced, and **not re-measured for this pass
(2026-09-14)** unless the item says otherwise. What *was* re-checked for every
item is that the code still has the shape the measurement justified.

## §4.1 Why `refreshTask` is cleared inside the task, not after `await task.value` (0.1.8)

`refresh(intent:)` is single-flight: a caller that finds a refresh in flight
awaits it, then — if its own intent does more than the running one
(`RefreshIntent.owesFollowUp`) — runs one pass of its own by calling `refresh`
again. That recursion is safe only because the owning task clears
`refreshTask` **inside itself**, before `task.value` resolves for anyone
awaiting it.

Commit `5c50f4e5` ("Release 0.1.8: fix main-thread livelock (ANR) in refresh
coalescing", 2026-06-23) is where that moved. Before it, `refreshTask` was
cleared *after* `await task.value`, out in `refresh`. A user-present caller
that had coalesced onto a scheduled refresh resumed from its await before that
clear ran, found `refreshTask` still set to the just-finished task, took the
follow-up branch against it, and recursed — forever, on the main thread. The
commit records the fault as latent since `115801f` (pre-0.1.4) and confirmed
by `sample(1)`: 1490 of 1508 main-thread samples at the recursion line, 0
after the fix. The API was `refresh(allowTestFlight:)` then; the branch is the
same one `needFollowUp` guards today.

## §4.2 Why the button's sync waits for the round's read of the store (#518)

Launching TestFlight rebuilds its store, and for a few seconds the tester
query answers for nobody. Sampled through a refresh on 2026-09-11 (commit
`d44f65c8`, "Start TestFlight's sync only after the refresh has read its
store"): every beta reported as tested, then none from about +1.2 s, then all
again by about +6.9 s. Before that commit the round's own read of the store
raced the window the sync it had just started was opening, and when the read
lost, every beta row read "not testing" and showed a question mark until the
post-sync re-check, about fourteen seconds later. PR #518 is the authoritative
account, with the sampler log (a TestFlight pid appearing 0.2 s after the
refresh started, tester rows hitting 0 at +1.2 s).

The same window is why `startAutomaticTestFlightSync` lets a round in flight
publish before repairing the rows (commit `f2f027e5`, #543): a repair that
restores a row to exactly the round's baseline value is not a difference
`CheckRoundWriteBack.publishing(changedSince:)` will protect.

Two other retellings exist and were left alone: `armTestFlightStoreWatch`
(same file, the background-scheduler section, not this slice) and
`TestFlightStoreWatch.reacts`'s doc comment in Core, which carries its own
2026-09-12 measurement of the same effect (installed rows 6 → 0 → 7 across
one-second samples). Both cite #518 and repeat its "~6.9s" figure — two
copies of one number, each next to the code that depends on it; they were
left because each is documenting its own guard, not the round.

## §4.3 The 3.4 s a permission flip used to wait (#503)

`recheckTestFlightRows` waits for a round in flight only when that round began
on the other side of the Full Disk Access change — one that began after it
reads the new state itself. Before that distinction, the re-check waited on
any round in flight. Measured once, on the first grant of a launch where
opening the menu had started a round: the rows changed 3.4 s after the grant
instead of at once. Quoted from the comment commit `fd43fbaa` ("Refresh
TestFlight in an instance we own, and read it only with Full Disk Access",
#503, 2026-09-11) introduced; the commit message itself records the grant
reaching the reads "within a second" on macOS 26.6 but not this number.

## §4.4 What a user-present refresh restarts, and the two times the scheduled tick did too

Two caches are dropped only when the user asked (`RefreshIntent
.restartsChangelogs`), and each was once dropped by the wrong caller:

- **The release notes, hourly (#228).** Until commit `a084b4aa` (2026-09-02)
  `performRefresh` invalidated `ChangelogCache`, cleared `changelogState` and
  cancelled every in-flight load near its top, under a comment scoping that to
  a manual refresh — but it is also the body of the scheduled check, three
  hops down from `backgroundRefresh`. So an hourly tick defeated the notes'
  TTL and, with the Release Notes pane open, blinked what the user was reading
  to a spinner. The distinction was a `Bool` named for one of its consequences
  (`allowTestFlight`); it became `RefreshIntent`, in Core, with each
  consequence a named, tested property. The one thing the wholesale reset had
  been doing right — retrying `.failed` prewarms — is what the tick still does.
- **The App Store page cache, in both directions on one day.** Commit
  `63f841da` (2026-09-05) found `AppStorePageCache.invalidateAll` wired into
  `recheckMany` only, so the Check for Updates button could not reach past an
  hour-old product page; commit `a7a003fe` (same day) found that having it on
  `recheckMany` at all wiped every other App Store row's page on a single
  row's recheck. The full wipe now hangs off `restartsChangelogs` alone and
  the per-row path invalidates just its own rows. Both incidents, with the
  measurement, are `app-store-page-cache.md` §4 — that doc is the home, this
  bullet is only the index entry.

## §4.5 Why the elevation set and the runtime keys are memoized against `results` alone

`policyEnvironment` is rebuilt by every `isRunning` / `canAutoInstall` /
`requiresInstaller` query, and the workbench sidebar asks at least one of
those per row. Anything inside it that touches the filesystem is therefore
paid once per row per repaint, on the main actor. Two commits, five days
apart, are why `elevationRequiredPaths` is a bare memo invalidated only by
`results.didSet`; `runtimeKeys` came later (`986edbcc`, #571, 2026-09-13) and
copies that shape by construction, which is why its own doc comment defers to
the elevation memo's rather than repeating the argument:

- **`1440da71` (2026-08-16), the memo.** The elevation gate had landed the same
  day (`95283bf0`, "the row remembers a declined admin prompt"), building the
  set of paths that need an administrator prompt with an `access(2)`-class
  check per app, per query. The comment it replaced recorded: 0.86 ms to build
  the set once for that machine's 121 apps, so a single list pass spent ~105 ms
  in the filesystem on the main actor — arrow-key scrubbing crawled, scrolling
  dropped frames. The fix memoized the set, keyed on the app paths it was
  computed from.
- **`0fee3c45` (2026-08-21), dropping the key.** The key could never miss:
  `results.didSet` already cleared the memo, and `results` holds value types,
  so any change to any app — including the path move to a differently
  permissioned location the key was written to catch — is a write that clears
  it. And it was not free: `URL.path` bridges to `NSURL` (~58 µs a call
  there), so one arrow-key press through 124 apps cost 124 × 124 trips through
  `-[NSURL path]` — 6% of the main thread in a profile of the sidebar under a
  held arrow key. With the key gone, holding the down arrow took the
  row-building closure from 1440 samples to 377, and the per-step mean from
  65 ms to 56 ms (p90 116 ms → 66 ms). The commit also notes what this did
  *not* fix: a step still cost ~50 ms against a 30 ms key repeat, because a
  selection change re-laid-out the whole window.

"121 apps" and "124 apps" above are one-time counts of the development
machine's installed apps on those two days, quoted from the commit and the
comment it replaced, not a tracked metric and not re-derived for this pass —
the shape `scripts/check_prose_claims.py` exists to keep out of code
comments, which is part of why the numbers live here and not there. A third
copy of the 124 × 124 figure is `CHANGELOG.md`'s user-facing note for that
release ("fifteen thousand redundant lookups"), left alone: it is release
prose, not a design record.

Not re-verified this pass: any of the timings. What was re-checked: both
memos are still `@ObservationIgnored`, both are still cleared by
`results.didSet` and nothing else, and `elevationRequiredPaths`'s doc comment
— which until this pass still described the keyed version `0fee3c45` removed
("cached against the app paths the set was computed from … that moves its
path, which changes the key") — now describes the bare memo. That was a
(c)-class claim in this issue's terms: no longer true, rewritten rather than
moved.

## §4.6 Why `refreshLocal` says which guard closed

Commit `23e6f48a` (2026-08-08) fixed three things surfaced by three identical
DuoPaste rows; the one that lives here is the third. `refreshLocal`'s four
guards had discarded every watcher event and backstop tick without a word,
which made "the list didn't update" indistinguishable from "the watcher never
fired" — and that ambiguity is what made the second of the three, a silently
dead FSEvents stream, take a live-log session to diagnose. The guard now logs
which condition closed it, at debug level. The dead-stream incident itself (an
instance that ran 90 minutes with an idle main thread and no wedged work, and
not one event from either watched root) has its authoritative home in
`App/Sources/AppDirectoryWatcher.swift`'s own doc comment, which also owns the
mitigation — rebuild the stream on a timer and on wake — and is not repeated
here.

## §4.7 The store snapshot that was taken per app

Commit `32a25021` (2026-09-03): the cold-start branch of `performRefresh`
built a `ResolvedChannelStore.Snapshot` inside its `map`, so the one paint
whose whole point is appearing instantly did one file open and decode per
installed app, on the main actor — against the explicit warning on the type,
and unlike the three sibling call sites added alongside it. Found by the fifth
review of that branch, not by a measurement. The snapshot is taken once now,
before `mergeScanned`, and the ignored rows take their own read after the
check has flushed (so a proof established in that same round is visible to
them) — that second read is the `provenNow` line, and its "read after the
check, not before" comment is the current contract, not history.

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

Same absence for §4, with the same reason: nothing constructs `AppListModel`
to run a round, so the single-flight/follow-up recursion (§4.1), the
sync-after-read ordering (§4.2) and the memo invalidation (§4.5) have no test
of their own. What IS tested is every pure decision the round delegates to
Core: `RefreshIntentTests.swift` (which intent restarts the notes, reads
TestFlight, owes a follow-up — the §4.1 recursion's termination condition
`owesFollowUp` included), `CheckRoundWriteBackTests.swift` (rows that moved
under a round survive its publish), `TestFlightSyncPolicyTests.swift` (when a
round earns an automatic sync), `TestFlightStoreWatchTests.swift` (the
watcher's three refusals), and, in the app-layer target,
`App/Tests/ScanRowAssemblyTests.swift` (`roundPlan` and the cold-start
`unchecked` rows §4.7 is about — `CLAUDE.md`'s "App 层的测试 target" section
says which mutation each of its cases pins).
