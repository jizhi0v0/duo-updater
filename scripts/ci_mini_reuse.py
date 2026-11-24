"""Find a recent successful full CI run on the same mini, across trusted branches."""
import datetime as dt
import json
import os
import re
import subprocess
from pathlib import Path

from ci_release_inputs import REPO, git, release_transition

WORKFLOW = ".github/workflows/ci.yml"


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", f"repos/{REPO}/{path}"], timeout=15))


def source_run(trees, platform, lookup=api):
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
    runs = lookup("actions/workflows/ci.yml/runs?status=success&per_page=16&created=%3E"
                  + since.strftime("%Y-%m-%dT%H:%M:%SZ"))["workflow_runs"]
    for run in runs:
        if (run["path"] != WORKFLOW or run["head_repository"]["full_name"] != REPO
                or run["actor"]["login"] != REPO.split("/")[0]
                or run["event"] not in {"pull_request", "workflow_dispatch", "push"}
                or run["conclusion"] != "success" or run["id"] == int(os.environ["GITHUB_RUN_ID"])):
            continue
        jobs = lookup(f"actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs?per_page=100")["jobs"]
        successful = {j["name"] for j in jobs if j["conclusion"] == "success"}
        if not {"swift", "app", "release", "ifchange", "test"} <= successful:
            continue
        for name in successful:
            m = re.fullmatch(rf"Full mini CI ([0-9a-f]{{40}}) ([0-9a-f]{{40}}) {platform}", name)
            if not m or m[2] not in trees:
                continue
            commit = lookup("git/commits/" + m[1])
            if commit["tree"]["sha"] != m[2]:
                continue
            if run["event"] == "pull_request":
                parents = commit["parents"]
                if len(parents) != 2 or parents[1]["sha"] != run["head_sha"]:
                    continue
            elif m[1] != run["head_sha"]:
                continue
            # A different workflow on a branch cannot supply evidence for this policy.
            expected = git("rev-parse", "HEAD:" + WORKFLOW).strip()
            if not all(lookup(f"contents/{WORKFLOW}?ref={sha}")["sha"] == expected
                       for sha in {run["head_sha"], m[1]}):
                continue
            return run["id"], m[2]
    return None


def candidate_trees(head):
    trees = [git("rev-parse", head + "^{tree}").strip()]
    # A normal release has two transitions: release metadata, then feed.
    for _ in range(2):
        parent = head + "^1"
        if subprocess.run(["git", "rev-parse", "--verify", "--quiet", parent],
                          stdout=subprocess.DEVNULL).returncode:
            break
        try:
            if not release_transition(parent, head):
                break
        except ValueError:
            if len(trees) == 1:
                raise  # A bad release in this change must be reported.
            break  # An older transition cannot extend the list of tested bases.
        trees.append(git("rev-parse", parent + "^{tree}").strip())
        head = parent
    return trees


def main():
    head = git("rev-parse", "HEAD").strip()
    if head != os.environ["GITHUB_SHA"]:
        raise ValueError("checkout does not match this event")
    platform = os.environ["MINI_PLATFORM"]
    tree = git("rev-parse", head + "^{tree}").strip()
    result = None
    if os.environ.get("FORCE_FULL") != "true":
        try:
            trees = candidate_trees(head)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Full CI: release inputs unavailable ({error})")
        else:
            try:
                result = source_run(trees, platform)
            except (OSError, KeyError, TypeError, ValueError, subprocess.SubprocessError) as error:
                print(f"Full CI: no verifiable Actions result ({error})")
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as out:
        print(f"reuse={'true' if result else 'false'}", file=out)
        print(f"tree={tree}", file=out)
    if result:
        run, tree = result
        message = f"Reused full mini CI https://github.com/{REPO}/actions/runs/{run} (tree `{tree}`)."
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a") as summary:
            print(message, file=summary)
        print(message)


if __name__ == "__main__":
    main()
