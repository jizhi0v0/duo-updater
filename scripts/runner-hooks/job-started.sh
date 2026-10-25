#!/bin/bash
# Pre-job hook for the mini's self-hosted runners (label `duo-mini`): refuse any
# job that is not this repository's own push, dispatch or same-repository pull
# request. A non-zero exit makes the runner fail the job before its first step
# (https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/run-scripts).
#
# Why: a pull request runs the PR's merge commit, so a fork's copy of
# scripts/ci_route.py can print the mini's labels without touching
# .github/workflows/ (security review 2026-10-25, item 8). The repository
# settings (collaborator-only PR creation, approval for every external
# contributor) are the first gate and the `if:` in ci.yml the second; this is the
# third, on the machine itself, and the only one a fork's change cannot edit.
#
# What lets a job through, all of:
#   • GITHUB_REPOSITORY is exactly jizhi0v0/duo-updater;
#   • GITHUB_EVENT_NAME is pull_request, push or workflow_dispatch. These are the
#     only events that reach the mini today: ci.yml is the one workflow with a
#     self-hosted job (via the `route` job), and it triggers on exactly these.
#     schedule, issues, pull_request_target and the rest are refused;
#   • for pull_request, the event payload (GITHUB_EVENT_PATH) names
#     pull_request.head.repo.full_name and it equals this repository. A missing,
#     null or non-string field, an unreadable file or invalid JSON refuses the job.
#
# INSTALL (not done by the pull request that added this file; the owner runs it
# once on each mini, for each runner directory). The hook must sit OUTSIDE the
# runner's directory, owned by root, and not writable by the runner's user,
# otherwise a job could rewrite it. `ACTIONS_RUNNER_HOOK_JOB_STARTED` must be an
# absolute path to a file with a `.sh` extension; a change to `.env` needs the
# runner restarted. From a checkout of this repository, as an administrator:
#
#   sudo install -d -o root -g wheel -m 755 /usr/local/lib/duo-runner-hooks
#   sudo install -o root -g wheel -m 755 scripts/runner-hooks/job-started.sh \
#        /usr/local/lib/duo-runner-hooks/job-started.sh
#   # in the directory of EACH runner (mini-duoupdater and mini-duoupdater-2 on each mini), as its user:
#   echo 'ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/lib/duo-runner-hooks/job-started.sh' >> .env
#   # then restart each runner (./svc.sh stop && ./svc.sh start, or however it is launched).
#
# Check it: `ls -ld /usr/local/lib/duo-runner-hooks /usr/local/lib/duo-runner-hooks/*`
# shows root:wheel and no group/other write; a job from a fork's pull request
# then fails with "job-started hook: ..." in the runner's log. Re-run the install
# command after this file changes; the installed copy does not follow the checkout.
#
# Every runner this hook is installed on must serve only this repository: any
# other repository's job is refused. The hook reads no secret and writes nothing.
set -u

REPO="jizhi0v0/duo-updater"

refuse() {
  echo "job-started hook: refusing this job: $*" >&2
  exit 1
}

[ "${GITHUB_REPOSITORY:-}" = "$REPO" ] || refuse "repository is '${GITHUB_REPOSITORY:-}', not $REPO"

case "${GITHUB_EVENT_NAME:-}" in
  push | workflow_dispatch) exit 0 ;;
  pull_request) ;;
  *) refuse "event '${GITHUB_EVENT_NAME:-}' is not pull_request, push or workflow_dispatch" ;;
esac

[ -n "${GITHUB_EVENT_PATH:-}" ] || refuse "GITHUB_EVENT_PATH is not set"

# -I: no user site, no PYTHON* variables, no script directory on sys.path.
head_repo=$(/usr/bin/python3 -I -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    event = json.load(f)
name = event["pull_request"]["head"]["repo"]["full_name"]
if not isinstance(name, str) or not name:
    raise TypeError("full_name is not a non-empty string")
print(name)
' "$GITHUB_EVENT_PATH" 2>/dev/null) || refuse "cannot read pull_request.head.repo.full_name from the event"

[ "$head_repo" = "$REPO" ] || refuse "pull request head is '$head_repo', not $REPO"
exit 0
