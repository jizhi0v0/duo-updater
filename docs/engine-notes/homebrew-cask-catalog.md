# HomebrewCaskCatalog.swift

Companion notes for `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/HomebrewCaskCatalog.swift`.
See `README.md` in this directory for what belongs here and what stays in the code.

## §1 `depends_on.macos` — what the API actually serves

One-time measurement, **2026-09-15**, over the live
`https://formulae.brew.sh/api/cask.json` — 7723 casks, 18,808,119 bytes of JSON,
which arrives as 2,037,602 bytes on the wire (gzip, `curl -H 'Accept-Encoding:
gzip'`). Not a tracked metric; brew publishes constantly, so re-measure before
quoting it.

That wire figure is the one the code's "~2 MB … measured at 2007 KB on
2026-09-05" comments mean, and it has not moved. Four other comments called it
"the 5 MB catalog"; three of them — `ChangelogCache`, `BrewLocalInventory`,
`HomebrewCaskSource` — describe the same download and now say ~2 MB. The fourth,
in `URLSession+Updates`, is **not** a copy of that claim: it is about what
`URLCache` will store, i.e. the decompressed body, and 18.8 MB is even further
past the cache's ~5%-of-capacity ceiling than "5 MB" was. It was left alone.

| Fact | Count |
|---|---|
| casks in the catalog | 7723 |
| casks with a `depends_on.macos` key | 5003 |
| …of which render as the empty object `{}` (i.e. **no** constraint) | 3445 |
| …of which state a constraint | 1558 |
| `{">=": ["<major>"]}` | 1554 |
| `{"==": [...]}` | 4 |
| `{"<=": ...}` | **0** |

`>=` values, all single-element: `12` ×714, `13` ×382, `14` ×287, `15` ×126,
`26` ×38, `11` ×4, `27` ×3 (`agentide`, `minmaxcal`, `onyx@beta`).

The four `==` casks are the Titanium tools — `calhash`, `deeper`, `maintenance`,
`onyx` — each `["11","12","13","14","15","26"]`. Note the gap: 16 through 25 are
absent, so `==` is a membership test, not a range.

Every declared value in that snapshot is a bare numeric major string. The code
still fails **open** on anything else (a symbolic `:big_sur`, an empty list):
hiding a cask from the index is the failure mode this whole area exists to
remove, so an unreadable declaration admits everyone.

`<=` is parsed even though the catalog contains none today. Treat "there is a
`<=` cask" as unmeasured rather than as false-forever.

## §2 Why the indexes are no longer first-writer-wins (issue #638)

141 `.app` filenames are claimed by more than one cask; 38 of those groups
disagree about `depends_on.macos`. Until #638 both indexes were pure catalog
order, so the shape below resolved to the cask brew itself refuses to install:

| cask | version | `depends_on.macos` | artifact |
|---|---|---|---|
| `onyx` (catalog position 5636) | 5.0.4 | `== [11,12,13,14,15,26]` | `OnyX.app` |
| `onyx@beta` (5637) | 5.1.0,260910 | `>= 27` | `OnyX.app` |

On macOS 27 `byAppFilename["onyx.app"]` was always `onyx`: a user on 5.1.0 fell
to `.unknown` (the provenance gate asks for the `onyx` token, which isn't
installed), and a user still on 5.0.4 was told "up to date" about a build that
cannot be installed there at all. Neither cask names a bundle id, so the
`utm`/`utm@beta` escape hatch (`entries(forBundleID:)`) did not apply.

The rule now has two halves, and the second one matters as much as the first.

**In the index**: both keys keep every declaring cask in catalog order
(`allByAppFilename`, `allByBundleID`), and both single answers are derived from
them by the same rule — the first entry this host admits, else the first entry,
so a host outside every cask's window still gets an answer rather than a hole.
Deriving both the same way is deliberate: the two lookups for one key cannot
disagree, and a hand-built test index cannot make them disagree either.

**In the source**: `HomebrewCaskSource` asks for *all* candidates and prefers the
cask that is actually **installed** here, using the host preference only to break
a tie among installed ones. Host-preference alone would have swapped which half
of the pair is broken rather than fixing it: someone who installed `onyx` on
macOS 26 and then upgraded to 27 would ask the Caskroom for `onyx@beta`, miss,
and drop from a correct "up to date" row to `.unknown` — there is no OnyX recipe
in either registry to catch them. Installed-beats-runnable answers both users.

## §3 What the bundle-id side could **not** be tested against

Measured the same day over every `uninstall: quit:` group: **no** group's first
cask is excluded on macOS 26 or 27 while a later one is admitted. So the
realistic host-27 split exists only on the app-filename side, and the regression
test uses the one real shape that does exist for bundle ids —
`carbon-copy-cloner` (`>= 13`) followed by `carbon-copy-cloner@6` (no
constraint), both declaring `com.bombich.ccc` — which only separates below macOS
13. When a Titanium-style pair does appear with a bundle id, prefer it.

## §4 Not verified

Nothing here was observed on a macOS 27 machine; there is none to hand. The host
version is injected (`HomebrewCaskCatalog(hostOSVersion:)`, defaulted to
`HostOS.numericVersion()` exactly like `SignatureVerifier`'s `osVersion`), so the
rule is exercised as a pure function against fixtures built from real response
bodies — see `HomebrewCaskMacOSConstraintTests`, whose header carries the
mutation table (12 mutations, all applied and all red).

Also not verified: that brew's own `depends_on macos` semantics match this
reading for a cask declaring **two** operators at once. None exists today, so
`parse` refuses that shape outright (→ no constraint) rather than keeping an
arbitrary half of it — dictionary iteration order would otherwise make the
index differ between launches of the same binary.
