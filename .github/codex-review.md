# Codex code review

Pull requests are reviewed by the official Codex GitHub integration, using the
connected Codex subscription. No OpenAI API key or review Action is required.
Repository rules are in `AGENTS.md`, which directs reviewers to `REVIEW.md`.

## Repository settings

In [Codex Code Review settings](https://chatgpt.com/settings/code-review), select
`jizhi0v0/duo-updater` and configure **Review code**:

- Automatic review: off for this repository. The cloud event task requests
  official reviews selectively, so nightly scan data does not consume review
  quota. The integration remains connected and serves `@codex review` requests.
- For each non-exempt PR head, the task requests a review once when no matching
  running/completed receipt or request already exists. Pushed fixes get a new
  review; the trusted gate still requires a clean current-head receipt.

To request a review manually, comment `@codex review` on a pull request.
Respond to findings with the fix or evidence for rejecting them before pushing
the next change. Codex follows the review guidance in `AGENTS.md`.

These settings live in Codex, not in GitHub Actions YAML. The integration owns
review triggering and publication. The former Claude workflow's round markers,
first-parent-only rechecks and automatic-branch exclusions are not configured
by `AGENTS.md`; do not assume those workflow behaviors carry over.

The former `.github/workflows/claude-review.yml` and its action-only Dependabot
configuration have been removed. `.github/claude-review/` remains as historical
input to the Claude onboarding replay benchmark and its regression checks.
Other Claude-powered automation uses its existing credentials independently.

## Cloud review, local fixes and merge gates

The cloud task **DuoUpdater PR 云端审查** receives this repository's PR,
review, comment (including bot reviews) and commit-update events only when the
associated PR has `codex-managed`. Its structured GitHub trigger uses
`label_match: codex-managed`, filtering before a model run, not by waking a
model and asking it to exit. It requests official reviews and reads their status. Cloud tasks must not edit
code, push commits, resolve review threads, remove holds or merge PRs. The local
agent owns fixes, macOS/VM validation and follow-through. It follows `AGENTS.md`
and leaves changes requiring missing real-machine evidence open.

After submitting a PR, the local agent polls its current head, official review
receipt, unresolved threads, required checks and mergeability until that head
meets the merge requirements. Fix confirmed defects locally, run the relevant
checks and push without overwriting others; a new head requires fresh review
and checks. A green CI summary alone is insufficient: retain real-machine holds
until the actual evidence exists, and refresh the local adversarial record when
risk-bearing code changes. Do not claim monitoring continues after ending the
session unless a durable watcher has actually been configured. Report an
external blocker explicitly instead of weakening checks or retrying endlessly.
Recheck the exact head and base before declaring the PR ready to merge.

The `cloud-routing` job in the trusted `pull_request_target` review-gate workflow
classifies the pinned head for PRs targeting `main`. It uses the same scan-file
allowlist as the review waiver, then assigns `codex-managed` to other PRs or
`nightly-data-only` to pure scan state. It changes only those two labels and
preserves human/real-machine holds. A scan branch gaining code is routed back
to the cloud. That managed route is intentionally sticky for the lifetime of
the PR: a later synchronize event can be delivered before Actions sees its new
head, so downgrading the same PR would expose a stale managed label to the
server-side filter. The workflow's `unlabeled` event passes the removed label
to the router, and the router also reads GitHub's paginated label-event history.
This preserves the managed route even if a later workflow event cancels the
`unlabeled` run. The final live label read and the write path both give
`codex-managed` precedence, so concurrent routing cannot delete it. A producer that returns to pure data must close that PR and
open a fresh scan PR. These labels are event routing hints, not approval
credentials. On first deployment, label the introducing PR and existing
ordinary PRs after independent classification so the already-filtered task can
receive them.

### Nightly scan state exception

Owner-authored PRs from this same repository with timestamped branches
`verify/baseline-YYYYMMDDTHHMMSSZ` may modify only `verify/baseline.json`;
`verify/install-YYYYMMDDTHHMMSSZ` may modify only `verify/identities.json` and/or
`verify/install-baseline.json`. These generated-state updates need no model
review. The trusted gate compares immutable base/head commits, rejects other
files, deletions, renames and incomplete file lists, then publishes
`codex-review: success` with **Nightly scan state only; review not required**.
It does not claim that Codex reviewed that head. CI uses a Linux-only
`nightly-data` job: strict JSON/duplicate-key checks, schema and field types,
timestamps, nonnegative counters, URL digest format and preservation of existing
installer trust/provenance fields. Data is read from immutable Git blobs without
checking out or executing PR code. Valid pruning and observed version changes
are allowed; the check does not re-run vendor probes or judge release ordering.
The aggregate `test` check requires this validator to pass and allows the three
Mac jobs and linked-code check to be skipped only for this classified path.
The main push after merging the same scan PR also uses this path, after verifying
its merged-PR association and complete before/after diff. Other pushes, dispatches,
and scan branches with code changes keep full CI. Evidence gates and actual holds
remain required.
PRs that are pure scan state from opening and have never entered the managed
route do not match the cloud trigger. The producer's CI-gated GitHub auto-merge
completes them without a model; failures stay visible in GitHub checks and
leave the PR unmerged. A PR that ever carried code remains managed even if a
later head removes it; the producer must use a fresh PR for pure data again. `Cloud PR wakeup` also suppresses
their completion comments. The saved task's scan-state guard is defensive for
manual or previously queued runs, not the normal classification mechanism.

The official repository settings currently expose no branch exclusion. Keeping
blanket automatic review on would still start reviews before the task could
classify them; `AGENTS.md` guidance alone cannot prevent that trigger.

The `main` ruleset requires:

- `test`: the lightweight data validator above for pure scan-state updates;
  otherwise the existing test jobs, plus `make test-release-build` in the App job.
  This compiles both shipping schemes in Release with signing disabled and
  committed dependency pins. It does not install, sign or notarize a release.
- `codex-review`: a verified nightly-state exemption, or an explicit clean
  official Codex receipt for the current PR head. For other PRs the trusted Linux
  job waits for that receipt and fails closed on
  missing, stale, malformed or non-clean results. A pushed fix starts a new run;
  rerun this workflow after a same-head review retry. No model token is used.
  Its `pull_request_target` workflow and verifier come from the protected default
  branch and target `main`. It never checks out PR code, downloads artifacts, invokes a model or
  reads a model secret. The review controller's read-only `GITHUB_TOKEN` reads metadata; a separate
  GitHub App installation token publishes the commit status on the explicit
  PR head rather than inferring it from the workflow SHA. The required status
  must be bound to that App's numeric ID, not GitHub Actions (15368) or any
  source. PR-controlled Actions credentials cannot publish as this App.
  Workflow changes take effect only after being merged.

  A separate routing job has `pull-requests: write` only to maintain the two
  routing labels. It has no App environment/key and executes no PR code.
  The review controller runs independently so failed routing cannot prevent
  it from rechecking holds and invalidating an earlier same-head success.

  First deployment must precede enforcing this new required status:
  `pull_request_target` cannot run until this workflow exists on `main`.
  Bootstrap the introducing PR through repository administration after an
  independently verified clean official review and all Mac CI/evidence gates.
  Enable the required `codex-review` status immediately after deployment;
  do not treat a PR-controlled predecessor as the trusted gate.
- `real-machine` and `adversarial-review`: the existing evidence-record gates.

### Isolated status publisher setup

The owner-only App manifest is [codex-review-app.json](codex-review-app.json).
It requests only **Commit statuses: write**, plus GitHub's implicit metadata
read permission. Install it only on this repository. It does not change source,
merge PRs, invoke a model or receive webhooks.

Before storing its key, configure environment `codex-review-publisher` with a
custom deployment policy allowing exactly the `main` **branch**, with no tag or
PR-merge-ref patterns. Store `CODEX_REVIEW_APP_PRIVATE_KEY` only as an environment
secret, never a repository/organization secret. Set environment variable
`CODEX_REVIEW_APP_CLIENT_ID` to the App client ID. This keeps the key unavailable
to PR-controlled workflows even when they request broader GITHUB_TOKEN scopes.

The token action is pinned, limited to this repository and status writes, and
revokes its token when the job finishes. Status writes have bounded retries.
Even if the initial pending write fails, the failure path attempts to invalidate
an earlier success before exiting. If publication is unavailable, inspect the
failed controller run; the local agent must still verify the current official
receipt and holds, rather than treating an old successful status as approval.

After deployment, require `codex-review` from the App's **numeric App ID** in the
main ruleset (not the client ID or installation ID). Keep the existing required
checks and review-thread resolution. No OpenAI API key is needed for this App.

The `needs-real-machine` label also blocks `codex-review`. Apply it when actual
installation, permissions, restart, rollback or another necessary real-machine
check remains unverified. Remove it only after evidence is supplied. A passing
record parser does not prove that an opt-out is true or covers the change.

`Cloud PR wakeup` keeps one current bot status comment per PR when CI, the
review gate, the real-machine record or the adversarial-review record workflow
finishes. Each new completion **creates** the replacement comment before removing
older marked bot wakeups. This preserves the existing comment-created trigger;
it does not depend on edited-comment delivery by the cloud task. Human comments,
official reviews and unrelated bot comments are never removed. Workflow-run
history remains in Actions. A failed POST preserves the old status; a failed
cleanup is retried on replay without posting another wakeup.

It runs trusted default-branch code, checks the live PR head and never checks
out PR code or executes an artifact with its comment-write token. Wakeup
comments are not merge approval; the local agent rechecks all gates and the
exact head SHA.

The status stores each workflow's latest run number and attempt for the current
head. Replays and late older runs are ignored; a successful rerun still creates
a wakeup after failure, and a new head resets the displayed check results.
Success, failure, cancellation and timeout remain wakeups. Old v2 wakeups are
cleaned up only after the replacement has been successfully published. The
notifier workflow serializes comment writes with `queue: max` and
`cancel-in-progress: false`, so simultaneous completions cannot create duplicate
current statuses or replace each other's recorded checks. A new independent
validation workflow must be added to the notifier's explicit workflow/event allowlist.

Official setup and review-rule documentation:
[Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github).
