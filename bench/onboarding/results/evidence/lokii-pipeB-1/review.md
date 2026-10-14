I found **no BLOCKING issues** in the Lokii onboarding. The rule, trust class, asset pattern, tests and docs are correct, and the planner's checklist is fully covered. I have four NOTEs, all for the audit doc or tests.

**What I checked myself:**
- **Upstream unchanged:** `/releases/latest` is still v0.1.2. All three releases (v0.1.0, v0.1.1, v0.1.2) are not prereleases, each has the same two assets, and the digests match the doc.
- **Vendor's claims hold** (`release.yml`, `build.sh`): the tag must equal the Cargo version, the release is created as a draft and then published with `--latest`, and the notes are a fixed sentence.
- **Packages:** I mounted the real v0.1.1 and v0.1.2 arm64 dmgs read-only. Both have identifier `com.lokii.app`, `flags=0x2(adhoc)` and no Team ID.
- **Core code paths** (`SignatureVerifier.verifyDigestOnlyIdentity`, `GitHubReleaseRule.installableAsset`, `GitHubReleasesSource`, `HomebrewCaskSource`): the doc and the recipe comment describe them correctly.
- **Homebrew:** the official cask catalog (7,782 casks) has nothing named Lokii, and the author's tap cask is still at 0.1.1.
- **Tests:** `swift test --filter 'DigestOnlyRecipeTests|GitHubAssetSelectionTests|RecipeGoldenTests|AppAuditCoverage'` passed 24 tests in 4 suites, exit 0. `check_app_audits.py` and `check_recipe_snapshots.py` both passed. The executor's `make-test.log` shows the full suite green: 4,561 tests, then 396 tests, then 156 app tests. Its first run had failed on Python 3.9 and was re-run.
- The working tree is clean; I made no edits.

## Findings

**NOTE 1: the "Full Disk Access may be lost" item is stronger than "未验证" (unverified).** Both releases use a designated requirement built from the build's own hash, and that hash differs between them:
- 0.1.1: `designated => cdhash H"beb55af78b167990b24d7b1431d573e075bfeb88"`
- 0.1.2: `designated => cdhash H"6a0fd887ae138cf4135076f379ec260f0ca4fbef"`

An Apple engineer on the developer forums says macOS uses the designated requirement to decide whether a new build is the same app for privacy permissions, and that ad-hoc signed code has no stable one. So the new build is expected to look like a different app, and Full Disk Access is expected to be lost on every update. That applies to the vendor's own drag-install too.
- **Fix:** in 已知问题, record both requirement lines and the forum source. Rephrase as "expected to be lost (static evidence); still to be confirmed on a real machine". Keep the real-machine check in 建议下一步 #1.

**NOTE 2: the global-hotkey item can be answered from source.** The hotkey uses Carbon `RegisterEventHotKey` (`Lokii/Lokii/KeyboardShortcuts/CarbonKeyboardShortcuts.swift:137`). The source has no `AXIsProcessTrusted`, no `CGEvent` tap and no global event monitor. So no privacy permission is involved for an update to drop.
- **Caveat:** that Carbon hotkeys need no permission is not stated by Apple; it comes from community reports.
- **Fix:** drop "全局快捷键" from that 未验证 item and from 建议下一步 #1. If you want, note "hotkey via Carbon, no permission involved (from source)".

**NOTE 3: the digest table has 4 rows; the plan asked for all 6.** The doc leaves out v0.1.0, which is still a published release and an old version the rule can update from. The digests are `arm64 sha256:2d548bf6…2924` and `x86_64 sha256:483685fd…856a`, both matching the planner's downloads.
- **Fix:** add both rows to the 一键安装 → 校验 table, or say why the table stops at v0.1.1.

**NOTE 4 (minor): the tests check the arm64 pick only.** The `DigestOnlyRecipeTests` Lokii row picks with `preferring: .arm64`. Nothing checks that an Intel Mac gets `Lokii-x86_64.dmg`. The plan allowed this as optional and the existing order test partly covers it, so this is not a gap in safety. Also, 建议下一步 #2 says "改回" (change back) to `.developerID`, but the rule was never `.developerID`.
- **Fix (optional):** add one check that `preferring: .x86_64, allowingIntelTranslation: false` picks `Lokii-x86_64.dmg`, and change "改回" to "改为".

## The planner's checklist

| Item | Result | Agree? |
|---|---|---|
| **A.** arm64 copy (any of 0.1.0–0.1.2) | **Covered.** v0.1.1 arm64 → `UPDATE → 0.1.2`, downloading `…/v0.1.2/Lokii-arm64.dmg`; v0.1.2 is up to date | Yes |
| **B.** x86_64 copy on an Intel Mac | **Covered in code** (arch selection). Not tested on an Intel host or by an x86_64-preference unit test (NOTE 4) | Yes, with NOTE 4 |
| **C.** x86_64 copy under Rosetta | **Covered statically.** Running channel-verify on the v0.1.1 x86_64 dmg on an arm64 host offers the arm64 dmg, and the architecture gate only refuses dropping an arm64 slice. Listed as 未验证 for a real swap | Yes |
| **D.** Copies of the deleted first v0.1.0 | **Covered as 未验证.** Source says `com.lokii.app`; no real package was available | Yes |
| **E.** Copies installed from the author's tap | **Covered.** The Homebrew source only reads the official catalog, so these fall through to the GitHub rule; Caskroom lag is in 已知问题. I re-checked both facts | Yes |
| **F.** Locally built copy | **Left out silently.** The plan itself said "not a target" | Yes, nothing to do |
| beta / nightly / RC | **Out of scope, with reason:** none exist (no prerelease ever, CI uploads nothing). The doc says so | Yes |
| Other editions (Mac App Store, Setapp, CLI) | **Out of scope, with reason:** none exist. The doc covers MAS and Homebrew; Setapp is not named, which is harmless | Yes |
| Old versions without a feed newer ones have | **Not applicable:** no version has any feed | Yes |
| §1.2 coverage matrix and winning source | **Covered,** identical to the plan | Yes |
| Changelog | **Out of scope, with reason:** the vendor publishes only the fixed sentence, and hiding it would need a Core change. The plan predicted the pane would show raw inline notes; the executor recorded what it actually shows (`source structured: 1 entries …`), which is correct | Yes |
| One-click e2e | **Out of scope, with reason:** "未跑" is stated in the doc, the README row and the commit message | Yes |
| B4: vendor might switch to Developer ID | **Covered** in 建议下一步 #2. Matches the core behaviour (`teamIdentifierAppeared`) | Yes |
| Digests for all 6 assets | **Partly covered:** 4 of 6 (NOTE 3) | Partly |
| Unverified FDA / hotkey | **Covered as 未验证,** but more can be settled now (NOTEs 1 and 2) | Partly |
| Optional x86_64 unit test | **Not done;** it was optional (NOTE 4) | Acceptable |

No one-click route available in the code base was left out. The Developer-ID route is impossible because there is no Team ID, the Homebrew route doesn't apply because the app is only in a tap, and there is no Sparkle feed or vendor endpoint. Digest-only was the only option and it is the one used.

Sources:
- [Apple forums: app loses Screen Recording permission after updating (ad-hoc signature)](https://developer.apple.com/forums/thread/795739)
- [Apple forums: TCC uses the designated requirement](https://developer.apple.com/forums/thread/707177)
- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements.md)
- [go-macos/hotkey: RegisterEventHotKey needs no permission (community report)](https://pkg.go.dev/github.com/go-macos/hotkey)
- [mjtsai: Hotkeys and the Mac App Store](https://mjtsai.com/blog/2012/05/17/hotkeys-and-the-mac-app-store/)
