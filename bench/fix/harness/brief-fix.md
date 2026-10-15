You are working in a clone of the duo-updater repo (a macOS app updater, Swift) at __CLONE__. The nightly `duo verify` sweep filed the GitHub issue(s) below against this commit. Resolve them.

"Resolve" means: find out what is actually wrong and do whatever the evidence supports. That may be a code change, or a deliberate decision not to change code. Either way, explain it with evidence.

__ISSUES__

## How to work
- The project skill `fragile-recipe` (Skill tool) describes how changelog and vendor-probe recipes are written and validated in this repo.
- Base every conclusion on the real current responses from the vendor's servers, run through the production code. Not on the issue text alone.

## Hard rules
- Scratch files go in __SCR__ only (never /tmp, never the repo root).
- Do NOT run `make cli`, `make install`, `pkill`, `killall`, `sudo`, `open`, `gh`, `git push`, `CLI/.build/debug/duo`, `swift run … duo` or `duo` in any form (the debug build hangs on a Keychain prompt). Validate through temporary Swift tests that call the production code, and delete them before committing.
- Never trigger system UI (Gatekeeper, TCC, admin password, keychain). Do not download or open an app installer.
- Run long commands in the FOREGROUND with an explicit Bash timeout (up to 600000 ms), output redirected to a file under __SCR__, then tail it. Never background a command and wait for it.
- `make test` is the gate. Judge it only by its exit code: `make test > __SCR__/make-test.log 2>&1; echo rc=$?`. If it takes longer than 600 s, rerun it the same way (it is incremental).
- Surgical changes only.

## Finish
1. If you changed code, commit it on the current branch (`git commit -F <file>`). Do not push.
2. Write __SCR__/verdict.json:
   {"issues": [{"number": <n>, "verdict": "fixed" | "no-change" | "acknowledged" | "blocked",
                "cause": "<one sentence>", "needs_human": true|false,
                "evidence": "<the command(s) and the key raw output>"}],
    "make_test_rc": <int or null>}
   "acknowledged" means you recorded a deliberate gap or exception in code instead of fixing it.
   Set "needs_human" when the right call is a judgment the maintainer should confirm.
3. Your final answer: the same, in prose.
