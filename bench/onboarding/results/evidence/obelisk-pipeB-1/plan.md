# Obelisk (tommy0103/obelisk) — onboarding plan for duo-updater

Observed 2026-10-14. Repo: https://github.com/tommy0103/obelisk (AGPL-3.0, default branch `main`).
The app is Electron. It is not in the registry today: `grep -rniI obelisk DuoUpdaterCore CLI App docs CHANNEL_COVERAGE_TODO.md application-test` returns nothing.

## 0. Summary of what was measured (evidence base for everything below)

All packages were downloaded to `scr/pkgs/`. Each file's sha256 equals the `digest` GitHub publishes for that asset. Packages were inspected with
`.claude/skills/coverage-discovery/scripts/check-bundle.sh`, `codesign -dvvv`, and the harnesses
(`swift build --package-path application-test --scratch-path ../scr/build`, so the clone stayed clean).

| Release (published) | Assets for macOS | bundle id | short = build | LSMinimumSystemVersion | SUFeedURL | Signature | Team | spctl |
|---|---|---|---|---|---|---|---|---|
| v0.1.0 (2026-06-14) | `Obelisk-0.1.0-mac-arm64.{dmg,zip}` | `com.obelisk.app` | 0.1.0 | 11.0 | none | **ad-hoc, linker-signed**, Identifier=`Electron`, Sealed Resources=none, `codesign --verify --deep --strict` exit 1 | none | — |
| v0.2.0 (2026-07-19) | `-mac-arm64.dmg` only | `com.obelisk.app` | 0.2.0 | 11.0 | none | same linker-signed shape | none | — |
| v0.2.1 (2026-07-21) | `-mac-arm64.dmg` only | `com.obelisk.app` | 0.2.1 | 11.0 | none | same | none | — |
| v0.2.2 (2026-08-03) | `-mac-arm64.dmg` only | `com.obelisk.app` | 0.2.2 | 12.0 | none | same | none | — |
| v0.2.3 | **tag only, no public release** (the releases API lists none; at that tag `app/package.json` has no `publish` config and no updater deps) | — | — | — | — | — | — | — |
| v0.2.4 (2026-10-02) | `-mac-arm64.{dmg,zip}`, `-mac-x64.{dmg,zip}`, `appcast-arm64.xml`, `appcast-x64.xml`, `latest-mac.yml`, blockmaps | `com.obelisk.app` | 0.2.4 | 12.0 | `https://github.com/tommy0103/obelisk/releases/latest/download/appcast-<arch>.xml` | Developer ID, hardened runtime, signed Identifier=`com.obelisk.app`, verify exit 0 | **433DLLA855** (MOERU AI LTD), arm64 and x64 | Notarized Developer ID |
| v0.2.5 (2026-10-08, `/releases/latest`) | same set as v0.2.4 | `com.obelisk.app` | 0.2.5 | 12.0 | same per-arch URL | same | **433DLLA855**, arm64 and x64 | Notarized Developer ID |

Other measured facts:
- **Same bundle id in every shipped build.** I read `com.obelisk.app` off the real package of every release. `build.appId` is `com.obelisk.app` in `app/package.json` at tags v0.2.0 through v0.2.5. At v0.1.0 the tag commit holds no app source; its real package also says `com.obelisk.app`. No rename has happened.
- **Architectures.** v0.1.0 to v0.2.2 are arm64-only (`lipo -archs`: arm64). Separate x64 builds start at v0.2.4. No release has a universal build.
- **v0.2.4+ updater.** Sparkle 2.9.4 through `electron-sparkle-updater` 0.5.1. If the native bridge fails at startup, the app falls back to `electron-updater` 6.6.2 reading `latest-mac.yml`; `app/src/main/update-backends.ts` picks one backend per process, before any check. `app/scripts/sparkle-packaging.mjs` writes these Info.plist keys at build time:
  `SUFeedURL`, `SUPublicEDKey = nodBHokaX/9bAlyvXDuiIQEQP3HmpuK2d+fLswGTLPk=` (same in 0.2.4 arm64, 0.2.5 arm64 and 0.2.5 x64), `SUAutomaticallyUpdate=false`,
  `SUEnableInstallerLauncherService=false`, `SUVerifyUpdateBeforeExtraction=true`, `SUScheduledCheckInterval=3600`, `SUDeltaChainHistory=0`.
  `Contents/Resources/app-update.yml` = `provider: github, owner: tommy0103, repo: obelisk, releaseType: draft`.
- **Appcast shape** (`scr/feeds/v02{4,5}-appcast-*.xml`). Each release attaches its own appcast with **one** `<item>`: no `<sparkle:channel>`, `<sparkle:minimumSystemVersion>12.0`, an enclosure pointing at the release's `-mac-<arch>.zip` with `sparkle:edSignature`, and **no `<sparkle:deltas>`** (`grep -c deltas` = 0 in all four files). Because the feed URL is `releases/latest/download/…`, it always serves the newest non-prerelease release's single item. `<description>` holds **Markdown without `sparkle:format="markdown"`** (generator: `app/scripts/update-release.mjs` line 71).
- `feed-discover` output (production `FeedDiscovery`):
  - 0.2.5 arm64, 0.2.5 x64, 0.2.4 arm64: `declared  https://github.com/tommy0103/obelisk/releases/latest/download/appcast-<arch>.xml (… SparkleAppcastSource already resolves this app)`
  - 0.2.2 and 0.1.0: `—  no Sparkle and no electron-builder update config`
- `channel-verify --expect stable` (production `UpdateChecker` chain, current `main`), excerpts:
  - 0.2.4 arm64 `.app`: `winning source Sparkle` · `latest 0.2.5` · `download …/v0.2.5/Obelisk-0.2.5-mac-arm64.zip` · `changelog pane raw inline notes, 6385 chars, no structure` · `release history 1 entries` · `deltas 0` · `status UPDATE → 0.2.5`
  - 0.2.5 arm64 `.app` / 0.2.5 x64 `.app`: `winning source Sparkle` · `latest 0.2.5` · `changelog pane raw inline notes, 6385 chars, no structure` · `status up to date` (the x64 copy reads `appcast-x64.xml` and gets the x64 zip)
  - 0.2.2 dmg and 0.1.0 `.app`: `detected channel → stable` · `SUFeedURL <none>` · `winning source <none>` · `changelog pane none` · `status unknown (no source answered)`
- **Channels.** Stable only. Every release has `prerelease=false`. Both backends hard-code stable: Sparkle reads `releases/latest`, and electron-updater sets `allowPrerelease=false, channel='latest'`. ADR `docs/adr/0015-desktop-sparkle-and-electron-updater.md` says "The initial channel is stable." `release-app.yml` *accepts* `vX.Y.Z-rc.N` tags and would mark them `--prerelease`, but no such tag or release exists.
- **No other macOS distribution.** `brew search --cask obelisk` finds no cask (formulae.brew.sh `/api/cask/obelisk.json` returns 404). The iTunes Mac search for "obelisk" returns nothing relevant. The homepage https://obelisk.antinomie.org links only to GitHub releases.
- **Nested bundles in 0.2.5.** The four Electron helpers `Obelisk Helper{, (GPU), (Plugin), (Renderer)}.app` (`com.obelisk.app.helper*`, LSUIElement=true) are child processes of the main app. Sparkle's `Updater.app` (`org.sparkle-project.Sparkle.Updater`, LSUIElement=1) runs only while an update is being installed. There is no `Contents/Library/LoginItems` and no LaunchAgent. Main-process source (`app/src/main/index.ts`, `indexer-worker-client.ts`) has no Tray and no `setLoginItemSettings`. The indexer is an in-process `worker_threads` Worker. On macOS, closing the window keeps the app itself running (standard Electron, `window-all-closed` quits only on non-darwin). **No resident helper.**
- **Separate edition from the same repo, not a macOS app.** The CLI `@obelisk-apps/cli` (npm: `latest 0.3.0`, `rc 0.2.6-rc.0`; installed by the repo's `install.sh` via `npm install --global`). Its package.json has **no `repository` field**, and it publishes no GitHub releases (the repo's tags are all `vX.Y.Z` desktop tags). Linux `.deb`, the DSH plugin and the agent skill are outside duo-updater's scope.

## 1. Coverage checklist

Legend: ✓ works on current `main` · ➕ added by this plan · ✗ not possible (reason given) · ⏸ detection-only until verified.

### 1.1 `com.obelisk.app` 0.2.4+ (Developer ID builds that declare `SUFeedURL`), arm64 and x64, stable

- **Signing path.** Developer ID 433DLLA855, notarized, hardened runtime, signed identifier `com.obelisk.app`. The EdDSA key has been the same in every build so far.
- **Resident helper.** None (see §0).
- **Detection: ✓ already, generic `SparkleAppcastSource`.** The bundle declares a per-arch `SUFeedURL`, and the feed's single item is untagged, so it is a default-channel item. Evidence: `feed-discover` = `declared`; `channel-verify` 0.2.4 arm64 → `UPDATE → 0.2.5`; 0.2.5 arm64 and x64 → `up to date`. **No recipe and no `sparkleFeeds` entry.** A probe or catalog entry pointing at this address would never run, because Sparkle sits ahead of it in `SourceStack.make`.
  - What it reads: the newest published stable on GitHub (`/releases/latest`). That is the same build anyone can download by hand from the Releases page. There is no device id and no staged rollout, so nothing runs ahead of allocation.
  - OS floor: the item carries `<sparkle:minimumSystemVersion>12.0`, and `SparkleAppcastSource` already filters on it.
- **One-click: available through the Sparkle route** (enclosure `Obelisk-<ver>-mac-<arch>.zip`, EdDSA plus Team-ID gate). The pieces line up: same Team (433DLLA855) at 0.2.4 and 0.2.5 on both archs, same signed identifier, same `SUPublicEDKey`, notarized, zip. **⏸ End-to-end not run.** A real `duo install` from 0.2.4 to 0.2.5 needs `make cli` + `duo` + `ditto` into `/Applications`, which the executor is not allowed to do (see Boundaries). Record it as 「未跑」 with that reason.
- **Changelog: ✗ today ("raw inline notes, 6385 chars, no structure") → ➕ a `ChangelogRecipe` with `structuredFormat: .gitHubReleases`.** The Sparkle `<description>` is Markdown with no `sparkle:format="markdown"`, and Core treats Markdown as Markdown only when that attribute is set (`SparkleAppcastSource.swift` ~L1074/L1212) or `<markdownDescription>` is present. The appcast also carries only the current release (`release history 1 entries`). The GitHub release bodies hold the same notes as Markdown with `##`/`###` headings for all 6 releases. A recipe outranks the source's notes in the pane. Precedents: Waku (`Recipes/sh-waku.swift`), Rockxy.

### 1.2 `com.obelisk.app` 0.1.0, 0.2.0, 0.2.1, 0.2.2 (older builds that lack the feed newer builds declare), arm64 only

- **Signing path.** Ad-hoc **linker-signed** only: Identifier=`Electron`, no sealed resources, `codesign --verify --deep --strict` exit 1, no Team ID. 0.1.0–0.2.1 need macOS 11.0+; 0.2.2 needs 12.0+.
- **Resident helper.** None. These builds have the same Electron helpers and no Sparkle.
- **Detection: ✗ today (`status unknown`) → ➕ a detection-only `GitHubReleaseRule`.** These copies have no `SUFeedURL` and no `app-update.yml`, so `SparkleAppcastSource` and `ElectronManifestSource` skip them and `GitHubReleasesSource` gets them. For 0.2.4+ copies, Sparkle answers first, so the rule never decides for them. This is exactly the MacDown 3000 precedent (`Recipes/app-macdown-macdown3000.swift`). Tags are `vX.Y.Z` and equal `CFBundleShortVersionString`. v0.2.1's tag points at the same commit as v0.2.0, but its real package says 0.2.1, so tag and bundle agree.
  - What it reads: `/releases/latest`, the public stable build. Nothing runs ahead of allocation.
  - Expected after the change (the executor must measure it): `channel-verify` on the 0.1.0 `.app` and the 0.2.2 dmg → `winning source GitHub`, `latest 0.2.5`, `status UPDATE → 0.2.5`, `download <nil>` (detection-only).
- **One-click: ✗ by design, so `installAssetPattern` stays nil.**
  - Team-ID route: the installed copy has no Team ID, and `SignatureVerifier.verifyTeamIdentifierMatch` throws `noTeamIdentifier(which: "installed")` (`Install/SignatureVerifier.swift:358`).
  - Digest-only route (`.publishedDigestOnly`, #952): not usable either way. The installed seal does not verify (linker-signed, no resources: the MarkText case in #952), and the download has a Team ID, so `digestOnlyIdentity` yields `.teamAppeared` and refuses "ad-hoc → Developer ID" (`SignatureVerifier.swift:87,189-191`).
  - The vendor's own 0.2.5 notes say the same: "Existing **0.2.2 installations** … require one manual upgrade."
  - Leaving the pattern nil also prevents an arch mix-up on fall-through. The source is arch-aware anyway (`GitHubReleasesSource.swift` ~L307-321).
- **Changelog: ➕ the same `.gitHubReleases` recipe.** It is keyed by bundle id with no channel, so it serves these copies too. Without it, the GitHub source's own structured log would show.
- **Known gap, recorded only, no change (see Boundaries).** A macOS 11 user on 0.1.0–0.2.1 will be offered 0.2.5, which needs 12.0. `GitHubReleaseRule` has no OS-floor field (`grep hostRequirement\|minimumSystem Sources/GitHubReleasesSource.swift` finds nothing). The impact is limited because this rule never installs.

### 1.3 v0.2.3

- No public release exists, so a GitHub user cannot have it. A copy built from source at that tag would have no `SUFeedURL` and would fall under the §1.2 rule (detection only). No item needed.

### 1.4 Channels / tracks

- **stable.** The only track. Covered by 1.1 and 1.2.
- **beta / rc / nightly.** None shipped. `release-app.yml` could publish `vX.Y.Z-rc.N` as a GitHub prerelease.
  - The anchored `versionPattern` below refuses such tags. `.gitHubReleases` changelog drops prereleases. Sparkle's `releases/latest` excludes them.
  - Nothing to add. Write it in the audit doc as "no non-stable track exists as of 2026-10-14; an rc build would share the bundle id and carry the stable feed URL, so it would need its own audit".
- No same-bundle-id switch exists in source: no pref key, `allowPrerelease=false` is hard-coded.

### 1.5 Copies built from source / dev builds

- Ad-hoc or unsigned, any arch. Builds made from ≥0.2.4 source through electron-builder still get the `SUFeedURL` from `beforePack`, so Sparkle detects them. Builds from older source fall under 1.2.
- One-click is refused safely by the Team gate: installed copy without a Team ID. Detection only. No item needed.

### 1.6 The electron-updater fallback (`latest-mac.yml`)

- Not a separate install kind. It is the same bundle with the same `SUFeedURL`. `ElectronManifestSource` comes last in `SourceStack`, so Sparkle answers first. Nothing to add.

### 1.7 CLI `@obelisk-apps/cli` (npm global; not a .app)

- Covered generically by duo's npm global-packages group (#949), **if** it was installed with `npm -g` under a supported prefix.
- Release notes: ✗. That group reads the package.json `repository`'s GitHub Releases, and this package declares no `repository` and publishes no CLI releases.
- Out of scope for this app onboarding. Mention it in the audit doc; no code change.

### 1.8 Delta / own-updater interplay (for the audit doc's table)

| | Client capability | What the server actually ships | Can we consume it |
|---|---|---|---|
| Delta | Sparkle 2.9.4 framework present (can apply BinaryDelta); `SUDeltaChainHistory=0` | None: no `<sparkle:deltas>` in the 4 appcasts (2026-10-14). electron-updater `.blockmap` files exist, but those are electron-updater differential downloads | Nothing to consume: no Sparkle delta is published, and blockmaps are not a mechanism we have |
| Staged rollout per device | No (no device id in the feed URL) | No (static GitHub asset) | — |
| Per-arch / per-OS tracks | Per arch: `appcast-arm64.xml` / `appcast-x64.xml` chosen by the bundle's own `SUFeedURL` | The item carries `minimumSystemVersion 12.0` | Yes. `SparkleAppcastSource` reads the bundle's own per-arch URL and the floor |
| Own updater competing with us | Automatic checks every 3600 s with auto-download; `SUAutomaticallyUpdate=false`, so it installs only on the user's click (`installUpdateNow`) | — | No silent install races a duo swap. Note it in the audit doc |

## 2. Steps for the executor

Work in the fresh clone on a branch, e.g. `git switch -c recipe/obelisk origin/main`. Keep downloads in a `mktemp -d` scratch directory outside the repo.

1. **Re-measure before writing anything.** These are cheap and the reviewer will ask for the raw lines.
   ```sh
   gh api repos/tommy0103/obelisk/releases/latest -q '.tag_name'      # expect v0.2.5 (or newer: re-run everything on the newest)
   B=https://github.com/tommy0103/obelisk/releases/download
   curl -sSfL -o "$SCR/Obelisk-0.2.5-mac-arm64.zip" "$B/v0.2.5/Obelisk-0.2.5-mac-arm64.zip"
   curl -sSfL -o "$SCR/Obelisk-0.2.4-mac-arm64.zip" "$B/v0.2.4/Obelisk-0.2.4-mac-arm64.zip"
   curl -sSfL -o "$SCR/Obelisk-0.2.2-mac-arm64.dmg" "$B/v0.2.2/Obelisk-0.2.2-mac-arm64.dmg"
   curl -sSfL -o "$SCR/Obelisk-0.1.0-mac-arm64.zip" "$B/v0.1.0/Obelisk-0.1.0-mac-arm64.zip"
   .claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR"/Obelisk-*.zip "$SCR"/Obelisk-*.dmg
   swift run --package-path application-test feed-discover "$SCR/Obelisk-0.2.5-mac-arm64.zip"   # expect: declared
   swift run --package-path application-test feed-discover "$SCR/Obelisk-0.2.2-mac-arm64.dmg"   # expect: — no Sparkle …
   ```
   `channel-verify` takes a `.app` or `.dmg`, **not a zip**. Unpack zips with `unzip -q` (or `ditto -x -k`) into the scratch directory first.

2. **Create `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-obelisk-app.swift`** (enum `com_obelisk_app`, family `"com-obelisk-app"`). It holds exactly one GitHub rule and one changelog recipe:
   ```swift
   githubRules: [
   // <comment: the claims of §1.2 — copies 0.1.0–0.2.2 ship no SUFeedURL (Sparkle
   //  arrived in 0.2.4, whose bundles declare releases/latest/download/appcast-<arch>.xml
   //  and are answered by SparkleAppcastSource first; MacDown 3000 is the same shape);
   //  tags vX.Y.Z == CFBundleShortVersionString; anchored so a future vX.Y.Z-rc.N
   //  prerelease is refused; detection-only because those copies are linker-signed
   //  ad-hoc with no Team ID (gate 3 refuses, digest-only refuses ad-hoc→Developer ID,
   //  and their seal does not verify); 0.2.4+ is Developer ID 433DLLA855, notarized.>
   GitHubReleaseRule(
       bundleID: "com.obelisk.app",
       owner: "tommy0103", repo: "obelisk",
       versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#),
   ],
   changelogs: [
   // <comment: Sparkle <description> is Markdown without sparkle:format="markdown", so the
   //  pane showed "raw inline notes … no structure"; each appcast carries only its own
   //  release. GitHub release bodies carry the same notes with ##/### headings for every
   //  release (Waku / Rockxy route).>
   ChangelogRecipe(
       bundleID: "com.obelisk.app",
       source: URL(string: "https://api.github.com/repos/tommy0103/obelisk/releases?per_page=40")!,
       mode: .json,
       maxEntries: 20,
       structuredFormat: .gitHubReleases),
   ]
   ```
   - Leave `installAssetPattern`/`installerKind` **nil**. Do not set `installTrust`, `usePrereleases`, `installedTagPrefix` or `tagPattern`: the repo carries only desktop `v*` releases. Do not add `sparkleFeeds`.
   - Optional, decide on the measured pane: `skipSections` for the install-instruction headings only. Names must match exactly: `Installation`, `Downloads`, `Install the Linux package`, `Install or update the CLI`, `Install the CLI`, `macOS installation`.
     - Do it only if the step-5 `changelog pane` line shows those sections as change items. Keep `Highlights`, `Updates` and `Included work`.
     - Read `skipSections`' doc comment and `ChangelogReviewRegressionTests` first.
   - Follow the comment style of `Recipes/com-jorisgallot-reviu.swift` / `app-macdown-macdown3000.swift`: claims plus dates, history in the audit doc.

3. **Register the family.** Add `com_obelisk_app.set,` to `AppRecipeIndex.all` in `Recipes/AppRecipeIndex.swift`, in sorted position.

4. **Re-record goldens.** From the repo root:
   ```sh
   DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests   # fails on purpose
   swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests                               # must pass
   ```
   Commit the new `DuoUpdaterCore/Tests/RecipeGoldens/com-obelisk-app.txt`.

5. **Verify detection and the changelog on real packages.** Paste the raw output into the audit doc's 「如何复验」.
   ```sh
   swift run --package-path application-test channel-verify "$SCR/x/old010/Obelisk.app" --expect stable   # GitHub, latest 0.2.5, UPDATE → 0.2.5, download <nil>
   swift run --package-path application-test channel-verify "$SCR/Obelisk-0.2.2-mac-arm64.dmg" --expect stable   # same
   swift run --package-path application-test channel-verify "$SCR/x/new024/Obelisk.app" --expect stable   # Sparkle, UPDATE → 0.2.5, download …-mac-arm64.zip
   swift run --package-path application-test channel-verify "$SCR/x/new025/Obelisk.app" --expect stable   # Sparkle, up to date
   ```
   Pass criteria:
   - The 0.2.4 and 0.2.5 copies still have `winning source Sparkle`; the new rule must not change that.
   - On every run, `changelog pane` says `recipe …` with **non-empty `headings [...]`** (e.g. `Highlights`, `Updates`, `Complete session browsing`).
   - If `headings []` appears with heading text among the items, the headings were flattened: report it, do not hide it.
   - Also run one x64 copy (`Obelisk-0.2.5-mac-x64.zip` unpacked) and confirm `download …-mac-x64.zip`.

6. **Write the audit doc `docs/app-audits/com-obelisk-app.md`.**
   - Copy the § Report template from `.claude/skills/app-audit/SKILL.md` verbatim, including 「观测版本」.
   - Content: the §0 table, §1.1–1.8, the HARD-RULE answer (it reads the public GA build = `/releases/latest`), and delta in three columns.
   - 一键安装: "Sparkle route for 0.2.4+: 端到端未跑 (needs `make cli`/`duo`/`/Applications`, not run by this agent); 0.1.0–0.2.2: 仅检测, reasons above".
   - Follow § Writing for a public repo: no `/Users/<name>` paths, no machine framing. Write "真包 … 解包/挂载验证", not anything about a machine.

7. **Add a README index line.** Put one line in `docs/app-audits/README.md` under `## Single-channel — GitHub Releases`, because a G rule is added. Do **not** write ``— S``, which would trip `genericSparkleIndexRowsStayInTheSparkleSection`. Example:
   `- [x] [**Obelisk**](com-obelisk-app.md) · `com.obelisk.app` — G (detection-only, 0.1.0–0.2.2 without SUFeedURL) + C (GitHub releases) · 0.2.4+ via Sparkle (declared) · 真包 0.1.0/0.2.2/0.2.4/0.2.5 验证 ✓ · 一键 (Sparkle) 端到端未跑 · 2026-10-14`

8. **Run the full suite and judge it by exit code, in the foreground.**
   ```sh
   make test; echo "exit=$?"
   ```
   That includes `scripts/check_app_audits.py`, `AppAuditCoverageTests` and the prose and offpool checks. Fix the doc or the recipe until it exits 0. Paste the command and the tail of the output.

9. **Commit and stop.** Commit with `git commit -F <msgfile>` and the subject `Track Obelisk: GitHub detection for pre-Sparkle copies + GitHub-releases changelog`. Do not push and do not open a PR.

10. **Report to the reviewer.**
    - The three counts per install kind: 0.2.4+ Sparkle detection ✓ / one-click Sparkle route, e2e not run / changelog structured; 0.1.0–0.2.2 detection ✓ / one-click ✗ with reason / changelog structured.
    - Raw `channel-verify` lines.
    - The asset URLs used: newest `…/v0.2.5/Obelisk-0.2.5-mac-arm64.zip`, previous `…/v0.2.4/Obelisk-0.2.4-mac-arm64.zip`, pre-Sparkle `…/v0.2.2/Obelisk-0.2.2-mac-arm64.dmg`.

## 3. Boundaries

**Do not:**
- run `make install`, `make cli`, the `duo` CLI, `pkill`/`killall`, `git stash` or `git push`, or create PRs/issues;
- copy into `/Applications` or `~/Applications`, launch or open any downloaded bundle, touch quarantine xattrs, or do anything that shows system UI. Mount dmgs only with `hdiutil attach -nobrowse -readonly -noautoopen` and detach them afterwards;
- add a `VendorProbeRecipe` or a `sparkleFeeds` (`SparkleFeedCatalog`) entry for `com.obelisk.app`:
  - 0.2.4+ already declares its feed, and a probe for that address would be a dead recipe that looks alive;
  - the old copies don't ship Sparkle at all, and a fill-in would also hand an arm64 feed to any non-arm64 source build;
- set `installAssetPattern` or `installTrust: .publishedDigestOnly` on the GitHub rule (§1.2: refused by gate 3 and by the digest-only identity rule; the vendor itself requires one manual upgrade from 0.2.2);
- add a channel rule, `ChannelBinding` or `ChannelProof`: no non-stable track exists;
- edit the CLI/npm group for `@obelisk-apps/cli`, or touch the local-only docs (`docs/app-onboarding-status.md`, `docs/top50-coverage-todo.md`) with `git add -f`;
- link `application-test/records/` from the audit doc;
- file anything upstream. Asking the vendor to add `sparkle:format="markdown"` or a `repository` field is their business; at most, mention it in the audit's 已知问题.

**Detection-only / unverified until run on a real machine:**
- One-click for 0.2.4+ through the Sparkle route. All gates line up on paper (same Team 433DLLA855 at 0.2.4 and 0.2.5 on both archs, same signed identifier, same EdDSA key, notarized zip), but no real `duo install` swap has run.
  - It needs the coverage-discovery Phase 5 run: the user adds `Bash(ditto:*)`, then `make cli`, install 0.2.4 arm64 into `/Applications`, `duo install "Obelisk" --yes`, `codesign --verify --deep --strict`, check TeamIdentifier, `spctl`, then Trash the test copy.
  - That is for the orchestrator/user, serially. Not for the executor.
  - Until it has run, the audit doc says 「需要验证 / 端到端未跑」, never ✓.
- The `.gitHubReleases` changelog headings are only a hypothesis until step 5's `changelog pane` line shows non-empty `headings`.
- The GitHub rule's verdict for 0.1.0–0.2.2 likewise waits on step 5's `channel-verify` output.

**Core changes: record only, do not make them in this onboarding:**
- `GitHubReleaseRule` has no OS-floor field. 0.1.0–0.2.1 run on macOS 11, while 0.2.2+ and the 0.2.5 offer need 12.0. A macOS 11 user on those copies would be offered a build that cannot run. The rule is detection-only, so there is no install harm. Record it in the audit's 已知问题 and suggest it as a possible Core follow-up. Do not add the field here: it is a Core API change that this app alone doesn't justify, and doing it unasked is out of scope.
- Treating Markdown inside a format-less Sparkle `<description>` as Markdown would be a heuristic in `SparkleAppcastSource`. #933 removed exactly such a heuristic, so don't do it. The changelog recipe solves this app without touching Core.
- Future rc builds: an `X.Y.Z-rc.N` bundle would carry the stable `releases/latest` feed URL and share the bundle id. If the vendor ever ships one, it needs its own audit (channel detection on a real rc bundle). Note it; no change now.
