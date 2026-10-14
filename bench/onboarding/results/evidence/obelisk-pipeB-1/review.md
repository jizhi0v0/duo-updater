# Obelisk onboarding review (`2c49ab0..d0f246f`)

I found one blocking problem: a changelog defect that a one-line change fixes. Everything else is correct. The recipe, the GitHub rule, the one-click decisions and the audit doc all hold up against the code and the real packages.

## Findings

### 1. BLOCKING: the changelog lists download filenames as change items in the 0.2.0, 0.2.1 and 0.2.2 entries

**Evidence.** I ran the production decoder on today's live release bodies (`gh api repos/tommy0103/obelisk/releases?per_page=40`). The harness lives in my scratchpad and calls `StructuredChangelogDecoder.decode(body, format: .gitHubReleases, channel: nil, maxEntries: 20)`. The `## Downloads` bullet lists come through as change items:

```
=== 0.2.2 items=51   … `Obelisk-0.2.2-mac-arm64.dmg` / `Obelisk-0.2.2-mac-arm64.zip` / `Obelisk-0.2.2-linux-amd64.deb`
=== 0.2.1 items=26   … `Obelisk-0.2.1-mac-arm64.dmg` / `Obelisk-0.2.1-linux-amd64.deb`
=== 0.2.0 items=29   … `Obelisk-0.2.0-mac-arm64.dmg` / `Obelisk-0.2.0-linux-amd64.deb`
```

- The `Downloads` heading itself is dropped, so these filenames read as part of the section above them.
- The 0.2.2 zip they list was never published as an asset.
- A user on 0.1.0 sees all three of these entries.
- With `skipSections: ["Downloads"]` the counts drop to 48, 24 and 27. 0.2.4 and 0.2.5 stay at 95 and 28, and `Included work` is kept.
- The other install headings produce no items, because their bodies are only code blocks and prose. That covers `Installation`, `Install the Linux package`, `Install or update the CLI`, `Install the CLI`, `macOS installation` and the H1 `# App — download .dmg…`. So they don't need skipping.

**What went wrong.** The plan made `skipSections` depend on the measured pane. The executor only looked at the newest entry and recorded the older ones as 「未验证」 (unverified). That was cheap to measure, and it is wrong in the shipped output.

**Fix.**
- Add `skipSections: ["Downloads"]` to the `ChangelogRecipe` in `com-obelisk-app.swift`.
- Re-record `RecipeGoldens/com-obelisk-app.txt`.
- In the audit doc's Changelog section, replace the 「未验证」 paragraph with the measured result: only `Downloads` yields items, and the other install headings yield none. Remove 建议下一步 #2 (the next-steps item that says to check this).

### 2. NOTE: `make test` did not exit 0, but the cause is the machine, not this diff

- `../scr/make-test.log` stops at `scripts/test_app_test_coverage.py`. It raises `TypeError: unsupported operand type(s) for |`, because `/usr/bin/python3` is 3.9.6 and that script needs 3.10 or newer.
- The diff touches no scripts, so the same failure happens on `main` without this change.
- The executor ran the pieces separately. Core: 4237 tests passed. CLI: 391 passed. `RecipeGoldenTests` and `check_app_audits` passed.
- I re-ran every Python step after the failure point with `/opt/homebrew/bin/python3.14`. All were green except `check_localizable_keys`, which fails only because `App/DuoUpdater.xcodeproj` is missing (needs xcodegen).
- `scripts/app-tests.sh` (xcodebuild over `App/Sources`) never ran. The diff doesn't touch App.
- **Fix:** none needed for the onboarding. The report should say `make test` exited 1 for an environment reason, not imply a clean run.

### 3. NOTE: the commit is on `main`, not a branch

`git branch --contains HEAD` shows only `* main`. The plan said to `git switch -c recipe/obelisk`. **Fix:** move the commit to a branch before it is integrated.

### 4. NOTE: the doc leaves out 0.2.4 x64 among the builds it checked for one-click

The doc's 一键安装 (one-click) section lists only 0.2.4 arm64, 0.2.5 arm64 and 0.2.5 x64. I unpacked `Obelisk-0.2.4-mac-x64.zip` and checked it:

- `Identifier=com.obelisk.app`, `TeamIdentifier=433DLLA855`, hardened runtime flag set
- `codesign --verify --deep --strict` exit 0
- `SUFeedURL …/appcast-x64.xml`, same `SUPublicEDKey`, `x86_64`

So the Intel 0.2.4 → 0.2.5 update lines up on paper too. **Fix:** add 0.2.4 x64 to that list.

### 5. NOTE: the doc doesn't mention copies built from source (plan §1.5)

**Fix:** add one line. Builds from 0.2.4+ source get `SUFeedURL` from `beforePack`, so Sparkle detects them. Builds from older source fall under the GitHub rule. One-click is refused either way, because the installed copy has no Team ID.

## Checks that passed

- **Source order.** `SourceStack.make` runs `SparkleAppcastSource` before `GitHubReleasesSource`, so the new rule only decides for copies without `SUFeedURL`. The executor's `channel-verify` log matches the doc exactly: GitHub wins for 0.1.0 and 0.2.2; Sparkle wins for 0.2.4 and for 0.2.5 on both architectures.
- **No OS-floor field.** `GitHubReleaseRule` really has no OS-floor field (I listed its properties), so recording the gap for macOS 11 users of 0.1.0–0.2.1 is right.
- **Prereleases and drafts.** `decodeGitHubReleases` drops both when `channel == nil`. All 6 releases are `prerelease=false`, and the tags are only `v0.1.0`…`v0.2.5` plus `v0.2.3`, which has a tag but no release.
- **One-click refusal for old copies.** `SignatureVerifier.swift:359` throws `noTeamIdentifier("installed")`, and `:191` returns `.teamAppeared` when the download has a Team ID. Leaving `installAssetPattern` empty is correct.
- **npm CLI.** `npm view @obelisk-apps/cli` returns no `repository`; dist-tags are `latest 0.3.0`, `rc 0.2.6-rc.0`. The doc's claim holds. The CLI's versions have also split from the desktop tags, so mapping its notes to them would be wrong anyway.
- **README.** The row sits under `## Single-channel — GitHub Releases` (line 203), with no `— S` marker.
- **Baseline.** `verify/baseline.json` is regenerated by a bot, so leaving it alone is correct.

## Plan coverage checklist

| Plan item | Result | Agree? |
|---|---|---|
| **1.1** 0.2.4+ signing (Team 433DLLA855, notarized) | Covered. The doc leaves out 0.2.4 x64, which I verified (finding 4) | Yes |
| 1.1 resident helper: none | Covered | Yes |
| 1.1 detection via generic Sparkle, no recipe or `sparkleFeeds` entry | Covered: `declared`; 0.2.4 → 0.2.5 shows an update; 0.2.5 up to date on both architectures | Yes |
| 1.1 reads the public GA build at `/releases/latest` | Covered | Yes |
| 1.1 OS floor (`minimumSystemVersion` 12.0 filtered by Sparkle) | Covered | Yes |
| 1.1 one-click via Sparkle, end-to-end not run | Covered and correctly marked 「需要验证 / 未跑」 (needs verification / not run). Never shown as ✓ | Yes |
| 1.1 changelog via `.gitHubReleases` recipe | Covered, but the optional `skipSections` decision was left unmeasured and is needed (finding 1) | Partly |
| **1.2** 0.1.0–0.2.2 signing (ad-hoc, linker-signed) | Covered | Yes |
| 1.2 resident helper: none | Covered | Yes |
| 1.2 detection-only `GitHubReleaseRule` with anchored pattern | Covered. `channel-verify` was run on 0.1.0 and 0.2.2 only, not 0.2.0 or 0.2.1; same shape, low risk | Yes |
| 1.2 expected download `<nil>` | Covered differently: shows the releases page URL. Harmless; the plan's expectation was just inexact | Yes |
| 1.2 one-click refused (Team gate and digest-only) | Covered, and confirmed in the code | Yes |
| 1.2 changelog shared with 1.1 | Covered, with finding 1. The old entries are exactly what 0.1.0 users see | Partly |
| 1.2 OS-floor gap recorded, no Core change | Covered in 已知问题 (known issues) | Yes |
| **1.3** v0.2.3 has a tag but no release | Covered in one line | Yes |
| **1.4** stable is the only track; anchored pattern refuses rc; a future rc needs its own audit | Covered | Yes |
| **1.5** source and dev builds | Missing (finding 5) | Should add |
| **1.6** electron-updater fallback is not a separate install | Covered in the 自更新机制 (self-update) line | Yes |
| **1.7** npm CLI out of scope | Covered in 已知问题 | Yes |
| **1.8** delta, staged rollout, per-arch/OS, competing updater, in three columns | Covered | Yes |

**Omissions sweep.** I found no missed editions, channels, distribution routes or one-click routes:

- There is no Homebrew cask and no Mac App Store listing.
- There has never been a universal build.
- The pre-0.2.4 builds are arm64-only, so no Intel copy predates Sparkle.
- The digest-only route cannot apply to the old copies, because the download has a Team ID and the installed copy doesn't.
