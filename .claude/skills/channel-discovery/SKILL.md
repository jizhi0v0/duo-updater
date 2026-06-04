---
name: channel-discovery
description: >-
  Breadth-first sweep that finds apps with release channels duo-updater might be
  missing — especially apps that switch channel INSIDE the app (a Settings toggle
  like stable→beta/preview/insider) rather than shipping a separate download. It
  enumerates candidates from concrete sources (installed bundles, Homebrew cask
  variants, the existing recipe registries) — NOT from memory — classifies each
  by channel pattern (A/B/C/D), and produces a ranked worklist plus a refreshed
  CHANNEL_COVERAGE_TODO. It does NOT implement or verify; it hands each actionable
  candidate to `/app-audit`. Trigger phrases: "find apps with beta/preview
  channels", "which apps have an in-app channel switch", "sweep for missing
  channels", "枚举有渠道切换的 app", "哪些 app 在设置里能切 beta/preview", "刷新
  channel 覆盖清单". Use this for breadth (many apps at once); use `/app-audit` for
  depth (one named app).
---

# Channel discovery skill

`app-audit` and `fragile-recipe` go **deep on one named app**. This skill goes
**wide**: it answers "which apps even *have* a channel we're not covering, and
which of those switch channel in-app?" — the breadth pass neither of the other
skills does.

Its whole reason to exist is to **remove the knowledge-base blind spot**: a human
(or model) listing "apps with betas" from memory will miss anything off its radar.
So this skill enumerates candidates from **concrete, on-machine + registry
sources**, then researches and classifies each. The output is a worklist; the
empirical confirmation and implementation are handed back to `/app-audit`.

> **Hard rule: do NOT seed the candidate list from memory.** If you find yourself
> typing a list of app names you "know" have betas, stop — that *is* the blind
> spot. Enumerate from the sources in Phase 1.

## What "in-app channel switch" means (and why it's the focus)

Reusing `app-audit`'s four patterns:

| Pattern | Shape | This skill's job |
|---|---|---|
| **A. Independent bundle id** | Each channel is its own `.app` / bundle id (Chrome `.canary`, Firefox beta) | Flag if uncovered → easy, hand to `/app-audit`; detection is "automatic" via bundle id |
| **B. Same id, preference-switched** | One bundle id; an **in-app toggle** writes a preference that swaps the feed/endpoint (Fork, Surge, DuoPaste) | **PRIMARY TARGET** — find the toggle, hypothesize the signal |
| **C. Same id, tag-filtered / keyed** | One bundle id + feed; an in-app toggle selects items via channel tag or header/license (OrbStack, TablePlus, CleanShot) | **PRIMARY TARGET** — same |
| **D. Same id, undetectable** | In-app/server-side opt-in that leaves **no local artifact** (Slack Beta, Figma Beta, Raycast Beta, Obsidian Insider) | Document as dead-end, do not re-investigate |

The user asked specifically about **B/C**: apps where you trigger stable→preview
*inside the app*. The deciding question is never "does it have a toggle" — it's
**"does flipping the toggle leave a readable local artifact"** (a `defaults` key, a
license file, a feed URL in prefs). That can only be settled empirically, so this
skill's verdict for B/C is a **hypothesis** ("likely a signal in domain `<id>`,
worth toggling"), confirmed later by `/app-audit` Phase 2c/3¾.

---

## Phase 1: Enumerate candidates from concrete sources

Build the candidate set from these, in order. Each is a real source of truth, not
recall.

**1a. What we ALREADY cover (to subtract, not re-investigate):**
```bash
# Channels already wired — skip these
grep -n "channel:" DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift
grep -n "channel:" DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/GitHubReleasesSource.swift
ls DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/*Channel*.swift   # ChannelBinding resolvers
# Already-investigated verdicts (A/B/C/D, incl. the ✗ dead-ends — DON'T redo these)
sed -n '/^## /p' CHANNEL_COVERAGE_TODO.md 2>/dev/null || echo "(ledger missing — rebuild §1 from code below; it's the only authoritative source)"
```

> **The code is the source of truth, not the ledger.** `CHANNEL_COVERAGE_TODO.md`
> can be stale or deleted (it has been). Always regenerate the "已覆盖/§1" section by
> extracting `channel:` entries from the two registries + the `*Channel.swift`
> resolvers (a `python3` pass pairing `bundleID:`→`channel:` is reliable; BSD `awk`'s
> 3-arg `match` is not). The ledger's TODO/dead-end sections are carried-forward
> *decisions* — preserve them, but never let a ledger entry override what the code says.

**1b. Installed apps — does a sibling channel bundle exist on disk?**
```bash
# Every installed app + its bundle id; look for .beta/.canary/.nightly/-Preview siblings
mdfind "kMDItemContentType == 'com.apple.application-bundle'" -onlyin /Applications 2>/dev/null
mdfind "kMDItemContentType == 'com.apple.application-bundle'" -onlyin ~/Applications 2>/dev/null
```
A sibling bundle with a channel-suffixed id → **Pattern A** (independent). No
sibling but the app is a known multi-channel vendor → candidate for **B/C/D**.

**1c. Homebrew cask variants — the most reliable breadth signal:**
```bash
# For each installed/known app, does the vendor publish a channel cask variant?
brew search --cask "<name>" 2>/dev/null        # shows <name>@beta / @nightly / @canary / @dev
# And read whether the variant is a distinct bundle (A) or same id (B/C/D):
brew cat --cask "<name>@beta" 2>/dev/null | grep -iE "name|url|pkgid|auto_updates"
```
A `@beta`/`@nightly` cask that installs a **distinct .app/bundle id** → Pattern A.
A vendor with betas but **no separate cask** → the channel is likely in-app (B/C/D).

**1d. Per surviving candidate, web-research the in-app toggle question** (use
Python `urllib`/`WebFetch`, browser UA — `curl` is trapped):
- "Does `<app>` have an in-app Beta/Preview/Insider/Nightly toggle, and where?"
  (vendor docs, release notes, support forum). Note the exact Settings path.
- Does anyone document *where the choice is stored* (a `defaults`/plist key, a
  config file)? Rare, but when found it sharpens the hypothesis for `/app-audit`.

---

## Phase 2: Classify each candidate

```
For each candidate app:
  1. Sibling bundle / @channel cask with a DIFFERENT bundle id?
       → Pattern A. If uncovered: actionable, but it's the easy path
         (bundle-id detection). Hand to /app-audit, low risk.
  2. Same bundle id, but a documented in-app channel toggle exists?
       → Pattern B or C — PRIMARY TARGET. Emit a hypothesis (Phase 3).
  3. Same bundle id, toggle is server-side feature-flag / build is byte-identical
     / no toggle found?
       → Pattern D. Dead-end. Document reason; never mark detectable.
  4. Already in a registry / ChannelBinding / CHANNEL_COVERAGE_TODO?
       → Skip (covered or already-ruled-out). Do not re-investigate ✗ entries.
```

> The split between B/C (actionable) and D (dead-end) is a **hypothesis from web
> research** at this stage. You cannot confirm a readable signal exists without
> toggling on a real install — that's `/app-audit`'s job. Mark B/C verdicts as
> "candidate / needs on-machine toggle", never as "detectable ✓".

---

## Phase 3: Output — worklist + hypotheses, then hand off

For each **B/C primary-target** candidate, emit a handoff block:

```markdown
### <App> — Pattern B/C candidate (needs on-machine confirm)
- bundle id (shared): `<id>`
- in-app switch: Settings → <path to the Beta/Preview toggle> (per <source>)
- hypothesis: flipping it likely writes a key in `defaults read <id>` domain;
  candidate signal to diff for.
- next: `/app-audit <App>` → install, toggle stable↔preview, diff `defaults read
  <id>` before/after to find the key, then wire a ChannelBinding + verify with
  `channel-verify`.
```

For **Pattern A uncovered** candidates: a one-liner "→ `/app-audit <App>` (independent
bundle id `<id>`, add a per-channel recipe)".

For **Pattern D**: a one-liner with the reason, for the dead-end log.

**Then update the global docs** (don't create parallel lists):
- New gaps / refreshed verdicts → edit `CHANNEL_COVERAGE_TODO.md` (A/B/C/D sections,
  matching its existing format and the 2026-06-04 provenance note style).
- If a sweep date matters, stamp it (the repo uses absolute dates).

**Then stop.** Implementation and the empirical toggle-and-diff are `/app-audit` +
`/fragile-recipe`, with the user's hands-on help. This skill's deliverable is the
*ranked worklist*, nothing landed in code.

---

## Boundaries & safety

1. **Enumerate, don't recall.** Candidates come from Phase 1 sources. A from-memory
   list is the exact failure mode this skill replaces.
2. **Web research ≠ detectability.** Knowing an app has a Beta toggle says nothing
   about whether the switch leaves a readable artifact. That verdict is a hypothesis
   until `/app-audit` toggles a real install and diffs `defaults`.
3. **Never mark a candidate detectable / ✓.** Highest you go is "B/C candidate,
   worth toggling." Only `channel-verify` on a real bundle earns a ✓.
4. **Don't re-open dead-ends.** `CHANNEL_COVERAGE_TODO.md` § C lists Pattern-D apps
   already ruled out (Slack Beta, Figma Beta, Raycast Beta, Obsidian Insider, …).
   Re-confirm only if you have a NEW signal; otherwise skip.
5. **Don't double-cover.** Subtract anything already in VendorProbeRecipe /
   GitHubReleasesSource / a `*Channel.swift` ChannelBinding before listing it.
6. **Fetching:** `curl` is trapped by a local wrapper — use Python `urllib` or
   `WebFetch`, always with a browser-like User-Agent.

## File map

- `CHANNEL_COVERAGE_TODO.md` — the breadth ledger this skill refreshes (A/B/C/D)
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Models/ReleaseChannel.swift` — channel enum + `detect()` signal hierarchy
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/ChannelBinding.swift` + `*Channel.swift` — the B/C resolvers already built (Fork/Surge/TablePlus/DuoPaste/OrbStack/CleanShot)
- `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/VendorProbeRecipe.swift` / `GitHubReleasesSource.swift` — covered channels to subtract
- `.claude/skills/app-audit/SKILL.md` — the depth skill this one feeds (Pattern A/B/C/D defined there in full)
- `application-test/` — `channel-verify`, the on-machine proof `/app-audit` runs
