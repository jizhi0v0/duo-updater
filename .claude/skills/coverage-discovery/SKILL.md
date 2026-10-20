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

- one-click refused while a nested app runs (VMPal: a running VM keeps the
  old bundle's code, and nothing can restart it without stopping the VM);
- one-click refused by the Team-ID gate for old copies (OpenInTerminal changed
  signing Team at 2.3.9; 2.3.8 users update by hand once);
- changelog flattened: the Sparkle markdown path keeps headings as plain items
  (Osaurus, Mos: `headings []`, and "What's Changed" among the items);
- changelog absent: the vendor publishes no notes.

A one-click that would replace or damage what the user has is **not** a
legitimate "can't": recording it in the audit is not enough. Gate it
(`OneClickGate`) or withhold one-click (MuseScore 3, GitKraken On-Premise).

## Phase 1: Enumerate — from data, not memory

```bash
python3 .claude/skills/coverage-discovery/scripts/candidates.py --limit 40
```

It ranks casks whose download is a GitHub release asset by 365-day installs
and drops what the code or `docs/app-audits/` already covers (its docstring
says how). Seeding a batch from a code-only grep let renamed repos and
audit-only coverage through. What the list **cannot** know:

- **Sparkle.** A bundle that declares `SUFeedURL` is covered by the generic
  source with no recipe. `auto_updates` is **not** a proxy (Mos, ClaudeBar,
  Osaurus were all `None`). Only the real package settles it (Phase 2).
- **Size.** Skip multi-hundred-MB apps (FreeCAD, slicers) unless asked. The
  end-to-end run downloads the package twice.

## Phase 2: Triage each candidate on its real package — before any agent

A minute or two per app, against up to 20 minutes and 180k tokens per agent.

```bash
gh api repos/<owner>/<repo>/releases/latest -q '.tag_name, (.assets[] | "\(.name)\t\(.size)")'
curl -sSL -o "$SCR/<asset>" "https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>"
.claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR/<asset>"
swift run --package-path application-test feed-discover "$SCR/<asset>"
grep -rnF '<bundle id>' DuoUpdaterCore/Sources docs/app-audits
```

| Triage result | Next |
|---|---|
| `declared` / `ADOPT`, or the bundle id is already in the repo | Covered. **Don't drop it silently**: run `channel-verify` on it and report its three counts, because "covered" can still mean a flattened changelog |
| `NEEDS BINDING` | A `ChannelBinding` job, not a recipe (the Osaurus route; `/app-audit` §1a-0) |
| `noKnownUpdater`, Developer ID + notarized | Dispatch (Phase 3) |
| No Team ID, shipped as a GitHub release asset | Dispatch. One-click goes through `installTrust: .publishedDigestOnly` when every condition in `Recipes/org-alacritty.swift` holds; otherwise detection-only. Lokii and disktree are the worked examples |
| No Team ID / not notarized | Detection-only at best — except a MyGo app (`declared`, MyGo), whose vendor signature carries one-click behind the user's setting. Dispatch only if detection alone is worth it |
| A prerelease ships an asset with the stable one's name (Lapce's `nightly` and `Lapce-macos.dmg`) | Download it too and diff its Info.plist with the stable one's. Same bundle id means another track on the same id: flag it in the brief, so the agent settles it per app-audit's coverage checklist |
| `check-bundle.sh` lists a `component` (system extension, XPC service, launchd job) or `exe-references` the app's own releases | Flag it in the brief: something that runs outside the bundle, or an updater with no plist signal (Lapce) |
| `check-bundle.sh` lists a `nested` app with `LSUIElement=true` | Flag it in the brief: a resident helper that keeps running after a bundle swap. `LSBackgroundOnly` launchers that exit are fine (OpenInTerminal) |
| Another product under the same bundle id: an older major shipped beside the new one (MuseScore 3 / 4), or an edition (GitKraken On-Premise differs only in `app.asar`'s `clientType.js`) | Flag it in the brief. Detection stays; one-click for those copies goes behind a `OneClickGate` in the family's recipe file (`.installedVersion` / `.asarEntry`) |

## Phase 3: Dispatch — one agent per app, isolated

The brief follows the memory note `subagent-brief-rules`. It must say:

- `isolation: "worktree"`, and first `git fetch origin && git switch -c recipe/<app> origin/main`;
- its own `SCR=$(mktemp -d "$TMPDIR/recipe-<app>.XXXX")`;
- follow `.claude/skills/app-audit/SKILL.md` and `fragile-recipe`; a new family starts from `scripts/scaffold-github-rule.py <owner/repo> --package <asset>`, which drafts the rule, its `AppRecipeIndex` line, the audit doc and the README row, reads the previous and oldest listed stable packages too, and leaves `TODO(audit)` where judgment is needed (an older bundle id or Team, a same-name prerelease, another installer in the release under the same bundle id, a system extension or other component, an executable naming its own releases). Every `TODO(audit)` is resolved with evidence before the commit; `scripts/check_app_audits.py` (in `make test`) fails on one left in an audit or a recipe file. When it stops (the package is itself a prerelease, pkg/tarball, an Intel-only bundle, a version that is not plain dotted, a Sparkle feed), write the rule by hand with `git show <a recent GitHubReleaseRule commit>` as the worked example;
- the facts triage already found (bundle id, Team, feed-discover verdict, nested helpers, other products under the same id), so the agent doesn't rediscover them;
- one-click when the app is Developer ID signed with a Team ID, `spctl` says Notarized, and the asset is dmg or zip; prefer universal, otherwise arm64. An ad-hoc build gets `.publishedDigestOnly` as in Phase 2; when a condition fails the audit names it, and "ad-hoc" alone is not a reason;
- check the **previous** release's Team ID too, because a change means the gate refuses every old copy;
- old→new `channel-verify` on the previous and newest packages (it reads a `.app` or a `.dmg`; `ditto -x -k` a `.zip` first and pass the `.app`), goldens re-recorded, `make test` in the foreground judged by exit code;
- the audit doc plus a README line **in the section matching its source**. A row whose coverage is generic Sparkle (`— S`) belongs in the Sparkle section; `AppAuditCoverageTests` fails it anywhere else;
- a track or group of copies left unwired goes in the report under 「待用户决定」 with its reason: the agent can't ask, and app-audit never lets "not wired" be decided alone. The main session asks the user before the batch merges;
- commit with `git commit -F`, no push;
- **forbidden**: `make install`, `make cli`, the `duo` CLI, `pkill`, `git stash`, copying into /Applications, launching anything downloaded, touching quarantine, anything that pops system UI. The end-to-end run is yours, serially (Phase 5): the CLI and /Applications are shared. A claim about install behaviour ("the next attempt draws the zip") is a hypothesis until Phase 5;
- hygiene, each of which went wrong once:
  - grep bundle ids with `grep -F` (dots are wildcards otherwise);
  - tell a dmg by `hdiutil imageinfo <file>` (exit 0), not by its extension: UDIF dmgs ship extensionless;
  - read `Content-Length` before downloading (`curl -sIL <url> | grep -i '^content-length' | tail -1`) and skip anything over the size cap;
  - compare editions or channels on the **same** version (12.6.0 against 12.5.0 drowned the signal);
- the report gives the three counts, the exact newest and previous asset URLs, and raw `channel-verify` lines.

An agent that stops without changing anything **loses its worktree**, and
resuming it fails on the first write. Spawn a fresh agent with the first one's
findings in the brief.

## Phase 4: Integrate — re-check, then pick

For each report:

1. Read the diff (`git show <sha>`), and read the rule's comment as a list of claims.
2. Re-run `check-bundle.sh` yourself on the agent's newest and previous downloads (they are in its `$SCR`). Don't take the Team, version or notarization from the report.
3. Question every deliberate "can't" in the report (detection-only, a skipped track). Is the reason measured or assumed (read the helper's source, as for OpenInTerminal)? Take each 「待用户决定」 item to the user.

Then pick the agents' **own** commits (parent = `origin/main`) onto one
integration branch cut from `origin/main`:

```bash
.claude/skills/coverage-discovery/scripts/integrate.sh <sha> [<sha> ...]
```

It resolves README rows and `<family>.set,` rows in `AppRecipeIndex.swift`, and
stops on any other conflict. Append-only tables conflict too —
`BundleIDMigration.swift`'s table, `GitHubListPageSizeTests.swift`,
`CHANNEL_COVERAGE_TODO.md`: keep both sides, then fix any count a test asserts
(`RaycastReleasesTests.swift`). Finish with `make test` on the combined branch,
judged by exit code.

If the batch touches engine code — a binding, `BundleIDMigration`,
`UpdateResult` / `UpdatePolicy`, or the installer — run one `adversary` agent
(Opus, xhigh) on that diff before opening the PR: #1358's review found bugs
in `UpdateResult` and `ZettlrChannel` that no recipe check would.

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
mdfind "kMDItemCFBundleIdentifier == '<bundle id>'"    # must be empty: never overwrite a real install
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$SCR/old/<app>" <previous.dmg>
ditto "$SCR/old/<app>/<App>.app" "/Applications/<App>.app"     # alone, one per command
duo check <bundle id>                       # proves the recipe is in this CLI; by id, since duo's name can differ
duo install <bundle id> --yes               #   ("MuseScore Studio": "MuseScore 4" matched nothing)
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
| `ditto: Couldn't read PKZip signature`, or a ~15 KB download | The vendor served an HTML page. The installer refetches; if it still fails, look at the vendor (Cork did this until its 2026-10-17 fix) |

**Reading the `changelog pane` line.** It names what the workbench pane shows,
in the pane's order: a changelog recipe beats the source's structured log,
which beats raw inline notes, which beat the vendor page in a web view. The
winning *source* doesn't decide it (Fork is detected through Sparkle but shows
its recipe), nor does `release notes N chars inline`. `headings [...]` means
sections were kept; `headings []` with a heading's text among the first items
means they were flattened (Osaurus, Mos). `raw inline notes`, `web page` and
`none` are all "not structured": say which, and why.

**Clean up — reversibly.** Check `pgrep -f "/Applications/<App>.app/"`, then
move the test installs to the Trash, never `rm`:

```bash
osascript -e 'tell application "Finder" to delete POSIX file "/Applications/<App>.app"'
```

Then tell the user what is left for them: the Trash, the rollback copies
`duo install` made (listed by `duo backups`), and the permission rule.

Record the result in each audit doc's 一键安装 section **and** its README row,
replacing the agent's placeholder (「待主会话」, 「端到端未做」) rather than
leaving it beside the result. `scripts/check_app_audits.py` fails on 「待主会话」
left in the README.

## Phase 6: Report

One row per app, all three counts, `✓ + evidence` or `✗ + reason`, never
blank:

```markdown
| App | 检测 | 一键 | Changelog |
|---|---|---|---|
| Neovide | ✓ GitHub, 0.16.1→0.16.2 | ✓ e2e 0.16.1→0.16.2 | ✓ 结构化，小标题 Bug Fixes / Docs |
| Osaurus | ✓ Sparkle + binding | ✓ e2e（含 EdDSA） | ⚠ 结构化但小标题被压平成条目 |
| Secretive | ✓ GitHub | ✓ e2e 3.0.4→4.0.0，换包后重启 SSH agent，签名实测通过 | ✓ Features / Fixes |
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
- `scripts/check-bundle.sh` — package identity, signature, notarization, nested apps, components that run outside the app, references to the app's own GitHub releases
- `scripts/scaffold-github-rule.py` — drafts a new single-rule GitHub family from its real package (`--facts` replays it on an `install-verify` report)
- `scripts/integrate.sh` — cherry-pick with README/index conflict resolution
- `.claude/skills/app-audit/SKILL.md` — the per-app method each agent follows
- `.claude/skills/channel-discovery/SKILL.md` — the sibling breadth pass, for channels of covered apps
- `application-test/` — `feed-discover` (Phase 2), `channel-verify` (detection and the `changelog pane` line)
