I found three blocking problems and five notes. The recipe for current installs is correct: the rule, the dmg pattern, the Team ID, the digests, the changelog and the README placement all check out against the real releases, and the tests pass. What's missing is coverage of older installs, and one safety claim in the audit doc is wrong.

**What I ran:**
- `swift test --filter "SpotifastGitHubRuleTests|RecipeGoldenTests|AppAuditCoverageTests|BundleIDMigration"`: 22 tests in 4 suites passed.
- `python3.14 scripts/check_app_audits.py`: "✓ app audits consistent — 236 docs".
- I downloaded and mounted read-only (in `scr/review/dl`) the macOS dmgs for 0.1.0, 0.5.0-rc2, 0.5.0, 0.6.0, 0.7.1, 0.8.0, 0.9.0, 0.9.1 and 0.10.0.
- I ran `channel-verify` on the 0.9.1 dmg.
- I read the vendor's `bundle.sh` at several tags, `src/updates.rs`, the `crmne/homebrew-tap` cask, and the `fastframe-update` v0.5.2 README plus its `helper.rs` and `macos.rs`.

## BLOCKING

**1. Every release before 0.10.0 has a different bundle id, and those installed copies get no update at all.**
- **Evidence:**
  - `packaging/macos/Info.plist` at v0.1.0, v0.5.0, v0.8.0 and v0.9.0 sets `me.paolino.fastpotify`.
  - `bundle.sh` at v0.9.1 keeps the old id for that release on purpose ("Last bridge for older updaters' bundle identity validation").
  - The mounted dmgs agree:

    | Releases | Bundle id | Signature |
    |---|---|---|
    | 0.1.0–0.7.1 | `me.paolino.fastpotify` | ad-hoc, `TeamIdentifier=not set` |
    | 0.8.0–0.9.1 | `me.paolino.fastpotify` | Team `JPL7999US3`, notarized |
    | 0.10.0 | `rocks.spotifast.Spotifast` | Team `JPL7999US3` |

  - `channel-verify scr/review/dl/spotifast-v0.9.1-macos-universal.dmg` prints `winning source <none> … status unknown (no source answered)`.
  - The audit doc never mentions `me.paolino.fastpotify`.
- **The code already supports this case:**
  - `BundleIDMigration` (added for WorkBuddy in b490286) lets the signature gate accept a download signed with the new id over a copy signed with the old one.
  - It doesn't help on its own here. `GitHubReleasesSource` looks rules up by `app.bundleID` (`GitHubReleasesSource.swift:651`), not by `recipeBundleID`, which only `VendorProbeSource` and `ChangelogRecipeSelection` read.
  - Keying several rules on one repo is already done (Zed and Zed Preview).
- **Fix:**
  - Add a second `GitHubReleaseRule(bundleID: "me.paolino.fastpotify", owner: "crmne", repo: "spotifast", <same installAssetPattern>, installerKind: .dmg)` to `rocks-spotifast-Spotifast.swift`.
  - Add `BundleIDMigration(from: "me.paolino.fastpotify", to: "rocks.spotifast.Spotifast", teamID: "JPL7999US3", lastFromVersion: "0.9.1", firstToVersion: "0.10.0")`.
  - Re-record the goldens.
  - Re-run `channel-verify` on the 0.9.1 dmg and expect `UPDATE → 0.13.1`.
  - Document the rename in the audit, including the evidence table above.
  - The ad-hoc copies (0.1.0–0.7.1) have no Team ID, so the migration's Team check should refuse one-click and leave them detection-only. I have not verified this; please test it and record the result.
  - A copy installed as `Fastpotify.app` keeps that name after a swap.

**2. The audit's claim that duo and the app's own updater can't end up installing different versions is wrong according to the vendor's source.**
- **Evidence:**
  - The doc says "所以两边并存不会装成不同的版本", reasoning that both read the same `/releases/latest`.
  - `fastframe-update` downloads into a `.spotifast-update-<hex>` folder next to the app and keeps the pending update in process memory. It only swaps when the user clicks restart.
  - `macos.rs::replace()` checks the staged package against its own version. It then renames whatever bundle is at the target to `previous` and moves the staged one in. It never compares against the version now on disk.
  - So if an older build is staged (say 0.13.0) and duo installs 0.13.1 while the app is running, clicking the in-app restart puts 0.13.0 back. This is exactly the "staged build older than duo's" case the skill's round 2 tells you to test.
  - I got this from reading the source; I did not run it.
- **Precedent:** `SelfUpdaterStaging` / `MagpieStagingClearance` already handle an updater that "swaps without comparing versions" (magpie) by moving its staging folder aside.
- **Fix:**
  - Remove the claim.
  - Either add a fastframe case to `SelfUpdaterStaging`, following the magpie pattern (folder `.spotifast-update-*` next to the bundle), or record the possible downgrade under 已知问题.
  - In both cases keep "end-to-end round 2" as required work.

**3. One-click is marked supported with no end-to-end run.**
- **Evidence:** The doc says `状态: **支持**` and also `端到端: **未跑**`. The README line is ticked `[x]`. The skill says a one-click route is proven only by an end-to-end run.
- **Fix:** Set the status to `需要验证`, or run both rounds. Given #2, round 2 is the one that matters.

## NOTE

**4. The vendor's own Homebrew tap is missing from the audit.**
- The README lists `brew install --cask crmne/tap/spotifast` as the main macOS install, and `crmne/homebrew-tap/Casks/spotifast.rb` tracks every release up to 0.13.1. `brew info --cask spotifast` says no such cask in homebrew-cask.
- `HomebrewCaskCatalog` only reads the main cask index, so for a tap install the GitHub rule answers. One-click then replaces a bundle that Homebrew manages, which is exactly what `fastframe-update` refuses to do.
- **Fix:** Change the Homebrew cell to "— (third-party tap, not indexed)" as the SuperCmd audit does, and note that Homebrew's own records of the install will be out of date after a duo one-click.

**5. The rc row lists the wrong detection signal.**
- The doc says detection is "`CFBundleShortVersionString` 带 `-rcN`". `ReleaseChannel.detect()` has no generic `-rc` rule (only the CotEditor-specific one), so an rc copy is read as stable and offered the final release. That is acceptable, and the vendor's updater does the same.
- All 7 rc builds are also the old id and ad-hoc signed, so they depend on #1.
- **Fix:** Say "reads as stable; offered the GA (same as the vendor's updater)".

**6. The duplicate-asset comment is incomplete.**
- The rule comment, the test comment and the doc all say only 0.9.x carries `fastpotify-` copies. 0.8.0 does too.
- In 0.8.0–0.9.1 the `spotifast-` dmg has the same sha256 as the `fastpotify-` one and contains `me.paolino.fastpotify` bundles. The anchor keeps the macOS dmg as the only candidate, but it does not separate the new app from the old one.
- **Fix:** Correct the wording to cover 0.8.0 and the identical bundles.

**7. The test only checks name matching.**
- **Fix:** Once #1 is in, add tests that `me.paolino.fastpotify` at 0.9.1 maps to the new id, that 0.10.0 does not map, and that the migration needs Team `JPL7999US3`.

**8. Checker environment.**
- `make test-scripts` failed under the system Python 3.9 (`TypeError` on `set[str] | None`). This comes from the environment, not the change. The checker passes on Python 3.14.

The downloaded dmgs are in `scr/review/dl`, and nothing was installed or launched.
