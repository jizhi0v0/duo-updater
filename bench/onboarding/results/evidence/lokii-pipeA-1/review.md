# Lokii onboarding review (`7bccb0b..7e6ed0e`)

The rule itself is correct, and I found nothing wrong in the code. Two things must be fixed before this ships, both in text rather than logic: the Settings opt-in copy, and an undocumented Full Disk Access problem. There are three smaller notes.

**What I checked and found correct:**
- **Packages:** I downloaded all six dmgs (v0.1.0, v0.1.1 and v0.1.2, each arm64 and x86_64). Every `shasum -a 256` equals the GitHub `digest`. Each one is `com.lokii.app`, signed identifier `com.lokii.app`, `flags=0x2(adhoc)`, no Team ID, and passes `codesign --verify --deep --strict` (exit 0). Short version equals the tag, `CFBundleVersion=1`, `LSMinimumSystemVersion=13.0`, single-arch, and no nested apps. That satisfies every check in `SignatureVerifier.verifyDigestOnlyIdentity`.
- **Rule:** the pattern `^Lokii-(?:arm64|x86_64)\.dmg$` and `/releases/latest` are right. All three releases are `prerelease:false` and there is no beta track. The vendor's homepage download buttons point at the same GitHub assets. The app's own `AppUpdater.swift` only opens a browser, so it can't race duo.
- **Tests:** the targeted suites passed (26 tests in 5 suites). The full `swift test --package-path DuoUpdaterCore` passed (4563 tests in 383 suites, exit 0). The six Python gates pass under 3.14 (`check_app_audits`, `check_recipe_snapshots`, `check_prose_claims`, `check_offpool`, `check_skill_docs`, `check_engine_notes`). I did not run `make test-app` or the CLI build.
- The repo is still clean, and no dmg is left mounted.

---

### 1. BLOCKING: the Settings opt-in copy names a closed list of apps that leaves out Lokii
- **Evidence:** `App/Sources/Settings/GeneralSettingsPage.swift:144`, the `info:` text on the "Allow one-click updates for apps without a developer signature" switch, reads: *"For apps whose GitHub releases are only ad-hoc signed: Alacritty, Flameshot and darktable."* That string is also in `App/Resources/Localizable.xcstrings`. This switch lowers the install trust level, and its copy tells the user exactly which apps it affects. Once this commit lands, turning it on also covers Lokii, and the text doesn't say so. No test ties this list to `GitHubReleaseRegistry`, which is why nothing failed.
- The shared rationale this recipe points to has the same staleness: `Recipes/org-alacritty.swift:20` says *"Three of them — Alacritty, Flameshot, darktable"*.
- **Fix:** add Lokii to the string and to every translation in `Localizable.xcstrings`. Alternatively, reword it to "such as …" the way `CHANGELOG.md` 0.5.0 does, so it stops being a closed list. Then update the count and list in `org-alacritty.swift`.

### 2. BLOCKING: every one-click update will lose Lokii's Full Disk Access, and the audit doesn't say so
- **Evidence I verified:**
  - Lokii needs Full Disk Access. `AppDelegate.swift` calls `checkAndPromptFDA()` and gates on `engine.hasFullDiskAccess`. `FDAGuideWindowController.swift:87` opens `…PrivacySecurity.extension?Privacy_AllFiles`.
  - The ad-hoc designated requirement is a bare cdhash, and it changes every release:
    - v0.1.1 arm64: `designated => cdhash H"beb55af7…"`
    - v0.1.2 arm64: `designated => cdhash H"6a0fd887…"`
- **Documented consequence:** Apple DTS says macOS identifies code by its designated requirement, and ad-hoc code has no stable one. So version N+1 isn't treated as the same code as version N, and privacy grants don't carry over. duo's own Settings detail text already warns about this in general terms.
- **Not verified on a machine:** what Lokii does after a duo swap. My inference is that a file-search app without Full Disk Access silently indexes much less until the user grants it again.
- The audit does the opposite. 一键安装 lists only the Gatekeeper first-launch question, and 已知问题 says nothing about privacy permissions.
- **Fix:**
  - In `docs/app-audits/com-lokii-app.md` 一键安装 and 已知问题, state that each one-click update invalidates the Full Disk Access grant because the designated requirement is a cdhash, and that the user must grant it again.
  - Add the same caveat to the README index line.
  - Extend 建议下一步 1 so the end-to-end round also checks whether Full Disk Access survives 0.1.1 → 0.1.2. That round was not run.

### 3. NOTE: the vendor's own Homebrew tap is missing from the audit
- **Evidence:**
  - `.github/workflows/update-homebrew.yml` maintains `huangy7/homebrew-tap/Casks/lokii.rb`. That cask is `version "0.1.1"`, with per-arch URLs, no `auto_updates`, and the same `com.lokii.app` zap paths. It has had one commit, on 2026-10-07.
  - The tap's update workflow has never run: the repo's Actions history has no "Update Homebrew Cask" runs. That's why the cask is stuck on 0.1.1 while the latest release is 0.1.2.
  - `brew info --cask lokii` returns "No Cask with this name exists". So there is no main-repo cask, and `HomebrewCaskCatalog` (which reads `formulae.brew.sh/api/cask.json`) never sees this one.
- **Consequence:** GitHub answers for a copy installed from the tap, and duo replaces it. The Caskroom then still records 0.1.1, so the next tap bump makes `brew upgrade` reinstall the same version.
- The matrix's Homebrew cell is just "—" with no reason. Precedent: `com-tinycast-app.md` and `com-supercmd-SuperCmd.md`.
- **Fix:** change the cell to `—（第三方 tap \`huangy7/tap/lokii\`，主 cask 库无收录）`, name the tap in 基本信息, and add the Caskroom drift to 已知问题.

### 4. NOTE: v0.1.0 was left out, and the test comment overstates its coverage
- **Evidence:**
  - The doc says "0.1.0 另有 release，未下载".
  - `DigestOnlyRecipeTests` says it covers "every stable release with a digest", but its `com.lokii.app` entry lists only v0.1.2 and v0.1.1.
  - v0.1.0 has digests too, and I checked both of its dmgs:
    - Digests match: arm64 `2d548bf6…`, x86_64 `483685fd…`.
    - Same identity as the other two releases: `com.lokii.app`, version 0.1.0, ad-hoc with signed identifier `com.lokii.app`, seal verifies, no Team ID.
    - So a v0.1.0 copy passes the digest-only gates too.
- **Fix:**
  - Add v0.1.0's `["Lokii-arm64.dmg", "Lokii-x86_64.dmg"]` to `expected`, with a third `"Lokii-arm64.dmg"` in `picks`.
  - Record the v0.1.0 package in the audit.
  - Change "上一版 Team" to cover both earlier releases.

### 5. NOTE: one sentence in the recipe comment is unverifiable
- **Evidence:** `com-lokii-app.swift` says the repo's signing secrets are absent: "…when the repo has the secrets, and it has none". Repository secrets aren't public. What I can observe is that every published build is ad-hoc.
- **Fix:** reword it to "the published builds were made without them (all ad-hoc)".

**Not a finding:** the changelog verdict is accurate. Every release body is the CI's fixed `--notes` sentence. `skipSections` only drops headings, so the code base has no way to strip a body with no heading, and the doc already quotes what the changelog pane will show.

**Sources:**
- [Apple Developer Forums 795739 (DTS): ad-hoc signatures lack a stable designated requirement, so permissions are lost after an update](https://developer.apple.com/forums/thread/795739). I only saw the search snippet; I didn't open the thread.
- [Apple Developer Forums 785384: changed designated requirements break existing permission grants](https://developer.apple.com/forums/thread/785384)
- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). The page body didn't load through the fetcher, so I didn't quote from it.
