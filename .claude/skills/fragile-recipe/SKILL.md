---
name: fragile-recipe
description: >-
  Author a "fragile recipe" for one app in the duo-updater repo — either a
  ChangelogRecipe (turn a vendor's changelog page into native structured entries)
  or a VendorProbeRecipe (read the latest version, and optionally the installer,
  straight from a vendor's own endpoint). Use this whenever the user wants to add,
  fix, or extend per-app changelog or version-detection support: phrases like "add
  a changelog for X", "X's release notes don't show up", "duo-updater can't see
  updates for X", "the recipe for X broke", "make Y's version detectable", or
  names a specific app whose notes/updates the app should surface. Both paths share
  one fetch→inspect→regex→validate-on-the-real-response→register→test loop; this
  skill walks it and encodes the safety rules that differ between the two.
---

# Authoring a fragile recipe

duo-updater stands on existing feeds (Sparkle / Homebrew / App Store / GitHub)
wherever it can. For everything else there are two hand-authored "recipe"
registries — small, declarative, per-app, and deliberately fragile (vendor pages
move). This skill adds or repairs one recipe end to end.

## Which recipe am I writing?

Decide first; the rest of the loop is shared but the stakes differ sharply.

| You want… | Recipe | Registry | Stakes |
|---|---|---|---|
| The app's **changelog** rendered natively (it has no inline notes) | `ChangelogRecipe` | `ChangelogRecipeRegistry` | **Low** — a bad parse just falls back to the embedded web page |
| To **detect the latest version** (no Sparkle/brew/MAS/GitHub coverage), maybe install it | `VendorProbeRecipe` | `VendorProbeRegistry` | **High** — a bad parse can invent a false "update available" |

If the app already shows updates but has no readable changelog → ChangelogRecipe.
If it shows as "unknown" (no source can answer) → VendorProbeRecipe.

Then read the matching reference for the field-by-field detail and worked
examples — don't author from memory:
- `references/changelog-recipe.md`
- `references/vendor-probe-recipe.md`

## The shared loop

1. **Identify the target.** Get the app's `CFBundleIdentifier` (it keys both
   registries) and the URL/endpoint to parse. If only the app name is known and
   it's installed: `mdls -name kMDItemCFBundleIdentifier "/Applications/<App>.app"`.
   Also note the **installed version** (`mdls -name kMDItemVersion …`) — you need
   it to sanity-check a vendor probe later.

2. **Fetch the raw response.** See "Fetching" below — `curl` is intercepted by a
   local shell wrapper, so use Python or WebFetch.

3. **Inspect the real structure.** Look at the *actual* bytes, not a
   markdown-rendered summary. Find the repeating shape (changelog: the
   version-block markup; probe: where the version literal lives — a JSON field is
   far better than HTML). Quote a real sample into your notes.

4. **Write the recipe** following the type's reference. Keep patterns anchored and
   specific so they can't match unrelated numbers/markup.

5. **VALIDATE against the real response before landing anything.** This is the
   step that separates a working recipe from a plausible-looking one. Run your
   regex over the bytes you actually fetched and confirm the output:
   - Changelog: how many entries matched? Do version/date/items look right on a
     few spot-checked entries?
   - Vendor probe: does the extracted version **match or exceed the installed
     version**? If it's *lower*, your pattern grabbed the wrong number — fix it,
     never ship it. A probe that can't be made confident must degrade to
     "unknown", not guess.

   Do this with a throwaway Python snippet over the fetched file (same regex you'll
   put in Swift) — it's the fastest honest check and needs no rebuild.

6. **Register it** — add the recipe to the right registry array, with a comment
   explaining where the version/notes live and any rollout/format gotcha (match the
   surrounding entries' comment style; they document hard-won quirks).

7. **Add a fixture test.** Drop a trimmed slice of the *real* response into a test
   and assert the parse. Tests run offline, so paste a representative fixture
   string rather than hitting the network. Extend the existing test file for that
   recipe type.

8. **Run `swift test`** from `DuoUpdaterCore/` and confirm green:
   `cd DuoUpdaterCore && swift test --filter <TestName>`.

   Logic lives in the `DuoUpdaterCore` SwiftPM package, so `swift test` fully
   exercises a recipe + its parser. Rebuilding the menu-bar app
   (`cd App && xcodebuild …`) is only needed to *see* the result in the UI, not to
   validate a recipe — leave that for when the user wants to eyeball it.

## Fetching (read this — `curl` is trapped)

A local zsh wrapper intercepts `curl` whenever the command line contains a URL and
fails with a misleading directory error (`目录不存在: -c`). `command curl` doesn't
escape it either. **Don't fight it — fetch another way:**

```bash
/usr/bin/python3 - <<'PY'
import urllib.request
req = urllib.request.Request(
    "<URL>",
    headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"})
data = urllib.request.urlopen(req, timeout=25).read()
open("/tmp/probe.html", "wb").write(data)
print(len(data))
PY
```

A browser-like User-Agent matters — several vendor endpoints reject unfamiliar
agents (the same reason `VendorProbeSource` and `ChangelogService` send one).
`WebFetch` is fine for a quick human-readable look, but it returns
markdown-converted text, so for **writing and validating a regex you need the raw
bytes** — use the Python fetch and inspect/validate against the saved file.

## The asymmetry that drives everything

These two recipes look alike but carry opposite risk, and the safety rules follow
from that — internalize it rather than memorizing rules:

- **A wrong changelog is cosmetic.** Worst case the user sees messy or empty notes,
  and the UI silently falls back to embedding the vendor's own page. So a
  ChangelogRecipe can be loose, redundant (try several `itemPatterns`), and is
  even `Codable` for future remote shipping. Bias toward shipping coverage.

- **A wrong version probe lies to the user.** It can claim an update exists when it
  doesn't, or point an installer at the wrong build. So a VendorProbeRecipe must be
  conservative: **prefer a JSON/version API over scraping HTML**, anchor the
  pattern so it can't catch a stray number, verify extracted ≥ installed, and when
  in doubt leave the app "unknown" (honest) rather than guess (harmful). An
  `install` spec is higher-stakes still — only attach one when the download is a
  notarized build signed by the **same Team ID** as the installed app (the
  mandatory gate in `VendorInstaller`); detection-only is the safe default.

When unsure on the probe side, the correct move is always to do less: narrower
pattern, detection-only, or no recipe at all.

## File map

Changelog (all under `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/`):
- `Changelog.swift` — the output model the UI renders (don't usually touch)
- `ChangelogRecipe.swift` — the recipe struct **and** `ChangelogRecipeRegistry`
- `ChangelogExtractor.swift` — the pure parser (don't usually touch)
- `ChangelogService.swift` — the network fetch (don't usually touch)
- test: `Tests/DuoUpdaterCoreTests/ChangelogExtractorTests.swift`

Vendor probe (same `Sources/` dir):
- `VendorProbeRecipe.swift` — the recipe struct, install spec, **and**
  `VendorProbeRegistry`
- `VendorProbeSource.swift` — the runtime that runs recipes (don't usually touch)
- tests live alongside the other `*Tests.swift` for probes

Adding a recipe almost always means editing exactly one file: the registry that
holds the recipe table, plus its fixture test.
