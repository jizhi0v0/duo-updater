# Review: Cindy onboarding (`7bccb0b..74364ea`)

**Verdict:** the global stable rule, the one-click pattern and the changelog recipe are correct, and the tests pass. Two findings are BLOCKING. Both are false "not feasible" conclusions written into the docs, and one of them led to the whole cn edition being left out.

**What I checked:**
- **Tests:** `swift test --package-path DuoUpdaterCore --filter 'CindyGitHubRuleTests|RecipeGoldenTests|GitHubAssetSelectionTests|RecipeHealthKeyTests'` gave `Test run with 27 tests in 4 suites passed`, rc=0.
- **Releases:** I fetched all 65 releases with `gh api`. `/releases/latest` returns `v0.1.104`. Every `-beta` tag has `prerelease: true`. `v1.0.0` has 0 assets and is the oldest release (created 07-25).
- **Fallback path:** I read the `settle()` fallback in `GitHubReleasesSource.swift:1321`. It filters the list to stable releases and skips releases with no matching asset, so `v1.0.0` can't be offered even though its version number is higher than 0.1.x.
- **Version and digest:** I mounted the 0.1.104 arm64 global dmg read-only. It reports `com.xd.cindy`, short version `0.1.104`, build `0.1.104`. The GitHub digests match what the audit wrote.

The rule's tag anchor, `-global` asset pattern and `.dmg` kind are right, the Team stays the same across versions, and the `PRs` skip works.

---

### 1. BLOCKING: cn edition left out because of a false premise; a supported route exists
The commit and audit say cn (`com.xd.cindycn`) can only be added through a second GitHub rule. That is in fact blocked: `recipeID = github:<slug>:<channel>` (`GitHubReleasesSource.swift:426`), and no existing rule pair shares a repo and channel. But the audit then marks VendorProbe ✗ on the grounds that "CDN 地址由应用运行时取、不写在包里". That is wrong:

- **The address is in the package.** `strings app.asar` in the 0.1.104 global dmg contains `https://hotfix.cindy.app/cindy` and `https://hotfix.cindy.com.cn/cindy`. In the vendor source, `ENDPOINT_MANIFEST_BASE_URL` is set at build time (`apps/desktop/src/shared/endpoints.ts`), and the app reads `<base>/endpoint.json`.
- **The cn endpoint file is public and points at itself.** `https://hotfix.cindy.com.cn/cindy/endpoint.json` returns 200 with `"cdnBaseUrl": "https://hotfix.cindy.com.cn/cindy"`.
- **The cn manifests are public and match GitHub byte for byte.**
  - `manifest-darwin-arm64.json` returns 200 with `app.version 0.1.104` and `installer.file app/darwin-arm64/cindy-0.1.104-arm64.dmg`. Its sha256 `8f0704e3…6331` equals the GitHub digest of `cindy-0.1.104-darwin-arm64-cn.dmg`.
  - The x64 manifest's `565f86c7…` equals the GitHub x64-cn digest.
  - A HEAD request on the cn dmg URL returns 200 (served from AliyunOSS).
  - The global manifest's `9e8ac572…eaeb` equals the GitHub arm64-global digest.
- **Vendor probes don't hit the collision.** Their `recipeID` is `vendor:<bundleID>:<channel>[:variant]` (`VendorProbeDiagnostics.swift:604`), and arm64/x64 splits are an existing pattern (`variant` + `VendorHostRequirement(architectures:)`, as in `com-raycast-macos.swift`).

**Fix:**
- Add two `VendorProbeRecipe`s for `com.xd.cindycn`, with `variant: "arm64"` and `variant: "x64"` plus a matching `hostRequirement`, reading `https://hotfix.cindy.com.cn/cindy/manifest-darwin-<arch>.json`.
  - The version pattern has to be anchored inside the `"app"` object, because `codex`, `claudeCode`, `pi` and `codexPackage` also have `"version"` keys. Something like `"app"\s*:\s*\{\s*"version"\s*:\s*"([0-9]+(?:\.[0-9]+)+)"`.
  - Use `.bodyPatternRelative(<app.installer.file>, base: https://hotfix.cindy.com.cn/cindy/)`, kind `.dmg`, and `checksumFormat: .sha256Hex` against `app.installer.sha256`.
- Add a `ChangelogRecipe` for `com.xd.cindycn` that reuses the GitHub releases source. Changelog `recipeID` is `changelog:<bundleID>:…` (`ChangelogRecipe.swift:335`), so this has no collision. It can be added today, with or without the probe.
- Correct the coverage matrix, 已知问题 and 建议下一步 in `docs/app-audits/com-xd-cindy.md`, and the README line.
- Verify on the real cn 0.1.103 package with `channel-verify` before landing.

### 2. BLOCKING: beta labelled Pattern D, but it's a device-local preference file (Pattern B)
The audit, the commit and `CHANNEL_COVERAGE_TODO.md` all say beta "cannot be told apart". The bundle really carries no beta marker; that part is correct. But the vendor's `apps/desktop/src/main/updateChannelStore.ts` stores the switch on disk at `userData/update-channel-settings.json`:
- The effective value is `enableBeta` when it's in `customizedKeys`, otherwise `orgDefaultEnableBeta`.
- Members of the xd org get beta turned on by default after login.
- `brandIdentity.ts` sets the userData directory to `CindyGlobal` for global and `Cindy` for cn.

The codebase already detects channels from files like this (`SuperconductorChannel.swift` reads `~/.superconductor/settings.json`; `MacMouseFixChannel.swift` reads a plist in Application Support). The skill's step 2c says a preference key found in source outranks bundle signals, and the audit itself cites `isBetaChannelEnabled()`.

Two other sources serve beta. The `-beta` GitHub releases (prerelease) are one. `manifest-darwin-<arch>-beta.json` is the other: right now it returns `0.1.108`, with sha256 `81a09b2d…`, equal to the GitHub `v0.1.108-beta` arm64-global asset.

Unverified: I have not seen the real on-disk shape that `createOverrideSettingsFile` writes. That needs a real install, or a read of `maker-host/override-settings-file`.

**Fix:**
- Reclassify beta as Pattern B (preference file) in the audit and in `CHANNEL_COVERAGE_TODO.md`, recording the path and the effective-value rule.
- Track a follow-up: a `CindyChannel` reader, plus a beta rule (`usePrereleases`, `^v(…)-beta$`, `channel: .beta`) or a vendor probe on the beta manifest.
- Remove the "beta 不可分辨" wording.

### 3. NOTE: account-level canary track not mentioned
`manifestService.ts` picks the update track in priority order canary > beta > release. Canary is a server-assigned, per-account flag (`canaryFlagStore`) that reads `manifest-<platform>-canary.json`. That file returns 200, and it is currently identical to the beta manifest. Canary has no GitHub tags.

**Fix:** add a canary row to the audit's Channel 详情 and to `CHANNEL_COVERAGE_TODO.md`. It's account-level and has no GitHub source, so record it as CDN-only and blocked/unknown.

### 4. NOTE: legacy `xdt-maker` identity not recorded
`packages/maker-shared/src/brandIdentity.ts` says the app's identity flipped on 2026-07-17. The old `xdt-maker` channel was frozen, and existing users stay on it until a future migration. Every public GitHub release (v0.1.17 and later) is after the flip, so this rule can't serve those copies. The audit should still say so, so a future auditor doesn't go looking.

**Fix:** add a line to 基本信息 / 已知问题 noting the legacy `xdt-maker` builds (bundle id not checked). They are frozen and not served by this repo.

### 5. NOTE: changelog order follows creation date, not version
The releases API lists `v0.1.85` (created 09-16) above `v0.1.86` (created 09-15, published 09-18). The `.gitHubReleases` decoder keeps the API's order (`StructuredChangelogDecoder.swift` ~700: "no re-sort needed"), so the notes list will show 0.1.85 above 0.1.86. It's cosmetic and doesn't affect detection.

**Fix:** none needed in the recipe. Optionally note it under the audit's Changelog section.

### 6. NOTE: end-to-end one-click not run
The README line and the audit both say this honestly. Before ticking the README checkbox as a full one-click ✓, run `duo install` from 0.1.103 global to 0.1.104, then check the Team, `codesign --verify --deep --strict` and `spctl`.

---

I edited nothing in the repo; `git status` is clean. Everything I downloaded is under `scr/review/{api,cdn,src}`, and the dmg I mounted is detached again.
