---
name: app-audit
description: >-
  Audit one app's full integration status in duo-updater — distribution sources,
  release channels, update detection, changelog, one-click install. If already
  integrated, output a structured report and persist it. If not, investigate the
  app's landscape and update mechanisms, stopping at every uncertain point to ask
  the user (who can assist with packet capture, plist inspection, etc.). Trigger
  phrases: "audit X", "what do we have for X", "how is X integrated", "add
  support for X", "can we detect updates for X", or naming an app when the intent
  is to understand or extend its coverage.
---

# App audit skill

Given **one app name** (or bundle ID), produce a full picture of its integration
in duo-updater — or investigate what integration is possible — then **persist the
result** as a per-app document.

## The two orthogonal dimensions

Every app sits at the intersection of two independent axes. The audit must cover
both; confusing them leads to wrong decisions.

### Axis 1: Distribution source (发布渠道) — WHERE the app comes from

How the user obtained the binary, and therefore how updates reach them:

| Source | Detection signal | Update mechanism |
|--------|-----------------|------------------|
| **Sparkle** (direct download) | `SUFeedURL` in Info.plist | Appcast XML; app can self-update |
| **Homebrew cask** | `brew list --cask` (unreliable — many direct-download apps also have a cask) | `brew upgrade`; but `auto_updates` casks self-update and brew just tracks |
| **Mac App Store** | `kMDItemAppStoreHasReceipt` / `_MASReceipt/receipt` | MAS native update; sandboxed |
| **TestFlight** | TestFlight container / receipt | TestFlight beta builds |
| **JetBrains Toolbox** | `.managed` marker / Toolbox manifest | Toolbox's own update pipeline |
| **GitHub Releases** | No plist signal; manually mapped via `GitHubReleaseRule` | Check releases API |
| **Vendor endpoint** | No plist signal; manually mapped via `VendorProbeRecipe` | Probe a vendor URL |

**The same bundle ID can arrive through multiple distribution sources.** A user
might install Firefox via direct download (has Sparkle) or via MAS (sandboxed,
no Sparkle). The app's bundle ID is `org.mozilla.firefox` either way, but the
update path differs completely.

`UpdateChecker` resolves this with a **priority chain** — it tries sources in
order and the first that returns a version wins. The audit should document which
source actually answers and why.

### Axis 2: Release channel — WHICH quality track

The version maturity track the user is following:

| Channel | Examples |
|---------|---------|
| stable | Production release |
| beta | Chrome Beta, Firefox Beta, OrbStack Beta |
| dev | Chrome Dev, Warp Dev |
| canary | Chrome Canary, Discord Canary |
| nightly | Firefox Nightly, Element Nightly |
| preview | Warp Preview, VS Code Insiders |
| ptb | Discord PTB |
| alpha | HBuilderX Alpha |
| esr | Firefox ESR |

**The same bundle ID can serve multiple channels.** Fork stable and Fork beta
share `com.DanPristupov.Fork` — the channel is determined by a user preference,
not the bundle ID. OrbStack stable/beta/canary all share `dev.kdrag0n.MacVirt`.

This creates a 2D matrix per app:

```
                  distribution source
                  Sparkle  Homebrew  MAS  GitHub  Vendor
channel
  stable            ✓        ✓       ✓     —       —
  beta              ✓(feed2) —       —     —       —
  canary            —        —       —     —       —
```

The audit fills in this matrix.

### How the axes interact

The axes combine in four ways. Understanding which pattern an app follows is the
first question the audit answers:

| Pattern | Same bundle ID? | Distribution source changes? | Example |
|---------|-----------------|------------------------------|---------|
| **A. Independent installs** | No — each channel has its own bundle ID | Each has its own sources | Chrome: `com.google.Chrome` / `.canary` / `.beta` |
| **B. Same ID, preference-switched** | Yes | Source is the same, but feed/endpoint varies by channel | Fork: preference → different Sparkle feed |
| **C. Same ID, tag-filtered** | Yes | Same source, same feed; channel filters items | OrbStack: one appcast, `<sparkle:channel>` tags |
| **D. Same ID, undetectable** | Yes | No signal to distinguish | Ghostty tip, Cursor nightly → **BLOCKED** |

Pattern D is a dead end in the current architecture. Don't waste time on it —
document it and move on.

---

## Decision tree

```
1. Is the app installed locally?
   ├─ Yes → read bundle ID, version, plist keys
   └─ No  → ASK: "要我按 app 名搜索，还是你先装一个？"

2. Search the codebase for the bundle ID
   ├─ Found → REPORT MODE (§ Already integrated)
   └─ Not found → INVESTIGATE MODE (§ Not yet integrated)

3. Persist the result (§ Persisting audit results)
```

---

## § Already integrated — structured report

Search these locations for the bundle ID (case-insensitive):

```bash
# All Swift sources + tests
grep -rn "<bundleID>" DuoUpdaterCore/Sources/ --include="*.swift"
grep -rn "<bundleID>" DuoUpdaterCore/Tests/ --include="*.swift"
# Channel coverage doc
grep -n "<app name>\|<bundleID>" CHANNEL_COVERAGE_TODO.md
# Homebrew cask
brew info --cask "<cask-name>" 2>/dev/null
```

Compile findings into the report template (§ Report template).

---

## § Not yet integrated — investigation workflow

**Core principle: stop and ask at every uncertain point.** The user has packet
capture tools and can inspect network traffic — leverage that.

### Phase 0: Identity

First **find** the app — don't assume `/Applications/`:

```bash
# Spotlight finds apps wherever they live (~/Applications, Toolbox dirs, Utilities…)
mdfind "kMDItemDisplayName == '<App Name>'" -onlyin / 2>/dev/null | head -5
# Or by bundle ID if known
mdfind "kMDItemCFBundleIdentifier == '<bundleID>'" 2>/dev/null | head -5
```

Then read identity fields from the actual path:

```bash
mdls -name kMDItemCFBundleIdentifier -name kMDItemVersion "<path>"
defaults read "<path>/Contents/Info" SUFeedURL 2>/dev/null
defaults read "<path>/Contents/Info" KSChannelID 2>/dev/null
codesign -dvvv "<path>" 2>&1 | grep "TeamIdentifier"
```

### Phase 1: Distribution sources — WHERE can users get this app?

**1a. Check all possible sources systematically:**

| Check | Command / method |
|-------|-----------------|
| Sparkle feed? | `defaults read ".../Info" SUFeedURL` — if present, app has built-in auto-update |
| Homebrew cask? | `brew search --cask "<name>"` — also check `auto_updates` flag |
| Mac App Store? | `mas search "<name>"` or check `kMDItemAppStoreHasReceipt` |
| GitHub repo? | Search `github.com/<vendor>/<app>` for macOS release assets |
| Vendor download page? | Check official site for direct download |

**1b. For each source found, note:**
- Does it serve the same version as other sources?
- Are there source-specific quirks? (MAS may lag behind direct download)
- Which source should `UpdateChecker` prefer? (Usually: Sparkle > MAS > Homebrew > GitHub > VendorProbe)

**1c. The `auto_updates` trap:**
If the Homebrew cask has `auto_updates: true`, `HomebrewCaskSource` returns nil —
the app **falls through** to the next source in the priority chain. This means:
- Having a cask ≠ having detection. The cask is metadata, not an update channel.
- You MUST confirm another source (Sparkle / GitHub / VendorProbe) answers,
  otherwise the app lands on "unknown".
- Check: `brew info --cask "<name>" | grep auto_updates`
- Common pattern: Electron apps self-update (`auto_updates: true`) but have no
  Sparkle feed — they need a `GitHubReleaseRule` or `VendorProbeRecipe` to be
  detected at all.

### Phase 2: Release channels — WHICH tracks exist?

**2a. Does the app ship multiple channels?**
- `brew search --cask "<name>"` — look for `@beta`, `@nightly`, `@canary`
- Vendor's download page for "Beta", "Canary", "Nightly", "Insider" links
- GitHub repo for prerelease tags

**2b. Which pattern? (A/B/C/D from above)**

For each non-stable channel found:
- What is its bundle ID? Same or different from stable?
  - Different → Pattern A (independent installs, safe to support)
  - Same → continue to 2c

**2c. For same-bundle-ID channels:**
- Can we detect the channel? Apply the signal hierarchy `ReleaseChannel.detect()`
  uses, highest-priority first:
  0. **Mozilla `RemotingName`** from `Contents/Resources/application.ini`
     (`firefox-esr`, `thunderbird-beta`, …) — `AppScanner` reads it for
     `org.mozilla.*` apps; it's the ONLY reliable signal for Firefox/Thunderbird
     (see the box below). Add the equivalent if another vendor bakes the channel
     into a readable resource file.
  1. `KSChannelID` plist key
  2. Bundle ID suffix (`.canary`, `-preview`)
  3. Display name word boundary ("App Beta")
  4. Version string suffix (`b6`, `a1`, `esr`) — least reliable; an installed app
     may strip the suffix (Mozilla does), so never rely on it for same-bundle-id
     channels without confirming on a real bundle.
- If none match → **ASK**: "这个 app 有没有在偏好设置里存 channel 选择？能帮我看一下
  `defaults read <bundleID>` 的输出吗？"
- If truly undetectable → Pattern D, document as blocked

> **⚠️ The vendor's version feed is NOT the installed app.** A channel's bundle id,
> app name, and version string as they appear in a vendor feed / product-details
> JSON / Homebrew cask routinely DIFFER from what the real installed bundle reports.
> Mozilla is the canonical trap (verified 2026-06-04, Thunderbird):
> - The feed's `…b3` / `…esr` suffixes are **stripped** from the installed app's
>   `CFBundleShortVersionString` (`152.0b3`→`152.0`, `140.11.1esr`→`140.11.1`), so
>   version-suffix detection silently fails for beta/esr — and an undetected ESR
>   install then matches the *stable* recipe and gets a cross-channel push.
> - Beta is a **separate bundle id** (`org.mozilla.thunderbirdbeta`), not the shared
>   one the feed implies.
> - The authoritative channel marker is `Contents/Resources/application.ini` →
>   `RemotingName` (`thunderbird-esr` / `-beta` / `-nightly` / `thunderbird`), baked
>   per-channel into every build, readable without launching.
>
> Never finalize same-bundle-id channel detection from a feed. Confirm it against a
> REAL bundle of that channel (Phase 3¾). This generalizes beyond Mozilla — treat
> any "shared bundle id + version suffix" claim as a hypothesis until a real bundle
> proves it.

**2d. How does the channel affect the update source?**
- Feed-swap: different URL per channel (Fork, Surge)
- Channel-tag: same feed, `<sparkle:channel>` filters items (OrbStack, DuoPaste)
- Header-keyed: same feed URL, HTTP header selects builds (TablePlus)
- Independent endpoint: completely separate probe per channel (Chrome, Discord)
- **ASK if unclear**: "你能帮我抓包看看切到 beta 后，app 请求的更新端点有什么变化吗？"

**2e. Does the changelog follow channel?**
- One changelog page covers all channels → one recipe, channel-agnostic
- Separate per-channel notes → need investigation
- **ASK if unclear**: "beta/canary 有独立的 release notes 页面吗？"

### Phase 3: Update detection

For each (distribution source × channel) combination that we want to support:

**Sparkle:**
- Fetch the feed and inspect: does it have `<sparkle:channel>` tags? Multiple
  `<item>`s with different channels? Or is it channel-unaware?
- Is the feed URL stable or does it change by channel?

**GitHub Releases:**
- Is there a clear tag naming pattern? (`v1.2.3`, `release-1.2.3-beta1`)
- Are macOS assets consistently named?
- Are prereleases properly flagged?

**Vendor endpoint:**
- What is the version API? (JSON preferred > redirect filename > HTML scrape)
- Does it take a channel parameter?
- **ASK if not found**: "我没找到公开的版本 API。你能帮我抓包看看这个 app 启动时的更新
  检查端点吗？"

**MAS / Homebrew:**
- These are mostly automatic — just confirm the app is listed

### Phase 3½: Version scheme validation (CRITICAL for VendorProbe/GitHub)

**This step has caught real bugs in production (Office, OneDrive, Teams).** The
version a vendor endpoint returns may NOT match what the installed app reports.
Three version strings can all differ:

| Source | Example (Office) |
|--------|-----------------|
| Endpoint / pkg filename | `16.109.26053122` (= `CFBundleVersion`) |
| `CFBundleShortVersionString` | `16.109.3` (marketing version) |
| Homebrew cask version | `16.109.26053122` (copies the endpoint) |

If the probe extracts a build number but `UpdateChecker.evaluate` compares it to
the marketing version → **permanent phantom update** (`26053122 > 3` forever).

**Mandatory checks:**

```bash
# Read BOTH version fields from the installed app
defaults read "<path>/Contents/Info" CFBundleShortVersionString
defaults read "<path>/Contents/Info" CFBundleVersion
```

Then compare the probed version against both:
- Matches `CFBundleShortVersionString`? → normal recipe (default)
- Matches `CFBundleVersion` but not short? → needs `versionIsBuild: true`
- Matches neither? → the pattern is extracting the wrong number. **STOP.**
  - Can you adjust the regex to extract only the marketing-version portion?
    (OneDrive fix: regex captures first 3 segments of a 4-segment string)
  - If not → this endpoint is not safely usable. Ask the user.

**Do NOT trust `brew info --cask` version as ground truth.** Cask version often
copies the download URL version, which may be the build number, not what
`Info.plist` reports. Always verify against the real installed app.

### Phase 3¾: Strict on-machine verification (HARD GATE for multi-channel apps)

**A channel recipe is not ✓ until it has run green against a real bundle on this
machine.** Reasoning from a feed, a cask, or even build-source config is a
*hypothesis*; only a real bundle is proof. This step caught two shipped-broken
Thunderbird recipes that every prior reasoning step (and the existing code) missed.

The repo ships a harness — `application-test/` — that runs the PRODUCTION
`ReleaseChannel.detect()` + `VendorProbeSource` against a real `.app` or a `.dmg`
(mounted read-only, auto-detached — **verify without installing**):

```bash
swift run --package-path application-test channel-verify "<path-to-.app-or-.dmg>" [--expect <channel>]
```

It prints the real bundle id, real `CFBundleShortVersionString`, the detected
channel, and the live probe's from→to verdict.

**Tiered identity resolution — cheapest authoritative source first:**
1. Channel **installed** → read its bundle directly (`mdls`, `application.ini`).
2. Homebrew per-channel cask → app name + URL: `brew cat --cask <name>@<channel>`.
3. Vendor build/source config → bundle id without download (Mozilla
   `MOZ_MACBUNDLE_ID`; the `RemotingName` per-channel marker).
4. **Fallback (and the proof step):** download the channel's installer and let the
   harness mount+inspect it. Required when a not-installed channel *might* have an
   independent bundle id or a feed-vs-app version mismatch that the cheaper sources
   can't settle.

**When download/mount is REQUIRED vs. skippable:**
- Channels that genuinely **share** the installed bundle id (confirmed) and detect
  via an unambiguous signal → no separate download needed.
- Any channel with a **possibly-independent bundle id**, a **suffix-stripping feed**
  (Mozilla), or **no detection signal** → MUST be verified on a real bundle before
  the recipe is marked ✓. Until then it's **needs-verify**, not ✓.

**Persist the evidence** to `application-test/records/<bundleID>.md` (the table of
real bundle id / version / channel marker / detected channel / probe verdict per
channel). That record is what backs a ✓ in the audit docs.

### Phase 3⅞: What else does the vendor's updater DO? (the step that keeps getting skipped)

Phases 1–3¾ all ask the same shape of question: *is there a feed we can read?*
When the answer is "no", it is easy to write the app up and stop. That is how a
whole capability goes missing — the audit is not wrong, it is **narrow**.

Ask the orthogonal question: **what does this app's own updater do that we could
consume, or that would break us if we ignored it?**

**Answer every row in three columns. Never collapse them.**

| | 客户端有这个能力? | 服务端现在真在发? | 我们能消费吗? |
|---|---|---|---|
| 增量 / 二进制补丁 | | | |
| 按设备灰度（同一个 key 因人而异）| | | |
| 按架构 / 按 OS 分轨 | | | |
| 自更新器会不会和我们抢 | | | |

Column 1 is usually answered from **strings in the binary**. Column 2 requires
**hitting the real endpoint**. They are different claims, and a string is never
evidence for column 2.

This is not hypothetical. The CapCut audit's first draft said "the patch format
isn't Sparkle's, so consuming it would need new machinery" — both halves wrong,
both from inferring rather than opening the framework sitting in the bundle. The
same draft said a field was "absent from `update_reminder`" when that key could
never have lived there.

**Delta / binary patch — how to actually check:**

```bash
# 1. Client capability: does the app carry a patch applier at all?
strings -a "<app>/Contents/Frameworks/<vendor>.dylib" | grep -iE "delta|diffpatch|bspatch|hdiff"
# Sparkle apps: the applier is in the framework's Autoupdate, NOT the main binary
strings -a "<app>"/Contents/Frameworks/Sparkle.framework/Versions/*/Autoupdate \
  | grep -iE "BinaryDelta|SUBinaryDelta|bspatch|sparkle:deltaFrom"
plutil -p "<app>"/Contents/Frameworks/Sparkle.framework/Versions/*/Resources/Info.plist | grep Version

# 2. Server reality: does a real response actually carry a patch URL?
#    Do NOT grep for the key name you expect — scan the WHOLE body.
python3 - <<'PY'
import re; raw = open("body.json").read()
print(sorted(set(re.findall(r'"([a-z0-9_.]*(?:diff|delta|patch)[a-z0-9_.]*)"\s*:', raw, re.I))))
print(re.findall(r'"(https?://[^"]*\.(?:delta|patch|diff))"', raw) or "no patch URL")
PY
```

If it is a **Sparkle** binary delta, we already apply it: `DeltaApplier` ships
Sparkle's own `BinaryDelta`, and `VendorAppcastDeltas` pulls patches out of an
appcast's `<sparkle:deltas>`. So "can we consume it" is usually a *plumbing*
question — where does the patch URL come from — not a new-mechanism one.

**Two traps that produced false "no" answers:**

- **Log format strings are column 1, never column 2.** `cfg.diff_url=%s` in a
  binary means the client can print that field. It says nothing about whether any
  server populates it.
- **Check the container before declaring a key absent.** A key spelled
  `diff_update.enable` in the binary may be a top-level `diff_update` OBJECT in
  the JSON. Confirm whether the schema is flat or nested (`[k for k in obj if "."
  in k]`) before reporting "not there".

**A pinned request parameter can silently foreclose this.** If the recipe pins a
version/id in the query, ask what that pin costs beyond the field you pinned it
for: patches are typically keyed *from* a version *to* a version, so a pinned
fake version can never match a patch mapping. Record the cost even when it is
zero today.

#### HARD RULE: say which of the two things the recipe reads

For every recipe, answer in writing:

> Does this read **the newest build published on the track**, or **the build this
> machine has been allocated**?

They are not the same thing whenever a vendor stages a rollout, and the
difference is invisible in every downstream check: the version resolves, the URL
resolves, the download is a real notarized build from the same vendor with the
same Team ID, so the signature gate passes too.

Reading "newest on the track" is allowed, but it is never the default and it
must be argued in the audit — it means one-click installs a build the vendor has
not allocated to this machine. Say what makes it acceptable for this app.

What the registry looks like today, as the calibration:

| App | What the recipe reads | Ahead of allocation? |
|---|---|---|
| ChatGPT | the track `plan_type` names | no — precise |
| Claude `/latest` | the public GA build, downloadable by hand | no |
| Claude `squirrel/update?device_id=` | the build allocated to this machine | no |
| CapCut beta | the newest build on the beta track | **yes** |

Note what makes Claude's GA endpoint safe and does NOT transfer: that build is
one the user could fetch manually from the vendor's own download page. Where the
vendor publishes no manual route to the build (CapCut's site serves only the
stable stub), "it's public if you know the URL" is not the same argument.

If you find yourself citing another app as precedent, open that recipe and read
its comment first — the two Claude endpoints are safe for reasons that look like
"we take the newest" from a distance and are not.

### Reference: what a recipe can already express

An audit that does not know a field exists will report the situation it covers as
"not supported". Check this list before writing 「不可行」— it is derived from
`VendorProbeRecipe`'s initializer, so verify against the source if it looks stale.

| Field | Use it when |
|---|---|
| `versionIsBuild` | the endpoint's version matches `CFBundleVersion`, not the marketing string |
| `displayVersionPattern` | the compared value is an ugly build id and there is a human one to show |
| `publishedAtPattern` | the entry states its own release date (Release Log gets an exact time) |
| `selectHighest` | the feed lists many releases and document order is not newest-first |
| `entryStartPattern` | multi-entry feed: slice it so version/URL/date all come from ONE entry |
| `channel` | this endpoint serves a non-stable track (source refuses cross-channel) |
| `variant` | one channel legitimately has more than one endpoint worth asking |
| `hostRequirement` | the build only runs on some Macs (arch / OS floor) — **detection half** |
| `identities` (`ProbeIdentity`) | the endpoint only answers for a machine id the app already wrote to disk |
| `track` (`RolloutTrack`) | one URL, several vendor-assigned tracks, picked by a request-borne value |
| `requestBody` | the service answers nothing to a GET (Omaha-style) |
| `requestHeaders` | a WAF needs a Referer, or rejects the default browser-ish UA |
| `followRedirects: false` | the endpoint 302s to a huge binary and the version is in `Location` |
| `install` + `ChannelProofRegistry` | one-click; a NON-STABLE channel install **requires** a proof entry |

Adjacent machinery an audit should also weigh: `DeltaApplier` (applies Sparkle
binary patches), `VendorAppcastDeltas` (pulls them out of an appcast),
`RecipeSanity` (flags a version that appears verbatim in the request URL, and a
feed that reads behind the installed copy).

### Phase 4: One-click install feasibility

Only after detection is confirmed. For each supported channel:
- Stable download URL?
- Format? (.dmg / .zip / .pkg / .tar.gz)
- Same Team ID as installed copy?
- Authentication or special headers needed?

**ASK before implementing**: "检测可以做，要不要也加一键安装？"

---

## § Report template

Use this structure for both reporting and persisting. The 2D matrix is the
centerpiece — it shows at a glance what's covered and what's not.

```markdown
# <App Name>

## 基本信息
- Bundle ID: `...`
- Team ID: `...`
- 已安装版本: ...
- 自更新机制: Sparkle / Electron / Keystone / 自研 / 无

## 覆盖矩阵

> ✓ = 已接入  ○ = 可接入(未实现)  ✗ = 已调查不可行  — = 不适用

|              | Sparkle | Homebrew | MAS | GitHub | VendorProbe |
|--------------|---------|----------|-----|--------|-------------|
| **stable**   |         |          |     |        |             |
| **beta**     |         |          |     |        |             |
| **canary**   |         |          |     |        |             |

当前生效源（`UpdateChecker` 优先链中第一个应答的）: **...**

## Channel 详情

| Channel | Bundle ID | 独立/共享 | 检测信号 | 门控方式 | 状态 |
|---------|-----------|----------|---------|---------|------|
| stable  | ...       | 独立      | —       | —       | ✓    |
| beta    | ...       | 共享      | 偏好 X  | feed-swap | ○  |

## 更新检测
- 源: ...
- 端点: ...
- 注意事项: (版本方案陷阱、rollout、WAF 等)

## 增量更新（delta / binary patch）
> 三栏分开写，每栏标证据来源。空着不如写「没查」。

| | 客户端能力 | 服务端实际下发 | 我们能否消费 |
|---|---|---|---|
| 结论 | 有/无/没查 | 有/无/没查 | 能/不能/没查 |
| 证据 | (binary strings / framework) | (真实响应，注明 date + 参数) | (哪条现成机制，或缺什么) |

- 格式: Sparkle binary delta / 厂商自有 / 未知
- 阻塞项: ...

## Changelog
- 来源: Sparkle inline / recipe / WebView / 无
- 跟随 channel: 是/否
- Recipe 状态: 已有 / 需要 / 不需要

## 一键安装
- 状态: 支持 / 仅检测 / 需要验证
- 格式: dmg/zip/pkg
- **读的是**: 轨道最新 / 本机被分配 / 人人可手动下载的 GA  ← 必填,见 Phase 3⅞
  - 若是「轨道最新」: 为什么这个 app 可以接受? (一键会装厂商还没分配给这台机器的构建)
- 阻塞: ...

## 已知问题
- ...

## 建议下一步
1. ...
```

---

## § Persisting audit results

Every audit produces a document. This keeps documentation in sync with code.

**Location**: `docs/app-audits/<bundleID>.md`
(Use the primary/stable bundle ID as the filename, dots replaced with dashes:
`com.google.Chrome` → `com-google-Chrome.md`)

> ⚠️ **This directory is TRACKED and the repo is PUBLIC.** `/docs/` is otherwise
> gitignored — `app-audits/` is the one subtree re-included, because these are the
> reasoning behind the recipe registries and belong next to the code. Everything
> you write here gets pushed. See § Writing for a public repo before you write a
> line; it is not a review step you do at the end, because a rewrite after pushing
> does not reliably un-publish (GitHub keeps pushed commits reachable by SHA, and
> anyone who cloned already has them).

**When to write:**
- REPORT MODE: write/update the doc at the end of the audit
- INVESTIGATE MODE: write the doc once the investigation reaches a conclusion
  (even if the conclusion is "blocked" or "needs more info from user")

**When to update:**
- After any integration change (new recipe, new channel, fix)
- The skill should check if a doc exists and update it, not create a duplicate

**Index**: maintain `docs/app-audits/README.md` as a one-line-per-app index:
```markdown
- [Chrome](com-google-Chrome.md) — 4 channels, VendorProbe, one-click ✓
- [Firefox](org-mozilla-firefox.md) — 5 channels, Sparkle+MAS, detection only
```

### Relationship to existing tracking docs

The repo has three **global-view** documents. Per-app audit docs are the
**deep-dive per app**. They serve different purposes and must stay in sync:

| Document | Scope | Role |
|----------|-------|------|
| `docs/app-audits/<id>.md` | Single app, full depth | **Source of truth** for one app's integration |
| `docs/app-onboarding-status.md` | All apps, one line each | Done / Skipped / TODO status board |
| `CHANNEL_COVERAGE_TODO.md` | All apps, channel gaps | Which channels are missing and why |
| `docs/top50-coverage-todo.md` | Top-50 apps, progress | Priority tracking |

**After completing an audit, also update the relevant global docs:**
- If a new app is integrated → add it to `app-onboarding-status.md` § Done
- If an app is investigated and skipped → add it to § Skipped (with reason)
- If channel gaps are found → update `CHANNEL_COVERAGE_TODO.md`
- If a previously-TODO app is now done → move it in the global doc

---

## § Handoff — what to do after the audit

The audit produces a report; implementation is a separate step. The report's
"建议下一步" section should give **concrete handoff instructions**, not vague
suggestions. Use this decision table:

| Finding | Action | How |
|---------|--------|-----|
| Needs VendorProbe recipe | → `/fragile-recipe <app>` (VendorProbe path) | Pass the endpoint URL, version pattern, and channel from the audit |
| Needs ChangelogRecipe | → `/fragile-recipe <app>` (Changelog path) | Pass the changelog URL and markup structure from the audit |
| Needs GitHubReleaseRule | → Edit `GitHubReleasesSource.swift` directly | Add rule to the `rules` array with owner/repo/pattern/channel |
| Needs ChannelBinding | → Edit `ChannelBinding.swift` + new `<App>Channel.swift` | Create resolver, add to switch, add tests |
| Needs channel added to existing probe | → Edit `VendorProbeRecipe.swift` | Duplicate the stable recipe, change channel + endpoint |
| Blocked (same ID, undetectable) | → Update `CHANNEL_COVERAGE_TODO.md` § C | Document the reason; no code change |
| Already fully covered | → Write/update audit doc only | No code change needed |

**Example handoff text in the report:**

```markdown
## 建议下一步
1. 加 stable 检测: `/fragile-recipe Notion` (VendorProbe,
   endpoint `https://www.notion.so/api/v3/...`, pattern `"version":"(\d+\.\d+\.\d+)"`)
2. 加 changelog: `/fragile-recipe Notion` (ChangelogRecipe,
   source `https://www.notion.so/releases`, entry markup `<div class="release">`)
3. beta channel: BLOCKED — 同 bundle ID `notion.id`, 应用内 opt-in, 无检测信号
   → 更新 CHANNEL_COVERAGE_TODO.md § C
```

---

## Safety rules

1. **Never guess a version endpoint.** A wrong probe creates phantom updates.
   Ask the user to help with packet capture.

2. **Never assume bundle IDs.** Verify from installed app or cask metadata.

3. **Stop on ambiguity.** The user has tools (Charles, mitmproxy, `defaults read`)
   that you don't. Asking is faster than guessing.

4. **Cross-reference with existing code.** Before declaring "not integrated",
   search thoroughly — the bundle ID might be covered by a broader source.

5. **Respect the architecture.** Same bundle ID + undetectable channel = blocked.
   Don't propose workarounds that bypass the cross-channel safety gate.

6. **Document what you can't do.** A "blocked, reason: ..." entry is more
   valuable than silence. Future readers need to know what was investigated.

7. **A feed is not the app.** Bundle id, name, and version in a vendor feed / cask /
   product-details JSON may all differ from the real installed bundle. For any
   multi-channel app, a channel recipe stays **needs-verify** (not ✓) until
   `application-test/channel-verify` runs green against a real bundle of that
   channel. Don't let "the JSON says so" stand in for a mounted bundle.

8. **Write it for the public repo.** See the section below. The audit is published;
   the machine it was produced on is not.

## § Writing for a public repo

An audit is produced by poking at one machine and is then published. Those two
facts pull in opposite directions, and the whole job is keeping the findings while
dropping the machine.

The rule that governs it: **`docs/` was gitignored because software fingerprint is
a personal profile** — a list of which apps someone runs, at which versions, on
which channels, sketches their work environment. `app-audits/` is the exception,
so each file has to carry the exception's cost.

### Never write

- Absolute paths containing the account name (`/Users/<name>/…`). Use `~/…`.
  `/Applications/Foo.app` is fine — it names no one.
- Emails, account names, licence keys, order or receipt numbers, tokens, cookies,
  session ids, serial numbers, or any UUID/device id read off the machine.
- IPs, hostnames, LAN topology, Wi-Fi names, VPN or tailnet names, node names.
- Enterprise software that identifies an employer (corp VPN clients, corp IM,
  internal ad-hoc builds by name).
- The owner's purchase/subscription state ("我买了 Pro", "试用还剩 N 天").

### The class that actually slips through

The list above is easy and audits are usually already clean of it. What got
published on 2026-08-27, and had to be rewritten, was subtler — three shapes that
all *look* like legitimate forensic evidence:

**1. Which channel this machine runs the app on.**

```
✗ KDDefaults.plist `IncludeBetaBuilds=true` → 本机在 **beta**
✓ KDDefaults.plist `IncludeBetaBuilds=true` 时判定为 **beta**
```

Same key, same value, same verdict — the second one just doesn't say whose machine
it is. Nothing of engineering value is lost: what a reader needs is the preference
key and which value selects which channel.

**2. The narrative of toggling a preference to test the other channel.**

```
✗ **stable 也已本机验证**（临时翻 `sparkleIncludePrereleases`→`--scan`→还原）
✓ **stable 也已在真实 bundle 上验证**（`sparkleIncludePrereleases=false` 时
   `--scan` 结果=stable；验证用的临时改动已还原）
```

State the method and that it was reverted, not a first-person account of an
afternoon on someone's laptop.

**3. Incidental facts about the machine's environment.** The Raycast audit
explained a TLS handshake failure by saying this machine runs an interception
proxy. The finding is worth keeping; the machine is not:

```
✗ SSLV3_ALERT_HANDSHAKE_FAILURE 系本机 MITM 代理拦截所致
✓ 经中间人代理探测该端点时会看到 SSLV3_ALERT_HANDSHAKE_FAILURE，
   那是端点拒绝被拦截，与 auth 无关；直连即 200
```

### Keep

Observed version numbers, observation dates, HTTP status codes, captured response
bodies, vendor endpoints, regexes, vendor Team IDs, and the audited app's own
bundle id. These are the evidence the document exists for. Only strip the framing
that points at the owner — the numbers and facts stay.

Mentioning another app to compare mechanisms ("跟 Chrome 一样走 Keystone") is
ordinary engineering prose and stays. Cross-listing what else is installed
("本机还装了 X、Y、Z") is the inventory and goes.

### Two judgement calls to raise with the user, not decide alone

- **The file's existence is itself a signal** when the app is NOT in any recipe
  registry. For an app the registry already names, an audit adds nothing — the repo
  already says we support it. For one it doesn't, publishing the audit says someone
  ran that app. Ask before adding the first audit for an unsupported app.
- **`docs/app-audits/README.md` is the highest-risk file in the tree**, because it
  aggregates every app's state into one place — that is the profile in miniature.
  Keep its lines to app name, link, coverage and date. No per-app channel state, no
  "temporarily flipped X" notes.

## File map

Verification harness:
- `application-test/` — `channel-verify` runs production detect()+probe against a
  real `.app`/`.dmg`; `records/<bundleID>.md` holds the per-channel evidence.

Core (read as needed):

Core (read as needed):
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Models/ReleaseChannel.swift` — channel enum + detect()
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/ChannelBinding.swift` — per-app preference resolvers
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift` — probe registry
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift` — GitHub rules
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/ChangelogRecipe.swift` — changelog registry
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/SparkleAppcastSource.swift` — Sparkle channel filtering
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Engine/UpdateChecker.swift` — source priority chain
- `CHANNEL_COVERAGE_TODO.md` — channel gap analysis
- `docs/app-audits/` — persisted audit results

Fetching (same constraint as fragile-recipe skill):
- `curl` is trapped by local wrapper — use Python `urllib` or `WebFetch`
- Always use a browser-like User-Agent
