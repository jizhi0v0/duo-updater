---
name: coverage-discovery
description: >-
  Breadth-first onboarding of apps duo-updater does not cover yet — typically
  open-source apps shipped through GitHub Releases. It enumerates candidates from
  Homebrew's cask data (not from memory), subtracts what the code AND the audit
  docs already cover, triages each survivor on its real package BEFORE spending
  an agent on it, dispatches one `/app-audit` agent per app, integrates their
  commits, runs the one-click install end to end, and reports every app on three
  counts: detection, one-click install, structured changelog. Trigger phrases:
  "find more apps to onboard", "寻找更多 GitHub 开源项目接入", "批量接入",
  "扩大覆盖面", "which popular apps don't we cover". Use this for many apps at
  once; use `/app-audit` for one named app and `/channel-discovery` for missing
  release channels of apps already covered.
---

# Coverage discovery skill

`/app-audit` goes deep on one app. This skill goes wide: which apps nothing
resolves today, which of those are worth an agent, and how to land a batch of
them without leaving risk on the user's machine.

It was written from a batch of twelve (2026-09-29). Three of the twelve turned
out to be covered already, and two of those three were detectable from the repo
before any agent ran. Most of the rules below come from that batch.

## What "onboarded" means — report all three, every time

An app is onboarded when **all three** hold:

| | Done means | Evidence |
|---|---|---|
| **Detection** | an old copy is offered the newest version; the newest copy is up to date | `channel-verify` on the previous and the newest real package |
| **One-click install** | `duo install` replaces an old copy with the new one, same Team, signature intact | the end-to-end run in Phase 5 |
| **Structured changelog** | the changelog view gets entries, with the vendor's section headings kept as headings | the `changelog pane` line of `channel-verify` (Phase 5) |

When one of the three can't be done, **say so, with the reason**, in the report
and in the audit doc. Reporting only the parts that work, so the reader assumes
the rest works too, is the failure this rule exists for. Legitimate "can't"s
seen so far:

- one-click withheld on purpose (Secretive: a long-running login-item agent
  would keep running replaced code);
- one-click refused by the Team-ID gate for old copies (OpenInTerminal changed
  signing Team at 2.3.9; 2.3.8 users update by hand once);
- changelog flattened: the Sparkle markdown path keeps headings as plain items
  (Osaurus, Mos: `headings []`, and "What's Changed" among the items);
- changelog absent: the vendor publishes no notes.

## Phase 1: Enumerate — from data, not memory

```bash
python3 .claude/skills/coverage-discovery/scripts/candidates.py --limit 40
```

It ranks casks whose download is a GitHub release asset by 365-day installs
and drops anything already covered. Coverage is checked against both the code
and `docs/app-audits/`, in three ways: the repo (following a rename through the
API), any bundle id the cask names in `uninstall`/`zap`, and the app's name in
the audit index. The last batch was seeded with a code-only grep. Headlamp got
through because its repo had been renamed. ClaudeBar got through because its
coverage lived only in an audit doc.

What the list **cannot** know:

- **Sparkle.** A bundle that declares `SUFeedURL` is covered by the generic
  source with no recipe. The cask won't say so. `auto_updates` is **not** a
  proxy: casks leave it unset for Sparkle apps (Mos, ClaudeBar, Osaurus were all
  `None`). Only the real package settles it (Phase 2).
- **Size.** Skip multi-hundred-MB apps (FreeCAD, slicers) unless asked. The
  end-to-end run downloads the package twice.

## Phase 2: Triage each candidate on its real package — before any agent

This takes a minute or two per app. In the last batch an agent took up to
20 minutes and 180k tokens. Do this first.

```bash
gh api repos/<owner>/<repo>/releases/latest -q '.tag_name, (.assets[] | "\(.name)\t\(.size)")'
curl -sSL -o "$SCR/<asset>" "https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>"
.claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR/<asset>"
swift run --package-path application-test feed-discover "$SCR/<asset>"
grep -rni '<bundle id>' DuoUpdaterCore/Sources docs/app-audits
```

| Triage result | Next |
|---|---|
| `declared` / `ADOPT`, or the bundle id is already in the repo | Covered. **Don't drop it silently**: run `channel-verify` on it and report its three counts, because "covered" can still mean a flattened changelog |
| `NEEDS BINDING` | A `ChannelBinding` job, not a recipe (the Osaurus route; `/app-audit` §1a-0) |
| `noKnownUpdater`, Developer ID + notarized | Dispatch (Phase 3) |
| No Team ID / not notarized | Detection-only at best. Dispatch only if detection alone is worth it |
| `check-bundle.sh` lists a `nested` app with `LSUIElement=true` | Flag it in the brief: a resident helper that keeps running after a bundle swap. `LSBackgroundOnly` launchers that exit are fine (OpenInTerminal) |

`check-bundle.sh` is used again in Phase 4. It mounts dmgs read-only, reads
exit codes directly (never through a pipe), and prints any nested apps.

## Phase 3: Dispatch — one agent per app, isolated

The brief follows the memory note `subagent-brief-rules`. It must say:

- `isolation: "worktree"`, and first `git fetch origin && git switch -c recipe/<app> origin/main`;
- its own `SCR=$(mktemp -d "$TMPDIR/recipe-<app>.XXXX")`;
- follow `.claude/skills/app-audit/SKILL.md` and `fragile-recipe`, with `git show <a recent GitHubReleaseRule commit>` as the worked example;
- the facts triage already found (bundle id, Team, feed-discover verdict, nested helpers), so the agent doesn't rediscover them;
- one-click only when the app is Developer ID signed with a Team ID, `spctl` says Notarized, and the asset is dmg or zip; prefer universal, otherwise arm64;
- check the **previous** release's Team ID too, because a change means the gate refuses every old copy;
- old→new `channel-verify` on the previous and newest packages, then goldens re-recorded and `make test` judged by exit code, in the foreground;
- the audit doc plus a README line **in the section matching its source**. A row whose coverage is generic Sparkle (`— S`) belongs in the Sparkle section; `AppAuditCoverageTests` fails it anywhere else;
- commit with `git commit -F`, no push;
- **forbidden**: `make install`, `make cli`, the `duo` CLI, `pkill`, `git stash`, copying into /Applications, launching anything downloaded, touching quarantine, anything that pops system UI. The end-to-end run is yours, done serially (Phase 5), because the CLI and /Applications are shared by every agent;
- the report gives the three counts, the exact newest and previous asset URLs, and raw `channel-verify` lines.

An agent that stops without changing anything **loses its worktree**, which is
cleaned up automatically. Resuming it fails on the first write. Spawn a fresh
agent and pass the first one's findings in the brief.

## Phase 4: Integrate — re-check, then pick

For each report:

1. Read the diff (`git show <sha>`), and read the rule's comment as a list of claims.
2. Re-run `check-bundle.sh` yourself on the agent's newest and previous downloads (they are in its `$SCR`). Don't take the Team, version or notarization from the report.
3. Question every deliberate "can't" in the report (detection-only, a skipped track). Is the reason measured or assumed? What does the helper actually do? For OpenInTerminal that meant reading `OpenInTerminalHelper/AppDelegate.swift`.

Then pick all commits onto one integration branch cut from `origin/main`:

```bash
.claude/skills/coverage-discovery/scripts/integrate.sh <sha> [<sha> ...]
```

It resolves only the conflicts every batch produces: one-line rows in the audit
README, and `<family>.set,` rows in `AppRecipeIndex.swift`, re-sorted. Any
other conflict stops the run. Use the agents' **own** commits (parent =
`origin/main`). Commits already rebased onto each other don't conflict on the
index and so don't exercise the merge. Finish with `make test` on the combined
branch, judged by exit code.

## Phase 5: End to end — install the previous release, update it with `duo`

The Team-ID gate, the archive extraction and the swap only run on a real
install. `duo verify` and `channel-verify` never download an installer.

**Permission.** Copying apps into /Applications is blocked by the auto-mode
classifier, and a yes in chat does not clear it. Ask the user to add this to the
**worktree's** `.claude/settings.local.json` (gitignored). It matches single
commands that start with `ditto`, so run one `ditto` per command:

```json
{ "permissions": { "allow": [ "Bash(ditto:*)" ] } }
```

Then:

```bash
make cli                                    # the CLI from THIS branch
duo check "<App>"                           # proves the recipe is in it — don't grep `strings`
                                            # for the bundle id: it found none for `org.cryptomator`
                                            # in a CLI that did contain the recipe (cause not established)
mdfind "kMDItemCFBundleIdentifier == '<bundle id>'"    # must be empty: never overwrite a real install
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$SCR/old/<app>" <previous.dmg>
ditto "$SCR/old/<app>/<App>.app" "/Applications/<App>.app"     # alone, one per command
duo check "<App>"
duo install "<App>" --yes
.claude/skills/coverage-discovery/scripts/check-bundle.sh <newest package>   # compare with the installed copy:
codesign -dvv "/Applications/<App>.app" 2>&1 | grep TeamIdentifier
codesign --verify --deep --strict "/Applications/<App>.app"; echo $?
spctl -a -vv -t exec "/Applications/<App>.app"
swift run --package-path application-test channel-verify <previous package> --expect stable   # the `changelog pane` line
```

Expected outcomes, all seen in practice:

| `duo install` says | Means |
|---|---|
| `backed up … verifyingCodeSignature … installed.` | One-click works. Confirm the version, the Team, and `codesign --verify` on the result |
| `verifyingSignature` as well | A Sparkle route; the EdDSA signature was checked too |
| `Team Identifier mismatch … Refusing to install.` | The vendor changed Team. The old copy must be untouched; check it |
| `Skipping: … detection only` | `installAssetPattern` is nil, as designed |

**Reading the `changelog pane` line.** It names what the workbench pane shows,
in the pane's own order: a changelog recipe (fetched, as the app does) beats the
source's structured log, which beats raw inline notes, which beat the vendor
page in a web view. The *winning source* does not decide it: Fork is detected
through Sparkle but shows its recipe. `release notes N chars inline` above is
not evidence either way, since the Sparkle route carries inline HTML and a
structured log at once. For `recipe …` / `source structured …`, `headings [...]`
means sections were kept; `headings []` with a heading's text among the first
items means they were flattened (Osaurus, Mos). `raw inline notes`, `web page`
and `none` are all "not structured": say which, and why.

**Clean up — reversibly.** Nothing launched, so nothing is running. Check with
`pgrep -f "/Applications/<App>.app/"` anyway. Move the test installs to the
Trash, never `rm`:

```bash
osascript -e 'tell application "Finder" to delete POSIX file "/Applications/<App>.app"'
```

Then tell the user what is left for them: the Trash, the rollback copies
`duo install` made (listed by `duo backups`), and the permission rule.

Record the end-to-end result in each audit doc's 一键安装 section. Replace any
"端到端未做" line; don't leave it next to the result.

## Phase 6: Report

One row per app, all three counts, `✓ + evidence` or `✗ + reason`, never
blank:

```markdown
| App | 检测 | 一键 | Changelog |
|---|---|---|---|
| Neovide | ✓ GitHub, 0.16.1→0.16.2 | ✓ e2e 0.16.1→0.16.2 | ✓ 结构化，小标题 Bug Fixes / Docs |
| Osaurus | ✓ Sparkle + binding | ✓ e2e（含 EdDSA） | ⚠ 结构化但小标题被压平成条目 |
| Secretive | ✓ GitHub | ✗ 只检测：常驻 SSH agent 换包后跑旧代码 | ✓ Features / Fixes |
```

Also list:
- candidates found already covered, with their three counts;
- tracks not taken (same-bundle-id nightlies and RCs) and why;
- what's left on the user's machine (Phase 5 cleanup).

Then open one PR for the batch, and turn Auto-fix on. Enable auto-merge only
after the review round is read and found free of blocking findings. A green
`review` check is not that.

## File map

- `scripts/candidates.py` — Phase 1 ranking, minus what the repo covers
- `scripts/check-bundle.sh` — package identity, signature, notarization, nested helpers
- `scripts/integrate.sh` — cherry-pick with README/index conflict resolution
- `.claude/skills/app-audit/SKILL.md` — the per-app method each agent follows
- `.claude/skills/channel-discovery/SKILL.md` — the sibling breadth pass, for channels of covered apps
- `application-test/` — `feed-discover` (Phase 2), `channel-verify` (detection and the `changelog pane` line)
