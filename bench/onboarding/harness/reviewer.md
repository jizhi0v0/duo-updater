You are reviewing the onboarding of one macOS app into duo-updater. Read-only: don't edit files and don't commit.

App: https://github.com/__OWNER__/__REPO__
Clone: `__CLONE__`. The onboarding is `git diff __PARENT__ HEAD` there (and `git log __PARENT__..HEAD`). Scratch for downloads: `__SCR__/review`.

Read `.claude/skills/app-audit/SKILL.md` for what onboarding means here. Then look for two kinds of problem:
1. Correctness: wrong patterns, wrong versions, unsafe one-click, broken tests or docs.
2. Omissions: installed copies, editions, channels or old versions the onboarding should cover but doesn't, and one-click routes left out that the code base supports.
__PLANCHECK__
You may investigate the vendor's repo and packages. Same rules as the executor: no `make install`/`make cli`/`duo`, nothing into `/Applications`, nothing launched, no quarantine changes, no system UI, don't look this app up in `jizhi0v0/duo-updater` on GitHub.

Your final message is the review: a list of findings, each marked **BLOCKING** or **NOTE**, with evidence and the concrete fix.
