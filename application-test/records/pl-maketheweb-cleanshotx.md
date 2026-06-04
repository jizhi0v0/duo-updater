# CleanShot X — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/CleanShot X.app`) via the production `AppScanner.scan()` →
`ChannelBinding.resolve()` path, plus a fetch of the resolved personalized feed.

CleanShot is a single **stable** channel, but with a feed twist: the signed
Info.plist `SUFeedURL` points at the legacy v3 appcast frozen at 3.7.1. The real 4.x
updates come from the maketheweb "Legit" licensing service, a per-license
entitlement-filtered appcast. `ChannelBinding` reads `activationKey` from CleanShot's
plaintext prefs and swaps the feed to `legit.maketheweb.io/api/v1/appcast?key=<key>`.

| Channel | real bundle id | real short ver | `activationKey` | detect()/binding | resolved feed head |
|---------|----------------|----------------|-----------------|------------------|--------------------|
| stable  | `pl.maketheweb.cleanshotx` | `4.8.8` | present | **stable** ✓ | 4.8.8 = installed, up to date |

## Notes
- The license key is a credential: it is **never logged**. This record states only
  that a key is present and the feed head is 4.8.8 — the URL/key is not printed.
- The legit feed correctly reports **4.8.8** (= installed), eliminating the
  `4.8.8 ↓ 3.7.1` phantom downgrade the frozen v3 feed would otherwise produce.
- VendorProbe intentionally returns nothing (mechanism is the license Sparkle feed).
  The harness "VendorProbe → no version" is **expected**.

## Command
```
swift run --package-path application-test channel-verify --scan pl.maketheweb.cleanshotx --expect stable
```
