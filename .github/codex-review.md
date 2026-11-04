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

Official setup and review-rule documentation:
[Review GitHub pull requests with Codex](https://learn.chatgpt.com/docs/third-party/github).
