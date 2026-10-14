You are onboarding one macOS app into duo-updater. You work alone, in a fresh clone of the repo at `__CLONE__` (branch `main`, no git remote).

App: https://github.com/__OWNER__/__REPO__

"Onboarded" means three things, and your report states each one with evidence, or why it can't be done: (1) update detection, (2) one-click install when the package qualifies, (3) a structured changelog.

## Method

- Read `.claude/skills/app-audit/SKILL.md` and follow its not-yet-integrated workflow, through code, tests, goldens and the audit doc.
- Read `.claude/skills/coverage-discovery/SKILL.md`: Phase 2 (triage on the real package) and the rules listed in Phase 3 apply to you.
- For a worked example, find the most recent commit in `git log` that added a `GitHubReleaseRule` recipe for one app, and `git show` it.
- There is nobody to ask. Where a skill says to ask the user, make the conservative choice and list it under "Open questions" in your report.
- Skip the real-machine end-to-end install (app-audit's one-click run, coverage-discovery Phase 5). The coordinator runs it serially afterwards. Say in the report that it was not run.

## Rules

- Scratch: put downloads and temp files only under `__SCR__`.
- Forbidden: `make install`, `make cli`, the `duo` CLI, `pkill`/`killall`, `git stash`, `git push`, creating GitHub PRs or issues, writing into `/Applications` or `~/Applications`, launching or opening anything you downloaded, setting or removing quarantine xattrs, and anything that shows system UI (Gatekeeper, TCC, password prompts). Mounting a dmg read-only (`hdiutil attach -nobrowse -readonly`) and reading files from it is fine; detach it afterwards.
- Don't look this app up in `jizhi0v0/duo-updater` on GitHub (issues, PRs, branches, code search). This is a benchmark, and upstream may already contain the answer. Work from the app's own repo, its real packages, and this clone.
- Run long commands in the foreground with an explicit Bash timeout (at most 600000 ms), output redirected to a file, then tail it. Never background them; nothing will wake you.
- Gates: re-record the recipe goldens the way the repo documents, then run `make test` and judge it by its exit code only: `make test > __SCR__/make-test.log 2>&1; echo rc=$?`.
- Finish with exactly one commit, made with `git commit -F <file>`, in the repo's commit-message style.

## Report (your final message)

- The three outcomes, each `✓ + evidence` or `✗ + reason`.
- Bundle id; Team ID and notarization of the newest and previous packages; the exact asset URLs you examined.
- The `make test` exit code.
- Open questions: anything you were unsure about or decided conservatively.
