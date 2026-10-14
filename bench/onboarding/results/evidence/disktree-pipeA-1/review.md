No BLOCKING findings. Detection, the digest-only one-click gate and the changelog claims all held up against the vendor's real releases and the repo's own checks. There are four NOTEs, all about evidence or documentation gaps, not unsafe behaviour.

**What I checked and confirmed:**
- **Tests:** `swift test --package-path DuoUpdaterCore --filter 'DigestOnly|GitHubAssetSelection|RecipeGolden|AppAuditCoverage|GitHubReleaseRule|RecipeRegistry|Registry'` gave "166 tests in 22 suites passed", exit 0. That includes `DigestOnlyRecipeTests`, `GitHubAssetSelectionTests` and the goldens.
- **Repo checks:** `check_app_audits.py`, `check_ifchange.py --base 90f8415`, `check_recipe_snapshots.py`, `check_prose_claims.py` and `check_skill_docs.py` all pass.
- **Releases:** v0.9.0–v0.11.0, none marked prerelease. macOS zips exist from 0.10.0 on. The vendor's release workflow only publishes once every build is in, with `--latest`, so `/releases/latest` never shows a half-uploaded release.
- **Digests:** GitHub's `digest` values for the four 0.10.1/0.11.0 zips match the doc's table.
- **Pattern:** `^disktree-[0-9.]+-(?:aarch64|x86_64)-macos\.zip$` excludes the `.sha256` files, Linux and Windows. `HostArch` recognises both `aarch64` and `x86_64`.
- **Changelog:** the 0.11.0 notes really have 23 items under `## What's Changed` plus a `## New Contributors` section, as the doc says.
- **Other channels:** there is no Homebrew cask or formula, no Mac App Store listing and no prerelease track, so "stable only" is right.
- **Vendor build:** `Info.plist.in` fixes the bundle id. `xtask bundle` signs ad-hoc (`codesign --sign -`) whenever the repo has no Developer ID secrets.
- **Team-ID change:** the doc says a future Developer ID build blocks one-click only once. That matches the code: a Team-signed installed copy goes back to the normal Team-ID gate.

## Findings

**NOTE 1 — The one-click route ships without its end-to-end run, and the doc's status field doesn't say so.**
- **Evidence:** the doc says `状态: **digest-only**` and `端到端: **未跑**`. The skill says a one-click route is proven only by an end-to-end run, which is what the Lokii row in the index records.
- The doc's own Known Issues leaves open whether the Full Disk Access grant survives a swap of an ad-hoc build. That grant is the app's main requirement. My guess, not checked: for ad-hoc signed apps the permission may be tied to the exact build, so it could be lost on every update.
- **Fix:** set `状态: 需要验证` until the coordinator runs both rounds (setting off → refused; setting on → 0.10.1 to 0.11.0). In that run, also check whether Full Disk Access survives, and record the result under Known Issues.

**NOTE 2 — Missed installed copy: source builds on macOS are in scope, but the doc says they aren't.**
- **Evidence:** the doc says `分发: 只有 GitHub Releases（另有 AUR、源码构建，都不在 macOS 检测范围内）`.
- The vendor's README and Makefile give `make install` as a macOS route. It runs `xtask bundle` (ad-hoc signed, same `io.github.tobi.disktree`, version taken from `Cargo.toml`). It then copies the result to `~/Applications/disktree.app` and adds a symlink `~/.local/bin/disktree` pointing at `$(APPS)/disktree.app/Contents/MacOS/disktree`.
- `AppScanner` scans `~/Applications`, and the rule matches on bundle id. So a source-built copy is detected, and once a newer tag exists the digest-only route would replace it with the release build.
- **Fix:** correct that doc line and add a Known Issues entry: a source build is detected and replaced by the release zip. The CLI symlink should keep working because it points at the bundle's path. That last part is my reading of the Makefile; I didn't test a swap.

**NOTE 3 — Old version 0.10.0 was never examined.**
- The doc says macOS assets exist "from 0.10.0 on" but checked only 0.10.1 and 0.11.0.
- **What I confirmed** on the 0.10.0 arm64 zip:
  - The download's `shasum` is `efe3c3ba…c49`, which equals GitHub's digest.
  - The Info.plist has `io.github.tobi.disktree`, short version = build = `0.10.0`, and a macOS 11.0 minimum.
  - The zip has the same 9 entries, with nothing nested.
- **Not checked:** the 0.10.0 code signature and the x86_64 zip. Unpacking the zip and running `channel-verify` on it were both denied by the permission settings.
- **Fix:** run `codesign --verify --deep --strict` / `codesign -dvv` and `channel-verify` on both 0.10.0 zips and add them to the doc's checked set. Otherwise, say in the doc that 0.10.0 was not checked.

**NOTE 4 — The test fixtures say they are real asset listings, but they are trimmed.**
- **Evidence:** `gh api repos/tobi/disktree/releases` shows 12 assets for both v0.11.0 and v0.10.1.
  - `DigestOnlyRecipeTests.expected` lists 8 for 0.11.0 (missing the four Linux/Windows `.sha256` files) and only 2 for 0.10.1.
  - The `GitHubAssetSelectionTests.multiCandidateCases` entry lists 7, missing `disktree-0.11.0-aarch64-windows.zip` and four `.sha256` files.
  - Both tables' comments say they hold what the vendor actually published.
- None of the missing names would match the pattern, so the tests still pass. But they don't contain what their comments say.
- **Fix:** paste the full 12-name listings from the API. While there, the comment "Exactly one arm64-runnable dmg" and the name `eachPatternPicksTheOneDmgForThisMac` now also cover zips.

**NOTE 5 (minor) — A vendor rebuild can make the "latest" release point backwards.**
- **Evidence:** in `release.yml`, the manual `workflow_dispatch` path rebuilds an existing tag. Its `publish` job then runs `gh release edit "$TAG" --latest`, so rebuilding an old tag makes `/releases/latest` return that old release.
- This fails safe: an up-to-date copy just sees nothing newer, and `RecipeSanity` flags a feed that reads behind the installed copy.
- **Fix:** one line in the doc's 注意事项 so the next person doesn't mistake it for a broken rule. No code change.
