# Onboarding plan: Spotifast (crmne/spotifast, formerly Fastpotify)

Planner's evidence date: 2026-10-14. Downloads used are in `scr/dl/`. Source excerpts are in `scr/src/`, and the `main` tarball is in `scr/srcmain/`.
Everything below marked **measured** was read off a real artifact or a live API response.
Anything marked **from source** was read in the vendor's code but not run.
Anything marked **unverified** is a hypothesis the executor must settle.

## 0. Facts the executor should not re-derive

| Fact | Value | How it was established |
|---|---|---|
| Repo | `crmne/spotifast`. It was `crmne/fastpotify`, and GitHub redirects the old name (`gh api repos/crmne/fastpotify` → `crmne/spotifast`) | measured |
| Releases | 30 in total (= 30 tags). 21 are stable, `v0.1.0` … `v0.13.0`. 9 are rc prereleases (`v0.4.0-rc1..rc5`, `v0.5.0-rc1..rc2`), every one flagged `prerelease: true`, none after 2026-09-01. Every non-rc release has `prerelease: false`. No drafts | measured, `releases?per_page=100` |
| Newest | `v0.13.0`, 2026-10-13. `/releases/latest` → `v0.13.0`, `prerelease false` | measured |
| Imminent | `Cargo.toml` on `main` already says `0.13.1`, and `packaging/release-notes/v0.13.1.md` exists. **If 0.13.1 has shipped when you run this, use it as "newest" and 0.13.0 as "previous" throughout** | measured on `main` |
| macOS asset | One universal dmg per release. `spotifast-v<ver>-macos-universal.dmg` from v0.8.0 on. v0.8.0–v0.9.1 also attach a byte-identical `fastpotify-v<ver>-…dmg`, and ≤v0.7.1 attach only `fastpotify-v<ver>-…dmg`. There is no mac zip and no arm64-only build | measured (asset list + digests) |
| Asset digests | Every asset has a GitHub `digest`. `shasum -a 256` of all 9 downloaded dmgs matches its digest (e.g. 0.13.0 `7c16925e…a93c`, 0.12.0 `80570465…daab6`) | measured |
| Version scheme | tag `vX.Y.Z` ↔ `CFBundleShortVersionString` `X.Y.Z` ↔ `CFBundleVersion` `X.Y.Z`. An rc is short `0.5.0-rc2` / build `0.5.0` | measured (dmgs) + `packaging/macos/bundle.sh` |
| OS floor | `LSMinimumSystemVersion` `11.0` on every dmg, from 0.1.0 to 0.13.0; universal `x86_64 arm64` | measured |
| Sparkle / Electron | None. No `SUFeedURL`, no `app-update.yml`, and `Contents/` holds only `Info.plist`, `MacOS/Spotifast`, `Resources/spotifast.icns` and `_CodeSignature` | measured (0.13.0 dmg) |
| Nested apps / LaunchAgents / LoginItems | None in any dmg checked | measured (`check-bundle.sh` + `find`) |
| Official homebrew-cask | None: `brew info --cask spotifast` / `fastpotify` give "No Cask"; `formulae.brew.sh/api/cask/spotifast.json` → 404 | measured |
| Vendor tap | `crmne/homebrew-tap` `Casks/spotifast.rb` (renamed from `fastpotify` on 2026-09-14, with `cask_renames.json`). Version 0.13.0, the same dmg URL and sha256, **no `auto_updates`**, `app "Spotifast.app"` | measured |
| MAS | None | measured: `mas search spotifast` → "No apps found"; README on `main` never mentions the App Store |

## 1. Coverage checklist

### 1a. Bundle ids, editions and signing across history (all measured on real dmgs with `check-bundle.sh`)

| Release range | `.app` in dmg | `CFBundleIdentifier` | Executable | Signature | Notarized |
|---|---|---|---|---|---|
| 0.1.0 | `Fastpotify.app` | `me.paolino.fastpotify` | `fastpotify` | ad-hoc, signed id `fastpotify-7ddae23c…` (linker-signed); `codesign --verify --deep --strict` **exit 1** | no ("no usable signature") |
| 0.4.0-rc1, 0.5.0-rc2, 0.7.1 (stand-ins for 0.2.0–0.7.1 and all rcs) | `Fastpotify.app` | `me.paolino.fastpotify` | `fastpotify` | ad-hoc, `TeamIdentifier=not set`, verify exit 0 | no |
| 0.8.0, 0.9.1 (0.9.0 assumed the same: the identity code is the same at the v0.9.0 tag, but its dmg was not downloaded) | **two identical bundles**: `Fastpotify.app` and `Spotifast.app` (`diff -rq` identical) | `me.paolino.fastpotify` | `fastpotify` | Developer ID, **Team `JPL7999US3`** ("PlentyLabs UG (haftungsbeschrankt) & Co. KG") | yes, "Notarized Developer ID" |
| 0.10.0, 0.12.0, 0.13.0 (0.10.1–0.11.2 assumed the same from `bundle.sh` history) | `Spotifast.app` | **`rocks.spotifast.Spotifast`** | `Spotifast` | Developer ID, Team `JPL7999US3` | yes |

`bundle.sh` history agrees (from source). At `06bc3cf2c6` the identifier is `rocks.spotifast.Spotifast`, except that version `0.9.1` was forced to keep `me.paolino.fastpotify` ("Last bridge for older updaters' bundle identity validation"). Before that it was `me.paolino.fastpotify` throughout.

**Rename bound for `BundleIDMigration`:** `lastFromVersion: "0.9.1"`, `firstToVersion: "0.10.0"`, Team `JPL7999US3` for both ids (measured).

### 1b. The app's own updater, by era (from source; nothing was run)

| Era | Updater | Effect on old copies |
|---|---|---|
| 0.1.0–0.1.3 | none (`src/updates.rs` first lands in `7b2812719f`, 2026-08-28) | never hears about anything |
| 0.2.0–0.7.1 | notify only: `api.github.com/repos/crmne/fastpotify/releases/latest` (redirects), links to the release page, never installs | the user downloads by hand |
| 0.8.0, 0.9.0 | in-tree installer (`#383`). It accepts **only** `me.paolino.fastpotify` (`const IDENTIFIER` in `src/updates/macos.rs` at both tags) | `/releases/latest` has been a `rocks.spotifast.Spotifast` build since 0.10.0, so these copies' own updater refuses every current release ("The download is not a Spotifast app bundle"). **They are stuck.** This is the main reason old-id one-click is worth doing |
| 0.9.1 | in-tree installer that accepts both ids and both executable names | can self-update to current releases; swaps in place at the existing path, so the `.app` filename is kept |
| 0.10.x–0.11.x | `fastframe-update` crate, accepting both ids | — |
| 0.12.0+ | `fastframe-update` v0.5.1 (as of 0.13.x). `bundle_ids: ["rocks.spotifast.Spotifast"]`, `publisher_key` required (Ed25519 over `checksums.txt`) | — |

Current updater behaviour (fastframe-update README at `v0.5.1` plus `src/settings.rs` / `src/app.rs` on `main`):
- It reads `/releases/latest` once a day (`check_for_updates` defaults to true). It never offers prereleases (`Prereleases::Never`, which Spotifast does not override), and an rc copy hears about its final release.
- It downloads only when the user clicks or `download_updates_automatically` is on; that setting **defaults to false**.
- The download is staged in `.spotifast-update-<16 hex>/` beside the bundle (for example `/Applications/.spotifast-update-…`, mode 0700). It is applied **only** when the user clicks "Restart to update" (`Action::InstallUpdate` → `updater.handoff`). The helper then waits for the app to exit, keeps `previous`, swaps the bundle and relaunches.
- There is no apply-on-quit. Nothing installs from paths read back from disk: a `Prepared` lives only in the process's memory.
- It refuses a copy that a Homebrew Caskroom owns ("Update this installation with Homebrew").
- `keep_playing_in_background` **defaults to true**: closing the window hides the app to the tray, and **the same main process keeps running**.
- Deltas: none. It downloads the whole dmg.

### 1c. Installed-copy matrix: detection, one-click and changelog routes

Legend: G = `GitHubReleasesSource` rule, M = `BundleIDMigration` entry, CL = `ChangelogRecipe` (GitHub releases).

| # | Installed copy a user may have | Detection route | One-click route | Changelog route |
|---|---|---|---|---|
| 1 | **`rocks.spotifast.Spotifast` 0.10.0+**, `Spotifast.app`, Team JPL7999US3, notarized (the current edition) | G rule keyed `rocks.spotifast.Spotifast` → `/releases/latest` | **Yes**: dmg `^spotifast-v[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$`, `.dmg`. The previous release (0.12.0) and 0.10.0 are the same Team (measured). Needs the e2e run in §2 step 9 before it is reported ✓ | CL on `rocks.spotifast.Spotifast` |
| 2 | Same id at **`/Applications/Fastpotify.app`**: an old copy the vendor's 0.9.1+ updater swapped in place, keeping the old filename | same rule (matched by id; the filename is irrelevant to G). The tap and official cask catalogs do not index it | same as #1. duo swaps at the installed path, so the name stays `Fastpotify.app`, as with the vendor's updater (`ArchiveExtractor.firstApp` + in-place swap) | CL |
| 3 | **`me.paolino.fastpotify` 0.8.0–0.9.1**, Developer ID JPL7999US3, either `Fastpotify.app` or `Spotifast.app` | **Second G rule keyed `me.paolino.fastpotify`**, the same repo and patterns. A rule is needed because `GitHubReleasesSource` looks up `rules[app.bundleID]` (`GitHubReleasesSource.swift:651`), **not** `recipeBundleID`, so a migration entry alone does not route this copy | **Detection-only at first** (old-id rule ships with `installAssetPattern: nil`). Flip it to installable **only after** the old-id e2e round (§2 step 9c) passes. That path depends on M: gate 4 (`verifyBundleIdentifierMatch`) lets a `rocks.spotifast.Spotifast` download replace a `me.paolino.fastpotify` copy below 0.10.0 for Team JPL7999US3. Gate 3 passes (same Team, measured) | CL through M: `InstalledApp.recipeBundleID` files this copy under `rocks.spotifast.Spotifast` (`ChangelogRecipeSelection.swift:9`) |
| 4 | **`me.paolino.fastpotify` 0.2.0–0.7.1**, ad-hoc, no Team, not notarized | the same old-id G rule (version < 0.13.0 → UPDATE) | **No.** Gate 3 throws `noTeamIdentifier(which: "installed")` (`SignatureVerifier.swift:358`). The user updates by hand once; later copies are on the Developer ID route. `installTrust: .publishedDigestOnly` is **not** appropriate: the download is Developer ID, not ad-hoc, and the identity differs | CL through M |
| 5 | **`me.paolino.fastpotify` 0.1.0–0.1.3**: ad-hoc, `codesign --verify` fails, no in-app updater | old-id G rule | **No** (gate 3, as #4) | CL through M |
| 6 | **rc builds** `0.4.0-rc1…rc5`, `0.5.0-rc1/rc2` (old id, ad-hoc) | old-id G rule. `ReleaseChannel.detect` classifies `0.5.0-rc2` as `.stable`: no step matches `-rcN`, and the CotEditor `-rc` branch is bundle-id-gated. So the stable rule answers and VersionComparator offers 0.13.0. **The executor confirms this with channel-verify on the rc dmg** | **No** (ad-hoc, gate 3) | CL through M. The `.gitHubReleases` decoder drops `prerelease: true` entries for `.stable` (`StructuredChangelogDecoder.swift:710`), so rc notes never appear |
| 7 | **Vendor-tap Homebrew copy** (`brew install --cask crmne/tap/spotifast`), the same notarized dmg, id per #1/#3 | `HomebrewCaskSource` does **not** answer: `HomebrewCaskCatalog` indexes only `formulae.brew.sh/api/cask.json` (precedent: `docs/app-audits/com-supercmd-SuperCmd.md`). It falls through to G, and the version is the same as the tap's (the tap updates minutes after each release, measured on tap commit times) | one-click works mechanically but leaves the Caskroom at the old version. The vendor's own updater refuses tap-owned copies. **Record it as a known issue; no code change** (see Boundaries) | CL |
| 8 | **Nix (flake) build on macOS**: built from source, `rcodesign` ad-hoc, id `rocks.spotifast.Spotifast`, version = `Cargo.toml` (it can be ahead of the newest release, e.g. `0.13.1` from `main`) | G rule (the same id). It reads as up to date or ahead | **No** (no Team → gate 3); also read-only `/nix/store` | CL |
| — | Beta / nightly / preview channel | **None exists.** There is no channel setting in `settings.rs` (only `check_for_updates`, `download_updates_automatically`), no `Prereleases::WhenRunningPrerelease`, and no rc since 2026-09-01. CI builds are workflow artifacts, not releases. **No channel rule, no `CHANNEL_COVERAGE_TODO.md` change** | — | — |
| — | Resident helper | None nested. The only thing that outlives the window is the **main process itself** (tray, `keep_playing_in_background=true`). That is the ordinary "app still running" case for `AppRestarter`; it is not a nested helper. The vendor helper is transient (it runs from a bundle copy in the staging folder during a handoff) | — | — |

**What the rules read:** the newest public GA (`/releases/latest`). That is what the vendor's own updater and the tap read, and anyone can download it by hand from the release page. It is not ahead of any allocation; there is no staged rollout.

**Published digest:** handled with no per-rule code, because GitHub `digest` is passed on (#1019). The vendor's `checksums.txt` + Ed25519 `checksums.txt.sig` have no duo consumer, and none is needed.

## 2. Steps for the executor (in order)

Work in your own clone on a branch from `origin/main`. Use `SCR=$(mktemp -d "$TMPDIR/recipe-spotifast.XXXX")` for downloads. Run everything in the foreground.

1. **Re-check the facts that can drift:**
   ```bash
   gh api repos/crmne/spotifast/releases/latest -q '.tag_name, .prerelease, (.assets[] | "\(.name)\t\(.digest)")'
   gh api 'repos/crmne/spotifast/releases?per_page=5' -q '.[] | "\(.tag_name) \(.prerelease)"'
   ```
   If 0.13.1 (or later) is out, shift "newest" and "previous" accordingly.

2. **Download the real packages** (newest, previous, last old-id signed, an ad-hoc old one, an rc):
   ```bash
   for spec in v0.13.0:spotifast v0.12.0:spotifast v0.9.1:spotifast v0.7.1:fastpotify v0.5.0-rc2:fastpotify; do
     t=${spec%%:*}; n=${spec##*:}; f="$n-$t-macos-universal.dmg"
     curl -sSL -o "$SCR/$f" "https://github.com/crmne/spotifast/releases/download/$t/$f"
   done
   shasum -a 256 "$SCR"/*.dmg          # compare with the API digests
   .claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR"/*.dmg
   ```
   Expect §1a. Note that `check-bundle.sh` picks the first `.app` it finds; for the 0.9.1 dmg that is `Spotifast.app`, which is identical to `Fastpotify.app`.

3. **feed-discover** on the newest dmg. Expect `noKnownUpdater` (no Sparkle, no electron-builder config):
   ```bash
   swift run --package-path application-test feed-discover "$SCR/spotifast-v0.13.0-macos-universal.dmg"
   ```
   Any other verdict: stop and re-plan.

4. **Create the family file** `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/rocks-spotifast-Spotifast.swift`, enum `rocks_spotifast_Spotifast`, family `"rocks-spotifast-Spotifast"`. Match the magpie/diri style (a comment per rule stating the measured claims, as in `com-dirijor-diri.swift`).
   - `changelogs:` one `ChangelogRecipe`:
     `bundleID: "rocks.spotifast.Spotifast"`, `source: https://api.github.com/repos/crmne/spotifast/releases?per_page=40`, `mode: .json`, `maxEntries: 20`, `channel: .stable`, `structuredFormat: .gitHubReleases`. **No `skipSections` initially** (see step 7).
   - `githubRules:` **two** rules on `owner: "crmne", repo: "spotifast"`, both with `versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#`. The anchor refuses the `-rcN` tags.
     - `bundleID: "rocks.spotifast.Spotifast"`, `installAssetPattern: #"^spotifast-v[0-9]+\.[0-9]+\.[0-9]+-macos-universal\.dmg$"#`, `installerKind: .dmg`.
     - `bundleID: "me.paolino.fastpotify"`, **detection-only** (`installAssetPattern` / `installerKind` omitted). Its comment must say why it exists: `GitHubReleasesSource` keys on the on-disk id, not `recipeBundleID`. It must also say it becomes installable only after the old-id e2e round passes.
   - Precedent for two bundle ids on one repo in one family: `com-tinycast-app.swift`, `dev-zed-Zed.swift`.

5. **Register the family** in `AppRecipeIndex.all` in slug order: `rocks_spotifast_Spotifast.set,` between `pro_betterdisplay_BetterDisplay.set,` and `ru_starmel_OpenSuperWhisper.set,`.

6. **Add the `BundleIDMigration` entry** in `DuoUpdaterCore/Sources/DuoUpdaterCore/Models/BundleIDMigration.swift` `all`. This is a data row in an existing table, not a mechanism change. Use the WorkBuddy entry's comment style:
   ```swift
   BundleIDMigration(
       from: "me.paolino.fastpotify", to: "rocks.spotifast.Spotifast",
       teamID: "JPL7999US3", lastFromVersion: "0.9.1", firstToVersion: "0.10.0"),
   ```
   The comment cites the measured dmgs (0.9.1 old id, 0.10.0 new id, both JPL7999US3), the vendor's 0.9.1 "bridge" in `packaging/macos/bundle.sh`, and the audit doc. `BundleIDMigrationTests.everyEntryLandsOnRecipesAndLeavesTheOldIdUnkeyed` must still pass: the `to` side lands on the changelog recipe, and the `from` side has no vendor or changelog recipe (the old-id **GitHub** rule is not in that check, by design of the test).

7. **Re-record goldens, then verify on real bundles:**
   ```bash
   DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests   # fails on purpose
   swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests                              # must pass
   swift run --package-path application-test channel-verify "$SCR/spotifast-v0.13.0-macos-universal.dmg" --expect stable
   swift run --package-path application-test channel-verify "$SCR/spotifast-v0.12.0-macos-universal.dmg" --expect stable
   ```
   Expected: 0.13.0 → winning source GitHub, latest 0.13.0, up to date. 0.12.0 → UPDATE → 0.13.0, download URL `…/v0.13.0/spotifast-v0.13.0-macos-universal.dmg`.
   For the old-id copies, mount read-only and pass the `.app` path explicitly (the 0.9.1 dmg holds two apps):
   ```bash
   hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$SCR/m091" "$SCR/spotifast-v0.9.1-macos-universal.dmg"
   swift run --package-path application-test channel-verify "$SCR/m091/Fastpotify.app" --expect stable
   swift run --package-path application-test channel-verify "$SCR/m091/Spotifast.app"  --expect stable
   hdiutil detach "$SCR/m091"
   # same for v0.7.1 (Fastpotify.app) and v0.5.0-rc2 (Fastpotify.app, --expect stable)
   ```
   Expected for each: detected channel stable, source GitHub (old-id rule), UPDATE → 0.13.0. **If the rc copy is not detected as `stable`, or gets no answer, stop.** Record what it printed, and do not add a channel rule without asking.

   **Changelog pane decision point.** Read the `changelog pane` line for 0.12.0. Expect `recipe changelog:rocks.spotifast.Spotifast:…: N entries` with headings like `["New","Fixed","Thanks"]` (the bodies use `## New` / `## Fixed` / `## Changed` / `## Known limitations` / `## Thanks`; v0.8.0 and v0.2.0 bodies use CRLF). Check three things on the real output:
   - (a) whether the `**Download Spotifast:** [Mac](…) · …` paragraph or the lead paragraph becomes an item;
   - (b) whether `Thanks`, a paragraph listing @handles, becomes a heading carrying a contributor list;
   - (c) what the 0.1.x bodies (`**Full Changelog**: …` only) produce.

   Only if (b) shows `Thanks` as a heading with the contributor paragraph as an item, add `skipSections: ["Thanks"]`. Re-record the goldens and record the before/after pane lines in the audit doc. If (a) leaks, record it as a known issue; do **not** change `GitHubMarkdownParser` (see Boundaries).

8. **A focused test,** `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/SpotifastCoverageTests.swift`. Keep it small:
   - `GitHubReleaseRegistry` has exactly one rule each for `rocks.spotifast.Spotifast` and `me.paolino.fastpotify` on `crmne/spotifast`. The old-id rule has `installAssetPattern == nil` (or the dmg pattern, if step 9c flipped it).
   - Both rules' `versionPattern` accepts `v0.13.0` and rejects `v0.5.0-rc2` and `v0.4.0-rc1`.
   - `BundleIDMigration.recipeBundleID(for: "me.paolino.fastpotify", installedVersion: "0.9.1")` is `"rocks.spotifast.Spotifast"`; with `"0.5.0-rc2"` it is the new id too; with `"0.10.0"` it stays `me.paolino.fastpotify`.

   Then run `make test` in the foreground and judge it by exit code. Also run `python3 scripts/check_app_audits.py`.

9. **End to end (`coverage-discovery` Phase 5)**. Do this only if your brief allows `make cli`, `duo`, and `ditto` into `/Applications` (it is the serial, orchestrator-only step there). Otherwise skip it and write 「未跑」 with the reason. Before every `ditto`, both ids must be absent:
   `mdfind "kMDItemCFBundleIdentifier == 'rocks.spotifast.Spotifast'"` and `mdfind "kMDItemCFBundleIdentifier == 'me.paolino.fastpotify'"` must print nothing. **Never overwrite a real install.**
   - **9a. New id, not running:** 0.12.0 `Spotifast.app` → `/Applications/Spotifast.app` (one `ditto` per command). Then `duo check Spotifast` → `duo install Spotifast --yes --json`. Record outcome, short/build version, inode change, `codesign --verify --deep --strict` exit, `spctl -a -vv -t exec`, TeamIdentifier, `diff -r` against the vendor bundle, and `duo backups`.
   - **9b. New id, running:** reinstall 0.12.0 and launch it. Close its window so it sits in the tray. Optionally click "Download update" in its update dialog: it stages 0.13.0 in `/Applications/.spotifast-update-*`. Then `duo install` → `duo restart Spotifast`, and poll the on-disk version for about 10 s. Confirm three things: the tray-resident process is the one that got restarted (`pgrep -fl "/Applications/Spotifast.app/"` before and after); the disk stays 0.13.0; and whether a `.spotifast-update-*` folder is left beside the bundle. A staged build *older* than duo's cannot be produced with release builds: the vendor's `--demo-update-feed` hook exists only under the `demo` cargo feature. So the downgrade collision in Boundaries stays **unreproduced**. Say so.
   - **9c. Old id, Developer ID** (the gate for flipping the old-id rule to installable): temporarily build a CLI whose old-id rule carries the dmg `installAssetPattern` / `.dmg`. Run it twice, from the 0.9.1 dmg: once with its `Fastpotify.app` → `/Applications/Fastpotify.app`, once with `Spotifast.app` → `/Applications/Spotifast.app`, one at a time. Each: `duo check` (expect UPDATE 0.9.1 → 0.13.0 via GitHub) → `duo install --yes`. Expect success: the installed copy is `rocks.spotifast.Spotifast` 0.13.0, Team JPL7999US3, `codesign --verify --deep --strict` 0, and the path keeps its original filename. **Only if both pass:** keep `installAssetPattern` on the old-id rule, update the test from step 8, re-record goldens, and re-run `make test`. **If either fails:** revert to detection-only and record the exact `duo install` message.
   - **9d. Old id, ad-hoc** (refusal check): 0.7.1 `Fastpotify.app` → `/Applications/Fastpotify.app`. `duo check` shows UPDATE → 0.13.0, and `duo install --yes` must refuse (no installed Team ID, or "detection only") with the bundle untouched (same inode, still 0.7.1).
   - Clean up: `pgrep -f "/Applications/Spotifast.app/"` and `pgrep -f "/Applications/Fastpotify.app/"` must be empty (quit the app normally if it is running). Move test installs to the Trash with Finder (`osascript … delete POSIX file …`), never `rm`. Report what is left: the Trash, `duo backups`, any `.spotifast-update-*` folder, and the permission rule.

10. **Audit doc** `docs/app-audits/rocks-spotifast-Spotifast.md`, using the app-audit report template **verbatim**, including 「观测版本」. It must contain:
    - the §1a table;
    - the vendor-updater era table from §1b (the 0.8.0/0.9.0 copies are stuck on their own updater);
    - the coverage matrix (stable × GitHub ✓; Homebrew `—`, because the tap cask is not indexed);
    - a Channel 详情 row saying there is a single track, with rcs historical and excluded by the tag anchor and the `prerelease` flag (cite `settings.rs` having no channel toggle: "settled from source");
    - the 按 OS 分轨 floor (11.0, universal, one bucket);
    - the delta table (client 无: whole-dmg download; server 无; 不适用);
    - Changelog with the raw `changelog pane` line(s);
    - 一键安装: 读的是 = 人人可手动下载的 GA, the e2e results or 「未跑」, the per-copy-type verdicts from §1c, and the digest check (GitHub `digest`, measured equal to `shasum`);
    - 已知问题 (Boundaries below);
    - a 「如何复验」 section with the commands and raw outputs of steps 2, 3 and 7.

    Follow § Writing for a public repo: `~/…` paths only, no machine narrative, never "本机". No link to `application-test/records/`.

11. **README index line** in `docs/app-audits/README.md` under `## Single-channel — GitHub Releases`. It names the app, the link, `rocks.spotifast.Spotifast` (with "0.9.1 及以前是 `me.paolino.fastpotify`，见 `BundleIDMigration`", as the WorkBuddy CN line does), `G C`, the one-click scope, and the date. Nothing about any machine.

12. Commit if your brief says to (`git commit -F <file>`); never push and never open a PR. The commit message lists the three counts: detection, one-click, changelog.

## 3. Boundaries

**Do not:**
- Change `GitHubReleasesSource` to look rules up by `recipeBundleID`. That would be the cleaner fix for the rename: then `BundleIDMigration`'s doc line "Recipes are keyed by the NEW id" would hold for GitHub rules too, and the second rule would be unnecessary. But it is a **Core behaviour change** for every GitHub-sourced app, and today only WorkBuddy (a VendorProbe app) uses the table. **Record it in the audit doc's 建议下一步 as a follow-up; do not make it.**
- Add a `ChangelogRecipe` keyed `me.paolino.fastpotify`. The migration routes old copies to the new-id recipe, and `BundleIDMigrationTests` fails if the `from` id is keyed by a changelog recipe.
- Use `installTrust: .publishedDigestOnly` to get one-click for the ad-hoc copies (≤0.7.1, rcs, Nix). The download is Developer ID with a different signed identity; that route is for ad-hoc *downloads*.
- Add a beta/rc channel rule, a `ChannelBinding`, or a `CHANNEL_COVERAGE_TODO.md` entry. The vendor publishes no live prerelease track.
- Add an `installedTagPrefix`, `hostRequirement`, `listPageSize` or `checksumPattern`. None is needed: the floor is static at 11.0, the build is universal, and the digest arrives through GitHub.
- Change `GitHubMarkdownParser` (it is shared; `parserGeneration` bumps) to fix a cosmetic leak found in step 7. Record it instead.
- Touch `HomebrewCaskCatalog` / `HomebrewCaskSource` to index third-party taps.
- Use `make install`, `pkill`/`killall`, `git stash`, `git push`, PRs or issues, launch anything outside step 9b, or set/remove quarantine. Do not do step 9 at all unless your brief explicitly permits it.

**Detection-only until verified on a real machine:**
- The **old-id rule** (`me.paolino.fastpotify`) ships detection-only, and becomes one-click only if step 9c passes for both the `Fastpotify.app` and `Spotifast.app` filenames.
- The **new-id one-click** is written into the rule (the measured Team and notarization support it) but must not be reported as ✓ until 9a passes. If 9a fails, remove `installAssetPattern` and report detection-only.
- Ad-hoc copies (0.1.x–0.7.1, rcs, Nix) are permanently detection-only (gate 3). They are not "pending".

**Known issues to record (no code change):**
1. **Tap-installed copies.** duo's one-click updates the bundle behind Homebrew, and the Caskroom version goes stale. The vendor's own updater refuses such copies. Core gap: `HomebrewCaskCatalog` reads only the official `cask.json`. Record it; don't fix it.
2. **Possible downgrade by the vendor updater (unreproduced; from source).** Scenario: a running pre-swap process holds an in-memory `Prepared` for an older release, duo installs a newer one, and the user then clicks "Restart to update" in that still-running process. The fastframe helper backs up duo's bundle as `previous` and installs the older staged dmg: its `validate` compares the download against the job's version and Team, not against what is on disk. It is reachable only between `duo install` and the app's restart, and only by an explicit click. A magpie-style clearance (#1007: delete `.spotifast-update-*` so the handoff finds no folder) would close it. That would be a **Core change (`SelfUpdaterStaging` / `StagedBuildClearance`)**. **Record it as a follow-up only.**
3. **Changelog leaks,** if step 7 found any: describe them, with the pane line.
4. **The 0.1.x dmgs** fail `codesign --verify` (linker-signed binary, no `_CodeSignature`). This is irrelevant to detection.
