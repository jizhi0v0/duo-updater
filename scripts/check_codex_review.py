#!/usr/bin/env python3
"""Wait for the official Codex bot's clean review of this PR's current head.

The required `codex-review` check holds ordinary auto-merge while the cloud
review is running. A trusted pull_request_target workflow publishes the check
on the PR head through a separate status-publisher App. No PR code or model runs.
An unavailable or malformed receipt never passes. After a same-commit review
retry, rerun this check; a pushed fix starts a new check automatically.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

BOT = "chatgpt-codex-connector[bot]"
HEADER = "<!-- codex-pull-request-review-summary -->"
RECEIPT = re.compile(r"<!-- codex-review-state:v1 (.*?) -->")


def verdict(comments, head):
    """Return (pending|success|failure, reason) from the newest bot summary."""
    summaries = [c for c in comments
                 if c.get("user", {}).get("login") == BOT
                 and c.get("body", "").startswith(HEADER)]
    if not summaries:
        return "pending", "No official Codex review receipt yet."
    latest = max(summaries, key=lambda c: c.get("id", 0))
    match = RECEIPT.search(latest["body"])
    try:
        review = json.loads(match.group(1))["code_review"] if match else {}
    except (ValueError, KeyError, TypeError):
        return "pending", "Codex review receipt could not be validated."
    if not isinstance(review, dict) or review.get("commit_sha") != head:
        return "pending", "Codex has not reviewed the current head commit."
    if review.get("status") != "completed":
        return "pending", "Codex review has not completed."
    if (review.get("has_any_findings") is False
            and review.get("has_unresolved_findings") is False):
        return "success", "Codex completed this head with no findings."
    if (review.get("has_any_findings") is True
            or review.get("has_unresolved_findings") is True):
        return "failure", "Address the findings and obtain a clean Codex re-review."
    return "pending", "Codex has not reported an explicit clean result."


def api(path):
    result = subprocess.run(["gh", "api", "--paginate", "--slurp", path],
                            check=True, capture_output=True, text=True)
    pages = json.loads(result.stdout)
    if pages and isinstance(pages[0], list):
        return [item for page in pages for item in page]
    return pages[0]


def write_api(path, payload, method="POST"):
    token = os.environ.get("CODEX_REVIEW_STATUS_TOKEN")
    if not token:
        raise ValueError("isolated publisher token is required")
    result = subprocess.run(["gh", "api", "--method", method, path, "--input", "-"],
                            input=json.dumps(payload), check=True,
                            capture_output=True, text=True,
                            env={**os.environ, "GH_TOKEN": token})
    return json.loads(result.stdout)


def publish_status(args, state):
    """A commit status is distinct from a PR-controlled job with the same name."""
    description = {"pending": "Waiting for official Codex review",
                   "success": "Official Codex review is clean for this head",
                   "failure": "Review not approved; see the trusted gate run"}[state]
    for attempt in range(3):
        try:
            write_api(f"repos/{args.repo}/statuses/{args.head}",
                      {"context": "codex-review", "state": state,
                       "target_url": args.run_url, "description": description})
            return
        except subprocess.CalledProcessError:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def wait_for_review(args):
    deadline = time.monotonic() + args.timeout
    while True:
        pr = api(f"repos/{args.repo}/pulls/{args.pr}")
        if pr["state"] != "open" or pr["head"]["sha"] != args.head:
            print("PR closed or head changed; this check cannot approve it.", file=sys.stderr)
            return 1
        if any(label.get("name") == "needs-real-machine" for label in pr.get("labels", [])):
            print("Required real-machine validation is still on hold.", file=sys.stderr)
            return 1
        if pr.get("draft"):
            state, reason = "pending", "Draft PRs are not ready for automatic merge."
        else:
            state, reason = verdict(api(f"repos/{args.repo}/issues/{args.pr}/comments"), args.head)
        print(reason, flush=True)
        if state == "success":
            # A review result read during a concurrent push must not approve
            # a different head. Publication uses args.head explicitly, never
            # the target workflow's base SHA.
            current = api(f"repos/{args.repo}/pulls/{args.pr}")
            return 0 if (current["state"] == "open" and not current.get("draft")
                         and current["head"]["sha"] == args.head
                         and not any(label.get("name") == "needs-real-machine"
                                     for label in current.get("labels", []))) else 1
        if state == "failure" or time.monotonic() >= deadline:
            return 1
        time.sleep(min(args.interval, max(0, deadline - time.monotonic())))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--timeout", type=int, default=1500)
    parser.add_argument("--interval", type=int, default=20)
    parser.add_argument("--publish-check", action="store_true")
    parser.add_argument("--run-url")
    args = parser.parse_args()
    if (not args.repo or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo)
            or args.pr < 1 or not re.fullmatch(r"[0-9a-f]{40}", args.head)
            or args.timeout < 0 or args.interval < 1):
        parser.error("valid repo, PR, head SHA and polling bounds are required")
    if args.publish_check and not re.fullmatch(
            rf"https://github\.com/{re.escape(args.repo)}/actions/runs/[1-9][0-9]*",
            args.run_url or ""):
        parser.error("publishing a check requires this repository's workflow run URL")
    if not args.publish_check:
        return wait_for_review(args)
    result = 1
    try:
        publish_status(args, "pending")
        result = wait_for_review(args)
    finally:
        # API errors remain failure; never leave an earlier clean result in
        # place while validating a same-head retry.
        publish_status(args, "success" if result == 0 else "failure")
    return result


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, ValueError, KeyError, TypeError) as error:
        # Do not dump subprocess environments or response bodies into the log.
        print(f"Codex review check could not read valid GitHub metadata: {type(error).__name__}",
              file=sys.stderr)
        sys.exit(1)
