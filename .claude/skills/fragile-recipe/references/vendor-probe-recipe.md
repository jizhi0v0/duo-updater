# VendorProbeRecipe reference

Reads the latest version — and optionally the installer — straight from a vendor's
own endpoint, for apps no standard source (App Store / Sparkle / Homebrew / GitHub)
can resolve. `VendorProbeSource` runs these **last**, only after every standard
source misses, and swallows all failures to "unknown".

**This is the high-stakes path.** A wrong version makes the app lie — a phantom
"update available", or an installer aimed at the wrong build. The recipe's whole
design is about never doing that. The governing rule: *a probe that can't be made
confident must degrade to "unknown", never guess.*

## Order of preference for the endpoint

Pick the most robust source available; only fall down this list when forced:

1. **A version/JSON API** the vendor (or Homebrew's `livecheck`) already uses —
   stable, unambiguous, survives redesigns. Always prefer this.
2. **A redirecting "latest" download link** whose final filename carries the
   version (`…/Foo_3.2.1.dmg`) — robust, no body parsing.
3. **HTML scraping** of a product/release page — brittle; last resort. Comment it
   as such and expect to revisit it.

Tip: check the app's Homebrew cask `livecheck` block — it often names exactly the
stable endpoint you want.

## The recipe fields

```swift
VendorProbeRecipe(
    bundleID: String,
    url: URL,                  // endpoint to probe
    mode: .responseBody,       // .redirectFilename | .responseBody
    versionPattern: String,    // capture group 1 = version (anchored!)
    downloadURL: URL? = nil,   // where to send the user to download by hand
    changelogURL: URL? = nil,  // human-readable notes page (NOT the download)
    selectHighest: Bool = false,
    install: VendorInstallSpec? = nil,  // omit for detection-only (the safe default)
    followRedirects: Bool = true)
```

- **`.redirectFilename`** — `url` is a stable link that 302s to the real package;
  HEAD it, follow redirects, parse the version out of the final filename. Preferred
  when a versioned download filename exists.
- **`.responseBody`** — GET `url`, apply `versionPattern` to the body. For APIs and
  appcasts.
- **`versionPattern`** — capture group 1 is the version (whole match if no group).
  **Anchor it** to the app's own field so it can't grab an unrelated number
  (a plugin version, a min-OS, a build of something else). JSON example:
  `#""version"\s*:\s*"([0-9]+\.[0-9]+\.[0-9]+)""#`.
- **`selectHighest`** — when the body lists many releases. Use ONLY for
  ascending-ordered feeds whose pattern matches *nothing but* app versions; with a
  body that also holds version-shaped noise, "first match" (the app's own field,
  listed first) is correct and "highest" would grab a bigger unrelated number.
- **`followRedirects: false`** — for an endpoint that 302s to a *large binary*;
  reads the small 3xx body/`Location` instead of downloading the whole installer
  to read a version.

Extraction helpers on `VendorProbeRecipe` (pure, testable): `extractVersion`
(first match), `lastMatch` (last match — ascending feeds where newest is last),
`highestVersion` (max by version).

## The install spec (optional, highest-stakes)

Attach an `install` only when the app can be updated in place through its **own**
channel — never cross-channel. The download MUST be a notarized build signed by
the **same Team ID** as the installed copy; `VendorInstaller` enforces this gate,
but author defensively. If you can't verify that, ship **detection-only** (no
`install`) — the user downloads by hand.

`VendorInstallSpec(urlSource:, kind:, checksumPattern:)`:
- `kind`: `.zip` / `.dmg` / `.tarGz` / `.pkg` (drives unpacking; `.pkg` → opened in
  the system installer)
- `urlSource`: how to recover the installer URL from the body —
  `.bodyPattern` (first match), `.bodyPatternLast` (ascending feeds),
  `.bodyPatternRelative(_, base:)` (filename → resolve against base),
  `.bodyTemplate(_, fields:)` (build from several captures),
  `.redirect(URL)` (HEAD-follow a stable latest link), `.fixed(URL)`
- `checksumPattern`: optional regex (group 1) for a base64 SHA-512 in the same
  body, verified before unpacking — defense in depth on top of the signature gate

### `kind` is a safety decision, not just an unpacking hint

Since the default install policy became `.alwaysOverwrite` (2026-08-14), a running
app gets its bundle replaced and is then restarted. The argument that this is safe
rests on one invariant:

> **An app that installs anything outside its own `.app` bundle — a daemon, a
> launch item, a system extension, a helper in `/Library` — must be `kind: .pkg`.**

`.pkg` goes to macOS's own installer, which places those siblings properly.
`.zip` / `.dmg` / `.tarGz` are unpacked and the bundle is swapped **and nothing
else** — so choosing one of those for an app with sibling components ships an
updated `.app` next to stale daemons, with no error and nothing to notice.

Nothing in the code enforces this; it is a property of the recipes as written.
When authoring:

- Mount/expand the artifact and look at what is actually in it. If the vendor
  ships a `.pkg`, that is usually a signal in itself — check with
  `xar -tf <pkg>` whether the payload extends beyond the app.
- Look for a `LaunchDaemons` / `LaunchAgents` / `PrivilegedHelperTools` entry, a
  bundled system extension, or a `Contents/Library/LoginItems` the vendor also
  registers globally.
- If the vendor offers both a dmg and a pkg, prefer the **pkg** for anything that
  isn't a self-contained app.
- Existing examples: Tailscale (`kind: .pkg`, network extension + daemon), the
  Office suite and OneDrive (`.pkg`, MAU), Edge (`.pkg`). Chrome is `.dmg` and
  that is correct — Keystone lives inside the bundle.

If you cannot tell, ship **detection-only**. A missing one-click is a small loss;
a half-updated app with mismatched components is the kind of breakage that gets
blamed on the updater and is hard to diagnose.

## Validating against the real endpoint (do this before landing)

1. Note the **installed** version: `mdls -name kMDItemVersion "/Applications/<App>.app"`.
2. Fetch the endpoint (Python; `curl` is trapped — see SKILL.md) and run your
   `versionPattern` over the real body:

```bash
/usr/bin/python3 - <<'PY'
import re
body = open("/tmp/probe.html", encoding="utf-8").read()
m = re.search(r'<versionPattern here>', body)
print("extracted:", m.group(1) if m else None)
PY
```

3. **The extracted version must match or exceed the installed version.** If it's
   *lower*, your pattern caught the wrong number — fix it; do not ship. If you
   can't get a confident match, the right outcome is no recipe (app stays
   "unknown"), not a guess.

For an `install` spec, also confirm the resolved URL really points at the current
build and the host is the vendor's own.

## Register + test

Add the recipe to `VendorProbeRegistry.recipes` in `VendorProbeRecipe.swift`, with
a comment naming where the version lives, the Team ID if it installs, and any
rollout/format gotcha (study the neighbors — they encode real quirks like Chrome's
fractional rollout or VLC's ascending appcast).

Add a fixture test that feeds a trimmed real body to the extraction helper and
asserts the version, e.g.:

```swift
#expect(VendorProbeRecipe.extractVersion(from: fixture, pattern: pattern) == "1.2.3")
```

Then `cd DuoUpdaterCore && swift test`.

## Known-unfeasible (don't waste time)

Some endpoints can't be probed safely and are deliberately left out — account-gated
version APIs, JS bot-challenged appcasts, private SDK updaters, ad-hoc internal
builds. If the only path requires an auth token or defeating a bot wall, the honest
result is "unknown". See the comment block atop `VendorProbeRegistry` for the
current list and rationale.
