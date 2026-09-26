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
`<=` cask" as unmeasured rather than as false-forever — and note that zero live
occurrences is precisely why its test is hand-built: nothing real exercises that
branch, so a reversed comparison would wait silently for the first vendor to ship
one and then hide that cask.

## §2 Why the indexes stopped answering with one cask (issue #638)

**141** `.app` filenames are claimed by more than one cask — that is the raw
catalog; **135** after the `version == "latest"` filter the indexer applies, which
is the number that matters here. **35** of those groups disagree about
`depends_on.macos` under the code's own reading, where a missing key and a
rendered `{}` are both "unconstrained" (counting the raw JSON text instead, where
`null` and `{}` look different, gives 38 — that difference is notation, not
casks). Until #638 both indexes were pure catalog order, so the shape below
resolved to the cask brew itself refuses to install:

| cask | version | `depends_on.macos` | artifact |
|---|---|---|---|
| `onyx` (catalog position 5636) | 5.0.4 | `== [11,12,13,14,15,26]` | `OnyX.app` |
| `onyx@beta` (5637) | 5.1.0,260910 | `>= 27` | `OnyX.app` |

On macOS 27 the `onyx.app` lookup was always `onyx`: a user on 5.1.0 fell to
`.unknown` (the provenance gate asks for the `onyx` token, which isn't
installed), and a user still on 5.0.4 was told "up to date" about a build that
cannot be installed there at all. Neither cask names a bundle id, so the
`utm`/`utm@beta` escape hatch (`entries(forBundleID:)`) did not apply.

**The index now picks nothing.** Both keys keep every claiming cask in catalog
order (`allByAppFilename`, `allByBundleID`) and there is no single-answer
accessor, because choosing needs two facts the catalog does not have: the host's
macOS version and which cask the Caskroom holds. Indexing is therefore a pure
function of the catalog bytes — no host reaches it at all.

**`HomebrewCaskSource` picks**, with the cask that is actually **installed**
beating the one that is merely runnable, and `CaskEntry.preferred(among:
hostOSVersion:)` — first admitted, else first — breaking ties among installed
ones. Host preference alone would have swapped which half of the pair is broken
rather than fixing it: someone who installed `onyx` on macOS 26 and then upgraded
to 27 would ask the Caskroom for `onyx@beta`, miss, and drop from a correct "up
to date" row to `.unknown`; there is no OnyX recipe in either registry to catch
them. Installed-beats-runnable answers both users.

**One copy of the rule, on purpose.** The first version of this change also kept
a host-filtered `byAppFilename` / `byBundleID` on `CaskIndex`. Review found that
nothing in production read them — deleting them and reverting to `entries.first`
changed nothing a user could see — so every mutation aimed at those maps was
evidence about dead code, not about behaviour. The accessors are gone and the
source calls the shared rule.

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
version is injected (`HomebrewCaskSource(hostOSVersion:)`, defaulted to
`HostOS.numericVersion()` exactly like `SignatureVerifier`'s `osVersion`), so the
rule is exercised as a pure function against fixtures built from real response
bodies — see `HomebrewCaskMacOSConstraintTests`, whose header carries the
mutation table (every row applied and measured; the one that stays green on
the test you would expect, and why, is marked there).

`>=` is a floor and asks `SignatureVerifier.canRun`, the predicate install-time
gate 6 asks, so the two cannot disagree (`HostOS` lists the sites). `==`
and `<=` are not floors and keep their own truncate-then-compare, which splits
the host on `.` only while `VersionComparator` also splits on `- _ + space ( )`.
So `== 13-1` refuses 13.1.0 while `== 13.1` admits it. No live value has that
shape (every one was a bare major when measured, §1), and it is not fixed.

Also not verified: that brew's own `depends_on macos` semantics match this
reading for a cask declaring **two** operators at once. None exists today, so
`parse` refuses that shape outright (→ no constraint) rather than keeping an
arbitrary half of it — dictionary iteration order would otherwise make the
index differ between launches of the same binary.

## §5 Disabled casks are not indexed

`index(fromCatalogJSON:)` drops every cask whose catalog entry says
`"disabled": true`, the same way it drops `version == "latest"`. Before this a
brew-installed app whose cask was disabled resolved like any other, and its
one-click `brew install --cask --force <token>` was refused by brew.

**What brew does**, read in brew 7.0.6 (`/opt/homebrew/Library/Homebrew`,
commit `f420e01`, 2026-09-26):

- `cask/installer.rb` `check_deprecate_disable` (lines 223–236), first call in
  `prelude` (line 969), which `fetch` runs before the download: `:deprecated`
  prints a warning (`opoo`), `:disabled` raises `CaskCannotBeInstalledError`.
  `--force` does not skip it.
- `deprecate_disable.rb` `type` returns `:deprecated` **before** it asks
  `disabled?`. A cask that carries both a past `deprecate!` and a past
  `disable!` is therefore only warned about on install. Checked with
  `brew ruby`, which reported `DeprecateDisable.type` as `:disabled` for
  `1kc-razer` and as `:deprecated` for `bonitastudiocommunity` and
  `1password-cli@1`, all three `disabled? == true`.
- `cask/upgrade.rb` `outdated_casks` (lines 46 and 60) skips **every**
  `disabled?` cask, deprecated or not, with "Not upgrading <token>, it is …".
- `docs/Deprecating-Disabling-and-Removing.md`: deprecated "_should_ no longer
  be used … the action proceeds"; disabled "_cannot_ be used … the action
  fails", and disabled casks are removed a year after their disable date.
- `disable!` with a **future** date (`cask/dsl.rb`) sets `deprecated`, not
  `disabled`, until the date passes. brew re-evaluates the date locally when it
  loads a cask from the API (`cask/cask_loader.rb` replays `disable!`); the
  catalog's `disabled` is computed when the JSON is generated.

**So all disabled casks go, not only the ones `brew install` refuses.** The
one-click stands in for `brew upgrade`, which refuses them all, and the 218
that `brew install` lets through do so only because of the check order above.
Deprecated casks stay: brew installs and upgrades them with a warning.

**Not detection-only either.** `SourceStack` takes the first source that
answers and Homebrew sits ahead of Sparkle. A disabled cask no longer tracks
upstream, so its version would answer "up to date" or "update to X" from a
frozen snapshot, and shadow a source that does track upstream. Returning nothing
lets the row fall through (or end `.unknown`, as for any unmatched app).

**Counts**, the live catalog on 2026-09-26 (`last-modified` 11:01 GMT, 7761
casks). A one-time measurement, not a tracked metric:

| Fact | Count |
|---|---|
| `disabled: true` | 881 |
| …and also `deprecated: true` (`brew install` only warns) | 218 |
| …not deprecated (`brew install` raises) | 663 |
| …also `version == "latest"` (already dropped) | 11 |
| …matchable by `.app` or `uninstall: quit:`, not `latest`, not `auto_updates` | 650 |
| `disable_date` in the past but `disabled: false` | 0 |
| `disable_date` in the future (all `deprecated: true`, `disabled: false`) | 12 |
| casks indexed, before → after this filter | 5615 → 4745 |
| `.app` filenames claimed by more than one indexed cask (§2's 135) | 114 |

The zero row is what keeps reading the catalog's `disabled` (rather than
comparing `disable_date` to today) honest: the JSON had caught up with every
passed date. The window where it has not is the time until brew next
regenerates the catalog, plus this index's six-hour TTL; in it, a cask whose
future `disable!` date just passed is still offered and brew refuses it.

**Not verified:** the actual `brew install --cask --force` terminal output for a
disabled cask. Running it was declined in the session that made this change, so
the behaviour above is from the source and from `brew ruby`, not from the CLI.
Tests and the mutation table: `HomebrewCaskDisabledTests`.
