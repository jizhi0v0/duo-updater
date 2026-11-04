#!/usr/bin/env python3
"""Wake the GitHub-event cloud handler after CI or the review gate finishes.

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


def is_pr_completion(run):
    if run.get("status") != "completed":
        return False
    name, event = run.get("name"), run.get("event")
    return ((name == "CI" and event == "pull_request")
            or (name == "Codex review gate" and event == "pull_request_target"))


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
    head = run.get("head_sha", "")
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        raise ValueError("invalid workflow head")
    marker = f"<!-- cloud-pr-wakeup:v1 run={args.run} -->"
    numbers = targets(run)
    # GitHub can leave workflow_run.pull_requests empty even for this repo's
    # own PR runs. Resolve the exact head's associated PRs rather than losing
    # the completion event. Each candidate is checked live below.
    if not numbers and is_pr_completion(run):
        numbers = targets(run, api(f"repos/{args.repo}/commits/{head}/pulls"))
    # Fork commits need not have an association in the base repository.
    # Match all three fields; a same-named branch in another fork is unrelated.
    if not numbers and is_pr_completion(run):
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
        body = (f"{marker}\n{run['name']} completed for `{head}`: "
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
