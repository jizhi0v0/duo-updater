# Review instructions

Read by the Claude review workflow (`.github/workflows/claude-review.yml`) and by other AI reviewers that look for a root `REVIEW.md`. Every check below exists because a pull request in this repository shipped that bug, or nearly did.

## What is blocking

- The merged code would do the wrong thing, or a comment, doc or message states something false that someone would act on.
- Style, naming, optional refactors and problems that predate the change are not blocking. Don't report them.
- A claim about something outside the repository (a vendor endpoint's response, a third-party tool's default, OS behavior) that can't be checked from the code is **unverified**, not wrong. List it as unverified.

## Guards and conditions

- **Trace a guard's condition to where it is set.** A `guard`/`if` in the right place and direction still does nothing if the flag it reads is only set on a path the default configuration never takes, or only *looks* equivalent to the fact it stands for.
- **Compared values must come from the same moment.** One value read live from disk and the other from an earlier scan snapshot will disagree during a batch.
- **A count is not a set.** A check described as "nothing may disappear" that compares counts passes when one item leaves and another arrives.

## Tests that cannot fail

- **A test for a guard must fail when the guard is removed.** Watch for fixtures that return early before reaching the condition under test, and for fixtures that feed both branches the same input so both verdicts match.
- **Timing tests must first assert that the fixture was found.** "The fast path is fast" and "returned nil immediately because the fixture no longer decodes" pass the same way.
- **No wall-clock upper bounds in the core suite.** It runs in parallel in one process, so a duration measures the pool, not the code. Assert an ordering or an observable state instead.
- **Compare sets of names, not totals.** "Declared vs executed" totals cancel out under `.disabled()` and parameterized tests.
- **Harnesses that watch processes must prove something changed.** `NSWorkspace.shared.runningApplications` never refreshes in a process that doesn't run a run loop, so "no change" can be a stale snapshot.

## Swift and Foundation

- **`String(describing:)` escapes nested strings.** For a `String` inside an `Optional`, array, enum payload or struct field it uses the debug description (`\"`). A regex containing quotes silently never matches that text.
- **`FileManager.replaceItemAt` can replace and then throw.** It throws when it can't delete the replaced item (for example a `uchg` file), after the swap has happened. Decide whether the swap happened from file identity (inode), not from whether the path exists.
- **`try?` on cleanup hides the failures that matter.** A delete that fails on a `uchg` file leaves the directory behind, and `createDirectory(withIntermediateDirectories: true)` then succeeds on it.

## Cancellation

- **Once an install passes its commit point, everything after it runs to the end.** The swap and the steps after it (re-reading the version, reopening the app, settling the rollback point) run inside `InstallCommit.run`, or under a caller that shields the whole item. Code after the commit point that still runs in the cancelled task has its `.terminateChild` reads refused and its `try? Task.sleep` returning at once: a finished update is reported as failed, or a quit app is never reopened.
- **Before the commit point, an install writes only into its own workDir, the resumable-download store, the backup store or the install journal.** A cancel cleans up by deleting the workDir and returning permits and space reservations; anything written elsewhere is left behind.
- **A `try? await Task.sleep` in a loop must check `Task.isCancelled` on every pass.** Once the task is cancelled the sleep throws at once and `try?` swallows it, so the loop spins. `NoSwallowedCancelSleepsTests` enforces this under `Install/` and `CLITools/`; a site that cannot spin carries `// cancel-ok: <reason>`.
- **A child killed on cancel (`.terminateChild`) must write only inside the workDir.** Teardown signals the child's pid only, so grandchildren survive, and so do files it writes elsewhere: BinaryDelta writes its per-file diffs into `NSTemporaryDirectory()`, which ignores `TMPDIR`, so it stays `.runToCompletion`.

## Update sources

- **Every request that reads a latest version sets `URLRequest.versionFeedCachePolicy` on the request itself.** Without it URLCache can return an old body without sending a request: no error, and the row says "up to date". The session configuration's policy is not the one that applies.
- **GitHub's `/releases` list is not guaranteed newest-first.** Taking the first release whose tag matches a pattern can return a lower version.
- **Conditional update endpoints answer a "no update" sentinel for the current version.** A probe or test that only replays "I'm on the latest" proves nothing; it must go from an old version to a new one.
- **Probe scripts must decode the body before concluding anything.** Servers can send gzip regardless of `Accept-Encoding`; `URLSession` decodes it and Python's `urllib` does not. "The page has no version string" drawn from compressed bytes is wrong.

## Records in the PR description

- **A behaviour change needs a real-machine record in the PR description, and it must cover what the PR changed.** A PR touching `DuoUpdaterCore/Sources/`, `App/Sources/`, `App/Helper/`, `App/Shared/` or `CLI/Sources/` needs a dated `## Real-machine result (YYYY-MM-DD)` section with its results, or `Real-machine: not needed — <reason>` whose reason holds (refactor, test-only, internal plumbing); a missing record, one for another change, or an opt-out on a change users would see is blocking (`scripts/check_real_machine_record.py` checks only that one is there).

- **A high-risk change needs a local adversarial review on record, and it must cover the risks the PR raises.** `scripts/check_adversarial_review.py` lists them (process-control, data-loss, privilege, trust, secrets, untrusted-input) and checks that a dated `## Adversarial review (YYYY-MM-DD, <sha>)` names each one, at a commit after which nothing high-risk changed, or an `Adversarial review: not needed (<sha>) — <reason>` line. It cannot tell whether the review was real or the reason holds: a section that names a risk without saying what was attacked and what came of it, or an opt-out on a real risk (a new `sudo`, a token passed to a child, a deletion), is blocking.

## Recipes and onboarding

DuoUpdater runs only on Apple Silicon Macs with macOS 15 or later (`App/project.yml`). Copies that exist only on an Intel Mac or on an older macOS are not a group of users, and a gap that only shows on those hosts is not a finding.

- **A recorded gap counts only when its reason holds.** Check the audit's stated reason against the vendor's source or releases (a claim like "their own updater already moves them to the latest" must be true at that version). When the repository already has the mechanism for the group (`BundleIDMigration` for old bundle IDs, `OneClickGate` to keep detection but withhold one-click from another edition or major, `.publishedDigestOnly` for ad-hoc builds), the audit must say why it doesn't apply. A group the rule would offer a wrong version or replace with another edition is never a valid gap. Without a reason that holds, treat the group as neither covered nor recorded, whatever its worst case. A group the audit says it didn't check is neither covered nor recorded only if, for a plausible state of those copies, the rule would offer them the wrong version, one-click would replace them with another edition, or they would silently get no detection. A group, unrecorded or unchecked, whose worst case is a refused install (the Team-ID gate refusing a different signer) is not a finding.
