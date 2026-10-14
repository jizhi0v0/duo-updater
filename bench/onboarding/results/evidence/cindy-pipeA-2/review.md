# Review: Cindy onboarding (`d5fa268`)

Five things block this: Intel Macs get no update detection at all, the vendor's update manifest is public when the doc says it isn't, so the cn edition and the beta track are both reachable, and there's no proof yet that one-click actually works.

Everything else checks out. The 225 targeted tests pass (`swift test --filter 'RecipeGoldenTests|RecipeHealthKeyTests|GitHubRelease|AppAuditCoverageTests|ChangelogRecipe'` → exit 0), `scripts/check_app_audits.py` passes, and the README row sits in the right section. The tag pattern, version scheme and arm64 asset are correct, and the arm64 dmg's Team matches on 0.1.103 and 0.1.104.

---

### 1. BLOCKING: Intel Macs get no update detection at all
The commit and doc both say "Intel Macs stay detection-only". That's wrong.
- **Code path:** with the arm64-only `installAssetPattern`, every release counts as arch-incompatible on an x86_64 host (`GitHubReleasesSource.swift:1380-1385`). `resolve()` then returns `remote: nil` (`:1455-1460`), and the check reports `.notApplicable("…only ships an asset this host cannot run")` (`:931-936`). No version is shown at all.
- **The x64 dmg is safe to add.** I downloaded `cindy-0.1.104-darwin-x64-global.dmg` and mounted it read-only:
  - sha256 `826a807d…2909` equals the API digest
  - bundle id `com.xd.cindy`, version 0.1.104/0.1.104, `x86_64`
  - `TeamIdentifier=SX9RG894L5`, `codesign --verify --deep --strict` OK
  - spctl: `Notarized Developer ID`, stapler validate OK
  - only the 4 standard Electron Helper apps inside
- **The engine already handles both arches.** `HostArch` treats `x64` as an Intel marker, and one rule already covers both arches the same way (`dev-openchamber-desktop.swift:15`).
- **Fix:**
  1. Change the pattern to `#"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$"#`.
  2. Re-record the goldens.
  3. Correct the doc's 一键安装 section and 建议下一步 #3, and the recipe comment.

### 2. BLOCKING: the vendor's update manifest is public, so "✗ VendorProbe" and "cn is blocked by the engine" are both wrong
- **The doc says** the CDN address is resolved at run time and "没有可读的公开地址" (there's no readable public address). It's in the repo:
  - `config/endpoint.global.json` has `"cdnBaseUrl": "https://hotfix.cindy.app/cindy"`
  - `config/endpoint.json` (cn) has `https://hotfix.cindy.com.cn/cindy`
  - the app loads these files from the `raw.githubusercontent.com` mirrors listed in `config/endpoint-manifest-mirrors.json`
- **The URL format** comes from `manifestService.ts:175`: `${base}/manifest-${platform}-${arch}${suffix}.json`.
- **Fetched today, all returned HTTP 200:**

  | Manifest | `app.version` | `installer.sha256` | Matches GitHub digest of |
  |---|---|---|---|
  | `hotfix.cindy.app/cindy/manifest-darwin-arm64.json` | 0.1.104 | `9e8ac572…` | arm64 global dmg |
  | same, `-darwin-x64` | 0.1.104 | `826a807d…` | x64 global dmg |
  | `hotfix.cindy.com.cn/cindy/manifest-darwin-arm64.json` | 0.1.104 | `8f0704e3…` | arm64 cn dmg |

  The CDN installer URLs return 200, and their sizes equal the GitHub assets (305191277 B global, 305173888 B cn).
- **Why this unblocks cn.** The cn build doesn't need a second GitHub rule, so the `recipeID` collision never comes up. A VendorProbe is keyed by bundle id + channel, not by repo, and the existing recipe fields can express everything needed:
  - a VendorProbe for `com.xd.cindycn` on the cn manifest
  - version: `"app"\s*:\s*\{\s*"version"\s*:\s*"([0-9.]+)"`
  - install: `.bodyPatternRelative` on `installer.file`, with base `https://hotfix.cindy.com.cn/cindy/`
  - checksum: `checksumFormat: .sha256Hex`, using the tempered pattern bound to the `"installer"` object. The manifest also carries codex, claudeCode, hotfix and pi digests, so it must not pick up a neighbour's.
  - one recipe per arch (`hostRequirement`/`variant`)
  - a `ChangelogRecipe` for `com.xd.cindycn` on the same releases URL
- **The cn edition was otherwise ready.** The doc already shows `channel-verify` on the cn packages working, and the Team is unchanged from 0.1.103 to 0.1.104.
- **Fix:** add the cn probe and changelog. Then correct the matrix's VendorProbe cell, the 自更新机制 line and 已知问题. Also fix 建议下一步 #2: no engine change is needed for cn.

### 3. BLOCKING: the beta track is treated as undetectable, but it isn't
- **The doc says** the beta has "安装副本上没有可读的渠道信号" (no readable channel signal on the installed copy). But the doc itself names the switch file.
- **Where the signal lives** (from `updateChannelStore.ts`, `override-settings-file.ts` and `regionUserData.ts`):
  - the file is `~/Library/Application Support/CindyGlobal/update-channel-settings.json` for global, and `…/Cindy/…` for cn
  - it is a flat JSON of overrides
  - the effective value is `enableBeta` when that key is present, otherwise `orgDefaultEnableBeta`
- **The code base already reads files like this.** `ChannelBinding` resolvers read Application Support files today: Surge's `KDDefaults.plist` and Superconductor's `settings.json`. That makes this Pattern B ("switched by an in-app preference"), not Pattern D ("no signal").
- **The beta also has a public feed.** `manifest-darwin-arm64-beta.json` returns 0.1.108 with sha `81a09b2d…`. That equals the `v0.1.108-beta` asset digest, which I hashed myself.
- **The beta bundle's version string is now verified.** I mounted the beta dmg: `CFBundleShortVersionString = 0.1.108`, Team `SX9RG894L5`, and the bundle has no channel marker. The doc's "未验证" (unverified) guess was right, and that also confirms `installedTagPrefix` can't work.
- **The doc's safety claim is wrong.** "beta 副本不会被提示装 stable" (a beta copy is never offered stable) doesn't hold. Today a beta copy is treated as stable, so it is offered the next higher stable release. Examples from the release list: a copy on 0.1.96-beta → stable 0.1.97, and 0.1.81-beta → 0.1.82. One-click would install the stable dmg over it.
- **Not verified:** what the file looks like on a real installed copy. Nothing could be launched here.
- **Minimum fix:** reclassify beta as ○ (could be added, not yet implemented), with the file path and the rule for the effective value. Drop the "不会被提示装 stable" sentence and add the gap to `CHANNEL_COVERAGE_TODO.md` §2b.
- **Fuller fix:** a `CindyChannel` binding plus a beta VendorProbe. A non-stable install also needs a `ChannelProofRegistry` entry.

### 4. BLOCKING: one-click is listed but has no end-to-end proof
The README marks Cindy `G (one-click arm64 dmg)` while noting "一键端到端未跑" (end-to-end not run). Neither of the skill's two rounds was run:
- `duo install` from 0.1.103 → 0.1.104 with the app not running;
- the same with the app running and its own updater armed. That updater swaps the bundle from a zip and auto-updates when idle, so collision is a real risk.

**Fix:** the coordinator runs Phase 5 serially and puts the results in 一键安装 and 已知问题 before the row counts as one-click.

### 5. NOTE: there is a canary track too
The matrix shows canary as "—" (not applicable). It exists:
- `manifestService.ts:156-163` resolves canary > beta > release;
- canary is an account-level flag the server sends, which `canaryFlagStore` saves locally;
- `manifest-darwin-arm64-canary.json` currently returns 0.1.108.

**Fix:** document it, and decide ✗ or ○ alongside #3.

### 6. NOTE: the delta-update section can be filled in, and one claim in it is wrong
The doc says the "热更" (hot update) in release notes is mobile-only. But the desktop manifest has an `app.hotfix` entry: `cindy-0.1.104-arm64-hotfix.zip`, 278778019 B, with its own sha256. It's a full-bundle zip, not a binary delta. So the three columns are: client applies a full zip / server sends a full zip / no delta to use.

### 7. NOTE: GitHub releases are a mirror, and there's an assetless `v1.0.0` release
- **`v1.0.0`:** published 2026-07-25, stable, no assets, and it matches `versionPattern`.
- **Its body says:** "官方安装包由官网与官方 CDN 分发并自动更新；本 Release 标记 1.0.0 版本期的开源客户端源码快照" (official installers ship through the official sites and CDN; this release is the open-source source snapshot for the 1.0.0 line).
- **Today it does no harm.** `/releases/latest` is v0.1.104, the assetless fallback walks back past it, and it's outside both page windows.
- **The risk:** GitHub is not the vendor's primary channel. The CDN manifest from #2 is what the app itself reads.
- **Fix:** record this in the audit, and consider making the CDN probe the source for global too, or at least a second way to verify it.

### 8. NOTE: smaller doc gaps
- **Homebrew is "没查" (not checked).** `brew info --cask cindy` returns "No Cask with this name exists". Mark it "—".
- **`CHANNEL_COVERAGE_TODO.md` was not updated.** The skill requires an update for any channel gap; Cindy isn't mentioned there.
- **The commit message has the false "Intel detection-only" statement and the "VendorProbe ✗" reasoning.** The follow-up commit should say these were corrected.

**What I downloaded** (all checked against API digests, mounted read-only, then detached; nothing launched or installed): the beta 0.1.108 arm64 global dmg and the 0.1.104 x64 global dmg. They're in the review scratch folder, along with the API and CDN responses.
