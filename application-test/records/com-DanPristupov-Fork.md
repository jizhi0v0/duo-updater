# Fork — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/Fork.app`), exercising the production `AppScanner.scan()` →
`ChannelBinding.resolve()` path, plus a direct fetch of the resolved feed.

Fork is a **feed-swap** app: the signed Info.plist `SUFeedURL` is always the
Developer feed, and the channel is a private preference `applicationUpdateChannel`
(Int; `2` → Stable, anything else / unset → Developer/**beta**, the shipped default).
`ChannelBinding` reads it via CFPreferences and swaps the Sparkle feed.

| Channel | real bundle id | real short ver | pref `applicationUpdateChannel` | detect()/binding | feed served (build) |
|---------|----------------|----------------|----------------------------------|------------------|---------------------|
| beta (default) | `com.DanPristupov.Fork` | `2.67.0` | **unset** → Developer feed | **beta** ✓ | `feed.xml` → 2.67.0 = installed, up to date |
| stable  | `com.DanPristupov.Fork` | `2.67.0` | `2` (temp) → `feed-stable.xml` | **stable** ✓ | `feed-stable.xml` reachable |

## Both channels confirmed on this machine (2026-06-04)
- **beta**: native state (`applicationUpdateChannel` unset) → `--scan` → beta ✓.
- **stable**: temporarily set `applicationUpdateChannel=2`, `--scan` → stable ✓, then
  **deleted the key to restore the original unset** (re-scan → beta ✓). Fork was left
  running; only the stored pref was toggled, never the process. End state == original.

## Notes
- This machine has the pref **unset**, so Fork is correctly on the **Developer/beta**
  channel — `detect`-style classification (display name / version) would never see
  this; only the ChannelBinding preference read does. This is the real, on-machine
  channel.
- VendorProbe intentionally returns nothing for Fork (its mechanism is the Sparkle
  feed, not a vendor probe). "VendorProbe → no version" in the harness is **expected**,
  not a miss.
- Stable is the opposite leg of the same pure `ForkChannel.resolve(channelPref:)`
  mapping (also covered by unit tests), now additionally confirmed end-to-end on a
  real bundle via the temporary-toggle method above.
- Fork's feeds carry no `<sparkle:channel>` tags and report versions in
  `sparkle:version` (build) not `shortVersionString`.

## Command
```
swift run --package-path application-test channel-verify --scan com.DanPristupov.Fork --expect beta
```
