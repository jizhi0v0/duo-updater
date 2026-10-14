# Cindy (makecindy/cindy) — onboarding plan for duo-updater

Planner run: 2026-10-14. All "measured" facts below come from the real GitHub API,
real dmgs downloaded into `scr/dl/`, and real CDN responses saved under `scr/feeds/`.
Anything I did **not** execute is marked **(prediction — not run)**.

Repo HEAD at plan time: `7bccb0b` (main). Nothing for Cindy exists in the repo:
`grep -rn "com\.xd\.\|makecindy\|hotfix\.cindy" DuoUpdaterCore/Sources docs/app-audits CHANNEL_COVERAGE_TODO.md` → empty.
No Homebrew cask (`brew info --cask cindy` → "No Cask with this name exists"; no cask in
`formulae.brew.sh/api/cask.json` names `makecindy`, `com.xd.cindy` or `cindy.app`).

---

## 0. Evidence summary (what the rest of the plan relies on)

### 0.1 Product shape (settled from source, `makecindy/cindy@main`)
- Electron **Forge** app (`apps/desktop/forge.config.ts`; makers `MakerZIP` for darwin + dmg built by the
  release pipeline). **No Sparkle, no electron-builder `app-update.yml`.**
- Two **editions** are chosen at build time (`VITE_CINDY_AUTH_REGION`), and they can be installed side by side
  (`packages/maker-shared/src/brandIdentity.ts`, `appIdByRegion`):
  - `global` → bundle id **`com.xd.cindy`**, userData dir `CindyGlobal`
  - `cn` → bundle id **`com.xd.cindycn`**, userData dir `Cindy`
  - `dev` → `com.xd.cindydev`, `CindyDev.app` (internal build target, never published; see 1.5)
  - Both shipping editions name the bundle `Cindy.app` (same file name since 2026-07-26, commit `75baac1ee`;
    before that global was `CindyGlobal.app`). **No GitHub release predates that change**, because the first one is
    v0.1.17 from 2026-07-27.
- Own updater (`apps/desktop/src/main/manifestService.ts`, `updateService.ts`, `updateScriptMacOS.ts`):
  - reads `${cdnBaseUrl}/manifest-${process.platform}-${process.arch}${suffix}.json`, suffix `""` / `-beta` / `-canary`;
  - `cdnBaseUrl` comes from `https://hotfix.cindy.app/cindy/endpoint.json` (global) /
    `https://hotfix.cindy.com.cn/cindy/endpoint.json` (cn), both answering `"cdnBaseUrl": "https://hotfix.cindy.{app|com.cn}/cindy"`
    (bases read from the 0.1.104 global `app.asar`: `ENDPOINT_MANIFEST_BASE_URL=…"https://hotfix.cindy.app/cindy"`,
    `ENDPOINT_MANIFEST_PEER_BASE_URL=…"https://hotfix.cindy.com.cn/cindy"`);
  - downloads `app.hotfix` (a **full** `.app` zip, ~279 MB, not a delta), stages it in userData, and on relaunch runs a
    detached bash script that does `rm -rf <app>; mv <extracted>.app <app>` (no on-disk version check in the script);
  - channel = `canary > beta > release`: beta from `<userData>/update-channel-settings.json`
    (`enableBeta`, or `orgDefaultEnableBeta` when the user never touched the switch), canary from
    `<userData>/canary-flag.json` (`{"canary":true}`, written from a per-account server feature flag).
- Release notes in the app come from `${cdnBaseUrl}/notice/${platform}-${arch}/{version}.json`
  (`apps/desktop/src/main/releaseNotesService.ts`).

### 0.2 GitHub releases (measured, `gh api repos/makecindy/cindy/releases --paginate`, 2026-10-14)
- 65 releases. `/releases/latest` → **`v0.1.104`** (2026-10-12T04:56:47Z).
- Stable tags `vX.Y.Z` (`prerelease:false`); beta tags `vX.Y.Z-beta` (`prerelease:true`), **every** `-beta` is flagged and
  no non-beta is flagged. Newest beta: `v0.1.108-beta` (2026-10-14).
- Extra tags without a release (`v0.1.104-beta`, `v0.1.57`, …) exist. They are not releases and the source never sees them.
- **`v1.0.0`** (2026-07-25, `prerelease:false`, **zero assets**, body: "this release marks the open-source client
  source snapshot for the 1.0.0 line"). It is the oldest release, and its tag shape matches `^v\d+\.\d+\.\d+$`.
- macOS assets per release: `cindy-<ver>-darwin-{arm64,x64}-{global,cn}.dmg` (plus `win32-x64-*.exe` and, since 0.1.64,
  `linux-x64-*.deb`). No zip and no `latest-mac.yml`. **No universal build.**
- Partial release: **`v0.1.52`** ships only `cindy-0.1.52-darwin-arm64-global.dmg` (no cn, no x64).
- Promotion: `v0.1.58` and `v0.1.58-beta` carry **byte-identical** assets (same GitHub `digest` for all six), so
  beta and stable share one version-number space and a beta build can be promoted unchanged.
- Every asset checked carries a GitHub `digest` (`sha256:…`), including v0.1.17 (uploaded July 2026).

### 0.3 Real packages (measured with `.claude/skills/coverage-discovery/scripts/check-bundle.sh`, mounted read-only)

| dmg (in `scr/dl/`) | CFBundleIdentifier | short = build | arch | Team | codesign `--deep --strict` | spctl |
|---|---|---|---|---|---|---|
| v0.1.104/…-darwin-arm64-global.dmg | `com.xd.cindy` | 0.1.104 | arm64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.104/…-darwin-x64-global.dmg | `com.xd.cindy` | 0.1.104 | x86_64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.104/…-darwin-arm64-cn.dmg | `com.xd.cindycn` | 0.1.104 | arm64 | NTC4BJ542G | 0 | Notarized Developer ID |
| v0.1.103/…-darwin-arm64-global.dmg | `com.xd.cindy` | 0.1.103 | arm64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.103/…-darwin-arm64-cn.dmg | `com.xd.cindycn` | 0.1.103 | arm64 | NTC4BJ542G | 0 | Notarized Developer ID |
| v0.1.108-beta/…-darwin-arm64-global.dmg | `com.xd.cindy` | **0.1.108** (bare, no `-beta`) | arm64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.58/…-darwin-x64-global.dmg | `com.xd.cindy` | 0.1.58 | x86_64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.17/…-darwin-arm64-global.dmg | `com.xd.cindy` | 0.1.17 | arm64 | SX9RG894L5 | 0 | Notarized Developer ID |
| v0.1.17/…-darwin-arm64-cn.dmg | `com.xd.cindycn` | 0.1.17 | arm64 | NTC4BJ542G | 0 | Notarized Developer ID |

- Every downloaded dmg's `shasum -a 256` equals the GitHub `digest` of that asset.
- Signing authority (`codesign -dvv`, 0.1.104): global `Developer ID Application: XD Entertainment Pte Ltd (SX9RG894L5)`,
  cn `Developer ID Application: X.D. Network Inc. (NTC4BJ542G)`. `xcrun stapler validate` passes on both.
  **The two editions are signed by different Teams**, and each edition's Team is unchanged from 0.1.17 through 0.1.108.
- `LSMinimumSystemVersion` = `12.0` on every sampled build. No `SUFeedURL` on any.
- Nested apps (all four in every build): `Contents/Frameworks/Cindy Helper{, (GPU), (Plugin), (Renderer)}.app`, id
  `<bundle id>.helper`, `LSUIElement=true`. These are standard Electron child-process helpers. No `Contents/Library`
  (no LoginItems / LaunchAgents / LaunchDaemons). `Contents/Resources/tools/{agent-island,computer-permission-guide,remote-desktop,ripgrep}`
  and `Resources/cli/cindy` are plain executables, not bundles.
- Desktop-main code search (`repo:makecindy/cindy path:apps/desktop/src/main`): `LaunchAgents` 0 hits, `SMAppService` 0;
  `launchctl` is used only for `launchctl print` (env snapshot); `setLoginItemSettings` = "open the main app at login" toggle;
  the `cc-mgr` daemon (`maker-host/cc-manager-client.ts`) is spawned on **remote SSH hosts**, not locally.
- `application-test feed-discover` (built with `--scratch-path` outside the clone) on 0.1.104 global, 0.1.104 cn, 0.1.17 global:
  `Cindy [com.xd.cindy] 0.1.104 — no Sparkle and no electron-builder update config` (same verdict for the other two) → `noKnownUpdater`.

### 0.4 CDN (the app's own update track) vs GitHub (measured 2026-10-14)
`curl "https://hotfix.cindy.{app,com.cn}/cindy/manifest-darwin-{arm64,x64}{,-beta,-canary}.json"` → all 12 HTTP 200:

| manifest | app.version | installer.sha256 vs GitHub digest |
|---|---|---|
| global arm64 / x64 (release) | 0.1.104 | **equal** to `cindy-0.1.104-darwin-{arm64,x64}-global.dmg` |
| cn arm64 / x64 (release) | 0.1.104 | **equal** to `cindy-0.1.104-darwin-{arm64,x64}-cn.dmg` |
| global / cn arm64 / x64 `-beta` | 0.1.108 | **equal** to the `v0.1.108-beta` dmgs |
| `-canary` (all four) | 0.1.108 | identical to `-beta` today |

So GitHub `/releases/latest` serves the **same bytes** the app's own stable updater installs. The manifest has no device id
and no per-device bucketing. `app.releaseNotes` is empty in every manifest.

### 0.5 Changelog sources (measured)
- **GitHub release bodies**: `Desktop release X` / `## 更新说明` / `### <emoji> title` + one prose paragraph each, optional
  `## PRs` (links), then a `---` footer of **7 bullets** (`- commit:`, `- source tag:`, `- regions:`, 4 × iOS/Android build ids).
  Chinese only. About half the stable releases (0.1.21–0.1.86, among others) have **no `## PRs` heading**, so the footer sits
  under the last content heading.
  **(prediction — not run)** From reading `GitHubMarkdownParser`: the strict bullet pass takes only `-` bullets and does not
  skip `## PRs`, so the GitHub source's structured log for every recent release is the 7 footer bullets and nothing else.
  `skipSections: ["PRs"]` cannot fix the releases without a `## PRs` heading, and the prose pass caps at 12 lines
  (v0.1.97 has 13). **So the `.gitHubReleases` recipe route is rejected.**
- **CDN notices** `https://hotfix.cindy.{app|com.cn}/cindy/notice/darwin-arm64/{version}.json`: JSON keys
  `version, date, githash, contributors, intro, topics[{id,emoji,title,text,contributors}], contentByLocale{zh-CN,en,ja,ko}`.
  Top-level `topics` is the zh-CN copy. darwin-x64 notices are byte-identical to darwin-arm64.
  Swept the 45 newest versions in `index.json` for both hosts (90 files): all carry `topics` and `contentByLocale.en` with the
  same topic count (1–22). One quirk: cn `0.1.106` has no `intro`. `0.1.17` uses an older `sections` schema, which does not
  matter because the recipe fetches only the offered version. The two editions' notices differ in wording.
  No `<`, `&…;` or `<` in any notice text.
- Regexes in Step 4 were validated with Python (`re.S|re.I`, named groups converted) over all 90 files: one entry per file,
  version equals `d["version"]`, and the extracted titles and texts, after JSON-unescape, **equal** `contentByLocale.en.topics`
  (en variant) and `topics` (zh variant) exactly. Script: `scratchpad/tools/rx2.py`, output `en ok 90 bad []`, `zh ok 90 bad []`.

---

## 1. Coverage checklist

Legend: **D** = detection, **1C** = one-click install, **CL** = changelog.

### 1.1 Global edition, stable — `com.xd.cindy` (arm64 and x64 dmgs)
- Signing: Developer ID `XD Entertainment Pte Ltd (SX9RG894L5)`, notarized + stapled, hardened runtime; Team constant 0.1.17→0.1.108.
- **D**: `GitHubReleaseRule` on `makecindy/cindy`, `/releases/latest`, tag `^v([0-9]+\.[0-9]+\.[0-9]+)$`.
  Tag version == `CFBundleShortVersionString` == `CFBundleVersion` (measured on 0.1.17/0.1.58/0.1.103/0.1.104). The generic
  sources do not answer (no cask, no `SUFeedURL`, no `app-update.yml`; feed-discover `noKnownUpdater`).
- **1C**: yes. `installAssetPattern` `^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$`, `.dmg`.
  The arch-aware picker (`HostArch.assetTokens`: `arm64` / `x64`) chooses the host's dmg. GitHub `digest` is passed on
  automatically (#1019). Status stays **需要验证** until the serial e2e (Boundaries B3).
- **CL**: `ChangelogRecipe` over the CDN notice JSON (`hotfix.cindy.app`, `contentByLocale.en`, title → heading, text → note),
  per version via `sourceTemplate`.
- "读的是": 人人可手动下载的 GA (public GitHub asset, the same bytes as the stable CDN manifest's installer).

### 1.2 CN edition, stable — `com.xd.cindycn` (arm64 and x64 dmgs)
- Signing: Developer ID `X.D. Network Inc. (NTC4BJ542G)`, notarized + stapled; Team constant 0.1.17→0.1.104.
- **D**: second `GitHubReleaseRule`, same repo and tag pattern.
- **1C**: yes, pattern `^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-cn\.dmg$`. **Critical:** each edition's pattern must
  refuse the other edition's dmg. The Team gate would refuse a cross-edition dmg anyway (different Team), but the pattern
  must not rely on that. Status 需要验证 (B3).
- **CL**: `ChangelogRecipe`, same shape, host `hotfix.cindy.com.cn` (its own wording).

### 1.3 Beta track — same two bundle ids (Pattern B, preference-switched)
- Packages: `vX.Y.Z-beta` prereleases, same Teams, notarized. **Info.plist carries the bare `X.Y.Z`** (0.1.108 measured), so
  no version suffix, display name or bundle-id signal exists. The only local signal is
  `~/Library/Application Support/{CindyGlobal|Cindy}/update-channel-settings.json`
  (`enableBeta`, else `orgDefaultEnableBeta`). The schema is settled from `updateChannelStore.ts` +
  `override-settings-file.ts`, but **not observed on a real machine**.
- **D**: **not implemented**. A beta install is treated as stable. Consequence: while the beta is ahead
  (installed 0.1.108 > stable 0.1.104), the stable rule says "up to date" and offers no downgrade. Once stable passes it,
  a stable build is offered (a higher number, never a downgrade). Future route: a `ChannelBinding` reading that JSON, plus a
  `.beta` `GitHubReleaseRule` (`usePrereleases: true`, tag `^v([0-9]+\.[0-9]+\.[0-9]+)-beta$`). Record in
  `CHANNEL_COVERAGE_TODO.md` §2b and stop there (B1).
- **1C / CL**: none for beta. The CL recipe has `channel: nil`, so a beta install showing as stable still gets the notice for
  whatever version is offered.

### 1.4 Canary track — same ids (Pattern D for us)
- Per-account server flag mirrored to `<userData>/canary-flag.json`. Published only as CDN `manifest-…-canary.json`; no
  GitHub release. Today it is identical to beta (0.1.108).
- **D / 1C / CL**: none. Record only (B1).

### 1.5 Identities that are not shipped from the repo
- `com.xd.cindydev` / `CindyDev.app`: the internal `dev` build target. No GitHub asset name across 65 releases carries it
  (asset names are only `-global` / `-cn`). Not covered; record.
- Pre-fork **`xdt-maker`** predecessor: `brandIdentity.ts` says that channel was frozen at the 2026-07-17 identity flip and
  "stays on the frozen channel"; only legacy schemes, userData dirs and DB prefixes are kept. Its macOS bundle id **does not
  appear in the public source** (code search for `com.xd.xdt`, `com.xd.maker`, `legacyBundleId`: 0 hits), and it was never
  released on GitHub. No package exists to inspect, so: out of scope, no `BundleIDMigration`, record the fact. **No in-repo
  rename** exists between shipped Cindy builds: `com.xd.cindy` / `com.xd.cindycn` are the same from 0.1.17 to 0.1.108.

### 1.6 Old versions
- No Cindy build ever declared a feed (`SUFeedURL` absent on 0.1.17, 0.1.58, 0.1.103, 0.1.104, 0.1.108). The CDN manifest
  mechanism is compiled in for all of them, so old copies need nothing beyond the same GitHub rule.
- The oldest public copy, 0.1.17, has the same bundle id and Team, so it should get `UPDATE → 0.1.104` and the one-click Team
  gate should pass **(prediction — channel-verify in Step 7 confirms D)**.

### 1.7 Architectures
- Separate arm64 / x64 dmgs per edition. `0.1.52` shipped arm64-global only, so a cn or x64 rule walks back past it
  (`maxReleasesWithoutMacOSAsset` = 5) and offers 0.1.51 to those hosts. That is correct: there was no cn/x64 0.1.52 on GitHub.
- An x64 copy run under Rosetta on Apple silicon gets the arm64 dmg from duo (host-arch preference), while Cindy's own updater
  would keep x64 (`process.arch`). Known behaviour difference; record only.
- No OS-split tracks: the manifest has no min/max fields, and `LSMinimumSystemVersion` is a constant `12.0`.

### 1.8 Resident helpers and the app's own updater
- The four Electron helpers are children of the main process. Cindy's own swap script kills stragglers under the bundle path
  before swapping. No login item, LaunchAgent or daemon is installed locally (0.3).
- **Self-updater collision (settled from source, not observed):** `executeRelaunch()` compares the staged hotfix against
  `app.getVersion()` of the **running** process, and the bash script swaps without reading the on-disk version. If a running
  old copy has a staged hotfix and duo then installs a **newer** bundle, clicking Cindy's "relaunch" (or the idle
  auto-relaunch) before `duo restart` puts the staged, older build back. A freshly started process discards a staged patch
  that is not newer (`compareAppUpdateVersions`, startup path), so `duo restart` itself is safe. This must be measured in
  e2e round 2 (B3) and written in the audit's 已知问题.

### 1.9 Delta / rollout (Phase 3⅞ table for the audit doc)
| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 增量 | 无（hotfix 是整 .app zip，`updateScriptMacOS.ts` 只做整包替换） | 无（manifest 只给整 zip 与 dmg，2026-10-14） | 不需要 |
| 按设备灰度 | 有：canary 按账号 feature flag | 稳定 manifest 不带设备参数；canary 与 beta 当前同版本 | 不消费（不接 canary） |
| 按架构/OS 分轨 | 按 `platform-arch` 分 manifest | arm64/x64 各一份；无 min/max | GitHub 规则的架构偏好已覆盖 |
| 自更新器抢 | 有（见 1.8） | — | 需 e2e 第二轮实测 |

---

## 2. Steps (executor, in order)

Work in your fresh clone on a new branch from `origin/main`. Keep downloads in your own `SCR=$(mktemp -d "$TMPDIR/recipe-cindy.XXXX")`.
Follow `.claude/skills/app-audit/SKILL.md` and `.claude/skills/fragile-recipe/SKILL.md`. Worked example: `git show 21047ba`.

**Step 1 — Re-fetch the evidence packages** (no install, no launch):
```
https://github.com/makecindy/cindy/releases/download/v0.1.104/cindy-0.1.104-darwin-arm64-global.dmg   (sha256 9e8ac572…eaeb)
https://github.com/makecindy/cindy/releases/download/v0.1.104/cindy-0.1.104-darwin-arm64-cn.dmg       (sha256 8f0704e3…6331)
https://github.com/makecindy/cindy/releases/download/v0.1.103/cindy-0.1.103-darwin-arm64-global.dmg   (sha256 8807cf8f…225a)
https://github.com/makecindy/cindy/releases/download/v0.1.103/cindy-0.1.103-darwin-arm64-cn.dmg       (sha256 a75a4c72…861a)
https://github.com/makecindy/cindy/releases/download/v0.1.108-beta/cindy-0.1.108-darwin-arm64-global.dmg (sha256 81a09b2d…70e6)
https://github.com/makecindy/cindy/releases/download/v0.1.17/cindy-0.1.17-darwin-arm64-global.dmg     (sha256 cceca5b9…9a0a)
https://github.com/makecindy/cindy/releases/download/v0.1.104/cindy-0.1.104-darwin-x64-global.dmg     (sha256 826a807d…2909)
```
(~300 MB each. If the planner's copies are still present, they are under `…/cindy-pipeB-1/scr/dl/<tag>/` and match these digests.)
Then re-run `.claude/skills/coverage-discovery/scripts/check-bundle.sh` on them and confirm table 0.3 yourself. If
`gh api repos/makecindy/cindy/releases/latest -q .tag_name` has moved past `v0.1.104`, use the new latest and its predecessor.

**Step 2 — Family `Recipes/com-xd-cindy.swift`** (new file; enum `com_xd_cindy`; `changelogs:` before `githubRules:` as in
`com-obelisk-app.swift`). The comment states the **contract only** (no dated measurements; `check_recipe_snapshots.py`) and
starts with `// History: docs/app-audits/com-xd-cindy.md#历史与实测`. It covers: Forge app, no Sparkle/app-update.yml,
own CDN updater that serves the same bytes as the GitHub assets; two editions with different Teams; tag == short == build;
`-beta` tags are prereleases with a bare-version plist (why the tag is anchored); assetless `v1.0.0` snapshot release (why the
asset pattern is what keeps it out); partial releases such as `0.1.52`; why notes come from the CDN notice and not from the
release body (the `---` footer of build ids); English chosen as in `com-kimi-code-desktop`.
```swift
ChangelogRecipe(
    bundleID: "com.xd.cindy",
    source: URL(string: "https://hotfix.cindy.app/cindy/notice/darwin-arm64/index.json")!,
    entryPattern: #""version"\s*:\s*"(?<version>[0-9]+\.[0-9]+\.[0-9]+)"\s*,\s*"date"\s*:\s*"(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})".*?"contentByLocale"\s*:\s*\{.*?"en"\s*:\s*\{[^{}]*?"topics"\s*:\s*\[(?<body>(?:[^\[\]]|\[[^\[\]]*\])*)\]"#,
    itemPatterns: [#""text"\s*:\s*"(?<item>(?:[^"\\]|\\.)*)""#],
    mode: .json,
    stripTags: false,          // plain-text notes; keep decodeEntities = true (it gates the JSON unescape)
    maxEntries: 1,
    sourceTemplate: "https://hotfix.cindy.app/cindy/notice/darwin-arm64/{version}.json",
    headingPattern: #""title"\s*:\s*"(?<heading>(?:[^"\\]|\\.)*)""#),
```
```swift
GitHubReleaseRule(
    bundleID: "com.xd.cindy",
    owner: "makecindy", repo: "cindy",
    versionPattern: #"^v([0-9]+\.[0-9]+\.[0-9]+)$"#,
    installAssetPattern: #"^cindy-[0-9]+\.[0-9]+\.[0-9]+-darwin-(?:arm64|x64)-global\.dmg$"#,
    installerKind: .dmg),
```
Before committing, run the same regexes once more over the live `0.1.104.json` with a throwaway Python snippet
(the Swift regex engine is NSRegularExpression; the Python check in 0.5 was an approximation).

**Step 3 — Family `Recipes/com-xd-cindycn.swift`** (enum `com_xd_cindycn`). Same two entries with
`bundleID: "com.xd.cindycn"`, host `hotfix.cindy.com.cn` in `source` and `sourceTemplate`, asset pattern ending `-cn\.dmg$`.
Its comment says only what differs (Team NTC4BJ542G, cn host) and points to `Recipes/com-xd-cindy.swift` for the shared
rationale, as the storytold families do. **No `// History:` line here**: `check_app_audits.py` requires a family's
pointer to name `<family>.md`, and this family has no doc of its own.

**Step 4 — Register** `com_xd_cindy.set,` and `com_xd_cindycn.set,` in `AppRecipeIndex.all`, in slug order.

**Step 5 — Tests** (offline):
- New `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/CindyGitHubRuleTests.swift`, modelled on `StorytoldCraftGitHubRuleTests`:
  1. both rules exist; owner `makecindy`, repo `cindy`, `.stable`, `!usePrereleases`, `.dmg`;
  2. tag: `v0.1.104` → `0.1.104`; `v0.1.108-beta` → nil;
  3. global pattern matches `cindy-0.1.104-darwin-arm64-global.dmg` and `…-x64-global.dmg`, and rejects `…-arm64-cn.dmg`,
     `…-x64-cn.dmg`, `cindy-0.1.104-linux-x64-global.deb`, `cindy-0.1.104-win32-x64-global.exe`. Mirror for cn;
  4. arch pick via `GitHubReleaseRule.installableAsset(from:matching:preferring:allowingIntelTranslation:)` on the real
     8-asset listing: `.arm64` → the arm64 dmg, `.x86_64` → the x64 dmg, for each edition;
  5. replay through the source, as the storytold test does: a listing `[v0.1.108-beta (prerelease), v0.1.104, v0.1.103, …, v1.0.0 (no assets)]`
     answers `0.1.104` for both editions, and a `/releases/latest` that returns the assetless `v1.0.0` walks back to
     `0.1.104` (never offers `1.0.0`); a newest release shaped like `v0.1.52` (arm64-global only) makes the cn rule
     answer the previous release.
- `ChangelogExtractorTests`: a fixture test on a **trimmed real** notice (e.g. global `0.1.104.json` cut to 2 topics in both
  `topics` and `contentByLocale.en`, keeping one en `text` with an escaped `\"…\"` and the per-topic `"contributors": [...]`
  arrays). Assert version `0.1.104`, date `2026-10-12`, the en titles as `.heading` blocks interleaved with the en texts as
  notes (unescaped quotes), and that **no zh-CN text** leaks in. Add one fixture shaped like cn `0.1.106` (no `intro`).

**Step 6 — Goldens**:
`DUO_RECORD_RECIPE_GOLDENS=1 swift test --package-path DuoUpdaterCore --filter RecipeGoldenTests` (fails on purpose), read
`git diff DuoUpdaterCore/Tests/RecipeGoldens` (two new files only), rerun without the variable and expect a pass.

**Step 7 — Real-package verification** (`application-test`; mounts read-only, installs nothing):
```
swift run --package-path application-test channel-verify <0.1.104 arm64 global dmg> --expect stable   # expect: GitHub, latest 0.1.104, up to date
swift run --package-path application-test channel-verify <0.1.103 arm64 global dmg> --expect stable   # expect: UPDATE → 0.1.104
swift run --package-path application-test channel-verify <0.1.17  arm64 global dmg> --expect stable   # expect: UPDATE → 0.1.104
swift run --package-path application-test channel-verify <0.1.104 arm64 cn dmg>     --expect stable   # expect: up to date
swift run --package-path application-test channel-verify <0.1.103 arm64 cn dmg>     --expect stable   # expect: UPDATE → 0.1.104
swift run --package-path application-test channel-verify <0.1.108-beta arm64 global dmg> --expect stable  # expect: detected stable, latest 0.1.104, NO update (documents the beta blind spot)
swift run --package-path application-test channel-verify <0.1.104 x64 global dmg>   --expect stable   # identity + Team only
swift run --package-path application-test feed-discover  <0.1.104 arm64 global dmg>                    # expect: no Sparkle and no electron-builder update config
```
Paste the raw lines into the audit doc. The `changelog pane` line must say **`recipe`** with headings (the en topic titles)
for both editions. If it says `source structured` with items like ``commit: `…` `` or `regions: cn global`, the recipe did not
load or did not parse. Fix that; do not ship it.

**Step 8 — Audit doc `docs/app-audits/com-xd-cindy.md`** (one doc for both editions, as the storytold doc does). Use the
§ Report template verbatim, including the `观测版本` wording. Content: basic info for both editions (bundle ids, Teams +
authority names, observed versions 0.1.104 / beta 0.1.108); coverage matrix (stable: GitHub ✓, beta ✗/○, canary ✗); Channel
详情 (sections 1.3/1.4 with the on-disk switch files named generically as `~/Library/Application Support/<userData>/…`, no
machine state); 更新检测 (anchors, v1.0.0, 0.1.52, promotion); the delta table from 1.9; Changelog (CDN notice, en,
`changelog pane` raw line, why not the GitHub body); 一键安装 (状态 **需要验证**, 端到端 **未跑** with the reason "dispatched
agent may not use the duo CLI or write /Applications; left for the serial e2e", format, digest, 读的是 = 人人可手动下载的 GA,
the per-edition Team note); 已知问题 (self-updater collision 1.8, Rosetta x64→arm64 1.7, GitHub-body structured log is
footer junk if the recipe fails, beta blind spot); 如何复验 (Step 7 commands + raw output); 建议下一步 (B1/B5 items); and
**`## 历史与实测`** holding the dated measurements from section 0 of this plan (digest equality CDN↔GitHub, the 90-notice
sweep, the bullet/prose counts). Write it for a public repo (§ Writing for a public repo): no `/Users/…` paths, no
"本机", nothing about which channel any machine runs.

**Step 9 — Index lines**: two rows in `docs/app-audits/README.md` under **`## Single-channel — GitHub Releases`**, shaped like
the storytold rows, both linking `com-xd-cindy.md`: `Cindy` · `com.xd.cindy` and `Cindy CN` · `com.xd.cindycn`; each says
"G (one-click dmg, 需要验证) · changelog: CDN notice recipe (en) · beta/canary 未接入 · 2026-10-14". Keep them to app,
link, coverage and date.

**Step 10 — `CHANNEL_COVERAGE_TODO.md` §2b**: add an unchecked entry **Cindy** · `com.xd.cindy` / `com.xd.cindycn`: beta is a
device switch in `<userData>/update-channel-settings.json` (`enableBeta` / `orgDefaultEnableBeta`, from source, needs real-machine
diff); canary is a per-account server flag in `canary-flag.json` that maps to CDN-only manifests (no GitHub release); plist
version is bare; GitHub `-beta` prereleases exist for a future `.beta` rule.

**Step 11 — Gate**: `make test` in the foreground with a generous timeout, judged by **exit code**. Paste the command and
the tail of its output. Fix anything it trips (`check_app_audits.py`, `check_recipe_snapshots.py`, `check_prose_claims.py`,
`AppAuditCoverageTests`, goldens).

**Step 12 — Commit** with `git commit -F <msgfile>` (no push, no PR). The message lists the three counts: detection ✓
(channel-verify lines), one-click wired but e2e not run, changelog ✓ structured with headings (pane line).

---

## 3. Boundaries

**B1 — Out of scope for this change (record only):**
- No `ChannelBinding` / beta rule / canary probe. Beta needs the userData JSON confirmed on a real machine first, and
  canary has no GitHub release.
- No `VendorProbeRecipe` on `manifest-darwin-*.json`. `GitHubReleasesSource` sits ahead of `VendorProbeSource` in
  `SourceStack`, so a stable probe would be dead code that looks alive.
- No `.gitHubReleases` ChangelogRecipe and no `skipSections` workaround (0.5).
- No `BundleIDMigration` entry. There is no rename between shipped builds, and the `xdt-maker` predecessor's id is unknown.
- No coverage for `com.xd.cindydev` or Windows/Linux artifacts.
- No `hostRequirement` or other fields not listed in Step 2/3. Don't add a hand-wired checksum: the GitHub digest is
  already passed through.

**B2 — Forbidden for the executor:** `make install`, `make cli`, the `duo` CLI (including `duo verify`), `pkill`/`killall`,
`git stash`, `git push`, PRs/issues, writing into `/Applications` or `~/Applications`, launching or opening any downloaded
package, touching quarantine xattrs, anything that pops system UI. Mount dmgs only read-only and detach them. Don't edit
`verify/baseline.json` (bot-maintained). Don't put dated measurements in recipe comments.

**B3 — Stays "需要验证" until a serial run on a real machine** (orchestrator/user, `coverage-discovery` Phase 5, one app at a time):
- One-click for **both** editions: install 0.1.103 (global; then cn) into `/Applications`, `duo check Cindy`,
  `duo install Cindy --yes`, then check version, Team (SX9RG894L5 / NTC4BJ542G), `codesign --verify --deep --strict`, `spctl`,
  inode change, `duo backups`. Because both editions are named `Cindy.app`, run them **one after the other**, never both
  present, and use `mdfind "kMDItemCFBundleIdentifier == 'com.xd.cindy*'"` first so no real install is overwritten.
- Round 2, self-updater collision: launch 0.1.103 and let Cindy stage its hotfix (a `.zip` under
  `~/Library/Application Support/CindyGlobal/updates/`). Make the staged build **older** than the one duo installs (for example
  stage 0.1.103→0.1.104 and have duo install a newer one, or point the app at a local manifest via `XDT_CDN_BASE_URL`, which
  `manifestService.getBaseUrl()` honours). Then `duo install`, trigger Cindy's own relaunch **before** `duo restart`, and
  watch the on-disk version for ~10 s. Also run `duo restart Cindy` on its own and confirm the started process discards the
  stale patch.
- After quitting: `pgrep -fl "/Applications/Cindy.app/"` must be empty. This confirms no `tools/*` or helper process
  outlives the app, which is a claim from source only.
- Intel host or Rosetta behaviour of the arch pick (1.7): untested.

**B4 — Core changes noticed: record them, don't make them.**
- `GitHubMarkdownParser` cannot drop a trailing `---` footer, and its default skip keywords do not cover `## PRs`, so
  Cindy's GitHub-sourced structured log is build-id bullets **(prediction — not run)**. A per-recipe or per-rule "cut body at
  the first thematic break" option (in the spirit of `firstLanguage(of:)`) would fix it. It is a parser change with a
  `parserGeneration` bump, so record it in the audit's 建议下一步 and do **not** implement it here.
- Changelog language is hard-wired per recipe (en). A locale-aware notice selection would be new machinery. Record only.

**B5 — Judgement calls to surface in the report, not decide silently:**
- en vs zh-CN for the notice recipe. The plan picks en, following the Kimi precedent; the zh regex is validated too
  (drop the `contentByLocale … "en"` part of `entryPattern`).
- The beta blind spot (1.3) means a beta user can be offered the next stable build ahead of their beta track's newest build.
  That is acceptable for now because it is never a downgrade. Say so in the report.
