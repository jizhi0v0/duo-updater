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

## Cloud fixes and merge gates

The cloud task **DuoUpdater PR 云端修复与合并** receives this repository's PR,
review, comment (including bot reviews) and commit-update events only when the
associated PR has `codex-managed`. Its structured GitHub trigger uses
`label_match: codex-managed`, filtering before a model run, not by waking a
model and asking it to exit. It checks
findings, pushes fixes and reads the Mac CI results. It follows `AGENTS.md`
and leaves changes requiring missing real-machine evidence open.

The `cloud-routing` job in the trusted `pull_request_target` review-gate workflow
classifies the pinned head for PRs targeting `main`. It uses the same scan-file
allowlist as the review waiver, then assigns `codex-managed` to other PRs or
`nightly-data-only` to pure scan state. It changes only those two labels and
preserves human/real-machine holds. A scan branch gaining code is routed back
to the cloud. These labels are event routing hints, not approval credentials.
On first deployment, label the introducing PR and existing ordinary PRs after
independent classification so the already-filtered task can receive them.

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
Pure scan-state PRs do not match the cloud trigger. The producer's CI-gated
GitHub auto-merge completes them without a model; failures stay visible in
GitHub checks and leave the PR unmerged. `Cloud PR wakeup` also suppresses
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
failed controller run; the cloud handler must still verify the current official
receipt and holds, rather than treating an old successful status as approval.

After deployment, require `codex-review` from the App's **numeric App ID** in the
main ruleset (not the client ID or installation ID). Keep the existing required
checks and review-thread resolution. No OpenAI API key is needed for this App.

The `needs-real-machine` label also blocks `codex-review`. Apply it when actual
installation, permissions, restart, rollback or another necessary real-machine
check remains unverified. Remove it only after evidence is supplied. A passing
record parser does not prove that an opt-out is true or covers the change.

`Cloud PR wakeup` posts completion metadata when CI, the review gate, the
real-machine record or the adversarial-review record workflow finishes,
so the cloud event task can resume without a local polling job. It runs trusted
default-branch code, checks the live PR head and never checks out PR code or
executes an artifact with its comment-write token. Wakeup comments are not
merge approval; the cloud handler rechecks all gates and the exact head SHA.
Wakeups are deduplicated per workflow run **and attempt**; a successful rerun
can wake the handler even if the same run previously reported failure.
Success, failure, cancellation and timeout all wake the handler; it reads the
live checks and failed-job logs before acting. A new independent PR validation
workflow must be added to the notifier's explicit workflow/event allowlist.

Official setup and review-rule documentation:
[Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github).
