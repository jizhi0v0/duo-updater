# OpenInTerminal onboarding review: nothing was delivered

The onboarding is empty, so there is no code to judge for correctness. There were no commits, and the executor stopped to ask a question. Every finding below is something the redo has to cover.

## What was checked
- `git log --oneline -5`: HEAD is still `57e6ce0` (the Reviu commit), and `git status` is clean, so `git diff 57e6ce0…HEAD` is empty.
- In the run directory, `exec.diff` is 0 bytes and `exec.head` is `57e6ce0…`.
- Searching the repo for "openinterminal" returns no matches.
- The executor's transcript (`exec.jsonl`) shows why. Its `ditto -x -k` extraction of the downloaded zips was denied. It then stopped and asked to be allowed to extract. It exited 0, which a pipeline could read as success.

## Findings

**BLOCKING 1: No onboarding was produced.**
- **Evidence:** above.
- **Fix:** answer the executor's question, either by approving an extraction method into `scr/pkg-*/out` or by choosing detection-only, then re-run it. I didn't extract anything either, since that would get around the same denial.
- **Pipeline:** a run that finishes with exit 0 and an empty diff should be reported as "stopped / needs input", not as success.

**BLOCKING 2: Direct-download installs of all three apps would show as `.unknown`.**
- **Evidence:** none of the apps has a Sparkle feed, a Mac App Store listing or an in-app updater. A code search of the vendor repo only found matches in READMEs. `HomebrewCaskSource.swift:3-14` only picks up apps that Homebrew actually installed. Anything else falls through and stays "unknown until a vendor rule covers them".
- **Fix:** add a recipe set, modelled on `com-jorisgallot-reviu.swift`, with one `GitHubReleaseRule` per app, all pointing at `Ji4n1ng/OpenInTerminal`.

**BLOCKING 3: The Lite editions are a required part of the scope, not an extra.**
- **Evidence:** the one repo ships three apps. I read the bundle IDs from the vendor's project files:
  - `wang.jianing.app.OpenInTerminal`: `v2.x` tags, asset `OpenInTerminal.zip`.
  - `wang.jianing.app.OpenInTerminal-Lite`: `v1.x` tags, asset `OpenInTerminal-Lite.zip`.
  - `wang.jianing.app.OpenInEditor-Lite`: also `v1.x` tags, asset `OpenInEditor-Lite.zip`.
- **Also:** Homebrew has a cask for each one (`openinterminal` 2.3.9, `openinterminal-lite` 1.2.8, `openineditor-lite` 1.2.8). None of the casks is `auto_updates`.
- **Fix:** add three rules.

**BLOCKING 4: The Lite rules can't use `/releases/latest`.**
- **Evidence:** the endpoint returns `v2.3.9` today, but `v1.2.8` was published about 14 seconds after it (2026-07-13 12:08:34 and 12:08:48). Both release lines share one tag stream.
- **Fix:** give each Lite rule `usePrereleases: true`, which reads the release list, and a `^v(1\.[0-9]+(?:\.[0-9]+)*)$` pattern. Set the page size from the measured gap; in the history shown the v1 and v2 lines alternate, so 20 is plenty.
- **Main app:** pin `^v(2\.…)$`. Unverified, my guess: if a Lite release ever becomes "latest", a v2 rule that only reads `/releases/latest` may come back with no answer. `resolve()` only falls back to the list when an asset is missing, not when the tag pattern doesn't match. Either confirm that path in a test, or put the main rule on the list endpoint as well.

**BLOCKING 5: The asset name changed partway through the history, and the one-click checks were never done.**
- **Asset names:** releases up to v2.3.6 and v1.2.5 used `*.app.zip`. From v2.3.7 and v1.2.6 on they use `*.zip`. `installAssetPattern` should match the current names exactly: `^OpenInTerminal\.zip$`, `^OpenInTerminal-Lite\.zip$`, `^OpenInEditor-Lite\.zip$`. The main app's pattern must not catch the Lite zips, and each Lite pattern must not catch the other Lite zip.
- **Team ID:** the main project lists two teams, `C8VX3ZLX5U` and `Q33U8R4U57`. The expected Team ID has to come from `codesign` on the real v2.3.9 and v1.2.8 packages, not from the source.
- **Other package checks:** notarization, the `Info.plist` short/build versions compared with the tag, and the architectures still need to be read from the packages.
- **Fix:** one-click should only be enabled after those checks pass.

**BLOCKING 6: The deliverables Reviu included are all missing.**
- **Missing:** an `AppRecipeIndex.swift` entry, a golden in `Tests/RecipeGoldens/`, `docs/app-audits/<bundle-id>.md` and a `docs/app-audits/README.md` row (the full list is in `git show --stat 57e6ce0`). `make test` was never run.
- **Fix:** add these for each app, or one doc that covers all three, and paste the `make test` output.

**NOTE 7: Things for the audit doc to record.**
- **Changelog:** release bodies are markdown bullet lists, so `GitHubMarkdownParser` should be checked against the real v2.3.9 and v1.2.8 bodies.
- **Bundled parts:** the main app embeds a Finder extension and `OpenInTerminalHelper`, a login item. Replacing the app has to keep the bundle intact.
- **Minimum macOS:** the project sets deployment targets of 10.11 and 10.13. Read the real `LSMinimumSystemVersion` from the package.
