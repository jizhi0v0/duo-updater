#!/usr/bin/env python3
"""Classify a fixed PR head before the cloud task's label-filtered trigger."""
import argparse
import json
import os
import re
import subprocess

from check_codex_review import api, is_nightly_state, nightly_files

MANAGED = "codex-managed"
DATA_ONLY = "nightly-data-only"


def labels(pr):
    return {label["name"] for label in pr.get("labels", [])}


def was_managed(repo, number, read=None):
    """Use GitHub's paginated label history as the sticky-route record."""
    events = (read or api)(f"repos/{repo}/issues/{number}/events?per_page=100")
    return any(event.get("event") == "labeled"
               and event.get("label", {}).get("name") == MANAGED
               for event in events)


def is_scan_state(pr, repo, read=None):
    if not nightly_files(pr, repo):
        return False
    # A managed label may already have matched the synchronize webhook before
    # this trusted job can inspect the new head. Never downgrade the same PR:
    # a fresh pure-data scan PR is required after any managed head.
    if MANAGED in labels(pr):
        return False
    base, head = pr.get("base", {}).get("sha", ""), pr["head"].get("sha", "")
    if not all(isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha) for sha in (base, head)):
        raise ValueError("invalid scan comparison")
    comparison = (read or api)(f"repos/{repo}/compare/{base}...{head}")
    return is_nightly_state(pr, repo, comparison.get("files", []))


def set_route(repo, number, pr, data_only):
    present = labels(pr)
    # Managed always wins, even if it appeared after the caller's comparison.
    # A stale data-only verdict must never delete the sticky managed route.
    if data_only and MANAGED in present:
        data_only = False
    desired, other = (DATA_ONLY, MANAGED) if data_only else (MANAGED, DATA_ONLY)
    # Change only our two routing labels, preserving holds and human labels.
    # On the data-only path MANAGED cannot be in this snapshot, so a later
    # concurrent addition is left intact rather than deleted.
    if other in present:
        subprocess.run(["gh", "api", "--method", "DELETE",
                        f"repos/{repo}/issues/{number}/labels/{other}"],
                       check=True, capture_output=True, text=True)
    if desired not in present:
        subprocess.run(["gh", "api", "--method", "POST",
                        f"repos/{repo}/issues/{number}/labels", "--input", "-"],
                       input=json.dumps({"labels": [desired]}),
                       check=True, capture_output=True, text=True)
    return desired


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--pr", type=int, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--removed-label", default=os.environ.get("REMOVED_LABEL", ""))
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if (not args.repo or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo)
            or args.pr < 1 or not re.fullmatch(r"[0-9a-f]{40}", args.head)):
        parser.error("valid repo, PR and head required")
    pr = api(f"repos/{args.repo}/pulls/{args.pr}")
    if pr["state"] != "open" or pr["head"]["sha"] != args.head:
        print("Closed PR or superseded head; routing unchanged.")
        return
    # The unlabeled webhook is the durable evidence that this PR was managed
    # even though the live label is already absent. Restore that route instead
    # of allowing the same PR to downgrade to data-only.
    data_only = args.removed_label != MANAGED and is_scan_state(pr, args.repo)
    # The unlabeled run can be cancelled by a later event in this workflow's
    # concurrency group. GitHub's label event history survives that cancellation.
    if data_only and was_managed(args.repo, args.pr):
        data_only = False
    current = api(f"repos/{args.repo}/pulls/{args.pr}")
    if current["state"] != "open" or current["head"]["sha"] != args.head:
        print("PR changed while classifying; routing unchanged.")
        return
    if (current.get("base", {}).get("sha") != pr.get("base", {}).get("sha")
            or current.get("base", {}).get("ref") != pr.get("base", {}).get("ref")
            or current.get("changed_files") != pr.get("changed_files")
            or nightly_files(current, args.repo) != nightly_files(pr, args.repo)):
        raise ValueError("PR metadata changed while classifying")
    # A concurrent routing/manual event may have made this PR managed while
    # the immutable comparison was in flight. The final live label state wins:
    # never let a stale data-only verdict remove the sticky managed route.
    if MANAGED in labels(current):
        data_only = False
    if args.apply:
        set_route(args.repo, args.pr, current, data_only)
    print(f"cloud_route={'data-only' if data_only else 'managed'}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        raise SystemExit("Cloud routing could not validate current GitHub metadata.")
