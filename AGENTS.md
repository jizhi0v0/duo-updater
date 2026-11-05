# Repository guidance

## Code Review Rules

- Nightly scan state needs no code review: only owner-authored, same-repository
  `verify/baseline-<YYYYMMDDTHHMMSSZ>` PRs modifying `verify/baseline.json`, or
  `verify/install-<YYYYMMDDTHHMMSSZ>` PRs modifying `verify/identities.json`
  and/or `verify/install-baseline.json`. Any other changed file, deletion or
  rename follows the normal review rules, even on those branches.
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

Official GitHub Codex review is optional; see [the policy](.github/codex-review.md).
CI and the real-machine and local adversarial-review records remain required.

## PR completion

- Use normal pushes and SHA-bound merges, respecting branch protection. Read
  the current head, checks and unresolved review threads before merging.
  Evidence for an older head never approves a newer one.
- Require `test`, `real-machine` and `adversarial-review` to pass. Respect
  drafts, explicit author holds and confirmed unresolved defects.
- Do not automatically request official Codex reviews or wait for a clean
  cloud receipt. Cloud review quota exhaustion does not block merging.
- For the pure nightly scan-state exception above, `test` uses the Linux
  `nightly-data` check instead of Swift/App/Core tests and unsigned builds.
  It validates pinned JSON blobs, schema/types, dates, counters, URL digests
  and preservation of existing installer identity/provenance. The verified
  merged-state push uses the same light CI path. Keep evidence checks and
  genuine holds; changes outside scan state follow normal validation.
- When necessary real-machine validation is missing, apply `needs-real-machine`,
  explain the missing evidence and leave the PR open. Do not invent results or
  add an untrue opt-out. Remove the hold only after the required evidence exists.
