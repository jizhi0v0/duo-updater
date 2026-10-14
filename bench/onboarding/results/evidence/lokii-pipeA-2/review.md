No blocking problems in the recipe itself. The rule, version pattern, asset pattern and digest-only trust are correct for every release Lokii has published. There is **one BLOCKING** problem: the settings text that asks users to opt in to digest-only installs still names only three apps, so Lokii was added without telling them. There are also five NOTEs, mostly gaps in the docs.

## What I checked
- **Release metadata** (`gh api repos/huangy7/lokii/releases`): three releases, v0.1.0, v0.1.1 and v0.1.2. All are `prerelease:false` with assets `Lokii-arm64.dmg` and `Lokii-x86_64.dmg`, and every asset has a `digest`. There is no other release track.
- **All six dmgs downloaded.** `shasum -a 256` matches the API `digest` for every one, including v0.1.0, which the onboarding didn't check.
- **All six mounted read-only.** Every one is `com.lokii.app` with the short version equal to the tag and `CFBundleVersion` 1. Every one is `Signature=adhoc`, `TeamIdentifier=not set`, signed as `Identifier=com.lokii.app`, and passes `codesign --verify --deep --strict` (rc=0). Each is single-arch, has `LSMinimumSystemVersion` 13.0 and `LSUIElement` true, and has no nested apps.
- **Vendor source.** `release.yml` creates a draft, uploads both architectures, and only publishes if both build legs succeed. The notes line is hardcoded. `build.sh` signs ad-hoc unless `LOKII_SIGN_IDENTITY` is set. `AppUpdater.swift` only opens the download URL. The vendor site's download links point to `releases/latest/download/Lokii-{arm64,x86_64}.dmg`, the same assets.
- **Swift tests.** `swift test --filter 'DigestOnlyRecipeTests|GitHubAssetSelectionTests|RecipeGoldenTests|AppAuditCoverageTests|GitHubReleaseRuleTests'` → "104 tests in 4 suites passed". The `GitHubReleaseRuleTests` part of the filter probably matched nothing, because that file holds free test functions rather than a suite.
- **Script checks.** `make test` stops at Python 3.9, so the onboarding never reached the checks after that point. I ran each one by hand and all passed: `check_app_audits`, `check_recipe_snapshots`, `check_prose_claims`, `check_engine_notes`, `check_skill_docs`, `check_offpool`, `check_localizable_specifiers` and `check_staged_version_use`. `test_app_test_coverage.py` also passes under `uv run --python 3.12` (38 OK).
- **Not reproduced:** `channel-verify` returned "GitHub rate limit reached" even with `GH_TOKEN` set, although `gh api rate_limit` showed 3051 calls left. So I couldn't re-check the UPDATE → 0.1.2 result myself, and I don't know why the token wasn't used.

## Findings

**BLOCKING 1 — The opt-in text for digest-only installs doesn't mention Lokii**
- **Evidence:** the toggle that gates this route says "For apps whose GitHub releases are only ad-hoc signed: Alacritty, Flameshot and darktable." That text is in `App/Sources/Settings/GeneralSettingsPage.swift:144` and in `App/Resources/Localizable.xcstrings:11361–11421` (all 10 translations).
- **Effect:** a user who turned the toggle on after reading that list will now also get one-click installs of Lokii under the weaker trust model, without being told.
- **Fix:** add Lokii to the English string and all 10 translations, or reword it so it doesn't list apps.
- **Also:** add `com.lokii.app` to the ad-hoc list in `GitHubReleaseRuleTests.swift:1028` (`unsignedBuildsStayDetectionOnly`). Tests still pass without it, because `DigestOnlyRecipeTests` already checks the whole set.

**NOTE 2 — One-click is claimed but hasn't been run end to end**
- **Evidence:** the README row says "G (one-click …)" alongside "一键端到端未跑", and the commit says so too. This is disclosed honestly.
- **Why it matters here:** this would be the first end-to-end run for an app that is both menu-bar-only (`LSUIElement`) and ad-hoc signed.
- **Fix:** run the end-to-end install serially: put 0.1.1 or 0.1.0 into `/Applications`, turn on digest-only, then `duo install com.lokii.app --yes --json`, both with the app not running and with it running. Write the result into 一键安装 before treating one-click as ✓.

**NOTE 3 — Installs from the vendor's Homebrew tap aren't explained; the matrix just shows "—"**
- **Evidence:** the vendor maintains `huangy7/homebrew-tap` `Casks/lokii.rb`. It is still at 0.1.1, downloads these same GitHub dmgs by architecture, and installs `Lokii.app`. `HomebrewCaskCatalog` only reads homebrew/cask's main index, so `HomebrewCaskSource` never answers for a tap install. The app falls through to GitHub, and one-click replaces an app Homebrew installed, while Homebrew's own record (the Caskroom) still says 0.1.1.
- **Fix:** in `com-lokii-app.md`, change the Homebrew cell to ✗ with that reason, and add a sentence to 覆盖矩阵 or 已知问题. `com-supercmd-SuperCmd.md:35` already explains the same mechanism and can be the model.

**NOTE 4 — v0.1.0 is left out of the docs and tests**
- **Evidence:** the doc and the recipe comment only mention 0.1.1 and 0.1.2. I checked v0.1.0: both dmgs are ad-hoc, `com.lokii.app`, pass verification, are single-arch, have `LSMinimumSystemVersion` 13.0, and their digests match (arm64 `2d548bf6…2ef2924`, 1,974,275 B; x86_64 `483685fd…856a`, 2,081,789 B). So users on 0.1.0 are covered, but nothing says so.
- `DigestOnlyRecipeTests` says it covers "every stable release with a digest", but its Lokii entry lists only one release.
- **Fix:** add v0.1.0 to the doc's digest table and signature notes. Either list all three releases in `expected` (and `picks`), or reword the test's doc comment.

**NOTE 5 — Losing Full Disk Access after updates isn't recorded**
- **Evidence:**
  - Lokii depends on Full Disk Access (`AppDelegate.swift` calls `checkAndPromptFDA()` on launch and opens `FDAGuideWindowController` when access is missing).
  - The repo's own toggle text warns that "macOS may ask you to grant these apps' privacy permissions again after each update".
- **Unverified:** I'm inferring that every update of an ad-hoc build, by hand or one-click, makes Lokii ask for Full Disk Access again. I haven't measured it.
- **Fix:** add this to 已知问题, and check it during the NOTE 2 end-to-end run.

**NOTE 6 — The `CFBundleVersion` explanation is wrong**
- **Evidence:** the doc says `CFBundleVersion` is always 1. In fact `scripts/build.sh` sets it to `git rev-list --count HEAD`. It is 1 only because `release.yml` checks out with `actions/checkout@v4`'s default depth of 1.
- **Fix:** state the real cause ("settled from source: `scripts/build.sh` + shallow checkout"). This has no effect on detection, because the GitHub rule compares marketing versions.

Correct as written: the recipe (`^v([0-9]+(?:\.[0-9]+)+)$`, `^Lokii-(arm64|x86_64)\.dmg$`, `.dmg`, `.publishedDigestOnly`, stable only), the goldens, the README section, the decision to skip a changelog (the release body is the hardcoded line and the repo has no CHANGELOG), the delta table, the "public GA" answer, and the warning about the vendor switching to Developer ID signing later (`teamIdentifierAppeared`).
