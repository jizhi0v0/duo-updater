# AppStorePageCache: incident timeline and measurements

Companion to `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/AppStorePageCache.swift`.
The source file keeps the current contract; this file keeps *why it looks
that way* — incident timelines, measurements, and corrections to earlier
wrong comments. Written for issue #409.

⚠️ Every dated `measured`/`counted` number below is a **one-time measurement**,
not a metric this repo tracks over time, and not an installed-app inventory —
see `docs/engine-notes/README.md` for why that distinction has to hold for
anything living under `docs/engine-notes/`. §4.2 in particular records a
number that had already drifted once by the time it was written down; that is
not a reason to delete it, it's the reason to keep the date attached and not
restate it as a current fact without re-measuring.

---

## §1 Why this class exists: all the value is across scans, none within one

`resolve()` is a three-way dispatch with early returns, so exactly one of
`nativeMacVersion` / `remoteVersion(checkMacCompat:)` / `iosOnMacVersion` runs
per app per check — the version and compatibility pages use different URLs
*and* different dictionaries, so neither branch can serve the other. What
this class actually removes is the *second* scan's fetch, and the third's, up
to the TTL.

An earlier version of the class doc argued for this cache on a different
ground: that the pages are "read from more than one call site per app per
check." That was never true — the paragraph above is the correction. The real
benefit model is `1 − interval/ttl`:

- At a five-minute check interval, eleven rounds in twelve are free (as
  originally measured and quoted in the class doc: 23.6 → 3.0 product-page
  requests a round — date not recorded in the source comment this was
  carried over from, so treat it as an illustrative order-of-magnitude, not a
  reproducible figure).
- At the default check interval — six hours, per `Preferences` — `interval >
  ttl`: **this class saves nothing between scheduled sweeps** for a user who
  hasn't changed that setting, every round is a cold miss. (How many users
  have changed it is not something this repo can see — no telemetry — so
  that is as far as this claim goes.) What it still buys is the *second*
  scan inside one app launch: the scheduler ticks immediately on a cold
  start, and opening the workbench forces another refresh, so that pair
  costs one round of page fetches instead of two.

## §2 `shared`: the per-instance cache that measurably did nothing

`AppListModel.makeSources` rebuilds the whole source stack on every check —
deliberately, so a token change and the signed-in storefront region get
re-read — so a `MacAppStoreSource` lives about seven seconds. A per-instance
`AppStorePageCache` with a one-hour TTL is therefore born and destroyed
inside a single scan and never survives to answer the next one.

This was a real bug, not a hypothetical: **measured 2026-09-04**, the
product-page fetches per scan round did not fall at all after the cache
shipped (20.6 → 23.6 requests, 623 → 786 KB) — traffic went up, if anything —
while every other change landed in the same batch worked exactly as
predicted. The unit tests at the time missed it because they exercised one
`MacAppStoreSource` instance twice, which is exactly the case that was
already working; nothing in the suite constructed a *second* stack the way
production does on every check.

The fix is the `public static let shared` singleton. The regression test is
`aRebuiltSourceStackStillSeesTheCachedPage` in
`DuoUpdaterCore/Tests/DuoUpdaterCoreTests/MacAppStorePageCacheTests.swift`,
which deliberately builds two source stacks (the way two consecutive checks
do) rather than reusing one. That test's own doc comment repeats this same
measurement as the motivation for why it exists — that's the test explaining
itself, not a second copy of a spec that has to stay in sync with this file.

## §3 TTL = one hour: how it was picked, and why that reasoning doesn't hold today

The one-hour TTL was chosen on a machine set to check every five minutes. An
earlier version of the `ttl` doc comment wrote that setting down as a
property of the *product* — "a scan revisits the same app every few
minutes." It is not: the default check interval is six hours
(`Preferences`), and at that interval the TTL never spans two scheduled
scans in the first place (see §1's cost model) — the number was never doing
the job the old comment credited it with.

What the TTL actually bounds is staleness for `kind == "software"` listings
(iOS-on-Mac), which have no version source but this scraped page — see §4.1.
An hour is how long a user can be told yesterday's answer before
`invalidateAll` (any user-present refresh) resets it.

The claim that App Store product-page listings don't actually change more
than once an hour is **unverified** — nobody has measured real-world listing
update frequency to justify this specific number. It is a staleness ceiling
chosen for a different, since-corrected reason, not a tuned value.

## §4 `invalidateAll`: two incidents, in opposite directions

### §4.1 Why the TTL alone isn't enough

For a `kind == "software"` listing, the scraped page is the *only* version
source: `iosOnMacVersion` returns nil without it, and unlike
`nativeMacVersion` there is no lookup-API answer behind it to make a stale
page harmless. Before this cache existed, every check re-fetched, so a user
who read a release announcement and pressed Check Now got a live answer.
After the TTL was introduced without a full-wipe escape hatch, the same user
could have been told the same old version for up to an hour with no way to
insist — `invalidateAll`, called from `RefreshIntent.restartsChangelogs`
(a user-initiated refresh that's about to re-check every app anyway), is
that escape hatch.

Exactly how many installed apps take the `kind == "software"` route is not
answerable from the event log — it does not record which branch of
`resolve()` ran for a given request, so this is a structural blind spot, not
a number nobody has bothered to count.

### §4.2 `recheckMany` calling `invalidateAll` was a real bug

`recheckMany` (the per-row explicit recheck, e.g. after a channel-switch
prompt) used to call `invalidateAll()` too, on the theory that "we're about
to talk to the App Store anyway." That was wrong: **measured 2026-09-05, in
a live 45-minute window**, a single row's channel-flip recheck
(`recheckChannelSwitches` → `recheckMany`, 3 requests, 1 app) wiped every
*other* App Store app's cache entry as a side effect, and the next scheduled
sweep paid for it in full — 21/21 tracked App Store apps re-scraped, 975 KB
and 52 extra requests, where every other steady-state round cost close to
zero.

"21" is a count of Mac App Store apps that scrape a product page on the
development machine this was measured on, taken from the event store on
2026-09-05 (`select count(distinct app_id) ... where host='apps.apple.com'`).
It is quoted here, not re-verified for this pass — and it had already
drifted once before this note was written: an earlier version of the source
comment it's carried over from said "twenty." Treat it as an order of
magnitude illustrating the blast radius, not as a fact about this repo's
current app population; re-derive it from a live event store if it matters
for a decision.

The fix: `recheckMany` now calls `invalidate(bundleIDs:)` with just the rows
it actually re-checked, instead of the full-wipe `invalidateAll()`.

## §5 `invalidate(bundleIDs:)`'s known race window

"Forces a live scrape" only holds absent an overlapping sweep. A scheduled
check that already missed the cache for app X, and is still awaiting X's
page fetch when an `invalidate(bundleIDs:)` for X runs, will `storeVersionFacts`
a fresh entry once its fetch lands — and a recheck's own fan-out reading the
cache afterward can pick up that fresh entry instead of forcing its own
fetch. The window is one page fetch wide. This isn't new: `invalidateAll`
had the identical race before it was narrowed to `invalidate(bundleIDs:)`.
Closing it needs a per-key generation counter checked inside `storeVersionFacts`,
which nobody has written — this is written down so the next reader doesn't
take the "forces a live scrape" wording in the source comment at face value.

---

Tests: `DuoUpdaterCore/Tests/DuoUpdaterCoreTests/MacAppStorePageCacheTests.swift`.
