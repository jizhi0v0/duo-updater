# Review: OpenInTerminal onboarding (pipeB-1)

**Verdict: there is nothing to review.** The executor stopped before making any change, so every checklist item in the plan is missing. I spot-checked the plan's key facts; they hold, and with one caveat it can go ahead as written.

## Findings

### 1. BLOCKING — The onboarding is empty
**Evidence:**
- `git rev-parse HEAD` returns `57e6ce0d15d06a0cf2507796c4d057e212d04c4d`, which is the base commit. Branch `onboard-openinterminal` has no commits.
- `git status --porcelain --ignored` prints nothing: no untracked files and no work in the tree.
- `runs/…/exec.diff` is 0 bytes, `exec.head` = `57e6ce0…`, and `exec.rc` = 0. The run took about 195 s.
- The executor's last message says it stopped because `ditto -x -k` was denied three times. It hadn't started the Core change, the recipe file, the goldens, the audit doc or the commit. It asked the user to choose:
  1. allow `ditto` into `scr/pkg/*/x`, or
  2. run `codesign`/`plutil` read-only on the planner's extracted copies in `scr/dl/*/x`.
- Nothing in the code base mentions the app: `grep -rn 'jianing\|OpenInTerminal'` over `DuoUpdaterCore/Sources` and `docs/app-audits/README.md` finds nothing, and there's no `docs/app-audits/*jianing*`.

**Fix:** answer the executor's question, then run plan Steps 1–6. Option 2 is now low-risk, because I ran those read-only checks myself (finding 2).

### 2. NOTE — The evidence the executor was missing is consistent with the plan
These checks were read-only, on the planner's extracted copies, and nothing was launched:
- **Hashes:** the planner's zips match the current assets, so they're the re-uploaded builds, not the ad-hoc first upload.
  - v2.3.9 `OpenInTerminal.zip` = `14df8720…387765`
  - v1.2.8 `OpenInTerminal-Lite.zip` = `18984243…3250af`
  - v1.2.8 `OpenInEditor-Lite.zip` = `40db3a78…26106f`
- **Team IDs (`codesign -dv`):**

  | Bundle | Bundle id | Team |
  |---|---|---|
  | 2.3.8 | `wang.jianing.app.OpenInTerminal` | `Q33U8R4U57` |
  | 2.3.9 | `wang.jianing.app.OpenInTerminal` | `C8VX3ZLX5U` |
  | Lite 1.2.7 | `wang.jianing.app.OpenInTerminal-Lite` | `Q33U8R4U57` |
  | Lite 1.2.8 | `wang.jianing.app.OpenInTerminal-Lite` | `C8VX3ZLX5U` |
  | Editor-Lite 1.2.8 | `wang.jianing.app.OpenInEditor-Lite` | `C8VX3ZLX5U` |

  So the Team change that justifies detection-only is real.
- **Install gate:** `SignatureVerifier.swift:222-229` throws `teamIdentifierMismatch` or `noTeamIdentifier`. A one-click from 2.3.8 to 2.3.9 would download and then refuse to install.
- **Legacy ids:** the Info.plists of 2.0.5 and 1.0.2 say `wang.jianing.OpenInTerminal` and `wang.jianing.OpenInTerminal-Lite`, as the plan says.
- **Not verified:** the era-A Team. `codesign -dv` on the 2.0.5 bundle returned "No such process". Also not verified: the ad-hoc 25-hour window, which rests only on the vendor's release skill and can't be observed any more.
- **No updater:** the 2.3.9 and 1.2.8 Info.plists have no `SUFeedURL`, `Frameworks/` has no Sparkle, `CFBundleVersion` = `1`, and `LSMinimumSystemVersion` = 10.13.

**Fix:** the executor can use these results, as long as the audit doc marks them as taken from the planner's extractions.

### 3. NOTE — Plan Step 1's `recipeID` change can still rename a key later
Each rule's id depends on the whole registry. Today no two rules share a slug and a channel, so no key changes now; the plan is right about that. But the first time anyone adds a second rule on an existing slug and channel, the existing rule's key silently gains `:<bundleID>`. Its `verify/baseline.json` row becomes an orphan, `Baseline.prune` deletes it (via `Verify.liveRecipeIDs()`, `Verify.swift:577-588`), and that rule's `lastGoodVersion` history starts over.

This doesn't affect this onboarding, because all six OpenInTerminal rules get the suffix from the start. It also costs a scan of the whole registry on every call (there are 16 `.recipeID` call sites in Sources), which is minor.

**Fix:** keep the plan's design. Say this in the `recipeID` doc comment, and add the plan's uniqueness test, which turns a later collision into a visible change in review.

### 4. NOTE — Plan details that held up and need no change
- **Release list** (`scr/releases.json`, 55 releases): the newest `^v1\.` tags are at indices 1, 3, 5, 7, 9, 12, 15, 16, 18, so they are never more than 3 apart. `listPageSize: 10` has margin. The only prerelease is `0.9.0`.
- **The fallback the plan cites:** a stable rule with `usePrereleases: true` walks the raw list with no `stableOnly`. The `stableOnly` fallback applies only to `!usePrereleases` rules (`GitHubReleasesSource.swift:1302-1317`). The plan's argument about the one 2019 prerelease and the `$` anchor is right, and should go into the rule comment as it says.
- **History:** it is built before the asset filter (`:1330`), so the `2.`/`1.` anchors really are what keeps each train's history separate.
- **The failing test:** `rulesSharingASlugRecordSeparateHealthEntries` (`RecipeHealthKeyTests.swift:183`) expects one health row per rule. It would fail with six rules sharing one id, so Step 1 has to land first.
- **Asset names:** they changed from `*.app.zip` to `*.zip` at v2.3.7/v1.2.6. The plan's future one-click patterns (`^OpenInTerminal\.zip$`) only need to match current releases, so that's fine. Recording the change in 历史与实测 would help.

## Plan coverage checklist

Nothing is implemented, so every item is **missed**. The last column is whether I'd keep the plan's decision.

| Item | Result | Agree with the plan? |
|---|---|---|
| 1.1 main `wang.jianing.app.OpenInTerminal`: detection from `/releases/latest` with `^v(2\.…)$`, detection-only, changelog from the release body | Missed | **Yes.** The Team change (finding 2) makes one-click refuse every outdated era-B copy. The enable trigger is sound. |
| 1.2 Lite `wang.jianing.app.OpenInTerminal-Lite`: list read, page 10, no newest-first probe, `^v(1\.…)$` | Missed | **Yes.** The page-size measurement checks out (finding 4). |
| 1.3 Editor-Lite `wang.jianing.app.OpenInEditor-Lite`: same as 1.2 | Missed | **Yes.** The id and Team are confirmed for 1.2.8. |
| 1.4 legacy main `wang.jianing.OpenInTerminal`: detection-only for good, because the install gate requires the same signed bundle id | Missed | **Yes.** The id is confirmed; the era-A Team isn't, but it doesn't matter because the id differs anyway. |
| 1.5 legacy Lite `wang.jianing.OpenInTerminal-Lite`: detection-only | Missed | **Yes.** The id is confirmed from 1.0.2. |
| 1.6 legacy Editor-Lite `wang.jianing.OpenInEditor-Lite`: detection-only | Missed | **Yes.** I didn't check this bundle myself; it should be the same shape as 1.5. |
| 1.7 channels: stable only, no `ChannelBinding`, confirm with `channel-verify --expect stable` | Missed (Step 5 never ran) | **Yes.** The release list has one prerelease, from 2019. |
| 1.8 helper and Finder extension ride along with 1.1, not separate rows | Out of scope by design, and correctly so | **Yes.** The real-machine check after a swap belongs in 已知问题 / 建议下一步. |
| 1.9 Phase 3⅞: no delta, no rollout, universal build, no competing updater | Missed (no audit doc) | **Yes.** No feed or Sparkle, confirmed. |
| Step 1: Core `recipeID` collision suffix plus uniqueness and baseline-orphan tests | Missed | **Yes, needed.** Add the doc note from finding 3. |
| Steps 2/5: before and after runs of `feed-discover` / `channel-verify` | Missed | **Yes.** Extraction needs approval first. |
| Step 3: family file and `AppRecipeIndex` entry | Missed | **Yes.** |
| Step 4: goldens and the Core and CLI test suites | Missed | **Yes.** `swift test` rather than `make test` fits the boundaries. |
| Step 6: audit doc with the template headings verbatim, including 「观测版本」 (`SKILL.md:695`), and the README line | Missed | **Yes.** |
| Out of scope: `ChangelogRecipe`, `VendorProbe`, MAS, Homebrew entries, alias for the old ids, a Team-transition allowlist | Correctly not done | **Yes.** Each one is justified in the plan. |

The next step is to give the executor permission for extraction (or tell it to use the planner's copies), then rerun Steps 1–6 and review the actual diff.
