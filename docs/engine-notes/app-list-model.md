# AppListModel install path: design history

Companion to the install path in `App/Sources/AppListModel.swift`
(`install` → `runInstall` → `GateHandle` → `performInstall`). The source file
keeps the current contract; this file keeps *why it looks that way* where that
reasoning is a rejected prior design rather than something still true today.
Written for issue #409, which asked this file to be done in slices rather than
all at once — this is the first slice, the install path.

This slice is deliberately short. Most of the install path's comments describe
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

Tests: `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/` has no dedicated test for
the host-gate release point itself (it's exercised indirectly by
`AppListModel`'s own concurrency, which the app-layer test target does not
construct — see `CLAUDE.md`'s "App 层的测试 target" section for why). The
per-host/App-Store gate split itself is `hostInstallGate(for:)` and
`Self.appStoreInstallGate` in `AppListModel.swift`, upstream of this section.
