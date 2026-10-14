# Review: Secretive onboarding (`57e6ce0..7b6307a`)

One blocking problem: a copy built by Secretive's nightly workflow gets offered stable 4.0.0, with a working one-click download. Three other notes. Tag pattern, asset choice, Team ID, universal zip handling and the `/releases/latest` reasoning all hold.

**What I ran:**
- `python3 -I scripts/check_app_audits.py` → `✓ app audits consistent — 215 docs…`, rc=0.
- `swift test --package-path DuoUpdaterCore` → `3777 tests in 321 suites passed … with 1 known issue` (an EventStore schema-drift test, not this change). The `RecipeGoldenTests` filter also passed.
- My attempt to download a real nightly build was declined. So the nightly finding was tested on a stand-in bundle, as described below.

---

### 1. BLOCKING — A nightly channel exists. It reads as stable, so a nightly copy is offered and one-click installs 4.0.0

The audit and the recipe comment say the nightly workflow "only uploads a CI artifact … 没有可下载的 nightly 包". That is wrong.

**Evidence:**
- **Nightly builds are real, signed and downloadable.** The vendor's `.github/workflows/nightly.yml` (daily) and `oneoff.yml` both run `signing.sh`, build the Release scheme with the same base bundle ID (`Config.xcconfig`: default `com.maxgoedjen.Secretive`, Team `Z72PRUAWF6`), and notarize the result with `notarytool submit`. The build is uploaded as an Actions artifact, which any signed-in GitHub user can download. The 2026-10-14 nightly run 38533092908 has artifact `Secretive`, 22,834,452 bytes, kept until 2027-01-12.
- **Version string:** the workflow sets `GITHUB_CI_VERSION` to `0.0.0_nightly-$DATE` (`0.0.0_oneoff-$DATE` for one-off builds). `Info.plist` puts `$(CI_VERSION)` into `CFBundleShortVersionString`.
- **Why it reads as stable:** `ReleaseChannel.detect`'s version-tail rule is `[0-9]+(\.[0-9]+)+(-[0-9]+)*-nightly(-[0-9]+)*`. It needs a dash before `nightly`, and Secretive uses an underscore, so nothing matches.
- **Stand-in test:** I made a bundle in the scratchpad with only an `Info.plist` copying those values (`com.maxgoedjen.Secretive.Host`, `0.0.0_nightly-2026-10-14`) and ran it through `channel-verify`:
  ```
  inferred        stable
  detected channel  → stable
  ✗ MISMATCH: expected channel 'nightly'
  winning source  GitHub
  download        https://github.com/maxgoedjen/secretive/releases/download/v4.0.0/Secretive.zip
  status          UPDATE → 4.0.0
  ```
  This is a stand-in, not the real nightly bundle; the version string comes from the workflow source.
- **Effect:** a build from `main`, newer in code than 4.0.0, is offered 4.0.0. Same Team ID and bundle ID, so every install gate passes. This is the cross-channel push that safety rule 5 forbids and that the DB Browser and Freelens nightly rules exist to prevent. (Secretive's own updater also offers 4.0.0 to nightly builds, because it reads `0.0.0`. That lowers the harm but doesn't fit this repo's rule.)

**Fix:**
1. Add a detection rule scoped to `com.maxgoedjen.Secretive.Host`, alongside the Little Snitch step 0.7 rule:
   - `^[0-9.]+_nightly-` → `.nightly`
   - `_oneoff-` → a non-stable channel
   - Add `ReleaseChannelTests` cases for both strings, and one asserting `4.0.0` stays stable.
   - Alternatively, widen `versionTailPattern`'s separator to `[-_]`, but only after replaying `verify/baseline.json` as that rule's comment requires.
2. In the audit doc, the Channel table should get a `nightly` row: same bundle ID, version-string signal, no release feed, so detection-only or blocked with no one-click. Also update `CHANNEL_COVERAGE_TODO.md`, the recipe comment and the commit message text.

### 2. NOTE — One-click leaves the old SecretAgent running, and the audit doesn't mention it

- **Evidence (vendor source):**
  - `Sources/Secretive/App.swift` restarts the agent only when the host app becomes active, with the comment *"Relaunch the agent, since it'll be running from earlier update still"*.
  - `AgentStatusChecker.swift` registers SecretAgent through `SMAppService.loginItem`.
  - `FAQ.md`: "`SecretAgent` may continue running until you quit it or reboot."
- **On the duo-updater side:** the install quits and relaunches instances of the host bundle ID only (`AppRestarter.runningInstances(of:)`). `hasProcesses(insideBundle:)` is used only on the staged-relaunch path in `AppListModel.swift:6160`.
- **Likely result:** after a one-click update, the SSH agent keeps running 3.0.4 code (4.0.0 includes "Fix SSH ECDSA signature mpint encoding") until the user opens Secretive. Meanwhile the row shows up to date. I did not trace whether the post-install restart check sees the login-item process; treat that part as unverified.
- **Fix:**
  - Add this to 「一键安装」/「已知问题」.
  - The end-to-end run the audit defers should check the SecretAgent path, start time and version after install (e.g. `ps -axo pid,lstart,comm | grep SecretAgent`).
  - Ask the user whether one-click should end with "open Secretive once" guidance.

### 3. NOTE — The OS-floor ladder is incomplete, and the Homebrew claim is wrong below macOS 15

- **Evidence:**
  - Minimum macOS stated in the release bodies:

    | Release | Minimum macOS |
    |---|---|
    | v4.0.0 | 15.0.0 |
    | v3.0.0 / v3.0.4 | 14.0.0 |
    | v2.4.1 | 12.0.0 |
    | v2.3.1 / v2.2.0 | 11.0.0 |

  - The Homebrew cask (`homebrew-cask/Casks/s/secretive.rb`) pins a version per macOS: sequoia+ → 4.0.0, sonoma → 3.0.4, monterey/ventura → 2.4.1, big_sur and older → 2.3.1.
  - `HomebrewCaskSource` reports the cask's top-level `version` (4.0.0). Nothing under `DuoUpdaterCore/Sources` reads `variations`.
- **Where the audit falls short:** it says "cask 版本 `4.0.0` 与 GitHub 一致" and lists only the 14→15 step. In practice, copies on macOS 11–14 get a lasting "4.0.0" prompt from both sources:
  - GitHub copies: Gate 6 refuses after the 22 MB download.
  - Brew copies: a `brew upgrade` that brew itself won't carry out.
- **Fix:** put the full ladder into 「按 OS 分轨」 and 「已知问题」 for both sources. File the cask-`variations` gap as an engine issue.

### 4. NOTE — "Reading the body's minimum macOS needs an engine change" overstates it

`VendorProbeRecipe.minimumSystemVersionPattern` already exists (`VendorProbeSource.swift:855`). It turns a too-new release into an amber "vendor refused this macOS" mark instead of a false update. GitHub currently answers before VendorProbe, so using it would mean replacing the GitHub rule with a VendorProbe recipe on `api.github.com/repos/maxgoedjen/secretive/releases/latest`, with a pattern like `Minimum macOS Version(?:\\r)?\\n([0-9.]+)`. There is no existing recipe that probes `api.github.com` for versions, so this is a trade-off for the user to decide, not something to just do.

**Fix:** reword 建议下一步 #2 to name this existing route and ask the user, instead of calling it an engine change.
