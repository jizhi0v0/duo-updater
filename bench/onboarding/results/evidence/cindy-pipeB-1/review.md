# Review: Cindy onboarding (`7bccb0b..b2172f1`)

**Verdict: no BLOCKING findings.** The rules, the changelog recipes, the new `variant` field and the tests are correct. All the gaps below are in coverage and in the docs.

**What I ran** (all build output went to `scr/review/`, and the clone is still clean at `b2172f1`):
- `make test-scripts` with python 3.14 first on PATH → exit 0. All the `check_*` gates pass.
- `swift test --package-path DuoUpdaterCore` → 4570 tests passed, 1 issue that was already marked as known (`EventStoreSchemaDriftTests`).
- `swift test --package-path CLI` → 396 tests passed.
- Live `gh api …/releases --paginate`: 65 releases, latest is `v0.1.104`. Every `-beta` release is marked prerelease and no other release is. `v1.0.0` has no assets. `v0.1.52` has a single darwin asset (arm64 global). Every asset has a `digest`.
- The recipe's regexes, ported to Python, on live notices (0.1.97, 0.1.101, 0.1.103, 0.1.104 and 0.1.108, both hosts): exactly one match per file, and the headings and texts equal `contentByLocale.en.topics` exactly.
- `channel-verify` on two pre-GitHub CDN builds (see finding 1).

## Findings

**NOTE 1: copies installed from the vendor's CDN before the first GitHub release are not covered in the audit, and some are named `CindyGlobal.app`.**
- **Evidence:**
  - `notice/darwin-arm64/index.json` on both CDN hosts starts at `0.1.6`. The CDN also serves `app/darwin-arm64/cindy-0.1.6-arm64.dmg` through `cindy-0.1.16-arm64.dmg` (HTTP 200, last-modified 2026-07-22 to 07-27). None of these are GitHub releases; the first GitHub release is v0.1.17. The vendor's own `cindy.app/download` page links to `hotfix.cindy.app`.
  - I mounted 0.1.6 global read-only. It contains **`CindyGlobal.app`**, bundle `com.xd.cindy`, Team `SX9RG894L5`, notarized. 0.1.16 global and cn have the same ids and Teams.
  - Vendor commit `75baac1ee` says: 「存量 global 用户的升级迁移按 owner 决策不做处理」 — the vendor deliberately did not migrate existing global users to the new name. Its own updater swaps in place, so long-time global users can still have `/Applications/CindyGlobal.app` on 0.1.104 today.
  - Detection works: `channel-verify` on 0.1.6 (`CindyGlobal.app`) and on cn 0.1.16 both print `winning source GitHub … status UPDATE → 0.1.104` and `changelog pane recipe`. One-click should keep the old name, because `VendorInstaller` swaps over `result.app.path`. That last part comes from reading the code, not from a run.
- **What's wrong in the docs:**
  - The audit says 「两个版本都叫 `Cindy.app` … 不能同在 `/Applications`」 (both editions are called `Cindy.app` and cannot both be in `/Applications`). That is false for legacy global copies.
  - 「分发: GitHub Releases」 leaves out the CDN, which is the vendor's main download.
  - The e2e check `pgrep -fl "/Applications/Cindy.app/"` would miss a `CindyGlobal.app` copy.
- **Fix:**
  - Record the CDN as a distribution source and record the legacy `CindyGlobal.app` name.
  - Add the 0.1.6 `channel-verify` line to 如何复验.
  - Add a `CindyGlobal.app` round to the serial e2e plan, and change the `pgrep` to match on `com.xd.cindy` or both paths.

**NOTE 2: plan item 1.5 was never recorded.**
- **Evidence:** `com.xd.cindydev` / `CindyDev.app` (the internal dev build) and the `xdt-maker` predecessor (its id is unknown, so no `BundleIDMigration`) appear nowhere in the audit doc or in `CHANNEL_COVERAGE_TODO.md` (I grepped both). The plan said "Not covered; record."
- **Fix:** add a short 「未覆盖的身份」 paragraph to the audit.

**NOTE 3: the core change (`variant`) goes against plan boundaries B1/B4, but I think it was necessary.**
- **Evidence:**
  - Cindy is the first time two rules share one repo *and* one channel. Grouping the goldens by owner, repo and channel, `makecindy/cindy .stable` is the only pair that appears twice.
  - `RecipeHealthKeyTests.rulesSharingASlugRecordSeparateHealthEntries` depends on the registry, so it would fail without the field.
  - I checked everything that uses `recipeID`: `RecipeHealth.displayName`, `Verify.liveRecipeIDs`, the baseline prune, and the `--only` filter. None of them parse the last segment as the channel. The validator cache is keyed by endpoint, so the two editions sharing it is harmless. Recipes are never decoded from remote JSON (`RecipeCoding.swift` header), so older clients are not affected.
- **Fix:** none to the code. Raise it with the user as a judgement call: it is a Core API change that the plan did not authorise. The commit message does disclose it.

**NOTE 4: `make test` was not green as a whole, and `test-app` was not run.**
- **Evidence:** the commit says `make test` exits 2 because `/usr/bin/python3` is 3.9.6. It reports `test-scripts` and `test-swift` passing, but says nothing about `test-app` (`scripts/app-tests.sh`, xcodebuild). I didn't run `test-app` either. Nothing in `App/Sources` constructs a `GitHubReleaseRule` or reads `recipeID`, so the risk is low but not checked.
- **Fix:** run `make test` (with a 3.10+ python3) through to `test-app` before merging.

**NOTE 5: the GitHub "latest" release can briefly be a lower version than an existing stable release.**
- **Evidence:** in the release list, `v0.1.85` (created_at 2026-09-16) comes after `v0.1.86` (09-15). GitHub sorts `/releases/latest` by `created_at`, which is the date of the release's commit ([docs](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)). So during 09-16 to 09-20 a 0.1.83 copy was probably offered 0.1.85 rather than 0.1.86. That is my inference; I did not observe it.
- The CDN also hosts builds that were never GitHub releases (0.1.56, 0.1.57, 0.1.89, 0.1.99, each HTTP 200 as a dmg). I don't know whether any of them reached the stable manifest. The audit's claim that the CDN and GitHub serve the same bytes was measured on one day only.
- **Effect:** never a downgrade, at worst a short lag.
- **Fix:** add a line to 已知问题. No code change.

**NOTE 6: 如何复验 summarises the `channel-verify` output instead of pasting it.**
- **Evidence:** lines such as `→ status UPDATE → 0.1.104` are paraphrases. Only the two `changelog pane` lines are verbatim. Plan step 7 asked for the raw lines.
- **Fix:** paste the `winning source` / `latest` / `status` lines exactly as printed.

## Plan coverage checklist

| Item | Result | Agree? |
|---|---|---|
| 1.1 Global stable (detection, one-click, changelog, 读的是) | **Covered.** Rule, CDN-notice recipe and 读的是 = GA as planned. One-click is 需要验证; e2e not run. | Yes |
| 1.2 CN stable | **Covered.** Own rule; the asset patterns exclude the other edition's dmg (tested). | Yes |
| 1.3 Beta | **Out of scope, with a reason.** Entry in TODO §2b; the blind spot is documented. | Yes. The switch file has never been seen on a real machine, so a `ChannelBinding` now would go against the repo's rules. |
| 1.4 Canary | **Out of scope, recorded.** CDN-only, decided per account. | Yes |
| 1.5 `cindydev` / `xdt-maker` | **Missed.** Not recorded anywhere (NOTE 2). | The decision is right; the record is missing. |
| 1.6 Old versions | **Covered differently, and better than planned for GitHub-era builds:** 0.1.17 was verified for both editions. Both the plan and the result **missed** the pre-GitHub CDN builds and the `CindyGlobal.app` name (NOTE 1). | Partly |
| 1.7 Architectures | **Covered.** 0.1.52 walk-back is tested; arch pick is tested; the Rosetta behaviour is recorded; no OS-specific tracks. | Yes |
| 1.8 Helpers and self-updater collision | **Covered** as an 已知问题, read from source; e2e round 2 is still pending. I confirmed `agent-island` is started as a normal child process, not a detached one. | Yes |
| 1.9 Delta / rollout table | **Covered**, copied as-is. | Yes |
| B1 boundaries | **Covered differently:** the extra `variant` field (NOTE 3). | Yes, it was needed |
| B4 "don't change core" | **Deviated** (NOTE 3). The parser footer issue was recorded and not implemented, as asked. | Yes |
| B5 judgement calls (en vs zh, beta blind spot) | **Covered.** Both are stated in the audit. | Yes |

One thing is still to do: the serial one-click e2e for both editions is not run. Per B3, that is for you or the orchestrator.
