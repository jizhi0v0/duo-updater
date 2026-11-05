#!/usr/bin/env python3
"""Wake the cloud handler after CI, review or required evidence checks finish.

This runs from the default branch on workflow_run, never from PR code or an
artifact. It only publishes run metadata for an open PR with the same head.
One rolling bot comment is edited for each new completion, preserving comment
events for the cloud handler without adding conversation replies. It contains
no @codex mention and cannot request a duplicate review.
"""
import argparse
import json
import os
import re
import subprocess

from check_codex_review import api
from route_cloud_pr import MANAGED, is_scan_state, labels

PR_WORKFLOWS = {
    ".github/workflows/ci.yml": "CI",
    ".github/workflows/real-machine.yml": "Real-machine record",
    ".github/workflows/adversarial-review.yml": "Adversarial review record",
}
GATE_PATH = ".github/workflows/codex-review-gate.yml"
WORKFLOW_LABELS = {**PR_WORKFLOWS, GATE_PATH: "Codex review gate"}


def workflow_path(run):
    # GitHub returns both bare paths and paths qualified with @workflow-ref.
    return (run.get("path") or "").split("@", 1)[0]


def is_pr_completion(run):
    return (run.get("status") == "completed"
            and ((run.get("event") == "pull_request"
                  and workflow_path(run) in PR_WORKFLOWS)
                 or (run.get("event") == "pull_request_target"
                     and workflow_path(run) == GATE_PATH)))


def targets(run, associated=None):
    if not is_pr_completion(run):
        return []
    return [p["number"] for p in (associated if associated is not None else run.get("pull_requests", []))
            if isinstance(p.get("number"), int) and p["number"] > 0]


SUMMARY = "<!-- cloud-pr-wakeup:v3 "
CONCLUSIONS = {"success", "failure", "cancelled", "timed_out", "action_required",
               "neutral", "skipped", "stale", "startup_failure"}


def positive(value):
    return type(value) is int and value > 0


def rolling_comment(comments):
    # Only our bot's own comments can be reused. Migrate the newest v2 wakeup
    # rather than creating one more comment on an already noisy conversation.
    owned = [c for c in comments if c.get("user", {}).get("login") == "github-actions[bot]"
             and positive(c.get("id"))]
    current = [c for c in owned if c.get("body", "").startswith(SUMMARY)]
    legacy = [c for c in owned if c.get("body", "").startswith("<!-- cloud-pr-wakeup:v2 ")]
    if current:
        return min(current, key=lambda c: c["id"])
    return max(legacy, key=lambda c: c["id"]) if legacy else None


def read_checks(comment, head):
    # Invalid/old metadata is repaired in place, never treated as authority to
    # suppress future wakeups. Four fixed workflow paths bound the stored state.
    if not comment:
        return {}
    match = re.match(r"<!-- cloud-pr-wakeup:v3 (.*?) -->", comment.get("body", ""))
    try:
        state = json.loads(match[1]) if match else {}
        checks = state.get("checks")
        if state.get("head") != head or not isinstance(checks, dict):
            return {}
        return {path: {key: row[key] for key in ("run", "number", "attempt", "conclusion")}
                for path, row in checks.items()
                if path in WORKFLOW_LABELS and isinstance(row, dict)
                and all(positive(row.get(k)) for k in ("run", "number", "attempt"))
                and row.get("conclusion") in CONCLUSIONS}
    except (ValueError, AttributeError, TypeError):
        return {}


def summary_body(repo, head, checks, marker):
    state = json.dumps({"head": head, "checks": checks}, separators=(",", ":"), sort_keys=True)
    lines = [f"{SUMMARY}{state} -->", marker, "### PR automation status", "",
             f"Commit: `{head}`", "", "| Check | Result | Workflow run |", "| --- | --- | --- |"]
    for path, label in WORKFLOW_LABELS.items():
        if path in checks:
            row = checks[path]
            url = f"https://github.com/{repo}/actions/runs/{row['run']}"
            lines.append(f"| {label} | **{row['conclusion']}** | [attempt {row['attempt']}]({url}) |")
    lines += ["", "This status comment is updated in place to wake the cloud PR handler. "
              "It is not approval; the handler rechecks the current head, review, CI and holds."]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--run", type=int, required=True)
    args = parser.parse_args()
    if (not args.repo or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo)
            or args.run < 1):
        parser.error("valid repository and workflow run ID required")
    run = api(f"repos/{args.repo}/actions/runs/{args.run}")
    if not is_pr_completion(run):
        return
    head = run.get("head_sha", "")
    if run["event"] == "pull_request_target":
        # The trusted workflow supplies the PR number/head in its fixed title.
        # Do not infer either from the mutable name or workflow SHA semantics.
        match = re.fullmatch(r"Codex review gate PR #([1-9][0-9]*) @([0-9a-f]{40})",
                             run.get("display_title", ""))
        if not match:
            raise ValueError("invalid trusted review run title")
        numbers, head = [int(match[1])], match[2]
    else:
        numbers = targets(run)
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("invalid workflow head")
    attempt, number = run.get("run_attempt"), run.get("run_number")
    if not positive(attempt) or not positive(number):
        raise ValueError("invalid workflow attempt or number")
    if run.get("conclusion") not in CONCLUSIONS:
        raise ValueError("invalid completion conclusion")
    marker = f"<!-- cloud-pr-wakeup:v2 run={args.run} attempt={attempt} -->"
    # GitHub can leave workflow_run.pull_requests empty even for this repo's
    # own PR runs. Resolve the exact head's associated PRs rather than losing
    # the completion event. Each candidate is checked live below.
    if not numbers and run["event"] == "pull_request":
        numbers = targets(run, api(f"repos/{args.repo}/commits/{head}/pulls"))
    # Fork commits need not have an association in the base repository.
    # Match all three fields; a same-named branch in another fork is unrelated.
    if not numbers and run["event"] == "pull_request":
        run_repo = (run.get("head_repository") or {}).get("full_name")
        run_branch = run.get("head_branch")
        if run_repo and run_branch:
            candidates = api(f"repos/{args.repo}/pulls?state=open&per_page=100")
            numbers = [p["number"] for p in candidates
                       if p.get("head", {}).get("sha") == head
                       and p["head"].get("ref") == run_branch
                       and (p["head"].get("repo") or {}).get("full_name") == run_repo]
    for number in numbers:
        pr = api(f"repos/{args.repo}/pulls/{number}")
        if pr["state"] != "open" or pr.get("draft") or pr["head"]["sha"] != head:
            continue
        # The trigger filters before a model starts. Do not create redundant
        # wakeup comments for unlabelled PRs or pure scan state (even if a
        # routing label was copied onto it). CI failures remain visible in GitHub.
        if MANAGED not in labels(pr) or is_scan_state(pr, args.repo, read=api):
            continue
        comments = api(f"repos/{args.repo}/issues/{number}/comments")
        if any(c.get("user", {}).get("login") == "github-actions[bot]"
               and c.get("body", "").startswith(marker) for c in comments):
            continue
        comment = rolling_comment(comments)
        checks = read_checks(comment, head)
        path = workflow_path(run)
        previous = checks.get(path)
        if previous and (previous["number"], previous["attempt"]) >= (run["run_number"], attempt):
            continue
        checks[path] = {"run": args.run, "number": run["run_number"], "attempt": attempt,
                        "conclusion": run["conclusion"]}
        body = summary_body(args.repo, head, checks, marker)
        method = "PATCH" if comment else "POST"
        endpoint = (f"repos/{args.repo}/issues/comments/{comment['id']}" if comment
                    else f"repos/{args.repo}/issues/{number}/comments")
        subprocess.run(["gh", "api", "--method", method, endpoint, "--input", "-"],
                       input=json.dumps({"body": body}), text=True,
                       check=True, capture_output=True)
        print(f"Updated completion metadata for PR #{number}.")


if __name__ == "__main__":
    main()
