I found nothing that should stop this onboarding from merging: the code is correct, the tests pass and one-click is safe. One real coverage gap (old-id copies get no update detection) is honestly written up but needs a decision, and the audit doc has four factual errors to fix.

## What I ran
- **Full test suite on HEAD:** `swift test` in `DuoUpdaterCore` gave "4567 tests in 383 suites passed … with 1 known issue". That known issue is the existing schema-drift test, which is unrelated.
- **Focused suites:** Spotifast, BundleIDMigration, RecipeHealthKey, RecipeGolden and AppAuditCoverage: "31 tests in 5 suites passed".
- **Audit-doc checker:** `python3 scripts/check_app_audits.py` exits 0. The working tree is still clean.
- **Live releases API (re-checked today):** the newest release is still `v0.13.0` (`prerelease false`), and the dmg digest `7c16925e…a93c` matches the doc.
- **Two dmgs nobody had checked:** I ran `check-bundle.sh` on 0.10.0 and 0.8.0, which the planner had downloaded but neither the planner nor the executor checked. Each dmg's `shasum -a 256` matches the API digest.
  - 0.10.0: `rocks.spotifast.Spotifast`, Team `JPL7999US3`, notarized.
  - 0.8.0: `me.paolino.fastpotify`, same Team, notarized.
- **Vendor source at the tags (`src/updates/macos.rs`):** 0.8.0 and 0.9.0 only accept `me.paolino.fastpotify`, while 0.9.1 accepts both ids. So copies on 0.8.0 or 0.9.0 can't update themselves to any current release.

## Findings

**NOTE 1: Old-id copies (0.9.1 and earlier) get no update detection. This is the biggest gap, and it needs a decision.**
- **Evidence:**
  - The executor's reason for dropping the planned second rule holds. `recipeID` is `github:<slug>:<channel>`, with no bundle id in it (`GitHubReleasesSource.swift:426`). The executor's log shows `rulesSharingASlugRecordSeparateHealthEntries` failing with two `github:crmne/spotifast:stable` rules.
  - I scanned every golden file: no two existing rules share a repo and a channel, so there's no precedent to copy.
  - With the current code, channel-verify on the 0.9.1 and 0.5.0-rc2 copies says `unknown (no source answered)`.
- **Who it hurts:** the 0.8.0 and 0.9.0 copies, whose own updater refuses every current release. They are the users who need duo most.
- **Fix (a small Core change, which the plan had ruled out):** in `GitHubReleasesSource.swift:651`, fall back to `rules[app.recipeBundleID]` when there's no rule for the on-disk id.
  - This only changes behaviour for ids listed in `BundleIDMigration`. Today WorkBuddy is the only other entry, and it has no GitHub rule. So "a Core behaviour change for every GitHub app" overstates the risk.
  - Prefer this to putting the bundle id into `recipeID`. That would change the baseline key for every rule, and `Baseline.prune` would then treat the existing rows as orphans.
  - Then re-run channel-verify on the old-id copies. Do the old-id one-click round (plan step 9c) before claiming one-click for them.
- **Doc correction:** the doc says this "can only be fixed in Core", but there's a route without a Core change. `VendorProbeSource` looks recipes up by `recipeBundleID` (`VendorProbeSource.swift:345`), so a VendorProbe recipe keyed on the new id would reach old-id copies. It would run anonymously against `api.github.com` (60 requests an hour) and no existing probe reads that API. The audit should mention this route and say why it was rejected.
- **Wording to fix with it:**
  - The comment in `SpotifastCoverageTests.theOldIdHasNoGitHubRule` and the recipe comment both frame the fix as a `recipeID` change. That contradicts the doc's own next-step #3 (`recipeBundleID` lookup).
  - The coverage matrix marks old id as ✗ ("investigated, not feasible"). It should be ○ ("possible, not implemented").

**NOTE 2: One-click for the new id is presented as done, but the end-to-end install was never run.**
- The plan said not to report it as ✓ until step 9a passed.
- **Fix:**
  - Coverage matrix: change "GitHub ✓（新 id：检测 + 一键 dmg" to show detection ✓ and one-click "需要验证" (needs verification).
  - 一键安装 status: use the template's "需要验证" value.
  - Commit subject: don't claim one-click.
  - Run step 9a (and 9b) when the end-to-end install is allowed. The README line already says "端到端未跑" (not run), which is correct.

**NOTE 3: Wrong release counts in the doc, copied from the plan.**
- The doc says "21 个稳定版 … 9 个 rc" (21 stable, 9 rc).
- Live API: 23 stable and 7 prereleases. The tags are v0.4.0-rc1 to rc5 plus v0.5.0-rc1 and rc2, which makes 7.
- **Fix:** change it to 23 / 7.

**NOTE 4: Changelog point (c) is wrong.**
- The doc says the 0.1.x releases fall outside `maxEntries: 20`.
- They don't. There are 23 stable releases, and the decoder skips bodies that parse to nothing and keeps going (`StructuredChangelogDecoder.swift:723-728`).
- The pane's "19 entries" is exactly the 19 stable releases from 0.2.0 to 0.13.0. So all four 0.1.x bodies (`**Full Changelog**: …` only) produced nothing and were dropped. That's harmless.
- **Fix:** restate (c) that way.

**NOTE 5: The rename bound is labelled as inferred, but it has now been measured.**
- The `BundleIDMigration.swift` comment and the doc say 0.10.0 is "inferred" and the 0.8.0 and 0.10.0 dmgs weren't downloaded.
- The type's own doc comment asks for "versions as observed on real artifacts".
- I measured both (results above). The bound `0.9.1 → 0.10.0` and the Team are correct.
- **Fix:** change "inferred" to "measured", add 0.8.0 and 0.10.0 rows to the rename table with their digests, and also add the 0.1.0 row, which fails `codesign --verify`.

**NOTE 6: Known risks are recorded correctly. No change needed.**
- Copies installed from the vendor's Homebrew tap: same treatment as the SuperCmd and diri audits.
- The possible downgrade by the vendor's own updater: from source, not reproduced.
- Copies built from source with Nix: from source, not verified.

## Plan checklist, item by item

| Plan item | Result | Do I agree? |
|---|---|---|
| §0 facts | Covered. Newest release re-checked, still 0.13.0 | Yes, except the counts (NOTE 3) |
| §1a ids and signing by era | Partly covered: 0.1.0, 0.8.0 and 0.10.0 rows missing, and 0.10.0 called inferred | Partly (NOTE 5) |
| Rename bound 0.9.1 → 0.10.0, Team JPL7999US3 | Covered | Yes, now measured |
| §1b vendor updater by era | Covered | Yes. I confirmed the 0.8.0/0.9.0 vs 0.9.1 split at the tags |
| #1 new id, 0.10.0 and later | Covered: GitHub rule, dmg one-click, changelog recipe. End-to-end not run | Detection and changelog yes; one-click not yet (NOTE 2) |
| #2 new id at `Fastpotify.app` | Covered, because rules match by id | Yes (not tested end to end) |
| #3 old id 0.8.0–0.9.1, Developer ID | **Missed.** The plan's route breaks a test, and it was written up as a gap | The reason holds, but it needs the Core fix (NOTE 1) |
| #4 old id 0.2.0–0.7.1, ad-hoc signed | Detection missed (same cause). No one-click, as planned | One-click "never" is right; detection waits on NOTE 1 |
| #5 0.1.x | Same as #4 | Same |
| #6 release-candidate builds | Detected as stable (channel-verify); no update source; changelog through the migration entry | Yes. Detection waits on NOTE 1 |
| #7 vendor-tap Homebrew copy | Recorded as a known issue, no code | Yes |
| #8 Nix / source builds | One line in the doc, from source | Yes |
| Beta/nightly channel | None, settled from `settings.rs` | Yes |
| Resident helper | None; the tray-resident main process is covered | Yes |
| What the rules read | The public release anyone can download | Yes |
| Published digest | Handled by GitHub's `digest`; five downloads matched | Yes |
| Steps 7–8: goldens, channel-verify, focused test, `make test` | Done. The test checks that there is no old-id rule (the plan wanted one) | Yes. Suites pass on my re-run |
| Step 9 end-to-end | 「未跑」 (not run), with a reason | Acceptable given the brief. 9c can't happen until NOTE 1 is fixed |
| Steps 10–11: audit doc and README line | Done; the checker passes | Yes, apart from NOTES 2–5 |
| Boundaries: Core changes, parser, tap | Followed. The Core lookup change is listed as a next step | Yes, but I'd escalate that next step (NOTE 1) |
