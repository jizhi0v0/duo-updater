# Codex code review

Pull requests are reviewed by the official Codex GitHub integration, using the
connected Codex subscription. No OpenAI API key or review Action is required.
Repository rules are in `AGENTS.md`, which directs reviewers to `REVIEW.md`.

## Repository settings

In [Codex Code Review settings](https://chatgpt.com/settings/code-review), select
`jizhi0v0/duo-updater` and configure **Review code**:

- Automatic review: on.
- Review: All PRs, overriding personal preferences for this repository.
- Trigger: On every push, so fixes receive another review.

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
review, comment (including bot reviews) and commit-update events. It checks
findings, pushes fixes and reads the Mac CI results. It follows `AGENTS.md`
and leaves changes requiring missing real-machine evidence open.

The `main` ruleset requires:

- `test`: the existing test jobs, plus `make test-release-build` in the App job.
  This compiles both shipping schemes in Release with signing disabled and
  committed dependency pins. It does not install, sign or notarize a release.
- `codex-review`: an explicit clean official Codex receipt for the current PR
  head. The read-only Linux job waits for that receipt and fails closed on
  missing, stale, malformed or non-clean results. A pushed fix starts a new run;
  rerun this workflow after a same-head review retry. No model token is used.
  The workflow uses `pull_request_target`, so GitHub loads the job definition
  from the default branch rather than the PR. It never checks out or executes
  the PR ref. The job then checks out immutable commit
  `4f295669abfad4861fc4d7bc7add096a1491f327` for the verifier script.
  Changes to either trust boundary require review before they land on the
  default branch.

  The first merge that introduces this workflow is a bootstrap boundary:
  `pull_request_target` cannot run a workflow that is not yet present on the
  default branch. Do not treat the PR-controlled predecessor as equivalent.
  Bootstrap the trusted workflow through repository administration or another
  already-trusted required workflow; after it exists on `main`, future PRs
  cannot replace the required gate with a successful no-op.
- `real-machine` and `adversarial-review`: the existing evidence-record gates.

The `needs-real-machine` label also blocks `codex-review`. Apply it when actual
installation, permissions, restart, rollback or another necessary real-machine
check remains unverified. Remove it only after evidence is supplied. A passing
record parser does not prove that an opt-out is true or covers the change.

`Cloud PR wakeup` posts completion metadata when CI or the review gate finishes,
so the cloud event task can resume without a local polling job. It runs trusted
default-branch code, checks the live PR head and never checks out PR code or
executes an artifact with its comment-write token. Wakeup comments are not
merge approval; the cloud handler rechecks all gates and the exact head SHA.

Official setup and review-rule documentation:
[Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github).
