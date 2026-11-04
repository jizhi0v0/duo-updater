#!/usr/bin/env python3
"""Wake the cloud handler after CI, review or required evidence checks finish.

This runs from the default branch on workflow_run, never from PR code or an
artifact. It only publishes run metadata for an open PR with the same head.
The comment contains no @codex mention and cannot request a duplicate review.
"""
import argparse
import json
import os
import re
import subprocess

from check_codex_review import api

PR_WORKFLOWS = {
    ".github/workflows/ci.yml": "CI",
    ".github/workflows/real-machine.yml": "Real-machine record",
    ".github/workflows/adversarial-review.yml": "Adversarial review record",
}
GATE_PATH = ".github/workflows/codex-review-gate.yml"
WORKFLOW_LABELS = {**PR_WORKFLOWS, GATE_PATH: "Codex review gate"}


def is_pr_completion(run):
    return (run.get("status") == "completed"
            and ((run.get("event") == "pull_request"
                  and run.get("path") in PR_WORKFLOWS)
                 or (run.get("event") == "pull_request_target"
                     and run.get("path") == GATE_PATH)))


def targets(run, associated=None):
    if not is_pr_completion(run):
        return []
    return [p["number"] for p in (associated if associated is not None else run.get("pull_requests", []))
            if isinstance(p.get("number"), int) and p["number"] > 0]


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
    attempt = run.get("run_attempt")
    if type(attempt) is not int or attempt < 1:
        raise ValueError("invalid workflow attempt")
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
        comments = api(f"repos/{args.repo}/issues/{number}/comments")
        if any(c.get("user", {}).get("login") == "github-actions[bot]"
               and c.get("body", "").startswith(marker) for c in comments):
            continue
        body = (f"{marker}\n{WORKFLOW_LABELS[run['path']]} attempt {attempt} completed for `{head}`: "
                f"**{run.get('conclusion', 'unknown')}**.\n\n"
                f"[Workflow run](https://github.com/{args.repo}/actions/runs/{args.run}). "
                "The cloud PR handler must re-read current review, CI and real-machine "
                "validation state before taking any merge action.")
        subprocess.run(["gh", "api", "--method", "POST",
                        f"repos/{args.repo}/issues/{number}/comments", "--input", "-"],
                       input=json.dumps({"body": body}), text=True,
                       check=True, capture_output=True)
        print(f"Posted completion metadata to PR #{number}.")


if __name__ == "__main__":
    main()
