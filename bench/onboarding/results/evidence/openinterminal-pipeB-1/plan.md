# Onboarding plan: OpenInTerminal (Ji4n1ng/OpenInTerminal)

Planner investigation date: 2026-10-14. Packages were downloaded to
`scr/dl/<tag>_<asset>/a.zip` and extracted with `ditto -x -k` into `.../x/`.
They were inspected read-only and nothing was launched. Vendor source was
cloned to `scr/src/oit` (master `537ac2a`, 2026-07-14).

## 0. Summary of the landscape (evidence)

- **One repo, three apps, two release trains, one GitHub Releases list.**
  The vendor's own release skill (`.claude/skills/release/SKILL.md` on `master`)
  documents this:
  - OpenInTerminal (main) → release `OpenInTerminal vX.Y.Z`, tag `vX.Y.Z` (2.x line), asset `OpenInTerminal.zip`
  - OpenInTerminal-Lite + OpenInEditor-Lite → **one shared** release `OpenInTerminal-Lite vA.B.C`,
    tag `vA.B.C` (1.x line), assets `OpenInTerminal-Lite.zip` and `OpenInEditor-Lite.zip`
  - The two trains are interleaved in the list (55 releases; newest pair: `v2.3.9` and `v1.2.8`,
    both published 2026-07-13 ~12:08Z).
  - **The "Latest" marker is set by hand.** The vendor skill says: "GitHub auto-marks the most recently
    published release as Latest. By convention the main app is Latest, so fix it:
    `gh release edit vX.Y.Z --latest`." The Lite release is published second, so by default it
    would become Latest. Observed on 2026-10-14: `GET /repos/Ji4n1ng/OpenInTerminal/releases/latest` → `v2.3.9`.
- **No self-updater and no feed.** No `SUFeedURL` in any of the 23 inspected bundles (0.1.0 … 2.3.9).
  There is no Sparkle framework and no electron config. Vendor Swift sources contain no `URLSession` or update
  check; the only URLs are About-panel links (`AboutPreferencesViewController.swift`). The binary
  `strings` show no update endpoint.
- **Homebrew:** casks `openinterminal` (2.3.9), `openinterminal-lite` (1.2.8) and `openineditor-lite` (1.2.8)
  exist, with `auto_updates` unset. URLs are the GitHub assets. There are no `@beta`/`@nightly` casks.
- **Mac App Store:** none. `itunes.apple.com/lookup?bundleId=` returns 0 results for all six ids below.
- **Channels:** only one stable track. The only prerelease ever is `0.9.0` (2019). The branches are `master`,
  `develop` (stale, last commit 2019-04-30) and `fix/sandbox-command-injection`. There are no CI release workflows (the only
  workflow is "Copilot code review").
- **Version scheme:** tag `vX.Y.Z` == `CFBundleShortVersionString`. `CFBundleVersion` is always `1`.
  Every inspected bundle confirms this. Tags before 2021 have no `v` (`2.2.3`, `1.1.5`, …), but none of
  them is in the newest 20 releases.
- **Signing history. Three signing eras, and a Team ID change in 2026:**

  | Era | Main versions | Lite versions | Bundle ids | Signature | Team | Gatekeeper |
  |---|---|---|---|---|---|---|
  | A (2019) | 0.1.0 – 2.0.5 | 0.3.0 – 1.0.2 | `wang.jianing.OpenInTerminal`, `wang.jianing.OpenInTerminal-Lite`, `wang.jianing.OpenInEditor-Lite` | "Mac Developer" / "Apple Development" cert, no hardened runtime | C8VX3ZLX5U | `spctl` **rejected**, not notarized, x86_64 only |
  | B (2020-01 → 2025-01) | 2.1.1 – 2.3.8 | 1.0.3 – 1.2.7 | `wang.jianing.app.*` | Developer ID, runtime | **Q33U8R4U57** | Notarized, stapled |
  | C (2026-07 →) | 2.3.9 | 1.2.8 | `wang.jianing.app.*` | Developer ID, runtime | **C8VX3ZLX5U** | Notarized, stapled, universal (x86_64 arm64) |

  Both Developer IDs read "Jianing Wang". `codesign -dv` TeamIdentifier per package was checked for 2.0.1,
  2.0.5, 2.1.1, 2.2.0, 2.2.3, 2.3.0, 2.3.6, 2.3.8, 2.3.9 and for Lite/Editor 0.4.x, 1.0.0, 1.0.2, 1.0.3, 1.1.0, 1.1.4, 1.1.5, 1.2.5, 1.2.7, 1.2.8.
  - **Ad-hoc window:** the vendor skill records that v2.3.9/v1.2.8 "first shipped ad-hoc" and were
    re-uploaded with `--clobber`. Release `published_at` was 2026-07-13T12:08Z, but the current assets
    have `created_at` 2026-07-14T13:41Z (main) and 13:47Z (Lite). Anyone who downloaded in that ~25 h window has an
    **ad-hoc (no Team ID)** 2.3.9 / 1.2.8 with the same bundle id and version.
  - Current asset sha256 (API `digest` == local `shasum -a 256`): `OpenInTerminal.zip` `14df8720…7765`,
    `OpenInTerminal-Lite.zip` `18984243…50af`, `OpenInEditor-Lite.zip` `40db3a78…106f`.
- **Bundle id renames:** main `wang.jianing.OpenInTerminal` → `wang.jianing.app.OpenInTerminal` at **2.1.1**
  (vendor commit `0586e2f`, 2020-01-08; 2.0.5 is the last old id). Lite pair `wang.jianing.OpenIn{Terminal,Editor}-Lite`
  → `wang.jianing.app.OpenIn{Terminal,Editor}-Lite` at **1.0.3** (`a315e6a`, 2019-12-31; 1.0.2 is the last old id).
  Both renames coincide with the switch to era B.
- **Bundle layout (2.3.9):** zip root holds exactly `OpenInTerminal.app`. Inside it are
  `Contents/Library/LoginItems/OpenInTerminalHelper.app` (`wang.jianing.app.OpenInTerminalHelper`,
  `LSBackgroundOnly`, registered with `SMLoginItemSetEnabled`) and `Contents/PlugIns/OpenInTerminalFinderExtension.appex`
  (`wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension`, `com.apple.FinderSync`). All three apps
  are `LSUIElement` menu-bar/agent apps. `LSMinimumSystemVersion` is 10.13 (era C), 10.12 (era B) and 10.9–10.11 (era A).

### Engine facts that shape the plan (read in this clone)

1. `GitHubReleaseRule.recipeID` = `"github:\(slug):\(channel.rawValue)"`
   (`DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift:407`). Every rule below is
   `.stable` on the same slug, so **all of them would share one id**. That id keys:
   - `RecipeHealth` (`recordSuccess`/`recordMiss`): one rule's success would mask another's miss;
   - `verify/baseline.json` (`CLI/Sources/DuoKit/Baseline.swift`, `entries[finding.recipeID]`): the rules
     would overwrite each other's `lastGoodVersion` every sweep (2.3.9 ↔ 1.2.8 reads as "went backwards");
   - `RecipeHealthKeyTests.rulesSharingASlugRecordSeparateHealthEntries`, which is derived from the registry
     and **will fail** as soon as two of these rules exist (it expects one health row per rule).
   No existing registry has two rules with the same slug **and** channel (checked by a script over
   `Recipes/*.swift`), so this is a new shape, and it needs the Core change in Step 1.
2. A stable rule (`usePrereleases: false`) reads `/releases/latest`. It only falls back to the release
   list when `installAssetPattern` is set and the latest release lacks the asset (`settle(...)`). A
   **detection-only** stable rule whose tag does not match is a plain miss (`.unknown` plus a health miss), with no fallback.
3. `releaseHistory` is built from **every** fetched release whose tag matches `versionPattern`, *before*
   the asset filter. So the `versionPattern` must separate the trains by itself, or the history would mix them.
4. `SignatureVerifier.verifyInstallArtifact` gate 3 requires installed Team == downloaded Team, and gate 4
   requires the signed bundle id to match. There is no team-transition allowlist, and nothing pre-checks the installed Team
   before offering one-click (`InstalledApp` carries no Team ID). A mismatch surfaces as a plain install error
   after the download.
5. `SourceStack.make` order is MAS → Xcode → Homebrew → Sparkle → GitHub → … `HomebrewCaskSource` only
   answers for copies brew installed and keeps current. So a brew copy is answered by brew, and every other copy needs a GitHub rule.
6. `AppScanner` enumerates top-level bundles only (`contentsOfDirectory`). The embedded helper and appex never
   become rows.

---

## 1. Coverage checklist

Legend: **D** = detection route, **1C** = one-click route, **CL** = changelog route.

### 1.1 `wang.jianing.app.OpenInTerminal` — OpenInTerminal (main), era B + C, 2.1.1 → 2.3.9
- Signing: era B Developer ID Q33U8R4U57 for ≤2.3.8, era C Developer ID C8VX3ZLX5U for 2.3.9. There is also an ad-hoc 2.3.9 cohort (§0).
- Resident helper: `OpenInTerminalHelper.app` login item and the FinderSync extension, both embedded (see 1.8).
- **D:** new `GitHubReleaseRule` reading `/releases/latest` (the vendor convention keeps main as Latest; observed `v2.3.9`),
  `versionPattern: ^v(2\.[0-9]+\.[0-9]+)$`. The `2.` anchor is what keeps a Lite tag (`v1.x`) from ever reading as
  main if the Latest marker slips. In that case the row goes `.unknown` with a health miss, never a wrong version.
  Brew-installed copies are answered first by `HomebrewCaskSource` (cask `openinterminal`).
- **1C:** **none for now; detection-only.** Reasons:
  (a) every outdated copy today is era B (Team Q33U8R4U57), and gate 3 refuses the C8VX3ZLX5U 2.3.9 build for it.
  The user would download 25 MB and get "Team Identifier mismatch … Refusing to install";
  (b) the ad-hoc 2.3.9 cohort has no Team ID, so gate 3 fails with `noTeamIdentifier` on the next release;
  (c) the only copies that *could* one-click are C8VX3ZLX5U 2.3.9, which are already current. No older
  C8VX3ZLX5U Developer-ID build exists, so a red→green end-to-end install cannot be run today.
  Enable trigger: after the vendor ships the next main release signed by C8VX3ZLX5U, verify 2.3.9 → next end-to-end,
  then add `installAssetPattern: #"^OpenInTerminal\.zip$"#, installerKind: .zip`. The asset is a universal zip with
  `OpenInTerminal.app` at its root, which the arch selection treats as arch-neutral.
- **CL:** GitHub release body, carried by `GitHubReleasesSource` (`GitHubMarkdownParser`). Bodies are
  `Changes:` + `- ` bullet lists. No `ChangelogRecipe`. History stays main-only because of the `^v(2\.…)$` anchor.
- Evidence: §0. `dl/v2.3.9_OpenInTerminal.zip` and `dl/v2.3.8_OpenInTerminal.zip` (codesign/spctl/stapler output above).

### 1.2 `wang.jianing.app.OpenInTerminal-Lite` — OpenInTerminal-Lite, era B + C, 1.0.3 → 1.2.8
- Signing: as in 1.1 (Q33U8R4U57 for ≤1.2.7, C8VX3ZLX5U for 1.2.8, plus the ad-hoc 1.2.8 cohort). No helper, no extension.
- **D:** new `GitHubReleaseRule` that **must read the list**, because `/releases/latest` is the main release by convention:
  `usePrereleases: true, listPageSize: 10, probesNewestFirst: false,
  versionPattern: ^v(1\.[0-9]+\.[0-9]+)$`. This is the Bitwarden shape (`Recipes/com-bitwarden-desktop.swift`).
  Measured on 2026-10-14 over the newest 20 releases: the first `v1.x` is at index 1, and consecutive `v1.x` releases are at most
  3 apart, so 10 leaves margin. `probesNewestFirst: false` because the newest row is usually the main release.
  `usePrereleases: true` drops GitHub's stable-only filter. That is acceptable because the vendor has flagged one prerelease
  ever (2019, outside the page), and `$` rejects any suffixed tag. Write that argument into the rule comment.
  Brew copies are answered by cask `openinterminal-lite`.
- **1C:** none for now, for the same reasons and with the same enable trigger as 1.1 (asset `^OpenInTerminal-Lite\.zip$`, `.zip`).
- **CL:** GitHub release body of the shared Lite release. The one body covers both Lite apps (vendor practice),
  so record that in the audit and add no recipe.

### 1.3 `wang.jianing.app.OpenInEditor-Lite` — OpenInEditor-Lite, era B + C, 1.0.3 → 1.2.8
- Same as 1.2 in every respect (same release, same tag, same rule shape), with asset `OpenInEditor-Lite.zip` and cask `openineditor-lite`.
  The Editor-Lite edition first appeared at 0.4.4 (2019-05-28) under the old id.

### 1.4 `wang.jianing.OpenInTerminal` — pre-rename main, era A, 0.1.0 → 2.0.5
- Signing: development cert ("Mac Developer"/"Apple Development"), Team C8VX3ZLX5U, **not notarized**,
  `spctl` rejected, x86_64 only. The 0.1.x zips shipped per-terminal folders (`Terminal/`, `iTerm/`, …),
  and every copy inside still has this id. Helper id in that era was `wang.jianing.OpenInTerminalHelper` (from the
  `develop` pbxproj).
- **D:** detection-only `GitHubReleaseRule` with this bundle id, configured exactly like 1.1 (`/releases/latest`,
  `^v(2\.[0-9]+\.[0-9]+)$`). Installed 0.x–2.0.5 compares below 2.3.9, so the row offers the release page.
- **1C:** **never through this id.** The successor build has a different signed bundle id, so gate 4 refuses it.
  (The Team happens to equal today's C8VX3ZLX5U, but that does not matter.) The user installs the new
  `OpenInTerminal.app` by hand. It has the same file name, so it replaces the old bundle in place on disk.
- **CL:** same as 1.1 (the main release body).
- Evidence: `dl/2.0.5_…`, `dl/2.0.1_…`, `dl/0.10.3_…`, `dl/0.2.0_…`, `dl/0.1.0_…`, `dl/0.1.1_…`.

### 1.5 `wang.jianing.OpenInTerminal-Lite` — pre-rename Lite, era A, 0.3.0 → 1.0.2
- Signing as in 1.4. Only 0.3.0–0.4.1 shipped as `OpenInTerminal-Lite.zip` (with an `icons/` folder beside the app).
- **D:** detection-only rule configured like 1.2 (list, `^v(1\.[0-9]+\.[0-9]+)$`). **1C:** never (gate 4). **CL:** the Lite release body.
- Evidence: `dl/1.0.2_OpenInTerminal-Lite…`, `dl/0.4.5_…`, `dl/0.4.3_…`, `dl/0.4.1_…`.

### 1.6 `wang.jianing.OpenInEditor-Lite` — pre-rename Editor-Lite, era A, 0.4.4 → 1.0.2
- As in 1.5. Evidence: `dl/1.0.2_OpenInEditor-Lite…`, `dl/1.0.0_OpenInEditor-Lite…`, `dl/0.4.4_OpenInEditor-Lite…`.

### 1.7 Channels / tracks
- **stable only.** There is no beta, nightly, preview or insider build, no `@channel` cask, no channel preference in source, and no
  CI builds. It is not Pattern B/C/D, there is nothing to bind, and no `ChannelBinding` is needed. `ReleaseChannel.detect()` on all three
  current bundles should give `stable`: names `OpenInTerminal` / `…-Lite` carry no channel word, and versions are bare.
  Step 5 confirms this with `--expect stable`.

### 1.8 Resident helper / extension (not separate rows)
- `OpenInTerminalHelper.app` (login item, `SMLoginItemSetEnabled`) and `OpenInTerminalFinderExtension.appex`
  (FinderSync) live inside the main bundle. They are signed by the same Team as the main app in each package, and versioned with the main app
  (helper 2.3.9 inside 2.3.9). AppScanner never lists them. **D/1C/CL:** n/a, they ride with 1.1.
- Real-machine item for when one-click is enabled: after an in-place swap, check that the Finder extension is still
  enabled (`pluginkit -m -i wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension`) and that the
  login item still resolves. `VendorInstaller` never quits or relaunches the app, so the old process
  keeps running until the user restarts it.

### 1.9 Phase 3⅞ answers (for the audit doc)
| | Client capability | What the server actually sends | Can we consume it? |
|---|---|---|---|
| Delta / binary patch | None (no updater, no Sparkle) | None (assets are whole zips only) | — |
| Per-device staged rollout | None | None (public GitHub assets) | — |
| Per-arch / per-OS tracks | One universal build (era C); floor `LSMinimumSystemVersion` 10.13 | No bounds anywhere (no feed) | No `hostRequirement` needed |
| Does a self-updater compete with us? | None | — | — |

What the rules read: **the GA build anyone can download by hand** (public release assets; the Homebrew casks point
at the same URLs). This is not "newest on track, ahead of allocation".

---

## 2. Steps for the executor

Work in the fresh clone on a new branch (e.g. `onboard-openinterminal`). Don't push and don't open PRs.

### Step 1 — Core prerequisite: give same-slug, same-channel GitHub rules distinct `recipeID`s
File: `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift`, `var recipeID` (~line 407).
- Change it so that the **existing ids stay byte-identical**, and a bundle-id suffix is added **only** when another rule in
  `GitHubReleaseRegistry.rules` has the same `slug` and `channel`:
  ```swift
  var recipeID: String {
      let base = "github:\(slug):\(channel.rawValue)"
      let collides = GitHubReleaseRegistry.rules.contains {
          $0.slug == slug && $0.channel == channel && $0.bundleID != bundleID
      }
      return collides ? "\(base):\(bundleID)" : base
  }
  ```
  (If the reflection-based `channelAnchorFields` or any other code path turns out to evaluate `recipeID` while
  `GitHubReleaseRegistry.rules` is being initialised, stop and report it instead of working around it.)
  Update the doc comment on `recipeID` to say why the suffix exists: it keeps the baseline and health rows apart for one repo
  that ships several apps on one channel, and it leaves every existing key unchanged so no `verify/baseline.json` row is orphaned.
- Do **not** add a new field or initializer parameter to `GitHubReleaseRule`.
- Tests:
  - Add a test in `RecipeHealthKeyTests.swift` (or next to it) asserting `Set(GitHubReleaseRegistry.rules.map(\.recipeID)).count == GitHubReleaseRegistry.rules.count`.
  - Check that no existing baseline key is orphaned. Every `github:` key in `verify/baseline.json` must still be produced:
    ```bash
    python3 -I - <<'EOF'
    import json; b=json.load(open("verify/baseline.json"))
    keys=sorted(k for k in b["entries"] if k.startswith("github:"))
    print(len(keys))   # 101 on 2026-10-14 (top level is {entries, schemaVersion, updatedAt})
    EOF
    ```
    After the change, compare that set with the
    `github:` subset of `liveRecipeIDs()`, e.g. through a small test in `CLI/Tests/DuoKitTests`
    that asserts every `github:` key in `verify/baseline.json` is in `Verify.liveRecipeIDs()`, if one doesn't already exist.
    If writing such a test is awkward, a one-off check via `swift test` printing is enough. Report the result either way.
- Commit separately: `GitHub rules: distinct recipeID when one repo ships several apps on one channel`.

### Step 2 — Red: confirm nothing resolves these apps today
Before adding any rule, from the clone root:
```bash
mkdir -p "$SCR/oit" && cd "$SCR/oit"   # SCR = a scratch dir outside the clone
B=https://github.com/Ji4n1ng/OpenInTerminal/releases/download
for spec in v2.3.9/OpenInTerminal.zip v2.3.8/OpenInTerminal.zip v1.2.8/OpenInTerminal-Lite.zip v1.2.7/OpenInTerminal-Lite.zip \
            v1.2.8/OpenInEditor-Lite.zip v1.2.7/OpenInEditor-Lite.zip 2.0.5/OpenInTerminal.app.zip \
            1.0.2/OpenInTerminal-Lite.app.zip 1.0.2/OpenInEditor-Lite.app.zip; do
  d="$(echo $spec | tr '/' '_')"; mkdir -p "$d"; curl -sSL --max-time 120 -o "$d/a.zip" "$B/$spec"
  mkdir -p "$d/x" && ditto -x -k "$d/a.zip" "$d/x"
done
shasum -a 256 v2.3.9_OpenInTerminal.zip/a.zip v1.2.8_*/a.zip   # expect 14df8720…, 18984243…, 40db3a78…
```
Then, for each extracted `.app` (the 2.0.5 zip extracts `OpenInTerminal.app` directly):
```bash
swift run --package-path application-test feed-discover <dir>/a.zip        # expect: noKnownUpdater
swift run --package-path application-test channel-verify <dir>/x/<App>.app --expect stable
```
Expected red: no winning source or unknown for all of them. Save the raw output for the audit's 「如何复验」 section.

### Step 3 — Add the family file
New file `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/wang-jianing-app-OpenInTerminal.swift`, with
`enum wang_jianing_app_OpenInTerminal`, `family: "wang-jianing-app-OpenInTerminal"` and six `githubRules`. No
`installAssetPattern` and no `installerKind` on any of them. Shape:
```swift
GitHubReleaseRule(   // main, current id
    bundleID: "wang.jianing.app.OpenInTerminal",
    owner: "Ji4n1ng", repo: "OpenInTerminal",
    versionPattern: #"^v(2\.[0-9]+\.[0-9]+)$"#),
GitHubReleaseRule(   // main, pre-2.1.1 id
    bundleID: "wang.jianing.OpenInTerminal",
    owner: "Ji4n1ng", repo: "OpenInTerminal",
    versionPattern: #"^v(2\.[0-9]+\.[0-9]+)$"#),
GitHubReleaseRule(   // Lite pair ×2 current ids, ×2 pre-1.0.3 ids — identical config
    bundleID: "wang.jianing.app.OpenInTerminal-Lite",   // / OpenInEditor-Lite / wang.jianing.OpenIn{Terminal,Editor}-Lite
    owner: "Ji4n1ng", repo: "OpenInTerminal",
    usePrereleases: true, listPageSize: 10,
    versionPattern: #"^v(1\.[0-9]+\.[0-9]+)$"#,
    probesNewestFirst: false),
```
Rule comments, kept short as in the Reviu file, should state the contract and point to the audit
(`// History: docs/app-audits/wang-jianing-app-OpenInTerminal.md#历史与实测`). They should cover:
one repo with two interleaved trains; main is Latest **by the vendor's manual convention**, and the `2.` anchor keeps a slipped
marker from reading Lite as main; Lite rules read the list (Bitwarden shape) with page-size measurement 2026-10-14;
why `usePrereleases` is safe here; why detection-only (the Team change Q33U8R4U57→C8VX3ZLX5U plus the ad-hoc window, with the enable trigger);
legacy ids are detection-only forever (gate 4); the major-version anchor is a known fragility (main 3.x, or Lite 2.x, would
need the pattern revisited, and both surface as health misses).

Add `wang_jianing_app_OpenInTerminal.set,` to `AppRecipeIndex.all` between `uk_whatcable_whatcable.set,` and
`xyz_chatboxapp_app.set,` (case-insensitive sort).

### Step 4 — Goldens and tests
```bash
DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests   # fails on purpose, writes the golden
swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests
swift test --package-path DuoUpdaterCore --filter 'RecipeHealthKeyTests|AppRecipeIndexTests|GitHub'
cd DuoUpdaterCore && swift test          # full Core suite
swift test --package-path CLI --scratch-path DuoUpdaterCore/.build
python3 scripts/check_recipe_snapshots.py && python3 scripts/check_app_audits.py   # after Step 6
```
`rulesSharingASlugRecordSeparateHealthEntries` must pass. It now measures this slug (6 rules, so 6 health rows).
If a registry-derived test rejects a rule shape (for example a policy on `usePrereleases` with `.stable`), report it and do not weaken the test.

### Step 5 — Green: re-run channel-verify on the real bundles
Same commands as Step 2. Expected:
| Bundle | Expected verdict |
|---|---|
| main 2.3.8 (`wang.jianing.app.OpenInTerminal`) | winning source GitHub, latest 2.3.9, UPDATE (detection-only / manual) |
| main 2.3.9 | GitHub, 2.3.9, up to date |
| Lite 1.2.7 / Editor-Lite 1.2.7 | GitHub, 1.2.8, UPDATE |
| Lite 1.2.8 / Editor-Lite 1.2.8 | GitHub, 1.2.8, up to date |
| legacy main 2.0.5 (`wang.jianing.OpenInTerminal`) | GitHub, 2.3.9, UPDATE |
| legacy Lite / Editor-Lite 1.0.2 | GitHub, 1.2.8, UPDATE |
Every row has detected channel `stable`. Paste the raw output into the audit. If any Lite row shows a 2.x version, or any main
row shows a 1.x version, stop: the edition separation is broken.

### Step 6 — Audit doc and index
- `docs/app-audits/wang-jianing-app-OpenInTerminal.md`, using the app-audit § Report template **verbatim headings**
  (including 「观测版本」). Cover: the six bundle ids; the signing-era table from §0; the coverage matrix (GitHub ✓
  detection for all six, Homebrew answers for brew copies, MAS —, Sparkle —); the Phase 3⅞ table; 「一键安装」 with
  status 仅检测 (detection-only), why, the enable trigger, and **读的是**: 人人可手动下载的 GA (the GA build anyone can download by hand); 「已知问题」 (Team change and ad-hoc
  window; Latest marker is manual; major-anchor fragility; one Lite release body covers two apps); 「如何复验」 with the
  Step 2/5 raw output and the asset sha256s; and `## 历史与实测` (needed because the family file has the `// History:`
  pointer) holding the dated 2026-10-14 measurements.
  Public-repo rules apply: no `/Users/...` paths (the vendor skill contains one, so do not copy it), and nothing about which machine has which copy.
- `docs/app-audits/README.md`: one line at the end of `## Single-channel — GitHub Releases` (before `## Changelog-only`), e.g.
  `- [x] [**OpenInTerminal**](wang-jianing-app-OpenInTerminal.md) · `wang.jianing.app.OpenInTerminal` + Lite/Editor-Lite + 3 pre-rename ids — G (detection-only; one-click waits for the first post-Team-change release) · 真包 v2.3.9/v1.2.8 解包验证 ✓ · 2026-10-14`
- Commit: `Track OpenInTerminal, OpenInTerminal-Lite and OpenInEditor-Lite via GitHub releases` (body: the
  facts from §0, as in the Reviu commit).

---

## 3. Boundaries

**Don't:**
- run `make install`, `make cli`, the `duo` CLI, `pkill`/`killall`, `git stash`, `git push`, or create PRs/issues;
  write into `/Applications` or `~/Applications`; launch or `open` any downloaded app; touch quarantine xattrs. Use `swift run
  --package-path application-test …` and `swift test`, not `make test` (it also drives `xcodebuild` app tests, which are not needed here).
- edit `verify/baseline.json` (a bot owns it), `CHANNEL_COVERAGE_TODO.md` (no channel gap was found), or any
  local-only doc under `docs/` other than `app-audits/`.
- add `installAssetPattern`/`installerKind` to any rule in this change.
- add a `ChangelogRecipe`. The GitHub release body already carries the notes, and the version anchors keep the history per train.
- add a `ChannelBinding`, a channel proof, a `VendorProbeRecipe`, a Homebrew- or MAS-specific entry, or an AppScanner alias for the old ids.
- read Lite from `/releases/latest`, or drop the `2.`/`1.` anchors for a generic `v?(...)` pattern. Either one mixes the trains,
  in the version or in the history.
- change the format of existing GitHub `recipeID`s. Only the collision suffix is allowed.

**Detection-only until verified on a real machine:**
- One-click for 1.1–1.3. Enable it only after (1) the vendor ships a release after 2.3.9/1.2.8 signed by C8VX3ZLX5U,
  (2) an end-to-end 2.3.9 → next install (and 1.2.8 → next) succeeds on a real machine, with the Team unchanged, `codesign --verify --deep --strict` and
  `spctl` passing, and the FinderSync extension and login helper still working afterwards (§1.8), and (3) an era-B copy (2.3.8) is confirmed to be
  refused cleanly by gate 3. Until then, era-B users update by hand from the releases page.
- Legacy ids 1.4–1.6 stay detection-only **permanently** (the signed bundle id differs from the successor's).

**Core changes:**
| Need | Decision |
|---|---|
| Distinct `recipeID` for same-slug, same-channel GitHub rules (Step 1) | **Make it.** It is a hard prerequisite: without it an existing registry-derived test fails and the verify baseline rows collide. It is scoped to colliding rules, so no existing key changes. Fallback if the reviewer rejects it: ship only rule 1.1 (one rule on the slug, no collision) and leave 1.2–1.6 recorded as blocked on this change. |
| Team-ID transition (vendor moved Q33U8R4U57 → C8VX3ZLX5U; no allowlist exists) | **Record only** in the audit's 「已知问题」. It loosens a security gate and needs an owner decision. |
| Pre-check that downgrades one-click to manual when the installed Team can't match | **Record only.** It is moot while these rules are detection-only. |
| In-place install from a pre-rename bundle id to its successor | **Record only.** Gate 4 refuses this by design. |
| Separating trains by release name or asset for detection-only rules (instead of a major-version anchor) | **Record only** as a fragility note. No field exists, and the anchors are enough today. |
