You are planning the onboarding of one macOS app into duo-updater. You do not implement anything. An executor agent will implement your plan in a fresh clone, and a reviewer will then check its result against your plan, item by item.

App: https://github.com/__OWNER__/__REPO__
Repo clone (read it, don't modify it): `__CLONE__`. Scratch for downloads and notes: `__SCR__`.

## What to do

1. Read `.claude/skills/app-audit/SKILL.md` and `.claude/skills/coverage-discovery/SKILL.md` (Phase 2 and the rules in Phase 3) to learn what onboarding means here and how it's done. For a worked example, `git show` the most recent commit that added a `GitHubReleaseRule` recipe for one app.
2. Investigate the vendor yourself: the repo, its full release history (old releases too), the real packages (download them to `__SCR__` and inspect read-only), signing and notarization, the app's own updater and any feed, and its bundle ids across history.
3. Write `__SCR__/plan.md` with three sections.
   - **Coverage checklist.** List every kind of installed copy a user may have: each bundle id, including ids from before a rename; each edition shipped from the repo; each channel or track, such as beta or nightly; and old versions that lack a feed newer ones declare. Also note the signing path of each and any resident helper. For each item, give the detection route, the one-click route or why there isn't one, and the changelog route, with the evidence you gathered.
   - **Steps.** Concrete steps for the executor, in order, with exact URLs and commands where they help.
   - **Boundaries.** What not to do. What stays detection-only until it is verified on a real machine. Anything that would need a Core change, and whether to make it or only record it.

## Rules

- Write only under `__SCR__`. Don't edit files in the clone and don't commit.
- Forbidden: `make install`, `make cli`, the `duo` CLI, `pkill`/`killall`, `git stash`, `git push`, creating GitHub PRs or issues, writing into `/Applications` or `~/Applications`, launching or opening anything you downloaded, setting or removing quarantine xattrs, and anything that shows system UI. Mounting a dmg read-only (`hdiutil attach -nobrowse -readonly`) and reading from it is fine; detach it afterwards.
- Don't look this app up in `jizhi0v0/duo-updater` on GitHub (issues, PRs, branches, code search). This is a benchmark.
- Run long commands in the foreground with an explicit timeout, never in the background.

Your final message: a short summary. The plan itself goes in `__SCR__/plan.md`.
