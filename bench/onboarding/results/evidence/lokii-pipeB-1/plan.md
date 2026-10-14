# Lokii onboarding plan (`huangy7/lokii`)

Planner's observations were made 2026-10-14. Paths below are relative to the duo-updater repo root
unless absolute. `$SCR` = `$BENCH_ROOT/runs/lokii-pipeB-1/scr`
(the planner's scratch dir, which already holds every downloaded package, see "Evidence on disk").

## TL;DR

- One app, one bundle id (`com.lokii.app`, unchanged across all history), one channel (stable), two
  per-arch editions (thin arm64 dmg, thin x86_64 dmg). No Sparkle, no electron-builder config.
  The app's own updater only reads `api.github.com/repos/huangy7/lokii/releases/latest` and opens
  the dmg URL in the browser, so it never swaps the bundle.
- **Every release is ad-hoc signed** (`flags=0x2(adhoc)`, no Team ID, not notarized; `spctl`
  rejects it). The seal verifies, the signed identifier is `com.lokii.app`, and the short version
  equals the tag. That is exactly the `installTrust: .publishedDigestOnly` class (Alacritty,
  Flameshot, darktable), **not** the Obelisk/MarkText detection-only class.
- Work: one `GitHubReleaseRule` (detection + digest-only one-click on per-arch dmg), goldens,
  update `DigestOnlyRecipeTests` (it pins the exact set of digest-only rules, so it **will fail**
  otherwise), audit doc + README row. **No ChangelogRecipe**: the vendor publishes no notes. Every
  release body is the release workflow's fixed string. **No Core change.**

---

## 1. Coverage checklist

### 1.0 Facts every item below relies on (with evidence)

| Fact | Evidence |
|---|---|
| Repo | `huangy7/lokii`, MIT, created 2026-10-02, default branch `main`, 6 commits, no other branches. Website `https://lokii.huangy.top` (alias `lokii.huangy.dev`) only links to `releases/latest/download/Lokii-{arm64,x86_64}.dmg`. It has no changelog page, and its version label still says v0.1.1 |
| Releases | 3 published releases: `v0.1.0` (2026-10-03), `v0.1.1` (2026-10-06), `v0.1.2` (2026-10-13, `/releases/latest`). None prerelease, none draft. Tags = exactly these three. Each release has exactly two assets, `Lokii-arm64.dmg` and `Lokii-x86_64.dmg` (no version in the name), and both carry a GitHub `digest` |
| Digests == bytes | `shasum -a 256` of all 6 downloads equals the API `digest` (arm64 0.1.2 `ff475bae…8b29`, x86_64 0.1.2 `95b5be83…db3c`, arm64 0.1.1 `291a53f9…71bd`, x86_64 0.1.1 `c4ac5972…2593`, arm64 0.1.0 `2d548bf6…2924`, x86_64 0.1.0 `483685fd…856a`) |
| Bundle identity (all 6 real packages, mounted read-only via `check-bundle.sh` + `codesign -dvv`) | `CFBundleIdentifier=com.lokii.app`, `CFBundleShortVersionString` = tag without `v` (0.1.0 / 0.1.1 / 0.1.2), `CFBundleVersion=1` on every build (the workflow builds from a depth-1 checkout, so `git rev-list --count HEAD` = 1. Don't use the build number for anything), `LSMinimumSystemVersion=13.0`, `LSUIElement=true`, no `SUFeedURL`, archs: thin `arm64` / thin `x86_64` per file |
| Signing (all 6) | `Identifier=com.lokii.app`, `CodeDirectory … flags=0x2(adhoc)`, `Signature=adhoc`, `TeamIdentifier=not set`, `codesign --verify --deep --strict` exit 0 (resources sealed, not linker-signed), `spctl -a -t exec` exit 3 (rejected), `stapler validate`: no ticket. The dmg itself is unsigned ("code object is not signed at all") |
| Nested code | None. Bundle = `MacOS/Lokii`, `Resources/{Assets.car, Lokii.icns, en.lproj, zh-Hans.lproj}`, `_CodeSignature`. No `LoginItems`, `Helpers`, `LaunchAgents`, XPC, or frameworks. Source has no `SMAppService` / login-item code |
| Why ad-hoc (settled from source) | `.github/workflows/release.yml` + `scripts/build.sh` on `main`: if the `APPLE_CERTIFICATE` / `LOKII_SIGN_IDENTITY` secrets are absent it does `codesign --force --sign -` ("启用 Ad-hoc 签名"), and notarization runs only when `LOKII_NOTARY_PROFILE` is set. A Developer ID path exists in the script, so the vendor **could** switch later (see Boundaries) |
| Version scheme (settled from source) | `release.yml` `prepare` job fails unless tag `vX` == `lokii-core/Cargo.toml` `version`; `build.sh` writes that same Cargo version into `CFBundleShortVersionString`. So tag ↔ short version is enforced by the vendor's CI |
| Release atomicity (settled from source) | The release is created as a **draft**. Both arch legs upload into it, then the `publish` job (`needs: release`) un-drafts it with `--latest`. If either arch fails, the release stays a draft, so `/releases/latest` never shows a release with one arch missing |
| Bundle id history (settled from source) | `bundle_id="com.lokii.app"` in `scripts/build.sh` since the root commit `93f3ccb`, and `PRODUCT_BUNDLE_IDENTIFIER: com.lokii.app` in `Lokii/project.yml`. `git log --all -G'PRODUCT_BUNDLE_IDENTIFIER\|bundle_id\|com\.lokii'` shows only the root commit. Pickaxe across all reachable revs finds only `com.lokii.app` |
| Pre-rewrite v0.1.0 | Actions history shows an earlier `Release` run for `v0.1.0` on 2026-10-02 (commit `ace89438`, now unreachable from `main`, history was rewritten), plus a failed run (`216ecf98`). At `ace89438` and `216ecf98`, `build.sh` still says `bundle_id="com.lokii.app"` and Cargo `version = "0.1.0"`. **Not verified on a real bundle**: downloading that run's workflow artifact was denied in planning, and the release object from that day no longer exists |
| App's own updater (settled from source) | `Lokii/Lokii/AppUpdater.swift`: GET `https://api.github.com/repos/huangy7/lokii/releases/latest` 3 s after launch and from the menu; compares `tag_name` minus `v` to `CFBundleShortVersionString`; on update it **opens the arch-matching dmg URL in the browser** (`NSWorkspace.open`). No download/staging/swap. Strings in the 0.1.2 binary confirm the URL |
| Channels | None besides stable. No prerelease ever. No channel preference anywhere in source (`AppUpdater` hardcodes `/releases/latest`). `ci.yml` builds but uploads nothing, so there is no nightly |
| Homebrew | Not in official homebrew-cask (`brew info --cask lokii` → "No Cask with this name exists"; `formulae.brew.sh/api/cask/lokii.json` → 404). Third-party tap `huangy7/homebrew-tap` `Casks/lokii.rb`: **stale at 0.1.1** (its `update-homebrew.yml` never ran for v0.1.2: the release is published with `GITHUB_TOKEN` unless `RELEASE_PAT` is set, and token-triggered events don't start workflows). No `auto_updates`. `HomebrewCaskSource` reads only `formulae.brew.sh/api/cask.json` (`HomebrewCaskCatalog.swift:325`), so it never answers for the tap cask, and a tap install falls through to GitHub |
| MAS | none (`itunes.apple.com/lookup?bundleId=com.lokii.app&entity=macSoftware` → 0 results) |
| Generic sources | `feed-discover` on the real 0.1.2 arm64 dmg: `Lokii [com.lokii.app] 0.1.2 (1) — no Sparkle and no electron-builder update config` |
| Baseline (red) | `channel-verify` on the real 0.1.0 arm64 dmg with today's code: `detected channel → stable`, `VendorProbe — no recipe registered for 'com.lokii.app'`, `winning source <none>`, `changelog pane none`, `status unknown (no source answered)` |
| Repo coverage today | `grep -rni lokii` over the duo-updater clone: no hits (Sources, Tests, docs) |
| OS window | `LSMinimumSystemVersion=13.0` on every release, no maximum anywhere. GitHub releases state nothing. Gate 6 reads the floor off the bundle. No `hostRequirement` needed (13.0 is below the DuoUpdater floor in practice, and the bundle states it anyway) |
| Delta | Client: none (no Sparkle, updater opens a browser). Server: none (release = 2 dmgs). Not applicable |
| Rollout | None. `/releases/latest` is the public GA that the website's download buttons and the app's own updater both use. **Reads: the GA anyone can download by hand** |

### 1.1 Installed-copy kinds

| # | Kind of installed copy | Bundle id | Signing path | Resident helper | Detection route | One-click route | Changelog route |
|---|---|---|---|---|---|---|---|
| A | **stable, arm64 build** (`Lokii-arm64.dmg`, any of 0.1.0–0.1.2) | `com.lokii.app` | ad-hoc, no Team, seal verifies, not notarized | none (the app itself is `LSUIElement`; since 0.1.2 it switches to `.regular` at launch when `show_in_dock` is true, the default) | **New** `GitHubReleaseRule` → `/releases/latest`, tag `^v(…)$` vs `CFBundleShortVersionString` | **Digest-only** (`installTrust: .publishedDigestOnly`, `installAssetPattern` `^Lokii-(arm64\|x86_64)\.dmg$`, `.dmg`). Arch selection picks `Lokii-arm64.dmg` on Apple silicon. Offered only when the user enabled digest-only installs in Settings. Proof = GitHub `digest` + gate 2 (seal) + plist id/version + signed id | **None**: every release body is the literal `See the assets to download this version and install.` (the `gh release create --notes` string in `release.yml`). No CHANGELOG file in the repo, no notes on the website. ✗ with that reason |
| B | **stable, x86_64 build on an Intel Mac** | `com.lokii.app` | same as A | none | same rule | same rule. Arch selection picks `Lokii-x86_64.dmg` (host-arch token `x86_64`) | ✗ (same) |
| C | **x86_64 build running under Rosetta on Apple silicon** (user grabbed the wrong dmg) | `com.lokii.app` | same | none | same rule | same rule picks `Lokii-arm64.dmg` (host arch first). Gate 5b only refuses dropping an arm64 slice, so x86_64→arm64 passes. Not separately end-to-end tested; low risk, record as such | ✗ |
| D | **Copies from the pre-rewrite v0.1.0 release** (published 2026-10-02 from `ace89438`, since deleted) | `com.lokii.app` per `build.sh` at that commit (**source-derived, not bundle-verified**) | ad-hoc per the same script (not verified) | none expected | same rule (0.1.0 < 0.1.2) | same rule. Digest-only identity needs no Team on either side, so an ad-hoc 0.1.0 is fine | ✗ |
| E | **Tap install** (`brew install --cask huangy7/tap/lokii`, cask stuck at 0.1.1) | `com.lokii.app` | same artifacts as A/B (cask URLs are the release dmgs) | none | `HomebrewCaskSource` declines (official catalog only), so it falls through to the same GitHub rule | same rule. Caveat: Caskroom metadata stays at the cask's version after an in-place swap (same as the diri tap precedent). Record under 已知问题, no code | ✗ |
| F | **Locally built / dev copy** (`make release` / Xcode, `CODE_SIGN_IDENTITY: "-"`, possibly `CFBundleShortVersionString` from `Info.plist` source = `0.1.2`) | `com.lokii.app` | ad-hoc | none | same rule (version comparison only) | digest-only would refuse nothing extra (identity check is by plist id/version of the **download**). Not a target, nothing to do | ✗ |
| — | beta / nightly / RC channels | — | — | — | **Do not exist** (no prerelease ever, no channel pref, CI uploads nothing) | — | — |
| — | Other editions (MAS, Setapp, CLI) | — | — | — | **Do not exist** | — | — |
| — | Old versions lacking a feed newer ones declare | — | — | — | **N/A**: no version declares any feed. All versions use the same self-check against the GitHub API | — | — |

Self-updater collision: none possible. Lokii's updater never writes the bundle; it opens the dmg URL in the
browser, so the user installs by hand (drag from dmg).

### 1.2 Coverage matrix the audit doc should show

|            | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|------------|---------|----------|-----|--------|-------------|
| **stable** | — | —（仅第三方 tap，不在官方 catalog；落到下一个源） | — | ✓（digest-only 一键，按架构 dmg） | — |

Current winning source: **GitHub**.

---

## 2. Steps (executor)

Template: `git show 4cf8459` (diri, the most recent single-app `GitHubReleaseRule` commit: family file,
`AppRecipeIndex` line, goldens, audit doc, README row). For the digest-only shape, read
`DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/org-darktable.swift` (per-arch dmgs + `.publishedDigestOnly`)
and `org-alacritty.swift` (the shared rationale), plus `docs/app-audits/org-alacritty.md`
§「三条改为 digest-only」 for the evidence table format.

0. **Branch.** In the fresh clone: `git fetch origin && git switch -c recipe/lokii origin/main`.
   Use your own scratch: `SCR=$(mktemp -d "$TMPDIR/recipe-lokii.XXXX")`. Pass
   `--scratch-path "$SCR/swiftbuild"` to every `swift run --package-path application-test …` so that
   no build products land in the tree.

1. **Re-fetch the evidence yourself** (don't take this plan's numbers on trust; the reviewer will compare):
   ```bash
   gh api "repos/huangy7/lokii/releases?per_page=100" \
     -q '.[] | "\(.tag_name) pre=\(.prerelease) draft=\(.draft) \([.assets[] | "\(.name)=\(.digest)"] | join(" "))"'
   gh api repos/huangy7/lokii/releases/latest -q .tag_name          # expect v0.1.2 unless upstream shipped since
   for t in v0.1.1 v0.1.2; do for a in arm64 x86_64; do mkdir -p "$SCR/$t-$a"
     curl -sSfL -o "$SCR/$t-$a/Lokii-$a.dmg" "https://github.com/huangy7/lokii/releases/download/$t/Lokii-$a.dmg"
   done; done
   shasum -a 256 "$SCR"/*/Lokii-*.dmg                                  # must equal the API digests
   .claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR"/*/Lokii-*.dmg
   ```
   Also run `codesign -dvv` on the mounted `.app` of the newest and previous arm64 dmg
   (`hdiutil attach -nobrowse -readonly -noautoopen -mountpoint …`, then detach), and record
   `Identifier`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`. If upstream shipped a newer release in the
   meantime, use it as "newest" and the one before it as "previous". **If any newest asset now shows a
   `TeamIdentifier`, stop and re-plan** (see Boundaries B4).

2. **Add the family file** `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-lokii-app.swift`:
   ```swift
   import Foundation

   enum com_lokii_app {
       static let set = AppRecipeSet(
           family: "com-lokii-app",
           githubRules: [
           // Shared rationale for digest-only: Recipes/org-alacritty.swift.

           // Lokii — native file search (Rust core + AppKit), huangy7/lokii. No
           // updater we can read: no `SUFeedURL`, no electron-builder config; the
           // app's own check (`Lokii/Lokii/AppUpdater.swift`) reads
           // `/releases/latest` and only opens the dmg in a browser, so it never
           // swaps the bundle. One channel: no release has ever been a
           // prerelease and there is no channel setting. The release workflow
           // refuses a tag that differs from `lokii-core/Cargo.toml`, and
           // `scripts/build.sh` writes that version into
           // `CFBundleShortVersionString`, so short == tag without the `v`.
           //
           // Ad-hoc signed, no Team ID: `build.sh` signs with `-` unless the
           // repo's signing secrets are set. The seal verifies, the signed
           // identifier is the bundle id, so one-click is digest-only. One thin
           // dmg per architecture, both named without a version; arch selection
           // picks this Mac's. No nested code, no login item.
           GitHubReleaseRule(
               bundleID: "com.lokii.app",
               owner: "huangy7", repo: "lokii",
               versionPattern: #"^v([0-9]+(?:\.[0-9]+)+)$"#,
               installAssetPattern: #"^Lokii-(arm64|x86_64)\.dmg$"#,
               installerKind: .dmg,
               installTrust: .publishedDigestOnly),
           ])
   }
   ```
   Wording can change, but keep these claims, and **no dated measurements in the comment**
   (`scripts/check_recipe_snapshots.py` fails dated observations. Those go in the audit doc).
   No `ChangelogRecipe`.

3. **Register it**: `AppRecipeIndex.swift`, insert `com_lokii_app.set,` between
   `com_local_claudestatusbar.set,` and `com_longbridge_app_desktop.set,` (currently lines 101–102).

4. **Update `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/DigestOnlyRecipeTests.swift`.**
   `everyDigestOnlyRuleIsADmgZipOrTarballOnTheStableChannel` asserts that the set of digest-only bundle ids
   **equals** `expected.keys`, so a new digest-only rule without an entry fails `make test`. Add:
   - to `expected`: `"com.lokii.app": [["Lokii-arm64.dmg", "Lokii-x86_64.dmg"]]` (the real asset list of
     every Lokii release; all three releases are identical, one entry is enough. Add a second identical row
     only if you want to show "every release has this shape");
   - to `picks` in `eachPatternPicksTheOneDmgForThisMac`: `"com.lokii.app": ["Lokii-arm64.dmg"]`;
   - fix the suite's doc comment ("The three rules this route was opened for…") so it no longer says
     three, and cite `docs/app-audits/com-lokii-app.md` for Lokii's asset names.
   Optionally add one `#expect` that with `preferring: .x86_64` the pattern picks `Lokii-x86_64.dmg`
   (`GitHubReleaseRule.installableAsset(from:matching:preferring:allowingIntelTranslation:)`). Keep it
   to that; don't add other tests.

5. **Goldens** (from the repo root, foreground):
   ```bash
   DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests   # fails on purpose
   swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests                               # must pass
   ```
   Expect exactly one new file `DuoUpdaterCore/Tests/RecipeGoldens/com-lokii-app.txt`, and no diff to other goldens.

6. **Verify detection on real packages** (red→green; baseline red was recorded above):
   ```bash
   swift run --package-path application-test --scratch-path "$SCR/swiftbuild" feed-discover "$SCR/v0.1.2-arm64/Lokii-arm64.dmg"
   swift run --package-path application-test --scratch-path "$SCR/swiftbuild" channel-verify "$SCR/v0.1.1-arm64/Lokii-arm64.dmg"  --expect stable
   swift run --package-path application-test --scratch-path "$SCR/swiftbuild" channel-verify "$SCR/v0.1.1-x86_64/Lokii-x86_64.dmg" --expect stable
   swift run --package-path application-test --scratch-path "$SCR/swiftbuild" channel-verify "$SCR/v0.1.2-arm64/Lokii-arm64.dmg"  --expect stable
   ```
   Expected: previous → `winning source GitHub`, `latest 0.1.2`, `status UPDATE → 0.1.2`, `download …/v0.1.2/Lokii-arm64.dmg`
   (on an arm64 host, for both previous dmgs); newest → `up to date`. Paste the raw lines, including the
   `changelog pane` line, into the audit doc's 如何复验 and Changelog sections. Planner's **unverified
   prediction** for that line: `raw inline notes` carrying the one boilerplate sentence (a bare paragraph
   yields no items in `GitHubMarkdownParser`, so `releaseNotesHTML` gets the raw body). Record whatever it
   actually prints.

7. **Audit doc** `docs/app-audits/com-lokii-app.md`, using the § Report template in
   `.claude/skills/app-audit/SKILL.md` **verbatim headings, including 「观测版本」**. Content is §1 of this plan:
   - 基本信息 (Team ID: 无, ad-hoc `flags=0x2(adhoc)`; 自更新机制: 自研, opens the browser only);
   - 覆盖矩阵 (§1.2) + 当前生效源 GitHub;
   - Channel 详情 (single channel; settled from source: `.github/workflows/release.yml`, `Lokii/Lokii/AppUpdater.swift` on `main`);
   - 更新检测 (version scheme settled from source; draft→publish atomicity; tap cask stale at 0.1.1 and not in the official catalog);
   - 按 OS 分轨 (`LSMinimumSystemVersion` 13.0 on all, no max, one build per arch);
   - 增量更新 (三栏: 无/无/不适用, with evidence);
   - Changelog: 来源 无. Why: all release bodies = `See the assets to download this version and install.` from
     `release.yml`'s `gh release create --notes`; no CHANGELOG file; the website has no notes. Paste the
     `changelog pane` line verbatim. Recipe 状态: 不需要 (a GitHub-releases ChangelogRecipe would only repeat the same sentence);
   - 一键安装: 状态 **digest-only（用户开启后）**; 端到端 **未跑** + reason (Boundaries B1/B2);
     格式 dmg (per-arch, thin); 校验: GitHub `digest` passed automatically (#1019) and is the whole proof on
     this route; table of 6 digests == `shasum`; **读的是**: 人人可手动下载的 GA; 常驻进程: 无;
     阻塞: none in code. Team-ID route impossible (no Team);
   - 已知问题: tap cask lag/Caskroom; app's own updater also announces the version (harmless, it never swaps);
     after a swap the running process keeps old code until restarted; **unverified**: whether a Full Disk
     Access grant survives an ad-hoc → ad-hoc swap (the app needs FDA; a new ad-hoc build has a new cdhash).
     Label it "未验证" and list it under 建议下一步 as a real-machine check. Don't state it as fact;
   - 如何复验: commands + raw outputs from steps 1 and 6;
   - 建议下一步: e2e by the orchestrator (B1); switch to the Team-ID route if upstream starts Developer ID signing (B4).
   Follow § Writing for a public repo: no `/Users/<name>` paths, no statement about what any machine has installed.

8. **README row** in `docs/app-audits/README.md`, section **`## Single-channel — GitHub Releases`** (after the diri row
   is fine), same shape as neighbours, e.g.:
   `- [x] [**Lokii**](com-lokii-app.md) · \`com.lokii.app\` — G (digest-only one-click per-arch dmg；ad-hoc 签名，无 Team ID) · 无 changelog（release 正文为固定句）· 真包 v0.1.2 挂载验证 ✓ · 一键端到端未跑 · <date>`
   No `CHANNEL_COVERAGE_TODO.md` change (no channel gap). Local-only docs (`docs/app-onboarding-status.md`): update only if present; never `git add -f`.

9. **Tests, foreground, judged by exit code.** `make test` = `test-scripts` + `test-swift` + `test-app`. It can
   exceed one 10-minute tool call, so run the three targets separately, each with an explicit timeout, and report each exit code:
   ```bash
   make test-scripts; echo "exit=$?"
   make test-swift;   echo "exit=$?"
   make test-app;     echo "exit=$?"
   ```
   If `check_app_audits.py` or `AppAuditCoverageTests` complains, fix the doc and README, not the checker.

10. **Commit** with `git commit -F <msgfile>` (message: what/why plus the verified lines, diri-style), no push.
    Expected diff: `Recipes/com-lokii-app.swift` (new), `Recipes/AppRecipeIndex.swift` (+1),
    `Tests/RecipeGoldens/com-lokii-app.txt` (new), `Tests/DuoUpdaterCoreTests/DigestOnlyRecipeTests.swift`,
    `docs/app-audits/com-lokii-app.md` (new), `docs/app-audits/README.md` (+1). Nothing else.

11. **Report**: the three counts (检测 ✓ with old→new channel-verify lines; 一键 digest-only, e2e 未跑 + why;
    Changelog ✗ vendor publishes none), exact newest/previous asset URLs
    (`https://github.com/huangy7/lokii/releases/download/v0.1.2/Lokii-arm64.dmg`, `…/v0.1.1/Lokii-arm64.dmg`, and the x86_64 twins),
    and the raw `channel-verify` output.

### Evidence on disk (planner's, read-only reuse is fine)
- `$SCR/dl/v0.1.{0,1,2}-{arm64,x86_64}/Lokii-*.dmg`: all six real assets, digests verified.
- `$SCR/releases.json`: full releases API dump. `$SCR/src/`: `release.yml`, `update-homebrew.yml`, `ci.yml`, `AppUpdater.swift`, `build.sh`, `project.yml`, `Info.plist`.
- `$SCR/lokii-src/`: full upstream clone (`git log --all`, tags v0.1.0–v0.1.2).

---

## 3. Boundaries

**B1. No end-to-end install by the executor.** Forbidden: `make install`, `make cli`, the `duo` CLI, `pkill`/`killall`,
`git stash`, `git push`, PRs/issues, writing to `/Applications` or `~/Applications`, launching/opening any download,
touching quarantine xattrs, and anything that shows system UI. The one-click e2e (coverage-discovery Phase 5) is for the
orchestrator/user, run serially. Until it runs, the audit says **一键：digest-only，端到端未跑** and the README row says the same.
"Supports one-click" must not be claimed on the strength of `channel-verify`/unit tests alone. Those never download or swap.

**B2. A real Lokii install exists on the planning machine** (`mdfind kMDItemCFBundleIdentifier == 'com.lokii.app'` hit
`/Applications/Lokii.app`, a 0.1.1 arm64 ad-hoc copy, not running). Phase 5's rule "mdfind must be empty: never overwrite a real install"
applies. Whoever runs the e2e must ask the user first (or use that copy only with explicit consent). Its e2e also needs
the user to turn on digest-only installs in DuoUpdater's Settings (`AllowDigestOnlyInstalls`). **Do not write that default
yourself**; it is a user trust decision. Don't mention this machine's install in the public audit doc.

**B3. Stays unverified until a real machine shows it** (write these as 未验证 in the doc, never as facts):
- digest-only one-click 0.1.1 → 0.1.2 actually completes (download → digest → gate 2 → plist id/version → swap), on arm64 and on Intel;
- the x86_64-under-Rosetta → arm64 cross-grade (kind C);
- whether the Full Disk Access grant (and the global hotkey) survives the ad-hoc swap. If FDA is lost, it's a 已知问题 for every
  update path including the vendor's manual one, not a reason to withhold one-click. But it must be measured before anyone writes it down as fact;
- the pre-rewrite 2026-10-02 v0.1.0 copies' bundle id (source says `com.lokii.app`; no bundle inspected).

**B4. Don't pre-empt a signing change.** If a future release carries a Team ID, the digest-only identity gate throws
`teamIdentifierAppeared` for ad-hoc installs (users update by hand once). Then the rule should move to the default
`.developerID` trust (and leave `DigestOnlyRecipeTests`). Record this in 建议下一步 only. Don't add conditional logic now.
If the newest release *already* has a Team ID when you run step 1, stop and report instead of following this plan.

**B5. No changelog machinery.** Don't add a `ChangelogRecipe`, don't scrape commit messages or the website, and don't add a
"suppress boilerplate body" option to `GitHubReleasesSource`/`GitHubMarkdownParser`. That would be a **Core change**: record
it in the audit's 已知问题 / 建议下一步 as a possible follow-up ("the pane shows the vendor's fixed sentence"); **don't make it**.

**B6. No other Core change.** Everything needed exists: `GitHubReleaseRule`, `.publishedDigestOnly`, arch-aware asset
selection (`HostArch.assetTokens` includes `arm64` / `x86_64`), the automatic GitHub digest check (#1019). Don't touch
`org-alacritty.swift`'s shared comment (it describes its own 2026-08-16 batch), `SourceStack`, `HomebrewCaskSource`
(tap support is out of scope), or `SignatureVerifier`.

**B7. Don't add** `hostRequirement` (13.0 floor is read from the bundle by gate 6), `listPageSize`, `usePrereleases`,
a beta/nightly rule (no such track), `versionIsBuild` (`CFBundleVersion` is always `1`), or a `ChannelBinding`. No extra
tests beyond the `DigestOnlyRecipeTests` update in step 4.

**B8. Surgical edits only.** Don't reformat or reorder untouched lines in `AppRecipeIndex.swift`, the README, or the test file.
