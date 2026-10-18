# Onboarding benchmark

How well does a given model, effort level or agent setup onboard an app that ships through
GitHub Releases into DuoUpdater? This directory holds the harness, the tasks, the results
so far and the evidence behind them, so the comparison can be repeated when a new model ships.

Results are a dated snapshot, not a reproducible number. See [Limits](#limits).

## The task

Each case (`cases/<app>.json`) is an app this repository has already onboarded. A run:

1. clones this repository at the commit **before** that onboarding (`parent`), with no later
   history, so the merged answer can't be read from git (`harness/mkclone.sh`);
2. gives an agent the same brief a person would (`harness/brief.md`): track the app,
   with detection, one-click install and a structured changelog;
3. records the commits, runs `make test`, and grades the result by running the
   production update sources against an old and a new installed version of the app
   (`harness/ZZBenchGrade.swift`, copied into the Core test target for the run only;
   `ZZBenchGradeLegacy.swift` for bases that lack APIs the current grader uses).

The reference is main's own onboarding (`ref/main`, a clone of main), graded the same way.
A run is then judged on:

- `vs_main`: does the graded behaviour (status, source, download, one-click kind,
  changelog pane, and how each published release is read) match main's? `DIFF(n)` counts
  the fields and releases that differ.
- `probe`: does the stable rule's version pattern still read the vendor's next tag, and
  reject an rc/beta tag the vendor forgets to flag (`harness/probe.py`)?
- by hand, for the seven hard apps: which groups of installed copies main covers that the
  run missed, and what it did beyond main (`results/hard7-coverage.yml`), from the run's
  diff, grade and the old-id grade (below). The evidence is in `results/evidence/`.

Two cases are extra grades, not onboarding tasks: `fastpotify` grades an installed copy on
Spotifast's pre-rename bundle id (`harness/grade-oldid.sh`, `TREES=` the trees to grade),
and `cindycn` the Cindy cn edition. Neither has a job of its own.

## Results so far (2026-10-13/14, Claude Code 2.1.296)

| Round | What | Finding |
|---|---|---|
| 1-2 | 9 simple apps; Haiku, Sonnet, Opus 5.5 at high; Haiku at xhigh and max | All correct today. Haiku xhigh fixed the one future-tag miss; max only cost more. |
| 3 | Haiku xhigh on 21 past onboardings | 7 fell short of main, all omissions (no wrong installs) that `make test`, the probe and the grader can't see. |
| 4 | Those 7 hard apps: Opus/Sonnet xhigh, Haiku xhigh with a fuller brief | Same brief: Opus > Sonnet > Haiku. The fuller brief let Haiku close 5 gaps but overreach on 2. |
| 5 | Those 7: Opus medium single agent, and two multi-agent pipelines (twice for A) | Below. |
| 6 | 6 past onboardings no prompt was written from: Opus medium with and without the app-audit coverage checklist | Below. |

The seven hard apps, rounds 4 and 5 (`results/hard7-coverage.yml`):

| Configuration | Round | Missed vs main | Overreach | Probe errors | Mean cost | Mean time |
|---|---|---|---|---|---|---|
| Opus 5.5 medium, single agent | 5 | 2 | 0 | 1 | $3.36 | 16 min |
| Opus 5.5 xhigh, single agent | 4 | 3 | 0 | 1 | $7.97 | 26 min |
| Pipeline A (Sonnet + Haiku subagent, Opus review, Sonnet fix), repetition 1 | 5 | 3 | 0 | 0 | $5.12 | 32 min |
| Pipeline A, repetition 2 (with the ditto note) | 5 | 2 | 2 | 2 | $5.49 | 36 min |
| Pipeline B (A plus an Opus plan) | 5 | 4 | 1 | 0 | $9.76 | 49 min |

"Probe errors" counts probe hits not already counted as a miss: OpenInTerminal pinned to
v2 is a miss (it won't see v3.0.0), so its NEXT-MISS isn't counted again. That is why
`runs.yml` shows one more probe hit than this table for some pipeline runs.

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

### The production review, replayed (`results/review-replay.yml`)

The workflow's own review (`.github/claude-review/full.md` and `REVIEW.md` at main
`57a2e88e`, Opus 5.5, the workflow's tool allowlist) on the seven Opus-medium onboardings:

| Review effort | Expected problems caught | Other true findings | False positives | Cost (7 reviews) | Mean time |
|---|---|---|---|---|---|
| high (the workflow's setting until #1301) | 1 of 4 | 2 | 0 | $8.85 | 2.9 min |
| xhigh (the workflow's setting since #1301) | 2 of 4 | 3 | 0 | $17.43 | 6.3 min |

xhigh added Secretive's nightly downgrade and a wrong SHA-256 in an audit, at twice the cost.
Neither effort caught the Settings text that names the digest-only apps; `REVIEW.md` has
no check for it. At high, 2 of 7 reviews had the write to `review.md` refused and returned
the review only as text. Both had `cd`'d into a subdirectory first, and the workflow's
`Edit(./.claude-review/review.md)` is relative to the current directory; the same failure
then hit the workflow itself on #1301. The rule is absolute now (`claude-review.yml`).

### The app-audit coverage checklist, held out (`results/holdout6-skill-ab.yml`)

Gaps like round 3's can be prevented while the onboarding is written instead of hoped for in
review. `harness/skill/coverage-checklist.md` lists the groups of installed copies to settle
first; it names no app. Because it (like `brief2.md`) came from the seven hard apps, it was
tested on six other past onboardings, each covering one hard category on main. Opus 5.5
medium, `brief.md`, the clone's own `app-audit` with and without the checklist
(`SKILL=1 run.sh single …`), two runs per arm:

| App | Hard item main covers | Without | With |
|---|---|---|---|
| SwiftVM | beta track | 2/2 | 2/2 |
| PdfCraft | copies on the pre-rename id | 1/2 | 2/2 |
| Tinycast | beta under its own bundle id | 2/2 | 2/2 |
| Cua Driver | nightly track | 0/2 | 0/2 |
| WhatCable | beta track | 1/2 | 2/2 |
| T3 Code | nightly track | 0/2 | 2/2 |
| **Total** | | **6/12** | **10/12** |
| WhatCable | pre-rename id `com.bitmoor.whatcable`, which main lacks | 0/2 | 2/2 |

No overreach in either arm; $4.92 → $5.69 and 17.8 → 19.1 min a run. Both arms missed Cua
Driver's nightly track, whose signal is a file outside the bundle while the checklist's
examples are all inside it; rewording it from this answer would need a new held-out set.
#1308 puts the checklist into `.claude/skills/app-audit/SKILL.md`, with one line changed
after the test (keeping a sibling out, now as `REVIEW.md` says).

Every run, with its configuration and cost per stage: `results/runs.yml`.

## Trap set (`trap7`, added 2026-10-17, not run yet)

Seven apps from the 2026-10-16 awesome-mac batch (#1358) whose correct answer hangs on one
trap. Easy apps don't separate configurations (rounds 1-2 were all correct); these were
picked because each has a specific way to get it wrong, and each answer was checked on a
real Mac. All seven start from the commit before #1358 (`577239fa`) and are graded against
#1358 (`9c1f721e`); none of their recipes changed after it.

| Case | The trap | Main's answer (reference grade) |
|---|---|---|
| `loop` | Dev builds report `🧪 1.4.3`; the dev release's tag is always `prerelease` | 1.4.1 → 1.4.2 through GitHub; the dev copy (`loop-dev`) is `dev`, no update |
| `cork` | corkmac.app answers every other request with its home page (deliberate, buresdv/Cork#687); GitHub releases lag the site (2.0.3 is a tag only); old ids `com.davidbures.cork` / `.Cork` | 2.0.2 → 2.0.3 from the `/RLS/` index, zip one-click, blog changelog; `cork-oldid` 1.5.7 → 2.0.3. Main reads the vendor's `releases.json` since 2026-10-18 (#1413); `/RLS/` now answers every other request with a 403 |
| `switchhosts` | Old id `SwitchHosts` up to 4.2.0; a beta track; a nested SMAppService root helper | 5.0.1 → 5.0.2, dmg; `switchhosts-oldid` 4.2.0 → 5.0.2 |
| `picard` | Old id `org.musicbrainz.picard` (2.0.x); betas are `release-3.0.0rc4` | 3.0.1 → 3.0.2, dmg, changelog recipe; `picard-oldid` 2.0.4 → 3.0.2 |
| `zettlr` | Beta choice in `config.json` (`checkForBeta`); nightly builds read `4.8.0+nightly` | 4.7.0 → 4.8.0, dmg; `zettlr-nightly` is `nightly`, no update |
| `krita` | Two lines shipped side by side (5.x for work, 6.x experimental); vendor site, not GitHub; nightly only visible in `CFBundleLongVersionString` | 5.3.3 → 5.3.4 (`krita-5.3.4.1-signed.dmg`); `krita6` 6.0.3 → 6.0.4, not pushed to 5.x or the other way |
| `snipaste` | Closed source, versions from the website's JSON; `-Beta` in old dmg names is naming, not a track | 2.11.2 → 2.11.3, dmg, Markdown changelog |

The `-oldid`, `-dev`, `-nightly` and `krita6` cases are extra grades (`"extra": true`, like
`fastpotify` and `cindycn`): no job of their own, graded with
`CASE=<case> TREES=runs/<run>/repo harness/grade-oldid.sh`. `loop-dev` and `zettlr-nightly` set
`detectChannel`, so the grader gives the synthesized copy the channel production's scan
would read from its version, instead of `stable`. Graded with detection off, both are pushed
to stable (`🧪 1.4.3` → 1.4.2, `4.8.0+nightly` → 4.8.0): that is what a run that misses the
trap looks like.

Checked before adding: on main every case grades as above (`results/evidence/_reference-trap7/`),
and at `577239fa` every case is `unknown` with no source, so each is a real task.

Cork, Krita and Snipaste aren't read from GitHub. Their `owner`/`repo` are the vendor's
GitHub presence (`buresdv/Cork`, `KDE/krita`, `Snipaste/feedback`), which is the URL the
brief names; finding the real source is part of the task. Their `perRelease` rows are
meaningless, and `probe.py` has no entries for them.

## Running it

Needs macOS with Xcode (Swift 6.4 here), Claude Code, `gh` logged in, and a Python ≥ 3.10
(`BENCH_PYTHON`, default `python3.14`): bases before 2026-10-11 call a bare `python3` in
their Makefile, which is 3.9 on macOS, and the harness puts this one first on `PATH`.

```bash
export BENCH_ROOT=~/duo-updater-bench     # work directory, outside the repo: tens of GB
export DUO_REPO=$(git rev-parse --show-toplevel)   # default: this checkout

# the reference: main, graded the same way. Once, and again when vendors release.
bench/onboarding/harness/mkclone.sh "$BENCH_ROOT/ref/main" "$(git rev-parse origin/main)"
bench/onboarding/harness/grade-refs.sh            # every case, one at a time

BENCH_ROUND=6 bench/onboarding/run.sh single claude-opus-5-5 medium hard7   # one agent per app
BENCH_ROUND=6 bench/onboarding/run.sh pipe A 3 hard7                         # pipeline A, repetition 3
bench/onboarding/run.sh replay opus-medium xhigh hard7  # production review (the workflow runs xhigh)
bench/onboarding/run.sh score                           # vs main
bench/onboarding/run.sh probe                           # next-tag probe
bench/onboarding/run.sh export                          # merge into results/runs.yml
```

`run.sh single` names runs `<model>-<effort>` (`opus-medium`); set `TAG` for another name.
Pipelines get `harness/ditto-note.md` unless `DITTO_NOTE=` (empty) is set, which reproduces
repetition 1. Runs land in `$BENCH_ROOT/runs/<case>-<tag>/`: transcript, `config.json`,
per-stage costs, diff, `make test` log, grade.

`rounds/` has the job lists of rounds 1-5, in the format `harness/run-mixed.sh` reads
(`single <case> <model> <effort> <tag> <brief>` or `pipe <case> <A|B> <tag>`). Round 5's
pipeline A rerun (`round5-hard7-pipeA-rerun.txt`) ran with `DITTO_NOTE=1`.

Keep `PAR` at 3 or below. The GitHub token has an hourly window that `gh api rate_limit`
doesn't show, and five agents in parallel emptied it; grading then fails with "rate limit
reached". Grade references and re-grades one at a time.

### What decides a result, and where it is recorded

| Input | Where |
|---|---|
| Model and effort, per stage and for the pipeline's subagent | `config.json` of each run; `config` in `runs.yml` |
| Brief and prompts | `harness/*.md`; which ones in `config.brief` / `ditto_note` |
| Permission mode, denied tools, environment | `config.json`; for 2026-10 runs, the scripts at this commit |
| Claude Code version | `claude_code` in `runs.yml` (from the transcript) |
| Starting commit, vendor repository | `cases/<app>.json` |
| Reference commit and the day it was graded | `reference_commit`, `reference_graded` in `runs.yml` |
| Grader | `grader` in `runs.yml` |

Two differences between the runners are deliberate and recorded: single-agent runs unset
only `CLAUDE_EFFORT`; pipeline stages also unset `CLAUDE_CODE_EFFORT_LEVEL` and set
`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` (so a stage waits for its subagents). Neither
runner passes `--setting-sources`, so the runner's own `~/.claude` settings, `CLAUDE.md`
and skills load: a run on another machine has a different context. Whether the
subagent's `"effort": "xhigh"` in `--agents` is honoured is not visible in the transcript.

### Evaluating a new model

Run it on `hard7` (and `simple9` if the change is large) at the effort you would use, with
`BENCH_ROUND` set, score, probe and export it, and classify each app in
`results/hard7-coverage.yml` the way earlier configurations are, from the run's diff and
grade. Run it twice before reading anything into a difference of one or two items.
Commit `results/runs.yml`, the classification and the run's evidence (`diff.patch`,
`grade.json`, `costs.json`, `review.md`, `gitlog.txt`, with local paths replaced), on a
`bench/` branch.

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
- **Evidence is kept for the seven hard apps and the six held-out ones only** (plus the
  trap set's reference grades). Transcripts and
  the other runs' diffs stay in the work directory (vendor content, size).

## In this repository

A pull request that only touches `bench/` skips the three macOS CI jobs (`ci.yml`, `route`),
and the required `test` check still reports. A branch named `bench/…` skips the Claude
review: use it for result-only pull requests, and any other name for harness changes.
