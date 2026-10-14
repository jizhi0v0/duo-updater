## Review: disktree onboarding (`90f8415..9ab087c`)

The code is correct and the trust model holds. Nothing in the rule, pattern, version mapping or digest-only gate is wrong. The one blocking item is the end-to-end install run, which hasn't happened. The rest are gaps in the evidence and docs.

**What I checked:**
- **Tests pass:** `swift test --filter 'DigestOnlyRecipeTests|GitHubAssetSelectionTests|RecipeGoldenTests|AppAuditCoverageTests|GitHubRelease'` → "110 tests in 7 suites passed".
- **Checkers pass:** `check_app_audits.py`, `check_recipe_snapshots.py`, `check_ifchange.py` and `check_prose_claims.py` all report ✓.
- **Vendor repo:** I read `release.yml`, `xtask/src/bundle.rs`, `Info.plist.in`, the `Makefile` and the README. I also downloaded the v0.10.0 macOS zips.
- **Digest-only gate:** `SignatureVerifier.verifyDigestOnlyIdentity` checks that both sides are ad-hoc, that the plist and signed identifiers equal the rule's bundle ID, and that the version matches. A Team ID showing up on the download makes it refuse (`teamIdentifierAppeared`). Quarantine is stripped after the swap (`InPlaceSwap.stripQuarantine`). So the route is gated correctly.
- **Arch selection:** `HostArch.assetTokens` covers both `aarch64` and `x86_64`, so the per-arch pick works on either kind of Mac.

---

### BLOCKING

**1. One-click is switched on but has never been run end to end, and this is the first `.zip` rule on the digest-only route.**
- **Evidence:** The audit doc and the README index both say "一键端到端 未跑". The other four digest-only rules (alacritty, darktable, flameshot, lokii) are all `installerKind: .dmg`. disktree is the first digest-only rule that goes through zip unpacking. Under `coverage-discovery` §「What "onboarded" means」, one-click counts as done only after the Phase 5 run, and `app-audit` says that run is pre-authorized.
- **Fix:** Run it serially from the coordinator before treating this as onboarded:
  - `ditto` 0.10.1 into `/Applications` and don't launch it.
  - With the setting off: `duo check disktree`, then `duo install disktree --yes --json` should be refused (`digestOnlyNotAllowed`).
  - With the setting on: it should report `installed`.
  - Afterwards check the version (0.11.0), the inode change, `codesign --verify --deep --strict`, and that the bundle is still ad-hoc with the same identifier. Also check `duo backups`.
  - Then do the running-app round.
  - Write the results into 一键安装 and the README line.

---

### NOTE

**2. The doc misses the `make install` copy: "仓库里没有 CLI 的 macOS 安装方式" is wrong.**
- **Evidence:** On Darwin, the vendor `Makefile` runs `cargo xtask bundle` and then `ditto` into `$(APPS)` (default `~/Applications/disktree.app`). It also runs `ln -sf …/Contents/MacOS/disktree $(BINDIR)/disktree` (default `~/.local/bin`). The README's macOS section documents this too: "`make install  # ~/Applications/disktree.app, and ~/.local/bin/disktree`".
- **Why it matters:** `AppScanner` scans `~/Applications`, so this locally built ad-hoc copy is an installed copy duo will detect. It will also replace it through the digest-only route, because neither side has a Team ID. The CLI is a symlink into the bundle, so it follows an in-place swap and needs no tracking of its own. Still, the doc's claim and the recipe comment ("no command-line tool to track on macOS") are inaccurate as written.
- **Fix:** In 基本信息/已知问题, list the `make install` copy as a second installed form. It reports the `Cargo.toml` version at build time and is ad-hoc signed by the machine that built it. One-click replaces it with the release build. The `~/.local/bin/disktree` symlink survives an in-place swap. Reword the recipe comment to say there is no CLI to track *separately*.

**3. The first macOS release, v0.10.0, is left out of the evidence.**
- **Evidence:** `gh api …/releases` shows macOS zips in v0.10.0, v0.10.1 and v0.11.0. v0.9.0 and v0.9.1 have Linux tarballs only. The doc and tests cover only 0.10.1 and 0.11.0.
- **What I found:** I downloaded both v0.10.0 zips. Their shasums equal GitHub's digests (`efe3c3ba…69c49`, `1e24d718…ae87d`). Both `Info.plist` files say `io.github.tobi.disktree` and `0.10.0` / `0.10.0`. The binary has no updater strings (`releases/latest`, `api.github.com`, `appcast`, `SUFeed`). So 0.10.0 copies are covered. I didn't run `codesign` on 0.10.0, because `ditto -x` was denied in this session. That doesn't matter for installs, since the gate only checks the new package.
- **Fix:** Add a line to the doc: macOS builds start at 0.10.0, and that release has the same bundle ID and version scheme.

**4. The vendor's CI can switch to Developer ID signing with no code change, and duo will then refuse the update once.**
- **Evidence:** In `release.yml`, the `macos` job passes `--sign` / `--notarize` whenever the `MACOS_CERTIFICATE`/`NOTARY_*` secrets exist; without them it signs ad hoc. `bundle.rs` also adds a hardened runtime and staples a notarization ticket on that path.
- **What happens then:** The first signed release hits `teamIdentifierAppeared`, which fails safely. Every ad-hoc install then has to be updated by hand once. The rule also stays digest-only, so it stays hidden behind the setting until someone changes it.
- **Fix:** Record this mechanism in 建议下一步 2 and the recipe comment. When the first signed release appears, change `installTrust` to the default and write down the expected one-time manual update.

**5. The test fixtures leave out 4 of the 12 real assets, yet both comments say they are what GitHub listed.**
- **Evidence:** v0.11.0 and v0.10.1 each publish 12 assets. These four are missing from the `DigestOnlyRecipeTests` and `GitHubAssetSelectionTests` fixtures: `aarch64-linux.tar.gz.sha256`, `aarch64-windows.zip.sha256`, `x86_64-linux.tar.gz.sha256` and `x86_64-windows.zip.sha256`. The pattern wouldn't match them, so behaviour is unaffected. Only the "actually published" / "in the order GitHub listed them" claims are wrong.
- **Fix:** Use the full 12-name lists in API order.
- **Optional:** The digest-only test only picks for arm64. An `x86_64` pick assertion for disktree (`disktree-<v>-x86_64-macos.zip`) would cover the Intel half of "arch left to the source's preference".

**6. The changelog explanation is slightly off.**
- **Evidence:** The release bodies do have headings: `## What's Changed` and `## New Contributors`. `GitHubMarkdownParser` drops the auto-generated boilerplate on purpose, which is why the count is 23 items, exactly the What's Changed list. `headings []` is the right result, but not because "正文没有小节标题".
- **Fix:** Reword it as: the body is GitHub's auto-generated notes, and the parser drops their two fixed headings and the contributor list by design.

---

**Not findings (checked and fine):**
- **Tag and version mapping:** tags are `v<X.Y.Z>`, `Cargo.toml` must equal the tag (`release.yml` enforces this), and `@VERSION@` is filled into both `CFBundleShortVersionString` and `CFBundleVersion`.
- **Channels:** every release is stable, with no prereleases or alternate tracks.
- **Homebrew:** there is no Homebrew cask or formula (`brew info --cask disktree` → "No Cask with this name exists").
- **Digest test change:** the `"rc"` → `"-rc"` edit is needed ("aarch64" contains "rc") and still catches `Alacritty-v0.17.0-rc2.dmg`.
- **Golden and index:** the golden file is consistent, and the README index line sits in the correct section.
