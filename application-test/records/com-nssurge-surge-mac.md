# Surge — channel verification record

Verified 2026-06-04 with `channel-verify --scan` against the **installed** bundle
(`/Applications/Surge.app`) via the production `AppScanner.scan()` →
`ChannelBinding.resolve()` path, plus a direct fetch of the resolved feed.

Surge is a **feed-swap** app whose choice lives in `IncludeBetaBuilds` inside
`~/Library/Application Support/com.nssurge.surge-mac/KDDefaults.plist` (NOT in
UserDefaults). `ChannelBinding` reads that plist and picks the public feed.

| Channel | real bundle id | real short ver (build) | `IncludeBetaBuilds` | detect()/binding | feed served |
|---------|----------------|------------------------|---------------------|------------------|-------------|
| beta    | `com.nssurge.surge-mac` | `6.6.0` (`11270`) | **true** | **beta** ✓ | `appcast-signed-beta.xml` → 6.6.0/11270 = installed, up to date |
| stable  | `com.nssurge.surge-mac` | `6.6.0` (`11270`) | false (temp) | **stable** ✓ | `appcast-signed.xml` reachable |

## Both channels confirmed on this machine (2026-06-04)
- **beta**: native state (`IncludeBetaBuilds=true`) → `--scan` → beta ✓.
- **stable**: `IncludeBetaBuilds` lives in a file Surge reads directly (not cfprefsd), so
  toggled via a **byte-for-byte backup**: set the flag to `NO`, `--scan` → stable ✓, then
  restored the original file bytes (re-scan → beta ✓). **Surge was NOT quit** — the flag
  flip is invisible to the running process (verifier reads the file independently).
  End state == original (`true`).

## Notes
- `IncludeBetaBuilds = true` on this machine → Surge is genuinely on **beta**. Confirmed
  by reading the KDDefaults.plist directly (`plutil -extract IncludeBetaBuilds raw …` → `true`).
- VendorProbe intentionally returns nothing (mechanism is Sparkle feed-swap). The
  harness "VendorProbe → no version" is **expected**.
- Feeds carry no `<sparkle:channel>` tags; the signed `SUFeedURL` is the release feed
  and Surge rewrites it to an internal `surge-data-pipe://…?beta=<0|1>` at runtime.

## Command
```
swift run --package-path application-test channel-verify --scan com.nssurge.surge-mac --expect beta
```
