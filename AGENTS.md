# Repository guidance

## Code Review Rules

- Read [REVIEW.md](REVIEW.md) before reviewing. It contains the repository's
  blocking criteria and checks learned from previous defects.
- Review the pull request's own diff against its merge base. Read surrounding
  code as needed, but report only defects introduced or exposed by the change.
  The PR description and comments explain intent; verify their claims.
- Report concrete wrong behavior or actionable false claims. Do not report
  style, naming, formatting, optional refactors, missing tests alone, or
  pre-existing problems. For each finding, name the triggering input or state
  and cite the changed lines. Before posting, search for guards, callers and
  tests that could already prevent it; drop findings you cannot confirm.
- When revisiting a PR, read previous findings and the author's responses.
  Check whether fixes work and introduce new defects. Do not repeat a finding
  rejected with evidence unless the changes provide new evidence.
- For recipe or app-audit changes, first enumerate the installed-copy groups
  from the audit, `CHANNEL_COVERAGE_TODO.md` and repository context: old bundle
  IDs, editions, release tracks, version ranges and signing differences. Then
  check coverage or justified gaps using the criteria in REVIEW.md. Supported
  hosts are Apple Silicon Macs running macOS 15 or later.
- Check external claims against vendor sources when available. If an endpoint,
  signature, third-party default or OS behavior cannot be verified, identify it
  as unverified rather than calling it wrong. Distinguish claims the behavior
  depends on from incidental claims; uncertainty alone is not a defect.
- Run checks only when the required tools are available. A Linux review
  environment cannot validate the macOS app, installer or real-machine behavior;
  assess the PR's recorded evidence and state any validation limits accurately.

Codex's official GitHub integration runs reviews; see
[the setup notes](.github/codex-review.md). CI and the real-machine and local
adversarial-review records remain separate requirements.

## Automated PR fixes and merges

- Cloud PR handling is driven by GitHub events. Read the current PR head,
  official Codex receipt, unresolved review threads and CI before acting.
  Evidence for an older head never approves a newer one.
- Use normal pushes and SHA-bound merges, respecting branch protection.
  Require a clean current-head Codex re-review, `test` (including App and CLI
  unsigned Release builds), `real-machine` and `adversarial-review` to pass.
  Do not enable auto-merge early while review or validation is outstanding.
- When necessary real-machine validation is missing, apply `needs-real-machine`,
  explain the missing evidence and leave the PR open. Do not invent results or
  add an untrue opt-out. Remove the hold only after the required evidence exists.
- A same-head Codex retry does not push code: rerun the PR's `codex-review`
  workflow after the clean retry so its required check reflects that receipt.
- Completion comments from `Cloud PR wakeup` are wakeups, not approvals.
  Re-read current state, deduplicate work and avoid reacting to your own status
  replies in a loop. Respect drafts and explicit author holds.
