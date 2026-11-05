# Optional Codex review

Official GitHub Codex reviews are optional and requested manually when useful.
Do not automatically request a review, retry quota failures, or require a clean
cloud receipt before merging. The cloud PR task is paused; the review gate and
cloud wakeup workflows have been removed.

The required checks remain `test`, `real-machine` and `adversarial-review`.
Use current-head evidence and resolve confirmed defects before merging; an
optional review does not replace CI, real-machine validation or local review.
See [REVIEW.md](../REVIEW.md) for review criteria.

Pure owner-authored nightly scan-state changes retain their narrowly scoped
lightweight data-validation path in `scripts/check_nightly_data.py`.
