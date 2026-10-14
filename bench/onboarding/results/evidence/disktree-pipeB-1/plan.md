# Onboarding plan: disktree (tobi/disktree)

Observed 2026-10-14. Everything below marked **measured** was run by the planner; the raw
commands are in "Evidence" at the end. Anything marked **unverified** has to stay worded that
way in the code comment and the audit doc.

## Facts the plan rests on

| Fact | Value | How it was settled |
|---|---|---|
| Repo | `tobi/disktree`, MIT, Rust + GPUI, default branch `main`; main == `v0.11.0` (ahead 0 / behind 0) | `gh api repos/tobi/disktree`, `compare/v0.11.0...main` |
| Already covered in duo-updater? | No. `grep -rni disktree DuoUpdaterCore/Sources docs/app-audits CHANNEL_COVERAGE_TODO.md` returns nothing | measured |
| Bundle id | `io.github.tobi.disktree`, the only one ever. `packaging/macos/Info.plist.in` has a single commit (cbdfe1c3, 2026-09-25, "macOS support…"). The same id is on all 9 branches that carry the file | settled from source: `packaging/macos/Info.plist.in` on `main` and every branch |
| Version stamp | `CFBundleShortVersionString` = `CFBundleVersion` = workspace `version` in `Cargo.toml` (`xtask/src/bundle.rs` replaces `@VERSION@`). `release.yml` refuses a tag that is not `v<Cargo version>` | settled from source: `xtask/src/bundle.rs`, `.github/workflows/release.yml` on `main`; the real bundles agree (0.10.0/0.10.1/0.11.0) |
| Releases | v0.9.0, v0.9.1 (Linux only, no macOS asset); v0.10.0, v0.10.1, v0.11.0 (macOS). None is a prerelease. The workflow publishes with `--latest`. `/releases/latest` = v0.11.0 | `gh api repos/tobi/disktree/releases` |
| macOS assets | `disktree-<ver>-aarch64-macos.zip` and `disktree-<ver>-x86_64-macos.zip`, plus `.zip.sha256` sidecars, next to Linux `.tar.gz` and Windows `.zip`. Every asset has a GitHub `digest` | releases API; all 6 macOS zips downloaded, `shasum -a 256` equals both the API `digest` and the `.sha256` sidecar for every zip |
| Architectures | Thin builds: arm64 zip → `lipo` arm64; x86_64 zip → x86_64. No universal build | measured on all 6 |
| OS floor | `LSMinimumSystemVersion` 11.0 on all 6; `DEPLOYMENT_TARGET = "11.0"` in `bundle.rs` | measured + source |
| Signing | **Ad hoc on every macOS release so far.** `Signature=adhoc`, `flags=0x2(adhoc)`, `TeamIdentifier=not set`; `codesign --verify --deep --strict` exit 0 (seal intact) on all 6; signed `Identifier=io.github.tobi.disktree`; `spctl -a -t exec` → `rejected` (exit 3); no stapled ticket. `release.yml` signs with Developer ID and notarizes **only if** the repo has the `MACOS_*`/`NOTARY_*` secrets. They evidently are not set: README tells macOS users to run `xattr -dr com.apple.quarantine` | measured on all 6 + source |
| Designated requirement | `designated => cdhash H"…"`, a different hash per release (0.10.1 arm64 `4ed4e7ae…`, 0.11.0 arm64 `67134b8f…`) | measured (`codesign -dr -`) |
| Bundle contents | 4 files: `Info.plist`, `MacOS/disktree`, `Resources/AppIcon.icns`, `_CodeSignature/CodeResources`. No Frameworks, no `LoginItems`/`Helpers`, no nested app, no LaunchAgent, no `SUFeedURL`, no `app-update.yml` | measured (`find`, `check-bundle.sh`) |
| Own updater | **None.** No Sparkle. The binary's only URLs are doc links (oklab, MDN). It has no `releases/latest` or update-check strings. `Cargo.lock` has `hyper` only through GPUI, and no update crate. Source has no update code (`main.rs`/`app_menu.rs` grep) | measured + source |
| Homebrew / MAS | No cask and no formula (`brew search disktree` shows only `disktype`/`disk-expert`; `formulae.brew.sh/api/cask/disktree.json` and `/formula/disktree.json` both 404). No MAS | measured |
| Changelog | Release body is GitHub `--generate-notes`: `## What's Changed` bullets "… by @user in …/pull/N", `## New Contributors`, `**Full Changelog**`. v0.9.x bodies are only the Full Changelog line | releases API |
| Open PRs that could change this | #79 / #102 (headless scan + MCP server) and #32 / #85 (CLI) add crates but touch neither `packaging/` nor `xtask/`. None is merged | `gh pr view … --json files` |

## 1. Coverage checklist

Pattern: one bundle id, one track (stable), two arch editions. No channels to bind.

| # | Installed copy | Bundle id / signing / helper | Detection route | One-click route | Changelog route |
|---|---|---|---|---|---|
| 1 | **Release build, Apple silicon** (`disktree-<v>-aarch64-macos.zip`, dragged into `/Applications`), 0.10.0 / 0.10.1 / 0.11.0 | `io.github.tobi.disktree`, ad hoc, no Team ID, seal verifies; no helper | New `GitHubReleaseRule` on `tobi/disktree`, stable, default `versionPattern` (tags `vX.Y.Z` = short version). No generic source answers: no `SUFeedURL`, no electron config, no cask. | `installTrust: .publishedDigestOnly`, `installerKind: .zip`, pattern `^disktree-[0-9.]+-(?:aarch64\|x86_64)-macos\.zip$`. Host-arch preference picks the `aarch64` zip (`HostArch.arm64.assetTokens` contains `aarch64`). Offered only when the user has turned on `AllowDigestOnlyInstalls`. The gates: digest = GitHub `digest` (all present); `verifyDigestOnlyIdentity` checks ad hoc on both sides, plist + signed id = `io.github.tobi.disktree`, and short version = tag. **E2E not yet run** (see Boundaries). | GitHub release body → `GitHubMarkdownParser` (generated-notes shape it is written for; `New Contributors` skipped, `by @x in URL` stripped). Expected: structured. Executor records the real `changelog pane` line. |
| 2 | **Release build, Intel** (`…-x86_64-macos.zip`) | Same id, ad hoc, x86_64 slice only; no helper | Same rule (the version check does not depend on arch) | Same rule; the selector picks the `x86_64` zip on an Intel host. Wired, **not verified on an Intel Mac** (no Intel host here). It uses the generic arch selector already unit-tested for other rules, so no separate rule. | Same |
| 3 | **Intel zip on Apple silicon** (user took the wrong zip) | Same id, x86_64 only | Same rule | Host preference picks `aarch64`. Gate 5b only refuses dropping an arm64 slice the installed copy *has*, and this copy has none, so it becomes a native build. Expected fine, **unverified** on a real install. | Same |
| 4 | **Built from source** with `make install` (README, macOS section) → `~/Applications/disktree.app`, plus symlink `~/.local/bin/disktree` → `…/Contents/MacOS/disktree` | Same id, ad hoc, signed on the builder's Mac (different cdhash); version = the `Cargo.toml` of the checked-out branch | Same rule. No signal tells it apart from a release copy (same id, same ad-hoc shape), and none is needed: a build of `main` at 0.11.0 reads "up to date"; a build from an older branch (several still carry 0.9.1 / 0.10.x) is offered 0.11.0 | The same digest-only gates pass in principle. A swap replaces the self-built bundle with the release build at the same path, so the `~/.local/bin` symlink keeps resolving. **Unverified**; document, don't special-case. | Same |
| 5 | **Pre-macOS releases v0.9.0 / v0.9.1** | No macOS asset was ever published. No downloadable macOS copy exists; only a source build (row 4) can report 0.9.x | Row 4 | Row 4 | v0.9.x bodies have no bullets (only the Full Changelog line); the parser's prose pass may or may not yield an entry. Record what `channel-verify` shows; no recipe |
| 6 | **Channels: beta / nightly / RC** | None exist: no prerelease ever, no prerelease tag, workflow always `--latest`, no channel pref in source | — (nothing to wire). State "settled from source: `.github/workflows/release.yml`" | — | — |
| 7 | **Old copies lacking a feed newer ones declare** | Not applicable: no version declares any feed (all 4-file bundles, no `SUFeedURL`) | Same GitHub rule covers every version | — | — |
| 8 | **Bundle id renames** | None. One id since the first macOS commit; Info.plist comment says the id is kept stable on purpose (TCC keys) | — | — | — |
| 9 | **Resident helper** | None (no nested app, no login item, no LaunchAgent). The CLI symlink (row 4) runs the bundle's own binary, so it is not a separate copy | — | No one-click block from a helper | — |
| 10 | **Homebrew / MAS / AUR** | No cask, formula, or MAS listing. AUR `disktree` / `disktree-bin` are Linux only | — | — | — |

Delta / binary patch: client none (no updater), server none (no delta assets), consume —.
Self-updater collision: none possible (no updater).
What the rule reads: **the public GA build anyone can download by hand** (`/releases/latest`, which the README links to).

## 2. Steps for the executor

Work in your own clone on a branch (`git fetch origin && git switch -c recipe/disktree origin/main`) and your own scratch dir `SCR`. Worked example: `git show c9923e4` (Pulse) for the file set, and `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/com-lokii-app.swift` (+ `docs/app-audits/com-lokii-app.md`) for the **digest-only** shape, which this app needs.

1. **Re-check identity yourself** (don't take it from this plan):
   ```bash
   mkdir -p "$SCR/dl" && cd "$SCR/dl"
   for v in 0.10.1 0.11.0; do for a in aarch64 x86_64; do
     curl -sSLf -O "https://github.com/tobi/disktree/releases/download/v$v/disktree-$v-$a-macos.zip"; done; done
   shasum -a 256 *.zip     # compare with: gh api repos/tobi/disktree/releases -q '.[].assets[] | select(.name|endswith("-macos.zip")) | "\(.digest) \(.name)"'
   <repo>/.claude/skills/coverage-discovery/scripts/check-bundle.sh "$SCR"/dl/*.zip
   ```
   Expect `io.github.tobi.disktree`, short = build = tag, `TeamIdentifier=not set`, `codesign-verify-exit=0`, no `nested` line. Also `codesign -dv` → `Signature=adhoc` on each. Retry a curl that fails with a TLS EOF (seen once).
   Expected sha256 (from the API, measured equal to the downloads):
   - 0.11.0 aarch64 `942f2508fbbbd6901f796494492b16250d52227155b0ab59f6a5a446b033600b`
   - 0.11.0 x86_64 `16ddba6c3d983651cb6389d1c7fd6a070ba443aafcf03c2bc857e35e73b43f4d`
   - 0.10.1 aarch64 `90381628fdd0fc5c87aa32ba003ee85f2fb5eb496fab7aa1ee16428aaf7d9eca`
   - 0.10.1 x86_64 `9955a0da39630296aef5709114979d79c8eb6f7e045bf67a056e490e1d3c4b96`

2. **Confirm no generic source:** `swift run --package-path application-test feed-discover "$SCR/dl/disktree-0.11.0-aarch64-macos.zip"` (it takes a zip). Expected `noKnownUpdater`. Paste the line.

3. **Add the family file** `DuoUpdaterCore/Sources/DuoUpdaterCore/Recipes/io-github-tobi-disktree.swift`, modelled on `com-lokii-app.swift`:
   ```swift
   import Foundation

   enum io_github_tobi_disktree {
       static let set = AppRecipeSet(
           family: "io-github-tobi-disktree",
           githubRules: [
           // Shared rationale for digest-only: Recipes/org-alacritty.swift.

           // disktree (tobi) — Rust + GPUI disk treemap. No Sparkle and no
           // updater of its own; no cask. Tags `vX.Y.Z` (release.yml refuses a
           // tag that is not `v` + the Cargo.toml version) and the bundle's short
           // and build versions are both that version (checked 2026-10-14 on
           // 0.10.0, 0.10.1, 0.11.0, both arches). v0.9.x shipped no macOS build.
           //
           // Ad-hoc signed, no Team ID (`spctl` rejects it): release.yml signs
           // with Developer ID only when the repo has the signing secrets, and
           // no release so far had them. The seal verifies (`--deep --strict` 0),
           // the signed identifier is io.github.tobi.disktree, and GitHub
           // publishes a sha256 for every asset (matches the downloads), so
           // `.publishedDigestOnly`. Should a release ever arrive Developer ID
           // signed, the digest-only gate refuses it (`teamIdentifierAppeared`)
           // and this rule has to move to `.developerID`.
           //
           // Thin zips per arch, `disktree-<v>-aarch64-macos.zip` /
           // `-x86_64-macos.zip`, beside Linux/Windows archives and `.sha256`
           // sidecars; the arch is left to the source's arch preference. The
           // bundle is the binary, its plist and icon: no helpers or nested apps.
           GitHubReleaseRule(
               bundleID: "io.github.tobi.disktree",
               owner: "tobi", repo: "disktree",
               versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
               installAssetPattern: #"^disktree-[0-9.]+-(?:aarch64|x86_64)-macos\.zip$"#,
               installerKind: .zip,
               installTrust: .publishedDigestOnly),
           ])
   }
   ```
   Keep the comment's claims to what you re-measured in step 1. Add `io_github_tobi_disktree.set,` to `AppRecipeIndex.all` in sorted position (it falls after the existing `io_github_*` rows; check the neighbours).

4. **Re-record goldens**, then run the test without the variable:
   ```bash
   DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests   # fails on purpose
   swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests                                # must pass
   ```
   Commit the new `DuoUpdaterCore/Tests/RecipeGoldens/io-github-tobi-disktree.txt`. Check it shows `installTrust = .publishedDigestOnly`, `installerKind? = .zip`, `channel = .stable`, `usePrereleases = false`.

5. **Old → new detection on real bundles.** `channel-verify` takes `.app`/`.dmg`/`.pkg`, not `.zip`, so expand into scratch first (one dir per zip, nothing executed):
   ```bash
   for z in "$SCR"/dl/*.zip; do d="$SCR/x/$(basename "$z" .zip)"; mkdir -p "$d"; ditto -x -k "$z" "$d"; done
   swift run --package-path application-test channel-verify "$SCR/x/disktree-0.10.1-aarch64-macos/disktree.app" --expect stable
   swift run --package-path application-test channel-verify "$SCR/x/disktree-0.11.0-aarch64-macos/disktree.app" --expect stable
   swift run --package-path application-test channel-verify "$SCR/x/disktree-0.10.1-x86_64-macos/disktree.app" --expect stable
   ```
   Expected: 0.10.1 → `UPDATE → 0.11.0`, winning source GitHub; 0.11.0 → up to date. Paste the raw lines, including the **`changelog pane`** line. If it shows `headings []` with "What's Changed" among the items, that is flattening: report it. `headings []` with no heading text in the items is a single non-category heading being dropped, which is fine: say so. Also check which asset the x86_64 run's download URL names (the host here is arm64, so expect the `aarch64` zip).

6. **Audit doc** `docs/app-audits/io-github-tobi-disktree.md`, from the app-audit report template (copy 「观测版本」 verbatim). Required content:
   - 基本信息: bundle id, "Team ID: 无（ad-hoc）", 观测版本 0.11.0 (+ date), 自更新机制: 无, 分发: GitHub Releases only (no cask / MAS).
   - Coverage matrix: stable × GitHub ✓, the others —. Channel 详情: single track, "settled from source: `.github/workflows/release.yml` on `main`" (no prerelease, `--latest`).
   - 按架构 / 按 OS 分轨: thin arm64 / x86_64 zips; `LSMinimumSystemVersion` 11.0 on all; no `hostRequirement`.
   - 增量: 无 / 无 / — with evidence.
   - Changelog: the real `changelog pane` line from step 5.
   - 一键安装: 状态 **digest-only（需要用户打开设置）**; pattern + kind; 校验 = the GitHub `digest` per asset, with the 4 hashes matched; **读的是**: 人人可手动下载的 GA; **端到端: 未跑**, with the reason (see Boundaries). Don't write ✓ for one-click.
   - 已知问题: (a) every release so far is ad hoc, and a future signed release makes the digest-only gate refuse once (`teamIdentifierAppeared`), so the rule must move to `.developerID`; (b) the designated requirement is a bare cdhash that changes per release (measured). Whether macOS then drops the Full Disk Access grant after any update (by hand or by duo) is **unverified**; word it as such; (c) self-built `~/Applications` copies (`make install`) share the id and are treated the same; (d) the x86_64 route is unverified on an Intel Mac.
   - 如何复验: the commands from steps 1, 2 and 5. **No** links to `application-test/records/`.
   - Public-repo rules: no `/Users/<name>` paths, no "this machine runs…" framing.

7. **README index line** in `docs/app-audits/README.md` under `## Single-channel — GitHub Releases`, next to the Lokii row and in that row's style, e.g.
   `- [x] [**disktree**](io-github-tobi-disktree.md) · \`io.github.tobi.disktree\` — G (**digest-only**，ad-hoc 签名，arm64/x86_64 zip) · 真包 0.10.1/0.11.0 两个 arch 核对封印/标识/版本/digest ✓ · 一键端到端 **未跑** · changelog <result from step 5> · 2026-10-14`
   Use `[x]` only if that section's convention allows it for a not-yet-e2e app; otherwise `[ ]`. Look at the neighbours.

8. **`make test`** in the foreground with a long timeout, judged by exit code (it also runs `check_app_audits.py`, `check_ifchange.py`, `AppAuditCoverageTests`). Paste the tail and the exit code. Fix doc wording that `check_app_audits.py` rejects, not the checker.

9. Commit with `git commit -F <msgfile>`, no push. The message gives the three counts: detection ✓ (channel-verify 0.10.1→0.11.0), one-click wired digest-only / e2e not run, and changelog <result>.

## 3. Boundaries

**Don't:**
- Don't use `installTrust: .developerID` (the default). With no Team ID on either side, the Team gate refuses every install, so the rule would look installable and never install.
- Don't add a channel, `usePrereleases`, `ChannelBinding`, `VendorProbeRecipe`, `ChangelogRecipe`, `SparkleFeedCatalog` entry, `hostRequirement` or `architectureRequirement`. Nothing calls for any of them (single track, GA notes in the release body, floor 11.0 everywhere, both arches published).
- Don't use the `.zip.sha256` sidecars as the checksum source. GitHub rules already pass the asset `digest` (#1019), and the source's rule is "never from the URL or a sidecar file".
- Don't write separate per-arch rules. The single pattern plus the arch selector is the Lokii shape.
- Don't touch `verify/baseline.json`, `verify/identities.json` or `verify/install-baseline.json`. A bot (`duo-verify`) maintains them.
- Don't edit `Recipes/org-alacritty.swift`'s list of no-Team-ID rules. Lokii didn't either; the one-line "Shared rationale" pointer is the convention.
- Planner's rules carry over: no `make install`, `make cli`, `duo` CLI, `pkill`/`killall`, `git stash`, `git push`, PRs/issues; nothing into `/Applications` or `~/Applications`; don't launch the downloads, don't touch quarantine xattrs, nothing that pops system UI.

**Stays unverified until run on a real machine (word it so in the doc):**
- **One-click end to end.** It needs `make cli`, `ditto` of 0.10.1 into `/Applications`, and `duo install` twice: once with `AllowDigestOnlyInstalls` off (expect `skipped` with the "no developer signature" reason) and once with it temporarily on (expect `installed`, 0.11.0, inode changed, `--deep --strict` 0, `diff -r` = vendor bundle), following coverage-discovery Phase 5 and the Lokii audit. Under the executor's brief that run is forbidden, so it is the serial Phase-5 owner's job. Until then the doc says 端到端未跑 and the README row says so. The rule still carries `installAssetPattern`. That matches the coverage-discovery flow (agent wires, orchestrator runs e2e), and it is fail-safe: digest-only is off by default and every gate refuses rather than degrades.
  If the reviewer or user prefers strict "no one-click until e2e", the fallback is `installAssetPattern: nil` (detection only). Raise it; don't decide alone.
- x86_64 one-click on an Intel Mac, and the wrong-arch (row 3) and self-built (row 4) swaps.
- Whether Full Disk Access survives an update of a cdhash-designated app. The only sources found were third-party issue threads, not Apple docs, so the claim stays a hypothesis.

**Core changes, record only, don't make:**
- `channel-verify` doesn't accept `.zip` (only `feed-discover` does). The workaround is expanding the zip first. Mention it in the report; don't patch the harness in this change.
- A vendor switching from ad hoc to Developer ID needs only a rule edit (`.developerID`); the Core already refuses safely. No Core change.
- Re-audit triggers, for the doc's 建议下一步: the repo gains signing secrets (first signed release); PR #79/#102 (MCP server) or #32/#85 (CLI) merges and changes the bundle (a second executable or a long-running process); a universal or dmg asset appears (pattern change).

## Evidence (planner's commands, abbreviated output)

```
gh api repos/tobi/disktree/releases -q …   → v0.11.0 / v0.10.1 / v0.10.0 (6 macOS zips + sha256), v0.9.1 / v0.9.0 Linux only; all pre=false
shasum -a 256 *.zip                        → all 6 equal API digest and .sha256 sidecar
check-bundle.sh *.zip                      → io.github.tobi.disktree, short=build=<tag>, LSMinimumSystemVersion=11.0, SUFeedURL=<none>,
                                             archs arm64|x86_64, TeamIdentifier=not set, codesign-verify-exit=0, no nested
codesign -dvvv 0.11.0-arm64                → Signature=adhoc, flags=0x2(adhoc), Identifier=io.github.tobi.disktree
spctl -a -vv -t exec                       → rejected (exit 3), all 6;  stapler validate → no ticket
codesign -dr -                             → designated => cdhash H"4ed4e7ae…" (0.10.1) / H"67134b8f…" (0.11.0)
find disktree.app                          → Info.plist, MacOS/disktree, Resources/AppIcon.icns, _CodeSignature/CodeResources
strings binary | grep URLs/update          → only doc URLs; no update endpoints
brew search disktree; formulae.brew.sh     → no cask/formula (404/404)
gh api compare/v0.11.0...main              → ahead=0 behind=0
Info.plist.in on 9 branches                → io.github.tobi.disktree everywhere
```
