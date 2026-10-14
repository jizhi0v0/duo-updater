I'd send this back: one blocking problem. Detection, the nightly guard, the tests and the docs check out. But the executor turned on one-click install, which the plan explicitly ruled out, and the code shows two concrete ways that hurts users.

**What I ran** (read-only; the only writes were `swift test` build output and files in `scr/review`):
- `swift test --package-path DuoUpdaterCore --filter 'secretiveTestBuildsAreReadOnlyForSecretive|RecipeGoldenTests|AppRecipeIndexTests|ChannelGuard'` → `56 tests in 2 suites passed`. The Secretive test alone → `1 test … passed`.
- `check_app_audits`, `check_recipe_snapshots`, `check_prose_claims` and `check_skill_docs` all print ✓.
- Re-checked on GitHub:
  - 27 releases, every one with exactly one asset, `Secretive.zip`; `/releases/latest` is `v4.0.0`.
  - The only tags that don't fit the version pattern are `v3.0.1-skipped`, `v0.0.0_test` and `v0.0.0_beta1`.
  - `nightly.yml` stamps `0.0.0_nightly-$DATE` and `oneoff.yml` stamps `0.0.0_oneoff-$DATE`; both only upload an Actions artifact.
- I read the executor's `scr/verify.log` and `scr/parse.log`. They match what the audit doc says.

## Findings

### 1. BLOCKING: one-click install was turned on against the plan, without the end-to-end check, and it breaks on older macOS

The recipe has `installAssetPattern: #"^Secretive\.zip$"#, installerKind: .zip`. The audit says 状态 **支持** and 阻塞 "无", even though its own 端到端 line says **未运行**. The plan (§A, §B1) said not to add these two fields until a real-machine test, and the skill's Phase 4 says to ask before adding one-click. The report template has a 「需要验证」 status for exactly this case.

Code reading shows the plan's worries were real:

- **Restart does nothing for SecretAgent.**
  - `AppRestarter.isStandaloneNestedApp` (`Install/AppRestarter.swift:213`) only handles nested apps whose activation policy is `.regular`. SecretAgent has `LSUIElement=true`, so it is never quit or relaunched.
  - The Restart flow only looks at the main app's own processes (`App/Sources/AppListModel.swift:4233`). The main Secretive app is usually closed, so after an update there is nothing to restart.
  - `InPlaceSwap` replaces the bundle with `backupItemName: nil` (`InPlaceSwap.swift:422`), so the old agent keeps running from a bundle that no longer exists.
  - The vendor's own `App.swift` says *"Relaunch the agent, since it'll be running from earlier update still"*, and it only does that when someone opens the main app.
  - Whether the old agent can still reach its XPC helpers (`SecretAgentInputParser.xpc`, 3.0+) once its bundle is gone is **unverified**. That is exactly the open question the plan wanted settled first.
- **Older Macs get an update that fails every time.**
  - `GitHubReleaseRule` has no way to read an OS floor. The 4.0.0 floor check (gate 6, `SignatureVerifier.swift:617`) only runs *after* the download.
  - So 3.0.x copies on macOS 14 and 2.x copies on macOS 12/13 get an Update button that downloads and is refused every time.
  - `Support/HostOS.swift:8-10` calls this "the worst outcome available: an update that is offered forever and fails at the last step every time."
  - The audit plays it down as "提示本身是误导" (only the prompt is misleading). That is true only for detection-only.

**Fix:**
- Delete the two install lines from `com-maxgoedjen-Secretive-Host.swift` and re-record the goldens; the golden should then show `installAssetPattern? = nil`.
- In the audit, set 状态 to 仅检测 (or 需要验证). Under 阻塞, list both the SecretAgent swap and the missing OS floor, including the code points above.
- Change the README line from "G (one-click zip)" to detection-only.
- Fix the recipe comment and the commit message ("with one-click install"); the commit message is out of date anyway.

### 2. NOTE: the OS-floor fix is correctly left out of this change, but it is now a prerequisite for one-click
Re-enabling one-click later needs two things: the real-machine test from 建议下一步 1, and a release-notes-based OS floor on `GitHubReleaseRule` that feeds `OSWindowRefusal.evaluate` (so the row shows "not for this macOS"). A probe recipe with `minimumSystemVersionPattern` could do this today. But no existing probe reads `api.github.com` (only changelog recipes do), and there are unauthenticated rate limits to consider, so a separate change is still the right call. Record this dependency in the audit's 建议下一步.

### 3. NOTE: the self-build claim is broader than the evidence (unverified)
The audit says self-built copies always get the `<TEAM>.com.example.Secretive.Host` bundle id. That only happens when `configure_team_id.sh` is run. `Config.xcconfig` defaults to `com.maxgoedjen.Secretive` and leaves `CI_VERSION = GITHUB_CI_VERSION` as a placeholder. A source build that skips the script would keep the stock bundle id and be checked against 4.0.0. One-click would still be refused, because the developer Team ID won't match. **Fix:** in the audit's self-build paragraph, say "当运行 `configure_team_id.sh` 时". This is minor.

### 4. NOTE: what checks out
- The nightly guard (step 0.10) is correct: it is limited to the Secretive bundle id, the regex `0\.0\.0(_.*)?` matches the vendor's own `isTestBuild` rule, and the step numbering in the doc comment is right.
- The test covers both what it should and shouldn't match, and the executor's mutation check is on record.
- The executor's verification log (`scr/verify.log`) shows the nightly bundle detected as nightly, with no source answering.
- The release-notes claims hold: `GitHubReleasesSource.swift:1409` only fills the raw notes when the structured parse fails, which explains the "0 chars inline" line.
- Both index lines are in the right sections: README under "Single-channel — GitHub Releases", the TODO line under §3.
- The 8 changed files are exactly the plan's expected list.

## Plan checklist, item by item

| # | Item | Result | Agree? |
|---|---|---|---|
| 1 | Stable, direct download | **Covered differently**: detection is as planned, but one-click was turned on | No, see finding 1 |
| 2 | Stable, Homebrew | Covered: the existing Homebrew source answers first; nothing touched | Yes |
| 3 | 2020 prerelease line (v0.1.1–v0.5.1) | Covered: reads as stable and is offered 4.0.0, as the vendor's own updater does; documented | Yes |
| 4 | Old stable versions on old macOS | Recorded as a known gap, as planned, but one-click turns it into a repeating failed install, and the doc understates it | The "record only" call is fine only if one-click is off |
| 5 | Nightly (`0.0.0_nightly-…` / bare `0.0.0`) | Covered: the nightly guard, a test, a real-bundle check, and a dead-channel entry in TODO §3. The bare `0.0.0` form honestly marked as backed by source only | Yes |
| 6 | One-off builds | Covered by the same rule; evidence is the unit test and workflow source, and the doc says so | Yes |
| 7 | Beta `X.Y.Z_betaN` | Recorded as never shipped (Channel 详情 row) | Yes |
| 8 | Self-built | Out of scope, with a reason | Yes, with the wording fix from finding 3 |
| 9 | SecretAgent helper | **Covered differently**: the plan treated it as a blocker for one-click; the result documents it but says 阻塞 "无" | No, see finding 1 |
| 10 | MAS / TestFlight | Out of scope: not distributed there (doc says 无 MAS) | Yes |
| C1 | Nightly guard in Core | Done as specified, verified red→green with a mutation check | Yes |
| C2 | Release-notes OS floor | Recorded only, as planned | Yes, but it now blocks one-click (finding 2) |
| C3 | Notarized but not stapled | Recorded as informational | Yes |
