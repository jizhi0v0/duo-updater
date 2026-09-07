# PreInstallGate: incident timeline and rejected designs

Companion to
`DuoUpdaterCore/Sources/DuoUpdaterCore/Engine/PreInstallGate.swift`. The
source file keeps the current contract; this file keeps *why it looks that
way* — the design it replaced and the incident that motivated its one
non-obvious case. Written for issue #409.

---

## §1 Why this exists: three endings used to share one sentence

The decision used to be a single `guard result.hasUpdate`, true only for
`.updateAvailable` — so every other outcome fell into one branch that logged
"already current on disk". Three unrelated endings wore that same sentence:

- genuinely current (the manual-install / self-updater case the branch was
  written for),
- the source was tried and FAILED — a timeout, a 404, a rate limit — which is
  not a verdict about the app at all and is retryable,
- the app turned out to be managed elsewhere (App Store, Toolbox,
  TestFlight).

The middle one is the damaging conflation: a network blip during an install
attempt produced "already current on disk" in the log, which reads as a fact
about the disk and sends the next person looking at the bundle instead of
the network. `UpdateStatus` already drew exactly this line before this gate
existed — `.unknown` is "nothing covers this app", `.error` is "a source was
tried and failed, retryable" — `PreInstallGate` is what finally reads it
before installing anything, instead of collapsing it back down to one
branch.

## §2 The Nowdex incident: an answer that walked backwards

Observed 2026-09-06 on Nowdex (an App Store iOS-on-Mac app): four install
attempts over ~40 minutes, every one swallowed. Each time, the scheduled
check's batched iTunes lookup answered 1.0.9 and the re-check's own
single-bundle lookup answered 1.0.8 seconds later — both live network loads,
in one process, and the two response bodies differed in length, so these
were two documents, not one document read twice. It turned out to be the
machine's outbound path handing that one URL a stale copy; the same URL from
another process on the same machine answered 1.0.9 throughout, and
re-routing it fixed the install.

⚠️ Quoted from the original source comment, not re-measured for this pass —
the specific root cause (a stale response on one outbound network path) is a
live-network observation that cannot be independently re-verified after the
fact. What *was* re-checked before moving this out of the code comment:
`PreInstallDecision` still has the same five cases, and
`decision(for:offered:confirmed:)` still compares via
`VersionComparator.isNewer(_:than:)` on `VersionSide` pairs — the mechanism
`.answerRegressed` relies on is unchanged as of this pass (2026-09-08).

The root cause is not something this gate can see, and the point of
`.answerRegressed` is that it does not have to be: an answer that walks
backwards is not evidence that something was already installed by another
path, whatever made it walk backwards.

At the time of this incident, `AppListModel.performInstall` (the menu-bar
click) was the only caller of this gate. The CLI's own re-check
(`Install.reconsider`, #404) landed the following night, in PR #434
(2026-09-07). Both callers now feed the same comparator, so the fix in this
gate protects both — but the incident itself was observed and diagnosed only
through the menu-bar path; nobody has reproduced the stale-outbound-copy
shape against the CLI's own lookup call.

---

Tests: `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/PreInstallGateTests.swift`
(the comparator, pinned against both a synthetic backwards answer and the
Nowdex shape), `CLI/Tests/DuoKitTests/InstallTests.swift`
(`answerWalkingBackwardsIsAFailureNotASkip`, pinning
`PreInstallDecision.answerRegressed` → `ReconsiderOutcome.answerRegressed`
on the CLI side).
