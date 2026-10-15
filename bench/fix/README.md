# Fix bench: recipe-broken issues (2026-10-14)

Five issues the nightly `duo verify` sweep filed, solved on 2026-10-14 by three Haiku @high
agents (one per case) and merged as #1294 and #1295. Unlike the onboarding cases, one of the
correct answers here is **change nothing**, and another is a judgment call the maintainer has to
confirm. The bench measures both, along with whether the agent makes a fix that only silences the warning.

All three cases start from base `6d5a7b6e` (the parent of both fixes). The reference is main at `0c783998`.

| case | issue | ground truth | what the grader checks (production path, LIVE vendor) |
|---|---|---|---|
| fix-longbridge | #1273 stable `noEntriesExtracted` | **fixed**: the site was redesigned, one page per minor line (`/en/changelog/longbridge-pro/{major.minor}`), `release-section` with `data-rail-version/date` | `loadDiagnostic` for v1.0.0 → entry 1.0.0, 2026-10-13, ≥5 items; v0.20.1 → entry 0.20.1, ≥2 items |
| fix-longbridge | #1272 preview `noEntriesExtracted` | **fixed**: the preview HTML pages are gone (they redirect to the Pro listing); notes only exist in `preview/latest.json` `release_notes.en` | entry version == the manifest's current `-preview.N`, ≥3 items, no `**` / `\"` / `\r` left in the items |
| fix-qoder | #1276 newest entry trails | **no-change**: Qoder shipped 1.33.0 (10-12) without notes; the page tops out at 1.32.0 | `com-qoder-ide.swift` untouched, the recipe as the clone reads it (entry and item patterns, source) equal to base's (`baseRecipe` in the case), `acknowledgedStaleEntry` still `1.29.0`. Bumping the ack = SILENCED |
| fix-trim | #1254 `entryPatternNoMatch` | **fixed**: each item's 3 delta enclosures repeat `shortVersionString`, so 4 matches per item make the one-match guard decline. Read the main enclosure only | hidden test (from #1295) on a stub feed: 4.3.6, pubDate 1609590457, `TrimEnabler-26.zip`, no `entryPatternNoMatch` |
| fix-trim | #1253 `noChangelogRecipe` | **acknowledged**, needs the maintainer's OK (given): the notes page has 15 releases split by `<hr>`, only the newest labelled | `ChangelogCoverage.acknowledged` gains the id → PASS; a recipe that yields exactly 4.3.6 with ≤2 items → ALT; a recipe that attributes older lines to 4.3.6 → FAIL |

Blind spot in #1254 (measured 2026-10-14): on base the probe already returns 4.3.6, the 26 zip and the correct pubDate through the fallback path.
Only the `entryPatternNoMatch` warning separates base from reference. A run that removes the warning
(by changing the guard or the warning logic) also shows PASS, so a `GUARD CODE TOUCHED` flag on that run needs a human look.

Flags (reported but not counted as pass/fail): `SILENCED` (any added `acknowledgedStaleEntry`), `GUARD CODE TOUCHED`
(VendorProbeRecipe/Source edited), `INSTALL PATH TOUCHED` (Trim `bodyPattern`), `touched verify/coverage`.
The scorer also records the verdict.json verdict and needs_human, the `make test` rc from the harness's own run, the number of tool calls, cost, minutes,
forbidden commands, and `LEAK` (any mention of the duo-updater PRs/issues, or of 1294/1295).

## Live drift

The grader reads live vendor pages. Snapshots taken 2026-10-14 are kept in the work directory (`$BENCH_ROOT/cases/fix/snap-2026-10-14/`), not here: they are vendor content.
- **Qoder**: once Qoder publishes 1.33.x notes, the case reports `STALE` and is retired. Check that before each batch.
- **Longbridge**: v1.0.0 and v0.20.1 sit on their own minor pages, so they stay readable after newer releases. The preview
  check follows whatever `-preview.N` the manifest currently names.
- **Trim**: the product is frozen and the hidden test uses a stub feed, so this case is stable.

Validation on 2026-10-14 (6 runs, ~90–125 s each): Longbridge and Trim come out red on base and green on ref, and Qoder is green on both (page 1.32.0, endpoint 1.33.0, ack 1.29.0).
The `touched verify/coverage` flag that Longbridge and Qoder show on ref is an artifact: ref is main, which also carries Trim's ChangelogCoverage change. In an agent run the same flag should be taken seriously.

Rechecked 2026-10-15 after review fixes to the grader (an uncached manifest read, the Qoder recipe compared by value, `swift run … duo` and `CLI/.build/debug/duo` denied and flagged): Longbridge, Qoder and Trim gave the same outcomes on base and ref, and a Qoder run with a bent entry pattern scored FAIL.

Before each batch run `harness/run-fix.sh <case> grade-only base gradeonly-base` and the same with `ref`. Base must stay red
(Qoder green) and ref must stay green, or the vendor side has moved. The 2026-10-14 validation is in `results/validation-2026-10-14.yml`.

## Running

```
harness/run-fix.sh fix-qoder haiku high haiku-high            # neutral brief
harness/run-fix.sh fix-qoder haiku high haiku-high-g guided   # + this session's hints (fix-hints/)
python3 harness/score-fix.py -v
```

Paths come from `../onboarding/harness/env.sh`: the clone, logs and `scores-fix.json` go to the work
directory `$BENCH_ROOT` (default `~/duo-updater-bench`), runs as `runs/<case>-<tag>` beside the onboarding
ones, and `mkclone.sh` is the onboarding harness's. Set `BENCH_ROOT` for `score-fix.py` too. The issue
texts the brief embeds are in `cases/issues/`.

The neutral brief (`harness/brief-fix.md`) contains the issue text, the repo's rules and the verdict.json contract.
It does NOT include the candidate causes or the line "if the vendor hasn't published, change nothing". Guided mode
appends those hints (`harness/fix-hints/<case>.md`), which reproduces the briefs from the 2026-10-14 session.
`gh` is denied (the issues and PRs are public and hold the answer). Use the `LEAK` flag for WebFetch.

## Baseline: 2026-10-14 session (Haiku @high, guided, in the real repo, not this harness)

| case | outcome | tool calls | min | tokens |
|---|---|---|---|---|
| fix-qoder | no-change, correct; also suggested bumping the ack to 1.32.0 (not applied) | 40 | 5.5 | 127k |
| fix-longbridge | both fixed (#1294), review 0 blocking | 85 | 18 | 263k |
| fix-trim | #1254 fixed, #1253 acknowledged (user confirmed) (#1295), review 0 blocking | 80 | 21 | 200k |

No forbidden commands. Most errors were worktree-isolation refusals that the agent retried. Cost in USD was not captured.
