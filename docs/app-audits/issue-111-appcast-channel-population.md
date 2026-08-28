# Issue #111 — the Sparkle-appcast channel population, enumerated and swept

> Measurement task only, no code changes. Produced for issue #111 ("Channel
> bindings served by Sparkle appcasts are a third install-carrying population
> no proof registry enumerates"). Branch `audit/111-appcast-channel-population`.
> All live probes run 2026-08-28 from this worktree; commands and raw output
> are reproduced verbatim below rather than summarized.

## TL;DR

- The third population is **8 apps**: DuoPaste, Fork, Surge, TablePlus,
  CleanShot X, IINA, Ghostty, BetterDisplay. Confirmed by grepping both
  `VendorProbeRecipe.swift` and `GitHubReleasesSource.swift` for each of the
  12 bundle ids `ChannelBinding.resolve()` switches on — 4 of the 12
  (OrbStack, Alfred, Tailscale, CapCut) actually resolve through
  `VendorProbeRegistry` and are **already** covered by
  `ChannelProofRegistry.channelRecipesWithInstall` / `.proofs`. The issue's
  own doc comments say this for OrbStack/Alfred/Tailscale but don't say it
  plainly enough to rule them out of the "third population" headline — worth
  stating explicitly since it's exactly the kind of undercount CLAUDE.md's
  "先量一遍" rule warns about.
- Of the 8, **4 carry no non-stable channel at all** (CleanShot X and
  Ghostty resolve only `.stable`) or are **structurally protected already**
  by `SparkleAppcastSource`'s own channel-tag filtering (DuoPaste,
  BetterDisplay) — a proof-registry entry would be a no-op for all four.
- The remaining **4 are genuinely unprotected**: Fork, Surge, TablePlus,
  IINA. All four are feed-swap or header-keyed, and **none of their vendors
  puts a channel token anywhere in the downloaded artifact** — channel
  identity is 100% "which URL/header we used to ask," with nothing in the
  response tying back to that choice. TablePlus's header-flip was
  live-reproduced today (build 770 stable / 771 beta, see below) — the exact
  failure mode the issue describes is real and currently silent everywhere
  in this group.
- `SparkleInstaller.swift` contains **zero** occurrences of the word
  "channel" — the actual install pipeline for this population has no
  channel-awareness of any kind. EdDSA verification (where present) proves
  authenticity, never channel.

---

## 1. The population table (Q1)

### Reconciling `boundBundleIDs` vs the `resolve()` switch

`ChannelBinding.resolve(bundleID:)`'s switch has **12** cases: DuoPaste,
Fork, Surge, OrbStack, TablePlus, CleanShot, Tailscale, IINA, Alfred,
Ghostty, BetterDisplay, CapCut.

`ChannelBinding.boundBundleIDs` has **11** — every one of those *except*
Ghostty. This is not a bug: the doc comment on `boundBundleIDs` says so
outright ("Deliberately excludes Ghostty: its binding is a fixed
stable-only feed override with no user-settable preference, so there is
nothing to watch"). `boundBundleIDs` feeds the preference-file watcher, not
channel resolution — Ghostty still resolves through `resolve()`, it just
has no on-disk toggle worth polling. Stated here because the task asked to
reconcile the two lists explicitly, but this one turned out to be
intentional, not a gap.

### Which of the 12 are VendorProbe/GitHub (not the third population) vs pure Sparkle-appcast

Grepped `VendorProbeRecipe.swift` and `GitHubReleasesSource.swift` for each
of the 12 bundle ids directly (not from doc-comment claims):

| Bundle ID | Reaches install via | Evidence |
|---|---|---|
| `dev.kdrag0n.MacVirt` (OrbStack) | **VendorProbeRegistry** (`orbStackRecipe(channel:tag:)`, `VendorProbeRecipe.swift:4971`) | Already in `channelRecipesWithInstall` + `ChannelProofRegistry.proofs` (`.recipeAnchor("<sparkle:channel>beta")` / `"canary"`) |
| `com.runningwithcrayons.Alfred` | **VendorProbeRegistry** (two recipes, `VendorProbeRecipe.swift:915`, `:3275`) | Already in `channelRecipesWithInstall` + proofs (`.recipeAnchor("prerelease\.xml")`) |
| `io.tailscale.ipn.macsys` | **VendorProbeRegistry** (three recipes, `VendorProbeRecipe.swift:2616-2663`) | Already in `channelRecipesWithInstall` + proofs (`.artifact("/unstable/")`, `.artifact("/release-candidate/")`) |
| `com.lemon.lvoverseas` (CapCut) | **VendorProbeRegistry** (`VendorProbeRecipe.swift:4864` area) | Already in `channelRecipesWithInstall` + proofs (`.artifact("_capcutpc_beta_")`) |
| `io.duopaste.daemon` | **SparkleAppcastSource only** — no hit in either registry | **Third population** |
| `com.DanPristupov.Fork` | **SparkleAppcastSource only** | **Third population** |
| `com.nssurge.surge-mac` | **SparkleAppcastSource only** | **Third population** |
| `com.tinyapp.tableplus` / `TablePlus` | **SparkleAppcastSource only** | **Third population** |
| `pl.maketheweb.cleanshotx` | **SparkleAppcastSource only** | **Third population** (single-channel) |
| `com.colliderli.iina` | **SparkleAppcastSource only** | **Third population** |
| `com.mitchellh.ghostty` | **SparkleAppcastSource only** | **Third population** (single-channel) |
| `pro.betterdisplay.BetterDisplay` | **SparkleAppcastSource only** | **Third population** |

So the third population is exactly the 8 the TL;DR names — 4 fewer than a
naive read of `boundBundleIDs` would suggest, because 4 of the 12 bindings
exist purely to tell `VendorProbeSource` which recipe to pick, not to feed
`SparkleAppcastSource` at all.

### Per-binding detail

For every row: shape, whether it carries an install (traced
`ChannelBinding` → `AppScanner.swift:484-490` → `InstalledApp` →
`SparkleAppcastSource.latestVersion`/`usableItems` → `RemoteVersion.downloadURL`
→ `UpdatePolicy.canAutoInstall` → `SignatureVerifier`/`SparkleInstaller`),
and what currently proves the resolved artifact belongs to the resolved
channel.

#### DuoPaste (`io.duopaste.daemon`) — channel-tag

- Channels: stable / beta. One feed
  (`raw.githubusercontent.com/jizhi0v0/duo-paste-releases/main/appcast.xml`),
  no `feedOverride`.
- Install-carrying: **yes**. `SUPublicEDKey` present on the installed
  bundle (`5Ws5rSunj3IH4UiP8aN8YFtDni4inudOxMLTgmzhr1s=`); every item in the
  live feed carries `sparkle:edSignature`; enclosure is a `.dmg`
  (`sparkleArchiveExtensions`) → `UpdatePolicy.canAutoInstall` returns true
  once the EdDSA signature verifies.
- What proves channel: the `<sparkle:channel>beta</sparkle:channel>` tag on
  each item, enforced **structurally** by
  `SparkleAppcastSource.allowedChannels`/`usableItems` — not a per-app
  registry entry, but code that runs identically for every channel-tag app.
  Belt-and-suspenders: the enclosure filename itself also embeds the
  literal string `-beta+<hash>` (e.g.
  `DuoPaste-0.1.1283-beta+dc86f01.dmg`), so even a hypothetical tag-parsing
  bug would still have a filename token to fall back on.

#### Fork (`com.DanPristupov.Fork`) — feed-swap, **genuinely unprotected**

- Channels: stable / beta ("Developer", the shipped default). Two entirely
  separate feed documents:
  `fork.dev/update/feed-stable.xml` (stable) and
  `fork.dev/update/feed.xml` (beta/Developer, also the code-signed
  `SUFeedURL`).
- Install-carrying: **yes**, but **unsigned** — `SUPublicEDKey` is absent
  from the installed Info.plist. `UpdatePolicy.canAutoInstall`'s unsigned
  branch applies: "best-effort one-click," gated only by
  `SparkleInstaller`'s code-signature + Team ID + bundle-id check (the same
  gate Vendor/GitHub installs use), never by EdDSA. Enclosure is `.dmg`.
- What proves channel: **nothing in the artifact**. Neither feed's items
  carry a `<sparkle:channel>` tag (confirmed live, see §2), and the
  enclosure URL (`https://cdn.fork.dev/mac/Fork-2.66.7.dmg` vs
  `…Fork-2.69.0.dmg`) carries no channel word — only a version number that
  happens to differ because the two feeds happen to be at different
  releases today. The entire trust boundary is "we asked the URL
  `ForkChannel.resolve(channelPref:)` says to ask" — a pure, tested
  function, but nothing downstream checks that the *content* returned at
  that URL is what it claims to be.

#### Surge (`com.nssurge.surge-mac`) — feed-swap, **genuinely unprotected**

- Channels: stable / beta. Two feeds:
  `nssurge.com/mac/latest/appcast-signed.xml` (stable) and
  `…appcast-signed-beta.xml` (beta).
- Install-carrying: **yes**, and **signed** — `SUPublicEDKey` present
  (`+kybZprlaFQheSwPX2lkSI/zCXrN3uBI2dJDTqM0qlg=`), `edSignature` present on
  live items, enclosure `.zip`. Full EdDSA gate applies — which is exactly
  the case `ChannelArtifactProof`'s own doc comment warns about: "the
  download is a real notarized build from the same vendor … so the
  signature gate passes too." EdDSA proves the vendor signed it; it says
  nothing about which channel it belongs to.
- What proves channel: **nothing in the artifact**, same shape as Fork.
  Enclosure filenames carry a content hash but no "beta"/"stable" word
  (`Surge-6.8.1-12030-69f4be88db9663476f31a6b264109f0b.zip`). Note in
  passing (not part of the channel question, but observed while probing):
  the *installed* app's own `SUFeedURL` is `https://sgupd.com/latest/…`,
  a different domain than the `nssurge.com` constant `SurgeChannel` hard-codes
  — irrelevant to correctness today because `feedOverride` always wins, but
  worth a note in case `sgupd.com` and `nssurge.com` ever diverge instead of
  mirroring each other. **Unverified**: whether they are the same origin
  under the hood.

#### TablePlus (`com.tinyapp.TablePlus`) — header-keyed, **the sharpest case, live-reproduced**

- Channels: stable / beta. **One** feed URL
  (`https://tableplus.com/osx/version.xml`); the server decides what to
  return based on the `X-Tiny-Beta-Update: true` request header.
- Install-carrying: **yes**, and **signed** — `SUPublicEDKey` present
  (`+SVxmqxTHeb9ZPYezeYQNR48kMq9BEq9fcPHUWQW7Eg=`), `edSignature` present in
  both responses, enclosure `.dmg`.
- What proves channel: **nothing in the artifact, and not even a version
  number by convention** — see the live probe in §2. The bare response and
  the header'd response return the **same filename**
  (`TablePlus.dmg`) at the **same host**, differing only by a numeric build
  folder in the path (`/770/` vs `/771/`) that is higher for beta only
  because beta happens to be ahead today. If the vendor's header logic
  broke (ignored the header, or started serving the same build both ways),
  there would be no way to detect it from the response alone.

#### CleanShot X (`pl.maketheweb.cleanshotx`) — single-channel, no-op

- Channel: **stable only**. `CleanShotChannel.resolveCurrent()` never
  returns a non-stable `ResolvedChannel` — the personalized, license-keyed
  feed swap exists to fix a phantom-downgrade bug (frozen legacy v3 feed
  vs. the real subscription-gated "legit" feed), not to expose a channel
  choice.
- Install-carrying: yes (signed, `SUPublicEDKey` present), but there is no
  cross-channel question to ask: with one channel, there is no wrong train
  to cross to.
- What proves channel: N/A. A proof-registry entry would be a no-op.

#### IINA (`com.colliderli.iina`) — feed-swap, **same shape as Fork/Surge, currently dormant**

- Channels: stable / beta. Two feeds: `iina.io/appcast.xml` (stable) and
  `iina.io/appcast-beta.xml` (beta).
- Install-carrying: **yes**, signed (`SUPublicEDKey` present), edSignature
  present, `.dmg`.
- What proves channel: **nothing in the artifact** — identical risk shape
  to Fork/Surge. Live-measured 2026-08-28 (§2): the two feeds are currently
  **byte-identical** (matching md5), i.e. IINA has not shipped a beta build
  ahead of stable recently, so there is nothing to misresolve *today*. That
  is a fact about the current vendor state, not a property of the
  mechanism — the exposure is the same as Fork/Surge and will matter again
  the moment a beta build diverges.

#### Ghostty (`com.mitchellh.ghostty`) — single-channel, no-op

- Channel: **stable only**, deliberately — the doc comment states tip/nightly
  builds are on GitHub Releases under a rolling `tip` tag, not this appcast,
  and a user actually running tip is a documented, accepted blind spot
  (`CHANNEL_COVERAGE_TODO`), unrelated to this issue.
- Install-carrying: yes, signed (`SUPublicEDKey` present), edSignature
  present, `.zip`.
- What proves channel: N/A, single channel.
- **Docs finding, unrelated to the proof question**: `docs/app-audits/com-mitchellh-ghostty.md`
  is stale — it says "当前生效源…unknown", "本机 bundle has no SUFeedURL",
  and lists both Sparkle and VendorProbe as unimplemented (`○`). That was
  true before `GhosttyChannel.swift` was added; today the binding is fully
  wired (`feedOverride`, EdDSA-verified one-click). Flagged separately from
  the channel-proof question since it's a documentation-drift finding, not
  a code gap — the audit doc should be updated to match `GhosttyChannel.swift`.

#### BetterDisplay (`pro.betterdisplay.BetterDisplay`) — channel-tag, no-op, **undocumented in `docs/app-audits/`**

- Channels: stable / beta (`pre`) / unstable (`internal`, subsumes `pre`).
  One appcast, `<sparkle:channel>` tags, `sparkleChannelNames` override
  (`ReleaseChannel` has no `.pre`/`.internal` case).
- Install-carrying: **yes** for all three tracks — signed (`SUPublicEDKey`
  present), edSignature present, `.dmg`/`.zip`.
- What proves channel: the `<sparkle:channel>` tag, same structural
  enforcement as DuoPaste. Live-verified 2026-08-28 (§2): `internal` items
  live under a distinct, rolling `/releases/download/pre/` GitHub tag path
  (two hash-named `.zip` builds, no per-version tag); `pre` items live under
  per-version tag paths with `-pre-release` in the filename; stable items
  are untagged with a plain filename. So for the `pre` and stable tracks the
  artifact path *also* independently corroborates the tag; only `internal`
  relies on the tag alone.
- **No audit doc exists** for BetterDisplay under `docs/app-audits/` at all,
  despite `BetterDisplayChannel.swift` carrying the most involved binding
  logic in the whole file (three tracks, a subsuming toggle, an excluded
  `arm64_pre` fourth tag with its own architecture trap). Worth creating
  one — flagged as a documentation gap, not part of this task's scope to fix.

---

## 2. Live sweep (Q2) — raw commands and output

Built `channel-verify` fresh from **this worktree's source**
(`swift build --package-path application-test -c release`) rather than
relying on the installed `duo` binary, whose exact provenance relative to
this checkout was not confirmed (its mtime, `Aug 28 14:00`, is close to
this branch's HEAD commit `0dd7540` at `2026-08-28 14:00:25`, but "close"
isn't "known-same" — per CLAUDE.md, an unverified match is not a verified
one). Building from source sidesteps the question entirely: every result
below ran the code actually in this checkout.

Six of the eight apps in the population are installed on this machine
(Fork, Surge, TablePlus, CleanShot X, Ghostty, BetterDisplay), plus DuoPaste
in `~/Applications`. IINA is not installed, so it was probed by curl only.

### 2.1 Production chain, per installed app (`channel-verify --check`)

```
$ .build/release/channel-verify --check com.DanPristupov.Fork
  UpdateChecker.check() — full production source chain
    app             Fork
    bundle id       com.DanPristupov.Fork
    short version   2.69.0
    build version   2.69.0
    detected channel → beta
    winning source    → Sparkle
    latest            → 2.69.0
    status            → up to date

$ .build/release/channel-verify --check com.nssurge.surge-mac
    app             Surge
    short version   6.9.0
    build version   12230
    detected channel → beta
    winning source    → Sparkle
    latest            → 6.9.0
    status            → up to date

$ .build/release/channel-verify --check com.tinyapp.TablePlus
    app             TablePlus
    short version   26.9.13
    build version   771
    detected channel → beta
    winning source    → Sparkle
    latest            → 26.9.13
    status            → up to date

$ .build/release/channel-verify --check pl.maketheweb.cleanshotx
    app             CleanShot X
    short version   4.8.10
    detected channel → stable
    winning source    → Sparkle
    latest            → 4.8.10
    status            → up to date

$ .build/release/channel-verify --check com.mitchellh.ghostty
    app             Ghostty
    short version   1.3.1
    build version   15212
    detected channel → stable
    winning source    → Sparkle
    latest            → 1.3.1
    status            → up to date

$ .build/release/channel-verify --check pro.betterdisplay.BetterDisplay
    app             BetterDisplay
    short version   4.3.6
    build version   50119
    detected channel → stable
    winning source    → Sparkle
    latest            → 4.3.6
    status            → up to date

$ .build/release/channel-verify --check io.duopaste.daemon
    app             DuoPaste
    short version   0.1.1283-beta+dc86f01
    build version   1283
    detected channel → beta
    winning source    → Sparkle
    latest            → 0.1.1283-beta+dc86f01
    status            → up to date
```

Verdict: **all seven installed apps resolve to the channel their own
on-disk preference says, and the production chain reports "up to date"
against the live feed** — i.e. `ChannelBinding` correctly identifies which
channel each of these real installs is on today. This says nothing about
artifact-level protection (that's §1) — it confirms the *resolver* half of
the pipeline works, on real machines, right now.

### 2.2 TablePlus header flip — the issue's exact question, answered

```
$ curl -s "https://tableplus.com/osx/version.xml" | <extract first item>
<item><enclosure … sparkle:version="770" sparkle:shortVersionString="26.9.12"
  sparkle:edSignature="IM+EwfMotkiBPshQkKS4xll4XiIknYo0DBtrbq2H8R3bXapf9OoFWuX2diZ3ZqvfB3CKVVZ5OkzilKJ7GLuvAQ=="
  url="https://files.tableplus.com/macos/770/TablePlus.dmg"></enclosure>
<title>Build 770 - Support MacOS 27 Golden Gate</title> …

$ curl -s -H "X-Tiny-Beta-Update: true" "https://tableplus.com/osx/version.xml" | <extract first item>
<item><enclosure … sparkle:version="771" sparkle:shortVersionString="26.9.13"
  sparkle:edSignature="gk9xVrej8FTgKZn4TCprvierNQX1s69IjPvXLo9xIEaVdR55h65p9iXW0ddMTKrPbuAWYCU9+dYLbMk1QhgwCg=="
  url="https://files.tableplus.com/macos/771/TablePlus.dmg"></enclosure>
<title>Beta Update - Golden Gate - You received this update because you've
  enabled: Preferences > Receive Beta Updates.</title> …
```

**Verdict: currently correct.** The header is still load-bearing today —
bare gets build 770 (stable), the header gets build 771 (beta), and the
description text in the beta response even states the reason
("...because you've enabled..."). But per §1, this is entirely
unprotected: the only thing distinguishing the two responses is a
build-number path segment, and nothing checks that "the header worked."
This is a live confirmation of the issue's central claim, not a
hypothetical.

### 2.3 Fork feed-swap — content check

```
$ curl -s "https://fork.dev/update/feed-stable.xml" | <first item>
<title>Fork 2.66</title> … <enclosure url="https://cdn.fork.dev/mac/Fork-2.66.7.dmg"
  sparkle:version="2.66.7" type="application/octet-stream"/>

$ curl -s "https://fork.dev/update/feed.xml" | <first item>
<title>Fork 2.69</title> … <enclosure url="https://cdn.fork.dev/mac/Fork-2.69.0.dmg"
  sparkle:version="2.69.0" type="application/octet-stream"/>
```

**Verdict: currently correct** (stable trails beta as expected, matching the
installed Fork's own resolution above). **No `<sparkle:channel>` tag on
either feed's items** — confirms the channel gate is purely "which URL," not
anything content-based.

### 2.4 Surge feed-swap — content check

```
$ curl -s "https://nssurge.com/mac/latest/appcast-signed.xml" | <first item>
<title>Version 6.8.1</title> … <enclosure
  url="https://dl.nssurge.com/mac/v6/Surge-6.8.1-12030-69f4be88db9663476f31a6b264109f0b.zip"
  sparkle:version="12030" sparkle:shortVersionString="6.8.1"
  sparkle:edSignature="Y20CeDkOVmRqup4Em11hLa/cAghbZp5yc4K2YXv0bMJnwnkfwo27gHeS5gxs8GqOHLl35cUlzXc6WHpD+JeaAg=="/>

$ curl -s "https://nssurge.com/mac/latest/appcast-signed-beta.xml" | <first item>
<title>Version 6.9.0</title> … (edSignature present, different build)
```

**Verdict: currently correct** (stable 6.8.1/12030 vs beta 6.9.0, matching
the installed Surge's own resolution above). No `<sparkle:channel>` tag
either.

### 2.5 IINA feed-swap — content check

```
$ curl -s "https://www.iina.io/appcast.xml" | md5
4baab4045924cc7ee1f34dfba6dad355
$ curl -s "https://www.iina.io/appcast-beta.xml" | md5
4baab4045924cc7ee1f34dfba6dad355
```

**Verdict: could not measure divergence-handling** — the two feeds are
currently byte-identical (both head at 1.4.4 / build 168), so there is
nothing to misresolve right now. The mechanism (feed-swap, no artifact
marker) is structurally identical to Fork/Surge, so the same exposure
applies whenever IINA next ships a beta ahead of stable — this is a
statement about current vendor state, not a clean bill of health.

### 2.6 DuoPaste channel-tag — content check

```
$ curl -s "https://raw.githubusercontent.com/jizhi0v0/duo-paste-releases/main/appcast.xml"
  | <first 6 items>
title: Version 0.1.1283-beta+dc86f01   channel: beta
  url: …/download/v0.1.1283-beta+dc86f01/DuoPaste-0.1.1283-beta+dc86f01.dmg   edSig: True
title: Version 0.1.1282-beta+5699299   channel: beta
  url: …/DuoPaste-0.1.1282-beta+5699299.dmg   edSig: True
… (all 20 items in the head of the feed are tagged `beta` and carry `-beta+`
   in the filename)
```

**Verdict: currently correct and structurally protected** — every item is
both tagged and filename-marked as beta.

### 2.7 BetterDisplay channel-tag — content check

```
$ curl -s "https://betterdisplay.pro/betterdisplay/sparkle/appcast.xml" | <first 6 items>
title: 5.0.4   channel: internal
  url: …/releases/download/pre/BetterDisplay-v5.0.4-b53044.zip
title: 5.0.4   channel: internal
  url: …/releases/download/pre/BetterDisplay-v5.0.4-b52989.zip
title: 5.0.3   channel: pre
  url: …/releases/download/v5.0.3/BetterDisplay-v5.0.3-pre-release.dmg
title: 5.0.2   channel: pre
  url: …/releases/download/v5.0.2/BetterDisplay-v5.0.2-pre-release.dmg
title: 4.3.6   channel: (untagged/stable)
  url: …/releases/download/v4.3.6/BetterDisplay-v4.3.6.dmg
title: 5.0.1   channel: arm64_pre
  url: …/releases/download/v5.0.1/BetterDisplay-v5.0.1-pre-release.dmg
```

**Verdict: currently correct and structurally protected** — matches
`BetterDisplayChannel.swift`'s doc comment exactly (internal under rolling
`/pre/` tag, pre under per-version tag with `-pre-release` filename token,
stable untagged, `arm64_pre` present and correctly excluded from every
allowed set).

### 2.8 CleanShot X — could not measure the channel that actually matters

```
$ curl -s "https://updates.getcleanshot.com/v3/appcast.xml" | <first item>
<title>3.7.1</title> … <enclosure url="https://updates.getcleanshot.com/v3/CleanShot-X-3.7.1.dmg" …
```

This confirms the **legacy, frozen** feed (matches the doc comment: stuck at
3.7.1). It is **not** the feed `ChannelBinding` actually uses — that's the
personalized `legit.maketheweb.io/api/v1/appcast?key=<licenseKey>` feed,
which requires a real license key this session does not have.
**Could not measure** the feed duo-updater actually reads; relying on the
prior verification recorded in `docs/app-audits/pl-maketheweb-cleanshotx.md`
(2026-06-04: personalized feed head = 4.8.8 = installed). Not re-verified
this session. Moot for the channel-proof question regardless, since
CleanShot only ever resolves `.stable`.

### 2.9 Ghostty — single channel, sanity only

```
$ curl -s "https://release.files.ghostty.org/appcast.xml" | <first 3 items>
title: Build 8343   channel: (untagged/stable)   edSig: True
title: Build 8346   channel: (untagged/stable)   edSig: True   url: …/0.1.4/ghostty-macos-universal.zip
title: Build 8347   channel: (untagged/stable)   edSig: True   url: …/0.1.5/ghostty-macos-universal.zip
```

Confirms stable-only, signed, one-click-eligible — no channel question to
ask.

---

## 3. Which rows a proof entry would be a no-op for

| Binding | Channel(s) at risk | Structural protection today | Would a proof entry add anything? |
|---|---|---|---|
| DuoPaste (beta) | beta | `<sparkle:channel>` tag, enforced in `SparkleAppcastSource.usableItems` for every channel-tag app + filename also carries `-beta+` | **No-op** |
| BetterDisplay (beta="pre", unstable="internal") | pre / internal | Same tag mechanism + path-level corroboration for pre/stable | **No-op** |
| CleanShot X | none (stable only) | N/A — no non-stable channel exists | **No-op** |
| Ghostty | none (stable only) | N/A — no non-stable channel exists | **No-op** |
| **Fork (beta)** | beta | **None** — feed-swap, zero artifact marker, unsigned | **Real gap** |
| **Surge (beta)** | beta | **None** — feed-swap, zero artifact marker, signed (over-trust risk) | **Real gap** |
| **TablePlus (beta)** | beta | **None** — header-keyed, zero artifact marker beyond an incidental build number | **Real gap** |
| **IINA (beta)** | beta | **None** — feed-swap, zero artifact marker, currently dormant (feeds identical) | **Real gap** |

**Exactly half (4 of 8) are no-ops**, and the other half is the entire
feed-swap / header-keyed subset. This is precisely the shape the issue
warned about ("a proof table that is half no-ops is worse than none") —
except here it isn't a warning about a hypothetical table, it's a
measured split of the real population.

Worth stating plainly: the 4 "no-op" rows aren't no-ops because nobody
bothered to protect them — they're no-ops because `SparkleAppcastSource`'s
channel-tag filtering **already is** an equivalent-strength, code-level
guarantee that applies uniformly to every channel-tag app, VendorProbe or
Sparkle-native alike, without anyone having to remember to register
anything. That's arguably a stronger guarantee than `ChannelProofRegistry`
gives the VendorProbe population (a regex some author has to write and
which can silently rot) — it just isn't visible as a "proof" because it was
never designed as one.

---

## 4. Recommendation (not implemented)

The genuinely exposed rows (Fork, Surge, TablePlus, IINA) share a property
that makes them harder to close with the *same primitive* the existing
registry uses: **`ChannelArtifactProof.artifact(pattern)` needs a string in
the resolved URL to anchor on, and none of these four vendors puts a
channel token in the artifact at all.** Unlike OrbStack/Alfred/CapCut/
Tailscale/GitHub-rule cases — where the issue text and `ChannelProofRegistry`
comments describe a real path segment or filename token to regex against —
here the entire channel signal lives *outside* the response: in which URL
was requested, or which header was sent, before the vendor ever answered.
A regex proof on the *response* literally cannot see that decision.

Trade-offs, stated rather than decided:

- **Extend the two-map pattern with a third `ChannelBinding`-typed overload
  of `crossChannelArtifact`.** Matches the existing shape and reuses
  `ChannelProofKey`. But for Fork/Surge/TablePlus/IINA there is nothing
  honest to write as an `.artifact` pattern — the best available assertion
  is something weaker than what the type currently promises (e.g. "the
  beta feed's head version is not older than stable's," which is a
  staleness heuristic, not a channel proof, and would pass even if the
  vendor collapsed both feeds to the same content). Writing a proof entry
  that can't actually prove anything risks the opposite failure the issue
  is trying to prevent — a green check nobody should trust.
- **Extend the *exhaustiveness test* only, not a proof registry**, requiring
  a hand-written, honest note per `(bundleID, channel)` in this population
  — including "no artifact-level marker exists; protection is entirely
  'we asked the right URL'" for the four exposed rows. Cheaper, and it
  makes the real state of things impossible to overlook in a diff, without
  fabricating a check that would pass unconditionally.
- **A live differential check** (not a static proof): periodically fetch
  both feeds/both header states for these four apps and assert they are
  *not* byte-identical (or, for TablePlus, that the two responses' builds
  differ) — catching a vendor-side collapse the moment it happens rather
  than asserting a pattern that can't distinguish "the header worked" from
  "the header stopped mattering and both requests happen to return the
  same thing today." This is closest to what would have caught the actual
  failure mode described in the issue, but it is a monitoring addition, not
  a build-time guard, and the two kinds of protection are not substitutes
  for each other.

No implementation attempted per the task's scope. The choice among these
(or some combination) is the decision this report exists to inform.
