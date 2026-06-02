# ChangelogRecipe reference

Turns a vendor's changelog **page** into a structured `Changelog` that the detail
window renders natively (version headers + bulleted lists). This sidesteps the
problems of embedding a vendor page in a `WKWebView` — white-on-white text,
content cut off, site chrome. It's the **third tier** of changelog rendering, in
this priority order:

1. `releaseNotesHTML` — inline notes the update source already gave us (Sparkle, GitHub)
2. **structured extraction (this recipe)** — when a recipe exists for the bundle id
3. `changelogURL` embedded in a `WKWebView` — the previous fallback
4. empty state

A recipe that extracts nothing returns `nil`, and the UI drops to tier 3. That
benign fallback is *why* you can author these aggressively.

## The output model (what you're producing)

`Changelog { entries: [Entry] }`, `Entry { version: String; date: String?; items: [String] }`.
Date is kept **verbatim** as printed (display only — don't parse it). Items keep
their emoji/category prefixes (✨ 🔔 🎨) inline as the vendor wrote them.

## The recipe fields

```swift
ChangelogRecipe(
    bundleID: String,          // CFBundleIdentifier, lowercase by convention
    source: URL,               // the changelog page to fetch
    entryPattern: String,      // iterated; ONE MATCH = ONE VERSION BLOCK
    itemPatterns: [String],    // tried in order; first that yields ≥1 item wins
    mode: .html,               // .html | .json (default .html)
    stripTags: true,           // strip inner <b>/<a>… from captured text
    decodeEntities: true,      // &quot; &amp; &#39; … → real chars
    maxEntries: 40,            // changelogs run for years; cap the recent ones
    minItemLength: 1,          // drop change lines shorter than this after cleaning
    indexLinkPattern: nil)     // set for two-stage "index → latest" recipes (below)
```

`entryPattern` is matched with **dot-matches-newline + case-insensitive**, so a
single `.*?` spans a multi-line block. Named capture groups it consumes:
- `version` (**required**) — the version string
- `date` (optional) — wrap as `(?:…(?<date>…)…)?` so an entry with no date still matches
- `body` (optional) — the chunk `itemPatterns` then run against; if absent, the
  patterns run against the whole entry match

`itemPatterns` consume an `item` named group, else capture group 1, else the whole
match. **Redundancy is a feature**: list several patterns to survive a page's
old/new markup variants without branching code — the first that produces any item
wins per entry.

The recipe is forgivingly `Codable`: a remote/JSON-authored recipe needs only
`bundleID`, `source`, `entryPattern`, `itemPatterns`; every tuning field defaults.

## Worked example — CleanShot X

Real markup (Nuxt, regular):

```html
<div class="version" data-v-62d3e76f>
  <div class="number" data-v-62d3e76f>4.8.8</div>
  <div class="date" data-v-62d3e76f>23 March, 2026</div>
  <ul class="changes" data-v-62d3e76f>
    <li class="change" data-v-62d3e76f>Fixed issue with recording microphone …</li>
    <li class="change" data-v-62d3e76f>Fixed bug with the &quot;Ask for Name&quot; dialog …</li>
  </ul>
</div>
```

Recipe:

```swift
ChangelogRecipe(
    bundleID: "pl.maketheweb.cleanshotx",
    source: URL(string: "https://cleanshot.com/changelog")!,
    entryPattern:
        #"<div class="version"[^>]*>\s*"#
        + #"<div class="number"[^>]*>(?<version>[^<]+)</div>\s*"#
        + #"(?:<div class="date"[^>]*>(?<date>[^<]*)</div>\s*)?"#
        + #"<ul[^>]*class="changes"[^>]*>(?<body>.*?)</ul>"#,
    itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#]),
```

Note the loose attribute matching (`[^>]*`) so a stray `data-v-*` hash or
attribute-order change doesn't break the match.

## Two-stage recipes — `indexLinkPattern` (the per-version-page case)

Some vendors give **each release its own page** with no single "latest" or
all-versions page to parse (VLC's `/vlc/releases/3.0.23.html`, Ghostty's
`/docs/install/release-notes/1-3-1`). The naive recipe pins `source` to one
version's URL and needs a manual bump every release — workable but a chore.

If the vendor also publishes a **newest-first index** (a list of per-version
links, latest first), prefer a two-stage recipe instead:

- `source` points at the **index** page, not a changelog.
- `indexLinkPattern` is a regex whose `link` named group (else capture group 1)
  is the first per-version link. `ChangelogService` fetches `source`, takes the
  **first** match (= latest), resolves it against `source`, and runs
  `entryPattern`/`itemPatterns` on **that** detail page — which you write exactly
  as for a direct-source recipe.

This auto-tracks the latest release with zero maintenance, and — crucially —
**follows the real href**, so it sidesteps version→URL naming quirks. VLC folds
`3.0.19/3.0.20` (and `3.0.22/3.0.23`) onto a single page, so the page is *not*
always named after the latest version; templating a version number into the URL
would 404, but following the index link is always correct. It also needs **no
caller-supplied version**, so nothing changes in the app — the existing
`load(recipe)` path resolves the URL itself.

```swift
ChangelogRecipe(
    bundleID: "org.videolan.vlc",
    source: URL(string: "https://www.videolan.org/vlc/releases/")!,   // the index
    entryPattern: #"<h1[^>]*>(?:[\d.]+/)*(?<version>[\d.]+)\s*Fixes</h1>\s*(?<body>.*?)(?=<h1|</section>)"#,
    itemPatterns: [#"<li[^>]*>(?<item>.*?)</li>"#],
    maxEntries: 1,
    indexLinkPattern: #"href="(?<link>/vlc/releases/\d[^"]*\.html)""#)   // follow first link
```

Anchor `indexLinkPattern` tightly enough that nav/footer links (`/vlc/features.html`)
can't be picked — require the version-path shape (e.g. `/vlc/releases/\d…`). The
first match in document order must be the newest release; confirm that against
the real index (vendors put newest first, but verify).

When the vendor has no index, fall back to a version-pinned `source` and note in
the comment that the URL needs bumping when a new version ships (as the older Warp
/ Ghostty entries did before they moved to indexes).

## Validating against the real page (do this before landing)

Run the *same* regex over the fetched bytes and eyeball the result:

```bash
/usr/bin/python3 - <<'PY'
import re
h = open("/tmp/probe.html", encoding="utf-8").read()
entry = re.compile(
    r'<div class="version"[^>]*>\s*<div class="number"[^>]*>(?P<version>[^<]+)</div>\s*'
    r'(?:<div class="date"[^>]*>(?P<date>[^<]*)</div>\s*)?'
    r'<ul[^>]*class="changes"[^>]*>(?P<body>.*?)</ul>', re.S | re.I)
item = re.compile(r'<li[^>]*>(?P<item>.*?)</li>', re.S | re.I)
ms = list(entry.finditer(h))
print("entries:", len(ms))
for m in ms[:3]:
    items = item.findall(m.group("body"))
    print(f"  {m.group('version')} | {m.group('date')} | {len(items)} items | {items[0][:50]!r}")
PY
```

Healthy output for CleanShot: ~78 entries, sane version/date, ≥1 item each. If
entries == 0 your `entryPattern` is wrong; if items == 0 your `itemPatterns` are.

For a **two-stage** recipe, validate the whole chain end to end before landing:
fetch the index, apply `indexLinkPattern` to get the first link, fetch *that* URL,
then run the entry/item regexes on it. Confirm the followed URL is the latest
release and the detail parse yields sane entries — the same Python snippet, with a
`urljoin(index, first_link)` step in the middle.

## Register + test

Add the recipe to `ChangelogRecipeRegistry.recipes` in `ChangelogRecipe.swift`.

Add a test to `ChangelogExtractorTests.swift` with an **inline fixture** (a trimmed
copy of the real markup, including at least one HTML entity to prove decoding) and
assert entry count, version, date, item count, and a decoded item. Pattern:

```swift
@Test func extractsXEntries() throws {
    let recipe = try #require(ChangelogRecipeRegistry.recipe(forBundleID: "<id>"))
    let cl = try #require(ChangelogExtractor.extract(from: fixture, using: recipe))
    #expect(cl.entries.first?.version == "…")
    #expect(cl.entries.first?.items.count == …)
}
```

For a two-stage recipe, also add a `ChangelogService.firstLink(in:pattern:base:)`
test (it's pure/offline): paste a trimmed index slice that includes a decoy
nav/footer link, and assert the resolved absolute URL is the latest release page —
proving the anchor skips non-version links. See `followsFirstVLCReleaseLink…`.

Then `cd DuoUpdaterCore && swift test --filter ChangelogExtractorTests`.

## To see it in the UI (optional)

Rebuild and relaunch the menu-bar app, then open Changelog and select the app:
`cd App && xcodebuild -project DuoUpdater.xcodeproj -scheme DuoUpdater -configuration Debug build`,
then `open` the built `.app` (use the **full** DerivedData path — a `DuoUpdater-*`
glob can match multiple build dirs and launch several copies).
