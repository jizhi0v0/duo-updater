# TablePlus — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/TablePlus.app`) via the production `AppScanner.scan()` →
`ChannelBinding.resolve()` path, plus both header variants of the shared feed.

TablePlus is a **header-keyed** app: stable and beta share ONE appcast
(`https://tableplus.com/osx/version.xml`); the server returns beta builds only when
the request carries `X-Tiny-Beta-Update: true`. The opt-in lives in
`ViewSetting.IsReceiveBetaBuild` (Bool) in TablePlus's UserDefaults. Note the real
bundle id is `com.tinyapp.TablePlus` (mixed-case) but prefs live under the
lower-cased domain — `ChannelBinding` matches case-insensitively.

| Channel | real bundle id | real short ver (build) | `IsReceiveBetaBuild` | detect()/binding | feed (header) → served |
|---------|----------------|------------------------|----------------------|------------------|------------------------|
| beta    | `com.tinyapp.TablePlus` | `6.9.1` (`670`) | **1 (true)** | **beta** ✓ | header `true` → 7.1.1/711 (update available) |
| stable  | `com.tinyapp.TablePlus` | `6.9.1` (`670`) | 0 (temp) | **stable** ✓ | no header → 7.1.0/710 |

## Both channels confirmed on this machine (2026-06-04)
- **beta**: native state (`ViewSetting.IsReceiveBetaBuild=1`) → `--scan` → beta ✓.
- **stable**: snapshotted the full domain, flipped the nested `IsReceiveBetaBuild` to
  `false` (preserving the rest of `ViewSetting`), `--scan` → stable ✓, then restored the
  snapshot (re-scan → beta ✓). TablePlus left running; only the stored pref toggled.
  End state == original (`1`).

## Notes
- `IsReceiveBetaBuild = 1` on this machine → TablePlus is genuinely on **beta**.
- The header is load-bearing: the same URL returns **710** without it and **711** with
  it — the whole channel split. Confirmed live with both header variants.
- Beta shows a real available update (installed 6.9.1/670 → 7.1.1/711); the mechanism
  works.
- VendorProbe intentionally returns nothing (mechanism is the header-keyed Sparkle
  feed). The harness "VendorProbe → no version" is **expected**.

## Command
```
swift run --package-path application-test channel-verify --scan com.tinyapp.TablePlus --expect beta
```
