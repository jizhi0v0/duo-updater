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

## Update sources

- **Every request that reads a latest version sets `URLRequest.versionFeedCachePolicy` on the request itself.** Without it URLCache can return an old body without sending a request: no error, and the row says "up to date". The session configuration's policy is not the one that applies.
- **GitHub's `/releases` list is not guaranteed newest-first.** Taking the first release whose tag matches a pattern can return a lower version.
- **Conditional update endpoints answer a "no update" sentinel for the current version.** A probe or test that only replays "I'm on the latest" proves nothing; it must go from an old version to a new one.
- **Probe scripts must decode the body before concluding anything.** Servers can send gzip regardless of `Accept-Encoding`; `URLSession` decodes it and Python's `urllib` does not. "The page has no version string" drawn from compressed bytes is wrong.
