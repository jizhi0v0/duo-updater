# Onboarding benchmark

How well does a given model, effort level or agent setup onboard an app that ships through
GitHub Releases into DuoUpdater? This directory holds the harness, the tasks and the results
so far, so the comparison can be repeated when a new model ships.

Results are a dated snapshot, not a reproducible number. See [Limits](#limits).

## The task

Each case (`cases/<app>.json`) is an app this repository has already onboarded. A run:

1. clones this repository at the commit **before** that onboarding (`parent`), with no later
   history, so the merged answer can't be read from git (`harness/mkclone.sh`);
2. gives an agent the same brief a person would (`harness/brief.md`): track the app,
   with detection, one-click install and a structured changelog;
3. records the commits, runs `make test`, and grades the result by running the
   production update sources against an old and a new installed version of the app
   (`harness/ZZBenchGrade.swift`, copied into the Core test target for the run only).

The reference is main's own onboarding, graded the same way. A run is then judged on:

- `vs_main`: did the graded behaviour (status, source, download, one-click kind,
  changelog) match main's?
- `probe`: does the stable rule's version pattern still read the vendor's next tag, and
  reject an rc/beta tag the vendor forgets to flag (`harness/probe.py`)?
- by hand, for the seven hard apps: which groups of installed copies main covers that
  the run missed, and what it did beyond main (`results/hard7-coverage.yml`).

## Results so far (2026-10-13/14, Claude Code 2.1.296)

| Round | What | Finding |
|---|---|---|
| 1-2 | 9 simple apps; Haiku, Sonnet, Opus 5.5 at high; Haiku at xhigh and max | All correct today. Haiku xhigh fixed the one future-tag miss; max only cost more. |
| 3 | Haiku xhigh on 21 past onboardings | 7 fell short of main, all omissions (no wrong installs) that `make test`, the probe and the grader can't see. |
| 4 | Those 7 hard apps: Opus/Sonnet xhigh, Haiku xhigh with a fuller brief | Same brief: Opus > Sonnet > Haiku. The fuller brief let Haiku close 5 gaps but overreach on 2. |
| 5 | Those 7: Opus medium single agent, and two multi-agent pipelines (twice for A) | Below. |

Round 5, the seven hard apps (`results/hard7-coverage.yml`):

| Configuration | Missed vs main | Overreach | Probe errors | Mean cost | Mean time |
|---|---|---|---|---|---|
| Opus 5.5 medium, single agent | 2 | 0 | 1 | $3.36 | 16 min |
| Opus 5.5 xhigh, single agent | 3 | 0 | 1 | $7.97 | 26 min |
| Pipeline A (Sonnet + Haiku subagent, Opus review, Sonnet fix), run 1 | 3 | 0 | 0 | $5.12 | 32 min |
| Pipeline A, run 2 | 2 | 2 | 2 | $5.49 | 36 min |
| Pipeline B (A plus an Opus plan) | 4 | 1 | 0 | $9.76 | 49 min |

What it says, with seven apps and one or two runs each:

- **Opus medium as a single agent is the default to beat**: cheapest, fastest, fewest misses.
- **The same configuration run twice differed on 4 of 7 apps.** Gaps between configurations
  this small are within that noise.
- **An Opus review catches what single agents miss** (Spotifast's pre-rename id twice, the
  Lokii Settings copy twice, Cindy's cn edition), **and can make things worse**: it called
  scope main doesn't have blocking, and the fix pinned a correct version pattern to v2.
- **A plan is not an implementation.** Pipeline B's plan had Spotifast's old id right; the
  executor didn't build it and the plan-checking review let it pass.
- **Tell the agent what the harness blocks.** With `ditto` denied and no word on what to use
  instead, Sonnet stopped rather than "work around a permission decision" in 3 of 14
  pipeline runs; single agents switched to `unzip`. `harness/ditto-note.md` fixed it.

Every run, with cost per stage for the pipelines: `results/runs.yml`.

## Running it

Needs macOS with Xcode (Swift 6.4 here), Claude Code, `gh` logged in, and Python ≥ 3.10.

```bash
export BENCH_ROOT=~/duo-updater-bench     # work directory, outside the repo: tens of GB
export DUO_REPO=$(git rev-parse --show-toplevel)   # default: this checkout

# the reference: main, graded the same way (once, and again when vendors release)
bench/onboarding/harness/mkclone.sh "$BENCH_ROOT/ref/main" "$(git rev-parse origin/main)"
mkdir -p "$BENCH_ROOT/ref/out" && bench/onboarding/harness/grade-refs.sh secretive obelisk  # …

bench/onboarding/run.sh single claude-opus-5-5 medium hard7   # one agent per app
bench/onboarding/run.sh pipe A 3 hard7                         # pipeline A, repetition 3
bench/onboarding/run.sh replay opus-medium high hard7          # production review on those runs
bench/onboarding/run.sh score                                  # vs main
bench/onboarding/run.sh probe                                  # next-tag probe
bench/onboarding/run.sh export                                 # results/runs.yml
```

Runs land in `$BENCH_ROOT/runs/<case>-<tag>/`: transcript, per-stage costs, diff, `make test`
log, grade. `rounds/` has the exact job lists of rounds 1-5.

Keep `PAR` at 3 or below. The GitHub token has an hourly window that `gh api rate_limit`
doesn't show, and five agents in parallel emptied it; grading then fails with "rate limit
reached". Grade references and re-grades one at a time.

### Evaluating a new model

Run it on `hard7` (and `simple9` if the change is large) at the effort you would use, score
it, and classify each app in `results/hard7-coverage.yml` the way earlier configurations
are. Run it twice before reading anything into a difference of one or two items. `run.sh
export` then rewrites `results/runs.yml`; commit it with the classification.

## Limits

- **Not reproducible to the number.** The models are non-deterministic (see above), vendors
  keep releasing (Lokii and Spotifast both shipped during round 5, which shifts the
  reference), and main keeps changing. Compare distributions, not single runs.
- **Selection bias.** The seven hard apps were picked from Haiku's failures, and several
  `REVIEW.md` checks were written from these same failures, so a reviewer replayed on them
  looks better than it would on a new app.
- **The grader reads live GitHub.** A run graded on a different day can differ only because
  the vendor released.
- **The brief is part of the result.** Omissions mostly came from facts the brief didn't
  state; a better brief moves every configuration.

## In this repository

A pull request that only touches `bench/` skips the three macOS CI jobs (`ci.yml`, `route`),
and the required `test` check still reports. A branch named `bench/…` skips the Claude
review: use it for result-only pull requests, and any other name for harness changes.
