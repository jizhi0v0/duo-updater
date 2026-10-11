#!/usr/bin/env python3
"""Pick the runner for CI's three macOS jobs: the mini, or a GitHub-hosted Mac.

    python3 scripts/ci_route.py >> "$GITHUB_OUTPUT"

Prints `runner=<JSON>` for `runs-on: ${{ fromJSON(needs.route.outputs.runner) }}`,
and a one-line reason on stderr.

Why this exists: a `runs-on` names ONE set of labels, and a job waits for a runner
that has all of them; GitHub has no "whichever is free" across self-hosted and
hosted runners (checked against GitHub's "Choose the runner for a job" page,
2026-10-11). Since #1074 every pull request from this repository went to the
mini's two runners, so when several were open they queued there while the five
hosted macOS slots sat empty: from 2026-10-10 20:00 to 2026-10-11 02:00, PR jobs
on the mini waited 17 minutes on average and up to 58, and hosted jobs 0.1.

The rule, for a pull request from a branch of this repository: estimate when the
run would finish on each side and take the earlier, the mini on a tie. The mini is
faster per job but has two runners; the hosted Macs are slower but five. Medians
of successful jobs since 2026-10-08 (measured 2026-10-11):

               swift   app   release   one run, alone
    mini        4.6    1.8     6.6     ~6.6 min (two runners share three jobs)
    hosted      6.9    4.0    10.9     ~10.9 min (three in parallel, release last)

So an idle mini wins (6.6 < 10.9), a mini with two jobs ahead ties (and keeps the
run), and from three jobs ahead a hosted Mac with free slots finishes first.
Everything else (push to main, dispatch, a fork's pull request) stays hosted,
exactly as before. Anything that goes wrong reading the queue falls back to the
mini, which is what every same-repository pull request got before this.

The count is a snapshot, and it cannot see a run whose macOS jobs do not exist yet:
another run's jobs appear only once its own `route` job has finished. Two pull
requests pushed within that window both miss each other (measured 2026-10-11: two
runs 3 s apart both saw "mini 4 active" and both took the mini; the second waited
18.7 minutes there). The cost is that one of them queues on the mini, as all of
them did before this script.

Also not counted: macOS jobs of the owner's other repositories, which share the
five hosted slots (the limit is per account).
"""

import json
import os
import subprocess
import sys

MINI = ["self-hosted", "duo-mini"]
HOSTED = "xcode-27"
MINI_SLOTS = 2      # mini-duoupdater and mini-duoupdater-2
HOSTED_SLOTS = 5    # free plan: 5 concurrent macOS jobs (GitHub "Actions limits")
JOBS_PER_RUN = 3    # swift, app, release

# Minutes, from the table in the docstring.
MINI_JOB, MINI_RUN = 4.3, 6.6       # average job; one run's wall clock alone
HOSTED_JOB, HOSTED_RUN = 7.3, 10.9

ACTIVE = {"queued", "in_progress", "waiting", "pending", "requested"}


def is_mini(labels):
    return "duo-mini" in labels


def is_hosted_mac(labels):
    return any(label == HOSTED or label.startswith("macos") or label.startswith("xcode")
               for label in labels)


def choose(jobs):
    """`jobs`: (status, labels) for every job of the repository's other runs.
    Returns (runner, reason)."""
    active = [labels for status, labels in jobs if status in ACTIVE]
    mini = sum(1 for labels in active if is_mini(labels))
    hosted = sum(1 for labels in active if is_hosted_mac(labels))
    # Jobs ahead drain through the slots at one average job each; then this run.
    on_mini = mini / MINI_SLOTS * MINI_JOB + MINI_RUN
    on_hosted = max(0, hosted + JOBS_PER_RUN - HOSTED_SLOTS) / HOSTED_SLOTS * HOSTED_JOB + HOSTED_RUN
    detail = (f"mini {mini} active / {MINI_SLOTS} slots ~{on_mini:.1f} min, "
              f"hosted {hosted} active / {HOSTED_SLOTS} slots ~{on_hosted:.1f} min")
    # Rounded so that a tie is a tie, not a float artefact.
    if round(on_hosted, 1) < round(on_mini, 1):
        return HOSTED, f"hosted finishes first ({detail})"
    return MINI, f"mini finishes first or ties ({detail})"


def gh(path):
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True,
                         check=True, timeout=30).stdout
    return json.loads(out)


def active_runs(repo, this_run, fetch=None):
    """Run ids from the five status lists, each once. A run that changes status
    between two of the list requests (queued, then in_progress) is in both."""
    fetch = fetch or gh
    seen = []
    for status in ("queued", "in_progress", "waiting", "pending", "requested"):
        for run in fetch(f"repos/{repo}/actions/runs?status={status}&per_page=100")["workflow_runs"]:
            if run["id"] != this_run and run["id"] not in seen:
                seen.append(run["id"])
    return seen


def active_jobs(repo, this_run):
    jobs = []
    for run in active_runs(repo, this_run):
        for job in gh(f"repos/{repo}/actions/runs/{run}/jobs?per_page=100")["jobs"]:
            jobs.append((job["status"], job.get("labels") or []))
    return jobs


def main():
    if os.environ.get("SAME_REPO_PR") != "true":
        runner, reason = HOSTED, "not a pull request from this repository"
    else:
        try:
            runner, reason = choose(active_jobs(os.environ["GITHUB_REPOSITORY"],
                                                int(os.environ["GITHUB_RUN_ID"])))
        except Exception as error:  # noqa: BLE001 — any failure keeps the old route
            runner, reason = MINI, f"could not read the queue ({error!r}); the mini, as before"
    print(f"runner={json.dumps(runner)}")
    print(f"route: {json.dumps(runner)} — {reason}", file=sys.stderr)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as out:
            out.write(f"Runner: `{json.dumps(runner)}` — {reason}\n")


if __name__ == "__main__":
    main()
