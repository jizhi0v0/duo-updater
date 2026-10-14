I found nothing blocking. The rule is right, every gate it depends on passes on the vendor's real bytes, and the suite is green. The one open item is the one-click end-to-end run, and the onboarding says honestly that it was not run. I have six notes, all fixes to the doc or test comments.

## What I checked
- **Vendor packages:** I downloaded all 6 macOS zips (0.10.0, 0.10.1 and 0.11.0, both arches). For each:
  - `shasum -a 256` equals the GitHub API `digest`.
  - The id is `io.github.tobi.disktree`, and the short version, build number and tag all agree.
  - Each is ad-hoc signed with no Team ID, and `codesign --verify --deep --strict` returns 0.
  - Each is a thin build for one arch, with an OS floor (`LSMinimumSystemVersion`) of 11.0.
  - Each bundle holds 4 files. The designated requirement is a bare cdhash that differs every time: 0.10.1 arm64 `4ed4e7ae…`, 0.11.0 arm64 `67134b8f…`, 0.11.0 x86_64 `826af9da…`.
- **Detection (channel-verify)**, including 0.10.0, which the executor didn't run:

  | Bundle | Result | Download URL names |
  |---|---|---|
  | 0.10.0 arm64 | `UPDATE → 0.11.0` | `aarch64` zip |
  | 0.10.0 x86_64 | `UPDATE → 0.11.0` | `aarch64` zip |
  | 0.11.0 arm64 | `up to date` | — |

  All three show the same changelog line: `source structured: 1 entries; newest 0.11.0: 23 items, headings []`. The v0.11.0 release body has exactly 23 "What's Changed" bullets and 14 "New Contributors" bullets, so the doc's changelog claim holds.
- **Gates on real bytes:** I wrote a throwaway SwiftPM test in my scratchpad (`@testable import DuoUpdaterCore`; nothing in the repo or /Applications touched). It runs the production `ArchiveExtractor.extractApp`, then `verifyPublishedDigest`, then `verifyInstallArtifact(trust: .publishedDigest)`:
  ```
  A  arm64 0.10.1 -> arm64 0.11.0:       PASS
  A0 arm64 0.10.0 -> arm64 0.11.0:       PASS
  B  x86 0.10.1 -> arm64 0.11.0 (row 3): PASS
  C  arm64 0.10.1 -> x86 0.11.0:         REFUSED architectureDowngrade(installed: "arm64", downloaded: "x86_64")
  D  wrong digest:                       REFUSED publishedDigestMismatch
  E  version pin 0.11.1:                 REFUSED infoPlistVersionMismatch
  ```
  This covers the identity, arch and OS-floor gates, not the swap itself or the settings switch.
- **Tests:** `make test` exits 0. Core: 5375 tests passed, with 1 known issue in `EventStoreSchemaDriftTests`, which is unrelated. `check_app_audits.py`, `check_ifchange.py`, `AppAuditCoverageTests`, `RecipeGoldenTests`, `DigestOnlyRecipeTests` and `GitHubAssetSelectionTests` all pass.

## Findings

1. **NOTE: the one-click end-to-end run is still owed.** The commit adds the one-click asset pattern before any end-to-end run. The plan said to raise that choice ("keep it wired, or `installAssetPattern: nil` until tested") rather than make it alone, and the commit just made it. I agree with keeping it wired: the digest-only setting is off by default, and every gate in my test refused rather than letting a bad case through. Precedent also allows a ticked index row with "一键未跑" (one-click not run), for example AppCleaner and Maccy.
   - **Fix:** run coverage-discovery Phase 5 for real: 0.10.1 into /Applications, then `duo install` with the setting off (expect a skip) and on (expect installed). Then replace the doc's "端到端: 未跑" (end-to-end: not run) line, as Phase 5 requires.

2. **NOTE: the "Intel Mac" unverified item can never happen.** The doc's 已知问题 (known issues) and 未验证 (unverified) lists, and plan row 2, describe the x86_64 route on an Intel Mac. DuoUpdater is built arm64-only (`App/project.yml:18-23`, `ARCHS: arm64`, deliberately), so it never runs on an Intel Mac.
   - **Fix:** drop that bullet. Say instead that the pattern admits x86_64 only so that Apple-silicon arch preference can choose between the two zips. Move the "x86_64 copy on Apple silicon is swapped to aarch64" case from unverified to "gates pass on real 0.10.1 x86_64 → 0.11.0 aarch64; swap itself not run".

3. **NOTE: the cdhash example compares different architectures.** The doc says the cdhash changes every release and cites 0.10.1 **arm64** `4ed4e7ae…` against 0.11.0 **x86_64** `826af9da…`. Two arches always differ, so that pair proves nothing. The claim itself is true.
   - **Fix:** cite 0.10.1 arm64 `4ed4e7ae…` against 0.11.0 arm64 `67134b8f…`.

4. **NOTE: a vendor rebuild can move "latest" back or swap the bytes, and the doc doesn't say so.** `release.yml` has a `workflow_dispatch` trigger to "(re)build" an existing tag. It uploads with `gh release upload --clobber` and then runs `gh release edit "$TAG" … --latest`. A rebuild of an old tag would therefore:
   - move `/releases/latest`, which this rule reads, back to the old version, so duo would show the app as current or behind;
   - replace the assets under the same version, with a new digest and cdhash;
   - if the signing secrets exist by then, switch an existing version from ad-hoc to Developer ID, which `teamIdentifierAppeared` refuses.

   **Fix:** add one line to 已知问题 and to the re-audit triggers. No code change is needed; every path fails safe.

5. **NOTE: an open PR that edits `release.yml` is missing from the re-audit triggers.** Open PR #84 changes how the macOS signing secrets reach the job. The plan's facts table said no open PR touches packaging or release, and the doc's 建议下一步 (next steps) lists only #79/#102/#32/#85.
   - **Fix:** add #84 to the triggers list.

6. **NOTE: small accuracy items.**
   - The recipe comment and doc say short version = build = tag for "0.10.1 and 0.11.0". 0.10.0 matches too (measured above, both arches), and the plan wanted it named. Add it.
   - `DigestOnlyRecipeTests` still says "Exactly one arm64-runnable dmg per release" and the test is named `eachPatternPicksTheOneDmgForThisMac`. disktree is a zip, so say "dmg or zip" in the comment.
   - The `"rc"` → `"-rc"` test change is fine: it still catches the only decoy, `Alacritty-v0.17.0-rc2.dmg`.
   - The doc's 增量 (delta updates) section answers delta, arch/OS and self-updater, but skips Phase 3⅞'s staged-rollout row (按设备灰度). Add "无（`/releases/latest` 人人同一结果）" (none: `/releases/latest` returns the same to everyone).
   - Optional: Lokii has a per-rule test (`LokiiGitHubRuleTests`: tag extraction, sidecar rejection); disktree only has the shared tables.

## Plan coverage checklist

| # | Item | Result | Agree? |
|---|---|---|---|
| 1 | Release build, arm64 | Covered as planned: GitHub rule, `.publishedDigestOnly`, `.zip`, the planned pattern. Detection verified; gates verified by my run; end-to-end not run, and the doc says so | Yes |
| 2 | Release build, Intel | Covered by the same rule, but the doc keeps "unverified on an Intel Mac" | No: that case can't happen (finding 2) |
| 3 | Intel zip on Apple silicon | Covered, listed as unverified. Detection picks the `aarch64` zip, and gates pass in my run (case B) | Yes; upgrade the wording |
| 4 | `make install` self-built copy | Covered differently: documented, not special-cased, unverified. Vendor `Makefile` confirms `~/Applications/disktree.app` plus a `~/.local/bin` symlink, and `xtask` signs it ad hoc (`--sign -`) | Yes |
| 5 | v0.9.x (no macOS build) | Covered: doc states there was no macOS package. Nothing was measured, because no macOS bundle exists | Yes |
| 6 | Beta / nightly / RC channels | Covered: single track, settled from `release.yml` | Yes, plus the rebuild caveat (finding 4) |
| 7 | Old copies without a feed | Not mentioned in the doc; doesn't apply (no feed anywhere) | Yes |
| 8 | Bundle id renames | Covered in 基本信息 (basic info); the vendor's plist comment confirms the id is kept stable on purpose | Yes |
| 9 | Resident helper | Covered: 4-file bundle, no helper | Yes |
| 10 | Homebrew / Mac App Store / AUR | Covered for cask, formula and Mac App Store. AUR isn't mentioned; it is Linux-only, so that's fine | Yes |
| — | Plan boundaries | Kept: no `.developerID`, no extra knobs, `verify/*.json` and the org-alacritty list untouched, no record links. The one-click-before-end-to-end question was not raised (finding 1) | Mostly |

The two items I did not verify: the swap and the settings switch (only the Phase 5 run proves those), and whether Full Disk Access survives an update of an app identified only by cdhash. The doc correctly leaves that last one unverified.

Downloads and unpacked bundles are in `scr/review/dl` and `scr/review/x`. The throwaway test package is in my session scratchpad (`…/scratchpad/gateprobe`). I changed nothing in the repo; `make test` only refreshed the ignored `.build` directory.
