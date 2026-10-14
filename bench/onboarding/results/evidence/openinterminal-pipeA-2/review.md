I found one blocking problem and four notes. The parts that were built work: the rule, tests and audit doc are correct for the main app, and every check I ran passed:
- `swift test --package-path DuoUpdaterCore --filter OpenInTerminal`: 3/3 passed.
- The filter covering `RecipeGoldenTests` and `AppRecipeIndex`: 53/53 passed.
- `python3 scripts/check_app_audits.py`: rc=0.

The blocking problem is that two apps shipped from the same repo were left out.

---

### 1. BLOCKING — OpenInTerminal-Lite and OpenInEditor-Lite are not covered, though the code base already supports them
The audit skips them: 「本次没有下载、没有核对其 bundle id」. Both are full apps with their own bundle ids, released from this same repo, and each has a Homebrew cask. Only brew-installed copies of the Lite apps get detected. Downloaded copies get nothing, and no Lite copy gets one-click.

What I measured (I downloaded the zips into `scr/review` and only read them; nothing was launched):

| asset | bundle id | short / build | Team | other |
|---|---|---|---|---|
| v1.2.8 `OpenInTerminal-Lite.zip` | `wang.jianing.app.OpenInTerminal-Lite` | 1.2.8 / 1 | C8VX3ZLX5U, stapled | universal, no `SUFeedURL`, min 10.13, `codesign --verify --deep --strict` OK |
| v1.2.8 `OpenInEditor-Lite.zip` | `wang.jianing.app.OpenInEditor-Lite` | 1.2.8 / 1 | C8VX3ZLX5U, stapled | same |
| v1.2.7 `OpenInTerminal-Lite.zip` | same as above | 1.2.7 / 1 | **Q33U8R4U57** | the same Team change as the main app |

- **Homebrew:** `brew info --cask openinterminal-lite` and `openineditor-lite` show 1.2.8, a URL on `releases/download/v1.2.8/…`, and no `auto_updates`.
- **Vendor's release guide** (`.claude/skills/release/SKILL.md` on `master`) says outright: "This repo ships three apps… both Lite apps ride together in the Lite release", with tag `vA.B.C`.
- **Why it already works:** `/releases/latest` is the main release (v2.3.9), which has no Lite asset. `settle` then falls back to the release list and keeps only stable releases (`GitHubReleasesSource.swift:1302-1318`). The walk skips v2.3.9 because the asset is missing, and lands on v1.2.8 (`:1344`). Releases alternate main/Lite, so the walk never comes near `maxReleasesWithoutMacOSAsset = 5`.

**Fix:**
- In `wang-jianing-app-OpenInTerminal.swift`, add two more `GitHubReleaseRule`s:
  - `bundleID: "wang.jianing.app.OpenInTerminal-Lite"` with `installAssetPattern: #"^OpenInTerminal-Lite\.zip$"#`
  - `"wang.jianing.app.OpenInEditor-Lite"` with `#"^OpenInEditor-Lite\.zip$"#`
  - Both: `installerKind: .zip`, plus a version pattern limited to the Lite line (see note 3).
- Re-record the goldens.
- Extend the test: pin both asset names, and check that `OpenInTerminal.zip` is not accepted by a Lite rule.
- Add Lite rows to the audit doc (same family, same doc), including the measurements above and the 1.2.7→1.2.8 Team change.
- Budget note for the doc: every Lite check always costs a `/latest` call plus a list call.

### 2. NOTE — the main safety argument is not exercised by a test
The rule's comment and test doc say the asset pattern is what keeps `/releases/latest` from answering when a Lite release holds the Latest badge. But `OpenInTerminalGitHubRuleTests` only checks the asset name via `carriesInstallableAsset`. The doc itself admits the path was 「未在 Lite 恰好是 Latest 的状态下实测」. Reading the code, the fallback does work, but nothing pins it.

**Fix:** add a fixture test using the URLProtocol pattern from `UTMGitHubChannelTests.swift:16`:
- Serve `/repos/Ji4n1ng/OpenInTerminal/releases/latest` as the real v1.2.8 Lite object.
- Serve the list as `[v2.3.9, v1.2.8, v2.3.8, v1.2.7]` with their real asset names.
- Expect `latestVersion` to return `2.3.9`, with `downloadURL` ending `v2.3.9/OpenInTerminal.zip`.
- If note 1 is fixed, add the same check for each Lite rule, expecting `1.2.8`.

### 3. NOTE — release history picks up the other app's tags whenever the list fallback runs
`settle` builds `history` from every release whose tag matches `versionPattern`, and ignores the asset filter (`GitHubReleasesSource.swift:1330-1336`). Lite tags (`v1.2.8`…) match the main pattern `^v([0-9]+(?:\.[0-9]+)+)$`.
- **Main rule:** whenever a Lite release is Latest, the main app's timeline gains phantom "OpenInTerminal 1.2.x" entries. This is temporary but real.
- **Lite rules (note 1):** they always take the fallback, so with an unanchored pattern their timeline would permanently include main-app 2.3.x entries.

**Fix:**
- Anchor the Lite rules to their line, e.g. `^v(1\.[0-9]+\.[0-9]+)$`, and say in the comment that the vendor would have to rename tags if Lite ever reaches 2.x.
- For the main rule, at least document this in the audit's 注意事项.
- The proper fix is to filter `history` by `installAssetPattern`. That is a change to shared code and should be its own change, with approval.

### 4. NOTE — some 2.3.9 copies are ad-hoc signed; the audit says every 2.3.9 copy is fine
The vendor's release guide records: "v2.3.9/v1.2.8 first shipped ad-hoc and were rejected in PR #274726; re-uploading notarized builds made CI pass". The API timestamps agree:
- The v2.3.9 release was published at `2026-07-13T12:08:34Z`.
- The current `OpenInTerminal.zip` was `created_at 2026-07-14T13:41:08Z`.
- The Lite zips were created at `2026-07-14T13:47:54Z`.

So for about 25 hours, `v2.3.9/OpenInTerminal.zip` was a different, ad-hoc build. A copy downloaded in that window reports 2.3.9 but has no TeamIdentifier. Its next one-click update will fail at `SignatureVerifier.swift:222` with `noTeamIdentifier(which: "installed")`. That contradicts the doc's 「2.3.9 之后的版本（同 Team）不受影响」. Detection is not affected.

**Fix:** in 一键安装 / 已知问题, add the ad-hoc window, cite the release guide and these timestamps, and give the failure text. Also replace 「换 Team 的原因仓库里没说」 with what the repo does say: signing and notarization were reworked for this release.

### 5. NOTE — the 常驻进程 section leaves out the Finder Sync extension
The section covers only the main app and `OpenInTerminalHelper`. The bundle also ships `wang.jianing.app.OpenInTerminal.OpenInTerminalFinderExtension`; it appears in the cask's `zap` list. Finder hosts this extension, and it is the part most likely to be running during an in-place swap.

**Fix:** list it in the doc. If the end-to-end run in the doc's 建议下一步 happens, record whether Finder picks up the new extension after the swap. I haven't checked this; it is my guess at a gap, not a confirmed failure.

---

**Claims I checked that hold up:**
- **Team gate:** `SignatureVerifier.verifyTeamIdentifierMatch` (`:218-233`) has no exception for a vendor changing Team, so refusing one-click for 2.3.8→2.3.9 is the correct reading and no available route was skipped.
- **Mac App Store:** the iTunes search API returns no OpenInTerminal listing.
- **Source order:** Homebrew runs before GitHub in `SourceStack.swift:37/41`.
- **Prereleases:** none of the 40 most recent releases is a prerelease.
- **Old tags:** pre-2021 tags have no `v` prefix (`2.2.3`, `1.1.5`). The pattern excludes them, but they are older than anything that would be offered, so detection is unaffected.
