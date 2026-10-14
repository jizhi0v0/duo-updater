Nothing in the Obelisk onboarding is wrong enough to stop it shipping: **0 BLOCKING, 5 NOTEs**. The recipe golden tests, `AppAuditCoverageTests` and `check_app_audits.py` all pass (206 tests in 24 suites; checker reports 224 docs consistent). The detection logic holds up. The one fix worth making before merge is in the changelog recipe: three older entries show download file names as change notes.

What I checked and found correct:
- **Source order:** in `SourceStack.make`, Sparkle (line 38) runs before the GitHub source (line 41). So the detection-only GitHub rule can't hide Sparkle's one-click install for 0.2.4 and later.
- **Old versions share the bundle ID:** I downloaded the v0.1.0 zip (sha256 matches GitHub's published hash `847e056b…`) and read its `Info.plist`: `com.obelisk.app`, version 0.1.0, no `SUFeedURL`. For v0.2.0 and v0.2.2 the vendor's `app/package.json` gives `appId` `com.obelisk.app`; v0.2.1 is the same unless it changed between those two. So the GitHub rule does cover every older copy, not just 0.2.2.
- **No one-click route was left out:** the newest build is Developer ID signed, and the code refuses to replace an install that has no Team ID with one that has a Team ID, on both the normal route and the hash-only route for ad-hoc apps from #952. Sparkle is the only workable one-click route, and it's in place.
- **Channels:** every release is non-prerelease. The rule's version pattern rightly ignores `-rc` tags.

## Findings

### 1. NOTE (fix before merge) — older changelog entries list download file names as changes
`com-obelisk-app.swift` only skips `"Included work"`. Releases v0.2.0, v0.2.1 and v0.2.2 have a `## Downloads` section with bullet points, and those bullets come through as change notes. I ran the repo's own `GitHubMarkdownParser.parse` on the real release text (from a separate test package in my scratch folder) with the recipe's skip list. The last items it returned were:

```
== 0.2.2 items=46   … - `Obelisk-0.2.2-mac-arm64.dmg`  - `Obelisk-0.2.2-mac-arm64.zip`  - `Obelisk-0.2.2-linux-amd64.deb`
== 0.2.1 items=26   … - `Obelisk-0.2.1-mac-arm64.dmg`  - `Obelisk-0.2.1-linux-amd64.deb`
== 0.2.0 items=29   … - `Obelisk-0.2.0-mac-arm64.dmg`  - `Obelisk-0.2.0-linux-amd64.deb`
```

The audit doc also claims the "Installation" section is "already dropped by the decoder". That's not true: the parser's built-in skip list is only `new contributors`, `contributors` and `full changelog`. v0.2.5's Installation section is left out only because it's plain paragraphs with no bullets.

**Fix:**
- Change the recipe to `skipSections: ["Included work", "Downloads", "Installation"]`.
- Update the doc and the recipe comment to say why each section is skipped.
- Re-record the goldens.

### 2. NOTE — the recipe comment and doc name the wrong refusal error
They say the signature check refuses with `teamIdentifierAppeared`. That error is only thrown on the hash-only route for ad-hoc apps (`SignatureVerifier.swift:214`). On this rule's default Developer ID route, an install with no Team ID fails the Team check with `noTeamIdentifier(which: "installed")` (`SignatureVerifier.swift:358-359`). The conclusion (detection only) is still right.

**Fix:** reword it as "the Team ID check refuses an install with no Team ID on either route (`noTeamIdentifier` on the default route, `teamIdentifierAppeared` on the hash-only route)".

### 3. NOTE — Homebrew is marked "未查" (not checked); it can be settled
`brew info --cask obelisk` returns `Error: Cask 'obelisk' is unavailable: No Cask with this name exists.`, and `brew search obelisk` only finds `bazelisk` and `blisk`.

**Fix:** mark the Homebrew cell as — (no cask, checked 2026-10-14) and remove the "没有核 Homebrew cask" (Homebrew cask not checked) line from 已知问题 (known issues).

### 4. NOTE — the doc's old-version facts are thin or slightly off
- It says "没有 v0.2.3" (there is no v0.2.3). Tag `v0.2.3` does exist; it just has no GitHub release. This doesn't affect anything, because the GitHub source reads releases, not tags.
- It verifies only 0.2.2 for the old-version rule. **Fix:** add v0.1.0's `CFBundleIdentifier` `com.obelisk.app`, read from the published zip (hash above), and the matching `appId` in `app/package.json` for v0.2.0 and v0.2.2.
- **Known gap to record:** v0.1.0's `LSMinimumSystemVersion` is `11.0`, while the 0.2.2 notes say "macOS now requires macOS 12". `GitHubReleaseRule` has no way to express a minimum macOS version, so a copy of 0.1.0 on macOS 11 is told to update to 0.2.5, which won't run there. Nothing gets installed (the rule is detection only), so this is cosmetic. I didn't check what v0.2.0 and v0.2.1 require. **Fix:** add a line to 已知问题.

### 5. NOTE — the one-click install hasn't been run end to end
The doc says this plainly, which is correct. Before the README line is final, someone still needs to run it in sequence: install 0.2.4, then `duo install --yes`, then check for 0.2.5 with Team `433DLLA855`, and that `codesign --verify` and `spctl` pass.

## Two things I couldn't run
- **`channel-verify` on the v0.1.0 bundle:** permission was denied, so whether the GitHub rule answers for 0.1.0 is inferred (same bundle ID, `v0.1.0` matches the rule's version pattern), not observed.
- **The npm registry lookup for the CLI** (`@obelisk-apps/cli`): blocked. From the vendor repo, the CLI's `package.json` has no `repository` field, and the 2025-10-08 release notes say its "npm release lifecycle" is separate. It isn't part of this app onboarding.
