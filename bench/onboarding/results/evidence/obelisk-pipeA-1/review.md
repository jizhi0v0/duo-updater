I found one blocking gap, in old installs, and five smaller notes. The Sparkle detection and the changelog recipe themselves look correct.

**What I checked:**
- **Tests and audit check:** `python3 scripts/check_app_audits.py` passed (224 docs). `swift test --filter 'RecipeGoldenTests|AppAuditCoverageTests|ChangelogRecipe'` passed 123 tests.
- **Appcasts:** both live appcasts (arm64 and x64) have one item each, pointing to v0.2.5. The x64 zip size matches the release asset (138591697 bytes).
- **Release workflow:** `release-app.yml` builds only on `v*` tags, separately for arm64 and x64, with one `SUFeedURL` per architecture. So the "single stable track" claim holds.
- **Old releases:** I downloaded the 0.1.0 zip and the 0.2.1 and 0.2.2 dmgs, and mounted the dmgs read-only.

---

**1. BLOCKING: installs of 0.1.0–0.2.2 get no update detection.**

The audit leaves this marked "未验证" (unverified). I checked, and none of those versions can be detected:

| Version | Bundle id | `SUFeedURL` | `app-update.yml` | Signature |
|---|---|---|---|---|
| 0.1.0 (zip) | `com.obelisk.app` | none | none | no Team ID |
| 0.2.1 (dmg) | `com.obelisk.app` | none | none | `TeamIdentifier=not set` |
| 0.2.2 (dmg) | `com.obelisk.app` | none | none | `flags=0x20002(adhoc,linker-signed)`, `Identifier=Electron`, "code has no resources but signature indicates they must be present" |

- **Why nothing answers:** there is no cask (`brew search obelisk` only returns `bazelisk` and `blisk`). There is no GitHub rule, and no Electron manifest in these builds. So every source misses, and these copies show as unknown.
- **Why it matters:** these are 5 of the 7 releases, and the newest of them is from 2026-08. The vendor's own release notes say these users must update by hand once. They are the installs that most need a detection signal.
- **The codebase already handles this shape:** `app-macdown-macdown3000.swift` uses a GitHub rule for older copies without `SUFeedURL`, and lets `SparkleAppcastSource` answer for newer ones. GitHub Releases comes after Sparkle in `SourceStack.make`.
- **Fix:**
  - Add `githubRules: [GitHubReleaseRule(bundleID: "com.obelisk.app", owner: "tommy0103", repo: "obelisk")]` to `com-obelisk-app.swift`, with no `installAssetPattern`, so it is detection only.
  - One-click can't work for these copies on either route. The installed copy has no Team ID and the 0.2.5 download has `433DLLA855`. The standard check (`verifyTeamIdentifierMatch`) refuses with `noTeamIdentifier(installed)`, and the hash-checked route for ad-hoc apps refuses with `teamIdentifierAppeared` (`SignatureVerifier.swift:189`).
  - Say in the comment and the audit doc that this one manual update is unavoidable.
  - Also note that 0.1.0 and 0.2.1 declare macOS 11.0 as their minimum, while 0.2.2+ need 12.0. A macOS 11 install would be shown an update it can't run.
  - Re-record the goldens, and update the audit doc's 已知问题 section, its coverage matrix (GitHub column, stable row: ✓, detection only) and the README row.

**2. NOTE: the changelog recipe has no fixture test.**
- `.claude/skills/fragile-recipe/SKILL.md` step 8 says a fixture test on a trimmed slice of the real response is "required".
- The two closest precedents both have one: `RockxyChangelogRecipeTests.swift` and `ShotbaseChangelogRecipeTests.swift`. `com.obelisk.app` appears in no test outside the golden file.
- **Fix:** add an `ObeliskChangelogRecipeTests` built from a trimmed v0.2.5 releases response. It should assert that the `##`/`###` headings ("Highlights", …) survive as headings.

**3. NOTE: the npm CLI, which the vendor recommends, is not mentioned.**
- The vendor README's recommended install is `npm install --global @obelisk-apps/cli` (also what `install.sh` runs). It is versioned separately: `latest` 0.3.0, `rc` 0.2.6-rc.0.
- The generic npm support from #949 should detect it. Its changelog would be empty, because the registry manifest has `repository: None`. That also means app tag v0.2.5's notes can't attach to CLI version 0.2.5.
- **Fix:** add a line to the audit doc saying the CLI is covered by the generic npm path, with versions that don't line up with the app.

**4. NOTE: one row of the Phase 3⅞ table is missing: does the app's own updater compete with ours?**
- The bundle sets `SUAutomaticallyUpdate=false` and `SUScheduledCheckInterval=3600`, and Electron's updater is a fallback.
- **Fix:** state these values and the verdict. The app notifies but doesn't install silently, so it doesn't compete with ours.

**5. NOTE: one-click evidence is incomplete.**
- The end-to-end `duo install` was not run. The doc and commit say so honestly, but the README row is still checked `[x]`.
- The x64 zip's EdDSA signature was not checked, and only the x64 dmg was inspected, not the x64 zip the feed actually points to.
- **Fix:** run the 0.2.4 → 0.2.5 end-to-end install serially. Run the signature and bundle check on `Obelisk-0.2.5-mac-x64.zip`.

**6. NOTE: the full test gate didn't complete.**
- The executor's `make test` stopped early at `scripts/app_test_coverage.py:280`: `TypeError: unsupported operand type(s) for |`. This is because the system `python3` is 3.9.6, which predates the `X | None` syntax that line uses.
- That's an environment problem, not this change, and the full core `swift test` run passed (4237 tests). But the later steps of `make test` never ran, including the CLI package tests, the app tests and `check_localizable_keys.py`.
- **Fix:** rerun `make test` with Python 3.10 or newer before merging.

I made no edits. My downloads are in `scr/review/` (`v010`, `v021`, `v022`, `feed`).
