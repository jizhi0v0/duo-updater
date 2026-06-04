# OrbStack — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/OrbStack.app`). OrbStack is a **channel-tag** app on a **shared**
bundle id: one appcast (`appcast.new.xml`) with stable/beta/canary items via
`<sparkle:channel>`, reached through the VendorProbe path. The user's choice is the
literal channel name in `updates_optinChannel` (absent → stable).

| Channel | real bundle id | real short ver (build) | `updates_optinChannel` | detect()/binding | VendorProbe → verdict |
|---------|----------------|------------------------|------------------------|------------------|------------------------|
| stable  | `dev.kdrag0n.MacVirt` | `2.1.3` (`20115`) | **absent → stable** | stable ✓ | 2.1.3 = installed, up to date |
| beta    | `dev.kdrag0n.MacVirt` | `2.1.3` (`20115`) | `beta` (temp) | **beta** ✓ | appcast `beta` items |
| canary  | `dev.kdrag0n.MacVirt` | `2.1.3` (`20115`) | `canary` (temp) | **canary** ✓ | appcast `canary` items |

## All three channels confirmed on this machine (2026-06-04)
- **stable**: native state (`updates_optinChannel` absent) → `--scan` → stable ✓.
- **beta / canary**: temporarily set `updates_optinChannel` to `beta` then `canary`,
  `--scan` → beta ✓ / canary ✓, then **deleted the key** to restore the original
  absent/stable state (re-scan → stable ✓). OrbStack was not running. End state == original.

## Notes
- This machine is on **stable** (pref absent); the VendorProbe recipe answered with
  2.1.3 = installed → no phantom update.
- beta/canary share the same bundle id and are selected purely by `updates_optinChannel`;
  the pure `OrbStackChannel.resolve(channelString:)` mapping is unit-tested, and now also
  confirmed end-to-end via the temporary-toggle method above (pref restored to original).

## Command
```
swift run --package-path application-test channel-verify --scan dev.kdrag0n.MacVirt --expect stable
```
