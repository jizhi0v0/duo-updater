## Review: Spotifast onboarding (`7bccb0b..d24cc0a`)

There is one **BLOCKING** finding and two **NOTE**s. The parts the onboarding did cover are correct; the problems are about what it left out.

### What I checked that holds up
- **Tests pass.** `swift test --filter 'spotifast|Spotifast|RecipeGoldenTests|AppAuditCoverageTests|BundleIDMigration'` ran 24 tests in 3 suites, all passed, rc=0. `python3 -I scripts/check_app_audits.py` reports "✓ app audits consistent — 236 docs", rc=0.
- **Test fixture is real.** The v0.12.0, v0.5.0-rc2 and v0.11.2 entries match the live API exactly (body, `prerelease`, `draft`, `published_at`). The asset names the test uses all exist in the real v0.13.0 listing.
- **Tags and the 0.10.0 identity are right.** All 30 releases use `vX.Y.Z`, and every `-rc` tag is flagged prerelease. I mounted the real 0.10.0 dmg: `rocks.spotifast.Spotifast`, Team `JPL7999US3`, which confirms "0.10.0 onwards".
- **Changelog headings are right.** The live v0.13.0 body has `## New`, `## Fixed`, `## Thanks`, which matches the doc's `headings ["New", "Fixed"]`.
- **The vendor site offers no other Mac build.** spotifast.rocks/download links the same `-macos-universal.dmg`.

---

### 1. BLOCKING: copies on the old bundle id `me.paolino.fastpotify` (0.1.0–0.9.1) get no detection, and the stated reason is wrong

The recipe comment and the audit's 「已知问题」 skip the old id because "switching identity is not an in-place update" (换身份，不是原地更新). Both the vendor and this code base say the opposite.

**Evidence:**
- **Real dmgs, mounted read-only:**

  | Version | Bundles in dmg | Bundle id | Team |
  |---|---|---|---|
  | 0.5.0, 0.6.0, 0.7.1 | `Fastpotify.app` | `me.paolino.fastpotify` | not set (ad-hoc) |
  | 0.8.0, 0.9.1 | `Fastpotify.app` and `Spotifast.app` | `me.paolino.fastpotify` | `JPL7999US3` |
  | 0.10.0 | `Spotifast.app` | `rocks.spotifast.Spotifast` | `JPL7999US3` |

  The repo's `packaging/macos/Info.plist` hard-codes `me.paolino.fastpotify` from v0.1.0 through v0.9.0.
- **The vendor does migrate in place.**
  - The v0.9.1 release notes say it "accepts the new archive and macOS bundle identities used by future releases".
  - The fastframe-update README (tag v0.5.1, §Renamed apps) says: "A bundle with a legacy bundle name is installed as `<app_name>.app` in the same folder."
- **The code base already handles this case.** `Models/BundleIDMigration.swift` was added in #1030. Its WorkBuddy entry is justified by "the vendor's own updater migrates old copies", which is the same situation as here.
- **The GitHub source can't find these copies through a migration entry alone.** `GitHubReleasesSource.swift:651` looks rules up by `app.bundleID`, not `recipeBundleID`. Nothing else in the repo mentions `fastpotify`. So these copies currently show as unknown. They are also the copies most likely to need help: the v0.9.1 notes say some older Mac builds' own update helper fails.

**Fix (in `rocks-spotifast-Spotifast.swift`):**
1. Add a second rule:
   ```swift
   GitHubReleaseRule(bundleID: "me.paolino.fastpotify", owner: "crmne", repo: "spotifast",
                     versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#, ...)
   ```
2. Add `BundleIDMigration(from: "me.paolino.fastpotify", to: "rocks.spotifast.Spotifast", teamID: "JPL7999US3", lastFromVersion: "0.9.1", firstToVersion: "0.10.0")`. This lets the changelog recipe, `AppRestarter` and the identity gate find old copies.
3. Copies at 0.7.1 and below have no Team, so the Team gate refuses them safely and they stay detection-only.
4. Two limits to write into the audit:
   - **Settings may be lost.** The v0.12.0 notes say settings and sign-ins from 0.9.0 or older "are no longer moved over… you start fresh". So one-click from 0.8.0 or 0.9.0 straight to the current release means starting fresh, which matches the vendor's own "install a newer release manually" advice. `BundleIDMigration` has no lower bound, so if that cost is not acceptable, leave `installAssetPattern` off the old-id rule.
   - **The folder name stays.** A duo swap keeps the copy at `Fastpotify.app`; the vendor's own updater would rename it to `Spotifast.app`.
5. Rewrite 「已知问题」 and the recipe comment to give these reasons, add tests, re-record the goldens, and run `channel-verify` on `spotifast-v0.9.1-macos-universal.dmg`.

### 2. NOTE: the vendor's own Homebrew tap is missed; "no cask" is wrong

- **What the onboarding says:**
  - The recipe comment says "no `SUFeedURL`, no Sparkle, and no cask".
  - The audit only checked the official Homebrew catalog, and the matrix shows Homebrew as "—".
- **What the vendor actually ships:**
  - The README's **first** macOS install route is `brew install --cask crmne/tap/spotifast`.
  - `crmne/homebrew-tap` has `Casks/spotifast.rb` (0.13.0, the same dmg, no `auto_updates`), and its `cask_renames.json` maps `fastpotify` to `spotifast`.
  - The download page also lists a Nix cache, and the vendor's `PACKAGING.md` says Nix packages the signed macOS `Spotifast.app`.
- **The conclusion still holds.** GitHub is still the source that answers, because `HomebrewCaskCatalog` reads only the official catalog. The SuperCmd recipe comment documents the same situation.
- **What the doc doesn't cover:**
  - For a tap-installed copy, duo's GitHub one-click replaces the app without Homebrew knowing, so Homebrew still records the old version.
  - The vendor's own updater refuses Homebrew-installed copies ("Update this installation with Homebrew", `detect.rs`).
- **Fix:**
  - Correct the recipe comment and 基本信息.
  - Set the Homebrew cell to ✗, with the reason "vendor tap only; the catalog doesn't read taps".
  - Add a line to 已知问题 about one-click on a copy installed from the tap.

### 3. NOTE: one-click is on but has never run end to end, including with the app running

The audit honestly says the end-to-end run 「未跑」. The skill says that run is pre-authorized and is what proves the one-click route.

There is a specific risk to check here (my guess from reading the vendor's code, not tested):
- The vendor's update helper keeps a backup called `previous`.
- If the relaunched app doesn't write `started` within a minute, the helper puts `previous` back.
- It stages in `.spotifast-update-<hex>` next to the bundle in `/Applications`.

So a duo swap that lands during a vendor update could be rolled back.

**Fix:** run both rounds one after the other, 0.12.0 → 0.13.0: first with the app not running, then with the app running and its updater mid-update on an older build. Record the results in 一键安装 and 已知问题.
