# Secretive — onboarding plan for duo-updater

App: Secretive (https://github.com/maxgoedjen/secretive), SSH agent that keeps keys in the Secure Enclave.
Planned 2026-10-14. All evidence below was collected that day unless a date says otherwise.

Read before planning:
- `.claude/skills/app-audit/SKILL.md` (whole file).
- `.claude/skills/coverage-discovery/SKILL.md` **does not exist** in this clone (`ls .claude/skills/` →
  `app-audit channel-discovery fragile-recipe`; `git log --all -- '.claude/skills/coverage-discovery*'` is empty;
  nothing in the tree references it). Its Phase 2/3 rules could not be read. This plan follows app-audit only.
- Worked example: `git show 57e6ce0` (Reviu, `GitHubReleaseRule` + audit doc + golden + README line).

Current state: not integrated. `grep -rni "secretive\|maxgoedjen"` over `*.swift *.md *.json *.txt` in the clone → no hits.

---

## 0. Evidence summary (what I measured, how)

| Fact | Command | Raw result |
|---|---|---|
| Release history | `gh api --paginate "repos/maxgoedjen/secretive/releases?per_page=100"` | 27 releases. v0.1.1–v0.5.1 (2020-03-15 → 2020-03-24) `prerelease:true`. v1.0.0 → v4.0.0 all `prerelease:false`, `draft:false`. Every release has exactly one asset, `Secretive.zip`. Newest `v4.0.0` 2026-09-21. |
| Tags without a release | `git tag` in a clone | `v0.0.0_beta1`, `v0.0.0_test`, `v3.0.1-skipped` (no release object for any of them) |
| `/releases/latest` | `gh api repos/maxgoedjen/secretive/releases/latest` | `v4.0.0 false false 2026-09-21T03:08:01Z Secretive.zip` |
| Download URL | `curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' …/releases/latest/download/Secretive.zip` | `302 https://github.com/maxgoedjen/secretive/releases/download/v4.0.0/Secretive.zip` |
| Asset digest | `shasum -a 256` of the download vs API `digest` | `877517e2…1ac1fa` both (v4.0.0); `696d0781…d084ba` both (v3.0.4). Homebrew cask `sha256` is the same `877517e2…`. |
| Zip layout | `zipinfo -1` | `Secretive.app/…` at the top level, every version sampled (v0.1.1, v2.4.1, v3.0.4, v4.0.0). |
| Bundle identity per release (17 real zips, v0.1.1 → v4.0.0, unzipped under `scr/dl/<tag>/x`) | `plutil -extract …` | `CFBundleIdentifier = com.maxgoedjen.Secretive.Host` in **all 17**. `CFBundleShortVersionString` == tag minus `v` for every one **except v0.1.1, which reports `1.0`** (build `1`). `CFBundleVersion` = `1.<GitHub run id>` (e.g. `1.35554366823` for 4.0.0) — not comparable, never use. No `SUFeedURL` in any version. `LSMinimumSystemVersion`: 10.15 (≤1.0.3), 11.0 (2.0.0–2.3.1), 12.0 (2.4.x), 14.0 (3.0.x), **15.0 (4.0.0)**. |
| Bundle id across source history | `PRODUCT_BUNDLE_IDENTIFIER` in the project file at each of the 30 tags | Host is `com.maxgoedjen.Secretive.Host` at every tag. Since v4.0.0 it is `$(SECRETIVE_BASE_BUNDLE_ID).Host` with default `com.maxgoedjen.Secretive` (`Sources/Config/Config.xcconfig`). No rename ever. |
| Signing (v0.1.1, v0.5.1, v1.0.3, v2.0.0, v2.4.1, v3.0.0, v3.0.4, v4.0.0, nightly 2026-10-13) | `codesign -dvv`, `codesign --verify --deep --strict`, `spctl -a -vv -t exec`, `xcrun stapler validate` | All: `Developer ID Application: Max Goedjen (Z72PRUAWF6)`, verify OK, `accepted source=Notarized Developer ID`. **None is stapled** ("does not have a ticket stapled") — notarization is online-only. duo-updater's install gates are signature + Team ID + bundle id + arch + OS floor (`Install/VendorInstaller.swift` header), none requires a stapled ticket. |
| Architectures | `lipo -archs Contents/MacOS/Secretive` | v0.x–v1.0.3 `x86_64`; v2.0.0–v2.4.1 `x86_64 arm64`; v3.0.0+ `x86_64 arm64 arm64e`. No arm64 drop in any upgrade path (gate 5b safe). |
| Resident helper | `find Contents -name '*.app' -o -name '*.xpc'` + plists | `Contents/Library/LoginItems/SecretAgent.app` (`com.maxgoedjen.Secretive.SecretAgent`, `LSUIElement=true`, same version as host, Team Z72PRUAWF6) in **every** version. Registered with `SMAppService.loginItem(identifier:)` (`Sources/Secretive/Controllers/AgentStatusChecker.swift`). XPC services: `SecretiveUpdater.xpc`, `SecretAgentInputParser.xpc` (3.0+), `SecretiveCertificateParser.xpc` (4.0). Host and agent share keychain group `Z72PRUAWF6.com.maxgoedjen.Secretive` in both 3.0.4 and 4.0.0 (`codesign -d --entitlements -`). |
| App's own updater | source read: `Sources/Packages/Sources/Brief/Updater.swift`, `Release.swift`, `SemVer.swift`, `Sources/SecretiveUpdater/SecretiveUpdater.swift` | GETs `https://api.github.com/repos/maxgoedjen/secretive/releases` (the whole list, no device id, no rollout), drops `prerelease`, picks the highest version whose body's "Minimum macOS Version" ≤ this OS, and **only notifies**: the button opens the release's `html_url` (`UpdateView.swift`, `SecretAgent/Notifier.swift`). It never downloads or installs, so it can't conflict with us. Present since v0.5.0 (target `com.maxgoedjen.Brief` first appears in the v0.5.0 project). v0.1.1–v0.4.2 have no update check. Since 3.0 the fetch runs in the `SecretiveUpdater` XPC service. Same endpoint throughout. |
| Nightly track | `.github/workflows/nightly.yml` (cron `0 8 * * *`), `gh run list --workflow nightly.yml`, `gh api …/actions/artifacts` | Built daily from `main`, signed + notarized, **uploaded only as a GitHub Actions artifact** (no release, no tag). Artifacts need a GitHub login and expire. The newest at planning time was artifact `11797329765`, run `38367930469`, 2026-10-13. |
| Nightly real bundle | `gh api repos/maxgoedjen/secretive/actions/artifacts/11797329765/zip`, unzip, plutil/codesign/spctl | `com.maxgoedjen.Secretive.Host`, `CFBundleShortVersionString = 0.0.0_nightly-2026-10-13`, build `1.38367930469`, min 15.0, Team Z72PRUAWF6, verify OK, `accepted source=Notarized Developer ID`. The SecretAgent inside reports the same version. |
| Older nightly version shape | `git show 902d5c4^:.github/workflows/nightly.yml` | Before #670 (2025-09-04) the nightly substituted a bare **`0.0.0`**. Since #670 it is `0.0.0_nightly-YYYY-MM-DD`. Nightlies exist since #341 (2022-01-30). |
| One-off builds | `.github/workflows/oneoff.yml` (since #768, 2025-11-29) | `workflow_dispatch`, any branch, version `0.0.0_oneoff-YYYY-MM-DD`, artifact only. |
| Vendor's own "test build" rule | `SemVer.isTestBuild` = `versionNumbers == [0,0,0]` | The app treats every `0.0.0[_…]` build as a test build. For those, `UpdateView` shows "Download latest nightly" (`…/actions/workflows/nightly.yml`). |
| Beta format | `SemVer.swift` comment "Betas have the format 1.2.3_beta1" | Only tag `v0.0.0_beta1` exists (2020), with no release. No beta was ever published. |
| Self-builds | `configure_team_id.sh` (#783, 2026-01-06) | Writes `SECRETIVE_BASE_BUNDLE_ID_OSS=<TEAM>.com.example.Secretive` → host id `<TEAM>.com.example.Secretive.Host`, a different bundle id and Team. Out of scope. |
| Homebrew | `brew info --cask --json=v2 secretive` | Cask `secretive` 4.0.0, URL = the GitHub zip, `auto_updates` absent, `depends_on.macos` empty. No `@beta`/`@nightly` cask (`brew search --cask secretive` → `secretive` only). |
| MAS | `mas search Secretive` | Not listed. |
| Release notes | API `body` | Markdown with `## Features`, `## Fixes`, `## Minimum macOS Version` (e.g. `15.0.0` for v4.0.0, `12.0.0` for v2.4.1), `## Build`, `## Attestation`. 3.0.x bodies also embed an H1 `# New in 3.0:` block. |
| Delta | assets list + updater source | Zip only, no Sparkle and no patches. The client has no patch applier. Nothing to consume. |

### What duo-updater Core does with this today (read from code, not executed)

- `Engine/SourceStack.swift` order: MAS → Xcode → **HomebrewCaskSource** → Sparkle → **GitHubReleasesSource** → (Alcove) → VendorProbe → Electron.
  A brew-installed copy is answered by `HomebrewCaskSource` (the cask is not `auto_updates`). A directly downloaded copy needs a `GitHubReleaseRule`.
- `Models/ReleaseChannel.detect` on a nightly bundle (`name: "Secretive"`, `bundleID: com.maxgoedjen.Secretive.Host`, `version: "0.0.0_nightly-2026-10-13"`):
  no Keystone id, no bundle-id suffix (`.Host`), no channel word in the name, and no step-4 version shape matches. I simulated the step-4 regexes in Python: `tail-nightly` needs `-nightly`, and the vendor uses `_nightly`. **→ `.stable`.** Bare `0.0.0` and `0.0.0_oneoff-…` → `.stable` too.
- `Version/VersionComparator` splits on `.` `_` `-` `+` and space, so `0.0.0_nightly-2026-10-13` < `4.0.0`.
  **Consequence without a Core change:** a stable GitHub rule would show every nightly/one-off install as "4.0.0 available". That is a downgrade off the nightly track: the nightly is built from `main` after v4.0.0. With one-click enabled it would replace the nightly with stable. This is the cross-channel push the architecture forbids.
- `GitHubReleasesSource` (line ~640) skips a rule whose `channel` ≠ the installed copy's channel ("GitHub skip …: no rule for app channel"). Once nightlies read `.nightly`, the stable rule no longer touches them.
- OS floor: `GitHubReleasesSource` reads no OS requirement. Only install-time gate 6 (`SignatureVerifier.verifyRunnableSystemVersion`, `LSMinimumSystemVersion` of the download) enforces one (`Support/HostOS.swift` list).

---

## 1. Coverage checklist

Legend: **Detect** = which duo-updater source answers. **One-click** = install route. **Changelog** = where notes come from.

| # | Installed copy | Bundle id | Signing | Detect | One-click | Changelog | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | **Stable, direct download**: v1.0.0 → v4.0.0, any version | `com.maxgoedjen.Secretive.Host` | Developer ID Z72PRUAWF6, notarized (not stapled), universal since 2.0.0 | **New** `GitHubReleaseRule` → `/releases/latest`, tag `^v(X.Y.Z)$` → equals `CFBundleShortVersionString` | **Detection-only in this change** (see Boundaries §B1). The package side is verified: zip with `Secretive.app` at the root, same Team, same bundle id, notarized, no arch drop. The ready-to-add fields are `installAssetPattern: #"^Secretive\.zip$"#`, `installerKind: .zip`. | GitHub release `body` carried by `GitHubReleasesSource`. No ChangelogRecipe. | §0 rows 1–9 |
| 2 | **Stable, Homebrew** (`brew install secretive`) | same | same artifact (cask URL + sha256 = GitHub v4.0.0 zip) | `HomebrewCaskSource` answers first (no `auto_updates`). Nothing to add. | brew route (existing machinery). Not touched here. | — (existing brew path) | `brew info` row |
| 3 | **Old 2020 prerelease line** v0.1.1–v0.5.1 | same | same Team, notarized, x86_64 only | Reads `.stable` (no suffix). The stable rule offers 4.0.0. That matches the vendor's own updater, which offers the newest non-prerelease to them. v0.1.1 reports `1.0`, still < 4.0.0. v0.1.1–v0.4.2 have no in-app updater at all, so for them we are the only signal. | Same as #1 (detection-only now). Gate 6 would refuse 4.0.0 below macOS 15. | same as #1 | plist table |
| 4 | **Old stable lines on old macOS** (3.0.x on macOS 14, 2.4.x on 12/13, …) | same | same | The rule offers 4.0.0 even where it can't run (min 15.0), because GitHub rules read no OS floor. The vendor's own updater hides it, using the body's "Minimum macOS Version". **Known gap, Core change recorded, not made** (Boundaries §C2). | Detection-only now. If one-click is enabled later, gate 6 refuses at install time (no broken swap). | same as #1 | `LSMinimumSystemVersion` row, `Release.minimumOSVersion` |
| 5 | **Nightly**: `0.0.0_nightly-YYYY-MM-DD` (2025-09-04 →), and bare `0.0.0` (2022-01-30 → 2025-09-03) | same id (shared) | same Team, notarized (real 2026-10-13 bundle) | **Pattern D-ish: recognized, not served.** No feed we can read: Actions artifacts only, auth-gated, expiring, no release/tag. **Core change (make it):** a scoped `ReleaseChannel.detect` rule maps these to `.nightly`, so the stable rule skips them and no downgrade is offered. | None. Artifacts need a GitHub login and expire. | None | nightly rows |
| 6 | **One-off CI build** `0.0.0_oneoff-YYYY-MM-DD` (2025-11-29 →) | same | same pipeline as nightly (not sampled as a real bundle) | Same scoped rule → `.nightly`. Reason: the vendor treats every `0.0.0` build as a test build and routes it to the nightly page. Not served. | None | None | `oneoff.yml`, `SemVer.isTestBuild` |
| 7 | **Beta** `X.Y.Z_betaN` (format documented in `SemVer.swift`) | would be same | — | **Never shipped** (only tag `v0.0.0_beta1`, 2020, no release). Not handled; recorded only. | — | — | tags list |
| 8 | **Self-built from source** | `<TEAM>.com.example.Secretive.Host` (since 2026-01-06) | builder's own Team | Different bundle id → no rule matches → not covered, by design. | — (Team gate would refuse anyway) | — | `configure_team_id.sh` |
| 9 | **Resident helper** `SecretAgent.app` (login item, nested) | `com.maxgoedjen.Secretive.SecretAgent` | same Team | Not a separate install; it ships inside the host and is updated with it. No rule for this id. | Updated with the host's bundle. **But** the running agent process keeps the old code until the host app is next launched (`App.swift`: `if justUpdatedChecker.justUpdatedBuild … forceLaunch()`) or the user logs out. Must be verified on a real machine before one-click (Boundaries §B1). | — | `AgentStatusChecker.swift`, `JustUpdatedChecker.swift` |
| 10 | Mac App Store / TestFlight | — | — | Not distributed there. | — | — | `mas search` |

Release-reading stance (HARD RULE, Phase 3⅞): the rule reads **the public GA build anyone can download by hand**: `/releases/latest`, the same zip the README links and the cask installs. There is no staged rollout: the vendor's updater fetches the full list with no device id.

Delta / OS-split / self-updater table (for the audit doc):

| | Client capability | Server actually sends | Can we consume |
|---|---|---|---|
| Delta | No (no Sparkle, the updater only opens `html_url`; source read) | No (one zip per release, 27/27) | — |
| Per-device rollout | No (GET of the full list, no id) | No | — |
| Per-OS split | Yes: the client filters by body "Minimum macOS Version" | Yes: the body states it per release (15.0.0 for 4.0.0) | **Not today**: GitHub rules read no floor (Core gap §C2). Install gate 6 backstops it. |
| Self-updater competes with us | No: notify-only, opens the browser | — | — |

---

## 2. Steps for the executor (in order)

Work in your fresh clone. Paths below are repo-relative.

### Step 1 — Core change: Secretive test builds read `.nightly` (red → green)

1. **Red first.** In `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/ChannelGuardTests.swift`, next to `cotEditorPrereleaseShapesAreReadOnlyForCotEditor`, add a test `secretiveTestBuildsAreReadOnlyForSecretive` with these rows, all with `name: "Secretive"`:
   - Positive, with `com.maxgoedjen.Secretive.Host` → `.nightly`: `"0.0.0_nightly-2026-10-13"` (real bundle), `"0.0.0"` (pre-#670 nightly), `"0.0.0_oneoff-2025-11-29"`.
   - Negative, same id → `.stable`: `"4.0.0"`, `"3.0.4"`, `"1.0"` (what v0.1.1 really reports), `"0.5.1"`.
   - Scoping, with `com.example.other` → `.stable`: `"0.0.0_nightly-2026-10-13"`, `"0.0.0"`.
   
   Run it and paste the failure:
   `swift test --package-path DuoUpdaterCore --filter secretiveTestBuildsAreReadOnlyForSecretive`
2. **Green.** In `DuoUpdaterCore/Sources/DuoUpdaterCore/Models/ReleaseChannel.swift`, add a scoped step right after step `0.9 CotEditor` and before `// 1. Keystone`, labelled `0.10 Secretive`. Match the existing comment density: say why (shared id, `_` separator that step 4 doesn't read, vendor's `isTestBuild`, downgrade risk). Logic:
   ```swift
   if bundleID == "com.maxgoedjen.Secretive.Host",
      let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
      fullyMatches(#"0\.0\.0(_.*)?"#, version) {
       return .nightly
   }
   ```
   Re-run the filter (green), then mutation-check it: drop the `bundleID ==` clause and confirm the `com.example.other` rows fail. Restore it afterwards.
3. Also run `swift test --package-path DuoUpdaterCore --filter ChannelGuard` and paste the result.

### Step 2 — Recipe family (detection-only GitHub rule)

1. Create `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-maxgoedjen-Secretive-Host.swift`:
   ```swift
   import Foundation

   enum com_maxgoedjen_Secretive_Host {
       static let set = AppRecipeSet(
           family: "com-maxgoedjen-Secretive-Host",
           githubRules: [
           // Secretive — SSH agent (Secure Enclave). No SUFeedURL in any release
           // v0.1.1–v4.0.0; its own updater GETs this repo's /releases (no device
           // id) and only opens the release page. v-tags; short == tag.
           // CFBundleVersion is `1.<run id>`, not comparable. One asset per release,
           // `Secretive.zip`, universal, Team Z72PRUAWF6, notarized (not stapled).
           // Nightly/one-off CI builds share this id as `0.0.0[_…]` and read
           // `.nightly` (ReleaseChannel step 0.10), so this stable rule skips them.
           // Detection-only until the in-place swap is verified with the resident
           // SecretAgent login item — see the audit.
           GitHubReleaseRule(
               bundleID: "com.maxgoedjen.Secretive.Host",
               owner: "maxgoedjen", repo: "secretive",
               versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
           ])
   }
   ```
   (Comment wording is the executor's. The constructor fields are not: no `installAssetPattern`, no `installerKind`, no `usePrereleases`, no `installedTagPrefix`, default `listPageSize`.)
2. Register it in `Recipes/AppRecipeIndex.swift`: add `com_maxgoedjen_Secretive_Host.set,` between `com_mak5er_aircard.set,` and `com_meetily_ai.set,`. The order is case-insensitive by slug, and `AppRecipeIndexTests` enforces it.
3. Re-record goldens. The first run fails by design:
   `DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests`, then
   `swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests` (must pass).
   Expect `DuoUpdaterCore/Tests/RecipeGoldens/com-maxgoedjen-Secretive-Host.txt` with `channel = .stable`, `usePrereleases = false`, `installAssetPattern? = nil`.

### Step 3 — Verify against real bundles (no install)

Download into your own scratch directory, one fresh directory per package, and unzip there. Don't open, launch or de-quarantine anything.
```
curl -sSfL -o <dir>/v4.0.0/Secretive.zip https://github.com/maxgoedjen/secretive/releases/download/v4.0.0/Secretive.zip   # sha256 877517e2…1ac1fa
curl -sSfL -o <dir>/v3.0.4/Secretive.zip https://github.com/maxgoedjen/secretive/releases/download/v3.0.4/Secretive.zip   # sha256 696d0781…d084ba
gh run list -R maxgoedjen/secretive --workflow nightly.yml -L 3          # pick the newest successful run
gh api "repos/maxgoedjen/secretive/actions/runs/<run>/artifacts" -q '.artifacts[0].id'
gh api repos/maxgoedjen/secretive/actions/artifacts/<id>/zip > <dir>/nightly/artifact.zip
unzip -q <zip> -d <dir>/<tag>/x
```
Then run from the repo root and paste the raw output of each:
```
swift run --package-path application-test feed-discover <dir>/v4.0.0/x/Secretive.app                    # expect noKnownUpdater
swift run --package-path application-test channel-verify <dir>/v4.0.0/x/Secretive.app --expect stable    # expect GitHub, latest 4.0.0, up to date
swift run --package-path application-test channel-verify <dir>/v3.0.4/x/Secretive.app --expect stable    # expect GitHub, UPDATE → 4.0.0
swift run --package-path application-test channel-verify <dir>/nightly/x/Secretive.app --expect nightly  # expect channel nightly, GitHub skips, no update offered
```
For the nightly run, the pass criterion is **detected channel = nightly, and no source offers 4.0.0**. The harness may exit 1 for "chain answered nothing". If so, record the exit code and the raw text. Don't treat it as a failure and don't "fix" the harness. If any expectation fails, stop and report. Don't adjust the regex until it passes.

Also confirm, and paste the output, that the GitHub answer for 3.0.4 carries the v4.0.0 release notes (body / structured notes) in whatever form channel-verify or an existing test prints them. If it carries none, record that in the audit's 已知问题. Don't add a ChangelogRecipe.

### Step 4 — Audit doc + indexes

1. Write `docs/app-audits/com-maxgoedjen-Secretive-Host.md`, copying the app-audit report template verbatim (including 「观测版本」). It must contain:
   - 基本信息: bundle id, Team `Z72PRUAWF6`, 观测版本 `4.0.0`, 自更新机制 = 自研 notify-only (GitHub releases API → opens release page), 分发 GitHub / Homebrew `secretive`, 开源 = yes, "settled from source" rows citing `.github/workflows/release.yml`, `nightly.yml`, `oneoff.yml`, `Sources/Packages/Sources/Brief/*.swift` on `main`.
   - The coverage matrix (stable: GitHub ✓ detection, Homebrew ✓ existing; nightly: ✗ with reason).
   - A Channel 详情 table with rows stable / nightly (+ one-off) / beta (never shipped).
   - The delta/OS/self-updater table from §1.
   - Changelog = GitHub release body.
   - 一键安装: 状态 **仅检测**. 读的是 = 人人可手动下载的 GA. The blocker is the resident SecretAgent swap, not yet verified on a real machine. List the exact fields to add later.
   - 已知问题: OS-floor gap (§C2); nightly not served; artifacts not stapled (informational).
   - `## 如何复验` with the real commands and outputs from Step 3. Don't link `application-test/records/`.
   - Write for a public repo (app-audit § Writing for a public repo): no `/Users/<name>` paths, no machine narrative, no "本机".
2. `docs/app-audits/README.md`: add one line under `## Single-channel — GitHub Releases`, modelled on the Reviu line: `- [x] [**Secretive**](com-maxgoedjen-Secretive-Host.md) · \`com.maxgoedjen.Secretive.Host\` — G (detection-only; one-click pending real-machine check of the SecretAgent login item) · 真包 v4.0.0/v3.0.4 + nightly 挂载验证 · nightly 识别为 .nightly、不服务 · <date>`. App name, link, coverage and date only.
3. `CHANNEL_COVERAGE_TODO.md` §3 (死轨, 勿重开): add `✗ **Secretive — Nightly / one-off** · same id \`com.maxgoedjen.Secretive.Host\`, version \`0.0.0[_nightly-DATE|_oneoff-DATE]\` → \`.nightly\` (detect step 0.10), artifacts behind GitHub login and expiring, no release → recognized, not served`. One line, and link the audit.

### Step 5 — Checks to run and paste

```
swift test --package-path DuoUpdaterCore                       # full Core suite (includes AppRecipeIndexTests, RecipeGoldenTests, ChannelGuardTests)
python3 scripts/check_app_audits.py
python3 scripts/check_recipe_snapshots.py
python3 scripts/check_prose_claims.py
python3 scripts/check_skill_docs.py
```
Paste the commands and their tails. If something unrelated is already failing on `main`, show that it also fails on a clean checkout before you call it pre-existing.

Expected diff (and nothing else): `Models/ReleaseChannel.swift`, `Tests/.../ChannelGuardTests.swift`, `Recipes/com-maxgoedjen-Secretive-Host.swift`, `Recipes/AppRecipeIndex.swift`, `Tests/RecipeGoldens/com-maxgoedjen-Secretive-Host.txt`, `docs/app-audits/com-maxgoedjen-Secretive-Host.md`, `docs/app-audits/README.md`, `CHANNEL_COVERAGE_TODO.md`.

---

## 3. Boundaries

### A. Don't do

- Don't add `installAssetPattern` / `installerKind` in this change (see B1).
- Don't add a nightly rule or probe of any kind: GitHub Actions artifacts need auth and expire, and neither `GitHubReleasesSource` nor `VendorProbeSource` can read them. Don't set `usePrereleases: true`. The 2020 prereleases are a dead line, and nothing after them is a prerelease.
- Don't add a `ChangelogRecipe`. The release body is the changelog.
- Don't add a `VendorProbeRecipe`, `SparkleFeedCatalog` entry or `ChannelBinding`. There is no feed or preference to bind.
- Don't add a rule for `com.maxgoedjen.Secretive.SecretAgent` or the XPC ids. They are nested and updated with the host.
- Don't handle the `X.Y.Z_betaN` shape. It was never shipped. Recording it is enough.
- Don't widen the detect rule beyond `com.maxgoedjen.Secretive.Host`. Don't touch the generic step-4 version shapes, because `_nightly` read globally would change other vendors.
- Don't touch `HomebrewCaskSource` behaviour for the brew-installed copy.
- Don't install anything into `/Applications` or `~/Applications`, don't launch downloads, don't touch quarantine xattrs, don't run `make install` / `make cli` / the `duo` CLI, don't push, and don't open PRs/issues.
- Don't use `application-test/records/` as evidence in the doc.

### B. Detection-only until verified on a real machine

**B1. One-click for stable (copy #1/#3).** The package gates are all satisfied on real artifacts: same bundle id, Team Z72PRUAWF6, notarized, zip layout, no arch drop. What is **not** verified is the in-place swap with the resident login item. The open questions:
  (a) after the swap, does `SMAppService` still have the `SecretAgent` login item registered, without a new Background Items prompt?
  (b) the running agent keeps the old code until the host relaunches (`JustUpdatedChecker` → `forceLaunch`) or the user logs out. duo-updater's "Restart" prompt keys on the host process, so does it cover the agent?
  (c) do existing Secure Enclave keys stay usable (keychain group `Z72PRUAWF6.com.maxgoedjen.Secretive`, identical in 3.0.4 and 4.0.0)?
  
  To enable it later, add `installAssetPattern: #"^Secretive\.zip$"#, installerKind: .zip` after this end-to-end check on a real Mac: install 3.0.4 → duo detects 3.0.4 → 4.0.0 → one-click → host is 4.0.0 with Team Z72PRUAWF6, `codesign --verify --deep --strict` OK → `ssh-add -l` against the agent socket still lists the keys → agent version after host relaunch = 4.0.0. Then re-record goldens. Run this on a macOS 15+ machine, because 4.0.0 needs 15.0.
  
**B2. Nightly detection rule (copy #5/#6).** It is proven on one real `0.0.0_nightly-2026-10-13` bundle, via channel-verify in Step 3. The bare `0.0.0` (2022–2025) and `0.0.0_oneoff-…` shapes are settled from workflow source only. Their artifacts have expired or none was sampled. The unit test covers them. Say so in the audit, and don't claim real-bundle proof for them.

### C. Core changes

- **C1. Make it:** the scoped `ReleaseChannel.detect` step 0.10 for `com.maxgoedjen.Secretive.Host` (`0.0.0(_.*)?` → `.nightly`). Without it the stable rule offers a downgrade to every nightly/one-off install. It follows the existing scoped precedents (0.7 Little Snitch, 0.8 CCC, 0.9 CotEditor) and needs only a test plus a mutation check.
- **C2. Record only, don't make:** `GitHubReleaseRule` has no way to read a per-release OS floor. Secretive states it in the body (`## Minimum macOS Version\n15.0.0`), and its own updater honours it. Today a 3.0.x copy on macOS 14 is shown "4.0.0 available" and can never take it. Install gate 6 would refuse a one-click, so no broken swap. A body-pattern floor on GitHub rules (analogous to `VendorProbeRecipe.minimumSystemVersionPattern`, wired through `OSWindowRefusal.evaluate` so it reaches `.notForThisMacOS`) touches the source used by every GitHub-tracked app. It belongs in its own change. Note it in the audit's 已知问题 and 建议下一步, not in code.
- **C3. Record only:** artifacts are notarized but not stapled. No duo-updater gate depends on stapling today. This is informational, and needs no change.
